//! Independent Step-4.0 search correctness and publication tests.
const std = @import("std");
const manta = @import("manta");

const chess = manta.chess;
const search = manta.search;
const EvalBinding = manta.eval.contract.Binding(manta.eval.hce.Hce, manta.eval.trace.Disabled);

const CountingEvaluator = struct {
    pub const State = struct {
        open_changes: i32 = 0,
        forward_updates: u64 = 0,
        backward_updates: u64 = 0,
    };
    pub const TraceEntry = i32;
    pub const see_values: chess.see.PieceValues = .{
        .pawn = 100,
        .knight = 300,
        .bishop = 300,
        .rook = 500,
        .queen = 900,
        .king = 0,
    };
    pub const backend: manta.eval.contract.Backend = .scalar;

    pub fn refresh(_: *const @This(), state: *State, _: *const chess.position.Position) void {
        state.* = .{};
    }

    pub fn update(
        _: *const @This(),
        state: *State,
        _: *const chess.position.Position,
        change: manta.eval.contract.Update,
    ) void {
        const count: i32 = @intCast(change.delta.slice().len);
        switch (change.direction) {
            .forward => {
                state.open_changes += count;
                state.forward_updates += 1;
            },
            .backward => {
                state.open_changes -= count;
                state.backward_updates += 1;
            },
        }
    }

    pub fn evaluate(
        comptime Sink: type,
        _: *const @This(),
        state: *State,
        _: *const chess.position.Position,
        sink: *Sink,
    ) manta.score.Score {
        sink.emit("open_changes", state.open_changes);
        return manta.score.Score.fromOrdinary(state.open_changes).?;
    }
};

const CountingBinding = manta.eval.contract.Binding(CountingEvaluator, manta.eval.trace.Disabled);

const TrackingHce = struct {
    inner: manta.eval.hce.Hce = .{},

    pub const State = struct {
        inner: manta.eval.hce.Hce.State = .{},
        open_updates: i32 = 0,
        forward_updates: u64 = 0,
        backward_updates: u64 = 0,
    };
    pub const TraceEntry = manta.eval.hce.Hce.TraceEntry;
    pub const see_values = manta.eval.hce.Hce.see_values;
    pub const backend = manta.eval.hce.Hce.backend;

    pub fn refresh(self: *const @This(), state: *State, value: *const chess.position.Position) void {
        state.* = .{};
        self.inner.refresh(&state.inner, value);
    }

    pub fn update(
        self: *const @This(),
        state: *State,
        value: *const chess.position.Position,
        change: manta.eval.contract.Update,
    ) void {
        self.inner.update(&state.inner, value, change);
        switch (change.direction) {
            .forward => {
                state.open_updates += 1;
                state.forward_updates += 1;
            },
            .backward => {
                state.open_updates -= 1;
                state.backward_updates += 1;
            },
        }
    }

    pub fn evaluate(
        comptime Sink: type,
        self: *const @This(),
        state: *State,
        value: *const chess.position.Position,
        sink: *Sink,
    ) manta.score.Score {
        return manta.eval.hce.Hce.evaluate(Sink, &self.inner, &state.inner, value, sink);
    }
};

const TrackingBinding = manta.eval.contract.Binding(TrackingHce, manta.eval.trace.Disabled);

const Harness = struct {
    evaluator: manta.eval.hce.Hce = .{},
    evaluator_state: manta.eval.hce.Hce.State = .{},
    sink: manta.eval.trace.Disabled = .{},
    thread: search.types.ThreadState = search.types.ThreadState.init(),

    fn binding(self: *Harness) EvalBinding {
        return .{
            .evaluator = &self.evaluator,
            .state = &self.evaluator_state,
            .sink = &self.sink,
        };
    }
};

test "terminal roots produce search-owned mate and stalemate evidence" {
    const cases = [_]struct { fen: []const u8, expected: manta.score.Score }{
        .{ .fen = "7k/6Q1/5K2/8/8/8/8/8 b - - 0 1", .expected = manta.score.Score.matedIn(0).? },
        .{ .fen = "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", .expected = .zero },
    };
    for (cases) |case| {
        var root_state: chess.position.PositionState = .{};
        var value = try chess.fen.parse(case.fen, &root_state);
        var harness: Harness = .{};
        var control: search.types.NeverStop = .{};
        const result = search.baseline.run(
            &value,
            harness.binding(),
            .{ .depth = 4 },
            &control,
            &harness.thread,
        );
        try std.testing.expect(result.best_move == null);
        try std.testing.expectEqual(case.expected, result.evidence.value);
        try std.testing.expectEqual(search.types.Provenance.terminal, result.evidence.provenance);
        try std.testing.expectEqual(search.types.Termination.terminal, result.termination);
        try std.testing.expectEqual(@as(u64, 0), result.nodes);
    }
}

test "depth-one search proves mate in one and returns a legal PV" {
    var root_state: chess.position.PositionState = .{};
    var value = try chess.fen.parse("7k/8/5KQ1/8/8/8/8/8 w - - 0 1", &root_state);
    var harness: Harness = .{};
    var control: search.types.NeverStop = .{};
    const result = search.baseline.run(
        &value,
        harness.binding(),
        .{ .depth = 1 },
        &control,
        &harness.thread,
    );
    const completed = result.completed.?;
    try std.testing.expectEqual(@as(?i32, 1), completed.evidence.value.mateDistance());
    try std.testing.expectEqual(search.types.Bound.exact, completed.evidence.bound);
    try std.testing.expectEqual(search.types.Provenance.full_search, completed.evidence.provenance);
    try std.testing.expect(completed.pv.length >= 1);
    try std.testing.expect(chess.movegen.isLegal(&value, completed.pv.slice()[0]));
}

test "dead and rule-fifty roots return neutral evidence with a legal fallback" {
    const cases = [_][]const u8{
        "7k/8/8/8/8/8/8/4K3 w - - 0 1",
        "7k/8/8/8/8/8/4R3/4K3 w - - 100 80",
    };
    for (cases) |fen_text| {
        var root_state: chess.position.PositionState = .{};
        var value = try chess.fen.parse(fen_text, &root_state);
        var harness: Harness = .{};
        var control: search.types.NeverStop = .{};
        const result = search.baseline.run(
            &value,
            harness.binding(),
            .{ .depth = 3 },
            &control,
            &harness.thread,
        );
        try std.testing.expectEqual(manta.score.Score.zero, result.evidence.value);
        try std.testing.expectEqual(search.types.Provenance.terminal, result.evidence.provenance);
        try std.testing.expectEqual(search.types.Termination.root_draw, result.termination);
        try std.testing.expect(chess.movegen.isLegal(&value, result.best_move.?));
        try std.testing.expectEqual(@as(u64, 0), result.nodes);
    }
}

test "threefold root history is consumed as terminal draw evidence" {
    // SAFETY: history.build initializes every state and move slot it exposes.
    var states: [9]chess.position.PositionState = undefined;
    var moves: [8]chess.move.Move = undefined;
    var game = try chess.history.build(
        chess.fen.start_position,
        &.{ "g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8" },
        &states,
        &moves,
    );
    var harness: Harness = .{};
    var control: search.types.NeverStop = .{};
    const result = search.baseline.run(
        &game.position,
        harness.binding(),
        .{ .depth = 3 },
        &control,
        &harness.thread,
    );
    try std.testing.expectEqual(search.types.Termination.root_draw, result.termination);
    try std.testing.expectEqual(manta.score.Score.zero, result.evidence.value);
    try std.testing.expect(chess.movegen.isLegal(&game.position, result.best_move.?));
}

test "repeated depth-three search is deterministic and every PV move is legal" {
    var first_root: chess.position.PositionState = .{};
    var second_root: chess.position.PositionState = .{};
    var first = try chess.fen.parse(chess.fen.start_position, &first_root);
    var second = try chess.fen.parse(chess.fen.start_position, &second_root);
    var first_harness: Harness = .{};
    var second_harness: Harness = .{};
    var first_control: search.types.NeverStop = .{};
    var second_control: search.types.NeverStop = .{};
    const first_result = search.baseline.run(
        &first,
        first_harness.binding(),
        .{ .depth = 3 },
        &first_control,
        &first_harness.thread,
    );
    const second_result = search.baseline.run(
        &second,
        second_harness.binding(),
        .{ .depth = 3 },
        &second_control,
        &second_harness.thread,
    );
    try std.testing.expectEqual(first_result.best_move, second_result.best_move);
    try std.testing.expectEqual(first_result.evidence, second_result.evidence);
    try std.testing.expectEqual(first_result.nodes, second_result.nodes);
    try std.testing.expectEqualSlices(
        chess.move.Move,
        first_result.completed.?.pv.slice(),
        second_result.completed.?.pv.slice(),
    );
    try expectLegalPv(chess.fen.start_position, first_result.completed.?.pv.slice());
}

test "node interruption retains only the last completed iteration and restores root" {
    var baseline_root: chess.position.PositionState = .{};
    var baseline_position = try chess.fen.parse(chess.fen.start_position, &baseline_root);
    var baseline_harness: Harness = .{};
    var baseline_control: search.types.NeverStop = .{};
    const depth_one = search.baseline.run(
        &baseline_position,
        baseline_harness.binding(),
        .{ .depth = 1 },
        &baseline_control,
        &baseline_harness.thread,
    );

    var limited_root: chess.position.PositionState = .{};
    var limited_position = try chess.fen.parse(chess.fen.start_position, &limited_root);
    var before: [chess.fen.max_length]u8 = undefined;
    const before_fen = try chess.fen.write(&limited_position, &before);
    var harness: Harness = .{};
    var control: search.types.NeverStop = .{};
    const limit = depth_one.nodes + 1;
    const result = search.baseline.run(
        &limited_position,
        harness.binding(),
        .{ .depth = 3, .nodes = limit },
        &control,
        &harness.thread,
    );
    var after: [chess.fen.max_length]u8 = undefined;
    const after_fen = try chess.fen.write(&limited_position, &after);

    try std.testing.expectEqual(search.types.Termination.node_limit, result.termination);
    try std.testing.expectEqual(limit, result.nodes);
    try std.testing.expectEqual(@as(u16, 1), result.completed.?.depth);
    try std.testing.expectEqual(result.completed.?.pv.slice()[0], result.best_move.?);
    try std.testing.expectEqualStrings(before_fen, after_fen);
    try std.testing.expect(chess.state.isConsistent(&limited_position));
}

test "immediate external stop returns a legal non-authoritative fallback" {
    const StopNow = struct {
        pub fn shouldStop(_: *@This()) bool {
            return true;
        }
    };
    var root_state: chess.position.PositionState = .{};
    var value = try chess.fen.parse(chess.fen.start_position, &root_state);
    var harness: Harness = .{};
    var control: StopNow = .{};
    const result = search.baseline.run(
        &value,
        harness.binding(),
        .{ .depth = 4 },
        &control,
        &harness.thread,
    );
    try std.testing.expectEqual(search.types.Termination.stopped, result.termination);
    try std.testing.expect(result.completed == null);
    try std.testing.expectEqual(search.types.Provenance.fallback, result.evidence.provenance);
    try std.testing.expectEqual(@as(u64, 0), result.nodes);
    try std.testing.expect(chess.movegen.isLegal(&value, result.best_move.?));
    try std.testing.expect(chess.state.isConsistent(&value));
}

test "a hard time abort retains a legal fallback and typed reason" {
    const TimeNow = struct {
        pub fn shouldStop(_: *@This()) bool {
            return true;
        }
        pub fn terminationReason(_: *const @This()) search.types.Termination {
            return .time_limit;
        }
    };
    var root_state: chess.position.PositionState = .{};
    var value = try chess.fen.parse(chess.fen.start_position, &root_state);
    var harness: Harness = .{};
    var control: TimeNow = .{};
    const result = search.baseline.run(
        &value,
        harness.binding(),
        .{ .depth = 4 },
        &control,
        &harness.thread,
    );
    try std.testing.expectEqual(search.types.Termination.time_limit, result.termination);
    try std.testing.expectEqual(search.types.Provenance.fallback, result.evidence.provenance);
    try std.testing.expect(chess.movegen.isLegal(&value, result.best_move.?));
}

test "aborted recursion balances evaluator updates before publishing" {
    var root_state: chess.position.PositionState = .{};
    var value = try chess.fen.parse(chess.fen.start_position, &root_state);
    var evaluator: CountingEvaluator = .{};
    var evaluator_state: CountingEvaluator.State = .{};
    var sink: manta.eval.trace.Disabled = .{};
    const binding = CountingBinding{
        .evaluator = &evaluator,
        .state = &evaluator_state,
        .sink = &sink,
    };
    var thread = search.types.ThreadState.init();
    var control: search.types.NeverStop = .{};
    const result = search.baseline.run(
        &value,
        binding,
        .{ .depth = 3, .nodes = 7 },
        &control,
        &thread,
    );
    try std.testing.expectEqual(search.types.Termination.node_limit, result.termination);
    try std.testing.expectEqual(@as(i32, 0), evaluator_state.open_changes);
    try std.testing.expect(evaluator_state.forward_updates != 0);
    try std.testing.expectEqual(evaluator_state.forward_updates, evaluator_state.backward_updates);
    try std.testing.expect(chess.state.isConsistent(&value));
}

test "verified null search balances evaluator perspective updates on abort" {
    // Null is a search fiction with an empty piece delta, but changing the
    // side to move still crosses the evaluator's forward/backward seam. Every
    // attempted null and verification path must unwind before publication.
    var root_state: chess.position.PositionState = .{};
    var value = try chess.fen.parse(
        "r2qr1k1/p4ppp/1pn1bn2/2b1p3/4P3/1BN1BN2/PPP2PPP/R2QR1K1 b - - 6 10",
        &root_state,
    );
    var before_buffer: [chess.fen.max_length]u8 = undefined;
    const before = try chess.fen.write(&value, &before_buffer);
    var evaluator: TrackingHce = .{};
    var evaluator_state: TrackingHce.State = .{};
    var sink: manta.eval.trace.Disabled = .{};
    const binding = TrackingBinding{
        .evaluator = &evaluator,
        .state = &evaluator_state,
        .sink = &sink,
    };
    var thread = search.types.ThreadState.init();
    var storage: [1024]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    var heuristics: search.ordering.State = .{};
    var counters: search.diagnostics.Counters = .{};
    const StopOnNull = struct {
        counters: *const search.diagnostics.Counters,

        pub fn shouldStop(self: *@This()) bool {
            return self.counters.null_move_attempts != 0;
        }
    };
    var control = StopOnNull{ .counters = &counters };
    const result = search.baseline.runWithFeatures(
        .{ .null_move = true, .shallow_selectivity = false },
        &value,
        binding,
        .{ .depth = 6 },
        &control,
        &thread,
        &table,
        &heuristics,
        &counters,
    );
    var after_buffer: [chess.fen.max_length]u8 = undefined;
    try std.testing.expectEqual(search.types.Termination.stopped, result.termination);
    try std.testing.expect(counters.null_move_attempts != 0);
    try std.testing.expectEqual(@as(i32, 0), evaluator_state.open_updates);
    try std.testing.expectEqual(evaluator_state.forward_updates, evaluator_state.backward_updates);
    try std.testing.expectEqualStrings(before, try chess.fen.write(&value, &after_buffer));
    try std.testing.expect(chess.state.isConsistent(&value));
}

fn expectLegalPv(fen_text: []const u8, pv: []const chess.move.Move) !void {
    // SAFETY: one state slot is initialized by makeMove before each use.
    var states: [chess.types.max_ply]chess.position.PositionState = undefined;
    var root: chess.position.PositionState = .{};
    var value = try chess.fen.parse(fen_text, &root);
    for (pv, 0..) |chess_move, ply| {
        try std.testing.expect(chess.movegen.isLegal(&value, chess_move));
        chess.transition.makeMove(&value, chess_move, &states[ply]);
    }
}
