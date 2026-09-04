//! Transactional standard-chess FEN setup and canonical serialization.
const std = @import("std");
const position = @import("position.zig");
const queries = @import("queries.zig");
const state = @import("state.zig");
const types = @import("types.zig");

pub const start_position = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
pub const max_length = 1024;

pub const ParseError = error{
    TooLong,
    NonAscii,
    FieldCount,
    InvalidPlacement,
    InvalidPiece,
    TooManyPieces,
    PawnOnBackRank,
    InvalidKingCount,
    TooManyPawns,
    ImpossibleMaterial,
    InvalidSide,
    InvalidCastling,
    InvalidEnPassant,
    InvalidHalfmove,
    InvalidFullmove,
    KingCanBeCaptured,
};

pub const WriteError = error{BufferTooSmall};

pub fn parse(fen: []const u8, root_state: *position.PositionState) ParseError!position.Position {
    for (fen) |byte| if (!std.ascii.isAscii(byte)) return error.NonAscii;

    var fields: [6][]const u8 = undefined;
    var field_count: usize = 0;
    var normalized_length: usize = 0;
    var tokens = std.mem.tokenizeAny(u8, fen, " \t\r\n");
    while (tokens.next()) |token| {
        if (field_count == fields.len) return error.FieldCount;
        normalized_length += token.len + @intFromBool(field_count != 0);
        if (normalized_length > max_length) return error.TooLong;
        fields[field_count] = token;
        field_count += 1;
    }
    if (field_count != fields.len) return error.FieldCount;

    var provisional_state: position.PositionState = .{};
    var candidate = position.Position{
        .current = &provisional_state,
    };
    try parsePlacement(fields[0], &candidate.physical);
    state.rebuildPhysical(&candidate.physical) catch return error.InvalidPiece;
    try validateMaterial(&candidate.physical);

    candidate.side_to_move = parseSide(fields[1]) catch return error.InvalidSide;
    provisional_state.castling_rights = parseCastling(fields[2]) catch
        return error.InvalidCastling;
    provisional_state.castling_rights = normalizedCastling(
        &candidate.physical,
        provisional_state.castling_rights,
    );

    const parsed_ep = parseEnPassant(fields[3], candidate.side_to_move) catch
        return error.InvalidEnPassant;
    provisional_state.rule50 = parseUnsigned(u16, fields[4]) catch
        return error.InvalidHalfmove;
    const fullmove = parseUnsigned(u32, fields[5]) catch
        return error.InvalidFullmove;
    if (fullmove == 0) return error.InvalidFullmove;
    const base_ply = @as(u64, fullmove - 1) * 2;
    candidate.game_ply = base_ply + @intFromBool(candidate.side_to_move == .black);

    const previous_king = queries.kingSquare(&candidate, candidate.side_to_move.opposite());
    if (queries.isAttacked(&candidate, previous_king, candidate.side_to_move)) {
        return error.KingCanBeCaptured;
    }

    provisional_state.ep_square = if (parsed_ep != .none and
        queries.hasLegalEnPassantCapture(&candidate, parsed_ep, candidate.side_to_move))
        parsed_ep
    else
        .none;
    state.applyDerived(&provisional_state, state.derive(&candidate));

    root_state.* = provisional_state;
    candidate.current = root_state;
    return candidate;
}

pub fn parseStart(root_state: *position.PositionState) ParseError!position.Position {
    return parse(start_position, root_state);
}

pub fn write(value: *const position.Position, buffer: []u8) WriteError![]const u8 {
    var writer = BufferWriter{ .buffer = buffer };
    var rank: i8 = 7;
    while (rank >= 0) : (rank -= 1) {
        var empty: u8 = 0;
        for (0..8) |file| {
            const square = types.Square.make(@enumFromInt(file), @enumFromInt(rank));
            const piece = value.physical.pieceOn(square);
            if (piece == .none) {
                empty += 1;
                continue;
            }
            if (empty != 0) {
                try writer.byte('0' + empty);
                empty = 0;
            }
            try writer.byte(pieceCharacter(piece));
        }
        if (empty != 0) try writer.byte('0' + empty);
        if (rank != 0) try writer.byte('/');
    }

    try writer.slice(if (value.side_to_move == .white) " w " else " b ");
    const rights = value.current.castling_rights;
    if (rights == .none) {
        try writer.byte('-');
    } else {
        if (rights.contains(.white_king)) try writer.byte('K');
        if (rights.contains(.white_queen)) try writer.byte('Q');
        if (rights.contains(.black_king)) try writer.byte('k');
        if (rights.contains(.black_queen)) try writer.byte('q');
    }

    try writer.byte(' ');
    if (value.current.ep_square == .none) {
        try writer.byte('-');
    } else {
        try writer.byte('a' + @as(u8, value.current.ep_square.file().index()));
        try writer.byte('1' + @as(u8, value.current.ep_square.rank().index()));
    }
    try writer.byte(' ');
    try writer.unsigned(value.current.rule50);
    try writer.byte(' ');
    std.debug.assert(value.game_ply >= @intFromBool(value.side_to_move == .black));
    const fullmove = 1 + (value.game_ply - @intFromBool(value.side_to_move == .black)) / 2;
    try writer.unsigned(fullmove);
    return writer.buffer[0..writer.length];
}

fn parsePlacement(text: []const u8, physical: *position.PhysicalPosition) ParseError!void {
    var rank: i8 = 7;
    var file: u8 = 0;
    var total: u8 = 0;
    for (text) |character| {
        if (character >= '1' and character <= '8') {
            file = std.math.add(u8, file, character - '0') catch return error.InvalidPlacement;
            if (file > 8) return error.InvalidPlacement;
            continue;
        }
        if (character == '/') {
            if (file != 8 or rank == 0) return error.InvalidPlacement;
            rank -= 1;
            file = 0;
            continue;
        }
        if (file >= 8) return error.InvalidPlacement;
        const piece = decodePiece(character) orelse return error.InvalidPiece;
        total = std.math.add(u8, total, 1) catch return error.TooManyPieces;
        if (total > 32) return error.TooManyPieces;
        const square = types.Square.make(@enumFromInt(file), @enumFromInt(rank));
        physical.board[square.index()] = piece;
        file += 1;
    }
    if (rank != 0 or file != 8) return error.InvalidPlacement;
}

fn validateMaterial(physical: *const position.PhysicalPosition) ParseError!void {
    const back_ranks: types.Bitboard = 0xff00_0000_0000_00ff;
    if (physical.by_type[types.PieceType.pawn.index()] & back_ranks != 0) {
        return error.PawnOnBackRank;
    }
    for ([_]types.Color{ .white, .black }) |color| {
        if (@popCount(physical.pieces(color, .king)) != 1) return error.InvalidKingCount;
        const pawns: u8 = @intCast(@popCount(physical.pieces(color, .pawn)));
        if (pawns > 8) return error.TooManyPawns;
        const promoted = excess(physical, color, .knight, 2) +
            excess(physical, color, .bishop, 2) +
            excess(physical, color, .rook, 2) +
            excess(physical, color, .queen, 1);
        if (promoted > 8 - pawns) return error.ImpossibleMaterial;
    }
}

fn excess(
    physical: *const position.PhysicalPosition,
    color: types.Color,
    piece_type: types.PieceType,
    ordinary: u8,
) u8 {
    const count: u8 = @intCast(@popCount(physical.pieces(color, piece_type)));
    return count -| ordinary;
}

fn parseSide(text: []const u8) !types.Color {
    if (std.mem.eql(u8, text, "w")) return .white;
    if (std.mem.eql(u8, text, "b")) return .black;
    return error.InvalidSide;
}

fn parseCastling(text: []const u8) !types.CastlingRights {
    if (std.mem.eql(u8, text, "-")) return .none;
    if (text.len == 0 or text.len > 4) return error.InvalidCastling;
    var raw: u4 = 0;
    for (text) |character| {
        const right: u4 = switch (character) {
            'K' => @intFromEnum(types.CastlingRights.white_king),
            'Q' => @intFromEnum(types.CastlingRights.white_queen),
            'k' => @intFromEnum(types.CastlingRights.black_king),
            'q' => @intFromEnum(types.CastlingRights.black_queen),
            else => return error.InvalidCastling,
        };
        if (raw & right != 0) return error.InvalidCastling;
        raw |= right;
    }
    return @enumFromInt(raw);
}

fn normalizedCastling(
    physical: *const position.PhysicalPosition,
    rights: types.CastlingRights,
) types.CastlingRights {
    var raw = rights.raw();
    if (physical.pieceOn(.e1) != .white_king) raw &= ~@intFromEnum(types.CastlingRights.white_king) &
        ~@intFromEnum(types.CastlingRights.white_queen);
    if (physical.pieceOn(.h1) != .white_rook) raw &= ~@intFromEnum(types.CastlingRights.white_king);
    if (physical.pieceOn(.a1) != .white_rook) raw &= ~@intFromEnum(types.CastlingRights.white_queen);
    if (physical.pieceOn(.e8) != .black_king) raw &= ~@intFromEnum(types.CastlingRights.black_king) &
        ~@intFromEnum(types.CastlingRights.black_queen);
    if (physical.pieceOn(.h8) != .black_rook) raw &= ~@intFromEnum(types.CastlingRights.black_king);
    if (physical.pieceOn(.a8) != .black_rook) raw &= ~@intFromEnum(types.CastlingRights.black_queen);
    return @enumFromInt(raw);
}

fn parseEnPassant(text: []const u8, side_to_move: types.Color) !types.Square {
    if (std.mem.eql(u8, text, "-")) return .none;
    if (text.len != 2 or text[0] < 'a' or text[0] > 'h') return error.InvalidEnPassant;
    const required_rank: u8 = if (side_to_move == .white) '6' else '3';
    if (text[1] != required_rank) return error.InvalidEnPassant;
    return types.Square.make(
        @enumFromInt(text[0] - 'a'),
        @enumFromInt(text[1] - '1'),
    );
}

fn parseUnsigned(comptime T: type, text: []const u8) !T {
    if (text.len == 0) return error.InvalidNumber;
    var result: T = 0;
    for (text) |character| {
        if (character < '0' or character > '9') return error.InvalidNumber;
        result = std.math.mul(T, result, 10) catch return error.InvalidNumber;
        result = std.math.add(T, result, character - '0') catch return error.InvalidNumber;
    }
    return result;
}

fn decodePiece(character: u8) ?types.Piece {
    return switch (character) {
        'P' => .white_pawn,
        'N' => .white_knight,
        'B' => .white_bishop,
        'R' => .white_rook,
        'Q' => .white_queen,
        'K' => .white_king,
        'p' => .black_pawn,
        'n' => .black_knight,
        'b' => .black_bishop,
        'r' => .black_rook,
        'q' => .black_queen,
        'k' => .black_king,
        else => null,
    };
}

fn pieceCharacter(piece: types.Piece) u8 {
    return switch (piece) {
        .white_pawn => 'P',
        .white_knight => 'N',
        .white_bishop => 'B',
        .white_rook => 'R',
        .white_queen => 'Q',
        .white_king => 'K',
        .black_pawn => 'p',
        .black_knight => 'n',
        .black_bishop => 'b',
        .black_rook => 'r',
        .black_queen => 'q',
        .black_king => 'k',
        .none, _ => unreachable,
    };
}

const BufferWriter = struct {
    buffer: []u8,
    length: usize = 0,

    fn byte(self: *BufferWriter, value: u8) WriteError!void {
        if (self.length == self.buffer.len) return error.BufferTooSmall;
        self.buffer[self.length] = value;
        self.length += 1;
    }

    fn slice(self: *BufferWriter, value: []const u8) WriteError!void {
        if (value.len > self.buffer.len - self.length) return error.BufferTooSmall;
        @memcpy(self.buffer[self.length..][0..value.len], value);
        self.length += value.len;
    }

    fn unsigned(self: *BufferWriter, value: anytype) WriteError!void {
        var remaining = value;
        var digits: [20]u8 = undefined;
        var start = digits.len;
        while (true) {
            start -= 1;
            digits[start] = '0' + @as(u8, @intCast(remaining % 10));
            remaining /= 10;
            if (remaining == 0) break;
        }
        try self.slice(digits[start..]);
    }
};

test "start position constructs one coherent canonical state" {
    // The setup producer must agree across mailbox, bitboards, keys, checkers
    // and canonical FEN before later make/unmake or movegen consumes it.
    var root: position.PositionState = .{};
    const value = try parseStart(&root);
    try std.testing.expectEqual(@as(u7, 32), @popCount(value.physical.occupied()));
    try std.testing.expectEqual(types.CastlingRights.all, root.castling_rights);
    try std.testing.expectEqual(@as(types.Bitboard, 0), root.checkers);
    try std.testing.expect(state.isConsistent(&value));

    var buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(start_position, try write(&value, &buffer));

    var check_root: position.PositionState = .{};
    const in_check = try parse("4k3/8/8/8/8/8/4R3/4K3 b - - 0 1", &check_root);
    try std.testing.expectEqual(types.Square.e2.bit(), check_root.checkers);
    try std.testing.expect(state.isConsistent(&in_check));
}

test "FEN normalizes stale rights and retains only legal en passant identity" {
    // Castling/EP tokens are position-identity facts. Harmless stale claims are
    // removed, while an EP capture exposing the capturer's king is not hashed.
    var stale_root: position.PositionState = .{};
    const stale = try parse("4k3/8/8/8/8/8/8/4K3 w KQkq e6 7 12", &stale_root);
    try std.testing.expectEqual(types.CastlingRights.none, stale_root.castling_rights);
    try std.testing.expectEqual(types.Square.none, stale_root.ep_square);
    try std.testing.expect(state.isConsistent(&stale));
    var buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        "4k3/8/8/8/8/8/8/4K3 w - - 7 12",
        try write(&stale, &buffer),
    );
    var canonical_root: position.PositionState = .{};
    _ = try parse("4k3/8/8/8/8/8/8/4K3 w - - 7 12", &canonical_root);
    try std.testing.expectEqual(canonical_root.key, stale_root.key);

    var legal_root: position.PositionState = .{};
    const legal = try parse("4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1", &legal_root);
    try std.testing.expectEqual(types.Square.e3, legal_root.ep_square);
    try std.testing.expect(state.isConsistent(&legal));
    try std.testing.expectEqualStrings(
        "4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1",
        try write(&legal, &buffer),
    );
    var no_ep_root: position.PositionState = .{};
    _ = try parse("4k3/8/8/8/3pP3/8/8/4K3 b - - 0 1", &no_ep_root);
    try std.testing.expect(legal_root.key != no_ep_root.key);

    var pinned_root: position.PositionState = .{};
    const pinned = try parse("3k4/8/8/8/3pP3/8/8/3RK3 b - e3 0 1", &pinned_root);
    try std.testing.expectEqual(types.Square.none, pinned_root.ep_square);
    try std.testing.expect(state.isConsistent(&pinned));
}

test "FEN rejects malformed and impossible core positions transactionally" {
    // A failed external setup cannot overwrite the caller's last valid root
    // state; syntax, material and previous-move legality are distinct checks.
    var root: position.PositionState = .{ .key = 0x1234 };
    try std.testing.expectError(error.FieldCount, parse("invalid", &root));
    try std.testing.expectEqual(@as(types.Key, 0x1234), root.key);
    const oversized: [max_length + 1]u8 = @splat('x');
    try std.testing.expectError(error.TooLong, parse(&oversized, &root));
    try std.testing.expectError(
        error.PawnOnBackRank,
        parse("4k3/8/8/8/8/8/8/P3K3 w - - 0 1", &root),
    );
    try std.testing.expectError(
        error.InvalidKingCount,
        parse("8/8/8/8/8/8/8/4K3 w - - 0 1", &root),
    );
    try std.testing.expectError(
        error.TooManyPawns,
        parse("4k3/8/8/8/8/P7/PPPPPPPP/4K3 w - - 0 1", &root),
    );
    try std.testing.expectError(
        error.ImpossibleMaterial,
        parse("4k3/8/8/8/8/Q7/PPPPPPPP/Q3K3 w - - 0 1", &root),
    );
    try std.testing.expectError(
        error.KingCanBeCaptured,
        parse("4k3/8/8/8/8/8/4R3/4K3 w - - 0 1", &root),
    );
    try std.testing.expectError(
        error.InvalidCastling,
        parse("4k3/8/8/8/8/8/8/4K3 w KK - 0 1", &root),
    );
    try std.testing.expectError(
        error.InvalidFullmove,
        parse("4k3/8/8/8/8/8/8/4K3 w - - 0 0", &root),
    );
    try std.testing.expectEqual(@as(types.Key, 0x1234), root.key);
}

test "FEN serialization is bounded" {
    var root: position.PositionState = .{};
    const value = try parseStart(&root);
    var short: [8]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, write(&value, &short));
}
