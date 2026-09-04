//! Controller-owned, transactional applied game history.
const std = @import("std");
const fen = @import("fen.zig");
const move = @import("move.zig");
const notation = @import("notation.zig");
const position = @import("position.zig");
const state = @import("state.zig");
const transition = @import("transition.zig");

pub const Error = fen.ParseError || notation.Error || error{
    InsufficientStateStorage,
    InsufficientMoveStorage,
};

/// A completed candidate position and its stable-address state chain. Storage
/// belongs to the controller; building a replacement never mutates an active
/// history. Candidate storage must therefore not alias the active history.
pub const GameHistory = struct {
    position: position.Position,
    states: []position.PositionState,
    moves: []move.Move,

    /// The search only needs states back to the last irreversible move. The
    /// returned chronological slice includes the current state.
    pub fn repetitionContext(self: *const GameHistory) []const position.PositionState {
        std.debug.assert(self.states.len != 0);
        const current_index = self.states.len - 1;
        const reversible = @min(@as(usize, self.position.current.rule50), current_index);
        return self.states[current_index - reversible ..];
    }
};

/// Constructs a complete replacement in caller-owned candidate storage. The
/// generated-move capacity is deliberately unrelated to the applied-game
/// length: every supplied token is either applied or the whole candidate is
/// rejected.
pub fn build(
    fen_text: []const u8,
    move_tokens: []const []const u8,
    state_storage: []position.PositionState,
    move_storage: []move.Move,
) Error!GameHistory {
    if (state_storage.len == 0 or move_tokens.len > state_storage.len - 1) {
        return error.InsufficientStateStorage;
    }
    if (move_tokens.len > move_storage.len) return error.InsufficientMoveStorage;

    var candidate = try fen.parse(fen_text, &state_storage[0]);
    std.debug.assert(state.isConsistent(&candidate));
    for (move_tokens, 0..) |token, index| {
        const chess_move = try notation.parseLegal(&candidate, token);
        move_storage[index] = chess_move;
        transition.makeMove(&candidate, chess_move, &state_storage[index + 1]);
        std.debug.assert(state.isConsistent(&candidate));
    }

    return .{
        .position = candidate,
        .states = state_storage[0 .. move_tokens.len + 1],
        .moves = move_storage[0..move_tokens.len],
    };
}

test "applied move lists are checked transactionally" {
    var active_states: [2]position.PositionState = undefined;
    var active_moves: [1]move.Move = undefined;
    var active = try build(fen.start_position, &.{"e2e4"}, &active_states, &active_moves);
    const active_key = active.position.current.key;
    const active_board = active.position.physical.board;
    const active_current = active.position.current;

    var candidate_states: [4]position.PositionState = undefined;
    var candidate_moves: [3]move.Move = undefined;
    try std.testing.expectError(
        error.Illegal,
        build(
            fen.start_position,
            &.{ "d2d4", "d7d5", "d4d6" },
            &candidate_states,
            &candidate_moves,
        ),
    );

    try std.testing.expectEqual(active_key, active.position.current.key);
    try std.testing.expectEqual(active_current, active.position.current);
    try std.testing.expectEqual(active_board, active.position.physical.board);
    try std.testing.expect(state.isConsistent(&active.position));
}

test "applied history is not capped by node move capacity" {
    const cycle = [_][]const u8{ "g1f3", "g8f6", "f3g1", "f6g8" };
    var tokens: [300][]const u8 = undefined;
    for (&tokens, 0..) |*token, index| token.* = cycle[index % cycle.len];
    var states: [301]position.PositionState = undefined;
    var moves: [300]move.Move = undefined;

    const game = try build(fen.start_position, &tokens, &states, &moves);
    try std.testing.expectEqual(@as(usize, 300), game.moves.len);
    try std.testing.expectEqual(@as(usize, 301), game.states.len);
    try std.testing.expectEqual(@as(usize, 301), game.repetitionContext().len);
    try std.testing.expect(state.isConsistent(&game.position));
}

test "history reports caller storage shortages without partial authority transfer" {
    var one_state: [1]position.PositionState = undefined;
    var one_move: [1]move.Move = undefined;
    try std.testing.expectError(
        error.InsufficientStateStorage,
        build(fen.start_position, &.{"e2e4"}, &one_state, &one_move),
    );

    var two_states: [2]position.PositionState = undefined;
    var no_moves: [0]move.Move = .{};
    try std.testing.expectError(
        error.InsufficientMoveStorage,
        build(fen.start_position, &.{"e2e4"}, &two_states, &no_moves),
    );
}
