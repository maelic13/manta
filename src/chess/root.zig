//! Chess-domain facade: representation, setup, reversible state and legal moves.
pub const attacks = @import("attacks.zig");
pub const draw = @import("draw.zig");
pub const fen = @import("fen.zig");
pub const history = @import("history.zig");
pub const move = @import("move.zig");
pub const movegen = @import("movegen.zig");
pub const notation = @import("notation.zig");
pub const perft = @import("perft.zig");
pub const position = @import("position.zig");
pub const queries = @import("queries.zig");
pub const see = @import("see.zig");
pub const state = @import("state.zig");
pub const transition = @import("transition.zig");
pub const types = @import("types.zig");
pub const zobrist = @import("zobrist.zig");

test {
    _ = attacks;
    _ = draw;
    _ = fen;
    _ = history;
    _ = move;
    _ = movegen;
    _ = notation;
    _ = perft;
    _ = position;
    _ = queries;
    _ = see;
    _ = state;
    _ = transition;
    _ = types;
    _ = zobrist;
}
