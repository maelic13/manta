//! Independent reconstruction of redundant physical and derived position state.
const std = @import("std");
const position = @import("position.zig");
const queries = @import("queries.zig");
const types = @import("types.zig");
const zobrist = @import("zobrist.zig");

pub const PhysicalError = error{InvalidPieceEncoding};

pub const Derived = struct {
    key: types.Key,
    pawn_key: types.Key,
    minor_key: types.Key,
    non_pawn_key: [2]types.Key,
    checkers: types.Bitboard,
};

/// Rebuilds every redundant physical fact from the mailbox. Setup and test
/// code use this path; hot make/unmake updates the same facts incrementally.
pub fn rebuildPhysical(physical: *position.PhysicalPosition) PhysicalError!void {
    physical.by_type = @splat(0);
    physical.by_color = @splat(0);
    physical.piece_count = @splat(0);
    physical.king_square = @splat(.none);

    for (physical.board, 0..) |piece, square_index| {
        if (!piece.isValid()) return error.InvalidPieceEncoding;
        if (piece == .none) continue;
        const bit = @as(types.Bitboard, 1) << @intCast(square_index);
        physical.by_type[types.PieceType.none.index()] |= bit;
        physical.by_type[piece.pieceType().index()] |= bit;
        physical.by_color[piece.color().index()] |= bit;
        physical.piece_count[piece.index()] += 1;
        if (piece.pieceType() == .king) {
            physical.king_square[piece.color().index()] = types.Square.fromIndex(@intCast(square_index));
        }
    }
}

pub fn derive(value: *const position.Position) Derived {
    var result = Derived{
        .key = zobrist.tables.castling[value.current.castling_rights.raw()],
        .pawn_key = 0,
        .minor_key = 0,
        .non_pawn_key = @splat(0),
        .checkers = 0,
    };

    for (value.physical.board, 0..) |piece, square_index| {
        if (piece == .none) continue;
        const piece_key = zobrist.tables.piece_square[piece.index()][square_index];
        result.key ^= piece_key;
        switch (piece.pieceType()) {
            .pawn => result.pawn_key ^= piece_key,
            .knight, .bishop => {
                result.minor_key ^= piece_key;
                result.non_pawn_key[piece.color().index()] ^= piece_key;
            },
            .rook, .queen, .king => result.non_pawn_key[piece.color().index()] ^= piece_key,
            .none => unreachable,
        }
    }

    if (value.side_to_move == .black) result.key ^= zobrist.tables.side;
    if (value.current.ep_square != .none) {
        result.key ^= zobrist.tables.en_passant_file[value.current.ep_square.file().index()];
    }
    result.checkers = queries.attackersToBy(
        value,
        queries.kingSquare(value, value.side_to_move),
        value.physical.occupied(),
        value.side_to_move.opposite(),
    );
    return result;
}

pub fn applyDerived(target: *position.PositionState, derived: Derived) void {
    target.key = derived.key;
    target.pawn_key = derived.pawn_key;
    target.minor_key = derived.minor_key;
    target.non_pawn_key = derived.non_pawn_key;
    target.checkers = derived.checkers;
}

pub fn isConsistent(value: *const position.Position) bool {
    var rebuilt = position.PhysicalPosition{ .board = value.physical.board };
    rebuildPhysical(&rebuilt) catch return false;
    if (!std.meta.eql(rebuilt, value.physical)) return false;

    const expected = derive(value);
    const current = value.current;
    return current.key == expected.key and
        current.pawn_key == expected.pawn_key and
        current.minor_key == expected.minor_key and
        current.non_pawn_key[0] == expected.non_pawn_key[0] and
        current.non_pawn_key[1] == expected.non_pawn_key[1] and
        current.checkers == expected.checkers;
}

test "reconstruction detects redundant physical and derived-state drift" {
    // Mailbox, bitboards, counts and keys have different future producers.
    // Independent reconstruction must reject corruption in either family.
    var root: position.PositionState = .{};
    var value = position.Position.initEmpty(&root);
    value.physical.board[types.Square.e1.index()] = .white_king;
    value.physical.board[types.Square.e8.index()] = .black_king;
    try rebuildPhysical(&value.physical);
    applyDerived(&root, derive(&value));
    try std.testing.expect(isConsistent(&value));

    value.physical.by_color[types.Color.white.index()] ^= types.Square.a1.bit();
    try std.testing.expect(!isConsistent(&value));
    value.physical.by_color[types.Color.white.index()] ^= types.Square.a1.bit();
    root.key ^= 1;
    try std.testing.expect(!isConsistent(&value));
}
