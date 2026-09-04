//! Parser and validator for the staged UCI transcript notation.
const std = @import("std");

pub const Exit = struct {
    code: u8,
    within_ms: u32,
};

pub const Step = union(enum) {
    send: []const u8,
    expect: []const u8,
    silence_ms: u32,
    send_oversized_line,
    close_stdin,
    block_stdout,
    unblock_stdout,
    allow_info_begin,
    allow_info_end,
    fail_next: []const u8,
    exit: Exit,
};

pub const Case = struct {
    phase: []const u8,
    steps: []Step,
};

pub const Document = struct {
    cases: []Case,

    pub fn deinit(document: *Document, allocator: std.mem.Allocator) void {
        for (document.cases) |case| allocator.free(case.steps);
        allocator.free(document.cases);
        document.* = undefined;
    }
};

pub const ParseError = error{
    InvalidPhase,
    InvalidDirective,
    InvalidDuration,
    InvalidExit,
    InvalidPlaceholder,
    MissingPhase,
    EmptyCase,
    UnbalancedInfoRegion,
};

pub fn parse(allocator: std.mem.Allocator, content: []const u8) (ParseError || std.mem.Allocator.Error)!Document {
    var cases: std.ArrayList(Case) = .empty;
    errdefer {
        for (cases.items) |case| allocator.free(case.steps);
        cases.deinit(allocator);
    }
    var steps: std.ArrayList(Step) = .empty;
    defer steps.deinit(allocator);
    var phase: ?[]const u8 = null;
    var info_depth: u1 = 0;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (std.mem.eql(u8, line, "---")) {
            try finishCase(allocator, &cases, &steps, &phase, info_depth);
            info_depth = 0;
            continue;
        }
        if (std.mem.startsWith(u8, line, "@phase ")) {
            if (phase != null or steps.items.len != 0) return error.InvalidPhase;
            const value = line[7..];
            if (!validPhase(value)) return error.InvalidPhase;
            phase = value;
            continue;
        }
        if (phase == null) return error.MissingPhase;

        const step: Step = if (std.mem.startsWith(u8, line, "< "))
            .{ .send = line[2..] }
        else if (std.mem.startsWith(u8, line, "> ")) blk: {
            try validatePlaceholders(line[2..]);
            break :blk .{ .expect = line[2..] };
        } else if (std.mem.startsWith(u8, line, "! ")) blk: {
            const directive = line[2..];
            if (std.mem.startsWith(u8, directive, "silence ")) {
                break :blk .{ .silence_ms = try parseDuration(directive[8..]) };
            }
            if (std.mem.eql(u8, directive, "send-oversized-line")) break :blk .send_oversized_line;
            if (std.mem.eql(u8, directive, "close-stdin")) break :blk .close_stdin;
            if (std.mem.eql(u8, directive, "block-stdout")) break :blk .block_stdout;
            if (std.mem.eql(u8, directive, "unblock-stdout")) break :blk .unblock_stdout;
            if (std.mem.eql(u8, directive, "allow-info begin")) {
                if (info_depth != 0) return error.UnbalancedInfoRegion;
                info_depth = 1;
                break :blk .allow_info_begin;
            }
            if (std.mem.eql(u8, directive, "allow-info end")) {
                if (info_depth == 0) return error.UnbalancedInfoRegion;
                info_depth = 0;
                break :blk .allow_info_end;
            }
            if (std.mem.startsWith(u8, directive, "fail-next ")) {
                const resource = directive[10..];
                if (!std.mem.eql(u8, resource, "hash-allocation") and
                    !std.mem.eql(u8, resource, "thread-allocation")) return error.InvalidDirective;
                break :blk .{ .fail_next = resource };
            }
            if (std.mem.startsWith(u8, directive, "exit ")) {
                break :blk .{ .exit = try parseExit(directive[5..]) };
            }
            return error.InvalidDirective;
        } else return error.InvalidDirective;

        try steps.append(allocator, step);
    }

    if (phase != null or steps.items.len != 0) {
        try finishCase(allocator, &cases, &steps, &phase, info_depth);
    }
    if (cases.items.len == 0) return error.EmptyCase;
    return .{ .cases = try cases.toOwnedSlice(allocator) };
}

fn finishCase(
    allocator: std.mem.Allocator,
    cases: *std.ArrayList(Case),
    steps: *std.ArrayList(Step),
    phase: *?[]const u8,
    info_depth: u1,
) !void {
    if (phase.* == null) return error.MissingPhase;
    if (steps.items.len == 0) return error.EmptyCase;
    if (info_depth != 0) return error.UnbalancedInfoRegion;
    try cases.append(allocator, .{
        .phase = phase.*.?,
        .steps = try steps.toOwnedSlice(allocator),
    });
    phase.* = null;
}

fn validPhase(value: []const u8) bool {
    var parts = std.mem.splitScalar(u8, value, '.');
    var count: usize = 0;
    while (parts.next()) |part| {
        if (part.len == 0) return false;
        for (part) |byte| if (!std.ascii.isDigit(byte)) return false;
        count += 1;
    }
    return count == 2;
}

fn parseDuration(value: []const u8) ParseError!u32 {
    if (!std.mem.endsWith(u8, value, "ms")) return error.InvalidDuration;
    const digits = value[0 .. value.len - 2];
    if (digits.len == 0) return error.InvalidDuration;
    const duration = std.fmt.parseInt(u32, digits, 10) catch return error.InvalidDuration;
    if (duration == 0) return error.InvalidDuration;
    return duration;
}

fn parseExit(value: []const u8) ParseError!Exit {
    var parts = std.mem.tokenizeScalar(u8, value, ' ');
    const code_text = parts.next() orelse return error.InvalidExit;
    if (!std.mem.eql(u8, parts.next() orelse return error.InvalidExit, "within")) return error.InvalidExit;
    const duration_text = parts.next() orelse return error.InvalidExit;
    if (parts.next() != null) return error.InvalidExit;
    return .{
        .code = std.fmt.parseInt(u8, code_text, 10) catch return error.InvalidExit,
        .within_ms = try parseDuration(duration_text),
    };
}

fn validatePlaceholders(line: []const u8) ParseError!void {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, line, cursor, "{{")) |start| {
        const end = std.mem.indexOfPos(u8, line, start + 2, "}}") orelse return error.InvalidPlaceholder;
        const placeholder = line[start .. end + 2];
        const allowed = [_][]const u8{
            "{{VERSION}}",
            "{{OPTION_DECLARATIONS}}",
            "{{U64}}",
            "{{POSITIVE_U64}}",
            "{{DECIMAL}}",
            "{{BENCH_POSITION_LINES}}",
            "{{ROOT_MOVE_INFO}}",
            "{{ITERATION_INFO}}",
            "{{SEARCH_INFO}}",
            "{{BESTMOVE_LINE}}",
            "{{PONDER}}",
        };
        var known = false;
        for (allowed) |candidate| {
            if (std.mem.eql(u8, placeholder, candidate)) known = true;
        }
        if (!known) return error.InvalidPlaceholder;
        cursor = end + 2;
    }
    if (std.mem.indexOfPos(u8, line, cursor, "}}") != null) return error.InvalidPlaceholder;
}

test "parses a bounded active transcript case" {
    const source =
        \\# comment
        \\@phase 1.2
        \\> Manta {{VERSION}}
        \\< isready
        \\> readyok
        \\! silence 50ms
        \\! exit 0 within 1000ms
    ;
    var document = try parse(std.testing.allocator, source);
    defer document.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), document.cases.len);
    try std.testing.expectEqualStrings("1.2", document.cases[0].phase);
    try std.testing.expectEqual(@as(usize, 5), document.cases[0].steps.len);
}

test "rejects unknown directives and placeholders" {
    try std.testing.expectError(error.InvalidDirective, parse(
        std.testing.allocator,
        "@phase 1.2\n! maybe\n",
    ));
    try std.testing.expectError(error.InvalidPlaceholder, parse(
        std.testing.allocator,
        "@phase 1.2\n> {{ANYTHING}}\n",
    ));
}
