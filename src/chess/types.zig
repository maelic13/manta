//! Precise value types shared by the chess domain.
const std = @import("std");

pub const Bitboard = u64;
pub const Key = u64;
pub const max_ply = 256;
pub const move_capacity = 256;

pub const Color = enum(u1) {
    white,
    black,

    pub fn opposite(self: Color) Color {
        return @enumFromInt(@intFromEnum(self) ^ 1);
    }

    pub fn index(self: Color) usize {
        return @intFromEnum(self);
    }
};

pub const PieceType = enum(u3) {
    none = 0,
    pawn = 1,
    knight = 2,
    bishop = 3,
    rook = 4,
    queen = 5,
    king = 6,

    pub fn index(self: PieceType) usize {
        return @intFromEnum(self);
    }

    pub fn isPiece(self: PieceType) bool {
        return self != .none;
    }
};

/// Piece values preserve the conventional color-bit layout while rejecting
/// the two unused encodings at checked boundaries.
pub const Piece = enum(u4) {
    none = 0,
    white_pawn = 1,
    white_knight = 2,
    white_bishop = 3,
    white_rook = 4,
    white_queen = 5,
    white_king = 6,
    black_pawn = 9,
    black_knight = 10,
    black_bishop = 11,
    black_rook = 12,
    black_queen = 13,
    black_king = 14,
    _,

    pub fn make(side: Color, piece_type: PieceType) Piece {
        std.debug.assert(piece_type.isPiece());
        const raw = (@as(u4, @intFromEnum(side)) << 3) | @as(u4, @intFromEnum(piece_type));
        return @enumFromInt(raw);
    }

    pub fn isValid(self: Piece) bool {
        const raw = @intFromEnum(self);
        return raw == 0 or (raw >= 1 and raw <= 6) or (raw >= 9 and raw <= 14);
    }

    pub fn pieceType(self: Piece) PieceType {
        std.debug.assert(self != .none and self.isValid());
        return @enumFromInt(@intFromEnum(self) & 0b111);
    }

    pub fn color(self: Piece) Color {
        std.debug.assert(self != .none and self.isValid());
        return @enumFromInt(@intFromEnum(self) >> 3);
    }

    pub fn index(self: Piece) usize {
        return @intFromEnum(self);
    }
};

pub const File = enum(u3) {
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,

    pub fn index(self: File) u3 {
        return @intFromEnum(self);
    }
};

pub const Rank = enum(u3) {
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,

    pub fn index(self: Rank) u3 {
        return @intFromEnum(self);
    }
};

pub const Square = enum(u7) {
    a1,
    b1,
    c1,
    d1,
    e1,
    f1,
    g1,
    h1,
    a2,
    b2,
    c2,
    d2,
    e2,
    f2,
    g2,
    h2,
    a3,
    b3,
    c3,
    d3,
    e3,
    f3,
    g3,
    h3,
    a4,
    b4,
    c4,
    d4,
    e4,
    f4,
    g4,
    h4,
    a5,
    b5,
    c5,
    d5,
    e5,
    f5,
    g5,
    h5,
    a6,
    b6,
    c6,
    d6,
    e6,
    f6,
    g6,
    h6,
    a7,
    b7,
    c7,
    d7,
    e7,
    f7,
    g7,
    h7,
    a8,
    b8,
    c8,
    d8,
    e8,
    f8,
    g8,
    h8,
    none,

    pub fn fromIndex(index_value: u6) Square {
        return @enumFromInt(index_value);
    }

    pub fn index(self: Square) u6 {
        std.debug.assert(self != .none);
        return @intCast(@intFromEnum(self));
    }

    pub fn file(self: Square) File {
        return @enumFromInt(self.index() & 7);
    }

    pub fn rank(self: Square) Rank {
        return @enumFromInt(self.index() >> 3);
    }

    pub fn make(file_value: File, rank_value: Rank) Square {
        return @enumFromInt((@as(u6, rank_value.index()) << 3) | file_value.index());
    }

    pub fn bit(self: Square) Bitboard {
        return @as(Bitboard, 1) << self.index();
    }

    pub fn flipRank(self: Square) Square {
        return @enumFromInt(self.index() ^ 56);
    }

    pub fn flipFile(self: Square) Square {
        return @enumFromInt(self.index() ^ 7);
    }
};

pub const Direction = enum(i8) {
    north = 8,
    south = -8,
    east = 1,
    west = -1,
    north_east = 9,
    north_west = 7,
    south_east = -7,
    south_west = -9,
};

pub const CastlingRights = enum(u4) {
    none = 0,
    white_king = 1,
    white_queen = 2,
    black_king = 4,
    black_queen = 8,
    all = 15,
    _,

    pub fn raw(self: CastlingRights) u4 {
        return @intFromEnum(self);
    }

    pub fn contains(self: CastlingRights, right: CastlingRights) bool {
        return self.raw() & right.raw() == right.raw();
    }

    pub fn intersect(self: CastlingRights, mask: CastlingRights) CastlingRights {
        return @enumFromInt(self.raw() & mask.raw());
    }
};

pub fn relativeRank(color: Color, rank_value: Rank) Rank {
    return if (color == .white) rank_value else @enumFromInt(rank_value.index() ^ 7);
}

comptime {
    std.debug.assert(@sizeOf(Color) == 1);
    std.debug.assert(@sizeOf(PieceType) == 1);
    std.debug.assert(@sizeOf(Piece) == 1);
    std.debug.assert(@sizeOf(Square) == 1);
    std.debug.assert(@sizeOf(CastlingRights) == 1);
    std.debug.assert(max_ply == 256);
    std.debug.assert(move_capacity == 256);
}

test "square coordinates preserve chess geometry" {
    // This convention makes north a constant +8 and file/rank extraction masks.
    try std.testing.expectEqual(@as(u6, 0), Square.a1.index());
    try std.testing.expectEqual(@as(u6, 63), Square.h8.index());
    try std.testing.expectEqual(Square.e4, Square.make(.e, .four));
    try std.testing.expectEqual(Square.a8, Square.a1.flipRank());
    try std.testing.expectEqual(Square.h1, Square.a1.flipFile());
}

test "piece encoding keeps color and type orthogonal" {
    // Every legal colored piece round-trips; unused encodings are not pieces.
    for ([_]Color{ .white, .black }) |color| {
        for ([_]PieceType{ .pawn, .knight, .bishop, .rook, .queen, .king }) |piece_type| {
            const piece = Piece.make(color, piece_type);
            try std.testing.expect(piece.isValid());
            try std.testing.expectEqual(color, piece.color());
            try std.testing.expectEqual(piece_type, piece.pieceType());
        }
    }
    try std.testing.expect(!(@as(Piece, @enumFromInt(7))).isValid());
    try std.testing.expect(!(@as(Piece, @enumFromInt(8))).isValid());
}
