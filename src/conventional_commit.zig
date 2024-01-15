const std = @import("std");

pub const ConventionalCommit = struct {
    type: []u8,
    scope: ?[]u8,
    is_breaking: bool,
    description: []u8,
    body: ?[]u8,
    trailers: std.BufMap,

    pub fn deinit(self: *ConventionalCommit, ally: std.mem.Allocator) void {
        ally.free(self.type);
        if (self.scope) |s| {
            ally.free(s);
        }
        ally.free(self.description);
        if (self.body) |s| {
            ally.free(s);
        }
        self.trailers.deinit();
    }
};

// ---------------------------------------------------

pub const ParseErrorCode = error{
    InvalidType,
    InvalidScope,
    InvalidHeaderSeperator,
    InvalidDescription,
    InvalidBody,
    InvalidTrailers,
    InvalidTrailerKey,
};

pub const ParseError = struct {
    code: ParseErrorCode,
    msg: []u8,

    pub fn deinit(self: *const ParseError, ally: std.mem.Allocator) void {
        ally.free(self.msg);
    }
};

pub const ParseResultType = enum {
    OK,
    FAILED,
};

pub const ConventionalCommitParseResult = union(ParseResultType) {
    OK: ConventionalCommit,
    FAILED: ParseError,
};

fn ParseResult(comptime t: type) type {
    return union(ParseResultType) {
        OK: t,
        FAILED: ParseError,
    };
}

fn parseError(
    comptime t: type,
    ally: std.mem.Allocator,
    comptime code: ParseErrorCode,
    comptime fmt: []const u8,
    val: anytype,
) ParseResult(t) {
    return .{ .FAILED = .{
        .code = code,
        .msg = std.fmt.allocPrint(ally, fmt, val) catch @panic("OOM"),
    } };
}

pub fn parse(ally: std.mem.Allocator, msg: []const u8) !ConventionalCommitParseResult {
    var offset: usize = 0;

    const commit_type = switch (try parseType(ally, msg, &offset)) {
        .OK => |x| x,
        .FAILED => |err| return ConventionalCommitParseResult{ .FAILED = err },
    };

    const commit_scope = switch (try parseScope(ally, msg, &offset)) {
        .OK => |x| x,
        .FAILED => |err| return ConventionalCommitParseResult{ .FAILED = err },
    };

    var commit_is_breaking = try parseBreakingChange(msg, &offset);

    if (try consumeHeaderSeperator(ally, msg, &offset)) |err| {
        return ConventionalCommitParseResult{ .FAILED = err };
    }
    const commit_description = switch (try parseDescription(ally, msg, &offset)) {
        .OK => |x| x,
        .FAILED => |err| return ConventionalCommitParseResult{ .FAILED = err },
    };

    switch (try consumeEmptyLine(ally, msg, &offset)) {
        .OK => {},
        .FAILED => |err| return ConventionalCommitParseResult{ .FAILED = err },
    }

    const commit_body = parseBody(msg, &offset);

    if (commit_body) |_| {
        switch (try consumeEmptyLine(ally, msg, &offset)) {
            .OK => {},
            .FAILED => |err| return ConventionalCommitParseResult{ .FAILED = err },
        }
    }

    var commit_trailers = switch (try parseTrailers(ally, msg, &offset)) {
        .OK => |x| x,
        .FAILED => |err| return ConventionalCommitParseResult{ .FAILED = err },
    };
    errdefer commit_trailers.deinit();

    // check trailers
    var iter = commit_trailers.iterator();
    while (iter.next()) |x| {
        if (std.mem.eql(u8, x.key_ptr.*, "BREAKING CHANGE")) {
            commit_is_breaking = true;
            continue;
        }
        for (x.key_ptr.*) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '-') {
                continue;
            }
            const errmsg = std.fmt.allocPrint(
                ally,
                "Invalid key: {s} ... allowed are [a-zA-Z0-9-]",
                .{x.key_ptr.*},
            ) catch @panic("OOM");
            commit_trailers.deinit();
            return ConventionalCommitParseResult{ .FAILED = .{
                .code = ParseErrorCode.InvalidTrailerKey,
                .msg = errmsg,
            } };
        }
    }

    // NOTE: this has potential to leak mem if alloc fails of a later element
    // but this is kinda not what we should worry about.
    return .{ .OK = .{
        .type = ally.dupe(u8, commit_type) catch @panic("OOM"),
        .scope = if (commit_scope) |s| (ally.dupe(u8, s) catch @panic("OOM")) else null,
        .is_breaking = commit_is_breaking,
        .description = ally.dupe(u8, commit_description) catch @panic("OOM"),
        .body = if (commit_body) |s| (ally.dupe(u8, s) catch @panic("OOM")) else null,
        .trailers = commit_trailers,
    } };
}

fn parseType(ally: std.mem.Allocator, s: []const u8, start: *usize) !ParseResult([]const u8) {
    const end_pos = std.mem.indexOfAnyPos(u8, s, start.*, "!(:") orelse {
        return parseError(
            []const u8,
            ally,
            ParseErrorCode.InvalidType,
            "expected conventional-commit to contain commit type ... did not find !, ( or :",
            .{},
        );
    };
    const res = trim(s[start.*..end_pos]);
    for (res) |c| {
        if (!std.ascii.isAlphanumeric(c)) {
            return parseError(
                []const u8,
                ally,
                ParseErrorCode.InvalidType,
                "the commit type must be a noun. Found character '{c}'",
                .{c},
            );
        }
    }

    start.* = end_pos;
    return .{ .OK = res };
}

fn parseScope(ally: std.mem.Allocator, s: []const u8, start: *usize) !ParseResult(?[]const u8) {
    if (start.* >= s.len or s[start.*] == ':' or s[start.*] == '!') {
        return .{ .OK = null };
    }

    if (s[start.*] != '(') {
        return parseError(
            ?[]const u8,
            ally,
            ParseErrorCode.InvalidScope,
            "expected scope or ': '",
            .{},
        );
    }

    start.* += 1; // advancing over (

    const end_pos = std.mem.indexOfScalarPos(u8, s, start.*, ')') orelse {
        return parseError(
            ?[]const u8,
            ally,
            ParseErrorCode.InvalidScope,
            "expected scope to be closed again ... missing ')'",
            .{},
        );
    };

    const res = .{ .OK = trim(s[start.*..end_pos]) };
    start.* = end_pos + 1;
    return res;
}

fn parseBreakingChange(s: []const u8, start: *usize) !bool {
    if (start.* < s.len and s[start.*] == '!') {
        start.* += 1; // consume the !
        return true;
    }
    return false;
}

fn consumeHeaderSeperator(ally: std.mem.Allocator, s: []const u8, start: *usize) !?ParseError {
    if (start.* < s.len and std.mem.startsWith(u8, s[start.*..], ": ")) {
        start.* += 2;
        return null;
    }

    return .{ .code = ParseErrorCode.InvalidHeaderSeperator, .msg = std.fmt.allocPrint(
        ally,
        "expected conventiona-commit's start type(scope)[!] to be followd by a colon and a whitespace",
        .{},
    ) catch @panic("OOM") };
}

// consumes ONE empty line given that some text follows it
fn consumeEmptyLine(ally: std.mem.Allocator, s: []const u8, start: *usize) !ParseResult(bool) {
    if (start.* >= s.len) {
        return .{ .OK = false };
    }

    const pos = std.mem.indexOfScalarPos(u8, s, start.*, '\n') orelse 0;
    if (trim(s[start.*..pos]).len > 0) {
        return parseError(
            bool,
            ally,
            ParseErrorCode.InvalidBody,
            "expected body to be seperated from the description by one empty line",
            .{},
        );
    }

    for (s[pos..]) |c| {
        if (std.ascii.isWhitespace(c)) {
            continue;
        }
        start.* = pos + 1;
        return .{ .OK = true };
    }

    start.* = pos + 1;
    return .{ .OK = false };
}

fn parseDescription(ally: std.mem.Allocator, s: []const u8, start: *usize) !ParseResult([]const u8) {
    if (start.* >= s.len) {
        return parseError(
            []const u8,
            ally,
            ParseErrorCode.InvalidDescription,
            "expected conventiona-commit to have description after ': '",
            .{},
        );
    }

    const end = std.mem.indexOfScalarPos(u8, s, start.*, '\n') orelse {
        // This should actually never happen as git will but a new line
        // at the end but just in case!
        return parseError(
            []const u8,
            ally,
            ParseErrorCode.InvalidDescription,
            "expected commit to have a new-line after the descriptio",
            .{},
        );
    };

    const desc = trim(s[start.*..end]);
    if (desc.len == 0) {
        return parseError(
            []const u8,
            ally,
            ParseErrorCode.InvalidDescription,
            "expected conventiona-commit to have description after ': '",
            .{},
        );
    }

    start.* = end + 1;
    return .{ .OK = desc };
}

fn parseBody(s: []const u8, start: *usize) ?[]const u8 {
    if (start.* > s.len) {
        return null;
    }

    var offset = start.*;
    var lastContent = start.*;
    var iter = std.mem.splitScalar(u8, s[start.*..], '\n');
    while (iter.next()) |line| {
        // looking for the shape of a trailer
        const pos_sep = std.mem.indexOf(u8, line, ": ") orelse std.mem.indexOf(u8, line, " #") orelse 0;
        if (pos_sep == 0) {
            offset += line.len + 1;
            if (trim(line).len > 0) {
                lastContent += line.len + 1;
            }
            continue;
        }

        const body = trim(s[start.*..lastContent]);
        start.* = lastContent;
        return if (body.len > 0) body else null;
    }

    const body = trim(s[start.*..@min(s.len, lastContent)]);
    start.* = lastContent;
    return if (body.len > 0) body else null;
}

fn parseTrailers(ally: std.mem.Allocator, s: []const u8, start: *usize) !ParseResult(std.BufMap) {
    var map = std.BufMap.init(ally);
    errdefer map.deinit();

    if (start.* >= s.len) {
        return .{ .OK = map };
    }
    var key: [1024 * 1]u8 = undefined;
    var keylen: usize = 0;
    var value: [1024 * 4]u8 = undefined;
    var valuelen: usize = 0;

    var iter = std.mem.tokenizeScalar(u8, s[start.*..], '\n');
    while (iter.next()) |line| {
        const pos_sep = std.mem.indexOf(u8, line, ": ") orelse std.mem.indexOf(u8, line, " #") orelse 0;
        // a new trailer is on this line
        if (pos_sep > 0) {
            if (keylen > 0) {
                try map.put(trim(key[0..keylen]), trim(value[0..valuelen]));
            }
            std.mem.copyForwards(u8, &key, line[0..pos_sep]);
            keylen = pos_sep;
            std.mem.copyForwards(u8, &value, std.mem.trim(u8, line[pos_sep + 2 ..], " \t"));
            valuelen = line.len - (pos_sep + 2);
            continue;
        }

        // the continuation of a folded string (multi line string)
        if (std.mem.startsWith(u8, line, " ") and keylen > 0) {
            const content = std.mem.trim(u8, line, " \t");
            value[valuelen] = ' ';
            std.mem.copyForwards(u8, value[valuelen + 1 ..], content);
            valuelen += 1 + content.len;
            continue;
        }

        map.deinit();
        return parseError(
            std.BufMap,
            ally,
            ParseErrorCode.InvalidTrailers,
            "line: '{s}' in the trailer section is invalid",
            .{line},
        );
    }

    if (keylen > 0) {
        try map.put(trim(key[0..keylen]), trim(value[0..valuelen]));
    }
    return .{ .OK = map };
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, &std.ascii.whitespace);
}
