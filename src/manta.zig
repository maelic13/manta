//! Non-UCI library facade for Manta tests, benchmarks, and future tools.
pub const chess = @import("chess/root.zig");
pub const eval = @import("eval/root.zig");
pub const engine = @import("engine/root.zig");
pub const score = @import("score.zig");
pub const search = @import("search/root.zig");

test {
    _ = chess;
    _ = eval;
    _ = engine;
    _ = score;
    _ = search;
}
