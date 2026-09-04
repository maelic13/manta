//! Checked, allocation-free legal leaf counting and root divide.
const std = @import("std");
const builtin = @import("builtin");
const fen = @import("fen.zig");
const move = @import("move.zig");
const movegen = @import("movegen.zig");
const position = @import("position.zig");
const state = @import("state.zig");
const transition = @import("transition.zig");
const types = @import("types.zig");

pub const Error = error{
    DepthTooLarge,
    InsufficientStateStorage,
    NodeCountOverflow,
};

pub const Outcome = struct {
    nodes: u64,
    completed: bool,
};

pub const DivideEntry = struct {
    chess_move: move.Move,
    nodes: u64,
};

pub const Divide = struct {
    entries: [types.move_capacity]DivideEntry,
    count: u16 = 0,
    total: u64 = 0,
    completed: bool = true,

    pub fn init() Divide {
        return .{ .entries = undefined };
    }

    pub fn slice(self: *const Divide) []const DivideEntry {
        return self.entries[0..self.count];
    }
};

/// Compile-time-specialized no-cancellation policy used by deterministic
/// tests and benchmarks. Later adapters can supply a type with the same
/// `shouldStop(*T) bool` method without importing control-plane concerns here.
pub const NeverStop = struct {
    pub inline fn shouldStop(_: *NeverStop) bool {
        return false;
    }
};

/// Counts legal leaves and restores `value` exactly before returning.
pub fn count(
    value: *position.Position,
    depth: u16,
    state_storage: []position.PositionState,
) Error!u64 {
    var control: NeverStop = .{};
    const outcome = try countControlled(value, depth, state_storage, &control);
    std.debug.assert(outcome.completed);
    return outcome.nodes;
}

/// The control type is statically dispatched and must provide
/// `shouldStop(*Control) bool`. Cancellation returns the number of completed
/// leaf subtrees reached so far and always restores the input position.
pub fn countControlled(
    value: *position.Position,
    depth: u16,
    state_storage: []position.PositionState,
    control: anytype,
) Error!Outcome {
    try validateStorage(depth, state_storage.len);
    return recurse(value, depth, state_storage, 0, control);
}

/// Produces one completed record per root move. If cancellation interrupts a
/// root subtree, that incomplete record is omitted and `completed` is false.
pub fn divide(
    value: *position.Position,
    depth: u16,
    state_storage: []position.PositionState,
) Error!Divide {
    var control: NeverStop = .{};
    const result = try divideControlled(value, depth, state_storage, &control);
    std.debug.assert(result.completed);
    return result;
}

pub fn divideControlled(
    value: *position.Position,
    depth: u16,
    state_storage: []position.PositionState,
    control: anytype,
) Error!Divide {
    try validateStorage(depth, state_storage.len);
    var result = Divide.init();
    if (control.shouldStop()) {
        result.completed = false;
        return result;
    }
    if (depth == 0) {
        result.total = 1;
        return result;
    }

    var legal = position.MoveList.init();
    movegen.generate(.all, value, &legal);
    for (legal.slice()) |chess_move| {
        transition.makeMove(value, chess_move, &state_storage[0]);
        const child = recurse(value, depth - 1, state_storage, 1, control) catch |err| {
            transition.unmakeMove(value, chess_move);
            return err;
        };
        transition.unmakeMove(value, chess_move);
        if (!child.completed) {
            result.completed = false;
            return result;
        }

        result.total = try addNodes(result.total, child.nodes);
        std.debug.assert(result.count < result.entries.len);
        result.entries[result.count] = .{ .chess_move = chess_move, .nodes = child.nodes };
        result.count += 1;
    }
    return result;
}

fn recurse(
    value: *position.Position,
    depth: u16,
    state_storage: []position.PositionState,
    ply: usize,
    control: anytype,
) Error!Outcome {
    if (control.shouldStop()) return .{ .nodes = 0, .completed = false };
    if (depth == 0) return .{ .nodes = 1, .completed = true };

    var legal = position.MoveList.init();
    movegen.generate(.all, value, &legal);
    if (depth == 1) return .{ .nodes = legal.count, .completed = true };

    var nodes: u64 = 0;
    for (legal.slice()) |chess_move| {
        transition.makeMove(value, chess_move, &state_storage[ply]);
        const child = recurse(value, depth - 1, state_storage, ply + 1, control) catch |err| {
            transition.unmakeMove(value, chess_move);
            return err;
        };
        transition.unmakeMove(value, chess_move);
        if (!child.completed) return .{ .nodes = nodes, .completed = false };
        nodes = try addNodes(nodes, child.nodes);
    }
    return .{ .nodes = nodes, .completed = true };
}

fn validateStorage(depth: u16, storage_length: usize) Error!void {
    if (depth > types.max_ply) return error.DepthTooLarge;
    if (@as(usize, depth) > storage_length) return error.InsufficientStateStorage;
}

fn addNodes(current: u64, additional: u64) Error!u64 {
    return std.math.add(u64, current, additional) catch error.NodeCountOverflow;
}

const PerftCase = struct {
    fen_text: []const u8,
    depth: u16,
    nodes: u64,
};

const fast_cases = [_]PerftCase{
    .{ .fen_text = fen.start_position, .depth = 0, .nodes = 1 },
    .{ .fen_text = fen.start_position, .depth = 1, .nodes = 20 },
    .{ .fen_text = fen.start_position, .depth = 2, .nodes = 400 },
    .{ .fen_text = fen.start_position, .depth = 3, .nodes = 8_902 },
    .{ .fen_text = fen.start_position, .depth = 4, .nodes = 197_281 },
    .{ .fen_text = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", .depth = 3, .nodes = 97_862 },
    .{ .fen_text = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", .depth = 4, .nodes = 43_238 },
    .{ .fen_text = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", .depth = 4, .nodes = 422_333 },
    .{ .fen_text = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", .depth = 3, .nodes = 62_379 },
    .{ .fen_text = "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", .depth = 3, .nodes = 89_890 },
};

const deep_cases = [_]PerftCase{
    .{ .fen_text = fen.start_position, .depth = 5, .nodes = 4_865_609 },
    .{ .fen_text = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", .depth = 4, .nodes = 4_085_603 },
    .{ .fen_text = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", .depth = 5, .nodes = 674_624 },
    .{ .fen_text = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", .depth = 4, .nodes = 2_103_487 },
    .{ .fen_text = "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", .depth = 4, .nodes = 3_894_594 },
};

fn expectCases(cases: []const PerftCase) !void {
    var storage: [types.max_ply]position.PositionState = undefined;
    for (cases) |case| {
        var root: position.PositionState = .{};
        var value = try fen.parse(case.fen_text, &root);
        try std.testing.expect(state.isConsistent(&value));
        const before_physical = value.physical;
        const before_root = root;
        const before_side = value.side_to_move;
        const before_ply = value.game_ply;

        try std.testing.expectEqual(case.nodes, try count(&value, case.depth, &storage));
        try std.testing.expectEqualDeep(before_physical, value.physical);
        try std.testing.expectEqualDeep(before_root, root);
        try std.testing.expectEqual(before_side, value.side_to_move);
        try std.testing.expectEqual(before_ply, value.game_ply);
        try std.testing.expect(value.current == &root);
        try std.testing.expect(state.isConsistent(&value));
    }
}

test "canonical perft covers structurally distinct legal positions" {
    try expectCases(&fast_cases);
}

test "deeper canonical perft is reserved for the ReleaseFast quality gate" {
    if (builtin.mode != .ReleaseFast) return;
    try expectCases(&deep_cases);
}

test "divide sums complete root subtrees and restores the root" {
    var root: position.PositionState = .{};
    var value = try fen.parseStart(&root);
    const before = value.physical;
    var storage: [2]position.PositionState = undefined;

    const result = try divide(&value, 2, &storage);
    try std.testing.expect(result.completed);
    try std.testing.expectEqual(@as(u16, 20), result.count);
    try std.testing.expectEqual(@as(u64, 400), result.total);
    for (result.slice()) |entry| try std.testing.expectEqual(@as(u64, 20), entry.nodes);
    try std.testing.expectEqualDeep(before, value.physical);
    try std.testing.expect(value.current == &root);
    try std.testing.expect(state.isConsistent(&value));

    const zero = try divide(&value, 0, storage[0..0]);
    try std.testing.expectEqual(@as(u16, 0), zero.count);
    try std.testing.expectEqual(@as(u64, 1), zero.total);
}

test "checked perft rejects invalid resource and arithmetic boundaries" {
    var root: position.PositionState = .{};
    var value = try fen.parseStart(&root);
    var storage: [types.max_ply]position.PositionState = undefined;
    try std.testing.expectError(error.InsufficientStateStorage, count(&value, 1, storage[0..0]));
    try std.testing.expectError(
        error.DepthTooLarge,
        count(&value, types.max_ply + 1, &storage),
    );
    try std.testing.expectError(error.NodeCountOverflow, addNodes(std.math.maxInt(u64), 1));
    try std.testing.expect(value.current == &root);
    try std.testing.expect(state.isConsistent(&value));
}

test "static cancellation returns only completed work and restores position" {
    const StopAfter = struct {
        remaining: u32,

        pub fn shouldStop(self: *@This()) bool {
            if (self.remaining == 0) return true;
            self.remaining -= 1;
            return false;
        }
    };

    var root: position.PositionState = .{};
    var value = try fen.parseStart(&root);
    const before = value.physical;
    var storage: [4]position.PositionState = undefined;
    var control = StopAfter{ .remaining = 32 };
    const result = try divideControlled(&value, 4, &storage, &control);

    try std.testing.expect(!result.completed);
    try std.testing.expect(result.count < 20);
    try std.testing.expectEqualDeep(before, value.physical);
    try std.testing.expect(value.current == &root);
    try std.testing.expect(state.isConsistent(&value));
}
