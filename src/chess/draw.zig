//! Orthodox draw facts, separate from evaluation and search policy.
const std = @import("std");
const fen = @import("fen.zig");
const history = @import("history.zig");
const movegen = @import("movegen.zig");
const position = @import("position.zig");
const state = @import("state.zig");
const types = @import("types.zig");

/// Counts earlier occurrences of the current position inside the reversible,
/// post-null state chain. The current position itself is not included.
pub fn priorRepetitions(value: *const position.Position) u16 {
    const current = value.current;
    const limit: usize = @min(current.rule50, current.plies_from_null);
    var matches: u16 = 0;
    var cursor = current.previous;
    var distance: usize = 1;
    while (cursor != null and distance <= limit) {
        if (distance % 2 == 0 and cursor.?.key == current.key) matches +|= 1;
        cursor = cursor.?.previous;
        distance += 1;
    }
    return matches;
}

/// Official claim fact: the current position has occurred at least three
/// times, counting the current occurrence.
pub fn isThreefold(value: *const position.Position) bool {
    return priorRepetitions(value) >= 2;
}

/// Search-cycle fact: one prior occurrence is sufficient when that occurrence
/// lies inside the current search tree; history before the root still requires
/// two prior occurrences. `search_ply` is the current distance from that root.
///
/// Both facts are already carried by the state the transition established, so
/// this is a constant-time read rather than a walk repeated at every visit.
/// A negative distance means the key has occurred at least three times, which
/// a side to move may claim wherever it lies.
pub fn isSearchRepetition(value: *const position.Position, search_ply: u16) bool {
    const repetition = value.current.repetition;
    if (repetition == 0) return false;
    if (repetition < 0) return true;
    return @as(u16, @intCast(repetition)) <= search_ply;
}

/// The 50-move claim applies at 100 halfmoves, except that checkmate has
/// precedence when the side to move has no legal move.
pub fn isRule50Draw(value: *const position.Position) bool {
    if (value.current.rule50 < 100) return false;
    if (value.current.checkers == 0) return true;
    var legal = position.MoveList.init();
    movegen.generate(.all, value, &legal);
    return legal.count != 0;
}

/// Provably dead material configurations. This intentionally excludes merely
/// unforceable mates such as king and two knights against king.
pub fn isDeadPosition(value: *const position.Position) bool {
    const physical = &value.physical;
    if (physical.by_type[types.PieceType.pawn.index()] != 0 or
        physical.by_type[types.PieceType.rook.index()] != 0 or
        physical.by_type[types.PieceType.queen.index()] != 0)
    {
        return false;
    }

    const knights = physical.by_type[types.PieceType.knight.index()];
    var bishops = physical.by_type[types.PieceType.bishop.index()];
    const minor_count = @popCount(knights | bishops);
    if (minor_count <= 1) return true;
    if (knights != 0) return false;

    var color_mask: u2 = 0;
    while (bishops != 0) {
        const square = types.Square.fromIndex(@intCast(@ctz(bishops)));
        const square_color: u1 = @truncate(square.file().index() ^ square.rank().index());
        color_mask |= @as(u2, 1) << square_color;
        bishops &= bishops - 1;
    }
    return @popCount(color_mask) == 1;
}

pub fn isClaimableDraw(value: *const position.Position) bool {
    return isRule50Draw(value) or isThreefold(value) or isDeadPosition(value);
}

pub fn isSearchDraw(value: *const position.Position, search_ply: u16) bool {
    return isRule50Draw(value) or isSearchRepetition(value, search_ply) or
        isDeadPosition(value);
}

test "repetition distinguishes official claims from search cycles" {
    const cycle = [_][]const u8{ "g1f3", "g8f6", "f3g1", "f6g8" };
    var states: [9]position.PositionState = undefined;
    var moves: [8]@import("move.zig").Move = undefined;

    const twice = try history.build(fen.start_position, &cycle, states[0..5], moves[0..4]);
    try std.testing.expectEqual(@as(i16, 4), twice.position.current.repetition);
    try std.testing.expectEqual(@as(u16, 1), priorRepetitions(&twice.position));
    try std.testing.expect(!isThreefold(&twice.position));
    try std.testing.expect(!isSearchRepetition(&twice.position, 0));
    try std.testing.expect(isSearchRepetition(&twice.position, 4));

    const three_times = try history.build(
        fen.start_position,
        &.{ "g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8" },
        &states,
        &moves,
    );
    // The third occurrence is claimable wherever it stands, which the sign of
    // the recorded distance is what carries.
    try std.testing.expectEqual(@as(i16, -4), three_times.position.current.repetition);
    try std.testing.expectEqual(@as(u16, 2), priorRepetitions(&three_times.position));
    try std.testing.expect(isThreefold(&three_times.position));
    try std.testing.expect(isSearchRepetition(&three_times.position, 0));
}

test "recorded repetition state agrees with an independent chain walk" {
    // FUNC-005: the constant-time consumer must answer exactly what a walk of
    // the reversible window answers, including which occurrence is nearest and
    // whether an earlier one exists. The cycle below revisits the same key at
    // several distances, with an irreversible pawn move fencing the window.
    const played = [_][]const u8{
        "g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8",
        "e2e4", "e7e5", "g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6",
    };
    var states: [played.len + 1]position.PositionState = undefined;
    var moves: [played.len]@import("move.zig").Move = undefined;
    for (1..played.len + 1) |count| {
        const game = try history.build(
            fen.start_position,
            played[0..count],
            states[0 .. count + 1],
            moves[0..count],
        );
        const value = &game.position;
        const walked = independentNearestRepetition(value);
        try std.testing.expectEqual(walked, value.current.repetition);
        try std.testing.expectEqual(walked < 0, priorRepetitions(value) >= 2);
        for (0..count + 1) |ply| {
            const search_ply: u16 = @intCast(ply);
            try std.testing.expectEqual(
                walkedSearchRepetition(value, search_ply),
                isSearchRepetition(value, search_ply),
            );
        }
    }
}

/// Independent oracle: nearest prior occurrence by walking the chain, negated
/// when a second one exists inside the same window.
fn independentNearestRepetition(value: *const position.Position) i16 {
    const current = value.current;
    const limit: usize = @min(current.rule50, current.plies_from_null);
    var nearest: i16 = 0;
    var matches: u16 = 0;
    var cursor = current.previous;
    var distance: usize = 1;
    while (cursor != null and distance <= limit) {
        if (distance % 2 == 0 and cursor.?.key == current.key) {
            matches += 1;
            if (nearest == 0) nearest = @intCast(distance);
        }
        cursor = cursor.?.previous;
        distance += 1;
    }
    return if (matches >= 2) -nearest else nearest;
}

/// Independent oracle for the search-cycle rule, expressed as the chain walk
/// the production consumer replaced.
fn walkedSearchRepetition(value: *const position.Position, search_ply: u16) bool {
    const current = value.current;
    const limit: usize = @min(current.rule50, current.plies_from_null);
    var matches: u16 = 0;
    var cursor = current.previous;
    var distance: usize = 1;
    while (cursor != null and distance <= limit) {
        if (distance % 2 == 0 and cursor.?.key == current.key) {
            matches += 1;
            if (distance <= @as(usize, search_ply) or matches >= 2) return true;
        }
        cursor = cursor.?.previous;
        distance += 1;
    }
    return false;
}

test "irreversible and null boundaries fence repetition" {
    var states: [6]position.PositionState = undefined;
    var moves: [4]@import("move.zig").Move = undefined;
    var game = try history.build(
        fen.start_position,
        &.{ "g1f3", "g8f6", "e2e4", "f6g8" },
        states[0..5],
        &moves,
    );
    try std.testing.expectEqual(@as(i16, 0), game.position.current.repetition);
    try std.testing.expectEqual(@as(u16, 0), priorRepetitions(&game.position));

    @import("transition.zig").makeNull(&game.position, &states[5]);
    try std.testing.expectEqual(@as(u16, 0), priorRepetitions(&game.position));
}

test "rule-50 draw preserves checkmate precedence" {
    const fixtures = [_]struct { fen_text: []const u8, expected: bool }{
        .{ .fen_text = "7k/6Q1/6K1/8/8/8/8/8 b - - 100 1", .expected = false },
        .{ .fen_text = "7k/8/5K2/8/8/8/8/7R b - - 100 1", .expected = true },
        .{ .fen_text = "7k/8/8/8/8/8/8/K7 w - - 100 1", .expected = true },
    };
    for (fixtures) |fixture| {
        var root: position.PositionState = .{};
        const value = try fen.parse(fixture.fen_text, &root);
        try std.testing.expect(state.isConsistent(&value));
        try std.testing.expectEqual(fixture.expected, isRule50Draw(&value));
    }
}

test "dead position recognizes only provably dead material sets" {
    const fixtures = [_]struct { fen_text: []const u8, expected: bool }{
        .{ .fen_text = "7k/8/8/8/8/8/8/K7 w - - 0 1", .expected = true },
        .{ .fen_text = "7k/8/8/8/8/8/8/KB6 w - - 0 1", .expected = true },
        .{ .fen_text = "7k/8/8/5b2/8/8/8/KB6 w - - 0 1", .expected = true },
        .{ .fen_text = "7k/8/8/8/5b2/8/8/KB6 w - - 0 1", .expected = false },
        .{ .fen_text = "7k/8/8/8/8/8/8/KNN5 w - - 0 1", .expected = false },
        .{ .fen_text = "7k/8/8/8/8/8/P7/K7 w - - 0 1", .expected = false },
    };
    for (fixtures) |fixture| {
        var root: position.PositionState = .{};
        const value = try fen.parse(fixture.fen_text, &root);
        try std.testing.expect(state.isConsistent(&value));
        try std.testing.expectEqual(fixture.expected, isDeadPosition(&value));
    }
}
