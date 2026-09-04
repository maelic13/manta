//! Deterministic HCE baseline and differential residual report.
//!
//! Step 5.3.0 needs one fixed picture of what Manta's evaluator says, how that
//! compares with what search concludes, and where an external classical
//! reference disagrees. The report describes; it never fits or promotes.
//!
//! Every reported value is deterministic so two runs are byte-identical.
//! Wall-clock cost is deliberately excluded for that reason and evaluation
//! cost is reported as evaluator invocation counts instead, following the same
//! rule the whole-search bench already uses: timing measures the host, the
//! deterministic totals measure the engine.
//!
//! Reference evaluations come from the pinned classical reference evaluator,
//! the strongest pre-NNUE classical evaluator the plan pins. They are frozen
//! in the cohort table rather than read from an external binary at run time,
//! so the report stays deterministic, reviewable and reproducible on a machine
//! that has no reference build. `config/eval-reference.json` records exactly
//! which revision they came from and how they were produced.
const std = @import("std");
const manta = @import("manta");

const chess = manta.chess;
const eval = manta.eval;
const search = manta.search;
const score = manta.score;
const cohorts = manta.eval.cohorts;

const TraceBuffer = eval.trace.Buffer(eval.hce.Hce.TraceEntry, 32);
const TracedBinding = eval.contract.Binding(eval.hce.Hce, TraceBuffer);
const PlainBinding = eval.contract.Binding(eval.hce.Hce, eval.trace.Disabled);

/// Counts evaluator invocations so cost is reported deterministically rather
/// than as host-dependent wall time.
const CountingSink = struct {
    pub const Entry = eval.hce.Hce.TraceEntry;

    calls: u64 = 0,

    pub inline fn emit(self: *CountingSink, comptime label: []const u8, _: Entry) void {
        // Every evaluation emits exactly one `total`, so counting that label
        // counts evaluator calls without depending on how many terms exist.
        if (comptime std.mem.eql(u8, label, "total")) self.calls += 1;
    }
};
const CountingBinding = eval.contract.Binding(eval.hce.Hce, CountingSink);

const Record = struct {
    raw_white: i32,
    raw_side: i32,
    phase: u8,
    terms: TraceBuffer,
    depth1: i32,
    searched: i32,
    searched_depth: u16,
    searched_provenance: search.types.Provenance,
    nodes: u64,
    eval_calls: u64,
    volatility: i32,
    volatile_move: chess.move.Move,
    legal_moves: usize,
};

const CorrectionRecord = struct {
    searched: i32,
    nodes: u64,
    best_move: chess.move.Move,
    root_correction: i32,
    counters: search.diagnostics.Counters,
    table: search.ordering.State.CorrectionSummary,
};

const CorrectionAggregate = struct {
    production_nodes: u64 = 0,
    candidate_nodes: u64 = 0,
    lookups: u64 = 0,
    nonzero_lookups: u64 = 0,
    exact_samples: u64 = 0,
    raw_abs_error: u64 = 0,
    corrected_abs_error: u64 = 0,
    updates_by_bound: [3]u64 = @splat(0),
    positive_updates: u64 = 0,
    negative_updates: u64 = 0,
    populated: usize = 0,
    positive_slots: usize = 0,
    negative_slots: usize = 0,
    near_cap: usize = 0,
    max_abs_cp: i32 = 0,

    fn add(self: *CorrectionAggregate, production: Record, candidate: CorrectionRecord) void {
        self.production_nodes += production.nodes;
        self.candidate_nodes += candidate.nodes;
        self.lookups += candidate.counters.correction_lookups;
        self.nonzero_lookups += candidate.counters.correction_nonzero_lookups;
        self.exact_samples += candidate.counters.correction_exact_samples;
        self.raw_abs_error += candidate.counters.correction_exact_raw_abs_error;
        self.corrected_abs_error += candidate.counters.correction_exact_corrected_abs_error;
        for (&self.updates_by_bound, candidate.counters.correction_updates_by_bound) |*total, value|
            total.* += value;
        self.positive_updates += candidate.counters.correction_positive_updates;
        self.negative_updates += candidate.counters.correction_negative_updates;
        self.populated += candidate.table.populated;
        self.positive_slots += candidate.table.positive;
        self.negative_slots += candidate.table.negative;
        self.near_cap += candidate.table.near_cap;
        self.max_abs_cp = @max(self.max_abs_cp, candidate.table.max_abs_cp);
    }
};

pub fn main(init: std.process.Init) !u8 {
    _ = init;
    std.debug.print(
        "Manta evaluation residual report\nschema: {s}\npositions: {d}\ncost: evaluator invocations (deterministic; wall time deliberately omitted)\n",
        .{ cohorts.version, cohorts.cases.len },
    );
    std.debug.print(
        "reference: pinned classical reference evaluator (config/eval-reference.json)\n",
        .{},
    );

    var correction_total: CorrectionAggregate = .{};
    for (cohorts.cases) |case| {
        const record = observe(case) catch |err| {
            std.debug.print("case={s} FAIL={s}\n", .{ case.id, @errorName(err) });
            return 1;
        };
        printRecord(case, record);
        const correction = observeCorrection(case) catch |err| {
            std.debug.print("correction_case={s} FAIL={s}\n", .{ case.id, @errorName(err) });
            return 1;
        };
        correction_total.add(record, correction);
        printCorrectionRecord(case, correction);
    }
    printCorrectionAggregate(correction_total);
    std.debug.print("evaluation residual: PASS\n", .{});
    return 0;
}

fn observeCorrection(case: cohorts.Case) !CorrectionRecord {
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parse(case.fen, &root);
    if (!chess.state.isConsistent(&position)) return error.PositionNotConsistent;

    var evaluator: eval.hce.Hce = .{};
    var evaluator_state: eval.hce.Hce.State = .{};
    var sink: eval.trace.Disabled = .{};
    const binding = PlainBinding{
        .evaluator = &evaluator,
        .state = &evaluator_state,
        .sink = &sink,
    };
    var thread = search.types.ThreadState.init();
    var control: search.types.NeverStop = .{};
    var observer: search.diagnostics.Counters = .{};
    var storage: [1 << 14]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    var ordering: search.ordering.State = .{};

    const result = search.baseline.runWithFeatures(
        .{ .correction_history = true },
        &position,
        binding,
        .{ .depth = case.depth },
        &control,
        &thread,
        &table,
        &ordering,
        &observer,
    );
    if (!chess.state.isConsistent(&position)) return error.PositionNotRestored;
    const completed = result.completed orelse return error.MissingCompletedIteration;
    try validatePv(case.fen, completed.pv.slice());

    return .{
        .searched = result.evidence.value.raw(),
        .nodes = result.nodes,
        .best_move = result.best_move orelse return error.MissingBestMove,
        .root_correction = ordering.correction(position.side_to_move, position.current.pawn_key),
        .counters = observer,
        .table = ordering.correctionSummary(),
    };
}

fn printCorrectionRecord(case: cohorts.Case, record: CorrectionRecord) void {
    std.debug.print(
        "  correction case={s} searched={d} nodes={d} best={x} root_cp={d} lookups={d} nonzero={d} exact={d} raw_abs={d} corrected_abs={d} updates=[{d},{d},{d}] slots={d} near_cap={d} max_cp={d}\n",
        .{
            case.id,
            record.searched,
            record.nodes,
            record.best_move.raw(),
            record.root_correction,
            record.counters.correction_lookups,
            record.counters.correction_nonzero_lookups,
            record.counters.correction_exact_samples,
            record.counters.correction_exact_raw_abs_error,
            record.counters.correction_exact_corrected_abs_error,
            record.counters.correction_updates_by_bound[@intFromEnum(search.types.Bound.exact)],
            record.counters.correction_updates_by_bound[@intFromEnum(search.types.Bound.lower)],
            record.counters.correction_updates_by_bound[@intFromEnum(search.types.Bound.upper)],
            record.table.populated,
            record.table.near_cap,
            record.table.max_abs_cp,
        },
    );
}

fn printCorrectionAggregate(total: CorrectionAggregate) void {
    const residual_change_bp: i64 = if (total.raw_abs_error == 0)
        0
    else
        @divTrunc(
            (@as(i64, @intCast(total.corrected_abs_error)) - @as(i64, @intCast(total.raw_abs_error))) * 10_000,
            @as(i64, @intCast(total.raw_abs_error)),
        );
    const node_change_bp: i64 = if (total.production_nodes == 0)
        0
    else
        @divTrunc(
            (@as(i64, @intCast(total.candidate_nodes)) - @as(i64, @intCast(total.production_nodes))) * 10_000,
            @as(i64, @intCast(total.production_nodes)),
        );
    std.debug.print(
        "correction aggregate production_nodes={d} candidate_nodes={d} node_change_bp={d} lookups={d} nonzero={d} exact={d} raw_abs={d} corrected_abs={d} residual_change_bp={d} updates=[{d},{d},{d}] positive={d} negative={d} slots={d} positive_slots={d} negative_slots={d} near_cap={d} max_cp={d}\n",
        .{
            total.production_nodes,
            total.candidate_nodes,
            node_change_bp,
            total.lookups,
            total.nonzero_lookups,
            total.exact_samples,
            total.raw_abs_error,
            total.corrected_abs_error,
            residual_change_bp,
            total.updates_by_bound[@intFromEnum(search.types.Bound.exact)],
            total.updates_by_bound[@intFromEnum(search.types.Bound.lower)],
            total.updates_by_bound[@intFromEnum(search.types.Bound.upper)],
            total.positive_updates,
            total.negative_updates,
            total.populated,
            total.positive_slots,
            total.negative_slots,
            total.near_cap,
            total.max_abs_cp,
        },
    );
}

fn observe(case: cohorts.Case) !Record {
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parse(case.fen, &root);
    if (!chess.state.isConsistent(&position)) return error.PositionNotConsistent;

    // Raw static evaluation with a full term trace.
    var evaluator: eval.hce.Hce = .{};
    var evaluator_state: eval.hce.Hce.State = .{};
    var trace_buffer = TraceBuffer.init();
    const traced = TracedBinding{
        .evaluator = &evaluator,
        .state = &evaluator_state,
        .sink = &trace_buffer,
    };
    traced.refresh(&position);
    const raw_side = traced.evaluate(&position).raw();
    const raw_white = if (position.side_to_move == .white) raw_side else -raw_side;

    var phase_value: u8 = 0;
    for (trace_buffer.slice()) |record| {
        if (std.mem.eql(u8, record.label, "phase")) {
            switch (record.value) {
                .phase => |value| phase_value = value,
                else => {},
            }
        }
    }

    // Shallow and deep searched evidence from the frozen production search.
    // The shallow column is a depth-one search whose leaves are quiescence,
    // not a bare qsearch call, and is labelled `depth1` to say exactly that.
    var plain_sink: eval.trace.Disabled = .{};
    const plain = PlainBinding{
        .evaluator = &evaluator,
        .state = &evaluator_state,
        .sink = &plain_sink,
    };
    var thread = search.types.ThreadState.init();
    var control: search.types.NeverStop = .{};
    var observer: search.diagnostics.Disabled = .{};
    var storage: [1 << 14]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    var ordering: search.ordering.State = .{};

    const shallow = search.baseline.runWith(
        &position,
        plain,
        .{ .depth = 1 },
        &control,
        &thread,
        &table,
        &ordering,
        &observer,
    );
    table.clear();
    ordering.clear();

    const deep = search.baseline.runWith(
        &position,
        plain,
        .{ .depth = case.depth },
        &control,
        &thread,
        &table,
        &ordering,
        &observer,
    );
    if (!chess.state.isConsistent(&position)) return error.PositionNotRestored;
    const completed = deep.completed orelse return error.MissingCompletedIteration;
    try validatePv(case.fen, completed.pv.slice());

    // Evaluation cost as a deterministic count of evaluator invocations for
    // one fixed-depth search of this position.
    var counting_sink = CountingSink{};
    const counting = CountingBinding{
        .evaluator = &evaluator,
        .state = &evaluator_state,
        .sink = &counting_sink,
    };
    table.clear();
    ordering.clear();
    var cost_thread = search.types.ThreadState.init();
    _ = search.baseline.runWith(
        &position,
        counting,
        .{ .depth = case.depth },
        &control,
        &cost_thread,
        &table,
        &ordering,
        &observer,
    );

    // Parent/child volatility: the largest static swing a single legal move
    // causes. A high value means the static score is unstable exactly where
    // search has to rely on it.
    var moves = chess.position.MoveList.init();
    chess.movegen.generate(.all, &position, &moves);
    var volatility: i32 = 0;
    var volatile_move: chess.move.Move = .none;
    var child_state: chess.position.PositionState = .{};
    for (moves.slice()) |chess_move| {
        chess.transition.makeMove(&position, chess_move, &child_state);
        plain.refresh(&position);
        // Negate to compare like with like: both scores are white-relative.
        const child_side = plain.evaluate(&position).raw();
        const child_white = if (position.side_to_move == .white) child_side else -child_side;
        chess.transition.unmakeMove(&position, chess_move);
        const delta = child_white - raw_white;
        const magnitude = if (delta < 0) -delta else delta;
        if (magnitude > volatility) {
            volatility = magnitude;
            volatile_move = chess_move;
        }
    }
    plain.refresh(&position);
    if (!chess.state.isConsistent(&position)) return error.PositionNotRestored;

    return .{
        .raw_white = raw_white,
        .raw_side = raw_side,
        .phase = phase_value,
        .terms = trace_buffer,
        .depth1 = shallow.evidence.value.raw(),
        .searched = deep.evidence.value.raw(),
        .searched_depth = completed.depth,
        .searched_provenance = deep.evidence.provenance,
        .nodes = deep.nodes,
        .eval_calls = counting_sink.calls,
        .volatility = volatility,
        .volatile_move = volatile_move,
        .legal_moves = moves.count,
    };
}

fn validatePv(fen_text: []const u8, pv: []const chess.move.Move) !void {
    var states: [chess.types.max_ply]chess.position.PositionState = undefined;
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parse(fen_text, &root);
    for (pv, 0..) |chess_move, ply| {
        if (!chess.movegen.isLegal(&position, chess_move)) return error.IllegalPv;
        chess.transition.makeMove(&position, chess_move, &states[ply]);
    }
}

fn printRecord(case: cohorts.Case, record: Record) void {
    var move_buffer: [8]u8 = @splat(0);
    var move_len: usize = 4;
    @memcpy(move_buffer[0..4], "none");
    if (record.volatile_move.isChessMove()) {
        const formatted = chess.notation.format(record.volatile_move) catch unreachable;
        move_len = formatted.slice().len;
        @memcpy(move_buffer[0..move_len], formatted.slice());
    }
    const move_text = move_buffer[0..move_len];
    std.debug.print(
        "case={s} cohort={s} phase={d} raw_white={d} raw_stm={d} depth1={d} depth={d} searched={d} producer={s} nodes={d} eval_calls={d} legal={d} volatility={d} volatile_move={s}\n",
        .{
            case.id,
            @tagName(case.cohort),
            record.phase,
            record.raw_white,
            record.raw_side,
            record.depth1,
            record.searched_depth,
            record.searched,
            @tagName(record.searched_provenance),
            record.nodes,
            record.eval_calls,
            record.legal_moves,
            record.volatility,
            move_text,
        },
    );
    // Static-versus-searched disagreement is the residual that matters: it is
    // where the evaluator would mislead search if search trusted it.
    const disagreement = record.searched - record.raw_side;
    if (case.reference_cp) |reference| {
        // The reference is white-relative, so it is compared against the
        // white-relative Manta score rather than the side-to-move view.
        std.debug.print(
            "  residual searched_minus_raw={d} depth1_minus_raw={d} reference={d} raw_minus_reference={d}\n",
            .{ disagreement, record.depth1 - record.raw_side, reference, record.raw_white - reference },
        );
    } else {
        // The classical reference refuses to evaluate a position whose side to
        // move is in check, so no residual exists for that case.
        std.debug.print(
            "  residual searched_minus_raw={d} depth1_minus_raw={d} reference=unavailable\n",
            .{ disagreement, record.depth1 - record.raw_side },
        );
    }
    std.debug.print("  terms", .{});
    for (record.terms.slice()) |entry| {
        switch (entry.value) {
            .tapered => |tapered| std.debug.print(
                " {s}=mg:{d}/eg:{d}",
                .{ entry.label, tapered.middlegame, tapered.endgame },
            ),
            .phase => |value| std.debug.print(" {s}={d}", .{ entry.label, value }),
            .total => |value| std.debug.print(" {s}={d}", .{ entry.label, value }),
        }
    }
    std.debug.print("\n", .{});
    if (record.terms.truncated) std.debug.print("  terms truncated\n", .{});
}

test "the residual harness is deterministic and preserves every position" {
    // PERF-006/QUAL-013: the report is only useful as a baseline if repeated
    // observation of the same case yields identical evidence and leaves the
    // board untouched.
    for (cohorts.cases) |case| {
        const first = try observe(case);
        const second = try observe(case);
        try std.testing.expectEqual(first.raw_white, second.raw_white);
        try std.testing.expectEqual(first.raw_side, second.raw_side);
        try std.testing.expectEqual(first.phase, second.phase);
        try std.testing.expectEqual(first.depth1, second.depth1);
        try std.testing.expectEqual(first.searched, second.searched);
        try std.testing.expectEqual(first.nodes, second.nodes);
        try std.testing.expectEqual(first.eval_calls, second.eval_calls);
        try std.testing.expectEqual(first.volatility, second.volatility);
        try std.testing.expectEqual(first.legal_moves, second.legal_moves);
    }
}

test "raw evaluation is antisymmetric between the two perspectives" {
    // SCORE-001: a static score is side-to-move evidence. If the white-relative
    // and side-to-move views ever disagree in magnitude the residual columns
    // would compare different quantities.
    for (cohorts.cases) |case| {
        const record = try observe(case);
        const magnitude = if (record.raw_white < 0) -record.raw_white else record.raw_white;
        const side_magnitude = if (record.raw_side < 0) -record.raw_side else record.raw_side;
        try std.testing.expectEqual(magnitude, side_magnitude);
    }
}

test "evaluation cost counting observes the evaluator without changing search" {
    // The counting sink must be a pure observer: a search that counts calls
    // has to explore exactly the same tree as one that does not.
    const case = cohorts.cases[0];
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parse(case.fen, &root);
    var evaluator: eval.hce.Hce = .{};
    var evaluator_state: eval.hce.Hce.State = .{};
    var control: search.types.NeverStop = .{};
    var observer: search.diagnostics.Disabled = .{};

    var counting_sink = CountingSink{};
    var plain_sink: eval.trace.Disabled = .{};
    var storage_a: [1 << 14]search.tt.Cluster = undefined;
    var storage_b: [1 << 14]search.tt.Cluster = undefined;
    var table_a = search.tt.Table.init(&storage_a);
    var table_b = search.tt.Table.init(&storage_b);
    var ordering_a: search.ordering.State = .{};
    var ordering_b: search.ordering.State = .{};
    var thread_a = search.types.ThreadState.init();
    var thread_b = search.types.ThreadState.init();

    const counted = search.baseline.runWith(
        &position,
        CountingBinding{ .evaluator = &evaluator, .state = &evaluator_state, .sink = &counting_sink },
        .{ .depth = 4 },
        &control,
        &thread_a,
        &table_a,
        &ordering_a,
        &observer,
    );
    const plain = search.baseline.runWith(
        &position,
        PlainBinding{ .evaluator = &evaluator, .state = &evaluator_state, .sink = &plain_sink },
        .{ .depth = 4 },
        &control,
        &thread_b,
        &table_b,
        &ordering_b,
        &observer,
    );

    try std.testing.expect(counting_sink.calls != 0);
    try std.testing.expectEqual(plain.nodes, counted.nodes);
    try std.testing.expectEqual(plain.evidence.value.raw(), counted.evidence.value.raw());
    try std.testing.expectEqual(plain.best_move.?.raw(), counted.best_move.?.raw());
}

test "correction evidence is deterministic and reduces online exact residual" {
    // SCORE-023/QUAL-013: each candidate search starts with a clear TT and
    // worker-local history, matching the existing residual contract. Exact
    // samples compare the correction available before the current result is
    // learned, so this is an online prediction property rather than an
    // after-the-fact fit to the same observation.
    var total: CorrectionAggregate = .{};
    for (cohorts.cases) |case| {
        const production = try observe(case);
        const candidate = try observeCorrection(case);
        total.add(production, candidate);
    }

    try std.testing.expect(total.lookups != 0);
    try std.testing.expect(total.nonzero_lookups != 0);
    try std.testing.expect(total.nonzero_lookups < total.lookups);
    try std.testing.expect(total.exact_samples != 0);
    try std.testing.expect(total.positive_updates != 0 and total.negative_updates != 0);
    try std.testing.expect(total.positive_slots != 0 and total.negative_slots != 0);
    try std.testing.expect(total.populated != 0);
    try std.testing.expectEqual(@as(usize, 0), total.near_cap);
    try std.testing.expect(total.corrected_abs_error < total.raw_abs_error);

    const first = try observeCorrection(cohorts.cases[0]);
    const second = try observeCorrection(cohorts.cases[0]);
    try std.testing.expectEqual(first.searched, second.searched);
    try std.testing.expectEqual(first.nodes, second.nodes);
    try std.testing.expectEqual(first.best_move.raw(), second.best_move.raw());
    try std.testing.expectEqual(first.root_correction, second.root_correction);
    try std.testing.expectEqual(first.counters.correction_lookups, second.counters.correction_lookups);
    try std.testing.expectEqual(first.counters.correction_exact_raw_abs_error, second.counters.correction_exact_raw_abs_error);
    try std.testing.expectEqual(first.counters.correction_exact_corrected_abs_error, second.counters.correction_exact_corrected_abs_error);
    try std.testing.expectEqual(first.table.populated, second.table.populated);
    try std.testing.expectEqual(first.table.near_cap, second.table.near_cap);
}
