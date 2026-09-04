//! Fixed-size standard UCI coordinate move notation.
const std = @import("std");
const move = @import("move.zig");
const movegen = @import("movegen.zig");
const position = @import("position.zig");
const types = @import("types.zig");

pub const Error = error{
    NotChessMove,
    Malformed,
    Illegal,
};

pub const Text = struct {
    bytes: [5]u8,
    length: u3,

    pub fn slice(self: *const Text) []const u8 {
        return self.bytes[0..self.length];
    }
};

pub fn format(chess_move: move.Move) Error!Text {
    if (!chess_move.isChessMove()) return error.NotChessMove;
    const from = chess_move.from();
    const to = chess_move.to();
    var result = Text{
        .bytes = .{
            'a' + @as(u8, from.file().index()),
            '1' + @as(u8, from.rank().index()),
            'a' + @as(u8, to.file().index()),
            '1' + @as(u8, to.rank().index()),
            0,
        },
        .length = 4,
    };
    if (chess_move.kind() == .promotion) {
        result.bytes[4] = switch (chess_move.promotionPiece()) {
            .knight => 'n',
            .bishop => 'b',
            .rook => 'r',
            .queen => 'q',
            .none, .pawn, .king => unreachable,
        };
        result.length = 5;
    }
    return result;
}

/// Resolves canonical lowercase coordinate text against the legal move set.
/// Matching generated moves avoids guessing castling or en-passant kinds at
/// the external boundary.
pub fn parseLegal(value: *const position.Position, text: []const u8) Error!move.Move {
    if (text.len != 4 and text.len != 5) return error.Malformed;
    const from = parseSquare(text[0..2]) orelse return error.Malformed;
    const to = parseSquare(text[2..4]) orelse return error.Malformed;
    if (from == to) return error.Malformed;
    const promotion = if (text.len == 5)
        parsePromotion(text[4]) orelse return error.Malformed
    else
        types.PieceType.none;

    var legal = position.MoveList.init();
    movegen.generate(.all, value, &legal);
    for (legal.slice()) |candidate| {
        if (candidate.from() != from or candidate.to() != to) continue;
        if (candidate.kind() == .promotion) {
            if (promotion == candidate.promotionPiece()) return candidate;
        } else if (promotion == .none) {
            return candidate;
        }
    }
    return error.Illegal;
}

fn parseSquare(text: []const u8) ?types.Square {
    if (text.len != 2 or text[0] < 'a' or text[0] > 'h' or
        text[1] < '1' or text[1] > '8') return null;
    return types.Square.make(@enumFromInt(text[0] - 'a'), @enumFromInt(text[1] - '1'));
}

fn parsePromotion(character: u8) ?types.PieceType {
    return switch (character) {
        'n' => .knight,
        'b' => .bishop,
        'r' => .rook,
        'q' => .queen,
        else => null,
    };
}

test "coordinate notation is canonical strict and legal-position aware" {
    const fen = @import("fen.zig");

    var start_root: position.PositionState = .{};
    const start = try fen.parseStart(&start_root);
    const e2e4 = try format(move.Move.normal(.e2, .e4));
    try std.testing.expectEqualStrings("e2e4", e2e4.slice());
    try std.testing.expectEqual(
        move.Move.normal(.e2, .e4).raw(),
        (try parseLegal(&start, "e2e4")).raw(),
    );
    try std.testing.expectError(error.Illegal, parseLegal(&start, "e2e5"));
    try std.testing.expectError(error.Malformed, parseLegal(&start, "E2E4"));
    try std.testing.expectError(error.Malformed, parseLegal(&start, "0000"));
    try std.testing.expectError(error.NotChessMove, format(move.Move.none));
    try std.testing.expectError(error.NotChessMove, format(move.Move.null_move));

    var promotion_root: position.PositionState = .{};
    const promotion = try fen.parse("7k/P7/8/8/8/8/8/7K w - - 0 1", &promotion_root);
    const promoted = try parseLegal(&promotion, "a7a8q");
    try std.testing.expectEqual(types.PieceType.queen, promoted.promotionPiece());
    const promoted_text = try format(promoted);
    try std.testing.expectEqualStrings("a7a8q", promoted_text.slice());
}

test "every legal move round-trips through canonical notation" {
    const fen = @import("fen.zig");
    const state = @import("state.zig");
    const fixtures = [_][]const u8{
        fen.start_position,
        "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
        "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
        "1r5k/P7/8/8/8/8/8/7K w - - 0 1",
    };
    for (fixtures) |fixture| {
        var root: position.PositionState = .{};
        const value = try fen.parse(fixture, &root);
        try std.testing.expect(state.isConsistent(&value));
        var legal = position.MoveList.init();
        movegen.generate(.all, &value, &legal);
        for (legal.slice()) |chess_move| {
            const text = try format(chess_move);
            try std.testing.expectEqual(
                chess_move.raw(),
                (try parseLegal(&value, text.slice())).raw(),
            );
        }
    }
}
