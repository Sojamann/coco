const std = @import("std");

const libgit = @cImport({
    @cInclude("git2.h");
});

pub const CommitishNotFound = error.CommitishNotFound;
pub const CouldNotRetrieveTags = error.CouldNotRetrieveTags;
pub const UnexpectedGitError = error.UnexpectedGitError;

// wrapper for liggit.git_commit to sperate c-world from zig-world
// things in this file can work with commit directly..
pub const Commit = struct {
    commit: *libgit.git_commit,

    pub fn deinit(self: *const Commit) void {
        _ = libgit.git_commit_free(self.commit);
    }

    pub fn msg(self: *const Commit) []u8 {
        return std.mem.span(@constCast(libgit.git_commit_message(self.commit)));
    }

    pub fn sha(self: *const Commit) []u8 {
        return std.mem.span(libgit.git_oid_tostr_s(libgit.git_commit_id(self.commit)));
    }
};

pub const TagList = struct {
    list: libgit.git_strarray,

    pub fn deinit(self: *const TagList) void {
        _ = libgit.git_strarray_free(@constCast(&self.list));
    }

    pub fn len(self: *const TagList) usize {
        return self.list.count;
    }

    pub fn get(self: *const TagList, idx: usize) [:0]u8 {
        if (idx >= self.list.count) {
            @panic("Invalid access");
        }
        return std.mem.span(self.list.strings[idx]);
    }
};

pub const Repo = struct {
    repo: *libgit.git_repository,

    pub fn init() !Repo {
        // This reports how many times this has been initialized or an error
        // code .... so if it is not right we have an error or initiaized it
        // one too many times
        if (libgit.git_libgit2_init() != 1) return UnexpectedGitError;

        var buff: libgit.git_buf = .{ .ptr = 0, .reserved = 0, .size = 0 };
        if (libgit.git_repository_discover(&buff, ".", 0, "/") != 0) {
            return error.NoRepositoryFound;
        }

        var repo: ?*libgit.git_repository = undefined;
        if (libgit.git_repository_open(&repo, buff.ptr) != 0) {
            return error.CouldNotReadRepository;
        }
        _ = libgit.git_buf_dispose(&buff);
        return .{ .repo = repo.? };
    }

    pub fn deinit(self: *const Repo) void {
        _ = libgit.git_repository_free(self.repo);
        _ = libgit.git_libgit2_shutdown();
    }

    pub fn getCommit(self: *const Repo, commitish: [:0]const u8) !Commit {
        var git_object: ?*libgit.git_object = undefined;

        if (libgit.git_revparse_single(&git_object, self.repo, @ptrCast(commitish)) != 0) {
            return CommitishNotFound;
        }
        defer {
            _ = libgit.git_object_free(git_object);
        }

        const oid = libgit.git_object_id(git_object);

        var commit: ?*libgit.git_commit = undefined;
        _ = libgit.git_commit_lookup(&commit, self.repo, oid);
        return Commit{ .commit = @ptrCast(commit) };
    }

    // returns all Commits in range '(start, end]' (start exclusive, end inclusive)
    pub fn getCommitsInRange(self: *const Repo, ally: std.mem.Allocator, start: []const u8, end: []const u8) ![]Commit {
        var walker: ?*libgit.git_revwalk = undefined;
        if (libgit.git_revwalk_new(&walker, self.repo) > 0) return UnexpectedGitError;

        var buff: [512]u8 = undefined;
        const range = try std.fmt.bufPrintZ(&buff, "{s}..{s}", .{ start, end });
        if (libgit.git_revwalk_push_range(walker, range) > 0) return UnexpectedGitError;

        var list = std.ArrayList(Commit).init(ally);
        errdefer list.deinit();

        var oid: libgit.git_oid = undefined;
        while (true) {
            switch (libgit.git_revwalk_next(&oid, walker)) {
                0 => {},
                libgit.GIT_ITEROVER => break,
                else => return UnexpectedGitError,
            }

            var commit: ?*libgit.git_commit = undefined;
            if (libgit.git_commit_lookup(&commit, self.repo, &oid) > 0) {
                return UnexpectedGitError;
            }
            list.append(Commit{ .commit = commit.? }) catch @panic("OOM");
        }

        return list.toOwnedSlice();
    }

    pub fn isCommitReachable(self: *const Repo, commit: Commit) !bool {
        const commit_oid = libgit.git_commit_id(commit.commit);

        const head_commit = try self.getCommit("HEAD");
        defer head_commit.deinit();
        const head_commit_oid = libgit.git_commit_id(head_commit.commit);
        const decendants = [_]libgit.git_oid{head_commit_oid.*};

        const reachable = libgit.git_graph_reachable_from_any;
        return switch (reachable(self.repo, commit_oid, @ptrCast(&decendants), 1)) {
            0 => false,
            1 => true,
            else => error.Unexpected,
        };
    }

    pub fn getTags(self: *const Repo) !TagList {
        var tagarr: libgit.git_strarray = undefined;
        if (libgit.git_tag_list(&tagarr, self.repo) != 0) {
            return UnexpectedGitError;
        }
        return TagList{ .list = tagarr };
    }
};
