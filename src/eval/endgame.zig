//! Specialized classical-endgame knowledge.
//!
//! Recognizers classify only exact material signatures. They never return a
//! mate, draw, tablebase result or search bound: a value is an ordinary static
//! estimate and a scale is only a statement about convertibility.
const std = @import("std");
const fen = @import("../chess/fen.zig");
const position = @import("../chess/position.zig");
const params = @import("hce_params.zig");
const kpk = @import("kpk.zig");
const state = @import("../chess/state.zig");
const types = @import("../chess/types.zig");
const score = @import("../score.zig");

const Bitboard = types.Bitboard;

pub const scale_normal: i32 = params.scale_normal;

pub const Kind = enum {
    kxk,
    kbnk,
    knnk,
    knnkp,
    kpk,
    kqkp,
    kqkr,
    krkb,
    krkn,
    krkp,
    kbpkb,
    kbpkn,
    kbppkb,
    kpkp,
    krpkb,
    krpkr,
    krppkrp,
};

pub const Value = struct {
    kind: Kind,
    strong_side: types.Color,
    /// White-relative ordinary score. Zero is a static assessment, not a draw
    /// verdict, and search remains free to prove a mate or rule draw.
    white_value: i32,
};

pub const Scale = struct {
    kind: Kind,
    /// Null only for symmetric material such as KPKP, where whichever side
    /// the ordinary evaluator leads for is the side whose conversion is
    /// scaled.
    strong_side: ?types.Color,
    factor: i32,
};

pub const Result = union(enum) {
    value: Value,
    scale: Scale,
};

const Material = struct {
    pawn: u4,
    knight: u4,
    bishop: u4,
    rook: u4,
    queen: u4,

    fn bare(self: Material) bool {
        return self.pawn == 0 and self.knight == 0 and self.bishop == 0 and
            self.rook == 0 and self.queen == 0;
    }

    fn code(self: Material) u20 {
        return @as(u20, self.pawn) |
            (@as(u20, self.knight) << 4) |
            (@as(u20, self.bishop) << 8) |
            (@as(u20, self.rook) << 12) |
            (@as(u20, self.queen) << 16);
    }
};

/// Returns the one exact-signature recognizer that owns this position.
///
/// The seven-piece cutoff makes the common middlegame path a population count
/// and branch. Syzygy may know the same position, but this result remains only
/// ordinary evaluator evidence and cannot replace a probe verdict.
pub fn recognize(value: *const position.Position) ?Result {
    if (@popCount(value.physical.occupied()) > 7) return null;

    const material = [2]Material{
        materialFor(value, .white),
        materialFor(value, .black),
    };

    return recognizeFor(value, .white, material[0], material[1]) orelse
        recognizeFor(value, .black, material[1], material[0]);
}

fn recognizeFor(
    value: *const position.Position,
    strong_side: types.Color,
    strong: Material,
    weak: Material,
) ?Result {
    const key = materialKey(strong.code(), weak.code());
    return switch (key) {
        materialKey(signature(0, 1, 1, 0, 0), 0) => knownValue(.kbnk, value, strong_side, kbnkValue(value, strong_side)),
        materialKey(signature(0, 2, 0, 0, 0), 0) => knownValue(.knnk, value, strong_side, 0),
        materialKey(signature(0, 2, 0, 0, 0), signature(1, 0, 0, 0, 0)) => knownValue(.knnkp, value, strong_side, knnkpValue(value, strong_side)),
        materialKey(signature(1, 0, 0, 0, 0), 0) => knownValue(.kpk, value, strong_side, kpkValue(value, strong_side)),
        materialKey(signature(0, 0, 0, 0, 1), signature(1, 0, 0, 0, 0)) => knownValue(.kqkp, value, strong_side, kqkpValue(value, strong_side)),
        materialKey(signature(0, 0, 0, 0, 1), signature(0, 0, 0, 1, 0)) => knownValue(.kqkr, value, strong_side, convertedValue(value, strong_side, params.endgame_kqkr)),
        materialKey(signature(0, 0, 0, 1, 0), signature(0, 0, 1, 0, 0)) => knownValue(.krkb, value, strong_side, convertedValue(value, strong_side, params.endgame_krkb)),
        materialKey(signature(0, 0, 0, 1, 0), signature(0, 1, 0, 0, 0)) => knownValue(.krkn, value, strong_side, convertedValue(value, strong_side, params.endgame_krkn)),
        materialKey(signature(0, 0, 0, 1, 0), signature(1, 0, 0, 0, 0)) => knownValue(.krkp, value, strong_side, krkpValue(value, strong_side)),
        materialKey(signature(1, 0, 1, 0, 0), signature(0, 0, 1, 0, 0)) => scaleResult(.kbpkb, value, strong_side, kbpkbScale(value, strong_side)),
        materialKey(signature(1, 0, 1, 0, 0), signature(0, 1, 0, 0, 0)) => scaleResult(.kbpkn, value, strong_side, kbpknScale(value, strong_side)),
        materialKey(signature(2, 0, 1, 0, 0), signature(0, 0, 1, 0, 0)) => scaleResult(.kbppkb, value, strong_side, kbppkbScale(value, strong_side)),
        materialKey(signature(1, 0, 0, 0, 0), signature(1, 0, 0, 0, 0)) => scaleResult(.kpkp, value, null, kpkpScale(value, strong_side)),
        materialKey(signature(1, 0, 0, 1, 0), signature(0, 0, 1, 0, 0)) => scaleResult(.krpkb, value, strong_side, krpkbScale(value, strong_side)),
        materialKey(signature(1, 0, 0, 1, 0), signature(0, 0, 0, 1, 0)) => scaleResult(.krpkr, value, strong_side, krpkrScale(value, strong_side)),
        materialKey(signature(2, 0, 0, 1, 0), signature(1, 0, 0, 1, 0)) => scaleResult(.krppkrp, value, strong_side, krppkrpScale(value, strong_side)),
        else => if (weak.bare() and kxkMaterial(strong))
            knownValue(.kxk, value, strong_side, kxkValue(value, strong_side, strong))
        else
            null,
    };
}

fn signature(pawn: u4, knight: u4, bishop: u4, rook: u4, queen: u4) u20 {
    return @as(u20, pawn) | (@as(u20, knight) << 4) |
        (@as(u20, bishop) << 8) | (@as(u20, rook) << 12) |
        (@as(u20, queen) << 16);
}

fn materialKey(strong: u20, weak: u20) u40 {
    return (@as(u40, strong) << 20) | weak;
}

fn materialFor(value: *const position.Position, side: types.Color) Material {
    const counts = &value.physical.piece_count;
    return .{
        .pawn = @intCast(counts[types.Piece.make(side, .pawn).index()]),
        .knight = @intCast(counts[types.Piece.make(side, .knight).index()]),
        .bishop = @intCast(counts[types.Piece.make(side, .bishop).index()]),
        .rook = @intCast(counts[types.Piece.make(side, .rook).index()]),
        .queen = @intCast(counts[types.Piece.make(side, .queen).index()]),
    };
}

fn knownValue(kind: Kind, value: *const position.Position, strong_side: types.Color, magnitude: i32) Result {
    std.debug.assert(magnitude >= 0 and magnitude <= score.ordinary_max_raw);
    _ = value;
    return .{ .value = .{
        .kind = kind,
        .strong_side = strong_side,
        .white_value = if (strong_side == .white) magnitude else -magnitude,
    } };
}

fn scaleResult(kind: Kind, value: *const position.Position, strong_side: ?types.Color, factor: i32) Result {
    std.debug.assert(factor >= 0 and factor <= scale_normal);
    _ = value;
    return .{ .scale = .{ .kind = kind, .strong_side = strong_side, .factor = factor } };
}

fn kxkMaterial(strong: Material) bool {
    if (strong.pawn != 0) return false;
    if (strong.queen != 0 or strong.rook != 0) return true;
    if (strong.bishop != 0 and strong.knight != 0) return true;
    return strong.bishop >= 2;
}

fn kxkValue(value: *const position.Position, strong_side: types.Color, strong: Material) i32 {
    const material = @as(i32, strong.queen) * params.endgame_kxk_material[0] +
        @as(i32, strong.rook) * params.endgame_kxk_material[1] +
        @as(i32, strong.bishop) * params.endgame_kxk_material[2] +
        @as(i32, strong.knight) * params.endgame_kxk_material[3];
    // Bare-king conversion is known to be winning when the material can mate.
    // The bonus is deliberately ordinary and far below decisive score bands.
    return params.endgame_kxk_base + material + conversionBonus(value, strong_side) + tempoBonus(value, strong_side);
}

fn kbnkValue(value: *const position.Position, strong_side: types.Color) i32 {
    const bishop = firstSquare(value.physical.pieces(strong_side, .bishop)).?;
    const weak_king = value.physical.king_square[strong_side.opposite().index()];
    const light_bishop = bishop.bit() & light_squares != 0;
    const corners = if (light_bishop)
        [2]types.Square{ .a8, .h1 }
    else
        [2]types.Square{ .a1, .h8 };
    const corner_distance = @min(kingDistance(weak_king, corners[0]), kingDistance(weak_king, corners[1]));
    return params.endgame_kbnk[0] + (7 - corner_distance) * params.endgame_kbnk[1] +
        kingApproach(value, strong_side) * params.endgame_kbnk[2] + tempoBonus(value, strong_side);
}

fn knnkpValue(value: *const position.Position, strong_side: types.Color) i32 {
    const weak = strong_side.opposite();
    const pawn = firstSquare(value.physical.pieces(weak, .pawn)).?;
    // The defender's pawn supplies the extra tempo that can make two knights
    // convertible, but the opportunity shrinks as it nears promotion.
    const progress = relativeRank(weak, pawn);
    return params.endgame_knnkp[0] + (6 - progress) * params.endgame_knnkp[1] +
        kingApproach(value, strong_side) * params.endgame_knnkp[2] + tempoBonus(value, strong_side);
}

fn kpkValue(value: *const position.Position, strong_side: types.Color) i32 {
    const pawn = firstSquare(value.physical.pieces(strong_side, .pawn)).?;
    const weak_king = value.physical.king_square[strong_side.opposite().index()];
    const strong_king = value.physical.king_square[strong_side.index()];
    const progress = relativeRank(strong_side, pawn);
    const promotion = promotionSquare(strong_side, pawn.file());

    if (!kpk.isWin(strong_king, weak_king, pawn, strong_side, value.side_to_move)) return 0;

    const next = forwardSquare(strong_side, pawn) orelse promotion;
    const support = @max(0, 3 - kingDistance(strong_king, next)) * params.endgame_kpk[2];
    const exclusion = @max(0, 3 - kingDistance(weak_king, next)) * params.endgame_kpk[3];
    return @max(0, params.endgame_kpk[0] + progress * params.endgame_kpk[1] + support - exclusion);
}

fn kqkpValue(value: *const position.Position, strong_side: types.Color) i32 {
    const weak = strong_side.opposite();
    const pawn = firstSquare(value.physical.pieces(weak, .pawn)).?;
    const weak_king = value.physical.king_square[weak.index()];
    const promotion = promotionSquare(weak, pawn.file());
    const fortress_file = switch (pawn.file()) {
        .a, .c, .f, .h => true,
        else => false,
    };
    if (relativeRank(weak, pawn) == 6 and fortress_file and kingDistance(weak_king, promotion) <= 1)
        return @max(0, params.endgame_kqkp[0] + tempoBonus(value, strong_side));
    return params.endgame_kqkp[1] + conversionBonus(value, strong_side) + tempoBonus(value, strong_side);
}

fn krkpValue(value: *const position.Position, strong_side: types.Color) i32 {
    const weak = strong_side.opposite();
    const pawn = firstSquare(value.physical.pieces(weak, .pawn)).?;
    const progress = relativeRank(weak, pawn);
    const stop = forwardSquare(weak, pawn) orelse promotionSquare(weak, pawn.file());
    const rook_king = value.physical.king_square[strong_side.index()];
    const pawn_king = value.physical.king_square[weak.index()];
    const blockade = @max(0, 4 - kingDistance(rook_king, stop)) * params.endgame_krkp[2];
    const support = @max(0, 3 - kingDistance(pawn_king, pawn)) * params.endgame_krkp[4];
    return @max(
        params.endgame_krkp[0],
        params.endgame_krkp[1] + blockade - progress * params.endgame_krkp[3] - support + tempoBonus(value, strong_side),
    );
}

fn kbpkbScale(value: *const position.Position, strong_side: types.Color) i32 {
    const strong_bishop = value.physical.pieces(strong_side, .bishop);
    const weak_bishop = value.physical.pieces(strong_side.opposite(), .bishop);
    const pawn = firstSquare(value.physical.pieces(strong_side, .pawn)).?;
    if (wrongRookBishop(value, strong_side, pawn, strong_bishop)) return params.endgame_kbpkb[0];
    return scaleWithGeometry(value, strong_side, pawn, if (oppositeColoured(strong_bishop, weak_bishop))
        params.endgame_kbpkb[1]
    else
        params.endgame_kbpkb[2]);
}

fn kbpknScale(value: *const position.Position, strong_side: types.Color) i32 {
    const pawn = firstSquare(value.physical.pieces(strong_side, .pawn)).?;
    const bishop = value.physical.pieces(strong_side, .bishop);
    if (wrongRookBishop(value, strong_side, pawn, bishop)) return params.endgame_kbpkn[0];
    return scaleWithGeometry(
        value,
        strong_side,
        pawn,
        params.endgame_kbpkn[1] + relativeRank(strong_side, pawn) * params.endgame_kbpkn[2],
    );
}

fn kbppkbScale(value: *const position.Position, strong_side: types.Color) i32 {
    const pawns = value.physical.pieces(strong_side, .pawn);
    const bishops = value.physical.pieces(strong_side, .bishop);
    const enemy_bishops = value.physical.pieces(strong_side.opposite(), .bishop);
    const files = pawnFileSpan(pawns);
    if (files == 0) return params.endgame_kbppkb[0];
    const front = mostAdvancedPawn(value.physical.pieces(strong_side, .pawn), strong_side);
    return scaleWithGeometry(value, strong_side, front, if (oppositeColoured(bishops, enemy_bishops))
        params.endgame_kbppkb[1]
    else
        params.endgame_kbppkb[2]);
}

fn kpkpScale(value: *const position.Position, strong_side: types.Color) i32 {
    const own = firstSquare(value.physical.pieces(strong_side, .pawn)).?;
    const enemy = firstSquare(value.physical.pieces(strong_side.opposite(), .pawn)).?;
    if (own.file() == enemy.file() and forwardSquare(strong_side, own) == enemy)
        return params.endgame_kpkp[0];
    const separation = @abs(@as(i32, own.file().index()) - @as(i32, enemy.file().index()));
    const own_race = 7 - relativeRank(strong_side, own);
    const enemy_race = 7 - relativeRank(strong_side.opposite(), enemy);
    const race_gap: i32 = @intCast(@abs(own_race - enemy_race));
    return clampScale((if (separation <= 1) params.endgame_kpkp[1] else params.endgame_kpkp[2]) +
        race_gap * params.endgame_king_geometry[0]);
}

fn krpkbScale(value: *const position.Position, strong_side: types.Color) i32 {
    const pawn = firstSquare(value.physical.pieces(strong_side, .pawn)).?;
    const progress = relativeRank(strong_side, pawn);
    return scaleWithGeometry(
        value,
        strong_side,
        pawn,
        params.endgame_krpkb[0] + progress * params.endgame_krpkb[1],
    );
}

fn krpkrScale(value: *const position.Position, strong_side: types.Color) i32 {
    const pawn = firstSquare(value.physical.pieces(strong_side, .pawn)).?;
    const weak_king = value.physical.king_square[strong_side.opposite().index()];
    const promotion = promotionSquare(strong_side, pawn.file());
    if (kingDistance(weak_king, promotion) <= 1 and relativeRank(strong_side, pawn) <= 5)
        return clampScale(params.endgame_krpkr[0] + tempoBonus(value, strong_side));
    return scaleWithGeometry(
        value,
        strong_side,
        pawn,
        params.endgame_krpkr[1] + relativeRank(strong_side, pawn) * params.endgame_krpkr[2],
    );
}

fn krppkrpScale(value: *const position.Position, strong_side: types.Color) i32 {
    const pawns = value.physical.pieces(strong_side, .pawn);
    const spread = pawnFileSpan(pawns);
    const front = mostAdvancedPawn(pawns, strong_side);
    return scaleWithGeometry(
        value,
        strong_side,
        front,
        if (spread <= 1) params.endgame_krppkrp[0] else params.endgame_krppkrp[1],
    );
}

fn scaleWithGeometry(value: *const position.Position, strong_side: types.Color, pawn: types.Square, base: i32) i32 {
    const strong_king = value.physical.king_square[strong_side.index()];
    const weak_king = value.physical.king_square[strong_side.opposite().index()];
    const promotion = promotionSquare(strong_side, pawn.file());
    const support = @max(0, 4 - kingDistance(strong_king, pawn)) * params.endgame_king_geometry[0];
    const blockade = @max(0, 4 - kingDistance(weak_king, promotion)) * params.endgame_king_geometry[1];
    return clampScale(base + support - blockade + tempoBonus(value, strong_side));
}

fn clampScale(value: i32) i32 {
    return @min(scale_normal, @max(0, value));
}

fn tempoBonus(value: *const position.Position, strong_side: types.Color) i32 {
    return if (value.side_to_move == strong_side) params.endgame_tempo else -params.endgame_tempo;
}

fn mostAdvancedPawn(pawns: Bitboard, side: types.Color) types.Square {
    var remaining = pawns;
    var best = firstSquare(remaining).?;
    remaining &= remaining - 1;
    while (remaining != 0) {
        const candidate = firstSquare(remaining).?;
        remaining &= remaining - 1;
        if (relativeRank(side, candidate) > relativeRank(side, best)) best = candidate;
    }
    return best;
}

fn conversionBonus(value: *const position.Position, strong_side: types.Color) i32 {
    return kingApproach(value, strong_side) * params.endgame_conversion[0] + edgeDistanceBonus(
        value.physical.king_square[strong_side.opposite().index()],
    ) * params.endgame_conversion[1];
}

fn convertedValue(value: *const position.Position, strong_side: types.Color, base: i32) i32 {
    return @max(0, base + conversionBonus(value, strong_side) + tempoBonus(value, strong_side));
}

fn kingApproach(value: *const position.Position, strong_side: types.Color) i32 {
    const distance = kingDistance(
        value.physical.king_square[strong_side.index()],
        value.physical.king_square[strong_side.opposite().index()],
    );
    return 7 - distance;
}

fn edgeDistanceBonus(square: types.Square) i32 {
    const file = @as(i32, square.file().index());
    const rank = @as(i32, square.rank().index());
    const edge_distance = @min(@min(file, 7 - file), @min(rank, 7 - rank));
    return 3 - edge_distance;
}

fn relativeRank(side: types.Color, square: types.Square) i32 {
    const rank = @as(i32, square.rank().index());
    return if (side == .white) rank else 7 - rank;
}

fn promotionSquare(side: types.Color, file: types.File) types.Square {
    return types.Square.make(file, if (side == .white) .eight else .one);
}

fn forwardSquare(side: types.Color, square: types.Square) ?types.Square {
    const step: i32 = if (side == .white) 8 else -8;
    const index = @as(i32, square.index()) + step;
    if (index < 0 or index >= 64) return null;
    return types.Square.fromIndex(@intCast(index));
}

fn kingDistance(a: types.Square, b: types.Square) i32 {
    const file_delta = @abs(@as(i32, a.file().index()) - @as(i32, b.file().index()));
    const rank_delta = @abs(@as(i32, a.rank().index()) - @as(i32, b.rank().index()));
    return @intCast(@max(file_delta, rank_delta));
}

fn firstSquare(bits: Bitboard) ?types.Square {
    if (bits == 0) return null;
    return types.Square.fromIndex(@intCast(@ctz(bits)));
}

fn isRookFile(file: types.File) bool {
    return file == .a or file == .h;
}

fn wrongRookBishop(value: *const position.Position, strong_side: types.Color, pawn: types.Square, bishops: Bitboard) bool {
    if (!isRookFile(pawn.file())) return false;
    const promotion = promotionSquare(strong_side, pawn.file());
    const weak_king = value.physical.king_square[strong_side.opposite().index()];
    const bishop_light = bishops & light_squares != 0;
    const promotion_light = promotion.bit() & light_squares != 0;
    return bishop_light != promotion_light and kingDistance(weak_king, promotion) <= 1;
}

fn oppositeColoured(a: Bitboard, b: Bitboard) bool {
    return (a & light_squares != 0) != (b & light_squares != 0);
}

fn pawnFileSpan(pawns: Bitboard) i32 {
    std.debug.assert(@popCount(pawns) == 2);
    var remaining = pawns;
    const first = firstSquare(remaining).?;
    remaining &= remaining - 1;
    const second = firstSquare(remaining).?;
    return @intCast(@abs(@as(i32, first.file().index()) - @as(i32, second.file().index())));
}

const light_squares: Bitboard = 0x55AA_55AA_55AA_55AA;

fn parsed(fen_text: []const u8) !struct { root: position.PositionState, value: position.Position } {
    var root: position.PositionState = .{};
    const value = try fen.parse(fen_text, &root);
    return .{ .root = root, .value = value };
}

test "all value recognizers own exact material signatures and stay ordinary" {
    const cases = [_]struct { kind: Kind, fen_text: []const u8 }{
        .{ .kind = .kxk, .fen_text = "7k/8/8/8/8/8/4R3/4K3 w - - 0 1" },
        .{ .kind = .kbnk, .fen_text = "7k/8/8/8/8/8/3BN3/4K3 w - - 0 1" },
        .{ .kind = .knnk, .fen_text = "7k/8/8/8/8/8/3NN3/4K3 w - - 0 1" },
        .{ .kind = .knnkp, .fen_text = "7k/7p/8/8/8/8/3NN3/4K3 w - - 0 1" },
        .{ .kind = .kpk, .fen_text = "7k/8/8/4P3/4K3/8/8/8 w - - 0 1" },
        .{ .kind = .kqkp, .fen_text = "7k/7p/8/8/8/8/4Q3/4K3 w - - 0 1" },
        .{ .kind = .kqkr, .fen_text = "7k/7r/8/8/8/8/4Q3/4K3 w - - 0 1" },
        .{ .kind = .krkb, .fen_text = "7k/7b/8/8/8/8/4R3/4K3 w - - 0 1" },
        .{ .kind = .krkn, .fen_text = "7k/7n/8/8/8/8/4R3/4K3 w - - 0 1" },
        .{ .kind = .krkp, .fen_text = "7k/7p/8/8/8/8/4R3/4K3 w - - 0 1" },
    };
    for (cases) |case| {
        var item = try parsed(case.fen_text);
        item.value.rebind(&item.root);
        const result = recognize(&item.value) orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(case.kind, result.value.kind);
        try std.testing.expect(@abs(result.value.white_value) <= score.ordinary_max_raw);

        var twin_root: position.PositionState = .{};
        var twin = try colorFlip(&item.value, &twin_root);
        twin.rebind(&twin_root);
        const mirrored = recognize(&twin).?.value;
        try std.testing.expectEqual(case.kind, mirrored.kind);
        try std.testing.expectEqual(-result.value.white_value, mirrored.white_value);
    }
}

test "all scale recognizers own exact material signatures and bounded factors" {
    const cases = [_]struct { kind: Kind, fen_text: []const u8 }{
        .{ .kind = .kbpkb, .fen_text = "7k/7b/8/8/4P3/8/3B4/4K3 w - - 0 1" },
        .{ .kind = .kbpkn, .fen_text = "7k/7n/8/8/4P3/8/3B4/4K3 w - - 0 1" },
        .{ .kind = .kbppkb, .fen_text = "7k/7b/8/8/3PP3/8/3B4/4K3 w - - 0 1" },
        .{ .kind = .kpkp, .fen_text = "7k/7p/8/8/4P3/8/8/4K3 w - - 0 1" },
        .{ .kind = .krpkb, .fen_text = "7k/7b/8/8/4P3/8/3R4/4K3 w - - 0 1" },
        .{ .kind = .krpkr, .fen_text = "7k/7r/8/8/4P3/8/3R4/4K3 w - - 0 1" },
        .{ .kind = .krppkrp, .fen_text = "7k/6pr/8/8/3PP3/8/3R4/4K3 w - - 0 1" },
    };
    for (cases) |case| {
        var item = try parsed(case.fen_text);
        item.value.rebind(&item.root);
        const result = recognize(&item.value) orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(case.kind, result.scale.kind);
        try std.testing.expect(result.scale.factor >= 0 and result.scale.factor <= scale_normal);

        var twin_root: position.PositionState = .{};
        var twin = try colorFlip(&item.value, &twin_root);
        twin.rebind(&twin_root);
        const mirrored = recognize(&twin).?.scale;
        try std.testing.expectEqual(case.kind, mirrored.kind);
        try std.testing.expectEqual(result.scale.factor, mirrored.factor);
    }
}

test "recognizers reject nearby material counterexamples" {
    const cases = [_][]const u8{
        // KBNK with a defending pawn is neither KBNK nor KNNKP.
        "7k/7p/8/8/8/8/3BN3/4K3 w - - 0 1",
        // KPK with an extra knight is a general ending.
        "7k/8/8/4P3/4K3/8/8/6N1 w - - 0 1",
        // KRPKR with an extra defender knight belongs to no retained class.
        "7k/7r/7n/8/4P3/8/3R4/4K3 w - - 0 1",
        // Eight pieces must leave through the cheap common-path cutoff.
        "6k1/5ppr/7p/8/3PP3/8/3R1P2/4K3 w - - 0 1",
    };
    for (cases) |fen_text| {
        var item = try parsed(fen_text);
        item.value.rebind(&item.root);
        try std.testing.expect(recognize(&item.value) == null);
    }
}

test "boundary relations distinguish convertible and fortress cases" {
    var won = try parsed("k7/4P3/4K3/8/8/8/8/8 w - - 0 1");
    var fortress = try parsed("7k/7P/8/8/8/8/4K3/8 w - - 0 1");
    won.value.rebind(&won.root);
    fortress.value.rebind(&fortress.root);
    const won_value = recognize(&won.value).?.value.white_value;
    const fortress_value = recognize(&fortress.value).?.value.white_value;
    try std.testing.expect(won_value > fortress_value);

    var opposite = try parsed("7k/7b/8/8/4P3/8/3B4/4K3 w - - 0 1");
    var same = try parsed("7k/7b/8/8/4P3/8/2B5/4K3 w - - 0 1");
    opposite.value.rebind(&opposite.root);
    same.value.rebind(&same.root);
    try std.testing.expect(recognize(&opposite.value).?.scale.factor < recognize(&same.value).?.scale.factor);
}

test "specialized values and scales respond to geometry and tempo" {
    // FUNC-006: driving the weak king to the edge and moving first are both
    // conversion resources in Q-v-R; neither changes the exact signature.
    var edge = try parsed("7k/7r/8/8/8/8/4Q3/4K3 w - - 0 1");
    var centre = try parsed("8/7r/8/3k4/8/8/4Q3/4K3 w - - 0 1");
    var defender_moves = try parsed("7k/7r/8/8/8/8/4Q3/4K3 b - - 0 1");
    edge.value.rebind(&edge.root);
    centre.value.rebind(&centre.root);
    defender_moves.value.rebind(&defender_moves.root);
    const edge_value = recognize(&edge.value).?.value.white_value;
    const centre_value = recognize(&centre.value).?.value.white_value;
    const defender_value = recognize(&defender_moves.value).?.value.white_value;
    try std.testing.expect(edge_value > centre_value);
    try std.testing.expect(edge_value > defender_value);

    // In R+P-v-R, a supporting king beside its pawn with the defender far
    // from promotion is more convertible than the reversed king geometry.
    var supported = try parsed("k7/7r/8/4P3/4K3/8/3R4/8 w - - 0 1");
    var blockaded = try parsed("8/4k2r/8/4P3/8/8/3R4/K7 w - - 0 1");
    supported.value.rebind(&supported.root);
    blockaded.value.rebind(&blockaded.root);
    try std.testing.expect(
        recognize(&supported.value).?.scale.factor > recognize(&blockaded.value).?.scale.factor,
    );
}

test "color and rank flip negates value and preserves scale" {
    const pairs = [_][2][]const u8{
        .{
            "7k/8/8/4P3/4K3/8/8/8 w - - 0 1",
            "8/8/8/4k3/4p3/8/8/7K b - - 0 1",
        },
        .{
            "7k/7b/8/8/4P3/8/3B4/4K3 w - - 0 1",
            "4k3/3b4/8/4p3/8/8/7B/7K b - - 0 1",
        },
    };
    for (pairs) |pair| {
        var left = try parsed(pair[0]);
        var right = try parsed(pair[1]);
        left.value.rebind(&left.root);
        right.value.rebind(&right.root);
        const a = recognize(&left.value).?;
        const b = recognize(&right.value).?;
        switch (a) {
            .value => |a_value| try std.testing.expectEqual(-a_value.white_value, b.value.white_value),
            .scale => |a_scale| try std.testing.expectEqual(a_scale.factor, b.scale.factor),
        }
    }
}

fn colorFlip(original: *const position.Position, root: *position.PositionState) !position.Position {
    var twin = position.Position.initEmpty(root);
    twin.side_to_move = original.side_to_move.opposite();
    root.rule50 = original.current.rule50;
    for (original.physical.board, 0..) |piece, square_index| {
        if (piece == .none) continue;
        const source = types.Square.fromIndex(@intCast(square_index));
        const destination = source.flipRank();
        twin.physical.board[destination.index()] = types.Piece.make(
            piece.color().opposite(),
            piece.pieceType(),
        );
    }
    try state.rebuildPhysical(&twin.physical);
    state.applyDerived(root, state.derive(&twin));
    return twin;
}
