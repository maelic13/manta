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
            try expectQuietCheckSet(&value);
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

/// ADR-0071 F's generator, checked both ways against an independent oracle.
///
/// Soundness: every generated move is a legal non-tactical quiet that really
/// gives check, verified by making it and reading the resulting check state
/// rather than by re-deriving the attack sets the generator used.
///
/// Completeness: every legal non-tactical quiet that gives check with the
/// moved piece as the sole checker must be generated. The sole-checker
/// condition is what separates a direct check from a discovered one, which
/// the generator deliberately omits; a discovery leaves a checker that is not
/// on the destination square.
fn expectQuietCheckSet(value: *const chess.position.Position) !void {
    var generated = chess.position.MoveList.init();
    chess.movegen.generate(.quiet_checks, value, &generated);

    var quiets = chess.position.MoveList.init();
    chess.movegen.generate(.non_tactical_quiets, value, &quiets);

    for (generated.slice()) |chess_move| {
        try std.testing.expect(chess.movegen.isLegal(value, chess_move));
        try std.testing.expect(!chess.movegen.isCapture(value, chess_move));
        try std.testing.expect(chess_move.kind() != .promotion);
        try std.testing.expect(chess_move.kind() != .castling);
        try std.testing.expect(containsMove(quiets.slice(), chess_move));

        var child_state: chess.position.PositionState = undefined;
        var child = value.*;
        chess.transition.makeMove(&child, chess_move, &child_state);
        try std.testing.expect(child.current.checkers != 0);
        // Direct check: the mover itself is the checker, and it is alone.
        try std.testing.expectEqual(
            @as(u32, 1),
            @popCount(child.current.checkers),
        );
        try std.testing.expectEqual(
            chess_move.to().bit(),
            child.current.checkers,
        );
    }

    for (quiets.slice()) |chess_move| {
        var child_state: chess.position.PositionState = undefined;
        var child = value.*;
        chess.transition.makeMove(&child, chess_move, &child_state);
        const sole_direct_check = child.current.checkers == chess_move.to().bit();
        if (!sole_direct_check) continue;
        // A king move can never be a direct check, and castling is excluded by
        // construction; both are outside the subset by design.
        const mover = value.physical.pieceOn(chess_move.from()).pieceType();
        if (mover == .king or chess_move.kind() == .castling) continue;
        try std.testing.expect(containsMove(generated.slice(), chess_move));
    }
}

fn containsMove(haystack: []const chess.move.Move, needle: chess.move.Move) bool {
    for (haystack) |candidate| {
        if (candidate.raw() == needle.raw()) return true;
    }
    return false;
}

fn expectSeeProperties(value: *const chess.position.Position) !void {
    var legal = chess.position.MoveList.init();
    chess.movegen.generate(.all, value, &legal);
    for (legal.slice()) |chess_move| {
        try std.testing.expect(chess.see.atLeast(value, chess_move, -40_000, see_values));
        try std.testing.expect(!chess.see.atLeast(value, chess_move, 40_000, see_values));
        // Castling keeps the conventional zero value: it moves two pieces and
        // the king is never capturable, so there is no exchange to price. Every
        // other legal move, quiet moves included, is priced by the exchange on
        // its destination and must satisfy the properties below.
        if (chess_move.kind() == .castling) continue;

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
        // Worst case: the mover is taken on its destination and nothing is
        // recaptured. For a quiet move `captured_value` is zero, so this is the
        // floor of minus the mover's value that ADR-0071 F's filter relies on.
        //
        // On the promotion ranks one more loss is possible: the recapturing
        // pawn promotes, so the exchange costs the mover plus the upgrade from
        // a pawn to a queen. That is a property of the exact gain-array path
        // this function already used for those ranks, not of quiet pricing --
        // a capture landing on rank one or eight has always been able to reach
        // it; quiet moves simply arrive there far more often.
        const promotable_rank =
            chess_move.to().rank() == .one or chess_move.to().rank() == .eight;
        const promotion_headroom: i32 =
            if (promotable_rank) see_values.queen - see_values.pawn else 0;
        const guaranteed_floor =
            captured_value - see_values.of(moving) - promotion_headroom;
        try std.testing.expect(chess.see.atLeast(
            value,
            chess_move,
            guaranteed_floor,
            see_values,
        ));
    }
}

test "static exchange prices a quiet move that hangs its mover" {
    // The case that motivated ADR-0071 F's review decision. Black king g8,
    // black pawn h3 attacking g2, black pawn d5 blocking the long diagonal,
    // white queen a2. Qa2-g2 is a legal quiet check onto a square the pawn
    // attacks with no white defender, so the exchange on g2 costs a queen and
    // wins nothing. The oracle is the position, not the implementation: a
    // filter that admits this move admits every spite check.
    var root: chess.position.PositionState = .{};
    var value = try chess.fen.parse("6k1/8/8/3p4/8/7p/Q7/4K3 w - - 0 1", &root);
    const quiet_check = chess.move.Move.normal(.a2, .g2);
    try std.testing.expect(chess.movegen.isLegal(&value, quiet_check));
    try std.testing.expect(!chess.movegen.isCapture(&value, quiet_check));

    try std.testing.expect(!chess.see.atLeast(&value, quiet_check, 0, see_values));
    try std.testing.expect(chess.see.atLeast(&value, quiet_check, -see_values.queen, see_values));
    try std.testing.expect(chess.see.atLeast(&value, quiet_check, -900, see_values));

    // A quiet move to a square the opponent does not attack loses nothing, so
    // the same function must accept it at zero. Qa2-b2 is unattacked.
    const safe_quiet = chess.move.Move.normal(.a2, .b2);
    try std.testing.expect(chess.movegen.isLegal(&value, safe_quiet));
    try std.testing.expect(chess.see.atLeast(&value, safe_quiet, 0, see_values));
}
