const std = @import("std");

pub fn log(comptime fmt: []const u8, args: anytype) void {
    _ = std.io.getStdErr().writer().print(fmt, args) catch {};
}

pub fn die(comptime fmt: []const u8, args: anytype) noreturn {
    log(fmt, args);
    std.os.exit(1);
}
