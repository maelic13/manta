//! Position-level attack and king-safety queries.
const std = @import("std");
const attacks = @import("attacks.zig");
const position = @import("position.zig");
const types = @import("types.zig");

pub fn kingSquare(value: *const position.Position, color: types.Color) types.Square {
    const square = value.physical.king_square[color.index()];
    std.debug.assert(square != .none and value.physical.pieceOn(square) == types.Piece.make(color, .king));
    return square;
}

pub fn attackersTo(
    value: *const position.Position,
    square: types.Square,
    occupied: types.Bitboard,
) types.Bitboard {
    const physical = &value.physical;
    const pawns = physical.by_type[types.PieceType.pawn.index()] & occupied;
    const knights = physical.by_type[types.PieceType.knight.index()] & occupied;
    const bishops = physical.by_type[types.PieceType.bishop.index()] & occupied;
    const rooks = physical.by_type[types.PieceType.rook.index()] & occupied;
    const queens = physical.by_type[types.PieceType.queen.index()] & occupied;
    const kings = physical.by_type[types.PieceType.king.index()] & occupied;
    return (attacks.pawn[types.Color.black.index()][square.index()] &
        pawns & physical.by_color[types.Color.white.index()]) |
        (attacks.pawn[types.Color.white.index()][square.index()] &
            pawns & physical.by_color[types.Color.black.index()]) |
        (attacks.knight[square.index()] & knights) |
        (attacks.bishop(square, occupied) & (bishops | queens)) |
        (attacks.rook(square, occupied) & (rooks | queens)) |
        (attacks.king[square.index()] & kings);
}

pub fn attackersToBy(
    value: *const position.Position,
    square: types.Square,
    occupied: types.Bitboard,
    color: types.Color,
) types.Bitboard {
    return attackersToByExcluding(value, square, occupied, color, 0);
}

/// Computes attacks after hypothetical captures without mutating the position.
/// `excluded` removes captured pieces whose destination remains occupied by the
/// mover and therefore cannot be represented by occupancy alone.
pub fn attackersToByExcluding(
    value: *const position.Position,
    square: types.Square,
    occupied: types.Bitboard,
    color: types.Color,
    excluded: types.Bitboard,
) types.Bitboard {
    const physical = &value.physical;
    const present = physical.by_color[color.index()] & occupied & ~excluded;
    const pawns = physical.by_type[types.PieceType.pawn.index()] & present;
    const knights = physical.by_type[types.PieceType.knight.index()] & present;
    const bishops = physical.by_type[types.PieceType.bishop.index()] & present;
    const rooks = physical.by_type[types.PieceType.rook.index()] & present;
    const queens = physical.by_type[types.PieceType.queen.index()] & present;
    const kings = physical.by_type[types.PieceType.king.index()] & present;

    return (attacks.pawn[color.opposite().index()][square.index()] & pawns) |
        (attacks.knight[square.index()] & knights) |
        (attacks.bishop(square, occupied) & (bishops | queens)) |
        (attacks.rook(square, occupied) & (rooks | queens)) |
        (attacks.king[square.index()] & kings);
}

pub fn isAttacked(value: *const position.Position, square: types.Square, by: types.Color) bool {
    return isAttackedByExcluding(value, square, value.physical.occupied(), by, 0);
}

/// Boolean king-safety query ordered from cheap leapers to sliding attacks.
/// `excluded` has the same hypothetical-capture meaning as in
/// `attackersToByExcluding`.
pub inline fn isAttackedByExcluding(
    value: *const position.Position,
    square: types.Square,
    occupied: types.Bitboard,
    color: types.Color,
    excluded: types.Bitboard,
) bool {
    const physical = &value.physical;
    const present = physical.by_color[color.index()] & occupied & ~excluded;
    if (attacks.pawn[color.opposite().index()][square.index()] &
        physical.by_type[types.PieceType.pawn.index()] & present != 0) return true;
    if (attacks.knight[square.index()] &
        physical.by_type[types.PieceType.knight.index()] & present != 0) return true;
    if (attacks.king[square.index()] &
        physical.by_type[types.PieceType.king.index()] & present != 0) return true;
    if (attacks.bishop(square, occupied) &
        (physical.by_type[types.PieceType.bishop.index()] |
            physical.by_type[types.PieceType.queen.index()]) & present != 0) return true;
    return attacks.rook(square, occupied) &
        (physical.by_type[types.PieceType.rook.index()] |
            physical.by_type[types.PieceType.queen.index()]) & present != 0;
}

pub fn hasLegalEnPassantCapture(
    value: *const position.Position,
    target: types.Square,
    capturer: types.Color,
) bool {
    if (target == .none) return false;
    const candidates = attacks.pawn[capturer.opposite().index()][target.index()] &
        value.physical.pieces(capturer, .pawn);
    var remaining = candidates;
    while (remaining != 0) {
        const from = types.Square.fromIndex(@intCast(@ctz(remaining)));
        if (isLegalEnPassantFrom(value, from, target, capturer)) return true;
        remaining &= remaining - 1;
    }
    return false;
}

pub fn isLegalEnPassantFrom(
    value: *const position.Position,
    from: types.Square,
    target: types.Square,
    capturer: types.Color,
) bool {
    if (from == .none or target == .none) return false;
    const physical = &value.physical;
    const required_rank: types.Rank = if (capturer == .white) .six else .three;
    if (target.rank() != required_rank) return false;
    if (physical.pieceOn(from) != types.Piece.make(capturer, .pawn)) return false;
    if (physical.pieceOn(target) != .none) return false;
    if (attacks.pawn[capturer.index()][from.index()] & target.bit() == 0) return false;

    const capture_offset: i8 = if (capturer == .white) -8 else 8;
    const captured_index: i8 = @as(i8, @intCast(target.index())) + capture_offset;
    if (captured_index < 0 or captured_index >= 64) return false;
    const captured = types.Square.fromIndex(@intCast(captured_index));
    if (physical.pieceOn(captured) != types.Piece.make(capturer.opposite(), .pawn)) return false;
    const origin_index = @as(i8, @intCast(target.index())) - capture_offset;
    const origin = types.Square.fromIndex(@intCast(origin_index));
    if (physical.pieceOn(origin) != .none) return false;

    var occupied = physical.occupied();
    occupied &= ~from.bit();
    occupied &= ~captured.bit();
    occupied |= target.bit();
    return !isAttackedByExcluding(
        value,
        kingSquare(value, capturer),
        occupied,
        capturer.opposite(),
        0,
    );
}

test "attack queries respect color and hypothetical occupancy" {
    // The query is a board fact consumed by FEN validation, legal king/EP
    // handling, move generation and SEE. Removed hypothetical pieces cannot
    // remain attackers merely because their physical bitboard is unchanged.
    var root: position.PositionState = .{};
    var value = position.Position.initEmpty(&root);
    value.physical.board[types.Square.e1.index()] = .white_king;
    value.physical.board[types.Square.e8.index()] = .black_king;
    value.physical.board[types.Square.d2.index()] = .white_pawn;
    value.physical.board[types.Square.b4.index()] = .black_bishop;
    value.physical.by_type[types.PieceType.none.index()] = types.Square.e1.bit() |
        types.Square.e8.bit() | types.Square.d2.bit() | types.Square.b4.bit();
    value.physical.by_type[types.PieceType.pawn.index()] = types.Square.d2.bit();
    value.physical.by_type[types.PieceType.bishop.index()] = types.Square.b4.bit();
    value.physical.by_type[types.PieceType.king.index()] = types.Square.e1.bit() |
        types.Square.e8.bit();
    value.physical.by_color[types.Color.white.index()] = types.Square.e1.bit() |
        types.Square.d2.bit();
    value.physical.by_color[types.Color.black.index()] = types.Square.e8.bit() |
        types.Square.b4.bit();
    value.physical.piece_count[types.Piece.white_king.index()] = 1;
    value.physical.piece_count[types.Piece.black_king.index()] = 1;
    value.physical.piece_count[types.Piece.white_pawn.index()] = 1;
    value.physical.piece_count[types.Piece.black_bishop.index()] = 1;
    value.physical.king_square = .{ .e1, .e8 };

    try std.testing.expect(attackersToBy(&value, .e3, value.physical.occupied(), .white) &
        types.Square.d2.bit() != 0);
    try std.testing.expect(!isAttacked(&value, .e1, .black));
    try std.testing.expect(attackersToBy(
        &value,
        .e1,
        value.physical.occupied() & ~types.Square.d2.bit(),
        .black,
    ) & types.Square.b4.bit() != 0);
    try std.testing.expectEqual(
        @as(types.Bitboard, 0),
        attackersToBy(
            &value,
            .e3,
            value.physical.occupied() & ~types.Square.d2.bit(),
            .white,
        ),
    );
}
