//! Native Zig fuzz entry points for checked chess boundaries and transitions.
const std = @import("std");
const manta = @import("manta");
const support = @import("support/chess.zig");

const chess = manta.chess;

test "fuzz FEN parsing and canonical reconstruction" {
    try std.testing.fuzz({}, fuzzFen, .{});
}

test "fuzz checked move and history boundaries" {
    try std.testing.fuzz({}, fuzzCheckedBoundaries, .{});
}

test "fuzz reversible legal and null transition sequences" {
    try std.testing.fuzz({}, fuzzTransitions, .{});
}

fn fuzzFen(_: void, smith: *std.testing.Smith) !void {
    var input_buffer: [chess.fen.max_length + 1]u8 = undefined;
    const input_length = smith.sliceWeightedBytes(&input_buffer, &.{
        .rangeAtMost(u8, 0, 255, 1),
        .rangeAtMost(u8, 32, 126, 8),
        .value(u8, ' ', 8),
        .value(u8, '/', 8),
        .value(u8, '-', 8),
    });
    const input = input_buffer[0..input_length];
    const sentinel = chess.position.PositionState{ .key = 0xA55A_1122_3344_7788 };
    var root = sentinel;
    var value = chess.fen.parse(input, &root) catch {
        try std.testing.expectEqualDeep(sentinel, root);
        return;
    };

    try std.testing.expect(chess.state.isConsistent(&value));
    var canonical_buffer: [chess.fen.max_length]u8 = undefined;
    const canonical = try chess.fen.write(&value, &canonical_buffer);
    var reparsed_root: chess.position.PositionState = .{};
    const reparsed = try chess.fen.parse(canonical, &reparsed_root);
    try std.testing.expectEqualDeep(value.physical, reparsed.physical);
    try std.testing.expectEqual(value.side_to_move, reparsed.side_to_move);
    try std.testing.expectEqual(value.game_ply, reparsed.game_ply);
    try std.testing.expectEqual(root.castling_rights, reparsed_root.castling_rights);
    try std.testing.expectEqual(root.ep_square, reparsed_root.ep_square);
    try std.testing.expectEqual(root.rule50, reparsed_root.rule50);
    try std.testing.expectEqual(root.key, reparsed_root.key);
    try std.testing.expectEqual(root.checkers, reparsed_root.checkers);

    value.current = &root;
    try std.testing.expect(chess.state.isConsistent(&value));
}

fn fuzzCheckedBoundaries(_: void, smith: *std.testing.Smith) !void {
    const root_fen = support.roots[smith.value(u3)];
    var root: chess.position.PositionState = .{};
    var value = try chess.fen.parse(root_fen, &root);
    const candidate = chess.move.Move{ .raw_value = smith.value(u16) };
    const independently_legal = chess.movegen.isLegal(&value, candidate);
    var generated = chess.position.MoveList.init();
    chess.movegen.generate(.all, &value, &generated);
    var generated_match = false;
    for (generated.slice()) |legal| {
        if (legal.raw() == candidate.raw()) generated_match = true;
    }
    try std.testing.expectEqual(independently_legal, generated_match);
    if (independently_legal) {
        const before_physical = value.physical;
        const before_root = root;
        var child: chess.position.PositionState = .{};
        chess.transition.makeMove(&value, candidate, &child);
        try std.testing.expect(chess.state.isConsistent(&value));
        chess.transition.unmakeMove(&value, candidate);
        try std.testing.expectEqualDeep(before_physical, value.physical);
        try std.testing.expectEqualDeep(before_root, root);
        try std.testing.expect(value.current == &root);
    }

    var token_bytes: [16][5]u8 = undefined;
    var tokens: [16][]const u8 = undefined;
    const token_count: usize = smith.value(u4);
    for (tokens[0..token_count], 0..) |*token, index| {
        smith.bytesWeighted(&token_bytes[index], &.{
            .rangeAtMost(u8, 0, 255, 1),
            .rangeAtMost(u8, '1', '8', 5),
            .rangeAtMost(u8, 'a', 'h', 5),
            .rangeAtMost(u8, 'n', 'r', 2),
        });
        const token_length: usize = smith.value(u3) % 6;
        token.* = token_bytes[index][0..token_length];
    }
    var states: [17]chess.position.PositionState = undefined;
    var moves: [16]chess.move.Move = undefined;
    const state_count: usize = smith.value(u5) % (states.len + 1);
    const move_count: usize = smith.value(u5) % (moves.len + 1);
    const result = chess.history.build(
        root_fen,
        tokens[0..token_count],
        states[0..state_count],
        moves[0..move_count],
    );
    if (result) |game| {
        try std.testing.expectEqual(token_count, game.moves.len);
        try std.testing.expectEqual(token_count + 1, game.states.len);
        try std.testing.expect(chess.state.isConsistent(&game.position));
    } else |_| {}
    try std.testing.expect(chess.state.isConsistent(&value));
}

fn fuzzTransitions(_: void, smith: *std.testing.Smith) !void {
    const root_fen = support.roots[smith.value(u3)];
    var root: chess.position.PositionState = .{};
    var value = try chess.fen.parse(root_fen, &root);
    const initial_physical = value.physical;
    const initial_root = root;
    const initial_side = value.side_to_move;
    const initial_ply = value.game_ply;

    var states: [64]chess.position.PositionState = undefined;
    var moves: [64]chess.move.Move = undefined;
    var was_null: [64]bool = @splat(false);
    const requested_plies: usize = smith.value(u6);
    var played: usize = 0;
    var previous_was_null = false;
    while (played < requested_plies) {
        var legal = chess.position.MoveList.init();
        chess.movegen.generate(.all, &value, &legal);
        if (legal.count == 0) break;

        if (!previous_was_null and value.current.checkers == 0 and smith.value(bool)) {
            chess.transition.makeNull(&value, &states[played]);
            was_null[played] = true;
            previous_was_null = true;
        } else {
            const selected = legal.slice()[smith.value(u8) % legal.count];
            moves[played] = selected;
            chess.transition.makeMove(&value, selected, &states[played]);
            was_null[played] = false;
            previous_was_null = false;
        }
        try std.testing.expect(chess.state.isConsistent(&value));
        played += 1;
    }

    while (played != 0) {
        played -= 1;
        if (was_null[played]) {
            chess.transition.unmakeNull(&value);
        } else {
            chess.transition.unmakeMove(&value, moves[played]);
        }
        try std.testing.expect(chess.state.isConsistent(&value));
    }
    try std.testing.expectEqualDeep(initial_physical, value.physical);
    try std.testing.expectEqualDeep(initial_root, root);
    try std.testing.expectEqual(initial_side, value.side_to_move);
    try std.testing.expectEqual(initial_ply, value.game_ply);
    try std.testing.expect(value.current == &root);
}
