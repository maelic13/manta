//! Step-4.3 reproducibility, self-play smoke, and tactical/endgame canaries.
const std = @import("std");
const manta = @import("manta");

const chess = manta.chess;
const search = manta.search;
const EvalBinding = manta.eval.contract.Binding(manta.eval.hce.Hce, manta.eval.trace.Disabled);

const Harness = struct {
    evaluator: manta.eval.hce.Hce = .{},
    evaluator_state: manta.eval.hce.Hce.State = .{},
    sink: manta.eval.trace.Disabled = .{},
    thread: search.types.ThreadState = search.types.ThreadState.init(),

    fn binding(self: *Harness) EvalBinding {
        return .{ .evaluator = &self.evaluator, .state = &self.evaluator_state, .sink = &self.sink };
    }
};

test "fresh-game resets reproduce varied node-limited search records" {
    // Node-limit interruption is deterministic work evidence: a reset must
    // reproduce the same legal publication without inheriting TT or history.
    const limits = [_]u64{ 1, 7, 53, 257 };
    for (limits) |limit| {
        const first = try limitedSearch(limit);
        const second = try limitedSearch(limit);
        try std.testing.expectEqual(first.best_move, second.best_move);
        try std.testing.expectEqual(first.evidence, second.evidence);
        try std.testing.expectEqual(first.nodes, second.nodes);
        try std.testing.expectEqual(first.termination, second.termination);
        try std.testing.expectEqual(limit, first.nodes);
        if (first.completed) |completed| {
            try std.testing.expectEqualSlices(chess.move.Move, completed.pv.slice(), second.completed.?.pv.slice());
        }
    }
}

test "completed root confidence is populated, reset, and partial-work silent" {
    // Root confidence describes only whole legal iterations. A node stop in a
    // later iteration must leave every committed move at the same observation
    // count, and a new search must discard the prior position's evidence.
    var root_state: chess.position.PositionState = .{};
    var position = try chess.fen.parse(chess.fen.start_position, &root_state);
    var harness: Harness = .{};
    var control: search.types.NeverStop = .{};

    const complete = search.baseline.run(
        &position,
        harness.binding(),
        .{ .depth = 3 },
        &control,
        &harness.thread,
    );
    const snapshot = complete.completed.?.root_confidence;
    try std.testing.expectEqual(@as(u16, 20), snapshot.root_move_count);
    try std.testing.expectEqual(@as(u16, 3), snapshot.completed_iterations);
    try std.testing.expect(snapshot.total_effort > 0);
    try std.testing.expect(snapshot.best_effort <= snapshot.total_effort);
    try std.testing.expectEqual(@as(u16, 20), harness.thread.root_confidence.count);
    for (harness.thread.root_confidence.moves[0..harness.thread.root_confidence.count]) |history|
        try std.testing.expectEqual(@as(u16, 3), history.observations);

    const interrupted = search.baseline.run(
        &position,
        harness.binding(),
        .{ .depth = 8, .nodes = 257 },
        &control,
        &harness.thread,
    );
    try std.testing.expectEqual(search.types.Termination.node_limit, interrupted.termination);
    const committed = harness.thread.root_confidence.completed_iterations;
    try std.testing.expect(committed > 0);
    for (harness.thread.root_confidence.moves[0..harness.thread.root_confidence.count]) |history|
        try std.testing.expectEqual(committed, history.observations);
    try std.testing.expectEqual(committed, interrupted.completed.?.root_confidence.completed_iterations);

    const restricted = [_]chess.move.Move{
        try chess.notation.parseLegal(&position, "e2e4"),
        try chess.notation.parseLegal(&position, "d2d4"),
    };
    var observer: search.diagnostics.Disabled = .{};
    const reset = search.baseline.runRestricted(
        &position,
        harness.binding(),
        .{ .depth = 1 },
        &control,
        &harness.thread,
        null,
        null,
        &observer,
        &restricted,
    );
    try std.testing.expectEqual(@as(u16, 2), reset.completed.?.root_confidence.root_move_count);
    try std.testing.expectEqual(@as(u16, 1), harness.thread.root_confidence.completed_iterations);
    try std.testing.expectEqual(@as(u16, 2), harness.thread.root_confidence.count);
}

test "two fresh short self-play games produce the same legal move sequence" {
    // This is a bounded crash/legality/state-restoration smoke, not game or Elo
    // evidence. TT and ordering persist within a game and reset between games.
    const first = try playSmokeGame();
    const second = try playSmokeGame();
    try std.testing.expectEqual(first.count, second.count);
    try std.testing.expectEqualSlices(chess.move.Move, first.slice(), second.slice());
}

test "tactical mate and material canaries retain mechanism-level outcomes" {
    const cases = [_]struct {
        fen: []const u8,
        depth: u16,
        expected_move: ?[]const u8 = null,
        expected_capture: ?chess.types.PieceType = null,
        expected_mate_plies: ?i32 = null,
        expect_positive: bool = false,
    }{
        .{
            .fen = "7k/8/5KQ1/8/8/8/8/8 w - - 0 1",
            .depth = 1,
            .expected_mate_plies = 1,
        },
        .{
            .fen = "4k3/8/8/8/8/8/3q4/3RK3 w - - 0 1",
            .depth = 1,
            // Either the rook or king may take the hanging queen. The
            // mechanism invariant is the winning capture, not which equal
            // recapture the current evaluator orders first.
            .expected_capture = .queen,
        },
        .{
            // WAC.001: the queen move forces the tactical continuation. This
            // is a diagnostic canary, not a solved-count or strength floor.
            .fen = "2rr3k/pp3pp1/1nnqbN1p/3pN3/2pP4/2P3Q1/PPB4P/R4RK1 w - - 0 1",
            .depth = 3,
            .expected_move = "g3g6",
        },
        .{
            .fen = "7k/8/8/8/8/8/4Q3/4K3 w - - 0 1",
            .depth = 2,
            .expect_positive = true,
        },
        .{
            .fen = "k7/8/8/8/8/2B1N3/8/4K3 w - - 0 1",
            .depth = 2,
            .expect_positive = true,
        },
    };

    for (cases) |case| {
        var root_state: chess.position.PositionState = .{};
        var position = try chess.fen.parse(case.fen, &root_state);
        var harness: Harness = .{};
        var control: search.types.NeverStop = .{};
        const result = search.baseline.run(
            &position,
            harness.binding(),
            .{ .depth = case.depth },
            &control,
            &harness.thread,
        );
        try std.testing.expect(result.best_move != null);
        try std.testing.expect(chess.movegen.isLegal(&position, result.best_move.?));
        try std.testing.expect(chess.state.isConsistent(&position));
        if (case.expected_move) |move_text| {
            const expected = try chess.notation.parseLegal(&position, move_text);
            if (result.best_move.?.raw_value != expected.raw_value) {
                const actual = try chess.notation.format(result.best_move.?);
                std.debug.print(
                    "canary fen={s} depth={d} expected={s} actual={s}\n",
                    .{ case.fen, case.depth, move_text, actual.slice() },
                );
                return error.TestExpectedEqual;
            }
        }
        if (case.expected_capture) |piece_type| {
            const target = position.physical.pieceOn(result.best_move.?.to());
            try std.testing.expect(target != .none);
            try std.testing.expectEqual(piece_type, target.pieceType());
        }
        if (case.expected_mate_plies) |plies| {
            try std.testing.expectEqual(@as(?i32, plies), result.evidence.value.mateDistance());
        }
        if (case.expect_positive) try std.testing.expect(result.evidence.value.raw() > 0);
    }
}

test "shallow selectivity family retains tactical and mate canaries" {
    // QUAL-013/QUAL-014: an initial depth-one razoring implementation changed
    // WAC.001 at root depth three, the same forcing-move failure mode already
    // refuted for wider reverse-futility scope (ADR-0027). This freezes that
    // refutation independently of the parked razoring switch's default state
    // so a future re-enable is caught here before any registered gate.
    const cases = [_]struct {
        fen: []const u8,
        depth: u16,
        expected_move: ?[]const u8 = null,
        expected_capture: ?chess.types.PieceType = null,
        expected_mate_plies: ?i32 = null,
        expect_positive: bool = false,
    }{
        .{
            .fen = "7k/8/5KQ1/8/8/8/8/8 w - - 0 1",
            .depth = 1,
            .expected_mate_plies = 1,
        },
        .{
            .fen = "4k3/8/8/8/8/8/3q4/3RK3 w - - 0 1",
            .depth = 1,
            .expected_capture = .queen,
        },
        .{
            .fen = "2rr3k/pp3pp1/1nnqbN1p/3pN3/2pP4/2P3Q1/PPB4P/R4RK1 w - - 0 1",
            .depth = 3,
            .expected_move = "g3g6",
        },
        .{
            .fen = "2rr3k/pp3pp1/1nnqbN1p/3pN3/2pP4/2P3Q1/PPB4P/R4RK1 w - - 0 1",
            .depth = 5,
            .expected_move = "g3g6",
        },
        .{
            .fen = "7k/8/8/8/8/8/4Q3/4K3 w - - 0 1",
            .depth = 2,
            .expect_positive = true,
        },
        .{
            .fen = "k7/8/8/8/8/2B1N3/8/4K3 w - - 0 1",
            .depth = 2,
            .expect_positive = true,
        },
    };

    for (cases) |case| {
        var root_state: chess.position.PositionState = .{};
        var position = try chess.fen.parse(case.fen, &root_state);
        var harness: Harness = .{};
        var control: search.types.NeverStop = .{};
        var storage: [4096]search.tt.Cluster = undefined;
        var table = search.tt.Table.init(&storage);
        var ordering: search.ordering.State = .{};
        var observer: search.diagnostics.Disabled = .{};
        const result = search.baseline.runWithFeatures(
            .{ .shallow_selectivity = true },
            &position,
            harness.binding(),
            .{ .depth = case.depth },
            &control,
            &harness.thread,
            &table,
            &ordering,
            &observer,
        );
        try std.testing.expect(result.best_move != null);
        try std.testing.expect(chess.movegen.isLegal(&position, result.best_move.?));
        try std.testing.expect(chess.state.isConsistent(&position));
        if (case.expected_move) |move_text| {
            const expected = try chess.notation.parseLegal(&position, move_text);
            if (result.best_move.?.raw_value != expected.raw_value) {
                const actual = try chess.notation.format(result.best_move.?);
                std.debug.print(
                    "selectivity canary fen={s} depth={d} expected={s} actual={s}\n",
                    .{ case.fen, case.depth, move_text, actual.slice() },
                );
                return error.TestExpectedEqual;
            }
        }
        if (case.expected_capture) |piece_type| {
            const target = position.physical.pieceOn(result.best_move.?.to());
            try std.testing.expect(target != .none);
            try std.testing.expectEqual(piece_type, target.pieceType());
        }
        if (case.expected_mate_plies) |plies| {
            try std.testing.expectEqual(@as(?i32, plies), result.evidence.value.mateDistance());
        }
        if (case.expect_positive) try std.testing.expect(result.evidence.value.raw() > 0);
    }
}

fn limitedSearch(limit: u64) !search.types.Result {
    var root_state: chess.position.PositionState = .{};
    var position = try chess.fen.parse(chess.fen.start_position, &root_state);
    var before_buffer: [chess.fen.max_length]u8 = undefined;
    const before = try chess.fen.write(&position, &before_buffer);
    var harness: Harness = .{};
    var storage: [64]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    var ordering: search.ordering.State = .{};
    var observer: search.diagnostics.Disabled = .{};
    var control: search.types.NeverStop = .{};
    const result = search.baseline.runWith(
        &position,
        harness.binding(),
        .{ .depth = 5, .nodes = limit },
        &control,
        &harness.thread,
        &table,
        &ordering,
        &observer,
    );
    var after_buffer: [chess.fen.max_length]u8 = undefined;
    try std.testing.expectEqualStrings(before, try chess.fen.write(&position, &after_buffer));
    try std.testing.expect(chess.state.isConsistent(&position));
    try std.testing.expect(chess.movegen.isLegal(&position, result.best_move.?));
    return result;
}

const SmokeGame = struct {
    moves: [16]chess.move.Move = @splat(.none),
    count: u8 = 0,

    fn slice(self: *const SmokeGame) []const chess.move.Move {
        return self.moves[0..self.count];
    }
};

fn playSmokeGame() !SmokeGame {
    var root_state: chess.position.PositionState = .{};
    var position = try chess.fen.parse(chess.fen.start_position, &root_state);
    var game_states: [16]chess.position.PositionState = undefined;
    var harness: Harness = .{};
    var storage: [256]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    var ordering: search.ordering.State = .{};
    var observer: search.diagnostics.Disabled = .{};
    var control: search.types.NeverStop = .{};
    var game: SmokeGame = .{};

    for (0..game.moves.len) |ply| {
        var before_buffer: [chess.fen.max_length]u8 = undefined;
        const before = try chess.fen.write(&position, &before_buffer);
        const result = search.baseline.runWith(
            &position,
            harness.binding(),
            .{ .depth = 4, .nodes = 500 },
            &control,
            &harness.thread,
            &table,
            &ordering,
            &observer,
        );
        var after_buffer: [chess.fen.max_length]u8 = undefined;
        try std.testing.expectEqualStrings(before, try chess.fen.write(&position, &after_buffer));
        const best = result.best_move orelse break;
        try std.testing.expect(chess.movegen.isLegal(&position, best));
        game.moves[ply] = best;
        game.count += 1;
        chess.transition.makeMove(&position, best, &game_states[ply]);
        try std.testing.expect(chess.state.isConsistent(&position));
    }
    return game;
}

test "the coordinated selective core retains the WAC.001 forcing move" {
    // ADR-0071's canary, required of the full core arm. Depth five is anchored
    // to the classical reference, which finds `g3g6` exactly there; the off
    // arm's depth-three answer is a property of the unpruned tree and is not
    // required here.
    //
    // This case is the reason three seeds were amended after the third review:
    // a zero-depth reduced probe, a late-move-count skip that dropped `Qh7#`
    // unmade, and a reverse-futility margin below the evaluator's own swing
    // each hid a mate in two on their own. The mating line is
    // `g3g6 g7f6 g6h7`.
    var root_state: chess.position.PositionState = .{};
    var position = try chess.fen.parse(
        "2rr3k/pp3pp1/1nnqbN1p/3pN3/2pP4/2P3Q1/PPB4P/R4RK1 w - - 0 1",
        &root_state,
    );
    var harness: Harness = .{};
    var control: search.types.NeverStop = .{};
    var storage: [8192]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    var ordering: search.ordering.State = .{};
    var observer: search.diagnostics.Disabled = .{};
    const result = search.baseline.runWithFeatures(
        .{ .selective_core = true },
        &position,
        harness.binding(),
        .{ .depth = 5 },
        &control,
        &harness.thread,
        &table,
        &ordering,
        &observer,
    );
    const expected = try chess.notation.parseLegal(&position, "g3g6");
    try std.testing.expect(result.best_move != null);
    try std.testing.expectEqual(expected.raw_value, result.best_move.?.raw_value);
    try std.testing.expectEqual(@as(?i32, 3), result.evidence.value.mateDistance());
    try std.testing.expect(chess.state.isConsistent(&position));
}
