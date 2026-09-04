//! Stable 16-bit chess-move value.
const std = @import("std");
const types = @import("types.zig");

pub const Error = error{
    InvalidSquare,
    SameSquare,
    InvalidPromotion,
};

pub const Move = struct {
    raw_value: u16,

    pub const Kind = enum(u2) {
        normal,
        promotion,
        en_passant,
        castling,
    };

    pub const none = Move{ .raw_value = 0 };
    pub const null_move = Move{ .raw_value = 65 };

    pub fn init(
        from_square: types.Square,
        to_square: types.Square,
        kind_value: Kind,
        promotion_piece: types.PieceType,
    ) Error!Move {
        if (from_square == .none or to_square == .none) return error.InvalidSquare;
        if (from_square == to_square) return error.SameSquare;
        if (kind_value == .promotion) {
            if (promotion_piece == .none or promotion_piece == .pawn or promotion_piece == .king)
                return error.InvalidPromotion;
        } else if (promotion_piece != .none) {
            return error.InvalidPromotion;
        }

        return encode(from_square, to_square, kind_value, promotion_piece);
    }

    /// Constructs a move whose squares and kind are already proven by chess
    /// rules. Checked external input must use `init`.
    pub fn normal(from_square: types.Square, to_square: types.Square) Move {
        std.debug.assert(from_square != .none and to_square != .none and from_square != to_square);
        return encode(from_square, to_square, .normal, .none);
    }

    pub fn promotion(
        from_square: types.Square,
        to_square: types.Square,
        promotion_piece: types.PieceType,
    ) Move {
        std.debug.assert(from_square != .none and to_square != .none and from_square != to_square);
        std.debug.assert(promotion_piece != .none and promotion_piece != .pawn and promotion_piece != .king);
        return encode(from_square, to_square, .promotion, promotion_piece);
    }

    pub fn enPassant(from_square: types.Square, to_square: types.Square) Move {
        std.debug.assert(from_square != .none and to_square != .none and from_square != to_square);
        return encode(from_square, to_square, .en_passant, .none);
    }

    pub fn castling(from_square: types.Square, king_destination: types.Square) Move {
        std.debug.assert(from_square != .none and king_destination != .none and from_square != king_destination);
        return encode(from_square, king_destination, .castling, .none);
    }

    pub fn from(self: Move) types.Square {
        std.debug.assert(self.isChessMove());
        return types.Square.fromIndex(@intCast((self.raw_value >> 6) & 0x3f));
    }

    pub fn to(self: Move) types.Square {
        std.debug.assert(self.isChessMove());
        return types.Square.fromIndex(@intCast(self.raw_value & 0x3f));
    }

    pub fn kind(self: Move) Kind {
        std.debug.assert(self.isChessMove());
        return @enumFromInt((self.raw_value >> 14) & 0x3);
    }

    pub fn promotionPiece(self: Move) types.PieceType {
        std.debug.assert(self.kind() == .promotion);
        return @enumFromInt(((self.raw_value >> 12) & 0x3) + @intFromEnum(types.PieceType.knight));
    }

    pub fn isChessMove(self: Move) bool {
        return self.raw_value != none.raw_value and self.raw_value != null_move.raw_value and
            (self.raw_value & 0x3f) != ((self.raw_value >> 6) & 0x3f) and
            ((self.raw_value >> 14) & 0x3 == @intFromEnum(Kind.promotion) or
                self.raw_value & 0x3000 == 0);
    }

    pub fn raw(self: Move) u16 {
        return self.raw_value;
    }

    fn encode(
        from_square: types.Square,
        to_square: types.Square,
        kind_value: Kind,
        promotion_piece: types.PieceType,
    ) Move {
        const promotion_bits: u16 = if (kind_value == .promotion)
            @as(u16, @intFromEnum(promotion_piece) - @intFromEnum(types.PieceType.knight))
        else
            0;
        return .{ .raw_value = @as(u16, to_square.index()) |
            (@as(u16, from_square.index()) << 6) |
            (promotion_bits << 12) |
            (@as(u16, @intFromEnum(kind_value)) << 14) };
    }
};

comptime {
    std.debug.assert(@sizeOf(Move) == 2);
    std.debug.assert(@alignOf(Move) == 2);
}

test "move encoding round-trips every chess move class" {
    // Castling stores the king's actual standard-chess destination; rule code
    // owns the associated rook movement rather than leaking it to consumers.
    const quiet = Move.normal(.g1, .f3);
    try std.testing.expectEqual(types.Square.g1, quiet.from());
    try std.testing.expectEqual(types.Square.f3, quiet.to());
    try std.testing.expectEqual(Move.Kind.normal, quiet.kind());

    const promoted = Move.promotion(.a7, .a8, .queen);
    try std.testing.expectEqual(Move.Kind.promotion, promoted.kind());
    try std.testing.expectEqual(types.PieceType.queen, promoted.promotionPiece());

    try std.testing.expectEqual(Move.Kind.en_passant, Move.enPassant(.e5, .d6).kind());
    try std.testing.expectEqual(types.Square.g1, Move.castling(.e1, .g1).to());
}

test "checked move construction rejects non-moves and false promotions" {
    try std.testing.expectError(error.InvalidSquare, Move.init(.none, .e4, .normal, .none));
    try std.testing.expectError(error.InvalidSquare, Move.init(.e4, .none, .normal, .none));
    try std.testing.expectError(error.SameSquare, Move.init(.e4, .e4, .normal, .none));
    try std.testing.expectError(error.InvalidPromotion, Move.init(.a7, .a8, .promotion, .king));
    try std.testing.expectError(error.InvalidPromotion, Move.init(.e2, .e4, .normal, .queen));
    try std.testing.expect(!Move.none.isChessMove());
    try std.testing.expect(!Move.null_move.isChessMove());
    try std.testing.expect(!(Move{ .raw_value = Move.normal(.b1, .a3).raw() | 0x1000 }).isChessMove());
}
