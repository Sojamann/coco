const std = @import("std");

const concom = @import("conventional_commit.zig");

const testing = std.testing;
const ally = testing.allocator_instance.allocator();

fn expectFail(
    res: concom.ConventionalCommitParseResult,
    expected: concom.ParseErrorCode,
) !void {
    switch (res) {
        .OK => unreachable,
        .FAILED => |err| {
            defer err.deinit(ally);
            try testing.expectEqual(expected, err.code);
        },
    }
}

fn expectOk(
    res: concom.ConventionalCommitParseResult,
    expected: concom.ConventionalCommit,
) !void {
    var actual = switch (res) {
        .FAILED => |err| {
            defer err.deinit(ally);
            unreachable;
        },
        .OK => |x| x,
    };
    defer actual.deinit(ally);

    try testing.expectEqualStrings(expected.type, actual.type);
    if (expected.scope) |expected_scope| {
        try testing.expectEqualStrings(expected_scope, actual.scope.?);
    }
    try testing.expectEqual(expected.is_breaking, actual.is_breaking);
    try testing.expectEqualStrings(expected.description, actual.description);
    if (expected.body) |expected_body| {
        try testing.expectEqualStrings(expected_body, actual.body.?);
    }

    try testing.expectEqual(expected.trailers.count(), actual.trailers.count());
    var expected_trailer_iter = expected.trailers.iterator();
    while (expected_trailer_iter.next()) |expected_entry| {
        try testing.expectEqualStrings(
            expected_entry.value_ptr.*,
            actual.trailers.get(expected_entry.key_ptr.*).?,
        );
    }
}

test "[OK] type: desc" {
    const msg =
        \\type: desc
        \\
    ;

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = null,
        .is_breaking = false,
        .description = @constCast("desc"),
        .body = null,
        .trailers = std.BufMap.init(ally),
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[FAIL] type with space: desc" {
    const msg =
        \\invalid type: desc
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidType);
}

test "[FAIL] type with special characters" {
    const msg =
        \\type$: desc
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidType);
}

test "[FAIL] type not closed" {
    const msg =
        \\type test
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidType);
}

test "[OK]: type(scope): desc" {
    const msg =
        \\type(scope): desc
        \\
    ;

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = @constCast("scope"),
        .is_breaking = false,
        .description = @constCast("desc"),
        .body = null,
        .trailers = std.BufMap.init(ally),
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[OK]: type(some weird - scope  ): desc" {
    const msg =
        \\type(some weird - scope  ): desc
        \\
    ;

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = @constCast("some weird - scope"),
        .is_breaking = false,
        .description = @constCast("desc"),
        .body = null,
        .trailers = std.BufMap.init(ally),
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[FAIL] scope not closed 1/2" {
    const msg =
        \\type(: desc
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidScope);
}

test "[FAIL] scope not closed 2/2" {
    const msg =
        \\type(ajs!: desc
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidScope);
}

test "[FAIL] unknown character after scope" {
    const msg =
        \\type(scope)@: desc
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidHeaderSeperator);
}

test "[FAIL] double breaking indicator !" {
    const msg =
        \\type!(x)!: desc
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidHeaderSeperator);
}

test "[FAIL] unknown character between breaking and colon" {
    const msg =
        \\type!@: desc
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidHeaderSeperator);
}

test "[FAIL] fails when no new line after desc" {
    const msg =
        \\type: desc
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidDescription);
}
test "[OK]: type!: desc" {
    const msg =
        \\type!: desc
        \\
    ;

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = null,
        .is_breaking = true,
        .description = @constCast("desc"),
        .body = null,
        .trailers = std.BufMap.init(ally),
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[OK]: type(scope)!: desc" {
    const msg =
        \\type(scope)!: desc
        \\
    ;

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = @constCast("scope"),
        .is_breaking = true,
        .description = @constCast("desc"),
        .body = null,
        .trailers = std.BufMap.init(ally),
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[OK]: type: desc body" {
    const msg =
        \\type: desc
        \\
        \\body
        \\
    ;

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = null,
        .is_breaking = false,
        .description = @constCast("desc"),
        .body = @constCast("body"),
        .trailers = std.BufMap.init(ally),
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[OK]: type: desc multi-line-body" {
    const msg =
        \\type: desc
        \\
        \\body
        \\body
        \\
    ;

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = null,
        .is_breaking = false,
        .description = @constCast("desc"),
        .body = @constCast("body\nbody"),
        .trailers = std.BufMap.init(ally),
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[OK]: type(scope)!: desc multi-line-body\n" {
    const msg =
        \\type(scope)!: desc
        \\
        \\body
        \\body
        \\
    ;

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = @constCast("scope"),
        .is_breaking = true,
        .description = @constCast("desc"),
        .body = @constCast("body\nbody"),
        .trailers = std.BufMap.init(ally),
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[OK]: type(scope)!: desc multi-paragraph-body\n" {
    const msg =
        \\type(scope)!: desc
        \\
        \\body
        \\body
        \\
        \\body
        \\body
        \\
    ;

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = @constCast("scope"),
        .is_breaking = true,
        .description = @constCast("desc"),
        .body = @constCast("body\nbody\n\nbody\nbody"),
        .trailers = std.BufMap.init(ally),
    };

    try expectOk(try concom.parse(ally, msg), expected);
}
test "[FAIL] fail when body not seperated with empty line from desc" {
    const msg =
        \\type: desc
        \\some body
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidBody);
}
test "[OK]: type: desc trailers-with-colon" {
    const msg =
        \\type: desc
        \\
        \\key: value
        \\
    ;
    var trailers = std.BufMap.init(ally);
    defer trailers.deinit();

    try trailers.put("key", "value");

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = null,
        .is_breaking = false,
        .description = @constCast("desc"),
        .body = null,
        .trailers = trailers,
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[OK]: type: desc trailers-with-hashtag" {
    const msg =
        \\type: desc
        \\
        \\key #value
        \\
    ;
    var trailers = std.BufMap.init(ally);
    defer trailers.deinit();

    try trailers.put("key", "value");

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = null,
        .is_breaking = false,
        .description = @constCast("desc"),
        .body = null,
        .trailers = trailers,
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[OK]: type: desc trailers-with-multiple-keys" {
    const msg =
        \\type: desc
        \\
        \\key1 #value
        \\key2: value
        \\
    ;
    var trailers = std.BufMap.init(ally);
    defer trailers.deinit();

    try trailers.put("key1", "value");
    try trailers.put("key2", "value");

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = null,
        .is_breaking = false,
        .description = @constCast("desc"),
        .body = null,
        .trailers = trailers,
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[OK]: type: desc trailers-same-key-twice" {
    const msg =
        \\type: desc
        \\
        \\key #asdha
        \\key: value
        \\
    ;
    var trailers = std.BufMap.init(ally);
    defer trailers.deinit();

    try trailers.put("key", "value");

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = null,
        .is_breaking = false,
        .description = @constCast("desc"),
        .body = null,
        .trailers = trailers,
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[OK]: type: desc trailers-multi-line-key" {
    const msg =
        \\type: desc
        \\
        \\key: value
        \\ test
        \\
    ;
    var trailers = std.BufMap.init(ally);
    defer trailers.deinit();

    try trailers.put("key", "value test");

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = null,
        .is_breaking = false,
        .description = @constCast("desc"),
        .body = null,
        .trailers = trailers,
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[OK]: type: desc trailer-breaking-change" {
    const msg =
        \\type: desc
        \\
        \\BREAKING CHANGE: value
        \\
    ;
    var trailers = std.BufMap.init(ally);
    defer trailers.deinit();

    try trailers.put("BREAKING CHANGE", "value");

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = null,
        .is_breaking = true,
        .description = @constCast("desc"),
        .body = null,
        .trailers = trailers,
    };

    try expectOk(try concom.parse(ally, msg), expected);
}
test "[OK]: type: desc trailers-multiple-multi-line-keys" {
    const msg =
        \\type: desc
        \\
        \\key1: value
        \\ test
        \\key2: xx
        \\    xx
        \\    xx
        \\
    ;
    var trailers = std.BufMap.init(ally);
    defer trailers.deinit();

    try trailers.put("key1", "value test");
    try trailers.put("key2", "xx xx xx");

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = null,
        .is_breaking = false,
        .description = @constCast("desc"),
        .body = null,
        .trailers = trailers,
    };

    try expectOk(try concom.parse(ally, msg), expected);
}

test "[FAIL] invalid trailer key 1/3" {
    const msg =
        \\type: desc
        \\
        \\some key: key
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidTrailerKey);
}
test "[FAIL] invalid trailer key 2/3" {
    const msg =
        \\type: desc
        \\
        \\some_key: key
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidTrailerKey);
}
test "[FAIL] invalid trailer key 3/3" {
    const msg =
        \\type: desc
        \\
        \\some-key^: key
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidTrailerKey);
}
test "[FAIL] content directly after trailers" {
    const msg =
        \\type: desc
        \\
        \\some: key
        \\s
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidTrailers);
}
test "[FAIL] content after trailers section" {
    const msg =
        \\type: desc
        \\
        \\some: key
        \\
        \\x
        \\
    ;

    try expectFail(try concom.parse(ally, msg), concom.ParseErrorCode.InvalidTrailers);
}
test "[OK]: all" {
    const msg =
        \\type(scope)!: desc
        \\
        \\ body
        \\X
        \\
        \\key: value
        \\ test
        \\
    ;
    var trailers = std.BufMap.init(ally);
    defer trailers.deinit();

    try trailers.put("key", "value test");

    const expected = concom.ConventionalCommit{
        .type = @constCast("type"),
        .scope = @constCast("scope"),
        .is_breaking = true,
        .description = @constCast("desc"),
        .body = @constCast("body\nX"),
        .trailers = trailers,
    };

    try expectOk(try concom.parse(ally, msg), expected);
}
