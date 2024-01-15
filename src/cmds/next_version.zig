const std = @import("std");

const git = @import("../git.zig");
const concom = @import("../conventional_commit.zig");
const util = @import("../util.zig");

const MAX_TAG_LEN = 512;
var TAG_BUFF: [MAX_TAG_LEN]u8 = undefined;

const SemVer = std.SemanticVersion;

// holds the parsed arguments for this command
const Args = struct {
    ignore_invalid_conventional_commits: bool = false,
    from_stdin: bool = false,
};

// parse cli arguments into the Args struct
fn parse_args(
    iter: *std.process.ArgIterator,
) !Args {
    var args = Args{};
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--ignore-invalid-conventional-commits")) {
            args.ignore_invalid_conventional_commits = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "-i")) {
            args.ignore_invalid_conventional_commits = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--from-stdin")) {
            args.from_stdin = true;
            continue;
        }

        util.log("the provided flag '{s}' is not known!\n\n", .{arg});
        return error.BadArg;
    }
    return args;
}

// return all tags... BufSet is used since BufList does not exist.
// The hashing overhead is just not that relevant for this type of cli app.
fn getTags(ally: std.mem.Allocator, repo: git.Repo, from_stdin: bool) !std.BufSet {
    var tags = std.BufSet.init(ally);
    errdefer tags.deinit();

    if (from_stdin) {
        var buff: [1024 * 2]u8 = undefined;
        const reader = std.io.getStdIn().reader();

        while (try reader.readUntilDelimiterOrEof(&buff, '\n')) |line| {
            tags.insert(line) catch @panic("OOM");
        }
        return tags;
    }

    const taglist = try repo.getTags();
    defer taglist.deinit();

    for (0..taglist.len()) |i| {
        tags.insert(taglist.get(i)) catch @panic("OOM");
    }
    return tags;
}

// returns the latest release in a git repository
fn getLatestReachableRelease(repo: *const git.Repo, tags: *const std.BufSet) ![:0]u8 {
    var largest: ?std.SemanticVersion = null;

    var iter = tags.iterator();
    while (iter.next()) |item| {
        const tag: [:0]const u8 = std.fmt.bufPrintZ(&TAG_BUFF, "{s}", .{item.*}) catch {
            util.die("The tag '{s}' is too long", .{item});
        };

        const ver = SemVer.parse(tag) catch {
            util.die("The tag {s} is not a valid semantic version!", .{tag});
        };
        if (ver.pre != null or ver.build != null) continue;

        const commit = try repo.getCommit(tag);
        defer commit.deinit();
        if (!try repo.isCommitReachable(commit)) continue;

        const current = largest orelse SemVer{ .major = 0, .minor = 0, .patch = 0 };
        if (SemVer.order(current, ver) == .lt) {
            largest = ver;
        }
    }

    if (largest == null) {
        util.die("There is no reachable release yet! The first one you need to name yourself!", .{});
    }

    return try std.fmt.bufPrintZ(&TAG_BUFF, "{}", .{largest.?});
}

fn determineNextVersion(
    ally: std.mem.Allocator,
    start: SemVer,
    commits: []git.Commit,
    ignore_invalid_conventional_commits: bool,
) !SemVer {
    var is_major_change = false;
    var is_feature_change = false;
    var is_patch_change = false;

    for (commits) |c| {
        const cc = switch (try concom.parse(ally, c.msg())) {
            .OK => |x| x,
            .FAILED => {
                if (ignore_invalid_conventional_commits) continue;
                util.die(
                    "The message of commit '{s}' does not follow conventional commit guidelines! Either change the message or ignore it with --ignore-invalid-conventional-commits.",
                    .{std.mem.trim(u8, c.sha(), &std.ascii.whitespace)},
                );
            },
        };

        if (cc.is_breaking) {
            is_major_change = true;
            break;
        }
        is_feature_change = is_feature_change or std.mem.eql(u8, cc.type, "feat");
        is_patch_change = is_patch_change or std.mem.eql(u8, cc.type, "fix");
    }

    var result: SemVer = start;
    if (is_major_change and start.major > 0) {
        result.major += 1;
    } else if (is_feature_change or (is_major_change and start.major == 0)) {
        result.minor += 1;
    } else if (is_patch_change) {
        result.patch += 1;
    }
    return result;
}

// TODO: constrict errors.... only allow a certain set of errors to be returned
pub fn cmd_next_version(
    ally: std.mem.Allocator,
    repo: git.Repo,
    iter: *std.process.ArgIterator,
) !void {
    const args = try parse_args(iter);

    const tags = try getTags(ally, repo, args.from_stdin);
    const latest_release = try getLatestReachableRelease(&repo, &tags);

    const commit = try repo.getCommit(latest_release);
    defer commit.deinit();
    if (!try repo.isCommitReachable(commit)) {
        util.die(
            "Seems like the tag '{s}' was made on another branch and is not reachable from HEAD",
            .{latest_release},
        );
    }

    const inbetween = try repo.getCommitsInRange(ally, latest_release, "HEAD");
    defer {
        for (inbetween) |*c| c.deinit();
        ally.free(inbetween);
    }

    const next = try determineNextVersion(
        ally,
        SemVer.parse(latest_release) catch unreachable,
        inbetween,
        args.ignore_invalid_conventional_commits,
    );

    _ = std.io.getStdOut().writer().print("{}\n", .{next}) catch {
        util.die("Failed writing to stdout!\n", .{});
    };
}
