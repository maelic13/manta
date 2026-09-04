//! Deterministic random-position move-set and SEE properties.
const std = @import("std");
const manta = @import("manta");
const support = @import("support/chess.zig");
const seeds = @import("support/seeds.zig");

const chess = manta.chess;
const walk_plies = 16;

const see_values = chess.see.PieceValues{
    .pawn = 100,
    .knight = 320,
    .bishop = 330,
    .rook = 500,
    .queen = 900,
    .king = 20_000,
};

test "deterministic random positions agree with exhaustive legal move validation" {
    var rng = support.Rng.init(seeds.chess_state_properties);
    var checked_positions: usize = 0;

    for (support.roots) |root_fen| {
        var root: chess.position.PositionState = .{};
        var value = try chess.fen.parse(root_fen, &root);
        try std.testing.expect(chess.state.isConsistent(&value));
        const initial_physical = value.physical;
        const initial_root = root;
        const initial_side = value.side_to_move;
        const initial_ply = value.game_ply;
        var states: [walk_plies]chess.position.PositionState = undefined;
        var moves: [walk_plies]chess.move.Move = undefined;
        var played: usize = 0;

        while (played < walk_plies) {
            try expectExactMoveSet(&value);
            try expectSeeProperties(&value);
            checked_positions += 1;

            var legal = chess.position.MoveList.init();
            chess.movegen.generate(.all, &value, &legal);
            if (legal.count == 0) break;
            const selected = legal.slice()[rng.below(legal.count)];
            moves[played] = selected;
            chess.transition.makeMove(&value, selected, &states[played]);
            try std.testing.expect(chess.state.isConsistent(&value));
            played += 1;
        }

        while (played != 0) {
            played -= 1;
            chess.transition.unmakeMove(&value, moves[played]);
        }
        try std.testing.expectEqualDeep(initial_physical, value.physical);
        try std.testing.expectEqualDeep(initial_root, root);
        try std.testing.expectEqual(initial_side, value.side_to_move);
        try std.testing.expectEqual(initial_ply, value.game_ply);
        try std.testing.expect(value.current == &root);
        try std.testing.expect(chess.state.isConsistent(&value));
    }

    try std.testing.expect(checked_positions >= 100);
}

fn expectExactMoveSet(value: *const chess.position.Position) !void {
    var generated: [std.math.maxInt(u16) + 1]bool = @splat(false);
    var legal = chess.position.MoveList.init();
    chess.movegen.generate(.all, value, &legal);
    for (legal.slice()) |chess_move| {
        try std.testing.expect(chess.movegen.isLegal(value, chess_move));
        try std.testing.expect(!generated[chess_move.raw()]);
        generated[chess_move.raw()] = true;
    }

    var raw: u32 = 0;
    while (raw <= std.math.maxInt(u16)) : (raw += 1) {
        const candidate = chess.move.Move{ .raw_value = @intCast(raw) };
        const independently_legal = chess.movegen.isLegal(value, candidate);
        if (generated[raw] != independently_legal) {
            var buffer: [chess.fen.max_length]u8 = undefined;
            const fen_text = try chess.fen.write(value, &buffer);
            std.debug.print(
                "move-set mismatch at raw {d} in {s}: generated={} independent={}\n",
                .{ raw, fen_text, generated[raw], independently_legal },
            );
            return error.MoveSetMismatch;
        }
    }
}

fn expectSeeProperties(value: *const chess.position.Position) !void {
    var legal = chess.position.MoveList.init();
    chess.movegen.generate(.all, value, &legal);
    for (legal.slice()) |chess_move| {
        try std.testing.expect(chess.see.atLeast(value, chess_move, -40_000, see_values));
        try std.testing.expect(!chess.see.atLeast(value, chess_move, 40_000, see_values));
        if (!chess.movegen.isCapture(value, chess_move) and chess_move.kind() != .promotion) {
            continue;
        }

        var seen_false = false;
        var threshold: i32 = -1_200;
        while (threshold <= 1_200) : (threshold += 100) {
            const accepted = chess.see.atLeast(value, chess_move, threshold, see_values);
            if (accepted and seen_false) return error.NonMonotonicSee;
            if (!accepted) seen_false = true;
        }

        const captured_value = if (chess_move.kind() == .en_passant)
            see_values.pawn
        else blk: {
            const captured = value.physical.pieceOn(chess_move.to());
            break :blk if (captured == .none) 0 else see_values.of(captured.pieceType());
        };
        const moving = value.physical.pieceOn(chess_move.from()).pieceType();
        const guaranteed_floor = captured_value - see_values.of(moving);
        try std.testing.expect(chess.see.atLeast(
            value,
            chess_move,
            guaranteed_floor,
            see_values,
        ));
    }
}
