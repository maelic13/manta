//! Process-level runner for active UCI transcripts.
const std = @import("std");
const build_options = @import("build_options");
const transcript = @import("uci/transcript.zig");

const corpus = [_][]const u8{
    "tests/uci/01-startup-handshake.transcript",
    "tests/uci/02-unknown-debug.transcript",
    "tests/uci/03-readiness-barriers.transcript",
    "tests/uci/04-options.transcript",
    "tests/uci/05-position-transaction.transcript",
    "tests/uci/06-search-lifecycle.transcript",
    "tests/uci/07-ponder-lifecycle.transcript",
    "tests/uci/08-perft.transcript",
    "tests/uci/09-terminal-position.transcript",
    "tests/uci/10-shutdown.transcript",
    "tests/uci/11-bench.transcript",
    "tests/uci/12-output-backpressure.transcript",
    "tests/uci/13-smp.transcript",
    "tests/uci/14-time-management.transcript",
};

const active_phase = "6.3";
// Upper bound on how long the harness waits for one expected line. Engine latency
// contracts are expressed by `! silence D` and `! exit CODE within D`, so a tight
// value here asserts nothing and only makes shared CI runners flaky.
const default_wait_ms = 15_000;
const max_file_bytes = 1024 * 1024;
const max_process_line_bytes = 4096;
const output_queue_capacity = 128;
const diagnostic_queue_capacity = 16;

const TestError = error{
    InvalidArguments,
    OutputTimeout,
    UnexpectedOutput,
    UnexpectedEndOfOutput,
    UnexpectedExit,
    WrongExitCode,
    OutputLineTooLong,
    ChildDiagnostic,
    UnsupportedActiveDirective,
};

const StreamLine = struct {
    kind: enum { line, too_long, read_failed },
    len: u16 = 0,
    bytes: [max_process_line_bytes]u8 = undefined,

    fn slice(line: *const StreamLine) []const u8 {
        return line.bytes[0..line.len];
    }
};

const Loaded = struct {
    content: []u8,
    document: transcript.Document,
};

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.debug.print("usage: manta-uci-tests <engine>\n", .{});
        return 2;
    }

    var root = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    defer root.close(io);

    var loaded: [corpus.len]?Loaded = @splat(null);
    defer for (&loaded) |*maybe_loaded| {
        if (maybe_loaded.*) |*item| {
            item.document.deinit(allocator);
            allocator.free(item.content);
        }
    };

    for (corpus, 0..) |path, index| {
        const content = root.readFileAlloc(io, path, allocator, .limited(max_file_bytes)) catch |err| {
            std.debug.print("uci transcript: cannot read {s}: {s}\n", .{ path, @errorName(err) });
            return 1;
        };
        const document = transcript.parse(allocator, content) catch |err| {
            std.debug.print("uci transcript: invalid {s}: {s}\n", .{ path, @errorName(err) });
            allocator.free(content);
            return 1;
        };
        loaded[index] = .{ .content = content, .document = document };
    }

    var executed: usize = 0;
    for (corpus, &loaded) |path, *maybe_loaded| {
        const item = &maybe_loaded.*.?;
        for (item.document.cases, 0..) |case, case_index| {
            if (!phaseAtMost(case.phase, active_phase)) continue;
            runCase(allocator, io, args[1], case) catch |err| {
                std.debug.print(
                    "uci transcript: {s} case {d} failed: {s}\n",
                    .{ path, case_index + 1, @errorName(err) },
                );
                return 1;
            };
            executed += 1;
        }
    }

    if (executed == 0) {
        std.debug.print("uci transcript: no active Phase {s} cases\n", .{active_phase});
        return 1;
    }
    std.debug.print("uci transcript: PASS ({d} Phase {s} cases)\n", .{ executed, active_phase });
    return 0;
}

fn runCase(
    allocator: std.mem.Allocator,
    io: std.Io,
    engine_path: []const u8,
    case: transcript.Case,
) !void {
    _ = allocator;
    var child = try std.process.spawn(io, .{
        .argv = &.{engine_path},
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
        .create_no_window = true,
    });
    defer child.kill(io);

    var output_storage: [output_queue_capacity]StreamLine = undefined;
    var diagnostic_storage: [diagnostic_queue_capacity]StreamLine = undefined;
    var output = std.Io.Queue(StreamLine).init(&output_storage);
    var diagnostics = std.Io.Queue(StreamLine).init(&diagnostic_storage);

    var output_future = try io.concurrent(streamPump, .{ io, child.stdout.?, &output });
    var diagnostic_future = try io.concurrent(streamPump, .{ io, child.stderr.?, &diagnostics });
    var output_finished = false;
    var diagnostic_finished = false;
    defer {
        if (!output_finished) _ = output_future.cancel(io) catch {};
    }
    defer {
        if (!diagnostic_finished) _ = diagnostic_future.cancel(io) catch {};
    }

    var stdin_buffer: [4096]u8 = undefined;
    var stdin_writer = child.stdin.?.writer(io, &stdin_buffer);
    var stdin_open = true;
    var stdout_blocked = false;
    var allow_info = false;
    var saw_exit = false;

    for (case.steps) |step| switch (step) {
        .send => |command| {
            if (!stdin_open) return error.UnsupportedActiveDirective;
            try stdin_writer.interface.print("{s}\n", .{command});
            try stdin_writer.interface.flush();
        },
        .expect => |expected| {
            if (stdout_blocked) return error.UnsupportedActiveDirective;
            if (std.mem.eql(u8, expected, "{{OPTION_DECLARATIONS}}")) {
                const declarations = [_][]const u8{
                    "option name Threads type spin default 1 min 1 max 1024",
                    "option name Hash type spin default 64 min 1 max 1048576",
                    "option name Clear Hash type button",
                    "option name Ponder type check default false",
                    "option name Move Overhead type spin default 10 min 0 max 5000",
                    "option name SyzygyPath type string default <empty>",
                    "option name SyzygyProbeDepth type spin default 1 min 1 max 100",
                    "option name SyzygyProbeLimit type spin default 7 min 0 max 7",
                    "option name Syzygy50MoveRule type check default true",
                };
                for (declarations) |declaration| {
                    const actual = try awaitLine(io, &output, default_wait_ms);
                    if (!std.mem.eql(u8, declaration, actual.slice())) return error.UnexpectedOutput;
                }
                continue;
            }
            if (std.mem.eql(u8, expected, "{{BENCH_POSITION_LINES}}")) {
                for (1..41) |position_index| {
                    const actual = try awaitLine(io, &output, default_wait_ms * 5);
                    var expected_buffer: [256]u8 = undefined;
                    const rendered = std.fmt.bufPrint(
                        &expected_buffer,
                        "info string bench position {d}/40 nodes {{{{U64}}}} time_ms {{{{U64}}}} nps {{{{U64}}}} ebf {{{{DECIMAL}}}}",
                        .{position_index},
                    ) catch return error.UnexpectedOutput;
                    if (!matchesExpected(rendered, actual.slice())) {
                        std.debug.print("expected: {s}\nactual:   {s}\n", .{ rendered, actual.slice() });
                        return error.UnexpectedOutput;
                    }
                }
                continue;
            }
            while (true) {
                const wait_ms: u32 = if (std.mem.startsWith(u8, expected, "info string bench "))
                    default_wait_ms * 5
                else
                    default_wait_ms;
                const actual = awaitLine(io, &output, wait_ms) catch |err| {
                    std.debug.print("timed out or lost output while waiting for: {s}\n", .{expected});
                    return err;
                };
                if (matchesExpected(expected, actual.slice())) break;
                if (allow_info and validSearchInfo(actual.slice())) continue;
                std.debug.print("expected: {s}\nactual:   {s}\n", .{ expected, actual.slice() });
                return error.UnexpectedOutput;
            }
        },
        .silence_ms => |milliseconds| {
            if (stdout_blocked) return error.UnsupportedActiveDirective;
            if (try unexpectedDuringSilence(io, &output, milliseconds, allow_info)) |line| {
                std.debug.print("unexpected stdout during silence: {s}\n", .{line.slice()});
                return error.UnexpectedOutput;
            }
        },
        .sleep_ms => |milliseconds| timer(io, milliseconds),
        .send_oversized_line => {
            if (!stdin_open) return error.UnsupportedActiveDirective;
            const oversized: [65_538]u8 = @splat('x');
            try stdin_writer.interface.writeAll(&oversized);
            try stdin_writer.interface.writeByte('\n');
            try stdin_writer.interface.flush();
        },
        .close_stdin => {
            if (!stdin_open) return error.UnsupportedActiveDirective;
            try stdin_writer.interface.flush();
            child.stdin.?.close(io);
            child.stdin = null;
            stdin_open = false;
        },
        .block_stdout => {
            if (stdout_blocked) return error.UnsupportedActiveDirective;
            _ = output_future.cancel(io) catch {};
            output_finished = true;
            while (try takeAvailable(io, &output)) |line| {
                std.debug.print("unexpected stdout before block: {s}\n", .{line.slice()});
                return error.UnexpectedOutput;
            }
            stdout_blocked = true;
        },
        .allow_info_begin => allow_info = true,
        .allow_info_end => {
            // If exit occurred inside the allowance region, wait until the
            // stdout pump has observed EOF before closing that region. Search
            // progress written before shutdown may otherwise be queued after
            // the directive and misclassified as unsolicited output.
            if (saw_exit and !output_finished) {
                _ = output_future.await(io) catch {};
                output_finished = true;
            }
            while (try takeAvailable(io, &output)) |line| {
                if (line.kind == .line and validSearchInfo(line.slice())) continue;
                std.debug.print("unexpected stdout at end of info region: {s}\n", .{line.slice()});
                return error.UnexpectedOutput;
            }
            allow_info = false;
        },
        .fail_next => |resource| {
            const command = if (std.mem.eql(u8, resource, "hash-allocation"))
                "__manta_test_fail_hash_allocation\n"
            else if (std.mem.eql(u8, resource, "thread-allocation"))
                "__manta_test_fail_thread_allocation\n"
            else
                return error.UnsupportedActiveDirective;
            try stdin_writer.interface.writeAll(command);
            try stdin_writer.interface.flush();
        },
        .unblock_stdout => {
            if (!stdout_blocked) return error.UnsupportedActiveDirective;
            output = std.Io.Queue(StreamLine).init(&output_storage);
            output_future = try io.concurrent(streamPump, .{ io, child.stdout.?, &output });
            output_finished = false;
            stdout_blocked = false;
        },
        .exit => |expected_exit| {
            if (stdin_open) {
                try stdin_writer.interface.flush();
            }
            const term = try awaitExit(io, &child, expected_exit.within_ms);
            saw_exit = true;
            switch (term) {
                .exited => |code| if (code != expected_exit.code) return error.WrongExitCode,
                .signal => |signal| {
                    std.debug.print("child terminated by signal {d}\n", .{@intFromEnum(signal)});
                    return error.UnexpectedExit;
                },
                .stopped => |signal| {
                    std.debug.print("child stopped by signal {d}\n", .{@intFromEnum(signal)});
                    return error.UnexpectedExit;
                },
                .unknown => |status| {
                    std.debug.print("child terminated with unknown status {d}\n", .{status});
                    return error.UnexpectedExit;
                },
            }
        },
    };

    if (!saw_exit) return error.UnexpectedExit;
    if (!output_finished) {
        _ = output_future.await(io) catch {};
        output_finished = true;
        while (try takeAvailable(io, &output)) |line| {
            if (allow_info and validSearchInfo(line.slice())) continue;
            std.debug.print("unlisted stdout after exit: {s}\n", .{line.slice()});
            return error.UnexpectedOutput;
        }
    }
    _ = diagnostic_future.await(io) catch {};
    diagnostic_finished = true;
    if (try takeAvailable(io, &diagnostics)) |line| {
        std.debug.print("unexpected stderr: {s}\n", .{line.slice()});
        return error.ChildDiagnostic;
    }
}

fn unexpectedDuringSilence(
    io: std.Io,
    queue: *std.Io.Queue(StreamLine),
    milliseconds: u32,
    allow_info: bool,
) !?StreamLine {
    const start = monotonicNs(io);
    const deadline = start +| @as(u64, milliseconds) * std.time.ns_per_ms;
    while (true) {
        const now = monotonicNs(io);
        if (now >= deadline) return null;
        const remaining_ns = deadline - now;
        const remaining_ms: u32 = @intCast(@max(@as(u64, 1), @min(@as(u64, milliseconds), (remaining_ns + std.time.ns_per_ms - 1) / std.time.ns_per_ms)));
        const line = try lineArrivesWithin(io, queue, remaining_ms) orelse return null;
        if (!allow_info or !validSearchInfo(line.slice())) return line;
    }
}

fn monotonicNs(io: std.Io) u64 {
    const value = std.Io.Clock.awake.now(io).nanoseconds;
    if (value <= 0) return 0;
    return @intCast(@min(value, std.math.maxInt(u64)));
}

fn streamPump(io: std.Io, file: std.Io.File, queue: *std.Io.Queue(StreamLine)) std.Io.Cancelable!void {
    defer queue.close(io);
    var read_buffer: [max_process_line_bytes + 1]u8 = undefined;
    var file_reader = file.reader(io, &read_buffer);
    const reader = &file_reader.interface;

    while (true) {
        const maybe_line = reader.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                try putStreamLine(io, queue, .{ .kind = .too_long });
                return;
            },
            error.ReadFailed => {
                if (file_reader.err) |read_error| switch (read_error) {
                    error.Canceled => return error.Canceled,
                    else => {},
                };
                try putStreamLine(io, queue, .{ .kind = .read_failed });
                return;
            },
        };
        const raw = maybe_line orelse return;
        const line = if (std.mem.endsWith(u8, raw, "\r")) raw[0 .. raw.len - 1] else raw;
        var record: StreamLine = .{ .kind = .line, .len = @intCast(line.len) };
        @memcpy(record.bytes[0..line.len], line);
        try putStreamLine(io, queue, record);
    }
}

fn putStreamLine(io: std.Io, queue: *std.Io.Queue(StreamLine), line: StreamLine) std.Io.Cancelable!void {
    queue.putOne(io, line) catch |err| switch (err) {
        error.Closed => return,
        error.Canceled => return error.Canceled,
    };
}

const LineRace = union(enum) {
    line: ?StreamLine,
    timeout,
};

fn awaitLine(io: std.Io, queue: *std.Io.Queue(StreamLine), milliseconds: u32) !StreamLine {
    const result = try raceLineAndTimer(io, queue, milliseconds);
    return switch (result) {
        .timeout => error.OutputTimeout,
        .line => |maybe_line| if (maybe_line) |line| switch (line.kind) {
            .line => line,
            .too_long => error.OutputLineTooLong,
            .read_failed => error.UnexpectedEndOfOutput,
        } else error.UnexpectedEndOfOutput,
    };
}

fn lineArrivesWithin(io: std.Io, queue: *std.Io.Queue(StreamLine), milliseconds: u32) !?StreamLine {
    const result = try raceLineAndTimer(io, queue, milliseconds);
    return switch (result) {
        .timeout => null,
        .line => |maybe_line| maybe_line orelse return error.UnexpectedEndOfOutput,
    };
}

fn raceLineAndTimer(io: std.Io, queue: *std.Io.Queue(StreamLine), milliseconds: u32) !LineRace {
    var storage: [2]LineRace = undefined;
    var select = std.Io.Select(LineRace).init(io, &storage);
    try select.concurrent(.line, receiveLine, .{ io, queue });
    try select.concurrent(.timeout, timer, .{ io, milliseconds });
    const result = try select.await();
    select.cancelDiscard();
    return result;
}

fn receiveLine(io: std.Io, queue: *std.Io.Queue(StreamLine)) ?StreamLine {
    return queue.getOne(io) catch null;
}

fn timer(io: std.Io, milliseconds: u32) void {
    std.Io.sleep(io, .fromMilliseconds(milliseconds), .awake) catch {};
}

fn awaitExit(io: std.Io, child: *std.process.Child, milliseconds: u32) !std.process.Child.Term {
    const ExitRace = union(enum) {
        term: std.process.Child.WaitError!std.process.Child.Term,
        timeout,
    };
    var storage: [2]ExitRace = undefined;
    var select = std.Io.Select(ExitRace).init(io, &storage);
    try select.concurrent(.term, waitChild, .{ io, child });
    try select.concurrent(.timeout, timer, .{ io, milliseconds });
    const result = try select.await();
    select.cancelDiscard();
    return switch (result) {
        .term => |term| try term,
        .timeout => error.OutputTimeout,
    };
}

fn waitChild(io: std.Io, child: *std.process.Child) std.process.Child.WaitError!std.process.Child.Term {
    return child.wait(io);
}

fn takeAvailable(io: std.Io, queue: *std.Io.Queue(StreamLine)) !?StreamLine {
    var buffer: [1]StreamLine = undefined;
    const count = queue.get(io, &buffer, 0) catch |err| switch (err) {
        error.Closed => return null,
        error.Canceled => return err,
    };
    return if (count == 0) null else buffer[0];
}

fn matchesExpected(expected: []const u8, actual: []const u8) bool {
    if (std.mem.eql(u8, expected, "{{ROOT_MOVE_INFO}}")) return validRootMoveInfo(actual);
    if (std.mem.eql(u8, expected, "{{ITERATION_INFO}}")) return validIterationInfo(actual);
    if (std.mem.eql(u8, expected, "{{SEARCH_INFO}}"))
        return validRootMoveInfo(actual) or validIterationInfo(actual);
    if (std.mem.eql(u8, expected, "{{BESTMOVE_LINE}}")) return validBestMove(actual);
    var expected_cursor: usize = 0;
    var actual_cursor: usize = 0;
    while (std.mem.indexOfPos(u8, expected, expected_cursor, "{{")) |start| {
        const end = std.mem.indexOfPos(u8, expected, start + 2, "}}") orelse return false;
        const literal = expected[expected_cursor..start];
        if (!std.mem.startsWith(u8, actual[actual_cursor..], literal)) return false;
        actual_cursor += literal.len;
        const placeholder = expected[start .. end + 2];
        const next_start = end + 2;
        const next_marker = std.mem.indexOfPos(u8, expected, next_start, "{{") orelse expected.len;
        const following_literal = expected[next_start..next_marker];
        const value_end = if (following_literal.len == 0)
            actual.len
        else
            std.mem.indexOfPos(u8, actual, actual_cursor, following_literal) orelse return false;
        const value = actual[actual_cursor..value_end];
        if (!matchesPlaceholder(placeholder, value)) return false;
        actual_cursor = value_end;
        expected_cursor = next_start;
    }
    return std.mem.eql(u8, expected[expected_cursor..], actual[actual_cursor..]);
}

fn matchesPlaceholder(placeholder: []const u8, value: []const u8) bool {
    if (std.mem.eql(u8, placeholder, "{{VERSION}}")) return std.mem.eql(u8, value, build_options.version);
    if (std.mem.eql(u8, placeholder, "{{PONDER}}")) return matchesOptionalPonder(value);
    if (std.mem.eql(u8, placeholder, "{{U64}}")) return parseUnsigned(value, false);
    if (std.mem.eql(u8, placeholder, "{{POSITIVE_U64}}")) return parseUnsigned(value, true);
    if (std.mem.eql(u8, placeholder, "{{DECIMAL}}")) return parseDecimal(value);
    return false;
}

/// Match either no continuation or one ` ponder <move>` suffix. A search cancelled
/// before it completes a second ply has no continuation to report, which is a
/// search-timing detail rather than a protocol contract.
fn matchesOptionalPonder(value: []const u8) bool {
    if (value.len == 0) return true;
    const prefix = " ponder ";
    if (!std.mem.startsWith(u8, value, prefix)) return false;
    return validUciMove(value[prefix.len..]);
}

fn parseUnsigned(value: []const u8, positive: bool) bool {
    if (value.len == 0) return false;
    for (value) |byte| if (!std.ascii.isDigit(byte)) return false;
    const parsed = std.fmt.parseInt(u64, value, 10) catch return false;
    return !positive or parsed != 0;
}

fn parseDecimal(value: []const u8) bool {
    if (value.len == 0) return false;
    var dots: u1 = 0;
    for (value) |byte| {
        if (byte == '.') {
            if (dots != 0) return false;
            dots = 1;
        } else if (!std.ascii.isDigit(byte)) return false;
    }
    return true;
}

fn validSearchInfo(line: []const u8) bool {
    return validRootMoveInfo(line) or validIterationInfo(line) or validTimeTelemetry(line);
}

fn validTimeTelemetry(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "info string time optimum_ms ") and
        std.mem.indexOf(u8, line, " maximum_ms ") != null and
        std.mem.indexOf(u8, line, " combined ") != null and
        std.mem.indexOf(u8, line, " ponder_credit_ns ") != null and
        std.mem.indexOf(u8, line, " helper_events ") != null and
        std.mem.indexOf(u8, line, " hard_overshoot_ns ") != null;
}

fn validRootMoveInfo(line: []const u8) bool {
    if (!std.mem.startsWith(u8, line, "info depth ")) return false;
    return std.mem.indexOf(u8, line, " currmove ") != null and
        std.mem.indexOf(u8, line, " currmovenumber ") != null and
        std.mem.indexOf(u8, line, " nodes ") != null and
        std.mem.indexOf(u8, line, " time ") != null;
}

fn validIterationInfo(line: []const u8) bool {
    if (!std.mem.startsWith(u8, line, "info depth ")) return false;
    return std.mem.indexOf(u8, line, " score ") != null and
        std.mem.indexOf(u8, line, " nodes ") != null and
        std.mem.indexOf(u8, line, " time ") != null and
        (std.mem.indexOf(u8, line, " pv ") != null or
            std.mem.endsWith(u8, line, " pv"));
}

fn validBestMove(line: []const u8) bool {
    if (!std.mem.startsWith(u8, line, "bestmove ")) return false;
    var tokens = std.mem.tokenizeScalar(u8, line[9..], ' ');
    const best = tokens.next() orelse return false;
    if (!validUciMove(best) and !std.mem.eql(u8, best, "(none)")) return false;
    const marker = tokens.next() orelse return true;
    if (!std.mem.eql(u8, marker, "ponder")) return false;
    const ponder = tokens.next() orelse return false;
    return validUciMove(ponder) and tokens.next() == null;
}

fn validUciMove(text: []const u8) bool {
    if (text.len != 4 and text.len != 5) return false;
    if (text[0] < 'a' or text[0] > 'h' or text[2] < 'a' or text[2] > 'h') return false;
    if (text[1] < '1' or text[1] > '8' or text[3] < '1' or text[3] > '8') return false;
    if (text.len == 5 and std.mem.indexOfScalar(u8, "qrbn", text[4]) == null) return false;
    return true;
}

fn phaseAtMost(candidate: []const u8, active: []const u8) bool {
    const candidate_value = phaseValue(candidate) orelse return false;
    const active_value = phaseValue(active) orelse return false;
    return candidate_value <= active_value;
}

fn phaseValue(text: []const u8) ?u32 {
    var parts = std.mem.splitScalar(u8, text, '.');
    const major = std.fmt.parseInt(u16, parts.next() orelse return null, 10) catch return null;
    const minor = std.fmt.parseInt(u16, parts.next() orelse return null, 10) catch return null;
    if (parts.next() != null) return null;
    return @as(u32, major) * 1000 + minor;
}
