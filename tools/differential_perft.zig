//! Compares Manta divide maps with a runtime-supplied UCI oracle executable.
//! The executable and generated campaign data remain local development inputs.
const std = @import("std");
const manta = @import("manta");

const chess = manta.chess;
const default_positions = 1_000;
const default_depth = 3;
const default_seed: u64 = 0x6d61_6e74_615f_6469;
const max_positions = 100_000;
const max_depth = 6;
const max_line_bytes = 4096;

const roots = [_][]const u8{
    chess.fen.start_position,
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
    "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
    "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
    "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
    "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
    "1r5k/P7/8/8/8/8/8/7K w - - 0 1",
};

const Options = struct {
    oracle: []const u8,
    positions: usize = default_positions,
    depth: u16 = default_depth,
    seed: u64 = default_seed,
};

const MoveText = struct {
    bytes: [5]u8 = @splat(0),
    len: u3,

    fn init(text: []const u8) !MoveText {
        if (text.len != 4 and text.len != 5) return error.InvalidOracleMove;
        if (text[0] < 'a' or text[0] > 'h' or text[1] < '1' or text[1] > '8' or
            text[2] < 'a' or text[2] > 'h' or text[3] < '1' or text[3] > '8')
        {
            return error.InvalidOracleMove;
        }
        if (text.len == 5 and text[4] != 'n' and text[4] != 'b' and
            text[4] != 'r' and text[4] != 'q') return error.InvalidOracleMove;
        var result = MoveText{ .len = @intCast(text.len) };
        @memcpy(result.bytes[0..text.len], text);
        return result;
    }

    fn slice(self: *const MoveText) []const u8 {
        return self.bytes[0..self.len];
    }
};

const Entry = struct {
    move_text: MoveText,
    nodes: u64,
};

const OracleDivide = struct {
    entries: [chess.types.move_capacity]Entry = undefined,
    count: u16 = 0,
    total: u64 = 0,

    fn append(self: *OracleDivide, entry: Entry) !void {
        if (self.count == self.entries.len) return error.TooManyOracleMoves;
        for (self.entries[0..self.count]) |existing| {
            if (std.mem.eql(u8, existing.move_text.slice(), entry.move_text.slice())) {
                return error.DuplicateOracleMove;
            }
        }
        self.entries[self.count] = entry;
        self.count += 1;
    }
};

const Rng = struct {
    state: u64,

    fn next(self: *Rng) u64 {
        var value = self.state;
        value ^= value >> 12;
        value ^= value << 25;
        value ^= value >> 27;
        self.state = value;
        return value *% 0x2545_F491_4F6C_DD1D;
    }

    fn below(self: *Rng, limit: usize) usize {
        std.debug.assert(limit != 0);
        return @intCast(self.next() % limit);
    }
};

pub fn main(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const options = parseOptions(args) catch |err| {
        std.debug.print("differential perft: {s}\n", .{@errorName(err)});
        printUsage();
        return 2;
    };
    run(init.io, options) catch |err| {
        std.debug.print("differential perft: FAIL ({s})\n", .{@errorName(err)});
        return 1;
    };
    return 0;
}

fn run(io: std.Io, options: Options) !void {
    var child = try std.process.spawn(io, .{
        .argv = &.{options.oracle},
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .inherit,
        .create_no_window = true,
    });
    defer child.kill(io);

    var input_buffer: [4096]u8 = undefined;
    var input_writer = child.stdin.?.writer(io, &input_buffer);
    var output_buffer: [max_line_bytes + 1]u8 = undefined;
    var output_reader = child.stdout.?.reader(io, &output_buffer);
    const writer = &input_writer.interface;
    const reader = &output_reader.interface;

    try send(writer, "uci\n", .{});
    try awaitExact(reader, "uciok");
    try send(writer, "isready\n", .{});
    try awaitExact(reader, "readyok");

    var rng = Rng{ .state = options.seed };
    var compared_nodes: u64 = 0;
    for (0..options.positions) |index| {
        var root: chess.position.PositionState = .{};
        var value = try chess.fen.parse(roots[index % roots.len], &root);
        var history_states: [96]chess.position.PositionState = undefined;
        const target_plies = 4 + rng.below(history_states.len - 3);
        for (history_states[0..target_plies]) |*child_state| {
            var legal = chess.position.MoveList.init();
            chess.movegen.generate(.all, &value, &legal);
            if (legal.count == 0) break;
            const selected = legal.slice()[rng.below(legal.count)];
            chess.transition.makeMove(&value, selected, child_state);
        }
        if (!chess.state.isConsistent(&value)) return error.InconsistentGeneratedPosition;

        var fen_buffer: [chess.fen.max_length]u8 = undefined;
        const fen_text = try chess.fen.write(&value, &fen_buffer);
        var perft_states: [chess.types.max_ply]chess.position.PositionState = undefined;
        const manta_divide = try chess.perft.divide(
            &value,
            options.depth,
            &perft_states,
        );
        const oracle_divide = try queryOracle(writer, reader, fen_text, options.depth);
        compareDivide(fen_text, &manta_divide, &oracle_divide) catch |err| {
            std.debug.print(
                "differential mismatch: index={d} seed=0x{x} depth={d}\nFEN: {s}\n",
                .{ index, options.seed, options.depth, fen_text },
            );
            printDivide("Manta", &manta_divide);
            printOracleDivide(&oracle_divide);
            return err;
        };
        compared_nodes = std.math.add(u64, compared_nodes, manta_divide.total) catch
            return error.NodeCountOverflow;

        if ((index + 1) % 100 == 0 or index + 1 == options.positions) {
            std.debug.print(
                "differential perft: {d}/{d} positions, {d} leaves\n",
                .{ index + 1, options.positions, compared_nodes },
            );
        }
    }

    try send(writer, "quit\n", .{});
    child.stdin.?.close(io);
    child.stdin = null;
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.OracleFailed,
        else => return error.OracleFailed,
    }
    std.debug.print(
        "differential perft: PASS positions={d} depth={d} seed=0x{x} leaves={d}\n",
        .{ options.positions, options.depth, options.seed, compared_nodes },
    );
}

fn queryOracle(
    writer: *std.Io.Writer,
    reader: *std.Io.Reader,
    fen_text: []const u8,
    depth: u16,
) !OracleDivide {
    try send(writer, "position fen {s}\ngo perft {d}\n", .{ fen_text, depth });
    var result = OracleDivide{};
    while (try nextLine(reader)) |line| {
        if (parseCompletion(line)) |total| {
            result.total = total;
            return result;
        }
        if (try parseEntry(line)) |entry| try result.append(entry);
    }
    return error.UnexpectedOracleExit;
}

fn compareDivide(
    fen_text: []const u8,
    manta_divide: *const chess.perft.Divide,
    oracle_divide: *const OracleDivide,
) !void {
    _ = fen_text;
    if (manta_divide.total != oracle_divide.total or
        manta_divide.count != oracle_divide.count) return error.DifferentialMismatch;

    for (manta_divide.slice()) |manta_entry| {
        const formatted = try chess.notation.format(manta_entry.chess_move);
        var found = false;
        for (oracle_divide.entries[0..oracle_divide.count]) |oracle_entry| {
            if (!std.mem.eql(u8, formatted.slice(), oracle_entry.move_text.slice())) continue;
            if (manta_entry.nodes != oracle_entry.nodes) return error.DifferentialMismatch;
            found = true;
            break;
        }
        if (!found) return error.DifferentialMismatch;
    }
}

fn parseEntry(line: []const u8) !?Entry {
    if (std.mem.startsWith(u8, line, "info string perft move ")) {
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        if (!std.mem.eql(u8, tokens.next() orelse return null, "info")) return null;
        if (!std.mem.eql(u8, tokens.next() orelse return null, "string")) return null;
        if (!std.mem.eql(u8, tokens.next() orelse return null, "perft")) return null;
        if (!std.mem.eql(u8, tokens.next() orelse return null, "move")) return null;
        const move_text = tokens.next() orelse return error.InvalidOracleOutput;
        if (!std.mem.eql(u8, tokens.next() orelse return error.InvalidOracleOutput, "nodes")) {
            return error.InvalidOracleOutput;
        }
        const nodes_text = tokens.next() orelse return error.InvalidOracleOutput;
        if (tokens.next() != null) return error.InvalidOracleOutput;
        return .{
            .move_text = try MoveText.init(move_text),
            .nodes = try parseUnsigned(nodes_text),
        };
    }

    const colon = std.mem.indexOfScalar(u8, line, ':') orelse return null;
    const move_text = std.mem.trim(u8, line[0..colon], " \t");
    if (move_text.len != 4 and move_text.len != 5) return null;
    const nodes_text = std.mem.trim(u8, line[colon + 1 ..], " \t");
    return .{
        .move_text = MoveText.init(move_text) catch return null,
        .nodes = try parseUnsigned(nodes_text),
    };
}

fn parseCompletion(line: []const u8) ?u64 {
    const common = "Nodes searched:";
    if (std.mem.startsWith(u8, line, common)) {
        return parseUnsigned(std.mem.trim(u8, line[common.len..], " \t")) catch null;
    }
    const manta_prefix = "info string perft depth ";
    if (!std.mem.startsWith(u8, line, manta_prefix)) return null;
    var tokens = std.mem.tokenizeScalar(u8, line[manta_prefix.len..], ' ');
    _ = tokens.next() orelse return null;
    if (!std.mem.eql(u8, tokens.next() orelse return null, "nodes")) return null;
    const total = parseUnsigned(tokens.next() orelse return null) catch return null;
    if (tokens.next() != null) return null;
    return total;
}

fn parseUnsigned(text: []const u8) !u64 {
    if (text.len == 0) return error.InvalidOracleOutput;
    return std.fmt.parseInt(u64, text, 10) catch error.InvalidOracleOutput;
}

fn nextLine(reader: *std.Io.Reader) !?[]const u8 {
    const raw = reader.takeDelimiter('\n') catch |err| switch (err) {
        error.StreamTooLong => return error.OracleLineTooLong,
        error.ReadFailed => return error.OracleReadFailed,
    };
    const line = raw orelse return null;
    return if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;
}

fn awaitExact(reader: *std.Io.Reader, expected: []const u8) !void {
    while (try nextLine(reader)) |line| {
        if (std.mem.eql(u8, line, expected)) return;
    }
    return error.UnexpectedOracleExit;
}

fn send(writer: *std.Io.Writer, comptime format: []const u8, args: anytype) !void {
    try writer.print(format, args);
    try writer.flush();
}

fn parseOptions(args: []const []const u8) !Options {
    var result: Options = undefined;
    result.positions = default_positions;
    result.depth = default_depth;
    result.seed = default_seed;
    var oracle: ?[]const u8 = null;
    var index: usize = 1;
    while (index < args.len) {
        const flag = args[index];
        index += 1;
        if (index == args.len) return error.MissingOptionValue;
        const value = args[index];
        index += 1;
        if (std.mem.eql(u8, flag, "--oracle")) {
            if (oracle != null or value.len == 0) return error.InvalidOracle;
            oracle = value;
        } else if (std.mem.eql(u8, flag, "--positions")) {
            result.positions = std.fmt.parseInt(usize, value, 10) catch
                return error.InvalidPositions;
            if (result.positions == 0 or result.positions > max_positions) {
                return error.InvalidPositions;
            }
        } else if (std.mem.eql(u8, flag, "--depth")) {
            result.depth = std.fmt.parseInt(u16, value, 10) catch return error.InvalidDepth;
            if (result.depth == 0 or result.depth > max_depth) return error.InvalidDepth;
        } else if (std.mem.eql(u8, flag, "--seed")) {
            result.seed = std.fmt.parseInt(u64, value, 0) catch return error.InvalidSeed;
            if (result.seed == 0) return error.InvalidSeed;
        } else {
            return error.UnknownOption;
        }
    }
    result.oracle = oracle orelse return error.MissingOracle;
    return result;
}

fn printDivide(label: []const u8, divide_result: *const chess.perft.Divide) void {
    std.debug.print("{s}: total={d} moves={d}\n", .{ label, divide_result.total, divide_result.count });
    for (divide_result.slice()) |entry| {
        const text = chess.notation.format(entry.chess_move) catch continue;
        std.debug.print("  {s}: {d}\n", .{ text.slice(), entry.nodes });
    }
}

fn printOracleDivide(divide_result: *const OracleDivide) void {
    std.debug.print("Oracle: total={d} moves={d}\n", .{ divide_result.total, divide_result.count });
    for (divide_result.entries[0..divide_result.count]) |entry| {
        std.debug.print("  {s}: {d}\n", .{ entry.move_text.slice(), entry.nodes });
    }
}

fn printUsage() void {
    std.debug.print(
        "usage: zig build differential-perft -- --oracle <executable> " ++
            "[--positions 1000] [--depth 3] [--seed 0x6d616e74615f6469]\n",
        .{},
    );
}

test "oracle output accepts common and Manta divide records" {
    const common = (try parseEntry("e2e4: 20")).?;
    try std.testing.expectEqualStrings("e2e4", common.move_text.slice());
    try std.testing.expectEqual(@as(u64, 20), common.nodes);
    const manta_entry = (try parseEntry("info string perft move a7a8q nodes 17")).?;
    try std.testing.expectEqualStrings("a7a8q", manta_entry.move_text.slice());
    try std.testing.expectEqual(@as(u64, 17), manta_entry.nodes);
    try std.testing.expect((try parseEntry("info: ignored diagnostic")) == null);
    try std.testing.expectEqual(@as(u64, 400), parseCompletion("Nodes searched: 400").?);
    try std.testing.expectEqual(
        @as(u64, 400),
        parseCompletion("info string perft depth 2 nodes 400").?,
    );
}

test "campaign options are explicit and bounded" {
    const options = try parseOptions(&.{
        "tool",
        "--oracle",
        "engine",
        "--positions",
        "25",
        "--depth",
        "2",
        "--seed",
        "17",
    });
    try std.testing.expectEqualStrings("engine", options.oracle);
    try std.testing.expectEqual(@as(usize, 25), options.positions);
    try std.testing.expectEqual(@as(u16, 2), options.depth);
    try std.testing.expectEqual(@as(u64, 17), options.seed);
    try std.testing.expectError(error.MissingOracle, parseOptions(&.{"tool"}));
    try std.testing.expectError(error.InvalidDepth, parseOptions(&.{
        "tool",
        "--oracle",
        "engine",
        "--depth",
        "7",
    }));
}
