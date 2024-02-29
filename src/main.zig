const std = @import("std");

const git = @import("git.zig");
const concom = @import("conventional_commit.zig");
const util = @import("util.zig");

const cmds = struct {
    usingnamespace @import("./cmds/validate.zig");
    usingnamespace @import("./cmds/next_version.zig");
};

fn usage(ally: std.mem.Allocator) noreturn {
    const txt =
        \\Usage: {s} cmd [args]
        \\
        \\cmds:
        \\  validate        validates the specified commit
        \\  next-version    prints the name of the next release
        \\
        \\validate [--ref commitish] [--file /path/to/msg]
        \\
        \\  Validates the over file, a git reference or stdin specified commit 
        \\  message.
        \\
        \\  --file </path/to/message>
        \\      read the message from the specified file
        \\
        \\  --ref <commitish>
        \\      read the message by looking up the git reference
        \\
        \\  "no arguments"
        \\      read the message from stdin
        \\
        \\next-version [-i|--ignore-invalid-conventional-commits]
        \\  
        \\  Prints what the next semantic version, given the since made
        \\  commits, will be.
        \\
        \\  -i, --ignore-invalid-conventional-commits 
        \\      ignore commits that don't conform the conventional commit
        \\      standards
    ;
    const prog_name = std.fs.selfExePathAlloc(ally) catch @panic("OOM");
    defer ally.free(prog_name);
    util.die(txt, .{prog_name});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const ally = arena.allocator();

    var iter = std.process.args();
    _ = iter.next().?;
    const cmd = iter.next() orelse "";
    if (std.mem.eql(u8, cmd, "validate")) {
        const repo = git.Repo.init() catch util.die("Failed initializing\n", .{});
        defer repo.deinit();

        cmds.cmd_validate(ally, repo, &iter) catch |err| {
            if (err == error.BadArg) usage(ally);
            util.die("Unexpected error: {}\n", .{err});
        };
    } else if (std.mem.eql(u8, cmd, "next-version")) {
        const repo = git.Repo.init() catch util.die("Failed initializing\n", .{});
        defer repo.deinit();

        cmds.cmd_next_version(ally, repo, &iter) catch |err| {
            if (err == error.BadArg) usage(ally);
            util.die("Unexpected error: {}\n", .{err});
        };
    } else {
        usage(ally);
    }
}
