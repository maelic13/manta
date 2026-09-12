//! Configurable, allocation-free static exchange evaluation.
const std = @import("std");
const attacks = @import("attacks.zig");
const fen = @import("fen.zig");
const move = @import("move.zig");
const movegen = @import("movegen.zig");
const position = @import("position.zig");
const queries = @import("queries.zig");
const state = @import("state.zig");
const transition = @import("transition.zig");
const types = @import("types.zig");

/// SEE is a board service, so evaluation owns the values and supplies them.
/// This prevents the board layer from freezing provisional HCE constants.
pub const PieceValues = struct {
    pawn: i32,
    knight: i32,
    bishop: i32,
    rook: i32,
    queen: i32,
    king: i32,

    pub inline fn of(self: PieceValues, piece_type: types.PieceType) i32 {
        return switch (piece_type) {
            .none => 0,
            .pawn => self.pawn,
            .knight => self.knight,
            .bishop => self.bishop,
            .rook => self.rook,
            .queen => self.queen,
            .king => self.king,
        };
    }

    pub fn isValid(self: PieceValues) bool {
        return self.pawn >= 0 and self.knight >= 0 and self.bishop >= 0 and
            self.rook >= 0 and self.queen >= 0 and self.king >= 0;
    }
};

/// Reports whether a legal move meets `threshold` under static exchange.
///
/// A quiet move is priced by the same exchange as a capture, with no initial
/// gain: the mover arrives on an empty square and the opponent may take it
/// there. That is what makes "this square is not losing" a statement about the
/// board rather than about the move's kind, which ADR-0071 F's first-ply
/// quiescence checks need -- a queen delivering a spite check onto a
/// pawn-attacked square must price as losing a queen.
///
/// Castling is the one exception and keeps the conventional zero: it moves two
/// pieces at once, and the king can never be captured, so an exchange on the
/// king's destination alone says nothing about the move.
///
/// Recaptures are filtered by full king safety, which covers absolute pins and
/// illegal king captures.
pub fn atLeast(
    value: *const position.Position,
    chess_move: move.Move,
    threshold: i32,
    comptime values: PieceValues,
) bool {
    std.debug.assert(values.isValid());
    std.debug.assert(movegen.isLegal(value, chess_move));
    if (chess_move.kind() == .castling) {
        return threshold <= 0;
    }
    if (chess_move.to().rank() == .one or chess_move.to().rank() == .eight) {
        // A recapturing pawn can promote on these ranks. The exact gain-array
        // path below retains that uncommon transformation.
        return exchangeScore(value, chess_move, values) >= threshold;
    }
    return exchangeAtLeast(value, chess_move, threshold, values);
}

const Attacker = struct {
    square: types.Square,
    piece_type: types.PieceType,
};

fn exchangeAtLeast(
    value: *const position.Position,
    chess_move: move.Move,
    threshold: i32,
    comptime values: PieceValues,
) bool {
    const us = value.side_to_move;
    const target = chess_move.to();
    const moving = value.physical.pieceOn(chess_move.from()).pieceType();
    const occupant = if (chess_move.kind() == .promotion)
        chess_move.promotionPiece()
    else
        moving;
    const initial_gain = @as(i64, values.of(capturedType(value, chess_move))) +
        promotionBonusForMove(chess_move, values);
    var balance = initial_gain - threshold;
    if (balance < 0) return false;
    balance = @as(i64, values.of(occupant)) - balance;
    if (balance <= 0) return true;

    var occupied = value.physical.occupied() & ~chess_move.from().bit();
    if (chess_move.kind() == .en_passant) {
        occupied &= ~enPassantCapturedSquare(target, us).bit();
    } else {
        occupied &= ~target.bit();
    }
    if (discoversCheckAwayFromTarget(value, chess_move.from(), target, us, occupied)) {
        return true;
    }
    var attackers = queries.attackersTo(value, target, occupied) & occupied;
    var side = us.opposite();
    var result = true;
    while (leastLegalAttacker(value, target, side, occupied, attackers, values)) |attacker| {
        result = !result;
        balance = @as(i64, values.of(attacker.piece_type)) - balance;
        if (balance < @as(i64, if (result) 1 else 0)) break;
        if (attacker.piece_type == .king) return result;

        const next_occupied = occupied & ~attacker.square.bit();
        if (discoversCheckAwayFromTarget(value, attacker.square, target, side, next_occupied)) {
            break;
        }
        occupied = next_occupied;
        attackers &= occupied;
        revealAttackers(value, target, occupied, &attackers, attacker.piece_type);
        side = side.opposite();
    }
    return result;
}

fn exchangeScore(
    value: *const position.Position,
    chess_move: move.Move,
    comptime values: PieceValues,
) i64 {
    const us = value.side_to_move;
    const target = chess_move.to();
    const moving = value.physical.pieceOn(chess_move.from()).pieceType();
    const captured = capturedType(value, chess_move);
    var occupant = if (chess_move.kind() == .promotion)
        chess_move.promotionPiece()
    else
        moving;

    var gains: [32]i64 = undefined;
    gains[0] = @as(i64, values.of(captured)) + promotionBonusForMove(chess_move, values);

    // The piece occupying the exchange square is represented abstractly.
    // Remaining original pieces stay in `occupied` until selected as attackers.
    var occupied = value.physical.occupied() & ~chess_move.from().bit();
    if (chess_move.kind() == .en_passant) {
        occupied &= ~enPassantCapturedSquare(target, us).bit();
    } else {
        occupied &= ~target.bit();
    }
    if (discoversCheckAwayFromTarget(value, chess_move.from(), target, us, occupied)) {
        return gains[0];
    }

    var side = us.opposite();
    var depth: usize = 0;
    var attackers = queries.attackersTo(value, target, occupied) & occupied;
    while (leastLegalAttacker(value, target, side, occupied, attackers, values)) |attacker| {
        std.debug.assert(depth + 1 < gains.len);
        depth += 1;
        const promotes = attacker.piece_type == .pawn and
            types.relativeRank(side, target.rank()) == .eight;
        gains[depth] = @as(i64, values.of(occupant)) +
            promotionBonus(promotes, .queen, values) - gains[depth - 1];
        occupant = if (promotes) .queen else attacker.piece_type;
        const next_occupied = occupied & ~attacker.square.bit();
        if (discoversCheckAwayFromTarget(value, attacker.square, target, side, next_occupied)) {
            break;
        }
        occupied = next_occupied;
        attackers &= occupied;
        revealAttackers(value, target, occupied, &attackers, attacker.piece_type);
        side = side.opposite();
    }

    while (depth != 0) {
        gains[depth - 1] = -@max(-gains[depth - 1], gains[depth]);
        depth -= 1;
    }
    return gains[0];
}

fn revealAttackers(
    value: *const position.Position,
    target: types.Square,
    occupied: types.Bitboard,
    attackers: *types.Bitboard,
    removed: types.PieceType,
) void {
    if (removed == .pawn or removed == .bishop or removed == .queen) {
        attackers.* |= attacks.bishop(target, occupied) &
            (value.physical.by_type[types.PieceType.bishop.index()] |
                value.physical.by_type[types.PieceType.queen.index()]) & occupied;
    }
    if (removed == .rook or removed == .queen) {
        attackers.* |= attacks.rook(target, occupied) &
            (value.physical.by_type[types.PieceType.rook.index()] |
                value.physical.by_type[types.PieceType.queen.index()]) & occupied;
    }
}

fn leastLegalAttacker(
    value: *const position.Position,
    target: types.Square,
    side: types.Color,
    occupied: types.Bitboard,
    attackers: types.Bitboard,
    comptime values: PieceValues,
) ?Attacker {
    const candidates = attackers & value.physical.by_color[side.index()] & occupied;
    const order = comptime pieceOrder(values);
    inline for (order, 0..) |piece_type, order_index| {
        if (comptime order_index != 0 and
            values.of(piece_type) == values.of(order[order_index - 1])) continue;

        var equal_value_types: types.Bitboard = 0;
        inline for (order) |candidate_type| {
            if (comptime values.of(candidate_type) == values.of(piece_type)) {
                equal_value_types |= value.physical.by_type[candidate_type.index()];
            }
        }
        var equal_value_candidates = candidates & equal_value_types;
        while (equal_value_candidates != 0) {
            const square = types.Square.fromIndex(@intCast(@ctz(equal_value_candidates)));
            equal_value_candidates &= equal_value_candidates - 1;
            if (recaptureIsLegal(value, square, target, side, occupied)) {
                return .{ .square = square, .piece_type = value.physical.pieceOn(square).pieceType() };
            }
        }
    }
    return null;
}

fn pieceOrder(comptime values: PieceValues) [6]types.PieceType {
    var result = [_]types.PieceType{ .pawn, .knight, .bishop, .rook, .queen, .king };
    for (1..result.len) |index| {
        const selected = result[index];
        var insertion = index;
        while (insertion != 0 and values.of(selected) < values.of(result[insertion - 1])) {
            result[insertion] = result[insertion - 1];
            insertion -= 1;
        }
        result[insertion] = selected;
    }
    return result;
}

fn recaptureIsLegal(
    value: *const position.Position,
    from: types.Square,
    target: types.Square,
    side: types.Color,
    occupied: types.Bitboard,
) bool {
    const piece_type = value.physical.pieceOn(from).pieceType();
    const after = (occupied & ~from.bit()) | target.bit();
    if (piece_type == .king) {
        return !queries.isAttackedByExcluding(
            value,
            target,
            after,
            side.opposite(),
            target.bit(),
        );
    }

    // Before this recapture, any non-slider attack on our king was either
    // already illegal or came from the contested-square occupant that this
    // move removes. Only vacating `from` can reveal a new absolute slider pin.
    const king = queries.kingSquare(value, side);
    const target_bit = target.bit();
    const from_bit = from.bit();
    const them = side.opposite();
    const present = value.physical.by_color[them.index()] & after & ~target_bit;
    if (attacks.rook_rays[king.index()] & from_bit != 0) {
        if (attacks.line[king.index()][from.index()] & target_bit != 0) return true;
        return attacks.rook(king, after) &
            (value.physical.by_type[types.PieceType.rook.index()] |
                value.physical.by_type[types.PieceType.queen.index()]) & present == 0;
    }
    if (attacks.bishop_rays[king.index()] & from_bit != 0) {
        if (attacks.line[king.index()][from.index()] & target_bit != 0) return true;
        return attacks.bishop(king, after) &
            (value.physical.by_type[types.PieceType.bishop.index()] |
                value.physical.by_type[types.PieceType.queen.index()]) & present == 0;
    }
    return true;
}

/// A capture can vacate a slider line and check the opposing king somewhere
/// other than the contested square. A nominal recapture on `target` cannot
/// answer that check, so the exchange ends after the checking capture.
fn discoversCheckAwayFromTarget(
    value: *const position.Position,
    from: types.Square,
    target: types.Square,
    mover: types.Color,
    occupied_without_from: types.Bitboard,
) bool {
    const king = queries.kingSquare(value, mover.opposite());
    const from_bit = from.bit();
    const occupied = occupied_without_from | target.bit();
    const present = value.physical.by_color[mover.index()] & occupied & ~target.bit();
    if (attacks.rook_rays[king.index()] & from_bit != 0) {
        return attacks.rook(king, occupied) &
            (value.physical.by_type[types.PieceType.rook.index()] |
                value.physical.by_type[types.PieceType.queen.index()]) & present != 0;
    }
    if (attacks.bishop_rays[king.index()] & from_bit != 0) {
        return attacks.bishop(king, occupied) &
            (value.physical.by_type[types.PieceType.bishop.index()] |
                value.physical.by_type[types.PieceType.queen.index()]) & present != 0;
    }
    return false;
}

fn capturedType(value: *const position.Position, chess_move: move.Move) types.PieceType {
    if (chess_move.kind() == .en_passant) return .pawn;
    const captured = value.physical.pieceOn(chess_move.to());
    return if (captured == .none) .none else captured.pieceType();
}

fn promotionBonus(promotes: bool, promoted: types.PieceType, values: PieceValues) i64 {
    if (!promotes) return 0;
    return @as(i64, values.of(promoted)) - values.pawn;
}

fn promotionBonusForMove(chess_move: move.Move, values: PieceValues) i64 {
    return if (chess_move.kind() == .promotion)
        promotionBonus(true, chess_move.promotionPiece(), values)
    else
        0;
}

fn enPassantCapturedSquare(target: types.Square, capturer: types.Color) types.Square {
    const offset: i8 = if (capturer == .white) -8 else 8;
    return types.Square.fromIndex(@intCast(@as(i8, @intCast(target.index())) + offset));
}

const test_values = PieceValues{
    .pawn = 100,
    .knight = 320,
    .bishop = 330,
    .rook = 500,
    .queen = 900,
    .king = 20_000,
};

/// Independent exact legal-capture minimax used only by tests. Unlike the
/// production swap-list implementation, it makes moves and generates every
/// legal recapture to the contested square.
fn oracleReply(value: *position.Position, target: types.Square, values: PieceValues) i64 {
    var captures = position.MoveList.init();
    movegen.generate(.captures, value, &captures);
    var best: i64 = 0;
    for (captures.slice()) |candidate| {
        if (candidate.to() != target) continue;
        const immediate = @as(i64, values.of(capturedType(value, candidate))) +
            promotionBonusForMove(candidate, values);
        var child: position.PositionState = .{};
        transition.makeMove(value, candidate, &child);
        const result = immediate - oracleReply(value, target, values);
        transition.unmakeMove(value, candidate);
        best = @max(best, result);
    }
    return best;
}

fn oracleScore(value: *position.Position, chess_move: move.Move, values: PieceValues) i64 {
    const immediate = @as(i64, values.of(capturedType(value, chess_move))) +
        promotionBonusForMove(chess_move, values);
    const target = chess_move.to();
    var child: position.PositionState = .{};
    transition.makeMove(value, chess_move, &child);
    const result = immediate - oracleReply(value, target, values);
    transition.unmakeMove(value, chess_move);
    return result;
}

test "threshold SEE agrees with legal exchange oracle" {
    const fixtures = [_]struct { fen_text: []const u8, move_text: []const u8 }{
        .{ .fen_text = "4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1", .move_text = "e4d5" },
        .{ .fen_text = "4k3/8/8/3p4/4P3/8/6b1/4K3 w - - 0 1", .move_text = "e4d5" },
        .{ .fen_text = "4k3/4p3/3n4/2B5/8/8/8/K3R3 w - - 0 1", .move_text = "c5d6" },
        .{ .fen_text = "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", .move_text = "e5d6" },
        .{ .fen_text = "1r5k/P7/8/8/8/8/8/7K w - - 0 1", .move_text = "a7b8q" },
        // Bxb3 vacates a2 and discovers Ra1+ away from b3. The d4 knight
        // attacks b3 geometrically, but cannot recapture while its king is in
        // check. The make/generate oracle independently enforces that rule.
        .{ .fen_text = "k7/8/8/8/3n4/1p6/B7/R6K w - - 0 1", .move_text = "a2b3" },
    };
    for (fixtures) |fixture| {
        var root: position.PositionState = .{};
        var value = try fen.parse(fixture.fen_text, &root);
        try std.testing.expect(state.isConsistent(&value));
        const chess_move = try @import("notation.zig").parseLegal(&value, fixture.move_text);
        const expected = oracleScore(&value, chess_move, test_values);
        try std.testing.expect(state.isConsistent(&value));

        var threshold: i32 = -1_000;
        while (threshold <= 1_200) : (threshold += 25) {
            try std.testing.expectEqual(
                expected >= threshold,
                atLeast(&value, chess_move, threshold, test_values),
            );
        }
    }
}

test "pinned recapturer is excluded from SEE" {
    var root: position.PositionState = .{};
    const value = try fen.parse(
        "4k3/4p3/3n4/2B5/8/8/8/K3R3 w - - 0 1",
        &root,
    );
    const chess_move = try @import("notation.zig").parseLegal(&value, "c5d6");
    try std.testing.expect(atLeast(&value, chess_move, 300, test_values));
    try std.testing.expect(!atLeast(&value, chess_move, 325, test_values));
}

test "king recapture is admitted only when the exchange square is safe" {
    const fixtures = [_]struct { fen_text: []const u8, expected: i32 }{
        .{ .fen_text = "4k3/4p3/8/8/8/8/4R3/4K3 w - - 0 1", .expected = -400 },
        .{ .fen_text = "4k3/4p3/8/8/1B6/8/4R3/4K3 w - - 0 1", .expected = 100 },
    };
    for (fixtures) |fixture| {
        var root: position.PositionState = .{};
        const value = try fen.parse(fixture.fen_text, &root);
        try std.testing.expect(state.isConsistent(&value));
        const chess_move = try @import("notation.zig").parseLegal(&value, "e2e7");
        try std.testing.expect(atLeast(&value, chess_move, fixture.expected, test_values));
        try std.testing.expect(!atLeast(&value, chess_move, fixture.expected + 1, test_values));
    }
}
