//! Bounded asynchronous UCI controller, joined search pool, and sole presenter.
const std = @import("std");
const builtin = @import("builtin");
const manta = @import("manta");
const chess = manta.chess;
const engine = manta.engine;
const search = manta.search;
const score = manta.score;
const protocol = @import("protocol.zig");

const command_capacity = 64;
const output_capacity = 64;
const max_output_bytes = 4096;
const shutdown_flush_ms = 250;
const Runtime = engine.runtime;
const ControllerState = Runtime.Controller;
const GameState = Runtime.GameState;
const HashResource = Runtime.HashResource;
const SearchSpec = Runtime.SearchSpec;
const Job = Runtime.Job;
const options = engine.options;

const Line = struct {
    len: u16 = 0,
    bytes: [max_output_bytes]u8 = @splat(0),

    fn slice(self: *const Line) []const u8 {
        return self.bytes[0..self.len];
    }
};

const OutputEvent = union(enum) {
    startup: *std.Io.Event,
    line: Line,
};

const Shared = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    version: []const u8,
    transcript_hooks: bool,
    commands: *std.Io.Queue(protocol.Command),
    output: *std.Io.Queue(OutputEvent),
    controller_wake: std.Io.Semaphore = .{},
    shutdown: *std.Io.Event,
    presenter_done: *std.Io.Event,
    active_epoch: std.atomic.Value(u64) = .init(0),
    cancel_epoch: std.atomic.Value(u64) = .init(0),
    ponderhit_epoch: std.atomic.Value(u64) = .init(0),
    ponderhit_received_ns: std.atomic.Value(u64) = .init(0),
    fatal: std.atomic.Value(bool) = .init(false),
};

pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    version: []const u8,
    transcript_hooks: bool,
) !u8 {
    var state = try ControllerState.init(allocator);
    defer state.deinit();

    var command_storage: [command_capacity]protocol.Command = undefined;
    var output_storage: [output_capacity]OutputEvent = undefined;
    var command_queue = std.Io.Queue(protocol.Command).init(&command_storage);
    var output_queue = std.Io.Queue(OutputEvent).init(&output_storage);
    var shutdown: std.Io.Event = .unset;
    var presenter_done: std.Io.Event = .unset;
    var shared: Shared = .{
        .io = io,
        .allocator = allocator,
        .version = version,
        .transcript_hooks = transcript_hooks,
        .commands = &command_queue,
        .output = &output_queue,
        .shutdown = &shutdown,
        .presenter_done = &presenter_done,
    };
    try state.startWorker(io);

    var presenter_future = try io.concurrent(presenter, .{&shared});
    var startup_flushed: std.Io.Event = .unset;
    try output_queue.putOne(io, .{ .startup = &startup_flushed });
    startup_flushed.waitTimeout(io, timeoutMs(1000)) catch {
        shared.fatal.store(true, .release);
        output_queue.close(io);
        _ = presenter_future.cancel(io) catch |err| switch (err) {
            error.Canceled => {},
        };
        return 1;
    };

    var controller_future = try io.concurrent(controller, .{ &shared, &state });
    var input_future = try io.concurrent(input, .{&shared});
    shutdown.wait(io) catch |err| switch (err) {
        error.Canceled => return err,
    };

    command_queue.close(io);
    // A fatal input/output shutdown can close the queue without enqueuing a
    // final command. Wake the event-driven controller so it observes Closed.
    shared.controller_wake.post(io);
    _ = input_future.cancel(io) catch |err| switch (err) {
        error.Canceled => {},
    };
    _ = controller_future.await(io) catch |err| switch (err) {
        error.Canceled => {},
        else => shared.fatal.store(true, .release),
    };
    output_queue.close(io);

    presenter_done.waitTimeout(io, timeoutMs(shutdown_flush_ms)) catch {
        _ = presenter_future.cancel(io) catch |err| switch (err) {
            error.Canceled => {},
        };
        return if (shared.fatal.load(.acquire)) 1 else 0;
    };
    _ = presenter_future.await(io) catch |err| switch (err) {
        error.Canceled => {},
    };
    return if (shared.fatal.load(.acquire)) 1 else 0;
}

fn input(shared: *Shared) std.Io.Cancelable!void {
    var read_buffer: [protocol.max_input_bytes + 2]u8 = undefined;
    var stdin_file = stdinForStreaming() catch return fatalInput(shared);
    var file_reader = stdin_file.readerStreaming(shared.io, &read_buffer);
    const reader = &file_reader.interface;

    while (true) {
        const maybe_line = reader.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                _ = reader.discardDelimiterInclusive('\n') catch |discard_err| switch (discard_err) {
                    error.EndOfStream => {},
                    else => return fatalInput(shared),
                };
                if (!try queueCommand(shared, protocol.oversizedCommand())) return;
                continue;
            },
            error.ReadFailed => return fatalInput(shared),
        };
        const raw_line = maybe_line orelse {
            try queueQuit(shared);
            return;
        };
        const line = if (std.mem.endsWith(u8, raw_line, "\r")) raw_line[0 .. raw_line.len - 1] else raw_line;
        if (line.len > protocol.max_input_bytes) {
            if (!try queueCommand(shared, protocol.oversizedCommand())) return;
            continue;
        }
        var command = protocol.parse(line, shared.transcript_hooks) orelse continue;
        const trimmed = std.mem.trim(u8, line, " \t");
        command.raw = shared.allocator.dupe(u8, trimmed) catch return fatalInput(shared);
        command.received_ns = monotonicNs(shared.io);
        if (command.tag == .stop or command.tag == .quit or command.tag == .ponderhit) {
            command.target_epoch = shared.active_epoch.load(.acquire);
        }
        if (command.tag == .stop or command.tag == .quit)
            urgentCancelEpoch(shared, command.target_epoch);
        if (command.tag == .ponderhit)
            urgentPonderHitEpoch(shared, command.target_epoch, command.received_ns);
        if (!try queueCommand(shared, command)) {
            shared.allocator.free(command.raw.?);
            return;
        }
        if (command.tag == .quit) {
            shared.shutdown.set(shared.io);
            return;
        }
    }
}

const StdinModeError = error{StdinModeQueryFailed};

/// Standard input is always consumed as a stream. On Windows, Zig 0.16 cannot
/// infer whether an inherited handle was opened for synchronous or asynchronous
/// I/O: `File.stdin()` unconditionally reports synchronous. Match the real file
/// object mode so the threaded reader selects the compatible `NtReadFile` path.
fn stdinForStreaming() StdinModeError!std.Io.File {
    var file = std.Io.File.stdin();
    if (comptime builtin.os.tag != .windows) return file;

    const windows = std.os.windows;
    // SAFETY: NtQueryInformationFile initializes the status block before any
    // branch reads it; PENDING waits for completion before reading Status.
    var io_status: windows.IO_STATUS_BLOCK = undefined;
    // SAFETY: mode_info is read only after NtQueryInformationFile succeeds or
    // its pending operation completes successfully.
    var mode_info: windows.FILE.MODE.INFORMATION = undefined;
    switch (windows.ntdll.NtQueryInformationFile(
        file.handle,
        &io_status,
        &mode_info,
        @sizeOf(windows.FILE.MODE.INFORMATION),
        .Mode,
    )) {
        .SUCCESS => {},
        .PENDING => {
            if (windows.ntdll.NtWaitForSingleObject(file.handle, .FALSE, null) != .SUCCESS)
                return error.StdinModeQueryFailed;
            if (io_status.u.Status != .SUCCESS) return error.StdinModeQueryFailed;
        },
        else => return error.StdinModeQueryFailed,
    }
    file.flags.nonblocking = mode_info.Mode.IO == .ASYNCHRONOUS;
    return file;
}

fn queueQuit(shared: *Shared) std.Io.Cancelable!void {
    const epoch = shared.active_epoch.load(.acquire);
    urgentCancelEpoch(shared, epoch);
    var command = protocol.Command{ .tag = .quit, .line = .{}, .token = .{} };
    command.target_epoch = epoch;
    command.raw = shared.allocator.dupe(u8, "quit") catch return fatalInput(shared);
    _ = try queueCommand(shared, command);
    shared.shutdown.set(shared.io);
}

fn fatalInput(shared: *Shared) void {
    shared.fatal.store(true, .release);
    urgentCancel(shared);
    shared.shutdown.set(shared.io);
}

fn urgentCancel(shared: *Shared) void {
    const epoch = shared.active_epoch.load(.acquire);
    urgentCancelEpoch(shared, epoch);
}

fn urgentCancelEpoch(shared: *Shared, epoch: u64) void {
    if (epoch != 0) shared.cancel_epoch.store(epoch, .release);
}

fn urgentPonderHitEpoch(shared: *Shared, epoch: u64, received_ns: u64) void {
    if (epoch != 0) {
        // Publishing the epoch releases the timestamp to the worker. A stale
        // pair is harmless because the consumer first matches the epoch.
        shared.ponderhit_received_ns.store(received_ns, .monotonic);
        shared.ponderhit_epoch.store(epoch, .release);
    }
}

fn queueCommand(shared: *Shared, command: protocol.Command) std.Io.Cancelable!bool {
    shared.commands.putOne(shared.io, command) catch |err| switch (err) {
        error.Closed => return false,
        error.Canceled => return error.Canceled,
    };
    shared.controller_wake.post(shared.io);
    return true;
}

fn controller(shared: *Shared, state: *ControllerState) !void {
    defer {
        if (state.active != null) {
            urgentCancel(shared);
            finishActive(shared, state, false);
        }
        drainCommands(shared);
        shared.output.close(shared.io);
    }
    var debug_enabled = false;

    while (true) {
        // Every accepted command and every worker completion contributes one
        // permit. Unlike a timer poll, the semaphore cannot lose a wakeup
        // between checking the completion slot and blocking.
        shared.controller_wake.wait(shared.io) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
        };

        if (state.active) |*active| {
            drainSearchProgress(shared, active);
            if (active.done.isSet()) {
                // Completion is published after the last iteration progress.
                // A first drain can race between those two publications, so
                // take the now-stable slot once more before final reporting.
                drainSearchProgress(shared, active);
                if (isWaitingPonder(active, shared)) {
                    publishRetainedPonderInfo(shared, active);
                } else {
                    finishActive(shared, state, true);
                    continue;
                }
            }
        }

        var buffer: [1]protocol.Command = undefined;
        const count = shared.commands.get(shared.io, &buffer, 0) catch |err| switch (err) {
            error.Closed => return,
            error.Canceled => return error.Canceled,
        };
        if (count == 0) continue;

        var command = buffer[0];
        defer if (command.raw) |raw| shared.allocator.free(raw);
        if (debug_enabled and !offerLine(shared, lineFmt(
            "info string debug received \"{s}\"",
            .{command.line.slice()},
        ))) return;

        switch (command.tag) {
            .uci => {
                if (!offerLine(shared, lineFmt("id name Manta {s}", .{shared.version}))) return;
                if (!offerText(shared, "id author Miloslav Macurek")) return;
                for (options.public) |spec| {
                    if (!offerLine(shared, optionDeclaration(spec))) return;
                }
                if (comptime search.params.tune_enabled) inline for (search.params.specs) |spec| {
                    if (!offerLine(shared, lineFmt(
                        "option name {s} type spin default {d} min {d} max {d}",
                        .{ spec.name, spec.default, spec.min, spec.max },
                    ))) return;
                };
                if (comptime engine.time.tune_enabled) inline for (engine.time.param_specs) |spec| {
                    if (!offerLine(shared, lineFmt(
                        "option name {s} type spin default {d} min {d} max {d}",
                        .{ spec.name, spec.default, spec.min, spec.max },
                    ))) return;
                };
                if (!offerText(shared, "uciok")) return;
            },
            .isready => if (!offerText(shared, "readyok")) return,
            .debug_on => debug_enabled = true,
            .debug_off => debug_enabled = false,
            .quit => {
                if (state.active != null) {
                    cancelActive(shared, state);
                    finishActive(shared, state, false);
                }
                return;
            },
            // The input-side atomic targets only the epoch observed at receipt.
            // Once dequeued, FIFO order is authoritative: a stop after a queued
            // replacement `go` belongs to that replacement search.
            .stop => if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            },
            .ponderhit => if (state.active) |active| {
                if (isPonderJob(active.job)) {
                    shared.ponderhit_received_ns.store(command.received_ns, .monotonic);
                    shared.ponderhit_epoch.store(active.epoch, .release);
                    if (active.done.isSet()) finishActive(shared, state, true);
                }
            },
            .ucinewgame => {
                if (state.active != null) {
                    cancelActive(shared, state);
                    finishActive(shared, state, true);
                }
                state.hash.table.clear();
                state.clearSearchState();
            },
            .position => try handlePosition(shared, state, command.raw.?),
            .go => try handleGo(shared, state, command.raw.?, command.received_ns),
            .bench => try handleBench(shared, state, command.raw.?),
            .setoption => try handleSetOption(shared, state, command.raw.?),
            .test_fail_hash_allocation => state.fail_next_hash_allocation = true,
            .test_fail_thread_allocation => state.fail_next_thread_allocation = true,
            .input_too_long => if (!offerText(shared, "info string invalid input: line exceeds 65536 bytes")) return,
            .invalid_uci => if (!offerText(shared, "info string invalid uci: unexpected argument")) return,
            .invalid_isready => if (!offerText(shared, "info string invalid isready: unexpected argument")) return,
            .invalid_debug => if (!offerText(shared, "info string invalid debug: expected on or off")) return,
            .invalid_quit => if (!offerText(shared, "info string invalid quit: unexpected argument")) return,
            .invalid_stop => if (!offerText(shared, "info string invalid stop: unexpected argument")) return,
            .invalid_ponderhit => if (!offerText(shared, "info string invalid ponderhit: unexpected argument")) return,
            .invalid_ucinewgame => if (!offerText(shared, "info string invalid ucinewgame: unexpected argument")) return,
            .unavailable => if (!offerLine(shared, lineFmt(
                "info string command \"{s}\" is not available yet",
                .{command.token.slice()},
            ))) return,
            .unknown => if (!offerLine(shared, lineFmt(
                "info string unknown command \"{s}\" ignored",
                .{command.token.slice()},
            ))) return,
        }
    }
}

fn handlePosition(shared: *Shared, state: *ControllerState, raw: []const u8) !void {
    const prepared = try preparePosition(state.allocator, raw);
    switch (prepared) {
        .invalid => |diagnostic| _ = offerLine(shared, diagnostic),
        .game => |candidate_value| {
            const candidate = candidate_value;
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            state.game.deinit(state.allocator);
            state.game = candidate;
        },
    }
}

const PreparedPosition = union(enum) { game: GameState, invalid: Line };

fn preparePosition(allocator: std.mem.Allocator, raw: []const u8) !PreparedPosition {
    var tokens = std.mem.tokenizeAny(u8, raw, " \t");
    _ = tokens.next();
    const form = tokens.next() orelse return .{ .invalid = lineText("info string invalid position: expected startpos or fen") };
    var fen_buffer: [chess.fen.max_length]u8 = undefined;
    var fen_text: []const u8 = &.{};
    var first_after_fen: ?[]const u8 = null;
    if (std.mem.eql(u8, form, "startpos")) {
        fen_text = chess.fen.start_position;
        first_after_fen = tokens.next();
    } else if (std.mem.eql(u8, form, "fen")) {
        var writer = std.Io.Writer.fixed(&fen_buffer);
        for (0..6) |index| {
            const field = tokens.next() orelse return .{ .invalid = lineText("info string invalid position: FEN requires six fields") };
            if (index != 0) writer.writeByte(' ') catch return .{ .invalid = lineText("info string invalid position: FEN is too long") };
            writer.writeAll(field) catch return .{ .invalid = lineText("info string invalid position: FEN is too long") };
        }
        fen_text = writer.buffered();
        first_after_fen = tokens.next();
    } else {
        return .{ .invalid = lineText("info string invalid position: expected startpos or fen") };
    }

    var move_tokens: std.ArrayList([]const u8) = .empty;
    defer move_tokens.deinit(allocator);
    if (first_after_fen) |token| {
        if (!std.mem.eql(u8, token, "moves"))
            return .{ .invalid = lineText("info string invalid position: expected moves") };
        while (tokens.next()) |move_text| try move_tokens.append(allocator, move_text);
    }

    const states = try allocator.alloc(chess.position.PositionState, move_tokens.items.len + 1);
    errdefer allocator.free(states);
    const moves = try allocator.alloc(chess.move.Move, move_tokens.items.len);
    errdefer allocator.free(moves);
    var position = chess.fen.parse(fen_text, &states[0]) catch |err| {
        allocator.free(states);
        allocator.free(moves);
        return .{ .invalid = if (err == error.FieldCount)
            lineText("info string invalid position: FEN requires six fields")
        else
            lineText("info string invalid position: invalid FEN") };
    };
    for (move_tokens.items, 0..) |move_text, index| {
        const chess_move = chess.notation.parseLegal(&position, move_text) catch {
            allocator.free(states);
            allocator.free(moves);
            return .{ .invalid = lineFmt(
                "info string invalid position: illegal move \"{s}\"",
                .{protocol.sanitize(move_text).slice()},
            ) };
        };
        moves[index] = chess_move;
        chess.transition.makeMove(&position, chess_move, &states[index + 1]);
    }
    return .{ .game = .{ .position = position, .states = states, .moves = moves } };
}

fn handleGo(shared: *Shared, state: *ControllerState, raw: []const u8, received_ns: u64) !void {
    const parsed = parseGo(&state.game.position, raw, received_ns, state.ponder_enabled);
    switch (parsed) {
        .invalid => |diagnostic| _ = offerLine(shared, diagnostic),
        .job => |job| {
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            try startActive(shared, state, job);
        },
    }
}

fn handleBench(shared: *Shared, state: *ControllerState, raw: []const u8) !void {
    const parsed = parseBench(raw);
    switch (parsed) {
        .invalid => |diagnostic| _ = offerLine(shared, diagnostic),
        .spec => |spec| {
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            startActive(shared, state, .{ .bench = spec }) catch {
                _ = offerText(shared, "info string bench failed: resource allocation failed");
            };
        },
    }
}

const ParsedBench = union(enum) { spec: engine.bench.Spec, invalid: Line };

fn parseBench(raw: []const u8) ParsedBench {
    var tokens = std.mem.tokenizeAny(u8, raw, " \t");
    _ = tokens.next();
    const depth = parseBenchField(tokens.next(), engine.bench.default_depth) orelse
        return .{ .invalid = lineText("info string invalid bench: depth must be a positive integer") };
    const repeats = parseBenchField(tokens.next(), 1) orelse
        return .{ .invalid = lineText("info string invalid bench: repeats must be a positive integer") };
    const threads = parseBenchField(tokens.next(), 1) orelse
        return .{ .invalid = lineText("info string invalid bench: threads must be a positive integer") };
    if (tokens.next() != null)
        return .{ .invalid = lineText("info string invalid bench: expected at most depth, repeats and threads") };
    if (depth > chess.types.max_ply - 1)
        return .{ .invalid = lineText("info string invalid bench: depth exceeds MAX_PLY - 1") };
    if (repeats > engine.bench.max_repeats)
        return .{ .invalid = lineFmt("info string invalid bench: repeats exceeds {d}", .{engine.bench.max_repeats}) };
    if (threads != 1)
        return .{ .invalid = lineText("info string invalid bench: threads must be 1 until Phase 6") };
    return .{ .spec = .{
        .depth = @intCast(depth),
        .repeats = @intCast(repeats),
        .threads = @intCast(threads),
    } };
}

fn parseBenchField(maybe_text: ?[]const u8, default: u16) ?u64 {
    const text = maybe_text orelse return default;
    const value = parseUnsigned(text) orelse return null;
    return if (value == 0) null else value;
}

const ParsedGo = union(enum) { job: Job, invalid: Line };

fn parseGo(
    position: *const chess.position.Position,
    raw: []const u8,
    received_ns: u64,
    ponder_enabled: bool,
) ParsedGo {
    var tokens = std.mem.tokenizeAny(u8, raw, " \t");
    _ = tokens.next();
    const first = tokens.next() orelse return .{ .invalid = lineText("info string invalid go: no search limit") };
    if (std.mem.eql(u8, first, "perft")) {
        const depth_text = tokens.next() orelse return .{ .invalid = lineText("info string invalid go: perft requires depth") };
        if (tokens.next() != null) return .{ .invalid = lineText("info string invalid go: perft conflicts with search fields") };
        const depth = parseUnsigned(depth_text) orelse return .{ .invalid = lineText("info string invalid go: perft depth must be an unsigned integer") };
        if (depth > chess.types.max_ply) return .{ .invalid = lineText("info string invalid go: perft depth exceeds MAX_PLY") };
        return .{ .job = .{ .perft = @intCast(depth) } };
    }

    var fields: GoFields = .{};
    parseGoField(&fields, first, &tokens, position) catch |err| return .{ .invalid = goParseDiagnostic(err, fields.bad_token.slice()) };
    while (tokens.next()) |keyword| {
        parseGoField(&fields, keyword, &tokens, position) catch |err| return .{ .invalid = goParseDiagnostic(err, fields.bad_token.slice()) };
    }
    return validateGo(position, fields, received_ns, ponder_enabled);
}

const GoParseError = error{ MissingValue, InvalidNumber, Duplicate, Unknown, IllegalMove, EmptySearchMoves };
const GoFields = struct {
    wtime: ?u64 = null,
    btime: ?u64 = null,
    winc: ?u64 = null,
    binc: ?u64 = null,
    movestogo: ?u64 = null,
    movetime: ?u64 = null,
    depth: ?u64 = null,
    nodes: ?u64 = null,
    mate: ?u64 = null,
    infinite: bool = false,
    ponder: bool = false,
    restricted: bool = false,
    root_moves: chess.position.MoveList = chess.position.MoveList.init(),
    seen: u16 = 0,
    bad_token: protocol.Sanitized = .{},
};

fn parseGoField(
    fields: *GoFields,
    keyword: []const u8,
    tokens: *std.mem.TokenIterator(u8, .any),
    position: *const chess.position.Position,
) GoParseError!void {
    const tag = goKeyword(keyword) orelse {
        fields.bad_token = protocol.sanitize(keyword);
        return error.Unknown;
    };
    const bit = @as(u16, 1) << @intFromEnum(tag);
    if (fields.seen & bit != 0) {
        fields.bad_token = protocol.sanitize(keyword);
        return error.Duplicate;
    }
    fields.seen |= bit;
    switch (tag) {
        .infinite => fields.infinite = true,
        .ponder => fields.ponder = true,
        .searchmoves => {
            fields.restricted = true;
            while (tokens.peek()) |move_text| {
                if (goKeyword(move_text) != null) break;
                _ = tokens.next();
                const chess_move = chess.notation.parseLegal(position, move_text) catch {
                    fields.bad_token = protocol.sanitize(move_text);
                    return error.IllegalMove;
                };
                var duplicate = false;
                for (fields.root_moves.slice()) |existing| {
                    if (existing.raw() == chess_move.raw()) duplicate = true;
                }
                if (!duplicate) fields.root_moves.append(chess_move);
            }
            if (fields.root_moves.count == 0) return error.EmptySearchMoves;
        },
        else => {
            const value_text = tokens.next() orelse {
                fields.bad_token = protocol.sanitize(keyword);
                return error.MissingValue;
            };
            const parsed = parseUnsigned(value_text) orelse {
                fields.bad_token = protocol.sanitize(value_text);
                return error.InvalidNumber;
            };
            switch (tag) {
                .wtime => fields.wtime = parsed,
                .btime => fields.btime = parsed,
                .winc => fields.winc = parsed,
                .binc => fields.binc = parsed,
                .movestogo => fields.movestogo = parsed,
                .movetime => fields.movetime = parsed,
                .depth => fields.depth = parsed,
                .nodes => fields.nodes = parsed,
                .mate => fields.mate = parsed,
                .infinite, .ponder, .searchmoves => unreachable,
            }
        },
    }
}

const GoKeyword = enum(u4) { wtime, btime, winc, binc, movestogo, movetime, depth, nodes, mate, infinite, ponder, searchmoves };

fn goKeyword(text: []const u8) ?GoKeyword {
    inline for (@typeInfo(GoKeyword).@"enum".fields) |field| {
        if (std.mem.eql(u8, text, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn validateGo(
    position: *const chess.position.Position,
    fields: GoFields,
    received_ns: u64,
    ponder_enabled: bool,
) ParsedGo {
    const side = position.side_to_move;
    if (fields.ponder and !ponder_enabled)
        return .{ .invalid = lineText("info string invalid go: Ponder option is false") };
    const has_clock = fields.wtime != null or fields.btime != null or fields.winc != null or fields.binc != null;
    const has_fixed = fields.depth != null or fields.nodes != null or fields.mate != null;
    if (fields.infinite) {
        if (has_clock or has_fixed or fields.movetime != null or fields.movestogo != null or fields.ponder)
            return .{ .invalid = lineText("info string invalid go: infinite conflicts with other limits") };
    }
    if (fields.ponder and (!has_clock or fields.movetime != null))
        return .{ .invalid = lineText("info string invalid go: ponder requires clock fields") };
    if (fields.movetime != null and (has_clock or fields.movestogo != null))
        return .{ .invalid = lineText("info string invalid go: movetime conflicts with clock fields") };
    const positive = [_]?u64{ fields.movestogo, fields.movetime, fields.depth, fields.nodes, fields.mate };
    for (positive) |maybe_value| if (maybe_value == 0) return .{ .invalid = lineText("info string invalid go: search limits must be positive") };

    var time_input: ?engine.time.Input = null;
    if (fields.movetime) |milliseconds| {
        time_input = .{ .movetime_ms = milliseconds };
    } else if (has_clock or fields.movestogo != null) {
        const remaining = if (side == .white) fields.wtime else fields.btime;
        if (remaining == null) return .{ .invalid = lineText("info string invalid go: side-to-move clock is missing") };
        time_input = .{ .clock = .{
            .remaining_ms = remaining.?,
            .increment_ms = (if (side == .white) fields.winc else fields.binc) orelse 0,
            .moves_to_go = fields.movestogo,
            .game_ply = position.game_ply,
        } };
    }
    if (!fields.infinite and time_input == null and !has_fixed)
        return .{ .invalid = lineText("info string invalid go: no search limit") };

    var depth: u16 = if (fields.depth) |value|
        @intCast(@min(value, chess.types.max_ply - 1))
    else
        chess.types.max_ply - 1;
    if (fields.mate) |moves| {
        const mate_depth = @min(moves *| 2, chess.types.max_ply - 1);
        depth = @min(depth, @as(u16, @intCast(mate_depth)));
    }
    var legal_root_moves = chess.position.MoveList.init();
    chess.movegen.generate(.all, position, &legal_root_moves);
    return .{ .job = .{ .normal = .{
        .limits = .{ .depth = depth, .nodes = fields.nodes },
        .root_moves = fields.root_moves,
        .legal_root_move_count = @intCast(legal_root_moves.count),
        .restricted = fields.restricted,
        .time_input = time_input,
        .received_ns = received_ns,
        .ponder = fields.ponder,
    } } };
}

fn goParseDiagnostic(err: GoParseError, token: []const u8) Line {
    return switch (err) {
        error.MissingValue => lineFmt("info string invalid go: missing value after \"{s}\"", .{token}),
        error.InvalidNumber => lineFmt("info string invalid go: \"{s}\" is not an unsigned integer", .{token}),
        error.Duplicate => lineFmt("info string invalid go: duplicate keyword \"{s}\"", .{token}),
        error.Unknown => lineFmt("info string invalid go: unknown token \"{s}\"", .{token}),
        error.IllegalMove => lineFmt("info string invalid go: illegal search move \"{s}\"", .{token}),
        error.EmptySearchMoves => lineText("info string invalid go: searchmoves requires a legal move"),
    };
}

fn handleSetOption(shared: *Shared, state: *ControllerState, raw: []const u8) !void {
    const parsed = parseSetOption(raw);
    switch (parsed) {
        .invalid => |diagnostic| _ = offerLine(shared, diagnostic),
        .unknown => |name| _ = offerLine(shared, lineFmt("info string unknown option \"{s}\" ignored", .{name.slice()})),
        .clear_hash => {
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            state.hash.table.clear();
        },
        .move_overhead => |milliseconds| {
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            state.move_overhead_ms = milliseconds;
        },
        .ponder => |enabled| {
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            state.ponder_enabled = enabled;
        },
        .threads => |count| {
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            state.resizeThreads(count) catch {
                _ = offerText(shared, "info string failed setoption: Threads resource allocation failed");
                return;
            };
        },
        .search_param => |update| {
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            state.search_params.set(update.id, update.value);
        },
        .time_param => |update| {
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            state.time_params.set(update.id, update.value);
        },
        .syzygy_probe_depth => |depth| {
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            state.syzygy_probe_depth = depth;
        },
        .syzygy_probe_limit => |limit| {
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            state.syzygy_probe_limit = limit;
        },
        .syzygy_fifty_move_rule => |honour| {
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            state.syzygy_fifty_move_rule = honour;
        },
        .syzygy_path => |path| {
            // Fathom initialization is not thread safe, so the handle is
            // replaced only with no search active, exactly like Hash.
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            // The probe library keeps one global generation, so the previous
            // handle must be released before the next is initialized. The
            // reverse order tears down the tables that were just loaded and
            // leaves a handle reporting coverage it no longer has.
            state.tablebase.deinit();
            state.tablebase = engine.syzygy.Handle.init(path.slice()) catch {
                _ = offerText(shared, "info string failed setoption: SyzygyPath could not be loaded");
                return;
            };
            const replacement = state.tablebase;
            if (replacement.largest == 0) {
                _ = offerText(shared, "info string SyzygyPath loaded no tablebase files");
            } else {
                _ = offerLine(shared, lineFmt(
                    "info string SyzygyPath loaded tablebases up to {d} pieces",
                    .{replacement.largest},
                ));
            }
        },
        .hash => |megabytes| {
            if (state.active != null) {
                cancelActive(shared, state);
                finishActive(shared, state, true);
            }
            if (state.fail_next_hash_allocation) {
                state.fail_next_hash_allocation = false;
                _ = offerText(shared, "info string failed setoption: Hash resource allocation failed");
                return;
            }
            const replacement = HashResource.init(state.allocator, megabytes) catch {
                _ = offerText(shared, "info string failed setoption: Hash resource allocation failed");
                return;
            };
            state.hash.deinit(state.allocator);
            state.hash = replacement;
            state.hash_mb = megabytes;
        },
    }
}

/// A filesystem path carried verbatim. `protocol.Sanitized` must not be used
/// here: it is a diagnostic escaper that rewrites a backslash as `\` and
/// truncates at 256 bytes, which corrupts every native Windows path and
/// silently loads the wrong directory.
const SyzygyPath = struct {
    len: u16 = 0,
    bytes: [engine.syzygy.max_path_len]u8 = @splat(0),

    fn init(text: []const u8) ?SyzygyPath {
        if (text.len > engine.syzygy.max_path_len) return null;
        var result: SyzygyPath = .{};
        @memcpy(result.bytes[0..text.len], text);
        result.len = @intCast(text.len);
        return result;
    }

    fn slice(self: *const SyzygyPath) []const u8 {
        return self.bytes[0..self.len];
    }
};

const ParsedOption = union(enum) {
    hash: u64,
    threads: u16,
    clear_hash,
    move_overhead: u64,
    ponder: bool,
    syzygy_path: SyzygyPath,
    syzygy_probe_depth: u16,
    syzygy_probe_limit: u8,
    syzygy_fifty_move_rule: bool,
    search_param: struct { id: search.params.Id, value: i32 },
    time_param: struct { id: engine.time.ParamId, value: i32 },
    unknown: protocol.Sanitized,
    invalid: Line,
};

fn parseSetOption(raw: []const u8) ParsedOption {
    var tokens = std.mem.tokenizeAny(u8, raw, " \t");
    _ = tokens.next();
    const name_keyword = tokens.next() orelse return .{ .invalid = lineText("info string invalid setoption: expected name") };
    if (!std.ascii.eqlIgnoreCase(name_keyword, "name")) return .{ .invalid = lineText("info string invalid setoption: expected name") };
    var name_buffer: [protocol.max_diagnostic_bytes]u8 = undefined;
    var name_length: usize = 0;
    var value: ?[]const u8 = null;
    while (tokens.next()) |token| {
        if (std.ascii.eqlIgnoreCase(token, "value")) {
            value = tokens.rest();
            break;
        }
        if (name_length != 0 and name_length < name_buffer.len) {
            name_buffer[name_length] = ' ';
            name_length += 1;
        }
        for (token) |byte| {
            if (name_length == name_buffer.len) break;
            name_buffer[name_length] = std.ascii.toLower(byte);
            name_length += 1;
        }
    }
    if (name_length == 0) return .{ .invalid = lineText("info string invalid setoption: expected name") };
    const name = name_buffer[0..name_length];
    if (options.find(name)) |spec| return parsePublicOption(spec, value);
    if (comptime search.params.tune_enabled) if (search.params.find(name)) |spec| {
        const text = value orelse return .{ .invalid = lineFmt(
            "info string invalid setoption: {s} requires a value",
            .{spec.name},
        ) };
        const parsed = parseSingleUnsigned(text) orelse return .{ .invalid = lineFmt(
            "info string invalid setoption: {s} requires an unsigned integer",
            .{spec.name},
        ) };
        if (parsed > std.math.maxInt(i32) or parsed < @as(u64, @intCast(spec.min)) or
            parsed > @as(u64, @intCast(spec.max))) return .{ .invalid = lineFmt(
            "info string invalid setoption: {s} is outside {d}..{d}",
            .{ spec.name, spec.min, spec.max },
        ) };
        return .{ .search_param = .{ .id = spec.id, .value = @intCast(parsed) } };
    };
    if (comptime engine.time.tune_enabled) if (engine.time.findParam(name)) |spec| {
        const text = value orelse return .{ .invalid = lineFmt(
            "info string invalid setoption: {s} requires a value",
            .{spec.name},
        ) };
        const parsed = parseSingleUnsigned(text) orelse return .{ .invalid = lineFmt(
            "info string invalid setoption: {s} requires an unsigned integer",
            .{spec.name},
        ) };
        if (parsed > std.math.maxInt(i32) or parsed < @as(u64, @intCast(spec.min)) or
            parsed > @as(u64, @intCast(spec.max))) return .{ .invalid = lineFmt(
            "info string invalid setoption: {s} is outside {d}..{d}",
            .{ spec.name, spec.min, spec.max },
        ) };
        return .{ .time_param = .{ .id = spec.id, .value = @intCast(parsed) } };
    };
    return .{ .unknown = protocol.sanitize(name) };
}

fn parsePublicOption(spec: options.Spec, value: ?[]const u8) ParsedOption {
    switch (spec.kind) {
        .button => {
            if (value != null) return .{ .invalid = lineFmt(
                "info string invalid setoption: {s} does not take a value",
                .{spec.name},
            ) };
            return switch (spec.id) {
                .clear_hash => .clear_hash,
                else => unreachable,
            };
        },
        .check => {
            const text = value orelse return .{ .invalid = lineFmt(
                "info string invalid setoption: {s} requires a value",
                .{spec.name},
            ) };
            const trimmed = std.mem.trim(u8, text, &[_]u8{ ' ', '\t' });
            const parsed = if (std.ascii.eqlIgnoreCase(trimmed, "true"))
                true
            else if (std.ascii.eqlIgnoreCase(trimmed, "false"))
                false
            else
                return .{ .invalid = lineFmt(
                    "info string invalid setoption: {s} requires true or false",
                    .{spec.name},
                ) };
            return switch (spec.id) {
                .ponder => .{ .ponder = parsed },
                .syzygy_fifty_move_rule => .{ .syzygy_fifty_move_rule = parsed },
                else => unreachable,
            };
        },
        .spin => |spin| {
            const text = value orelse return .{ .invalid = lineFmt(
                "info string invalid setoption: {s} requires a value",
                .{spec.name},
            ) };
            const parsed = parseSingleUnsigned(text) orelse return .{ .invalid = lineFmt(
                "info string invalid setoption: {s} requires an unsigned integer",
                .{spec.name},
            ) };
            if (parsed < spin.min or parsed > spin.max) return .{ .invalid = lineFmt(
                "info string invalid setoption: {s} is outside {d}..{d}",
                .{ spec.name, spin.min, spin.max },
            ) };
            return switch (spec.id) {
                .hash => .{ .hash = parsed },
                .threads => .{ .threads = @intCast(parsed) },
                .move_overhead => .{ .move_overhead = parsed },
                .syzygy_probe_depth => .{ .syzygy_probe_depth = @intCast(parsed) },
                .syzygy_probe_limit => .{ .syzygy_probe_limit = @intCast(parsed) },
                else => unreachable,
            };
        },
        .string => |default| {
            const text = value orelse return .{ .invalid = lineFmt(
                "info string invalid setoption: {s} requires a value",
                .{spec.name},
            ) };
            const trimmed = std.mem.trim(u8, text, &[_]u8{ ' ', '\t' });
            if (std.mem.eql(u8, trimmed, default)) return .{ .syzygy_path = SyzygyPath.init("").? };
            const path = SyzygyPath.init(trimmed) orelse return .{ .invalid = lineFmt(
                "info string invalid setoption: {s} is too long",
                .{spec.name},
            ) };
            return switch (spec.id) {
                .syzygy_path => .{ .syzygy_path = path },
                else => unreachable,
            };
        },
    }
}

fn startActive(shared: *Shared, state: *ControllerState, job: Job) !void {
    const epoch = try Runtime.start(
        state,
        shared.io,
        &shared.cancel_epoch,
        &shared.ponderhit_epoch,
        &shared.ponderhit_received_ns,
        &shared.controller_wake,
        job,
    );
    shared.active_epoch.store(epoch, .release);
}

fn cancelActive(shared: *Shared, state: *ControllerState) void {
    Runtime.cancel(state, &shared.cancel_epoch);
}

fn isPonderJob(job: Job) bool {
    return switch (job) {
        .normal => |spec| spec.ponder,
        .perft, .bench => false,
    };
}

fn isWaitingPonder(active: *const Runtime.Active, shared: *const Shared) bool {
    return isPonderJob(active.job) and shared.ponderhit_epoch.load(.acquire) != active.epoch;
}

fn drainSearchProgress(shared: *Shared, active: *Runtime.Active) void {
    const progress = active.progress.take(shared.io) orelse return;
    const spec = switch (active.job) {
        .normal => |normal| normal,
        .perft, .bench => return,
    };
    switch (progress) {
        .root_move => |root_move| {
            _ = tryOfferInfoLine(shared, rootMoveInfo(
                root_move.depth,
                root_move.chess_move,
                root_move.number,
                root_move.nodes,
                elapsedMilliseconds(spec.received_ns, root_move.observed_ns),
            ));
        },
        .iteration => |iteration| {
            _ = tryOfferInfoLine(shared, completedIterationInfo(
                iteration.completed,
                iteration.tablebase_hits,
                elapsedMilliseconds(spec.received_ns, iteration.observed_ns),
            ));
            active.last_published_iteration_nodes = iteration.completed.nodes;
        },
    }
}

fn publishRetainedPonderInfo(shared: *Shared, active: *Runtime.Active) void {
    if (active.ponder_completion_waiting) return;
    const spec = active.job.normal;
    const result = active.completion.normal;
    publishFinalSearchInfoIfNeeded(shared, active, spec, result);
    active.ponder_completion_waiting = true;
}

fn finishActive(shared: *Shared, state: *ControllerState, publish: bool) void {
    const active = &state.active.?;
    if (!active.done.isSet()) active.done.waitUncancelable(shared.io);
    if (publish) drainSearchProgress(shared, active) else _ = active.progress.take(shared.io);
    const last_published_iteration_nodes = active.last_published_iteration_nodes;
    const finished = Runtime.finish(state, shared.io);
    switch (finished.job) {
        .bench => {
            state.hash.table.clear();
            state.clearSearchState();
        },
        .normal, .perft => {},
    }
    if (publish) {
        switch (finished.completion) {
            .normal => |result| {
                const spec = finished.job.normal;
                if (last_published_iteration_nodes == null or
                    last_published_iteration_nodes.? != result.nodes)
                {
                    _ = offerLine(shared, searchInfo(
                        result,
                        elapsedMilliseconds(spec.received_ns, monotonicNs(shared.io)),
                    ));
                }
                if (finished.time_telemetry) |telemetry|
                    _ = offerLine(shared, timeTelemetryInfo(telemetry));
                publishBestMove(shared, result);
            },
            .perft => |divide| publishPerft(shared, finished.job.perft, divide),
            .perft_failed => _ = offerText(shared, "info string failed go: perft failed"),
            .bench => |report| publishBench(shared, report),
        }
    }
    shared.active_epoch.store(0, .release);
}

fn timeTelemetryInfo(telemetry: engine.time.Telemetry) Line {
    return lineFmt(
        "info string time optimum_ms {d} maximum_ms {d} root {d} stability {d} score {d} effort {d} smp {d} combined {d} ponder_credit_ns {d} helper_events {d} helpers {d} target_ns {d} reason {s} hard_overshoot_ns {d}",
        .{
            telemetry.allocation.optimum_ms,
            telemetry.allocation.maximum_ms,
            telemetry.factors.root_permille,
            telemetry.factors.stability_permille,
            telemetry.factors.score_permille,
            telemetry.factors.effort_permille,
            telemetry.factors.smp_permille,
            telemetry.factors.combined_permille,
            telemetry.ponder_credit_ns,
            telemetry.helper_instability_events,
            telemetry.helper_count,
            telemetry.target_ns,
            @tagName(telemetry.stop_reason),
            telemetry.hard_overshoot_ns,
        },
    );
}

fn publishFinalSearchInfoIfNeeded(
    shared: *Shared,
    active: *Runtime.Active,
    spec: SearchSpec,
    result: Runtime.SearchResult,
) void {
    if (active.last_published_iteration_nodes != null and
        active.last_published_iteration_nodes.? == result.nodes) return;
    _ = offerLine(shared, searchInfo(
        result,
        elapsedMilliseconds(spec.received_ns, monotonicNs(shared.io)),
    ));
    active.last_published_iteration_nodes = result.nodes;
}

fn publishBench(shared: *Shared, report: engine.bench.Report) void {
    if (report.failed) {
        _ = offerText(shared, "info string bench failed: frozen position could not be prepared");
        return;
    }
    if (report.cancelled) {
        _ = offerLine(shared, lineFmt(
            "info string bench cancelled run {d}/{d} positions {d}/40 nodes {d}",
            .{ report.completed_runs + 1, report.spec.repeats, report.completed_positions, report.current_nodes },
        ));
        return;
    }

    if (report.spec.repeats == 1) {
        for (report.positions, 0..) |record, index| {
            const ebf = fixedDecimal(engine.bench.positionEbfMilli(record), 3);
            if (!offerLine(shared, lineFmt(
                "info string bench position {d}/40 nodes {d} time_ms {d} nps {d} ebf {s}",
                .{ index + 1, record.nodes, record.time_ms, engine.bench.nps(record.nodes, record.time_ms), ebf.slice() },
            ))) return;
        }
        const run_record = report.runs[0];
        const ebf = fixedDecimal(report.geomean_ebf_milli, 3);
        const top_share = fixedDecimal(report.top_share_million, 6);
        _ = offerLine(shared, lineFmt(
            "info string bench total depth {d} repeats 1 threads {d} nodes {d} time_ms {d} nps {d} ebf {s} median_nodes {d} top_share {s}",
            .{ report.spec.depth, report.spec.threads, run_record.nodes, run_record.time_ms, engine.bench.nps(run_record.nodes, run_record.time_ms), ebf.slice(), report.median_nodes, top_share.slice() },
        ));
        return;
    }

    var samples: [engine.bench.max_repeats]u64 = @splat(0);
    for (report.runs[0..report.completed_runs], 0..) |run_record, index| {
        samples[index] = engine.bench.nps(run_record.nodes, run_record.time_ms);
        if (!offerLine(shared, lineFmt(
            "info string bench run {d}/{d} depth {d} threads {d} nodes {d} time_ms {d} nps {d}",
            .{ index + 1, report.spec.repeats, report.spec.depth, report.spec.threads, run_record.nodes, run_record.time_ms, samples[index] },
        ))) return;
    }
    const ordered = samples[0..report.completed_runs];
    std.mem.sort(u64, ordered, {}, std.sort.asc(u64));
    _ = offerLine(shared, lineFmt(
        "info string bench summary depth {d} repeats {d} threads {d} fingerprint_nodes {d} best_nps {d} median_nps {d}",
        .{ report.spec.depth, report.spec.repeats, report.spec.threads, report.fingerprint_nodes, ordered[ordered.len - 1], ordered[ordered.len / 2] },
    ));
}

const FixedDecimal = struct {
    bytes: [32]u8 = @splat(0),
    len: u8 = 0,

    fn slice(self: *const FixedDecimal) []const u8 {
        return self.bytes[0..self.len];
    }
};

fn fixedDecimal(scaled: u64, places: u8) FixedDecimal {
    std.debug.assert(places > 0 and places <= 9);
    var divisor: u64 = 1;
    for (0..places) |_| divisor *= 10;
    var result: FixedDecimal = .{};
    var writer = std.Io.Writer.fixed(&result.bytes);
    writer.print("{d}.", .{scaled / divisor}) catch unreachable;
    var remainder = scaled % divisor;
    var place = places;
    while (place > 0) : (place -= 1) {
        const digit_divisor = std.math.pow(u64, 10, place - 1);
        writer.writeByte(@intCast('0' + remainder / digit_divisor)) catch unreachable;
        remainder %= digit_divisor;
    }
    result.len = @intCast(writer.buffered().len);
    return result;
}

fn publishBestMove(shared: *Shared, result: Runtime.SearchResult) void {
    if (result.best_move) |best| {
        const text = chess.notation.format(best) catch return;
        if (result.completed) |completed| {
            if (completed.pv.length > 1) {
                const ponder = chess.notation.format(completed.pv.moves[1]) catch return;
                _ = offerLine(shared, lineFmt(
                    "bestmove {s} ponder {s}",
                    .{ text.slice(), ponder.slice() },
                ));
                return;
            }
        }
        _ = offerLine(shared, lineFmt("bestmove {s}", .{text.slice()}));
    } else {
        _ = offerText(shared, "bestmove (none)");
    }
}

fn rootMoveInfo(
    depth: u16,
    chess_move: chess.move.Move,
    number: u16,
    nodes: u64,
    elapsed_ms: u64,
) Line {
    const text = chess.notation.format(chess_move) catch @panic("root progress contains a non-chess move");
    return lineFmt(
        "info depth {d} currmove {s} currmovenumber {d} nodes {d} time {d}",
        .{ depth, text.slice(), number, nodes, elapsed_ms },
    );
}

fn completedIterationInfo(
    completed: search.types.CompletedIteration,
    tablebase_hits: u64,
    elapsed_ms: u64,
) Line {
    std.debug.assert(completed.pv.length != 0);
    return searchInfo(.{
        .best_move = completed.pv.moves[0],
        .evidence = completed.evidence,
        .completed = completed,
        .termination = .depth_limit,
        .nodes = completed.nodes,
        .tablebase_hits = tablebase_hits,
        .selective_depth = completed.selective_depth,
    }, elapsed_ms);
}

fn searchInfo(result: Runtime.SearchResult, elapsed_ms: u64) Line {
    const completed_depth: u16 = if (result.completed) |completed| completed.depth else 0;
    if (result.best_move == null) {
        if (result.evidence.value.isMate()) {
            return lineFmt(
                "info depth {d} score mate {d} nodes {d} time {d}",
                .{ completed_depth, mateMoves(result.evidence.value), result.nodes, elapsed_ms },
            );
        }
        return lineFmt(
            "info depth {d} score cp {d} nodes {d} time {d}",
            .{ completed_depth, result.evidence.value.raw(), result.nodes, elapsed_ms },
        );
    }

    var line: Line = .{};
    var writer = std.Io.Writer.fixed(&line.bytes);
    const selective_depth = if (result.completed) |completed| completed.selective_depth else result.selective_depth;
    writer.print("info depth {d} seldepth {d} score ", .{ completed_depth, selective_depth }) catch @panic("search info exceeds its fixed buffer");
    if (result.evidence.value.isMate()) {
        writer.print("mate {d}", .{mateMoves(result.evidence.value)}) catch @panic("search info exceeds its fixed buffer");
    } else {
        writer.print("cp {d}", .{result.evidence.value.raw()}) catch @panic("search info exceeds its fixed buffer");
    }
    switch (result.evidence.bound) {
        .exact => {},
        .lower => writer.writeAll(" lowerbound") catch @panic("search info exceeds its fixed buffer"),
        .upper => writer.writeAll(" upperbound") catch @panic("search info exceeds its fixed buffer"),
    }
    const nps = if (elapsed_ms == 0) result.nodes *| 1000 else (result.nodes *| 1000) / elapsed_ms;
    writer.print(" nodes {d} time {d} nps {d}", .{ result.nodes, elapsed_ms, nps }) catch @panic("search info exceeds its fixed buffer");
    // `tbhits` is emitted only when tablebases actually contributed, so a
    // deployment without them produces byte-identical output to before.
    if (result.tablebase_hits != 0) {
        writer.print(" tbhits {d}", .{result.tablebase_hits}) catch @panic("search info exceeds its fixed buffer");
    }
    writer.writeAll(" pv") catch @panic("search info exceeds its fixed buffer");
    if (result.completed) |completed| {
        for (completed.pv.slice()) |chess_move| {
            const text = chess.notation.format(chess_move) catch continue;
            writer.print(" {s}", .{text.slice()}) catch break;
        }
    } else if (result.best_move) |best| {
        const text = chess.notation.format(best) catch @panic("search published a non-chess move");
        writer.print(" {s}", .{text.slice()}) catch @panic("search info exceeds its fixed buffer");
    }
    line.len = @intCast(writer.buffered().len);
    return line;
}

fn publishPerft(shared: *Shared, depth: u16, divide_value: chess.perft.Divide) void {
    var divide = divide_value;
    sortDivide(&divide);
    for (divide.slice()) |entry| {
        const text = chess.notation.format(entry.chess_move) catch continue;
        if (!offerLine(shared, lineFmt(
            "info string perft move {s} nodes {d}",
            .{ text.slice(), entry.nodes },
        ))) return;
    }
    if (divide.completed) {
        _ = offerLine(shared, lineFmt("info string perft depth {d} nodes {d}", .{ depth, divide.total }));
    } else {
        _ = offerLine(shared, lineFmt(
            "info string perft depth {d} nodes {d} cancelled true",
            .{ depth, divide.total },
        ));
    }
}

fn sortDivide(divide: *chess.perft.Divide) void {
    var index: usize = 1;
    while (index < divide.count) : (index += 1) {
        const entry = divide.entries[index];
        var cursor = index;
        while (cursor > 0 and moveLess(entry.chess_move, divide.entries[cursor - 1].chess_move)) : (cursor -= 1) {
            divide.entries[cursor] = divide.entries[cursor - 1];
        }
        divide.entries[cursor] = entry;
    }
}

fn moveLess(lhs: chess.move.Move, rhs: chess.move.Move) bool {
    const lhs_text = chess.notation.format(lhs) catch return false;
    const rhs_text = chess.notation.format(rhs) catch return false;
    return std.mem.lessThan(u8, lhs_text.slice(), rhs_text.slice());
}

fn parseUnsigned(text: []const u8) ?u64 {
    if (text.len == 0) return null;
    for (text) |byte| if (!std.ascii.isDigit(byte)) return null;
    return std.fmt.parseInt(u64, text, 10) catch null;
}

fn parseSingleUnsigned(text: []const u8) ?u64 {
    var tokens = std.mem.tokenizeAny(u8, text, " \t");
    const value = tokens.next() orelse return null;
    if (tokens.next() != null) return null;
    return parseUnsigned(value);
}

fn monotonicNs(io: std.Io) u64 {
    const value = std.Io.Clock.awake.now(io).nanoseconds;
    if (value <= 0) return 0;
    return @intCast(@min(value, std.math.maxInt(u64)));
}

fn elapsedMilliseconds(received_ns: u64, completed_ns: u64) u64 {
    return (completed_ns -| received_ns) / std.time.ns_per_ms;
}

fn mateMoves(value: score.Score) i32 {
    const plies = value.mateDistance().?;
    return if (plies >= 0) @divTrunc(plies + 1, 2) else @divTrunc(plies, 2);
}

fn optionDeclaration(spec: options.Spec) Line {
    return switch (spec.kind) {
        .spin => |spin| lineFmt(
            "option name {s} type spin default {d} min {d} max {d}",
            .{ spec.name, spin.default, spin.min, spin.max },
        ),
        .check => |default| lineFmt(
            "option name {s} type check default {s}",
            .{ spec.name, if (default) "true" else "false" },
        ),
        .button => lineFmt("option name {s} type button", .{spec.name}),
        .string => |default| lineFmt(
            "option name {s} type string default {s}",
            .{ spec.name, default },
        ),
    };
}

fn lineText(text: []const u8) Line {
    std.debug.assert(text.len <= max_output_bytes);
    var result: Line = .{ .len = @intCast(text.len) };
    @memcpy(result.bytes[0..text.len], text);
    return result;
}

fn lineFmt(comptime format: []const u8, args: anytype) Line {
    var result: Line = .{};
    var writer = std.Io.Writer.fixed(&result.bytes);
    writer.print(format, args) catch @panic("protocol line exceeds its fixed buffer");
    result.len = @intCast(writer.buffered().len);
    return result;
}

fn offerText(shared: *Shared, text: []const u8) bool {
    return offerLine(shared, lineText(text));
}

fn offerLine(shared: *Shared, line: Line) bool {
    shared.output.putOne(shared.io, .{ .line = line }) catch return false;
    return true;
}

/// Live search progress is advisory and may be superseded. Never let it fill
/// the bounded presenter queue at the expense of a required response such as
/// `bestmove`; the worker/controller progress slot will publish a newer sample.
fn tryOfferInfoLine(shared: *Shared, line: Line) bool {
    const accepted = shared.output.put(shared.io, &.{.{ .line = line }}, 0) catch return false;
    return accepted == 1;
}

fn presenter(shared: *Shared) std.Io.Cancelable!void {
    defer shared.presenter_done.set(shared.io);
    var write_buffer: [max_output_bytes]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(shared.io, &write_buffer);
    const writer = &file_writer.interface;
    while (true) {
        const event = shared.output.getOne(shared.io) catch |err| switch (err) {
            error.Closed => return,
            error.Canceled => return error.Canceled,
        };
        switch (event) {
            .startup => |flushed| {
                writer.print("Manta {s} by Miloslav Macurek\n", .{shared.version}) catch return presenterFailed(shared, &file_writer);
                writer.flush() catch return presenterFailed(shared, &file_writer);
                flushed.set(shared.io);
            },
            .line => |line| {
                writer.print("{s}\n", .{line.slice()}) catch return presenterFailed(shared, &file_writer);
                writer.flush() catch return presenterFailed(shared, &file_writer);
            },
        }
    }
}

fn presenterFailed(shared: *Shared, file_writer: *std.Io.File.Writer) std.Io.Cancelable!void {
    if (file_writer.err) |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => {},
    };
    shared.fatal.store(true, .release);
    urgentCancel(shared);
    shared.shutdown.set(shared.io);
}

fn drainCommands(shared: *Shared) void {
    var buffer: [1]protocol.Command = undefined;
    while (true) {
        const count = shared.commands.get(shared.io, &buffer, 0) catch return;
        if (count == 0) return;
        if (buffer[0].raw) |raw| shared.allocator.free(raw);
    }
}

fn timeoutMs(milliseconds: i64) std.Io.Timeout {
    return .{ .duration = .{ .raw = .fromMilliseconds(milliseconds), .clock = .awake } };
}

test "go parsing rejects conflicting modes and preserves root restriction order" {
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parseStart(&root);
    try std.testing.expect(parseGo(&position, "go", 0, false) == .invalid);
    try std.testing.expect(parseGo(&position, "go movetime 10 wtime 100", 0, false) == .invalid);
    const parsed = parseGo(&position, "go depth 2 searchmoves e2e4 d2d4 e2e4", 7, false);
    const spec = parsed.job.normal;
    try std.testing.expect(spec.restricted);
    try std.testing.expectEqual(@as(usize, 2), spec.root_moves.count);
    try std.testing.expectEqual(@as(u16, 20), spec.legal_root_move_count);
    try std.testing.expectEqual(chess.move.Move.normal(.e2, .e4), spec.root_moves.slice()[0]);
}

test "go numeric and clock validation is transactional at u64 boundaries" {
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parseStart(&root);
    try std.testing.expect(parseGo(&position, "go nodes 0", 0, false) == .invalid);
    try std.testing.expect(parseGo(&position, "go depth 2 depth 3", 0, false) == .invalid);
    try std.testing.expect(parseGo(&position, "go nodes 18446744073709551616", 0, false) == .invalid);
    try std.testing.expect(parseGo(&position, "go btime 1000", 0, false) == .invalid);
    const zero_clock = parseGo(&position, "go wtime 0 btime 0", 11, false).job.normal;
    try std.testing.expectEqual(@as(u64, 0), zero_clock.time_input.?.clock.remaining_ms);
    try std.testing.expectEqual(@as(u64, 0), zero_clock.time_input.?.clock.game_ply);
    try std.testing.expectEqual(@as(u64, 11), zero_clock.received_ns);
    const clamped = parseGo(&position, "go depth 999999", 0, false).job.normal;
    try std.testing.expectEqual(@as(u16, chess.types.max_ply - 1), clamped.limits.depth);
}

test "ponder parsing requires the active option and a game clock" {
    // UCI-005: ponder is a clock mode, not an alias for infinite or movetime.
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parseStart(&root);
    try std.testing.expect(parseGo(&position, "go ponder wtime 1000 btime 1000", 9, false) == .invalid);
    try std.testing.expect(parseGo(&position, "go ponder depth 2", 9, true) == .invalid);
    try std.testing.expect(parseGo(&position, "go ponder movetime 10", 9, true) == .invalid);
    const parsed = parseGo(&position, "go ponder wtime 1000 btime 1000 depth 2", 9, true).job.normal;
    try std.testing.expect(parsed.ponder);
    try std.testing.expectEqual(@as(u64, 9), parsed.received_ns);
    try std.testing.expect(parsed.time_input != null);
}

test "bench parsing freezes defaults, semantic caps, and one-thread scope" {
    const defaults = parseBench("bench").spec;
    try std.testing.expectEqual(engine.bench.default_depth, defaults.depth);
    try std.testing.expectEqual(@as(u16, 1), defaults.repeats);
    try std.testing.expectEqual(@as(u16, 1), defaults.threads);
    try std.testing.expectEqual(@as(u16, 5), parseBench("bench 5 2 1").spec.depth);
    try std.testing.expect(parseBench("bench 0") == .invalid);
    try std.testing.expect(parseBench("bench 1 17") == .invalid);
    try std.testing.expect(parseBench("bench 1 1 2") == .invalid);
    try std.testing.expect(parseBench("bench 1 1 1 extra") == .invalid);
}

test "setoption registry normalizes names and enforces active ranges" {
    try std.testing.expectEqual(@as(u64, 128), parseSetOption("setoption name hAsH value 128").hash);
    try std.testing.expectEqual(@as(u16, 4), parseSetOption("setoption name Threads value 4").threads);
    try std.testing.expect(parseSetOption("setoption name Threads value 0") == .invalid);
    try std.testing.expect(parseSetOption("setoption name Threads value 1025") == .invalid);
    try std.testing.expect(parseSetOption("setoption name Hash value 0") == .invalid);
    try std.testing.expect(parseSetOption("setoption name Clear Hash value now") == .invalid);
    try std.testing.expectEqual(@as(u64, 5000), parseSetOption("setoption name move   overhead value 5000").move_overhead);
    try std.testing.expect(parseSetOption("setoption name pOnDeR value TRUE").ponder);
    try std.testing.expect(!parseSetOption("setoption name Ponder value false").ponder);
    try std.testing.expect(parseSetOption("setoption name Ponder value maybe") == .invalid);
    try std.testing.expect(parseSetOption("setoption name Future Knob value 1") == .unknown);
    if (comptime search.params.tune_enabled) {
        const tuned = parseSetOption("setoption name probcutmargin value 125").search_param;
        try std.testing.expectEqual(search.params.Id.probcut_margin, tuned.id);
        try std.testing.expectEqual(@as(i32, 125), tuned.value);
        try std.testing.expect(parseSetOption("setoption name ProbCutMargin value 301") == .invalid);
        try std.testing.expect(parseSetOption("setoption name ProbCutMargin value noise") == .invalid);
    } else {
        try std.testing.expect(parseSetOption("setoption name ProbCutMargin value 125") == .unknown);
    }
    if (comptime engine.time.tune_enabled) {
        const tuned = parseSetOption("setoption name timeeffortresponse value 1250").time_param;
        try std.testing.expectEqual(engine.time.ParamId.effort_response, tuned.id);
        try std.testing.expectEqual(@as(i32, 1250), tuned.value);
        try std.testing.expect(parseSetOption("setoption name TimeEffortResponse value 2001") == .invalid);
    } else {
        try std.testing.expect(parseSetOption("setoption name TimeEffortResponse value 1250") == .unknown);
    }
}

test "live root information has the bounded UCI field contract" {
    // UCI-001/FUNC-004: reporting formats a legal encoded root move and the
    // same bounded node/time snapshot without touching the position.
    const line = rootMoveInfo(4, chess.move.Move.normal(.e2, .e4), 3, 99, 7);
    try std.testing.expectEqualStrings(
        "info depth 4 currmove e2e4 currmovenumber 3 nodes 99 time 7",
        line.slice(),
    );
}

test "SyzygyPath preserves a whole path and spells unloading as <empty>" {
    // A tablebase path routinely contains spaces and platform separators, so
    // the value is the remainder of the line rather than a single token.
    // Splitting it would silently load the wrong directory or none at all.
    const spaced = parseSetOption("setoption name SyzygyPath value D:/chess/table bases/syzygy 345");
    try std.testing.expectEqualStrings("D:/chess/table bases/syzygy 345", spaced.syzygy_path.slice());
    const single = parseSetOption("setoption name syzygypath value /opt/syzygy");
    try std.testing.expectEqualStrings("/opt/syzygy", single.syzygy_path.slice());
    // UCI has no way to send an empty string, so `<empty>` is the unload token.
    try std.testing.expectEqualStrings("", parseSetOption("setoption name SyzygyPath value <empty>").syzygy_path.slice());
    try std.testing.expect(parseSetOption("setoption name SyzygyPath") == .invalid);
}

test "SyzygyPath survives a native Windows path unchanged" {
    // The value must reach the probe layer byte for byte. Routing it through
    // the diagnostic sanitizer would rewrite every backslash as a pair and cap
    // the path at 256 bytes, so a normal Windows path would silently load the
    // wrong directory or none at all.
    const windows = "setoption name SyzygyPath value D:\\chess\\tablebases\\syzygy3456";
    try std.testing.expectEqualStrings(
        "D:\\chess\\tablebases\\syzygy3456",
        parseSetOption(windows).syzygy_path.slice(),
    );
    // A path with spaces is also preserved whole rather than split or escaped.
    try std.testing.expectEqualStrings(
        "C:\\Program Files\\tb",
        parseSetOption("setoption name SyzygyPath value C:\\Program Files\\tb").syzygy_path.slice(),
    );
    // A path longer than the adapter accepts is refused rather than truncated.
    const long_value = "setoption name SyzygyPath value " ++ ("x" ** (engine.syzygy.max_path_len + 1));
    try std.testing.expect(parseSetOption(long_value) == .invalid);
}

test "SyzygyProbeDepth rejects values outside its advertised range" {
    // Spin values outside the advertised range are rejected, never clamped.
    try std.testing.expectEqual(@as(u16, 1), parseSetOption("setoption name SyzygyProbeDepth value 1").syzygy_probe_depth);
    try std.testing.expectEqual(@as(u16, 100), parseSetOption("setoption name syzygyprobedepth value 100").syzygy_probe_depth);
    try std.testing.expect(parseSetOption("setoption name SyzygyProbeDepth value 0") == .invalid);
    try std.testing.expect(parseSetOption("setoption name SyzygyProbeDepth value 101") == .invalid);
    try std.testing.expect(parseSetOption("setoption name SyzygyProbeDepth value deep") == .invalid);
    try std.testing.expect(parseSetOption("setoption name SyzygyProbeDepth") == .invalid);
}

test "position preparation is transactional and reports the offending move" {
    const allocator = std.testing.allocator;
    const invalid = try preparePosition(allocator, "position startpos moves e2e5");
    try std.testing.expect(invalid == .invalid);
    const prepared = try preparePosition(allocator, "position startpos moves e2e4 e7e5");
    var game = prepared.game;
    defer game.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), game.moves.len);
    try std.testing.expect(chess.state.isConsistent(&game.position));
}

test "mate output converts signed plies to UCI moves" {
    try std.testing.expectEqual(@as(i32, 2), mateMoves(score.Score.mateIn(3).?));
    try std.testing.expectEqual(@as(i32, -1), mateMoves(score.Score.matedIn(3).?));
    try std.testing.expectEqual(@as(i32, 0), mateMoves(score.Score.matedIn(0).?));
}

comptime {
    std.debug.assert(command_capacity > 0);
    std.debug.assert(output_capacity > 32);
    std.debug.assert(max_output_bytes >= protocol.max_diagnostic_bytes);
}
