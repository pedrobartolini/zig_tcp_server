const server = @import("server.zig");
const std = @import("std");

var thing_server: server.Server = undefined;

// pub const default_level: std.log.Level = switch (std.builtin.mode) {
//     .Debug => .debug,
//     .ReleaseSafe => .notice,
//     .ReleaseFast => .err,
//     .ReleaseSmall => .err,
// };

pub fn main() !void {
    try server.wsa_init();
    defer server.wsa_cleanup();

    try thing_server.init(6969, 10000);

    _ = try std.Thread.spawn(.{}, server.Server.start_accepting, .{&thing_server});
    _ = try std.Thread.spawn(.{}, server.poll_clients, .{});

    var count: u64 = 1;

    while (true) {
        const message = server.rx.receive();

        std.log.debug("{}", .{message});
        std.log.debug("received messages = {}", .{count});
        count += 1;

        // std.time.sleep(100 * 1000000);
    }
}
