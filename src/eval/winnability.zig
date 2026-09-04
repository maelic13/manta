//! Endgame winnability and initiative evidence.
//!
//! This module grades how many independent conversion routes remain. It never
//! decides a result: the returned adjustment is ordinary evaluation evidence,
//! is capped, and cannot reverse the sign of the endgame score it modifies.
const std = @import("std");
const position = @import("../chess/position.zig");
const types = @import("../chess/types.zig");
const params = @import("hce_params.zig");

const Bitboard = types.Bitboard;

pub const Facts = struct {
    passed_pawns: u5,
    total_pawns: u5,
    /// Files by which the kings' horizontal separation exceeds their vertical
    /// separation. Direct opposition is zero; room to walk around is positive.
    outflanking: u3,
    pawns_on_both_flanks: bool,
    infiltrating_kings: u2,
    pure_pawn_ending: bool,
    almost_unwinnable: bool,
};

pub const Result = struct {
    facts: Facts,
    adjustment: i32,
};

/// Derive position facts and a signed endgame-only score adjustment.
///
/// `passed` is produced by the authoritative pawn classifier. Reusing it keeps
/// this last structural cluster from rebuilding an earlier cluster's work.
pub fn evaluate(value: *const position.Position, passed: Bitboard, base_endgame: i32) Result {
    const facts = derive(value, passed, base_endgame);
    return .{ .facts = facts, .adjustment = adjust(base_endgame, facts) };
}

pub fn derive(value: *const position.Position, passed: Bitboard, base_endgame: i32) Facts {
    const white_king = value.physical.king_square[types.Color.white.index()];
    const black_king = value.physical.king_square[types.Color.black.index()];
    const file_distance = distance(white_king.file().index(), black_king.file().index());
    const rank_distance = distance(white_king.rank().index(), black_king.rank().index());
    const all_pawns = value.physical.by_type[types.PieceType.pawn.index()];
    const non_pawn_material = value.physical.occupied() & ~all_pawns &
        ~value.physical.by_type[types.PieceType.king.index()];
    const both_flanks = all_pawns & queen_flank != 0 and all_pawns & king_flank != 0;
    const infiltration = @as(u2, @intFromBool(white_king.rank().index() >= types.Rank.five.index())) +
        @as(u2, @intFromBool(black_king.rank().index() <= types.Rank.four.index()));
    const leader: ?types.Color = if (base_endgame > 0)
        .white
    else if (base_endgame < 0)
        .black
    else
        null;

    return .{
        .passed_pawns = @intCast(@popCount(passed)),
        .total_pawns = @intCast(@popCount(all_pawns)),
        .outflanking = @intCast(if (file_distance > rank_distance) file_distance - rank_distance else 0),
        .pawns_on_both_flanks = both_flanks,
        .infiltrating_kings = infiltration,
        .pure_pawn_ending = non_pawn_material == 0,
        .almost_unwinnable = if (leader) |side| almostUnwinnable(value, side) else false,
    };
}

/// Apply the current reasoned starting coefficients without changing the
/// winner named by `base_endgame`. Step 5.3.16 may fit the coefficients, but
/// the no-sign-flip cap is structural.
pub fn adjust(base_endgame: i32, facts: Facts) i32 {
    if (base_endgame == 0) return 0;
    var complexity = params.winnability_base +
        params.winnability_passed * @as(i32, facts.passed_pawns) +
        params.winnability_pawn_count * @as(i32, facts.total_pawns) +
        params.winnability_outflanking * @as(i32, facts.outflanking) +
        params.winnability_infiltration * @as(i32, facts.infiltrating_kings);
    if (facts.pawns_on_both_flanks) complexity += params.winnability_both_flanks;
    if (facts.pure_pawn_ending) complexity += params.winnability_pawn_ending;
    if (facts.almost_unwinnable) complexity += params.winnability_almost_unwinnable;
    complexity = @min(complexity, params.winnability_max_bonus);

    const magnitude: i32 = @intCast(@abs(base_endgame));
    const bounded = @max(complexity, -magnitude);
    return if (base_endgame > 0) bounded else -bounded;
}

fn almostUnwinnable(value: *const position.Position, leader: types.Color) bool {
    if (value.physical.pieces(leader, .pawn) != 0 or value.physical.pieces(leader, .queen) != 0)
        return false;
    const rooks: u8 = @intCast(@popCount(value.physical.pieces(leader, .rook)));
    const minors: u8 = @intCast(@popCount(
        value.physical.pieces(leader, .knight) | value.physical.pieces(leader, .bishop),
    ));
    // One rook or two minors can force against a bare king but often cannot
    // convert a small edge when defensive material remains. Exact recognizers
    // remain the higher-specificity authority for their seventeen signatures.
    return rooks * 2 + minors <= 2;
}

fn distance(a: u3, b: u3) u3 {
    return if (a >= b) a - b else b - a;
}

const queen_flank: Bitboard = 0x0F0F_0F0F_0F0F_0F0F;
const king_flank: Bitboard = 0xF0F0_F0F0_F0F0_F0F0;

test "complexity facts name independent conversion routes" {
    var root: position.PositionState = .{};
    const value = try @import("../chess/fen.zig").parse(
        "8/3k4/8/6K1/8/8/P6P/8 w - - 0 1",
        &root,
    );
    const facts = derive(&value, types.Square.a2.bit() | types.Square.h2.bit(), 40);
    try std.testing.expectEqual(@as(u5, 2), facts.passed_pawns);
    try std.testing.expectEqual(@as(u5, 2), facts.total_pawns);
    try std.testing.expect(facts.outflanking > 0);
    try std.testing.expect(facts.pawns_on_both_flanks);
    try std.testing.expectEqual(@as(u2, 1), facts.infiltrating_kings);
    try std.testing.expect(facts.pure_pawn_ending);
    try std.testing.expect(!facts.almost_unwinnable);

    var opposition_root: position.PositionState = .{};
    const opposition = try @import("../chess/fen.zig").parse(
        "8/3k4/8/8/3K4/8/P7/8 w - - 0 1",
        &opposition_root,
    );
    const sparse = derive(&opposition, types.Square.a2.bit(), 40);
    try std.testing.expectEqual(@as(u3, 0), sparse.outflanking);
    try std.testing.expect(!sparse.pawns_on_both_flanks);
    try std.testing.expectEqual(@as(u2, 0), sparse.infiltrating_kings);
    try std.testing.expect(sparse.pure_pawn_ending);
}

test "almost-unwinnable material is produced for the leading side only" {
    var rook_root: position.PositionState = .{};
    var queen_root: position.PositionState = .{};
    const rook = try @import("../chess/fen.zig").parse(
        "7k/8/8/8/8/8/q7/R3K3 w - - 0 1",
        &rook_root,
    );
    const queen = try @import("../chess/fen.zig").parse(
        "7k/8/8/8/8/8/8/1Q2K3 w - - 0 1",
        &queen_root,
    );
    try std.testing.expectEqual(true, derive(&rook, 0, 100).almost_unwinnable);
    try std.testing.expectEqual(false, derive(&queen, 0, 100).almost_unwinnable);
    try std.testing.expectEqual(false, derive(&rook, 0, -100).almost_unwinnable);
}

test "initiative is bounded and cannot reverse an endgame score" {
    const quiet: Facts = .{
        .passed_pawns = 0,
        .total_pawns = 0,
        .outflanking = 0,
        .pawns_on_both_flanks = false,
        .infiltrating_kings = 0,
        .pure_pawn_ending = false,
        .almost_unwinnable = true,
    };
    const complex: Facts = .{
        .passed_pawns = 4,
        .total_pawns = 8,
        .outflanking = 3,
        .pawns_on_both_flanks = true,
        .infiltrating_kings = 2,
        .pure_pawn_ending = true,
        .almost_unwinnable = false,
    };
    try std.testing.expectEqual(@as(i32, -9), adjust(9, quiet));
    try std.testing.expectEqual(@as(i32, 9), adjust(-9, quiet));
    try std.testing.expect(adjust(100, complex) > 0);
    try std.testing.expect(adjust(-100, complex) < 0);
    try std.testing.expect(@abs(adjust(100, complex)) <= params.winnability_max_bonus);
}

test "pawn count and pure pawn endings add independent conversion routes" {
    // FUNC-006: more pawns supply more irreversible breaks, and removing the
    // last piece opens king/pawn races. Hold every earlier fact fixed so these
    // two omitted complexity inputs are independently observable.
    const sparse: Facts = .{
        .passed_pawns = 0,
        .total_pawns = 1,
        .outflanking = 0,
        .pawns_on_both_flanks = false,
        .infiltrating_kings = 0,
        .pure_pawn_ending = false,
        .almost_unwinnable = false,
    };
    var many = sparse;
    many.total_pawns = 5;
    var pawn_only = sparse;
    pawn_only.pure_pawn_ending = true;
    try std.testing.expect(adjust(100, many) > adjust(100, sparse));
    try std.testing.expect(adjust(100, pawn_only) > adjust(100, sparse));
}
