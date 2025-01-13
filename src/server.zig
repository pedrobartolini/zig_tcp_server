const std = @import("std");
const winsock = std.os.windows.ws2_32;

const SOCKET = winsock.SOCKET;
const INVALID_SOCKET = winsock.INVALID_SOCKET;
const sockaddr = winsock.sockaddr;

const MAX_CLIENTS = 5000;

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

            mutex.lock();
            defer mutex.unlock();

            std.log.err("new client", .{});

            for (clients[0..]) |*_client| {
                if (_client.*.fd == INVALID_SOCKET) {
                    _client.* = client;
                    break;
                }
            }
        }
    }
};

var clients: [MAX_CLIENTS]Client = undefined;
var mutex: std.Thread.Mutex = .{};

pub fn wsa_init() !void {
    var wsaData: winsock.WSADATA = undefined;

    if (winsock.WSAStartup(@as(u16, 2) | (@as(u16, 2) << 8), &wsaData) < 0) {
        return error.WSAStartup;
    }

    mutex.lock();
    defer mutex.unlock();

    for (clients[0..]) |*client| {
        client.* = Client{
            .fd = INVALID_SOCKET,
            .addr_in = undefined,
            .server_port = undefined,
        };
    }
}

pub fn wsa_cleanup() void {
    _ = winsock.WSACleanup();
    return;
}
