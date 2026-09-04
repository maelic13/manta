//! Bounded text parsing for the currently active UCI shell.
const std = @import("std");

pub const max_input_bytes = 65_536;
pub const max_diagnostic_bytes = 256;

pub const Sanitized = struct {
    len: u16 = 0,
    bytes: [max_diagnostic_bytes]u8 = @splat(0),

    pub fn slice(self: *const Sanitized) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub const Tag = enum {
    uci,
    isready,
    debug_on,
    debug_off,
    quit,
    setoption,
    ucinewgame,
    position,
    go,
    bench,
    stop,
    ponderhit,
    test_fail_hash_allocation,
    test_fail_thread_allocation,
    input_too_long,
    invalid_uci,
    invalid_isready,
    invalid_debug,
    invalid_quit,
    invalid_stop,
    invalid_ponderhit,
    invalid_ucinewgame,
    unavailable,
    unknown,
};

pub const Command = struct {
    tag: Tag,
    line: Sanitized,
    token: Sanitized,
    raw: ?[]u8 = null,
    received_ns: u64 = 0,
    /// Search epoch observed when an urgent line was received. Zero means the
    /// preceding queued `go` had not yet been assigned its controller epoch.
    target_epoch: u64 = 0,
};

pub fn parse(line: []const u8, allow_test_hooks: bool) ?Command {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0) return null;

    var tokens = std.mem.tokenizeAny(u8, trimmed, " \t");
    const first = tokens.next().?;
    const second = tokens.next();
    const has_more = tokens.next() != null;

    const tag: Tag = if (std.mem.eql(u8, first, "uci"))
        if (second == null) .uci else .invalid_uci
    else if (std.mem.eql(u8, first, "isready"))
        if (second == null) .isready else .invalid_isready
    else if (std.mem.eql(u8, first, "debug"))
        if (second == null or has_more)
            .invalid_debug
        else if (std.mem.eql(u8, second.?, "on"))
            .debug_on
        else if (std.mem.eql(u8, second.?, "off"))
            .debug_off
        else
            .invalid_debug
    else if (std.mem.eql(u8, first, "quit"))
        if (second == null) .quit else .invalid_quit
    else if (std.mem.eql(u8, first, "setoption"))
        .setoption
    else if (std.mem.eql(u8, first, "ucinewgame"))
        if (second == null) .ucinewgame else .invalid_ucinewgame
    else if (std.mem.eql(u8, first, "position"))
        .position
    else if (std.mem.eql(u8, first, "go"))
        .go
    else if (std.mem.eql(u8, first, "bench"))
        .bench
    else if (std.mem.eql(u8, first, "stop"))
        if (second == null) .stop else .invalid_stop
    else if (std.mem.eql(u8, first, "ponderhit"))
        if (second == null) .ponderhit else .invalid_ponderhit
    else if (allow_test_hooks and std.mem.eql(u8, first, "__manta_test_fail_hash_allocation"))
        if (second == null) .test_fail_hash_allocation else .unknown
    else if (allow_test_hooks and std.mem.eql(u8, first, "__manta_test_fail_thread_allocation"))
        if (second == null) .test_fail_thread_allocation else .unknown
    else if (isReservedCommand(first))
        .unavailable
    else
        .unknown;

    return .{
        .tag = tag,
        .line = sanitize(trimmed),
        .token = sanitize(first),
    };
}

pub fn oversizedCommand() Command {
    return .{
        .tag = .input_too_long,
        .line = .{},
        .token = .{},
    };
}

fn isReservedCommand(_: []const u8) bool {
    return false;
}

pub fn sanitize(input: []const u8) Sanitized {
    var result: Sanitized = .{};
    var truncated = false;
    var ellipsis_start: u16 = 0;

    for (input) |byte| {
        var escaped: [4]u8 = undefined;
        const rendered: []const u8 = if (byte >= 0x20 and byte <= 0x7e and byte != '\\' and byte != '"')
            escaped[0..1]
        else if (byte == '\\' or byte == '"')
            escaped[0..2]
        else
            escaped[0..4];

        if (rendered.len == 1) {
            escaped[0] = byte;
        } else if (rendered.len == 2) {
            escaped[0] = '\\';
            escaped[1] = byte;
        } else {
            const hex = "0123456789ABCDEF";
            escaped = .{ '\\', 'x', hex[byte >> 4], hex[byte & 0x0f] };
        }

        if (@as(usize, result.len) + rendered.len > max_diagnostic_bytes) {
            truncated = true;
            break;
        }
        @memcpy(result.bytes[result.len..][0..rendered.len], rendered);
        result.len += @intCast(rendered.len);
        if (result.len <= max_diagnostic_bytes - 3) ellipsis_start = result.len;
    }

    if (truncated) {
        @memcpy(result.bytes[ellipsis_start..][0..3], "...");
        result.len = ellipsis_start + 3;
    }
    return result;
}

test "active fixed commands reject extra arguments" {
    try std.testing.expectEqual(Tag.uci, parse("  uci\t", false).?.tag);
    try std.testing.expectEqual(Tag.invalid_uci, parse("uci now", false).?.tag);
    try std.testing.expectEqual(Tag.invalid_isready, parse("isready extra", false).?.tag);
    try std.testing.expectEqual(Tag.invalid_debug, parse("debug on extra", false).?.tag);
    try std.testing.expectEqual(Tag.invalid_quit, parse("quit now", false).?.tag);
    try std.testing.expectEqual(Tag.invalid_stop, parse("stop now", false).?.tag);
    try std.testing.expectEqual(Tag.ponderhit, parse("ponderhit", false).?.tag);
    try std.testing.expectEqual(Tag.invalid_ponderhit, parse("ponderhit now", false).?.tag);
}

test "active and test-only commands are distinct from unknown commands" {
    try std.testing.expectEqual(Tag.go, parse("go depth 1", false).?.tag);
    try std.testing.expectEqual(Tag.bench, parse("bench", false).?.tag);
    try std.testing.expectEqual(Tag.unknown, parse("frobnicate payload", false).?.tag);
    try std.testing.expectEqual(Tag.unknown, parse("__manta_test_fail_hash_allocation", false).?.tag);
    try std.testing.expectEqual(Tag.test_fail_hash_allocation, parse("__manta_test_fail_hash_allocation", true).?.tag);
    try std.testing.expectEqual(Tag.unknown, parse("__manta_test_fail_thread_allocation", false).?.tag);
    try std.testing.expectEqual(Tag.test_fail_thread_allocation, parse("__manta_test_fail_thread_allocation", true).?.tag);
}

test "diagnostics escape hostile bytes and remain bounded" {
    const escaped = sanitize("a\n\\\"b");
    try std.testing.expectEqualStrings("a\\x0A\\\\\\\"b", escaped.slice());

    var long: [300]u8 = @splat('x');
    const bounded = sanitize(&long);
    try std.testing.expectEqual(max_diagnostic_bytes, bounded.slice().len);
    try std.testing.expect(std.mem.endsWith(u8, bounded.slice(), "..."));
}
