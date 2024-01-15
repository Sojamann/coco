const std = @import("std");

const git = @import("../git.zig");
const concom = @import("../conventional_commit.zig");
const util = @import("../util.zig");

const Source = union(enum) {
    gitref: [:0]const u8,
    stdin: void,
    file: []const u8,
};

const Args = struct {
    source: Source,
};

fn parseArgs(
    iter: *std.process.ArgIterator,
) !Args {
    var source: Source = .{ .stdin = {} };

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--file")) {
            const path = iter.next() orelse {
                util.log("expected a path to be provided to --file!\n\n", .{});
                return error.BadArg;
            };
            source = .{ .file = path };
            continue;
        }
        if (std.mem.eql(u8, arg, "--ref")) {
            const ref = iter.next() orelse {
                util.log("expected a ref to be provided to --ref!\n\n", .{});
                return error.BadArg;
            };
            source = .{ .gitref = ref };
            continue;
        }

        util.log("the provided flag '{s}' is not known!\n\n", .{arg});
        return error.BadArg;
    }
    return Args{
        .source = source,
    };
}

// reads from source returning the message ...caller owns the allocated message
fn getMessage(
    ally: std.mem.Allocator,
    repo: git.Repo,
    source: Source,
) ![]const u8 {
    switch (source) {
        .gitref => |ref| {
            const commit = repo.getCommit(ref) catch {
                util.die(
                    "Could not find commit for reference '{s}', does it exist?\n",
                    .{ref},
                );
            };
            defer commit.deinit();
            return ally.dupe(u8, commit.msg()) catch @panic("OOM");
        },
        .stdin => {
            return try std.io.getStdIn().readToEndAlloc(ally, 1024 * 8);
        },
        .file => |path| {
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();

            var buf_reader = std.io.bufferedReader(file.reader());
            return try buf_reader.reader().readAllAlloc(ally, 1024 * 8);
        },
    }
}

pub fn cmd_validate(
    ally: std.mem.Allocator,
    repo: git.Repo,
    iter: *std.process.ArgIterator,
) !void {
    const args = try parseArgs(iter);

    const msg = try getMessage(ally, repo, args.source);
    defer ally.free(msg);

    switch (try concom.parse(ally, msg)) {
        .OK => |*conventional_commit| {
            defer @constCast(conventional_commit).deinit(ally);
        },
        .FAILED => |err| {
            defer err.deinit(ally);
            util.die("Failed due to: {s}\n", .{err.msg});
        },
    }
}
