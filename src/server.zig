const std = @import("std");
const channel = @import("channel.zig");

const winsock = std.os.windows.ws2_32;

const SOCKET = winsock.SOCKET;
const INVALID_SOCKET = winsock.INVALID_SOCKET;
const sockaddr = winsock.sockaddr;

const MAX_CLIENTS = 10000;

const Clients = struct {
    list: [MAX_CLIENTS]Client = .{.{ .fd = INVALID_SOCKET, .addr_in = undefined, .server_port = 0 }} ** MAX_CLIENTS,
    mutex: std.Thread.Mutex = .{},

    pub fn find_client_by_fd(self: *Clients, fd: SOCKET) *Client {
        for (self.list) |client| {
            if (client.fd == fd) {
                return @constCast(&client);
            }
        }

        std.debug.panic("client not found", .{});
    }
};

var clients: Clients = .{};

const Client = struct {
    fd: SOCKET,
    addr_in: sockaddr.in,
    server_port: u16,
};

pub const Server = struct {
    fd: SOCKET,
    addr_in: sockaddr.in,
    port: u16,

    pub fn init(self: *Server, port: u16, backlog: u32) !void {
        self.port = port;

        self.fd = winsock.socket(winsock.AF.INET, winsock.SOCK.STREAM, winsock.IPPROTO.TCP);
        if (self.fd == INVALID_SOCKET) {
            return error.SocketCreation;
        }

        self.addr_in.family = winsock.AF.INET;
        self.addr_in.port = winsock.htons(port);
        self.addr_in.addr = 0x00000000;

        if (winsock.bind(self.fd, @ptrCast(&self.addr_in), @sizeOf(sockaddr.in)) < 0) {
            _ = winsock.closesocket(self.fd);
            return error.SocketBinding;
        }

        if (winsock.listen(self.fd, @intCast(backlog)) < 0) {
            _ = winsock.closesocket(self.fd);
            return error.SocketListening;
        }
    }

    pub fn start_accepting(self: *Server) void {
        while (true) {
            var client: Client = undefined;
            var size: i32 = @intCast(@sizeOf(sockaddr.in));
            client.fd = winsock.accept(self.fd, @constCast(@ptrCast(&client.addr_in)), &size);
            if (client.fd == INVALID_SOCKET) {
                continue;
            }

            client.server_port = self.port;

            clients.mutex.lock();
            defer clients.mutex.unlock();

            for (clients.list[0..]) |*_client| {
                if (_client.fd == INVALID_SOCKET) {
                    _client.* = client;

                    tx.send(ServerMessage{
                        .client = _client.*,
                        .event = .Connected,
                    });
                    break;
                }
            }
        }
    }
};

pub fn wsa_init() !void {
    var wsaData: winsock.WSADATA = undefined;
    if (winsock.WSAStartup(@as(u16, 2) | (@as(u16, 2) << 8), &wsaData) < 0) {
        return error.WSAStartup;
    }
}

pub fn wsa_cleanup() void {
    _ = winsock.WSACleanup();
    return;
}

pub fn poll_clients() void {
    var count: u64 = 0;

    while (true) {
        var pollfds: [MAX_CLIENTS]winsock.WSAPOLLFD = undefined;
        var nfds: u32 = 0;

        {
            clients.mutex.lock();
            defer clients.mutex.unlock();

            for (clients.list[0..]) |*client| {
                if (client.fd != INVALID_SOCKET) {
                    pollfds[nfds].fd = client.fd;
                    pollfds[nfds].events = winsock.POLL.RDNORM;
                    nfds += 1;
                }
            }
        }

        if (winsock.WSAPoll(&pollfds, nfds, 100) < 0) {
            std.time.sleep(100 * 1000000);
            continue;
        }

        for (pollfds[0..nfds]) |*pollfd| {
            if (pollfd.revents == 0) {
                continue;
            }

            var cleanup = false;

            if ((pollfd.revents & winsock.POLL.RDNORM) != 0) {
                const MAX_LENGTH = 1024;

                var buffer: [MAX_LENGTH]u8 = undefined;

                const n = winsock.recv(pollfd.fd, &buffer, MAX_LENGTH, 0);
                if (n <= 0) {
                    cleanup = true;
                } else {
                    tx.send(ServerMessage{ .client = clients.find_client_by_fd(pollfd.fd).*, .event = .{ .Read = .{ .buffer = buffer, .n = @intCast(n) } } });
                    count += 1;
                    std.log.err("sent messages = {}", .{count});
                }
            } else {
                cleanup = true;
            }

            if (cleanup) {
                clients.mutex.lock();
                defer clients.mutex.unlock();

                const client = clients.find_client_by_fd(pollfd.fd);
                _ = winsock.closesocket(client.fd);
                client.fd = INVALID_SOCKET;
                tx.send(ServerMessage{ .client = client.*, .event = .Disconnected });
            }
        }
    }
}

pub const ServerMessage = struct {
    client: Client,

    event: union(enum) {
        Connected,
        Disconnected,
        Read: struct {
            buffer: [1024]u8,
            n: usize,
        },
    },

    pub fn format(self: ServerMessage, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        _ = try writer.writeAll("ServerMessage { ");

        const byte1 = (self.client.addr_in.addr >> 24) & 0xFF;
        const byte2 = (self.client.addr_in.addr >> 16) & 0xFF;
        const byte3 = (self.client.addr_in.addr >> 8) & 0xFF;
        const byte4 = self.client.addr_in.addr & 0xFF;
        _ = try writer.print("addr: {d}.{d}.{d}.{d}", .{ byte4, byte3, byte2, byte1 });

        _ = try writer.print(", port: {d}", .{self.client.addr_in.port});

        _ = try writer.print(", server_port: {d}", .{self.client.server_port});

        switch (self.event) {
            .Connected => {
                _ = try writer.print(", event: Connected", .{});
            },
            .Disconnected => {
                _ = try writer.print(", event: Disconnected", .{});
            },
            .Read => |read_event| {
                _ = try writer.print(", event: Read, data: \"{s}\"", .{read_event.buffer[0..read_event.n]});
            },
        }

        _ = try writer.writeAll(" }");
    }
};

var chann = channel.Channel(ServerMessage, 1024).init();
var tx = chann.tx();
pub var rx = chann.rx();
