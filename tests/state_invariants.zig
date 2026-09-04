//! Independent state reconstruction across deterministic legal and null walks.
const std = @import("std");
const builtin = @import("builtin");
const manta = @import("manta");
const support = @import("support/chess.zig");
const seeds = @import("support/seeds.zig");

const chess = manta.chess;
const max_walk_plies = 96;

const Step = union(enum) {
    chess_move: chess.move.Move,
    null_move,
};

const Snapshot = struct {
    physical: chess.position.PhysicalPosition,
    state: chess.position.PositionState,
    state_pointer: *chess.position.PositionState,
    side_to_move: chess.types.Color,
    game_ply: u64,
};

const Coverage = struct {
    positions: usize = 0,
    quiets: usize = 0,
    captures: usize = 0,
    pawn_moves: usize = 0,
    castling: usize = 0,
    en_passant: usize = 0,
    promotions: [4]usize = @splat(0),
    checks: usize = 0,
    irreversible: usize = 0,
    null_moves: usize = 0,
    repetitions: usize = 0,
};

const Minimums = struct {
    quiets: usize,
    captures: usize,
    pawn_moves: usize,
    castling: usize,
    en_passant: usize,
    promotions: usize,
    checks: usize,
    irreversible: usize,
    null_moves: usize,
    repetitions: usize,
};

test "deterministic legal and null walks preserve every position fact" {
    const extended = builtin.mode == .ReleaseFast;
    const target_positions: usize = if (extended) 200_000 else 16_000;
    const walk_plies: usize = if (extended) max_walk_plies else 64;
    const minimums = Minimums{
        .quiets = if (extended) 500 else 100,
        .captures = if (extended) 500 else 100,
        .pawn_moves = if (extended) 500 else 100,
        .castling = if (extended) 32 else 8,
        .en_passant = if (extended) 32 else 8,
        .promotions = if (extended) 32 else 8,
        .checks = if (extended) 100 else 20,
        .irreversible = if (extended) 500 else 100,
        .null_moves = if (extended) 500 else 100,
        .repetitions = 2,
    };

    var coverage: Coverage = .{};
    try runRepetitionScenario(&coverage);

    var walk_index: usize = 0;
    while (coverage.positions < target_positions) : (walk_index += 1) {
        const root_index = walk_index % support.roots.len;
        const seed = walkSeed(walk_index, root_index);
        try runWalk(
            support.roots[root_index],
            seed,
            walk_plies,
            target_positions,
            minimums,
            &coverage,
        );
    }
    try expectCoverage(coverage, target_positions, minimums);
}

fn runWalk(
    root_fen: []const u8,
    seed: u64,
    walk_plies: usize,
    target_positions: usize,
    minimums: Minimums,
    coverage: *Coverage,
) !void {
    var root: chess.position.PositionState = .{};
    var value = try chess.fen.parse(root_fen, &root);
    try expectCoreFacts(&value);

    var rng = support.Rng.init(seed);
    var states: [max_walk_plies]chess.position.PositionState = undefined;
    var snapshots: [max_walk_plies]Snapshot = undefined;
    var steps: [max_walk_plies]Step = undefined;
    var played: usize = 0;
    var last_was_null = false;
    var fen_eligible = true;

    while (played < walk_plies and coverage.positions < target_positions) {
        var legal = chess.position.MoveList.init();
        chess.movegen.generate(.all, &value, &legal);
        if (legal.count == 0) break;

        snapshots[played] = takeSnapshot(&value);
        const use_null = !last_was_null and value.current.checkers == 0 and
            !hasDeficientRareMove(&value, legal.slice(), coverage.*, minimums) and
            rng.below(13) == 0;
        if (use_null) {
            steps[played] = .null_move;
            chess.transition.makeNull(&value, &states[played]);
            expectNullTransition(&value, &states[played], snapshots[played]) catch |err| {
                printFailure(root_fen, seed, played, steps[0 .. played + 1], err);
                return err;
            };
            coverage.null_moves += 1;
            fen_eligible = false;
            last_was_null = true;
        } else {
            const selected = chooseMove(&value, legal.slice(), &rng, coverage.*, minimums);
            steps[played] = .{ .chess_move = selected };
            chess.transition.makeMove(&value, selected, &states[played]);
            expectRealTransition(&value, &states[played], snapshots[played], selected, fen_eligible) catch |err| {
                printFailure(root_fen, seed, played, steps[0 .. played + 1], err);
                return err;
            };
            recordMove(&coverage.*, snapshots[played], &value, selected);
            last_was_null = false;
        }
        coverage.positions += 1;
        played += 1;
    }

    while (played != 0) {
        played -= 1;
        switch (steps[played]) {
            .chess_move => |chess_move| chess.transition.unmakeMove(&value, chess_move),
            .null_move => chess.transition.unmakeNull(&value),
        }
        expectRestored(&value, snapshots[played]) catch |err| {
            printFailure(root_fen, seed, played, steps[0 .. played + 1], err);
            return err;
        };
    }
}

fn runRepetitionScenario(coverage: *Coverage) !void {
    const moves_text = [_][]const u8{
        "g1f3", "g8f6", "f3g1", "f6g8",
        "g1f3", "g8f6", "f3g1", "f6g8",
    };
    var root: chess.position.PositionState = .{};
    var value = try chess.fen.parseStart(&root);
    var states: [moves_text.len]chess.position.PositionState = undefined;
    var snapshots: [moves_text.len]Snapshot = undefined;
    var moves: [moves_text.len]chess.move.Move = undefined;

    for (moves_text, 0..) |text, index| {
        snapshots[index] = takeSnapshot(&value);
        moves[index] = try chess.notation.parseLegal(&value, text);
        chess.transition.makeMove(&value, moves[index], &states[index]);
        try expectRealTransition(&value, &states[index], snapshots[index], moves[index], true);
        recordMove(coverage, snapshots[index], &value, moves[index]);
        coverage.positions += 1;
    }
    try std.testing.expectEqual(@as(u16, 2), independentPriorRepetitions(value.current));
    try std.testing.expect(chess.draw.isThreefold(&value));

    var count = moves.len;
    while (count != 0) {
        count -= 1;
        chess.transition.unmakeMove(&value, moves[count]);
        try expectRestored(&value, snapshots[count]);
    }
}

fn expectRealTransition(
    value: *const chess.position.Position,
    child: *chess.position.PositionState,
    before: Snapshot,
    chess_move: chess.move.Move,
    fen_eligible: bool,
) !void {
    const moving = before.physical.pieceOn(chess_move.from());
    const captured = capturedBefore(before.physical, before.side_to_move, chess_move);

    try std.testing.expect(value.current == child);
    try std.testing.expect(child.previous == before.state_pointer);
    try std.testing.expectEqualDeep(before.state, before.state_pointer.*);
    try std.testing.expectEqual(before.side_to_move.opposite(), value.side_to_move);
    try std.testing.expectEqual(before.game_ply + 1, value.game_ply);
    try std.testing.expectEqual(captured, child.captured_piece);
    try std.testing.expectEqual(
        expectedRights(before.state.castling_rights, chess_move.from(), chess_move.to()),
        child.castling_rights,
    );
    try std.testing.expectEqual(
        if (moving.pieceType() == .pawn or captured != .none)
            @as(u16, 0)
        else
            before.state.rule50 +| 1,
        child.rule50,
    );
    try std.testing.expectEqual(before.state.plies_from_null +| 1, child.plies_from_null);
    try std.testing.expectEqual(independentRepetitionState(child), child.repetition);
    try std.testing.expectEqual(independentPriorRepetitions(child), chess.draw.priorRepetitions(value));
    try std.testing.expectEqual(
        try expectedEnPassant(value, before, chess_move, moving),
        child.ep_square,
    );
    try expectDelta(before.physical, value.physical, child.delta);
    try expectCoreFacts(value);
    if (fen_eligible) try expectFenRoundTrip(value);
}

fn expectNullTransition(
    value: *const chess.position.Position,
    child: *chess.position.PositionState,
    before: Snapshot,
) !void {
    try std.testing.expect(value.current == child);
    try std.testing.expect(child.previous == before.state_pointer);
    try std.testing.expectEqualDeep(before.state, before.state_pointer.*);
    try std.testing.expectEqualDeep(before.physical, value.physical);
    try std.testing.expectEqual(before.side_to_move.opposite(), value.side_to_move);
    try std.testing.expectEqual(before.game_ply, value.game_ply);
    try std.testing.expectEqual(before.state.castling_rights, child.castling_rights);
    try std.testing.expectEqual(before.state.rule50, child.rule50);
    try std.testing.expectEqual(@as(u16, 0), child.plies_from_null);
    try std.testing.expectEqual(@as(i16, 0), child.repetition);
    try std.testing.expectEqual(chess.types.Square.none, child.ep_square);
    try std.testing.expectEqual(chess.types.Piece.none, child.captured_piece);
    try std.testing.expectEqualDeep(chess.position.MoveDelta{}, child.delta);
    try std.testing.expectEqual(@as(chess.types.Bitboard, 0), child.checkers);
    try expectCoreFacts(value);
}

fn expectCoreFacts(value: *const chess.position.Position) !void {
    try std.testing.expect(chess.state.isConsistent(value));
    for ([_]chess.types.Color{ .white, .black }) |color| {
        try std.testing.expectEqual(
            @as(usize, 1),
            @popCount(value.physical.pieces(color, .king)),
        );
    }
}

fn expectFenRoundTrip(value: *const chess.position.Position) !void {
    var buffer: [chess.fen.max_length]u8 = undefined;
    const text = try chess.fen.write(value, &buffer);
    var parsed_state: chess.position.PositionState = .{};
    const parsed = try chess.fen.parse(text, &parsed_state);
    try std.testing.expectEqualDeep(value.physical, parsed.physical);
    try std.testing.expectEqual(value.side_to_move, parsed.side_to_move);
    try std.testing.expectEqual(value.game_ply, parsed.game_ply);
    try std.testing.expectEqual(value.current.castling_rights, parsed_state.castling_rights);
    try std.testing.expectEqual(value.current.ep_square, parsed_state.ep_square);
    try std.testing.expectEqual(value.current.rule50, parsed_state.rule50);
    try std.testing.expectEqual(value.current.key, parsed_state.key);
    try std.testing.expectEqual(value.current.pawn_key, parsed_state.pawn_key);
    try std.testing.expectEqual(value.current.minor_key, parsed_state.minor_key);
    try std.testing.expectEqual(value.current.non_pawn_key, parsed_state.non_pawn_key);
    try std.testing.expectEqual(value.current.checkers, parsed_state.checkers);
    try expectCoreFacts(&parsed);
}

fn expectDelta(
    before: chess.position.PhysicalPosition,
    after: chess.position.PhysicalPosition,
    delta: chess.position.MoveDelta,
) !void {
    var expected_removals: [15][64]u8 = @splat(@splat(0));
    var expected_additions: [15][64]u8 = @splat(@splat(0));
    var actual_removals: [15][64]u8 = @splat(@splat(0));
    var actual_additions: [15][64]u8 = @splat(@splat(0));

    for (before.board, after.board, 0..) |old, new, square| {
        if (old == new) continue;
        if (old != .none) expected_removals[old.index()][square] += 1;
        if (new != .none) expected_additions[new.index()][square] += 1;
    }
    for (delta.slice()) |change| {
        try std.testing.expect(change.piece != .none and change.piece.isValid());
        try std.testing.expect(change.from != .none or change.to != .none);
        if (change.from != .none) actual_removals[change.piece.index()][change.from.index()] += 1;
        if (change.to != .none) actual_additions[change.piece.index()][change.to.index()] += 1;
    }
    try std.testing.expectEqualDeep(expected_removals, actual_removals);
    try std.testing.expectEqualDeep(expected_additions, actual_additions);
}

fn expectedEnPassant(
    value: *const chess.position.Position,
    before: Snapshot,
    chess_move: chess.move.Move,
    moving: chess.types.Piece,
) !chess.types.Square {
    if (chess_move.kind() != .normal or moving.pieceType() != .pawn or
        squareDistance(chess_move.from(), chess_move.to()) != 16)
    {
        return .none;
    }

    const target = chess.types.Square.fromIndex(@intCast(
        (@as(u7, chess_move.from().index()) + @as(u7, chess_move.to().index())) / 2,
    ));
    var probe_state = value.current.*;
    probe_state.ep_square = target;
    var probe = value.*;
    probe.current = &probe_state;
    chess.state.applyDerived(&probe_state, chess.state.derive(&probe));

    const capturer = before.side_to_move.opposite();
    const pawn = chess.types.Piece.make(capturer, .pawn);
    for (probe.physical.board, 0..) |piece, index| {
        if (piece != pawn or index == target.index()) continue;
        const candidate = chess.move.Move.enPassant(
            chess.types.Square.fromIndex(@intCast(index)),
            target,
        );
        if (chess.movegen.isLegal(&probe, candidate)) return target;
    }
    return .none;
}

fn expectedRights(
    rights: chess.types.CastlingRights,
    from: chess.types.Square,
    to: chess.types.Square,
) chess.types.CastlingRights {
    var raw = rights.raw();
    for ([_]chess.types.Square{ from, to }) |square| {
        raw &= switch (square) {
            .e1 => 0b1100,
            .a1 => 0b1101,
            .h1 => 0b1110,
            .e8 => 0b0011,
            .a8 => 0b0111,
            .h8 => 0b1011,
            else => 0b1111,
        };
    }
    return @enumFromInt(raw);
}

/// Recomputes the recorded repetition fact from the raw chain: the nearest
/// prior occurrence of the key inside the reversible post-null window, negated
/// when a further occurrence stands behind it.
fn independentRepetitionState(child: *const chess.position.PositionState) i16 {
    const limit: usize = @min(child.rule50, child.plies_from_null);
    var nearest: i16 = 0;
    var matches: u16 = 0;
    var cursor = child.previous;
    var distance: usize = 1;
    while (cursor != null and distance <= limit) : (distance += 1) {
        if (distance % 2 == 0 and cursor.?.key == child.key) {
            matches +|= 1;
            if (nearest == 0) nearest = @intCast(distance);
        }
        cursor = cursor.?.previous;
    }
    return if (matches >= 2) -nearest else nearest;
}

fn independentPriorRepetitions(child: *const chess.position.PositionState) u16 {
    const limit: usize = @min(child.rule50, child.plies_from_null);
    var matches: u16 = 0;
    var cursor = child.previous;
    var distance: usize = 1;
    while (cursor != null and distance <= limit) : (distance += 1) {
        if (distance % 2 == 0 and cursor.?.key == child.key) matches +|= 1;
        cursor = cursor.?.previous;
    }
    return matches;
}

fn capturedBefore(
    physical: chess.position.PhysicalPosition,
    mover: chess.types.Color,
    chess_move: chess.move.Move,
) chess.types.Piece {
    return switch (chess_move.kind()) {
        .castling => .none,
        .normal, .promotion => physical.pieceOn(chess_move.to()),
        .en_passant => physical.pieceOn(enPassantVictim(chess_move.to(), mover)),
    };
}

fn enPassantVictim(target: chess.types.Square, mover: chess.types.Color) chess.types.Square {
    const offset: i8 = if (mover == .white) -8 else 8;
    return chess.types.Square.fromIndex(@intCast(
        @as(i8, @intCast(target.index())) + offset,
    ));
}

fn takeSnapshot(value: *const chess.position.Position) Snapshot {
    return .{
        .physical = value.physical,
        .state = value.current.*,
        .state_pointer = value.current,
        .side_to_move = value.side_to_move,
        .game_ply = value.game_ply,
    };
}

fn expectRestored(value: *const chess.position.Position, expected: Snapshot) !void {
    try std.testing.expect(value.current == expected.state_pointer);
    try std.testing.expectEqualDeep(expected.physical, value.physical);
    try std.testing.expectEqualDeep(expected.state, value.current.*);
    try std.testing.expectEqual(expected.side_to_move, value.side_to_move);
    try std.testing.expectEqual(expected.game_ply, value.game_ply);
    try expectCoreFacts(value);
}

fn chooseMove(
    value: *const chess.position.Position,
    legal: []const chess.move.Move,
    rng: *support.Rng,
    coverage: Coverage,
    minimums: Minimums,
) chess.move.Move {
    var best_score: u8 = 0;
    var selected = legal[rng.below(legal.len)];
    var ties: usize = 0;
    for (legal) |candidate| {
        const score = movePriority(value, candidate, coverage, minimums);
        if (score > best_score) {
            best_score = score;
            selected = candidate;
            ties = 1;
        } else if (score == best_score and score != 0) {
            ties += 1;
            if (rng.below(ties) == 0) selected = candidate;
        }
    }
    return selected;
}

fn hasDeficientRareMove(
    value: *const chess.position.Position,
    legal: []const chess.move.Move,
    coverage: Coverage,
    minimums: Minimums,
) bool {
    for (legal) |candidate| {
        if (movePriority(value, candidate, coverage, minimums) >= 4) return true;
    }
    return false;
}

fn movePriority(
    value: *const chess.position.Position,
    candidate: chess.move.Move,
    coverage: Coverage,
    minimums: Minimums,
) u8 {
    return switch (candidate.kind()) {
        .en_passant => if (coverage.en_passant < minimums.en_passant) 7 else 0,
        .castling => if (coverage.castling < minimums.castling) 6 else 0,
        .promotion => if (coverage.promotions[promotionIndex(candidate.promotionPiece())] < minimums.promotions) 5 else 0,
        .normal => blk: {
            const moving = value.physical.pieceOn(candidate.from());
            if (moving.pieceType() == .pawn and coverage.pawn_moves < minimums.pawn_moves) break :blk 3;
            if (chess.movegen.isCapture(value, candidate) and coverage.captures < minimums.captures) break :blk 2;
            if (coverage.quiets < minimums.quiets) break :blk 1;
            break :blk 0;
        },
    };
}

fn recordMove(
    coverage: *Coverage,
    before: Snapshot,
    after: *const chess.position.Position,
    chess_move: chess.move.Move,
) void {
    const moving = before.physical.pieceOn(chess_move.from());
    const captured = capturedBefore(before.physical, before.side_to_move, chess_move);
    if (captured == .none) coverage.quiets += 1 else coverage.captures += 1;
    if (moving.pieceType() == .pawn) coverage.pawn_moves += 1;
    if (moving.pieceType() == .pawn or captured != .none) coverage.irreversible += 1;
    switch (chess_move.kind()) {
        .castling => coverage.castling += 1,
        .en_passant => coverage.en_passant += 1,
        .promotion => coverage.promotions[promotionIndex(chess_move.promotionPiece())] += 1,
        .normal => {},
    }
    if (after.current.checkers != 0) coverage.checks += 1;
    if (after.current.repetition != 0) coverage.repetitions += 1;
}

fn promotionIndex(piece_type: chess.types.PieceType) usize {
    return switch (piece_type) {
        .knight => 0,
        .bishop => 1,
        .rook => 2,
        .queen => 3,
        .none, .pawn, .king => unreachable,
    };
}

fn expectCoverage(coverage: Coverage, positions: usize, minimums: Minimums) !void {
    try std.testing.expect(coverage.positions >= positions);
    try std.testing.expect(coverage.quiets >= minimums.quiets);
    try std.testing.expect(coverage.captures >= minimums.captures);
    try std.testing.expect(coverage.pawn_moves >= minimums.pawn_moves);
    try std.testing.expect(coverage.castling >= minimums.castling);
    try std.testing.expect(coverage.en_passant >= minimums.en_passant);
    for (coverage.promotions) |count| try std.testing.expect(count >= minimums.promotions);
    try std.testing.expect(coverage.checks >= minimums.checks);
    try std.testing.expect(coverage.irreversible >= minimums.irreversible);
    try std.testing.expect(coverage.null_moves >= minimums.null_moves);
    try std.testing.expect(coverage.repetitions >= minimums.repetitions);
}

fn walkSeed(walk_index: usize, root_index: usize) u64 {
    const walk: u64 = @intCast(walk_index + 1);
    const root: u64 = @intCast(root_index + 1);
    const seed = seeds.chess_state_properties ^
        (walk *% 0x9E37_79B9_7F4A_7C15) ^
        (root *% 0xD1B5_4A32_D192_ED03);
    return if (seed == 0) 1 else seed;
}

fn squareDistance(a: chess.types.Square, b: chess.types.Square) u7 {
    const first: u7 = a.index();
    const second: u7 = b.index();
    return if (first > second) first - second else second - first;
}

fn printFailure(
    root_fen: []const u8,
    seed: u64,
    ply: usize,
    steps: []const Step,
    err: anyerror,
) void {
    std.debug.print(
        "state invariant failure: {s}; root={s}; seed=0x{x}; ply={d}; line=",
        .{ @errorName(err), root_fen, seed, ply },
    );
    for (steps) |step| switch (step) {
        .null_move => std.debug.print(" null", .{}),
        .chess_move => |chess_move| {
            const text = chess.notation.format(chess_move) catch unreachable;
            std.debug.print(" {s}", .{text.slice()});
        },
    };
    std.debug.print("\n", .{});
}
