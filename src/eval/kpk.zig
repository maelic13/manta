//! Exact king-and-pawn versus king win/draw bitbase.
//!
//! States are normalized to a White pawn on files a-d. The table is derived
//! at compile time from legal king and pawn moves; it is immutable, allocation
//! free and returns only win/draw evidence for the ordinary evaluator.
const std = @import("std");
const types = @import("../chess/types.zig");

const pawn_file_count = 4;
const pawn_rank_count = 6;
const pawn_count = pawn_file_count * pawn_rank_count;
const state_count = 2 * pawn_count * 64 * 64;
pub const word_count = (state_count + 63) / 64;
pub const byte_count = word_count * @sizeOf(u64);

const State = struct {
    strong_to_move: bool,
    pawn: u6,
    strong_king: u6,
    weak_king: u6,
};

const embedded = @embedFile("kpk.bin");

/// True exactly when the pawn side can force promotion or mate. Draw is the
/// only other legal KPK outcome; the caller decides how ordinary scores encode
/// that classification.
pub fn isWin(
    strong_king_value: types.Square,
    weak_king_value: types.Square,
    pawn_value: types.Square,
    strong_side: types.Color,
    side_to_move: types.Color,
) bool {
    std.debug.assert(embedded.len == byte_count);
    var strong_king = strong_king_value;
    var weak_king = weak_king_value;
    var pawn = pawn_value;
    if (strong_side == .black) {
        strong_king = strong_king.flipRank();
        weak_king = weak_king.flipRank();
        pawn = pawn.flipRank();
    }
    if (pawn.file().index() >= types.File.e.index()) {
        strong_king = strong_king.flipFile();
        weak_king = weak_king.flipFile();
        pawn = pawn.flipFile();
    }
    if (pawn.rank().index() < types.Rank.two.index() or
        pawn.rank().index() > types.Rank.seven.index()) return false;

    const item: State = .{
        .strong_to_move = side_to_move == strong_side,
        .pawn = @intCast(pawn.index()),
        .strong_king = @intCast(strong_king.index()),
        .weak_king = @intCast(weak_king.index()),
    };
    if (!legal(item)) return false;
    return embeddedBitIsSet(indexOf(item));
}

/// Derive the checked embedded artifact. This is called only by the offline
/// generator; ordinary builds consume `kpk.bin` directly.
pub fn buildWins() [word_count]u64 {
    var result = [_]u64{0} ** word_count;
    var changed = true;
    while (changed) {
        changed = false;
        for (0..2) |turn| {
            for (0..pawn_file_count) |file| {
                for (1..pawn_rank_count + 1) |rank| {
                    const pawn: u6 = @intCast(rank * 8 + file);
                    for (0..64) |strong_king| {
                        for (0..64) |weak_king| {
                            const item: State = .{
                                .strong_to_move = turn == 0,
                                .pawn = pawn,
                                .strong_king = @intCast(strong_king),
                                .weak_king = @intCast(weak_king),
                            };
                            if (!legal(item)) continue;
                            const index = indexOf(item);
                            if (bitIsSet(&result, index)) continue;
                            if (winningSuccessor(&result, item)) {
                                setBit(&result, index);
                                changed = true;
                            }
                        }
                    }
                }
            }
        }
    }
    return result;
}

fn winningSuccessor(table: *const [word_count]u64, item: State) bool {
    return if (item.strong_to_move)
        strongCanForce(table, item)
    else
        weakCannotEscape(table, item);
}

fn strongCanForce(table: *const [word_count]u64, item: State) bool {
    const strong_file = fileOf(item.strong_king);
    const strong_rank = rankOf(item.strong_king);
    var file_delta: i32 = -1;
    while (file_delta <= 1) : (file_delta += 1) {
        var rank_delta: i32 = -1;
        while (rank_delta <= 1) : (rank_delta += 1) {
            if (file_delta == 0 and rank_delta == 0) continue;
            const destination = squareAt(strong_file + file_delta, strong_rank + rank_delta) orelse continue;
            if (destination == item.pawn or destination == item.weak_king) continue;
            if (kingsTouch(destination, item.weak_king)) continue;
            const next: State = .{
                .strong_to_move = false,
                .pawn = item.pawn,
                .strong_king = destination,
                .weak_king = item.weak_king,
            };
            if (bitIsSet(table, indexOf(next))) return true;
        }
    }

    const one = item.pawn + 8;
    if (one != item.strong_king and one != item.weak_king) {
        if (rankOf(item.pawn) == 6) return promotionWins(item, one);
        const next: State = .{
            .strong_to_move = false,
            .pawn = one,
            .strong_king = item.strong_king,
            .weak_king = item.weak_king,
        };
        if (bitIsSet(table, indexOf(next))) return true;

        if (rankOf(item.pawn) == 1) {
            const two = item.pawn + 16;
            if (two != item.strong_king and two != item.weak_king) {
                const jumped: State = .{
                    .strong_to_move = false,
                    .pawn = two,
                    .strong_king = item.strong_king,
                    .weak_king = item.weak_king,
                };
                if (bitIsSet(table, indexOf(jumped))) return true;
            }
        }
    }
    return false;
}

fn promotionWins(item: State, promotion: u6) bool {
    // A bare king may capture the promoted piece unless the strong king
    // protects its square. Otherwise KQK/KRK is won, except for an immediate
    // stalemate; try both queen and rook because underpromotion can avoid it.
    if (kingsTouch(item.weak_king, promotion) and !kingsTouch(item.strong_king, promotion))
        return false;
    return promotedPositionWins(item, promotion, true) or
        promotedPositionWins(item, promotion, false);
}

fn promotedPositionWins(item: State, promotion: u6, queen: bool) bool {
    const weak_file = fileOf(item.weak_king);
    const weak_rank = rankOf(item.weak_king);
    var file_delta: i32 = -1;
    while (file_delta <= 1) : (file_delta += 1) {
        var rank_delta: i32 = -1;
        while (rank_delta <= 1) : (rank_delta += 1) {
            if (file_delta == 0 and rank_delta == 0) continue;
            const destination = squareAt(weak_file + file_delta, weak_rank + rank_delta) orelse continue;
            if (destination == item.strong_king or kingsTouch(destination, item.strong_king)) continue;
            if (destination == promotion) continue;
            if (!promotedPieceAttacks(promotion, destination, item.strong_king, queen)) return true;
        }
    }
    // With no move, check is mate and no check is stalemate.
    return promotedPieceAttacks(promotion, item.weak_king, item.strong_king, queen);
}

fn promotedPieceAttacks(from: u6, target: u6, blocker: u6, queen: bool) bool {
    const file_delta = fileOf(target) - fileOf(from);
    const rank_delta = rankOf(target) - rankOf(from);
    const diagonal = @abs(file_delta) == @abs(rank_delta);
    if (file_delta != 0 and rank_delta != 0 and (!queen or !diagonal)) return false;
    const file_step: i32 = if (file_delta > 0) 1 else if (file_delta < 0) -1 else 0;
    const rank_step: i32 = if (rank_delta > 0) 1 else if (rank_delta < 0) -1 else 0;
    var file = fileOf(from) + file_step;
    var rank = rankOf(from) + rank_step;
    while (true) {
        const square = squareAt(file, rank).?;
        if (square == target) return true;
        if (square == blocker) return false;
        file += file_step;
        rank += rank_step;
    }
}

fn weakCannotEscape(table: *const [word_count]u64, item: State) bool {
    const weak_file = fileOf(item.weak_king);
    const weak_rank = rankOf(item.weak_king);
    var legal_moves: u4 = 0;
    var file_delta: i32 = -1;
    while (file_delta <= 1) : (file_delta += 1) {
        var rank_delta: i32 = -1;
        while (rank_delta <= 1) : (rank_delta += 1) {
            if (file_delta == 0 and rank_delta == 0) continue;
            const destination = squareAt(weak_file + file_delta, weak_rank + rank_delta) orelse continue;
            if (destination == item.strong_king or kingsTouch(destination, item.strong_king)) continue;
            if (destination == item.pawn) {
                legal_moves += 1;
                return false;
            }
            if (pawnAttacks(item.pawn, destination)) continue;
            legal_moves += 1;
            const next: State = .{
                .strong_to_move = true,
                .pawn = item.pawn,
                .strong_king = item.strong_king,
                .weak_king = destination,
            };
            if (!bitIsSet(table, indexOf(next))) return false;
        }
    }
    if (legal_moves != 0) return true;
    return pawnAttacks(item.pawn, item.weak_king);
}

fn legal(item: State) bool {
    if (item.pawn == item.strong_king or item.pawn == item.weak_king or
        item.strong_king == item.weak_king or kingsTouch(item.strong_king, item.weak_king)) return false;
    // If the pawn side is to move, the bare king just moved and may not have
    // left itself in pawn check. Pawn check is legal when the bare king is to
    // move and must answer it.
    return !item.strong_to_move or !pawnAttacks(item.pawn, item.weak_king);
}

fn indexOf(item: State) usize {
    const pawn_file = fileOf(item.pawn);
    const pawn_rank = rankOf(item.pawn) - 1;
    const pawn_index: usize = @intCast(pawn_file * pawn_rank_count + pawn_rank);
    const turn: usize = if (item.strong_to_move) 0 else 1;
    return (((turn * pawn_count + pawn_index) * 64 + item.strong_king) * 64 + item.weak_king);
}

fn bitIsSet(table: *const [word_count]u64, index: usize) bool {
    return table[index / 64] & (@as(u64, 1) << @intCast(index % 64)) != 0;
}

fn setBit(table: *[word_count]u64, index: usize) void {
    table[index / 64] |= @as(u64, 1) << @intCast(index % 64);
}

fn embeddedBitIsSet(index: usize) bool {
    return embedded[index / 8] & (@as(u8, 1) << @intCast(index % 8)) != 0;
}

fn pawnAttacks(pawn: u6, target: u6) bool {
    return rankOf(target) == rankOf(pawn) + 1 and
        @abs(fileOf(target) - fileOf(pawn)) == 1;
}

fn kingsTouch(a: u6, b: u6) bool {
    return @max(@abs(fileOf(a) - fileOf(b)), @abs(rankOf(a) - rankOf(b))) <= 1;
}

fn fileOf(square: u6) i32 {
    return @intCast(square & 7);
}

fn rankOf(square: u6) i32 {
    return @intCast(square >> 3);
}

fn squareAt(file: i32, rank: i32) ?u6 {
    if (file < 0 or file > 7 or rank < 0 or rank > 7) return null;
    return @intCast(rank * 8 + file);
}

test "exact KPK bitbase distinguishes fortress and safe promotion" {
    // A rook pawn whose king cannot dislodge the defender from the corner is
    // drawn, while a clear legal promotion is won.
    try std.testing.expect(!isWin(.c6, .a8, .a7, .white, .white));
    try std.testing.expect(isWin(.e6, .a8, .e7, .white, .white));

    // Rank/color normalization must preserve the result exactly.
    try std.testing.expect(isWin(.e3, .a1, .e2, .black, .black));
}
