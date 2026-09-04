//! Allocation-free direct legal move generation and independent legality.
const std = @import("std");
const attacks = @import("attacks.zig");
const fen = @import("fen.zig");
const move = @import("move.zig");
const position = @import("position.zig");
const queries = @import("queries.zig");
const state = @import("state.zig");
const transition = @import("transition.zig");
const types = @import("types.zig");

pub const Mode = enum {
    all,
    captures,
    quiets,
};

/// Generates a complete legal subset into a caller-owned fixed-capacity list.
/// Captures and quiets are exact, disjoint chess categories whose union is all.
pub fn generate(
    comptime mode: Mode,
    value: *const position.Position,
    list: *position.MoveList,
) void {
    list.count = 0;
    switch (value.side_to_move) {
        .white => generateFor(.white, mode, value, list),
        .black => generateFor(.black, mode, value, list),
    }
}

/// Validates the complete geometry and special-move shape of an arbitrary
/// encoded move without assuming it came from a generator or trusted TT.
pub fn isPseudoLegal(value: *const position.Position, chess_move: move.Move) bool {
    if (!chess_move.isChessMove()) return false;
    const us = value.side_to_move;
    const from = chess_move.from();
    const to = chess_move.to();
    const moving = value.physical.pieceOn(from);
    if (moving == .none or moving.color() != us) return false;
    const captured = value.physical.pieceOn(to);
    if (captured != .none and
        (captured.color() == us or captured.pieceType() == .king)) return false;

    return switch (moving.pieceType()) {
        .pawn => pseudoLegalPawn(value, chess_move, moving, captured),
        .king => switch (chess_move.kind()) {
            .normal => attacks.king[from.index()] & to.bit() != 0,
            .castling => pseudoLegalCastling(value, us, from, to),
            .promotion, .en_passant => false,
        },
        .knight, .bishop, .rook, .queen => chess_move.kind() == .normal and
            attacks.forPiece(
                moving.pieceType(),
                us,
                from,
                value.physical.occupied(),
            ) & to.bit() != 0,
        .none => false,
    };
}

/// Fully validates an arbitrary encoded move through a path independent of
/// direct legal generation. Hot makeMove callers may skip this only when the
/// move was produced by `generate` for the unchanged position.
pub fn isLegal(value: *const position.Position, chess_move: move.Move) bool {
    if (!isPseudoLegal(value, chess_move)) return false;
    const us = value.side_to_move;
    const them = us.opposite();
    const from = chess_move.from();
    const to = chess_move.to();

    if (chess_move.kind() == .castling) {
        return legalCastling(value, us, from, to);
    }
    if (chess_move.kind() == .en_passant) {
        return queries.isLegalEnPassantFrom(value, from, to, us);
    }

    const moving = value.physical.pieceOn(from);
    const captured = value.physical.pieceOn(to);
    var occupied = value.physical.occupied() & ~from.bit();
    const king_move = moving.pieceType() == .king;
    if (!king_move) occupied |= to.bit();
    const king = if (king_move) to else queries.kingSquare(value, us);
    const excluded = if (!king_move and captured != .none) to.bit() else 0;
    return !queries.isAttackedByExcluding(
        value,
        king,
        occupied,
        them,
        excluded,
    );
}

pub fn isCapture(value: *const position.Position, chess_move: move.Move) bool {
    std.debug.assert(chess_move.isChessMove());
    return chess_move.kind() == .en_passant or
        (chess_move.kind() != .castling and
            value.physical.pieceOn(chess_move.to()) != .none);
}

fn generateFor(
    comptime us: types.Color,
    comptime mode: Mode,
    value: *const position.Position,
    list: *position.MoveList,
) void {
    const them = us.opposite();
    const physical = &value.physical;
    const occupied = physical.occupied();
    const friendly = physical.by_color[us.index()];
    // In a legal position the side not to move cannot already be in check, so
    // no pseudo-legal destination reaches its king. FEN validation and every
    // transition establish that invariant before direct generation.
    const enemy = physical.by_color[them.index()];
    const king = queries.kingSquare(value, us);
    const target = switch (mode) {
        .all => ~friendly,
        .captures => enemy,
        .quiets => ~occupied,
    };

    if (mode == .captures) {
        @call(.always_inline, generateKing, .{ us, value, king, target, list });
    } else {
        generateKing(us, value, king, target, list);
    }

    const checkers = value.current.checkers;
    if (@popCount(checkers) > 1) return;
    const check_mask = if (checkers == 0)
        ~@as(types.Bitboard, 0)
    else blk: {
        const checker = squareFromBit(checkers);
        break :blk checkers | attacks.between[king.index()][checker.index()];
    };
    const pinned = pinnedPieces(value, us, king, occupied);

    if (mode == .captures) {
        @call(.always_inline, generatePawns, .{
            us,
            mode,
            value,
            king,
            pinned,
            check_mask,
            enemy,
            list,
        });
    } else {
        generatePawns(us, mode, value, king, pinned, check_mask, enemy, list);
    }
    generatePieces(us, .knight, value, king, pinned, check_mask, target, list);
    generatePieces(us, .bishop, value, king, pinned, check_mask, target, list);
    generatePieces(us, .rook, value, king, pinned, check_mask, target, list);
    generatePieces(us, .queen, value, king, pinned, check_mask, target, list);

    if (mode != .captures and checkers == 0) generateCastling(us, value, list);
}

fn generateKing(
    comptime us: types.Color,
    value: *const position.Position,
    king: types.Square,
    target: types.Bitboard,
    list: *position.MoveList,
) void {
    const them = us.opposite();
    var destinations = attacks.king[king.index()] & target;
    const occupied_without_king = value.physical.occupied() & ~king.bit();
    while (destinations != 0) {
        const to = popSquare(&destinations);
        if (!queries.isAttackedByExcluding(
            value,
            to,
            occupied_without_king,
            them,
            0,
        )) {
            list.append(move.Move.normal(king, to));
        }
    }
}

inline fn generatePieces(
    comptime us: types.Color,
    comptime piece_type: types.PieceType,
    value: *const position.Position,
    king: types.Square,
    pinned: types.Bitboard,
    check_mask: types.Bitboard,
    target: types.Bitboard,
    list: *position.MoveList,
) void {
    var pieces = value.physical.pieces(us, piece_type);
    if (piece_type == .knight) pieces &= ~pinned;
    const occupied = value.physical.occupied();
    while (pieces != 0) {
        const from = popSquare(&pieces);
        var destinations = switch (piece_type) {
            .knight => attacks.knight[from.index()],
            .bishop => attacks.bishop(from, occupied),
            .rook => attacks.rook(from, occupied),
            .queen => attacks.queen(from, occupied),
            else => unreachable,
        } &
            target & check_mask;
        if (piece_type != .knight and pinned & from.bit() != 0) {
            destinations &= attacks.line[king.index()][from.index()];
        }
        while (destinations != 0) {
            list.append(move.Move.normal(from, popSquare(&destinations)));
        }
    }
}

fn generatePawns(
    comptime us: types.Color,
    comptime mode: Mode,
    value: *const position.Position,
    king: types.Square,
    pinned: types.Bitboard,
    check_mask: types.Bitboard,
    enemy: types.Bitboard,
    list: *position.MoveList,
) void {
    const push: i8 = if (us == .white) 8 else -8;
    const occupied = value.physical.occupied();
    const pawns = value.physical.pieces(us, .pawn);
    const promotion_rank: types.Bitboard = if (us == .white)
        0x00ff_0000_0000_0000
    else
        0x0000_0000_0000_ff00;
    const start_rank: types.Bitboard = if (us == .white)
        0x0000_0000_0000_ff00
    else
        0x00ff_0000_0000_0000;
    const file_a: types.Bitboard = 0x0101_0101_0101_0101;
    const file_h: types.Bitboard = 0x8080_8080_8080_8080;
    const free = pawns & ~pinned;
    const free_promotions = free & promotion_rank;
    const free_non_promotions = free & ~promotion_rank;

    if (mode != .captures) {
        var promotion_pushes = shiftPawns(us, free_promotions) & ~occupied & check_mask;
        appendPawnSet(list, &promotion_pushes, -push, true);

        var single_pushes = shiftPawns(us, free_non_promotions) & ~occupied & check_mask;
        appendPawnSet(list, &single_pushes, -push, false);

        const start_steps = shiftPawns(us, free & start_rank) & ~occupied;
        var double_pushes = shiftPawns(us, start_steps) & ~occupied & check_mask;
        appendPawnSet(list, &double_pushes, -(push * 2), false);
    }

    if (mode != .quiets) {
        const promotion_left_sources = free_promotions & ~file_a;
        const promotion_right_sources = free_promotions & ~file_h;
        var promotion_left = (if (us == .white)
            promotion_left_sources << 7
        else
            promotion_left_sources >> 9) & enemy & check_mask;
        var promotion_right = (if (us == .white)
            promotion_right_sources << 9
        else
            promotion_right_sources >> 7) & enemy & check_mask;
        appendPawnSet(list, &promotion_left, if (us == .white) -7 else 9, true);
        appendPawnSet(list, &promotion_right, if (us == .white) -9 else 7, true);

        const left_sources = free_non_promotions & ~file_a;
        const right_sources = free_non_promotions & ~file_h;
        var left_captures = (if (us == .white) left_sources << 7 else left_sources >> 9) &
            enemy & check_mask;
        var right_captures = (if (us == .white) right_sources << 9 else right_sources >> 7) &
            enemy & check_mask;
        appendPawnSet(list, &left_captures, if (us == .white) -7 else 9, false);
        appendPawnSet(list, &right_captures, if (us == .white) -9 else 7, false);
    }

    var pinned_pawns = pawns & pinned;
    while (pinned_pawns != 0) {
        const from = popSquare(&pinned_pawns);
        const pin_ray = attacks.line[king.index()][from.index()];
        const promotion_from = types.relativeRank(us, from.rank()) == .seven;

        if (mode != .captures) {
            if (offsetSquare(from, push)) |one| {
                if (occupied & one.bit() == 0) {
                    if (one.bit() & pin_ray & check_mask != 0) {
                        if (promotion_from) {
                            appendPromotions(list, from, one);
                        } else {
                            list.append(move.Move.normal(from, one));
                        }
                    }
                    if (!promotion_from and types.relativeRank(us, from.rank()) == .two) {
                        if (offsetSquare(one, push)) |two| {
                            if (occupied & two.bit() == 0 and
                                two.bit() & pin_ray & check_mask != 0)
                            {
                                list.append(move.Move.normal(from, two));
                            }
                        }
                    }
                }
            }
        }

        if (mode != .quiets) {
            var captures = attacks.pawn[us.index()][from.index()] & enemy &
                pin_ray & check_mask;
            while (captures != 0) {
                const to = popSquare(&captures);
                if (promotion_from) {
                    appendPromotions(list, from, to);
                } else {
                    list.append(move.Move.normal(from, to));
                }
            }
        }
    }

    const ep = value.current.ep_square;
    if (mode != .quiets and ep != .none) {
        var candidates = attacks.pawn[us.opposite().index()][ep.index()] & pawns;
        while (candidates != 0) {
            const from = popSquare(&candidates);
            if (queries.isLegalEnPassantFrom(value, from, ep, us)) {
                list.append(move.Move.enPassant(from, ep));
            }
        }
    }
}

fn shiftPawns(comptime color: types.Color, pawns: types.Bitboard) types.Bitboard {
    return if (color == .white) pawns << 8 else pawns >> 8;
}

fn appendPawnSet(
    list: *position.MoveList,
    destinations: *types.Bitboard,
    comptime from_offset: i8,
    comptime promotions: bool,
) void {
    while (destinations.* != 0) {
        const to = popSquare(destinations);
        const from = types.Square.fromIndex(@intCast(
            @as(i8, @intCast(to.index())) + from_offset,
        ));
        if (promotions) {
            appendPromotions(list, from, to);
        } else {
            list.append(move.Move.normal(from, to));
        }
    }
}

fn generateCastling(
    comptime us: types.Color,
    value: *const position.Position,
    list: *position.MoveList,
) void {
    const from: types.Square = if (us == .white) .e1 else .e8;
    const king_to: types.Square = if (us == .white) .g1 else .g8;
    const queen_to: types.Square = if (us == .white) .c1 else .c8;
    if (legalCastling(value, us, from, king_to)) {
        list.append(move.Move.castling(from, king_to));
    }
    if (legalCastling(value, us, from, queen_to)) {
        list.append(move.Move.castling(from, queen_to));
    }
}

fn appendPromotions(
    list: *position.MoveList,
    from: types.Square,
    to: types.Square,
) void {
    inline for ([_]types.PieceType{ .queen, .rook, .bishop, .knight }) |piece_type| {
        list.append(move.Move.promotion(from, to, piece_type));
    }
}

fn pinnedPieces(
    value: *const position.Position,
    comptime us: types.Color,
    king: types.Square,
    occupied: types.Bitboard,
) types.Bitboard {
    const them = us.opposite();
    var pinners = (attacks.bishop_rays[king.index()] &
        (value.physical.pieces(them, .bishop) | value.physical.pieces(them, .queen))) |
        (attacks.rook_rays[king.index()] &
            (value.physical.pieces(them, .rook) | value.physical.pieces(them, .queen)));
    var pinned: types.Bitboard = 0;
    while (pinners != 0) {
        const pinner = popSquare(&pinners);
        const blockers = attacks.between[king.index()][pinner.index()] & occupied;
        if (@popCount(blockers) == 1 and
            blockers & value.physical.by_color[us.index()] != 0)
        {
            pinned |= blockers;
        }
    }
    return pinned;
}

fn pseudoLegalPawn(
    value: *const position.Position,
    chess_move: move.Move,
    moving: types.Piece,
    captured: types.Piece,
) bool {
    const us = moving.color();
    const them = us.opposite();
    const from = chess_move.from();
    const to = chess_move.to();
    const push: i8 = if (us == .white) 8 else -8;
    const delta = @as(i8, @intCast(to.index())) - @as(i8, @intCast(from.index()));
    const pawn_capture = attacks.pawn[us.index()][from.index()] & to.bit() != 0;

    return switch (chess_move.kind()) {
        .promotion => types.relativeRank(us, from.rank()) == .seven and
            types.relativeRank(us, to.rank()) == .eight and
            ((delta == push and captured == .none) or
                (pawn_capture and captured != .none and captured.color() == them)),
        .en_passant => value.current.ep_square == to and captured == .none and
            pawn_capture and enPassantPawnPresent(value, to, us),
        .normal => blk: {
            if (types.relativeRank(us, to.rank()) == .eight) break :blk false;
            if (pawn_capture) break :blk captured != .none and captured.color() == them;
            if (captured != .none) break :blk false;
            if (delta == push) break :blk true;
            if (delta != push * 2 or types.relativeRank(us, from.rank()) != .two) {
                break :blk false;
            }
            const middle = offsetSquare(from, push) orelse break :blk false;
            break :blk value.physical.pieceOn(middle) == .none;
        },
        .castling => false,
    };
}

fn pseudoLegalCastling(
    value: *const position.Position,
    us: types.Color,
    from: types.Square,
    to: types.Square,
) bool {
    const expected_from: types.Square = if (us == .white) .e1 else .e8;
    if (from != expected_from) return false;
    const king_side_to: types.Square = if (us == .white) .g1 else .g8;
    const queen_side_to: types.Square = if (us == .white) .c1 else .c8;
    if (to != king_side_to and to != queen_side_to) return false;
    const king_side = to == king_side_to;
    const right: types.CastlingRights = switch (us) {
        .white => if (king_side) .white_king else .white_queen,
        .black => if (king_side) .black_king else .black_queen,
    };
    if (!value.current.castling_rights.contains(right)) return false;
    const rook: types.Square = switch (us) {
        .white => if (king_side) .h1 else .a1,
        .black => if (king_side) .h8 else .a8,
    };
    if (value.physical.pieceOn(rook) != types.Piece.make(us, .rook)) return false;
    const empty_mask = switch (to) {
        .g1 => types.Square.f1.bit() | types.Square.g1.bit(),
        .c1 => types.Square.b1.bit() | types.Square.c1.bit() | types.Square.d1.bit(),
        .g8 => types.Square.f8.bit() | types.Square.g8.bit(),
        .c8 => types.Square.b8.bit() | types.Square.c8.bit() | types.Square.d8.bit(),
        else => unreachable,
    };
    return value.physical.occupied() & empty_mask == 0;
}

fn legalCastling(
    value: *const position.Position,
    us: types.Color,
    from: types.Square,
    to: types.Square,
) bool {
    if (!pseudoLegalCastling(value, us, from, to) or value.current.checkers != 0) {
        return false;
    }
    const transit: types.Square = switch (to) {
        .g1 => .f1,
        .c1 => .d1,
        .g8 => .f8,
        .c8 => .d8,
        else => unreachable,
    };
    const them = us.opposite();
    const occupied = value.physical.occupied() & ~from.bit();
    return !queries.isAttackedByExcluding(value, transit, occupied, them, 0) and
        !queries.isAttackedByExcluding(value, to, occupied, them, 0);
}

fn enPassantPawnPresent(
    value: *const position.Position,
    target: types.Square,
    capturer: types.Color,
) bool {
    const offset: i8 = if (capturer == .white) -8 else 8;
    const captured = offsetSquare(target, offset) orelse return false;
    return value.physical.pieceOn(captured) == types.Piece.make(capturer.opposite(), .pawn);
}

fn offsetSquare(square: types.Square, offset: i8) ?types.Square {
    const index = @as(i8, @intCast(square.index())) + offset;
    if (index < 0 or index >= 64) return null;
    return types.Square.fromIndex(@intCast(index));
}

fn popSquare(bitboard: *types.Bitboard) types.Square {
    std.debug.assert(bitboard.* != 0);
    const square = types.Square.fromIndex(@intCast(@ctz(bitboard.*)));
    bitboard.* &= bitboard.* - 1;
    return square;
}

fn squareFromBit(bitboard: types.Bitboard) types.Square {
    std.debug.assert(@popCount(bitboard) == 1);
    return types.Square.fromIndex(@intCast(@ctz(bitboard)));
}

fn contains(list: *const position.MoveList, candidate: move.Move) bool {
    for (list.slice()) |item| if (item.raw() == candidate.raw()) return true;
    return false;
}

test "legal generation partitions coherent legal positions exactly" {
    // Every fixture passes strict FEN legality before use. Every generated
    // child independently preserves redundant state and the mover's king.
    const fixtures = [_][]const u8{
        fen.start_position,
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1",
        "4k3/8/8/8/8/8/4r3/4K3 w - - 0 1",
        "4k3/8/8/8/1b6/8/4r3/4K3 w - - 0 1",
        "4r1k1/8/8/8/8/8/4R3/4K3 w - - 0 1",
        "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
        "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
        "7k/P7/8/8/8/8/8/7K w - - 0 1",
        "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1",
        "4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1",
        "7k/8/8/8/8/8/p7/7K b - - 0 1",
    };

    for (fixtures) |fixture| {
        var root: position.PositionState = .{};
        var value = try fen.parse(fixture, &root);
        try std.testing.expect(state.isConsistent(&value));
        var all = position.MoveList.init();
        var captures = position.MoveList.init();
        var quiets = position.MoveList.init();
        generate(.all, &value, &all);
        generate(.captures, &value, &captures);
        generate(.quiets, &value, &quiets);
        try expectUnique(&all);
        try expectUnique(&captures);
        try expectUnique(&quiets);
        try std.testing.expectEqual(all.slice().len, captures.slice().len + quiets.slice().len);

        for (all.slice()) |chess_move| {
            try std.testing.expect(isLegal(&value, chess_move));
            try std.testing.expect(contains(
                if (isCapture(&value, chess_move)) &captures else &quiets,
                chess_move,
            ));
            const us = value.side_to_move;
            var child: position.PositionState = .{};
            transition.makeMove(&value, chess_move, &child);
            try std.testing.expect(state.isConsistent(&value));
            try std.testing.expectEqual(
                @as(types.Bitboard, 0),
                queries.attackersToBy(
                    &value,
                    queries.kingSquare(&value, us),
                    value.physical.occupied(),
                    value.side_to_move,
                ),
            );
            transition.unmakeMove(&value, chess_move);
            try std.testing.expect(state.isConsistent(&value));
        }
        for (captures.slice()) |chess_move| {
            try std.testing.expect(isCapture(&value, chess_move));
            try std.testing.expect(contains(&all, chess_move));
        }
        for (quiets.slice()) |chess_move| {
            try std.testing.expect(!isCapture(&value, chess_move));
            try std.testing.expect(contains(&all, chess_move));
        }
    }
}

test "checks pins castling en passant and promotions obey exact rules" {
    // These are rule-shaped assertions, not incidental move-order snapshots.
    var start_root: position.PositionState = .{};
    const start = try fen.parseStart(&start_root);
    var start_moves = position.MoveList.init();
    generate(.all, &start, &start_moves);
    try std.testing.expectEqual(@as(usize, 20), start_moves.slice().len);

    var black_start_root: position.PositionState = .{};
    const black_start = try fen.parse(
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1",
        &black_start_root,
    );
    var black_start_moves = position.MoveList.init();
    generate(.all, &black_start, &black_start_moves);
    try std.testing.expectEqual(@as(usize, 20), black_start_moves.slice().len);

    var double_root: position.PositionState = .{};
    const double = try fen.parse("4k3/8/8/8/1b6/8/4r3/4K3 w - - 0 1", &double_root);
    var double_moves = position.MoveList.init();
    generate(.all, &double, &double_moves);
    for (double_moves.slice()) |chess_move| {
        try std.testing.expectEqual(types.Square.e1, chess_move.from());
    }

    var double_block_root: position.PositionState = .{};
    const double_block = try fen.parse(
        "k7/7b/8/8/8/8/5P2/2K5 w - - 0 1",
        &double_block_root,
    );
    var double_block_moves = position.MoveList.init();
    generate(.all, &double_block, &double_block_moves);
    try std.testing.expect(contains(&double_block_moves, move.Move.normal(.f2, .f4)));

    var pin_root: position.PositionState = .{};
    const pin = try fen.parse("4r1k1/8/8/8/8/8/4R3/4K3 w - - 0 1", &pin_root);
    var pin_moves = position.MoveList.init();
    generate(.all, &pin, &pin_moves);
    try std.testing.expect(!contains(&pin_moves, move.Move.normal(.e2, .d2)));
    try std.testing.expect(contains(&pin_moves, move.Move.normal(.e2, .e8)));

    var castle_root: position.PositionState = .{};
    const castle = try fen.parse("r3kr1r/8/8/8/8/8/8/R3K2R w KQ - 0 1", &castle_root);
    var castle_moves = position.MoveList.init();
    generate(.all, &castle, &castle_moves);
    try std.testing.expect(!contains(&castle_moves, move.Move.castling(.e1, .g1)));
    try std.testing.expect(contains(&castle_moves, move.Move.castling(.e1, .c1)));

    var pinned_ep_root: position.PositionState = .{};
    const pinned_ep = try fen.parse("4k3/8/8/r4pPK/8/8/8/8 w - f6 0 1", &pinned_ep_root);
    try std.testing.expectEqual(types.Square.none, pinned_ep.current.ep_square);
    var pinned_ep_moves = position.MoveList.init();
    generate(.all, &pinned_ep, &pinned_ep_moves);
    try std.testing.expect(!contains(&pinned_ep_moves, move.Move.enPassant(.g5, .f6)));

    var promotion_root: position.PositionState = .{};
    const promotion = try fen.parse("7k/P7/8/8/8/8/8/7K w - - 0 1", &promotion_root);
    var promotion_moves = position.MoveList.init();
    generate(.all, &promotion, &promotion_moves);
    inline for ([_]types.PieceType{ .knight, .bishop, .rook, .queen }) |piece_type| {
        try std.testing.expect(contains(
            &promotion_moves,
            move.Move.promotion(.a7, .a8, piece_type),
        ));
    }

    var mate_root: position.PositionState = .{};
    const mate = try fen.parse("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1", &mate_root);
    var mate_moves = position.MoveList.init();
    generate(.all, &mate, &mate_moves);
    try std.testing.expectEqual(@as(usize, 0), mate_moves.slice().len);
    try std.testing.expect(mate.current.checkers != 0);

    var stalemate_root: position.PositionState = .{};
    const stalemate = try fen.parse("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", &stalemate_root);
    var stalemate_moves = position.MoveList.init();
    generate(.all, &stalemate, &stalemate_moves);
    try std.testing.expectEqual(@as(usize, 0), stalemate_moves.slice().len);
    try std.testing.expectEqual(@as(types.Bitboard, 0), stalemate.current.checkers);
}

test "direct generation agrees with independent legality for every encoding" {
    // Exhausting the full 16-bit representation catches malformed kinds,
    // promotion bits and special moves that curated legal lists may never emit.
    const fixtures = [_][]const u8{
        fen.start_position,
        "4k3/8/8/8/1b6/8/4r3/4K3 w - - 0 1",
        "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
        "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
        "7k/P7/8/8/8/8/8/7K w - - 0 1",
        "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1",
        "4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1",
        "7k/8/8/8/8/8/p7/7K b - - 0 1",
    };
    for (fixtures) |fixture| {
        var root: position.PositionState = .{};
        const value = try fen.parse(fixture, &root);
        try std.testing.expect(state.isConsistent(&value));
        var legal = position.MoveList.init();
        generate(.all, &value, &legal);
        for (0..std.math.maxInt(u16) + 1) |raw| {
            const candidate = move.Move{ .raw_value = @intCast(raw) };
            const generated = contains(&legal, candidate);
            const queried = isLegal(&value, candidate);
            if (generated != queried) {
                std.debug.print("legality mismatch fixture={s} raw={d} generated={} queried={}\n", .{
                    fixture,
                    raw,
                    generated,
                    queried,
                });
                return error.TestExpectedEqual;
            }
        }
    }
}

fn expectUnique(list: *const position.MoveList) !void {
    for (list.slice(), 0..) |left, index| {
        for (list.slice()[index + 1 ..]) |right| {
            try std.testing.expect(left.raw() != right.raw());
        }
    }
}
