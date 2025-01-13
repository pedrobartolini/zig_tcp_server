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

    try thing_server.init(1234, 1000);

    thing_server.start_accepting();
}
