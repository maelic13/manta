//! Allocation-free reversible chess-state transitions.
const std = @import("std");
const fen = @import("fen.zig");
const move = @import("move.zig");
const position = @import("position.zig");
const queries = @import("queries.zig");
const state = @import("state.zig");
const types = @import("types.zig");
const zobrist = @import("zobrist.zig");

/// Applies a legal generated move into caller-owned stable state storage.
/// Checked external moves must establish this function's preconditions first.
pub fn makeMove(value: *position.Position, chess_move: move.Move, child: *position.PositionState) void {
    std.debug.assert(chess_move.isChessMove());
    std.debug.assert(child != value.current);

    const parent = value.current;
    const us = value.side_to_move;
    const them = us.opposite();
    const from = chess_move.from();
    const to = chess_move.to();
    const moving = value.physical.pieceOn(from);
    std.debug.assert(moving != .none and moving.color() == us);

    child.key = parent.key;
    child.pawn_key = parent.pawn_key;
    child.minor_key = parent.minor_key;
    child.non_pawn_key = parent.non_pawn_key;
    child.previous = parent;
    // Only the `count`-selected delta prefix is observable; inactive entries
    // need no initialization on this hot path.
    child.delta.count = 0;
    child.ep_square = .none;
    child.captured_piece = .none;
    child.castling_rights = parent.castling_rights;
    child.rule50 = parent.rule50 +| 1;
    child.plies_from_null = parent.plies_from_null +| 1;
    child.repetition = 0;
    if (parent.ep_square != .none) {
        child.key ^= zobrist.tables.en_passant_file[parent.ep_square.file().index()];
    }

    const captured = switch (chess_move.kind()) {
        .en_passant => value.physical.pieceOn(enPassantCapturedSquare(to, us)),
        .castling => types.Piece.none,
        .normal, .promotion => value.physical.pieceOn(to),
    };
    std.debug.assert(captured == .none or
        (captured.color() == them and captured.pieceType() != .king));
    child.captured_piece = captured;

    switch (chess_move.kind()) {
        .normal => makeNormal(value, child, moving, captured, from, to),
        .promotion => makePromotion(value, child, moving, captured, chess_move, from, to),
        .en_passant => makeEnPassant(value, child, moving, captured, from, to, us),
        .castling => makeCastling(value, child, moving, from, to, us),
    }

    child.key ^= zobrist.tables.castling[parent.castling_rights.raw()];
    child.castling_rights = rightsAfterMove(parent.castling_rights, from, to);
    child.key ^= zobrist.tables.castling[child.castling_rights.raw()];
    if (moving.pieceType() == .pawn or captured != .none) child.rule50 = 0;

    if (moving.pieceType() == .pawn and chess_move.kind() == .normal and
        squareDistance(from, to) == 16)
    {
        const target = types.Square.fromIndex(@intCast(
            (@as(u7, from.index()) + @as(u7, to.index())) / 2,
        ));
        if (queries.hasLegalEnPassantCapture(value, target, them)) {
            child.ep_square = target;
            child.key ^= zobrist.tables.en_passant_file[target.file().index()];
        }
    }

    child.key ^= zobrist.tables.side;
    value.side_to_move = them;
    value.current = child;
    value.game_ply += 1;
    child.repetition = repetitionState(child);
    child.checkers = queries.attackersToBy(
        value,
        queries.kingSquare(value, them),
        value.physical.occupied(),
        us,
    );
}

/// Returns the nearest same-side state with an identical position key, negated
/// when that state was itself a repetition. Pawn moves, captures and null moves
/// bound the walk through the two counters.
///
/// The negation is what lets a consumer answer "has this position occurred
/// three times" without a second walk. No irreversible move can fall inside the
/// window, so the matched ancestor's own window is exactly this one shortened
/// by the distance travelled; an occurrence it recorded therefore lies inside
/// this window too, and any occurrence before the match lies inside its window.
fn repetitionState(child: *const position.PositionState) i16 {
    const limit: usize = @min(child.rule50, child.plies_from_null);
    // A legal non-null cycle needs at least four plies: after only one move by
    // each side, the first mover has not had a turn on which to restore its
    // changed piece fact. Null moves fence this walk through `plies_from_null`.
    if (limit < 4) return 0;

    var cursor = child.previous orelse return 0;
    cursor = cursor.previous orelse return 0;
    var distance: usize = 2;
    while (distance <= limit) : (distance += 2) {
        if (cursor.key == child.key) {
            const found: i16 = @intCast(distance);
            return if (cursor.repetition != 0) -found else found;
        }
        const odd = cursor.previous orelse break;
        cursor = odd.previous orelse break;
    }
    return 0;
}

pub fn unmakeMove(value: *position.Position, chess_move: move.Move) void {
    std.debug.assert(chess_move.isChessMove());
    const child = value.current;
    const parent = child.previous orelse unreachable;
    const them = value.side_to_move;
    const us = them.opposite();
    const from = chess_move.from();
    const to = chess_move.to();

    value.side_to_move = us;
    switch (chess_move.kind()) {
        .normal => {
            movePiece(&value.physical, to, from);
            if (child.captured_piece != .none) {
                putPiece(&value.physical, child.captured_piece, to);
            }
        },
        .promotion => {
            _ = removePiece(&value.physical, to);
            putPiece(&value.physical, types.Piece.make(us, .pawn), from);
            if (child.captured_piece != .none) {
                putPiece(&value.physical, child.captured_piece, to);
            }
        },
        .en_passant => {
            movePiece(&value.physical, to, from);
            putPiece(
                &value.physical,
                child.captured_piece,
                enPassantCapturedSquare(to, us),
            );
        },
        .castling => {
            const rook = castlingRookSquares(us, to);
            movePiece(&value.physical, to, from);
            movePiece(&value.physical, rook.to, rook.from);
        },
    }
    value.current = parent;
    value.game_ply -= 1;
}

/// Applies the search-only null move. It is not a played move: game ply and
/// rule-50 do not advance, and no factual piece delta is emitted.
pub fn makeNull(value: *position.Position, child: *position.PositionState) void {
    std.debug.assert(value.current.checkers == 0);
    std.debug.assert(child != value.current);
    const parent = value.current;
    child.* = .{
        .key = parent.key,
        .pawn_key = parent.pawn_key,
        .minor_key = parent.minor_key,
        .non_pawn_key = parent.non_pawn_key,
        .previous = parent,
        .castling_rights = parent.castling_rights,
        .rule50 = parent.rule50,
        .plies_from_null = 0,
    };
    if (parent.ep_square != .none) {
        child.key ^= zobrist.tables.en_passant_file[parent.ep_square.file().index()];
    }
    child.key ^= zobrist.tables.side;
    value.side_to_move = value.side_to_move.opposite();
    value.current = child;
    child.checkers = queries.attackersToBy(
        value,
        queries.kingSquare(value, value.side_to_move),
        value.physical.occupied(),
        value.side_to_move.opposite(),
    );
    std.debug.assert(child.checkers == 0);
}

pub fn unmakeNull(value: *position.Position) void {
    const child = value.current;
    std.debug.assert(child.delta.count == 0 and child.plies_from_null == 0);
    value.current = child.previous orelse unreachable;
    value.side_to_move = value.side_to_move.opposite();
}

fn makeNormal(
    value: *position.Position,
    child: *position.PositionState,
    moving: types.Piece,
    captured: types.Piece,
    from: types.Square,
    to: types.Square,
) void {
    if (captured != .none) {
        _ = removePiece(&value.physical, to);
        xorPiece(child, captured, to);
    }
    movePiece(&value.physical, from, to);
    xorPieceMove(child, moving, from, to);
    child.delta.append(.{ .piece = moving, .from = from, .to = to });
    if (captured != .none) child.delta.append(.{ .piece = captured, .from = to });
}

fn makePromotion(
    value: *position.Position,
    child: *position.PositionState,
    moving: types.Piece,
    captured: types.Piece,
    chess_move: move.Move,
    from: types.Square,
    to: types.Square,
) void {
    std.debug.assert(moving.pieceType() == .pawn);
    std.debug.assert(types.relativeRank(moving.color(), from.rank()) == .seven);
    std.debug.assert(types.relativeRank(moving.color(), to.rank()) == .eight);
    if (captured != .none) {
        _ = removePiece(&value.physical, to);
        xorPiece(child, captured, to);
    }
    _ = removePiece(&value.physical, from);
    xorPiece(child, moving, from);
    const promoted = types.Piece.make(moving.color(), chess_move.promotionPiece());
    putPiece(&value.physical, promoted, to);
    xorPiece(child, promoted, to);
    child.delta.append(.{ .piece = moving, .from = from });
    if (captured != .none) child.delta.append(.{ .piece = captured, .from = to });
    child.delta.append(.{ .piece = promoted, .to = to });
}

fn makeEnPassant(
    value: *position.Position,
    child: *position.PositionState,
    moving: types.Piece,
    captured: types.Piece,
    from: types.Square,
    to: types.Square,
    us: types.Color,
) void {
    const captured_square = enPassantCapturedSquare(to, us);
    std.debug.assert(moving == types.Piece.make(us, .pawn));
    std.debug.assert(captured == types.Piece.make(us.opposite(), .pawn));
    std.debug.assert(to == child.previous.?.ep_square);
    _ = removePiece(&value.physical, captured_square);
    xorPiece(child, captured, captured_square);
    movePiece(&value.physical, from, to);
    xorPieceMove(child, moving, from, to);
    child.delta.append(.{ .piece = moving, .from = from, .to = to });
    child.delta.append(.{ .piece = captured, .from = captured_square });
}

fn makeCastling(
    value: *position.Position,
    child: *position.PositionState,
    moving: types.Piece,
    from: types.Square,
    to: types.Square,
    us: types.Color,
) void {
    std.debug.assert(moving == types.Piece.make(us, .king));
    std.debug.assert(from == if (us == .white) types.Square.e1 else types.Square.e8);
    std.debug.assert(child.previous.?.castling_rights.contains(castlingRight(us, to)));
    const rook = castlingRookSquares(us, to);
    const rook_piece = types.Piece.make(us, .rook);
    std.debug.assert(value.physical.pieceOn(rook.from) == rook_piece);
    movePiece(&value.physical, from, to);
    xorPieceMove(child, moving, from, to);
    movePiece(&value.physical, rook.from, rook.to);
    xorPieceMove(child, rook_piece, rook.from, rook.to);
    child.delta.append(.{ .piece = moving, .from = from, .to = to });
    child.delta.append(.{ .piece = rook_piece, .from = rook.from, .to = rook.to });
}

fn putPiece(physical: *position.PhysicalPosition, piece: types.Piece, square: types.Square) void {
    std.debug.assert(piece != .none and physical.pieceOn(square) == .none);
    const bit = square.bit();
    physical.board[square.index()] = piece;
    physical.by_type[types.PieceType.none.index()] |= bit;
    physical.by_type[piece.pieceType().index()] |= bit;
    physical.by_color[piece.color().index()] |= bit;
    physical.piece_count[piece.index()] += 1;
    if (piece.pieceType() == .king) physical.king_square[piece.color().index()] = square;
}

fn removePiece(physical: *position.PhysicalPosition, square: types.Square) types.Piece {
    const piece = physical.pieceOn(square);
    std.debug.assert(piece != .none and physical.piece_count[piece.index()] != 0);
    const bit = square.bit();
    physical.board[square.index()] = .none;
    physical.by_type[types.PieceType.none.index()] &= ~bit;
    physical.by_type[piece.pieceType().index()] &= ~bit;
    physical.by_color[piece.color().index()] &= ~bit;
    physical.piece_count[piece.index()] -= 1;
    if (piece.pieceType() == .king) physical.king_square[piece.color().index()] = .none;
    return piece;
}

fn movePiece(
    physical: *position.PhysicalPosition,
    from: types.Square,
    to: types.Square,
) void {
    const piece = physical.pieceOn(from);
    std.debug.assert(piece != .none and physical.pieceOn(to) == .none);
    const mask = from.bit() | to.bit();
    physical.board[from.index()] = .none;
    physical.board[to.index()] = piece;
    physical.by_type[types.PieceType.none.index()] ^= mask;
    physical.by_type[piece.pieceType().index()] ^= mask;
    physical.by_color[piece.color().index()] ^= mask;
    if (piece.pieceType() == .king) physical.king_square[piece.color().index()] = to;
}

fn xorPiece(target: *position.PositionState, piece: types.Piece, square: types.Square) void {
    const key = zobrist.tables.piece_square[piece.index()][square.index()];
    target.key ^= key;
    switch (piece.pieceType()) {
        .pawn => target.pawn_key ^= key,
        .knight, .bishop => {
            target.minor_key ^= key;
            target.non_pawn_key[piece.color().index()] ^= key;
        },
        .rook, .queen, .king => target.non_pawn_key[piece.color().index()] ^= key,
        .none => unreachable,
    }
}

fn xorPieceMove(
    target: *position.PositionState,
    piece: types.Piece,
    from: types.Square,
    to: types.Square,
) void {
    const key = zobrist.tables.piece_square[piece.index()][from.index()] ^
        zobrist.tables.piece_square[piece.index()][to.index()];
    target.key ^= key;
    switch (piece.pieceType()) {
        .pawn => target.pawn_key ^= key,
        .knight, .bishop => {
            target.minor_key ^= key;
            target.non_pawn_key[piece.color().index()] ^= key;
        },
        .rook, .queen, .king => target.non_pawn_key[piece.color().index()] ^= key,
        .none => unreachable,
    }
}

fn rightsAfterMove(
    rights: types.CastlingRights,
    from: types.Square,
    to: types.Square,
) types.CastlingRights {
    return @enumFromInt(clearRightsAt(clearRightsAt(rights.raw(), from), to));
}

fn clearRightsAt(raw: u4, square: types.Square) u4 {
    const mask: u4 = switch (square) {
        .e1 => 0b1100,
        .a1 => 0b1101,
        .h1 => 0b1110,
        .e8 => 0b0011,
        .a8 => 0b0111,
        .h8 => 0b1011,
        else => 0b1111,
    };
    return raw & mask;
}

const RookMove = struct { from: types.Square, to: types.Square };

fn castlingRight(color: types.Color, king_to: types.Square) types.CastlingRights {
    return switch (color) {
        .white => switch (king_to) {
            .g1 => .white_king,
            .c1 => .white_queen,
            else => unreachable,
        },
        .black => switch (king_to) {
            .g8 => .black_king,
            .c8 => .black_queen,
            else => unreachable,
        },
    };
}

fn castlingRookSquares(color: types.Color, king_to: types.Square) RookMove {
    return switch (color) {
        .white => switch (king_to) {
            .g1 => .{ .from = .h1, .to = .f1 },
            .c1 => .{ .from = .a1, .to = .d1 },
            else => unreachable,
        },
        .black => switch (king_to) {
            .g8 => .{ .from = .h8, .to = .f8 },
            .c8 => .{ .from = .a8, .to = .d8 },
            else => unreachable,
        },
    };
}

fn enPassantCapturedSquare(target: types.Square, capturer: types.Color) types.Square {
    const offset: i8 = if (capturer == .white) -8 else 8;
    return types.Square.fromIndex(@intCast(@as(i8, @intCast(target.index())) + offset));
}

fn squareDistance(a: types.Square, b: types.Square) u7 {
    const first: u7 = a.index();
    const second: u7 = b.index();
    return if (first > second) first - second else second - first;
}

test "ordinary moves update incremental state and reverse exactly" {
    // Quiet/capture transitions are the common producer of every redundant
    // board fact. Full reconstruction and byte-level physical restoration
    // must agree before move generation or evaluation may consume them.
    var quiet_root: position.PositionState = .{};
    var quiet = try fen.parseStart(&quiet_root);
    const quiet_before = snapshot(&quiet, &quiet_root);
    var quiet_child: position.PositionState = .{};
    makeMove(&quiet, move.Move.normal(.e2, .e4), &quiet_child);
    try std.testing.expect(state.isConsistent(&quiet));
    try std.testing.expectEqual(types.Color.black, quiet.side_to_move);
    try std.testing.expectEqual(@as(u16, 0), quiet_child.rule50);
    try std.testing.expectEqual(types.Square.none, quiet_child.ep_square);
    try std.testing.expectEqual(@as(usize, 1), quiet_child.delta.slice().len);
    try std.testing.expectEqual(types.Square.e4, quiet_child.delta.slice()[0].to);
    unmakeMove(&quiet, move.Move.normal(.e2, .e4));
    try expectRestored(&quiet, &quiet_root, quiet_before);

    var capture_root: position.PositionState = .{};
    var capture = try fen.parse("4k3/8/8/3p4/4P3/8/8/4K3 w - - 7 1", &capture_root);
    const capture_before = snapshot(&capture, &capture_root);
    var capture_child: position.PositionState = .{};
    const capture_move = move.Move.normal(.e4, .d5);
    makeMove(&capture, capture_move, &capture_child);
    try std.testing.expect(state.isConsistent(&capture));
    try std.testing.expectEqual(types.Piece.black_pawn, capture_child.captured_piece);
    try std.testing.expectEqual(@as(usize, 2), capture_child.delta.slice().len);
    try std.testing.expectEqual(@as(u16, 0), capture_child.rule50);
    unmakeMove(&capture, capture_move);
    try expectRestored(&capture, &capture_root, capture_before);
}

test "special moves preserve exact chess facts and complete deltas" {
    // Promotion capture is the maximum three-change delta. Castling and EP
    // alter squares not described by an ordinary from/to pair.
    var promotion_root: position.PositionState = .{};
    var promotion = try fen.parse("1r5k/P7/8/8/8/8/8/7K w - - 0 1", &promotion_root);
    const promotion_before = snapshot(&promotion, &promotion_root);
    var promotion_child: position.PositionState = .{};
    const promotion_move = move.Move.promotion(.a7, .b8, .queen);
    makeMove(&promotion, promotion_move, &promotion_child);
    try std.testing.expect(state.isConsistent(&promotion));
    try std.testing.expectEqual(types.Piece.white_queen, promotion.physical.pieceOn(.b8));
    try std.testing.expectEqual(types.Piece.black_rook, promotion_child.captured_piece);
    try std.testing.expectEqual(@as(usize, 3), promotion_child.delta.slice().len);
    try std.testing.expectEqual(types.Square.b8.bit(), promotion_child.checkers);
    unmakeMove(&promotion, promotion_move);
    try expectRestored(&promotion, &promotion_root, promotion_before);

    var ep_root: position.PositionState = .{};
    var ep = try fen.parse("4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1", &ep_root);
    const ep_before = snapshot(&ep, &ep_root);
    var ep_child: position.PositionState = .{};
    const ep_move = move.Move.enPassant(.d4, .e3);
    makeMove(&ep, ep_move, &ep_child);
    try std.testing.expect(state.isConsistent(&ep));
    try std.testing.expectEqual(types.Piece.black_pawn, ep.physical.pieceOn(.e3));
    try std.testing.expectEqual(types.Piece.none, ep.physical.pieceOn(.e4));
    try std.testing.expectEqual(types.Piece.white_pawn, ep_child.captured_piece);
    try std.testing.expectEqual(@as(usize, 2), ep_child.delta.slice().len);
    unmakeMove(&ep, ep_move);
    try expectRestored(&ep, &ep_root, ep_before);

    var castle_root: position.PositionState = .{};
    var castle = try fen.parse("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", &castle_root);
    const castle_before = snapshot(&castle, &castle_root);
    var castle_child: position.PositionState = .{};
    const castle_move = move.Move.castling(.e1, .g1);
    makeMove(&castle, castle_move, &castle_child);
    try std.testing.expect(state.isConsistent(&castle));
    try std.testing.expectEqual(types.Piece.white_king, castle.physical.pieceOn(.g1));
    try std.testing.expectEqual(types.Piece.white_rook, castle.physical.pieceOn(.f1));
    try std.testing.expectEqual(@as(u4, 0b1100), castle_child.castling_rights.raw());
    try std.testing.expectEqual(@as(usize, 2), castle_child.delta.slice().len);
    unmakeMove(&castle, castle_move);
    try expectRestored(&castle, &castle_root, castle_before);
}

test "double pushes and home-square changes maintain identity rights" {
    // Repetition identity includes EP only when the opponent has a legal
    // capture, while moving/capturing a home rook permanently clears rights.
    var ep_root: position.PositionState = .{};
    var ep = try fen.parse("4k3/8/8/8/3p4/8/4P3/4K3 w - - 0 1", &ep_root);
    var ep_child: position.PositionState = .{};
    makeMove(&ep, move.Move.normal(.e2, .e4), &ep_child);
    try std.testing.expectEqual(types.Square.e3, ep_child.ep_square);
    try std.testing.expect(state.isConsistent(&ep));
    unmakeMove(&ep, move.Move.normal(.e2, .e4));

    var rook_root: position.PositionState = .{};
    var rook = try fen.parse("4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1", &rook_root);
    var rook_child: position.PositionState = .{};
    makeMove(&rook, move.Move.normal(.h1, .h2), &rook_child);
    try std.testing.expectEqual(types.CastlingRights.white_queen, rook_child.castling_rights);
    try std.testing.expect(state.isConsistent(&rook));
    unmakeMove(&rook, move.Move.normal(.h1, .h2));

    var captured_root: position.PositionState = .{};
    var captured = try fen.parse("4k3/8/8/8/8/8/1b6/R3K3 b Q - 0 1", &captured_root);
    var captured_child: position.PositionState = .{};
    makeMove(&captured, move.Move.normal(.b2, .a1), &captured_child);
    try std.testing.expectEqual(types.CastlingRights.none, captured_child.castling_rights);
    try std.testing.expectEqual(types.Piece.white_rook, captured_child.captured_piece);
    try std.testing.expect(state.isConsistent(&captured));
    unmakeMove(&captured, move.Move.normal(.b2, .a1));
}

test "color-symmetric special transitions preserve their chess geometry" {
    // Rank direction and castling rook geometry have color-specific branches;
    // exercising the opposite color prevents a one-sided implementation from
    // passing only the representative special-move cases above.
    var promotion_root: position.PositionState = .{};
    var promotion = try fen.parse("7k/8/8/8/8/8/p7/7K b - - 0 1", &promotion_root);
    const promotion_before = snapshot(&promotion, &promotion_root);
    var promotion_child: position.PositionState = .{};
    const promotion_move = move.Move.promotion(.a2, .a1, .knight);
    makeMove(&promotion, promotion_move, &promotion_child);
    try std.testing.expectEqual(types.Piece.black_knight, promotion.physical.pieceOn(.a1));
    try std.testing.expect(state.isConsistent(&promotion));
    unmakeMove(&promotion, promotion_move);
    try expectRestored(&promotion, &promotion_root, promotion_before);

    var ep_root: position.PositionState = .{};
    var ep = try fen.parse("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", &ep_root);
    const ep_before = snapshot(&ep, &ep_root);
    var ep_child: position.PositionState = .{};
    const ep_move = move.Move.enPassant(.e5, .d6);
    makeMove(&ep, ep_move, &ep_child);
    try std.testing.expectEqual(types.Piece.white_pawn, ep.physical.pieceOn(.d6));
    try std.testing.expectEqual(types.Piece.none, ep.physical.pieceOn(.d5));
    try std.testing.expect(state.isConsistent(&ep));
    unmakeMove(&ep, ep_move);
    try expectRestored(&ep, &ep_root, ep_before);

    var castle_root: position.PositionState = .{};
    var castle = try fen.parse("r3k2r/8/8/8/8/8/8/4K3 b kq - 0 1", &castle_root);
    const castle_before = snapshot(&castle, &castle_root);
    var castle_child: position.PositionState = .{};
    const castle_move = move.Move.castling(.e8, .c8);
    makeMove(&castle, castle_move, &castle_child);
    try std.testing.expectEqual(types.Piece.black_king, castle.physical.pieceOn(.c8));
    try std.testing.expectEqual(types.Piece.black_rook, castle.physical.pieceOn(.d8));
    try std.testing.expect(state.isConsistent(&castle));
    unmakeMove(&castle, castle_move);
    try expectRestored(&castle, &castle_root, castle_before);

    var push_root: position.PositionState = .{};
    var push = try fen.parse("4k3/4p3/8/3P4/8/8/8/4K3 b - - 0 1", &push_root);
    const push_before = snapshot(&push, &push_root);
    var push_child: position.PositionState = .{};
    const push_move = move.Move.normal(.e7, .e5);
    makeMove(&push, push_move, &push_child);
    try std.testing.expectEqual(types.Square.e6, push_child.ep_square);
    try std.testing.expect(state.isConsistent(&push));
    unmakeMove(&push, push_move);
    try expectRestored(&push, &push_root, push_before);
}

test "null move is a reversible search fiction" {
    // Null removes legal EP identity and fences repetition without advancing
    // played-move or rule-50 facts. Physical placement remains untouched.
    var root: position.PositionState = .{};
    var value = try fen.parse("4k3/8/8/8/3pP3/8/8/4K3 b - e3 17 9", &root);
    const before = snapshot(&value, &root);
    var child: position.PositionState = .{};
    makeNull(&value, &child);
    try std.testing.expect(state.isConsistent(&value));
    try std.testing.expectEqual(types.Square.none, child.ep_square);
    try std.testing.expectEqual(@as(u16, 17), child.rule50);
    try std.testing.expectEqual(@as(u16, 0), child.plies_from_null);
    try std.testing.expectEqual(before.game_ply, value.game_ply);
    try std.testing.expectEqualDeep(before.physical, value.physical);
    unmakeNull(&value);
    try expectRestored(&value, &root, before);
}

test "reversible counters saturate without corrupting round trips" {
    // Hostile but accepted clock values must not overflow in safe or production
    // builds; unmake restores the exact parent state through pointer ownership.
    var root: position.PositionState = .{};
    var value = try fen.parseStart(&root);
    root.rule50 = std.math.maxInt(u16);
    root.plies_from_null = std.math.maxInt(u16);
    const before = snapshot(&value, &root);
    var child: position.PositionState = .{};
    const knight_move = move.Move.normal(.g1, .f3);
    makeMove(&value, knight_move, &child);
    try std.testing.expectEqual(std.math.maxInt(u16), child.rule50);
    try std.testing.expectEqual(std.math.maxInt(u16), child.plies_from_null);
    try std.testing.expect(state.isConsistent(&value));
    unmakeMove(&value, knight_move);
    try expectRestored(&value, &root, before);
}

test "nested caller-owned states unwind in strict reverse order" {
    // Search owns stable state slots by ply. A short legal line proves that
    // each child links to its exact parent and that unwinding does not depend
    // on rebuilding or copying an earlier position.
    var root: position.PositionState = .{};
    var value = try fen.parseStart(&root);
    const before = snapshot(&value, &root);
    var children: [3]position.PositionState = @splat(.{});
    const line = [_]move.Move{
        move.Move.normal(.e2, .e4),
        move.Move.normal(.e7, .e5),
        move.Move.normal(.g1, .f3),
    };

    for (line, &children) |chess_move, *child| {
        makeMove(&value, chess_move, child);
        try std.testing.expect(state.isConsistent(&value));
    }
    try std.testing.expect(value.current == &children[2]);
    try std.testing.expect(children[2].previous == &children[1]);
    try std.testing.expect(children[1].previous == &children[0]);
    try std.testing.expect(children[0].previous == &root);

    var index = line.len;
    while (index != 0) {
        index -= 1;
        unmakeMove(&value, line[index]);
        try std.testing.expect(state.isConsistent(&value));
    }
    try expectRestored(&value, &root, before);
}

const Snapshot = struct {
    physical: position.PhysicalPosition,
    state: position.PositionState,
    current: *position.PositionState,
    side: types.Color,
    game_ply: u64,
};

fn snapshot(value: *const position.Position, root: *const position.PositionState) Snapshot {
    return .{
        .physical = value.physical,
        .state = root.*,
        .current = value.current,
        .side = value.side_to_move,
        .game_ply = value.game_ply,
    };
}

fn expectRestored(
    value: *const position.Position,
    root: *const position.PositionState,
    expected: Snapshot,
) !void {
    try std.testing.expectEqualDeep(expected.physical, value.physical);
    try std.testing.expectEqualDeep(expected.state, root.*);
    try std.testing.expect(value.current == expected.current);
    try std.testing.expectEqual(expected.side, value.side_to_move);
    try std.testing.expectEqual(expected.game_ply, value.game_ply);
    try std.testing.expect(state.isConsistent(value));
}
