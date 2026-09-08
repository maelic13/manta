//! Independent Step-4.1 TT, ordering, and observability properties.
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

test "warm transposition evidence preserves the exact root result" {
    // Exact TT evidence may reduce work but cannot change the position's score
    // or publish a move that is illegal at the current root.
    var storage: [64]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    var heuristics: search.ordering.State = .{};
    var first_counters: search.diagnostics.Counters = .{};
    var second_counters: search.diagnostics.Counters = .{};
    var first_root: chess.position.PositionState = .{};
    var second_root: chess.position.PositionState = .{};
    var first = try chess.fen.parse(chess.fen.start_position, &first_root);
    var second = try chess.fen.parse(chess.fen.start_position, &second_root);
    var first_harness: Harness = .{};
    var second_harness: Harness = .{};
    var first_control: search.types.NeverStop = .{};
    var second_control: search.types.NeverStop = .{};

    const cold = search.baseline.runWith(
        &first,
        first_harness.binding(),
        .{ .depth = 3 },
        &first_control,
        &first_harness.thread,
        &table,
        &heuristics,
        &first_counters,
    );
    const warm = search.baseline.runWith(
        &second,
        second_harness.binding(),
        .{ .depth = 3 },
        &second_control,
        &second_harness.thread,
        &table,
        &heuristics,
        &second_counters,
    );

    try std.testing.expectEqual(cold.evidence.value, warm.evidence.value);
    try std.testing.expect(chess.movegen.isLegal(&second, warm.best_move.?));
    try expectLegalPv(chess.fen.start_position, cold.completed.?.pv.slice());
    try expectLegalPv(chess.fen.start_position, warm.completed.?.pv.slice());
    try std.testing.expect(warm.nodes < cold.nodes);
    try std.testing.expectEqual(search.types.Provenance.tt_exact, warm.evidence.provenance);
    try std.testing.expect(second_counters.tt_usable_by_producer[@intFromEnum(search.types.Provenance.full_search)] != 0);
}

test "TT cutoffs cannot splice a stale sibling continuation into the PV" {
    // This root produced a fastchess `Illegal PV move` warning at depth five:
    // every move before the bad suffix was legal, so checking only bestmove or
    // the first PV move could not detect the violated sequential invariant.
    const fen_text = "r2qkbnr/pbpp1p1p/1pn1p1p1/8/2P1PP2/2NB1N2/PP4PP/R1BQ1RK1 b kq - 3 8";
    var storage: [4096]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    var heuristics: search.ordering.State = .{};
    var observer: search.diagnostics.Disabled = .{};
    var cold_root: chess.position.PositionState = .{};
    var warm_root: chess.position.PositionState = .{};
    var cold_position = try chess.fen.parse(fen_text, &cold_root);
    var warm_position = try chess.fen.parse(fen_text, &warm_root);
    var cold_harness: Harness = .{};
    var warm_harness: Harness = .{};
    var cold_control: search.types.NeverStop = .{};
    var warm_control: search.types.NeverStop = .{};

    const cold = search.baseline.runWithFeatures(
        .{ .null_move = false },
        &cold_position,
        cold_harness.binding(),
        .{ .depth = 5 },
        &cold_control,
        &cold_harness.thread,
        &table,
        &heuristics,
        &observer,
    );
    const warm = search.baseline.runWithFeatures(
        .{ .null_move = false },
        &warm_position,
        warm_harness.binding(),
        .{ .depth = 5 },
        &warm_control,
        &warm_harness.thread,
        &table,
        &heuristics,
        &observer,
    );

    try expectLegalPv(fen_text, cold.completed.?.pv.slice());
    try expectLegalPv(fen_text, warm.completed.?.pv.slice());
}

test "restricted root search cannot consume or publish an unrestricted TT move" {
    // UCI searchmoves changes the root domain: root TT evidence from the full
    // legal set is neither a valid cutoff nor a permitted fallback.
    var storage: [64]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    var heuristics: search.ordering.State = .{};
    var observer: search.diagnostics.Disabled = .{};
    var first_root: chess.position.PositionState = .{};
    var second_root: chess.position.PositionState = .{};
    var first = try chess.fen.parse(chess.fen.start_position, &first_root);
    var second = try chess.fen.parse(chess.fen.start_position, &second_root);
    var first_harness: Harness = .{};
    var second_harness: Harness = .{};
    var first_control: search.types.NeverStop = .{};
    var second_control: search.types.NeverStop = .{};
    _ = search.baseline.runWith(
        &first,
        first_harness.binding(),
        .{ .depth = 3 },
        &first_control,
        &first_harness.thread,
        &table,
        &heuristics,
        &observer,
    );
    const only = try chess.notation.parseLegal(&second, "d2d4");
    const restricted = search.baseline.runRestricted(
        &second,
        second_harness.binding(),
        .{ .depth = 2 },
        &second_control,
        &second_harness.thread,
        &table,
        &heuristics,
        &observer,
        &.{only},
    );
    try std.testing.expectEqual(only, restricted.best_move.?);
    try std.testing.expectEqual(only, restricted.completed.?.pv.slice()[0]);
}

test "an illegal TT move invalidates the hit before it influences search" {
    // TT data is untrusted ordering evidence until current-position legality is
    // established, even when its key and checksum match.
    var baseline_root: chess.position.PositionState = .{};
    var probed_root: chess.position.PositionState = .{};
    var baseline_position = try chess.fen.parse(chess.fen.start_position, &baseline_root);
    var probed_position = try chess.fen.parse(chess.fen.start_position, &probed_root);
    var baseline_harness: Harness = .{};
    var probed_harness: Harness = .{};
    var baseline_control: search.types.NeverStop = .{};
    var probed_control: search.types.NeverStop = .{};
    const baseline = search.baseline.run(
        &baseline_position,
        baseline_harness.binding(),
        .{ .depth = 2 },
        &baseline_control,
        &baseline_harness.thread,
    );

    var storage: [1]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    _ = table.store(
        probed_position.current.key,
        chess.move.Move.normal(.a1, .a2),
        manta.score.Score.fromOrdinary(12_345).?,
        null,
        12,
        .exact,
        .full_search,
        0,
    );
    var heuristics: search.ordering.State = .{};
    var observer: search.diagnostics.Disabled = .{};
    const probed = search.baseline.runWith(
        &probed_position,
        probed_harness.binding(),
        .{ .depth = 2 },
        &probed_control,
        &probed_harness.thread,
        &table,
        &heuristics,
        &observer,
    );
    try std.testing.expectEqual(baseline.evidence.value, probed.evidence.value);
    try std.testing.expect(chess.movegen.isLegal(&probed_position, probed.best_move.?));
}

test "diagnostics enabled and disabled preserve the complete search fingerprint" {
    // Observability is a compile-time consumer of events and has no authority
    // over ordering, bounds, cutoffs, or publication.
    var disabled_storage: [64]search.tt.Cluster = undefined;
    var enabled_storage: [64]search.tt.Cluster = undefined;
    var disabled_table = search.tt.Table.init(&disabled_storage);
    var enabled_table = search.tt.Table.init(&enabled_storage);
    var disabled_ordering: search.ordering.State = .{};
    var enabled_ordering: search.ordering.State = .{};
    var disabled_observer: search.diagnostics.Disabled = .{};
    var enabled_observer: search.diagnostics.Counters = .{};
    var disabled_root: chess.position.PositionState = .{};
    var enabled_root: chess.position.PositionState = .{};
    var disabled_position = try chess.fen.parse(chess.fen.start_position, &disabled_root);
    var enabled_position = try chess.fen.parse(chess.fen.start_position, &enabled_root);
    var disabled_harness: Harness = .{};
    var enabled_harness: Harness = .{};
    var disabled_control: search.types.NeverStop = .{};
    var enabled_control: search.types.NeverStop = .{};

    const disabled = search.baseline.runWith(
        &disabled_position,
        disabled_harness.binding(),
        .{ .depth = 3 },
        &disabled_control,
        &disabled_harness.thread,
        &disabled_table,
        &disabled_ordering,
        &disabled_observer,
    );
    const enabled = search.baseline.runWith(
        &enabled_position,
        enabled_harness.binding(),
        .{ .depth = 3 },
        &enabled_control,
        &enabled_harness.thread,
        &enabled_table,
        &enabled_ordering,
        &enabled_observer,
    );

    try std.testing.expectEqual(disabled.best_move, enabled.best_move);
    try std.testing.expectEqual(disabled.evidence, enabled.evidence);
    try std.testing.expectEqual(disabled.nodes, enabled.nodes);
    try std.testing.expectEqualSlices(
        chess.move.Move,
        disabled.completed.?.pv.slice(),
        enabled.completed.?.pv.slice(),
    );
    try std.testing.expectEqual(enabled.nodes, enabled_observer.main_nodes + enabled_observer.quiescence_nodes);
    try std.testing.expectEqual(@as(u16, 3), enabled_observer.completed_iterations);
    try std.testing.expectEqual(@as(u64, enabled_observer.completed_iterations), enabled_observer.root_searches);
    try std.testing.expectEqual(@as(u64, 0), enabled_observer.aspiration_searches);
    try std.testing.expect(enabled_observer.generated_moves >= enabled_observer.searched_main_moves);
    try std.testing.expect(enabled_observer.tt_stores_by_producer[@intFromEnum(search.types.Provenance.full_search)] != 0);
    try std.testing.expect(enabled_observer.max_nodes_between_stop_checks <= 1);
}

test "aspiration is ablatable and publishes only exact completed root evidence" {
    // SCORE-029/QUAL-014: a narrow root window changes selective search work
    // and may change its score/PV. Each arm must still publish an exact result,
    // a legal PV and a restored root, and retries must not train confidence.
    const cases = [_][]const u8{
        chess.fen.start_position,
        "2rr3k/pp3pp1/1nnqbN1p/3pN3/2pP4/2P3Q1/PPB4P/R4RK1 w KQ g6 0 20",
    };
    var aspiration_searches: u64 = 0;
    for (cases) |fen_text| {
        var enabled_state: chess.position.PositionState = .{};
        var disabled_state: chess.position.PositionState = .{};
        var enabled_position = try chess.fen.parse(fen_text, &enabled_state);
        var disabled_position = try chess.fen.parse(fen_text, &disabled_state);
        var enabled_harness: Harness = .{};
        var disabled_harness: Harness = .{};
        var enabled_storage: [256]search.tt.Cluster = undefined;
        var disabled_storage: [256]search.tt.Cluster = undefined;
        var enabled_table = search.tt.Table.init(&enabled_storage);
        var disabled_table = search.tt.Table.init(&disabled_storage);
        var enabled_ordering: search.ordering.State = .{};
        var disabled_ordering: search.ordering.State = .{};
        var enabled_counters: search.diagnostics.Counters = .{};
        var disabled_counters: search.diagnostics.Counters = .{};
        var enabled_control: search.types.NeverStop = .{};
        var disabled_control: search.types.NeverStop = .{};

        const enabled = search.baseline.runWithFeatures(
            .{ .aspiration = true },
            &enabled_position,
            enabled_harness.binding(),
            .{ .depth = 4 },
            &enabled_control,
            &enabled_harness.thread,
            &enabled_table,
            &enabled_ordering,
            &enabled_counters,
        );
        const disabled = search.baseline.runWithFeatures(
            .{ .aspiration = false },
            &disabled_position,
            disabled_harness.binding(),
            .{ .depth = 4 },
            &disabled_control,
            &disabled_harness.thread,
            &disabled_table,
            &disabled_ordering,
            &disabled_counters,
        );

        try std.testing.expectEqual(search.types.Bound.exact, enabled.completed.?.evidence.bound);
        try std.testing.expectEqual(search.types.Bound.exact, disabled.completed.?.evidence.bound);
        try expectLegalPv(fen_text, enabled.completed.?.pv.slice());
        try expectLegalPv(fen_text, disabled.completed.?.pv.slice());
        try std.testing.expect(chess.state.isConsistent(&enabled_position));
        try std.testing.expect(chess.state.isConsistent(&disabled_position));
        aspiration_searches += enabled_counters.aspiration_searches;
        try std.testing.expectEqual(@as(u64, 0), disabled_counters.aspiration_searches);
        try std.testing.expectEqual(
            enabled_counters.root_searches,
            enabled_counters.completed_iterations +
                enabled_counters.aspiration_fail_lows + enabled_counters.aspiration_fail_highs,
        );
        for (enabled_harness.thread.root_confidence.moves[0..enabled_harness.thread.root_confidence.count]) |history|
            try std.testing.expectEqual(enabled_harness.thread.root_confidence.completed_iterations, history.observations);
    }
    try std.testing.expect(aspiration_searches != 0);
}

test "decisive root evidence is never narrowed by aspiration" {
    // SCORE-004: mate-distance evidence is already decisive and must not be
    // placed inside an ordinary evaluation uncertainty window.
    var root_state: chess.position.PositionState = .{};
    var position = try chess.fen.parse("7k/8/5KQ1/8/8/8/8/8 w - - 0 1", &root_state);
    var harness: Harness = .{};
    var counters: search.diagnostics.Counters = .{};
    var control: search.types.NeverStop = .{};
    const result = search.baseline.runWithFeatures(
        .{ .aspiration = true },
        &position,
        harness.binding(),
        .{ .depth = 3 },
        &control,
        &harness.thread,
        null,
        null,
        &counters,
    );
    try std.testing.expect(result.evidence.value.isMate());
    try std.testing.expectEqual(@as(u64, 0), counters.aspiration_searches);
}

test "verified null move prunes non-pawn positions and excludes pawn-only zugzwang" {
    // Null-move evidence is a lower bound only after a legal-position search
    // verifies the fail-high. Pawn-only endings are excluded because passing
    // can be worse than moving there, violating the null-move observation.
    // A hanging queen gives a compact, stable verified fail-high without
    // making the test's activation depend on a particular fitted middlegame
    // score. The defender still has major-piece material, so this is not a
    // null-move-sensitive pawn ending.
    const rich_fen = "4k3/8/8/8/8/8/3q4/3RK3 w - - 0 1";
    var rich_state: chess.position.PositionState = .{};
    var rich_position = try chess.fen.parse(rich_fen, &rich_state);
    var rich_harness: Harness = .{};
    var rich_storage: [1024]search.tt.Cluster = undefined;
    var rich_table = search.tt.Table.init(&rich_storage);
    var rich_ordering: search.ordering.State = .{};
    var rich_counters: search.diagnostics.Counters = .{};
    var control: search.types.NeverStop = .{};
    const rich = search.baseline.runWithFeatures(
        .{ .null_move = true, .dynamic_lmr = false, .shallow_selectivity = false, .main_selectivity_sync = true },
        &rich_position,
        rich_harness.binding(),
        .{ .depth = 4 },
        &control,
        &rich_harness.thread,
        &rich_table,
        &rich_ordering,
        &rich_counters,
    );
    try std.testing.expectEqual(search.types.Bound.exact, rich.completed.?.evidence.bound);
    try expectLegalPv(rich_fen, rich.completed.?.pv.slice());
    try std.testing.expect(chess.state.isConsistent(&rich_position));
    try std.testing.expect(rich_counters.null_move_attempts != 0);
    try std.testing.expectEqual(rich_counters.null_move_attempts, rich_counters.null_move_dynamic_reductions);
    try std.testing.expect(rich_counters.null_move_max_reduction >= 2);
    try std.testing.expectEqual(rich_counters.null_move_fail_highs, rich_counters.null_move_verifications);
    try std.testing.expect(rich_counters.null_move_cutoffs != 0);
    try std.testing.expect(rich_counters.null_move_cutoffs <= rich_counters.null_move_verifications);
    try std.testing.expect(
        rich_counters.tt_stores_by_producer[@intFromEnum(search.types.Provenance.null_move)] != 0,
    );

    const pawn_fen = "8/pp2k3/8/2p5/2P5/1P2K3/P7/8 w - - 0 1";
    var pawn_state: chess.position.PositionState = .{};
    var pawn_position = try chess.fen.parse(pawn_fen, &pawn_state);
    var pawn_harness: Harness = .{};
    var pawn_counters: search.diagnostics.Counters = .{};
    const pawn = search.baseline.runWithFeatures(
        .{ .null_move = true, .dynamic_lmr = false, .shallow_selectivity = false, .main_selectivity_sync = true },
        &pawn_position,
        pawn_harness.binding(),
        .{ .depth = 6 },
        &control,
        &pawn_harness.thread,
        null,
        null,
        &pawn_counters,
    );
    try std.testing.expectEqual(search.types.Bound.exact, pawn.completed.?.evidence.bound);
    try expectLegalPv(pawn_fen, pawn.completed.?.pv.slice());
    try std.testing.expectEqual(@as(u64, 0), pawn_counters.null_move_attempts);
    try std.testing.expectEqual(@as(u64, 0), pawn_counters.null_move_dynamic_reductions);
}

test "verified null move preserves tactical and mate canaries" {
    // Search selectivity may change work, but these independently reasoned
    // legal outcomes protect forcing capture and mate-distance consumers.
    const cases = [_]struct {
        fen: []const u8,
        depth: u16,
        expect_positive: bool = false,
        mate_plies: ?i32 = null,
    }{
        .{
            .fen = "4k3/8/8/8/8/8/3q4/3RK3 w - - 0 1",
            .depth = 4,
            .expect_positive = true,
        },
        .{
            .fen = "7k/8/5KQ1/8/8/8/8/8 w - - 0 1",
            .depth = 4,
            .mate_plies = 1,
        },
    };
    for (cases) |case| {
        var root_state: chess.position.PositionState = .{};
        var position = try chess.fen.parse(case.fen, &root_state);
        var harness: Harness = .{};
        var counters: search.diagnostics.Counters = .{};
        var control: search.types.NeverStop = .{};
        const result = search.baseline.runWithFeatures(
            .{ .null_move = true, .shallow_selectivity = false },
            &position,
            harness.binding(),
            .{ .depth = case.depth },
            &control,
            &harness.thread,
            null,
            null,
            &counters,
        );
        if (case.expect_positive) try std.testing.expect(result.evidence.value.raw() > 0);
        if (case.mate_plies) |plies|
            try std.testing.expectEqual(@as(?i32, plies), result.evidence.value.mateDistance());
        try expectLegalPv(case.fen, result.completed.?.pv.slice());
        try std.testing.expect(chess.state.isConsistent(&position));
    }
}

test "late quiet reductions are ablatable and preserve root publication contracts" {
    // A reduced fail-low is speculative only. Any alpha-raising probe must be
    // re-searched before it can affect an exact root result, cutoff, or PV.
    const fen_text = "r2qr1k1/p4ppp/1pn1bn2/2b1p3/4P3/1BN1BN2/PPP2PPP/R2QR1K1 b - - 6 10";
    var enabled_state: chess.position.PositionState = .{};
    var disabled_state: chess.position.PositionState = .{};
    var enabled_position = try chess.fen.parse(fen_text, &enabled_state);
    var disabled_position = try chess.fen.parse(fen_text, &disabled_state);
    var enabled_harness: Harness = .{};
    var disabled_harness: Harness = .{};
    var enabled_storage: [1024]search.tt.Cluster = undefined;
    var disabled_storage: [1024]search.tt.Cluster = undefined;
    var enabled_table = search.tt.Table.init(&enabled_storage);
    var disabled_table = search.tt.Table.init(&disabled_storage);
    var enabled_ordering: search.ordering.State = .{};
    var disabled_ordering: search.ordering.State = .{};
    var enabled_counters: search.diagnostics.Counters = .{};
    var disabled_counters: search.diagnostics.Counters = .{};
    var enabled_control: search.types.NeverStop = .{};
    var disabled_control: search.types.NeverStop = .{};

    const enabled = search.baseline.runWithFeatures(
        .{ .lmr = true, .shallow_selectivity = false },
        &enabled_position,
        enabled_harness.binding(),
        .{ .depth = 5 },
        &enabled_control,
        &enabled_harness.thread,
        &enabled_table,
        &enabled_ordering,
        &enabled_counters,
    );
    const disabled = search.baseline.runWithFeatures(
        .{ .lmr = false, .shallow_selectivity = false },
        &disabled_position,
        disabled_harness.binding(),
        .{ .depth = 5 },
        &disabled_control,
        &disabled_harness.thread,
        &disabled_table,
        &disabled_ordering,
        &disabled_counters,
    );

    try std.testing.expectEqual(search.types.Bound.exact, enabled.completed.?.evidence.bound);
    try std.testing.expect(chess.movegen.isLegal(&enabled_position, enabled.best_move.?));
    try expectLegalPv(fen_text, enabled.completed.?.pv.slice());
    try expectLegalPv(fen_text, disabled.completed.?.pv.slice());
    try std.testing.expect(chess.state.isConsistent(&enabled_position));
    try std.testing.expect(chess.state.isConsistent(&disabled_position));
    try std.testing.expect(enabled_counters.lmr_probes != 0);
    try std.testing.expectEqual(
        enabled_counters.lmr_probes,
        enabled_counters.lmr_accepted + enabled_counters.lmr_researches,
    );
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.lmr_probes);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.lmr_researches);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.lmr_accepted);
}

test "qsearch SEE rejects only losing nonchecking captures" {
    // SEE is an eligibility oracle only: check evasions, promotions, and
    // checking captures retain full search authority, while every rejected
    // capture is made and unmade before its checking status is decided.
    const fen_text = chess.fen.start_position;
    var enabled_state: chess.position.PositionState = .{};
    var disabled_state: chess.position.PositionState = .{};
    var enabled_position = try chess.fen.parse(fen_text, &enabled_state);
    var disabled_position = try chess.fen.parse(fen_text, &disabled_state);
    var enabled_harness: Harness = .{};
    var disabled_harness: Harness = .{};
    var enabled_storage: [4096]search.tt.Cluster = undefined;
    var disabled_storage: [4096]search.tt.Cluster = undefined;
    var enabled_table = search.tt.Table.init(&enabled_storage);
    var disabled_table = search.tt.Table.init(&disabled_storage);
    var enabled_ordering: search.ordering.State = .{};
    var disabled_ordering: search.ordering.State = .{};
    var enabled_counters: search.diagnostics.Counters = .{};
    var disabled_counters: search.diagnostics.Counters = .{};
    var enabled_control: search.types.NeverStop = .{};
    var disabled_control: search.types.NeverStop = .{};

    const enabled = search.baseline.runWithFeatures(
        .{ .qsearch_see = true, .shallow_selectivity = false },
        &enabled_position,
        enabled_harness.binding(),
        .{ .depth = 5 },
        &enabled_control,
        &enabled_harness.thread,
        &enabled_table,
        &enabled_ordering,
        &enabled_counters,
    );
    const disabled = search.baseline.runWithFeatures(
        .{ .qsearch_see = false, .shallow_selectivity = false },
        &disabled_position,
        disabled_harness.binding(),
        .{ .depth = 5 },
        &disabled_control,
        &disabled_harness.thread,
        &disabled_table,
        &disabled_ordering,
        &disabled_counters,
    );

    try std.testing.expect(enabled_counters.qsearch_see_prunes != 0);
    try std.testing.expect(enabled_counters.qsearch_see_check_exemptions != 0);
    try std.testing.expectEqual(
        enabled_counters.qsearch_see_candidates,
        enabled_counters.qsearch_see_prunes + enabled_counters.qsearch_see_check_exemptions,
    );
    try std.testing.expectEqual(
        enabled_counters.qsearch_see_prunes,
        enabled_counters.prunes_by_cause[@intFromEnum(search.diagnostics.PruneCause.see)],
    );
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.qsearch_see_candidates);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.prunes_by_cause[@intFromEnum(search.diagnostics.PruneCause.see)]);
    try std.testing.expectEqual(search.types.Bound.exact, enabled.evidence.bound);
    try std.testing.expectEqual(search.types.Bound.exact, disabled.evidence.bound);
    try std.testing.expect(chess.movegen.isLegal(&enabled_position, enabled.best_move.?));
    try std.testing.expect(chess.movegen.isLegal(&disabled_position, disabled.best_move.?));
    try expectLegalPv(fen_text, enabled.completed.?.pv.slice());
    try expectLegalPv(fen_text, disabled.completed.?.pv.slice());
    try std.testing.expect(chess.state.isConsistent(&enabled_position));
    try std.testing.expect(chess.state.isConsistent(&disabled_position));
}

test "frontier reverse futility is ablatable and keeps speculative evidence out of TT" {
    // A high static score at a depth-one zero-window node may omit ordinary
    // move expansion only as speculative lower-bound evidence. The root still
    // publishes an exact legal result, and pawn-only positions never enter the
    // heuristic because zugzwang makes pass-like assumptions unreliable.
    const fen_text = chess.fen.start_position;
    var enabled_state: chess.position.PositionState = .{};
    var disabled_state: chess.position.PositionState = .{};
    var enabled_position = try chess.fen.parse(fen_text, &enabled_state);
    var disabled_position = try chess.fen.parse(fen_text, &disabled_state);
    var enabled_harness: Harness = .{};
    var disabled_harness: Harness = .{};
    var enabled_storage: [4096]search.tt.Cluster = undefined;
    var disabled_storage: [4096]search.tt.Cluster = undefined;
    var enabled_table = search.tt.Table.init(&enabled_storage);
    var disabled_table = search.tt.Table.init(&disabled_storage);
    var enabled_ordering: search.ordering.State = .{};
    var disabled_ordering: search.ordering.State = .{};
    var enabled_counters: search.diagnostics.Counters = .{};
    var disabled_counters: search.diagnostics.Counters = .{};
    var enabled_control: search.types.NeverStop = .{};
    var disabled_control: search.types.NeverStop = .{};

    const enabled = search.baseline.runWithFeatures(
        .{
            .shallow_selectivity = true,
            .reverse_futility = true,
            .quiet_futility = false,
            .late_move_pruning = false,
            .see_pruning = false,
        },
        &enabled_position,
        enabled_harness.binding(),
        .{ .depth = 5 },
        &enabled_control,
        &enabled_harness.thread,
        &enabled_table,
        &enabled_ordering,
        &enabled_counters,
    );
    const disabled = search.baseline.runWithFeatures(
        .{
            .shallow_selectivity = true,
            .reverse_futility = false,
            .quiet_futility = false,
            .late_move_pruning = false,
            .see_pruning = false,
        },
        &disabled_position,
        disabled_harness.binding(),
        .{ .depth = 5 },
        &disabled_control,
        &disabled_harness.thread,
        &disabled_table,
        &disabled_ordering,
        &disabled_counters,
    );

    try std.testing.expect(enabled_counters.reverse_futility_candidates != 0);
    try std.testing.expect(enabled_counters.reverse_futility_cutoffs != 0);
    try std.testing.expectEqual(
        enabled_counters.reverse_futility_cutoffs,
        enabled_counters.prunes_by_cause[@intFromEnum(search.diagnostics.PruneCause.reverse_futility)],
    );
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.reverse_futility_candidates);
    try std.testing.expectEqual(
        @as(u64, 0),
        enabled_counters.tt_stores_by_producer[@intFromEnum(search.types.Provenance.speculative_cutoff)],
    );
    try std.testing.expectEqual(search.types.Bound.exact, enabled.evidence.bound);
    try std.testing.expectEqual(search.types.Bound.exact, disabled.evidence.bound);
    try std.testing.expect(chess.movegen.isLegal(&enabled_position, enabled.best_move.?));
    try std.testing.expect(chess.movegen.isLegal(&disabled_position, disabled.best_move.?));
    try expectLegalPv(fen_text, enabled.completed.?.pv.slice());
    try expectLegalPv(fen_text, disabled.completed.?.pv.slice());
    try std.testing.expect(chess.state.isConsistent(&enabled_position));
    try std.testing.expect(chess.state.isConsistent(&disabled_position));

    var pawn_state: chess.position.PositionState = .{};
    var pawn_position = try chess.fen.parse(
        "8/pp2k3/8/2p5/2P5/1P2K3/P7/8 w - - 0 1",
        &pawn_state,
    );
    var pawn_harness: Harness = .{};
    var pawn_counters: search.diagnostics.Counters = .{};
    var pawn_control: search.types.NeverStop = .{};
    _ = search.baseline.runWithFeatures(
        .{
            .shallow_selectivity = true,
            .reverse_futility = true,
            .quiet_futility = false,
            .late_move_pruning = false,
            .see_pruning = false,
        },
        &pawn_position,
        pawn_harness.binding(),
        .{ .depth = 4 },
        &pawn_control,
        &pawn_harness.thread,
        null,
        null,
        &pawn_counters,
    );
    try std.testing.expectEqual(@as(u64, 0), pawn_counters.reverse_futility_candidates);
    try std.testing.expect(chess.state.isConsistent(&pawn_position));
}

test "shallow selectivity family is ablatable and preserves legal root publication" {
    // Step-5.1.4.3: quiet futility, late-move pruning and main-search SEE
    // pruning share one static/improving evidence model and never manufacture
    // TT, PV or terminal authority; disabling the family restores MAN-S10.
    const fen_text = "r2qr1k1/p4ppp/1pn1bn2/2b1p3/4P3/1BN1BN2/PPP2PPP/R2QR1K1 b - - 6 10";
    var enabled_state: chess.position.PositionState = .{};
    var disabled_state: chess.position.PositionState = .{};
    var enabled_position = try chess.fen.parse(fen_text, &enabled_state);
    var disabled_position = try chess.fen.parse(fen_text, &disabled_state);
    var enabled_harness: Harness = .{};
    var disabled_harness: Harness = .{};
    var enabled_storage: [4096]search.tt.Cluster = undefined;
    var disabled_storage: [4096]search.tt.Cluster = undefined;
    var enabled_table = search.tt.Table.init(&enabled_storage);
    var disabled_table = search.tt.Table.init(&disabled_storage);
    var enabled_ordering: search.ordering.State = .{};
    var disabled_ordering: search.ordering.State = .{};
    var enabled_counters: search.diagnostics.Counters = .{};
    var disabled_counters: search.diagnostics.Counters = .{};
    var enabled_control: search.types.NeverStop = .{};
    var disabled_control: search.types.NeverStop = .{};

    const enabled = search.baseline.runWithFeatures(
        .{ .shallow_selectivity = true, .main_selectivity_sync = true },
        &enabled_position,
        enabled_harness.binding(),
        .{ .depth = 6 },
        &enabled_control,
        &enabled_harness.thread,
        &enabled_table,
        &enabled_ordering,
        &enabled_counters,
    );
    const disabled = search.baseline.runWithFeatures(
        .{ .shallow_selectivity = false },
        &disabled_position,
        disabled_harness.binding(),
        .{ .depth = 6 },
        &disabled_control,
        &disabled_harness.thread,
        &disabled_table,
        &disabled_ordering,
        &disabled_counters,
    );

    try std.testing.expect(enabled_counters.quiet_futility_candidates != 0);
    try std.testing.expect(enabled_counters.late_move_pruning_candidates != 0);
    try std.testing.expect(enabled_counters.main_see_pruning_candidates != 0);
    try std.testing.expect(enabled_counters.main_see_pruning_prunes != 0);
    try std.testing.expect(
        enabled_counters.selectivity_history_positive +
            enabled_counters.selectivity_history_negative +
            enabled_counters.selectivity_history_neutral != 0,
    );
    try std.testing.expect(enabled_counters.history_pruning_protections != 0);
    try std.testing.expect(enabled_counters.capture_futility_candidates != 0);
    try std.testing.expect(enabled_counters.reverse_futility_candidates != 0);
    try std.testing.expect(enabled_counters.reverse_futility_cutoffs != 0);
    try std.testing.expect(enabled_counters.prunes_by_cause[@intFromEnum(search.diagnostics.PruneCause.futility)] != 0);
    try std.testing.expect(enabled_counters.prunes_by_cause[@intFromEnum(search.diagnostics.PruneCause.late_move)] != 0);
    // Razoring is a parked component: the default family never triggers it.
    try std.testing.expectEqual(@as(u64, 0), enabled_counters.razoring_candidates);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.quiet_futility_candidates);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.late_move_pruning_candidates);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.main_see_pruning_candidates);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.selectivity_history_positive);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.selectivity_history_negative);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.selectivity_history_neutral);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.capture_futility_candidates);
    try std.testing.expectEqual(
        @as(u64, 0),
        enabled_counters.tt_stores_by_producer[@intFromEnum(search.types.Provenance.speculative_cutoff)],
    );
    try std.testing.expectEqual(search.types.Bound.exact, enabled.evidence.bound);
    try std.testing.expectEqual(search.types.Bound.exact, disabled.evidence.bound);
    try std.testing.expect(chess.movegen.isLegal(&enabled_position, enabled.best_move.?));
    try std.testing.expect(chess.movegen.isLegal(&disabled_position, disabled.best_move.?));
    try expectLegalPv(fen_text, enabled.completed.?.pv.slice());
    try expectLegalPv(fen_text, disabled.completed.?.pv.slice());
    try std.testing.expect(chess.state.isConsistent(&enabled_position));
    try std.testing.expect(chess.state.isConsistent(&disabled_position));

    var pawn_state: chess.position.PositionState = .{};
    var pawn_position = try chess.fen.parse(
        "8/pp2k3/8/2p5/2P5/1P2K3/P7/8 w - - 0 1",
        &pawn_state,
    );
    var pawn_harness: Harness = .{};
    var pawn_counters: search.diagnostics.Counters = .{};
    var pawn_control: search.types.NeverStop = .{};
    const pawn_result = search.baseline.runWithFeatures(
        .{ .shallow_selectivity = true },
        &pawn_position,
        pawn_harness.binding(),
        .{ .depth = 6 },
        &pawn_control,
        &pawn_harness.thread,
        null,
        null,
        &pawn_counters,
    );
    // Zugzwang-sensitive pawn-only material is the shared guard every
    // consumer in the family respects: none may treat a quiet move as
    // speculatively futile when a single tempo can reverse the position.
    try std.testing.expectEqual(@as(u64, 0), pawn_counters.quiet_futility_candidates);
    try std.testing.expectEqual(@as(u64, 0), pawn_counters.late_move_pruning_candidates);
    try std.testing.expectEqual(@as(u64, 0), pawn_counters.selectivity_history_positive);
    try std.testing.expectEqual(@as(u64, 0), pawn_counters.selectivity_history_negative);
    try std.testing.expectEqual(@as(u64, 0), pawn_counters.capture_futility_candidates);
    try std.testing.expect(chess.movegen.isLegal(&pawn_position, pawn_result.best_move.?));
    try std.testing.expect(chess.state.isConsistent(&pawn_position));
}

test "search context is behavior-neutral and accounts for every completed node" {
    // The Step-5.1.4.1 context is descriptive infrastructure: an independently
    // disabled search must preserve the complete root result, PV and node tree.
    const fen_text = "r2qr1k1/p4ppp/1pn1bn2/2b1p3/4P3/1BN1BN2/PPP2PPP/R2QR1K1 b - - 6 10";
    var enabled_state: chess.position.PositionState = .{};
    var disabled_state: chess.position.PositionState = .{};
    var enabled_position = try chess.fen.parse(fen_text, &enabled_state);
    var disabled_position = try chess.fen.parse(fen_text, &disabled_state);
    var enabled_harness: Harness = .{};
    var disabled_harness: Harness = .{};
    var enabled_storage: [4096]search.tt.Cluster = undefined;
    var disabled_storage: [4096]search.tt.Cluster = undefined;
    var enabled_table = search.tt.Table.init(&enabled_storage);
    var disabled_table = search.tt.Table.init(&disabled_storage);
    var enabled_ordering: search.ordering.State = .{};
    var disabled_ordering: search.ordering.State = .{};
    var enabled_counters: search.diagnostics.Counters = .{};
    var disabled_counters: search.diagnostics.Counters = .{};
    var enabled_control: search.types.NeverStop = .{};
    var disabled_control: search.types.NeverStop = .{};

    const enabled = search.baseline.runWithFeatures(
        .{
            .search_context = true,
            .depth_authority = false,
            .shallow_selectivity = false,
            .contextual_history = false,
        },
        &enabled_position,
        enabled_harness.binding(),
        .{ .depth = 5 },
        &enabled_control,
        &enabled_harness.thread,
        &enabled_table,
        &enabled_ordering,
        &enabled_counters,
    );
    const disabled = search.baseline.runWithFeatures(
        .{
            .search_context = false,
            .depth_authority = false,
            .shallow_selectivity = false,
            .contextual_history = false,
        },
        &disabled_position,
        disabled_harness.binding(),
        .{ .depth = 5 },
        &disabled_control,
        &disabled_harness.thread,
        &disabled_table,
        &disabled_ordering,
        &disabled_counters,
    );

    try std.testing.expectEqual(enabled.best_move.?.raw(), disabled.best_move.?.raw());
    try std.testing.expectEqual(enabled.evidence, disabled.evidence);
    try std.testing.expectEqual(enabled.nodes, disabled.nodes);
    try std.testing.expectEqual(enabled.selective_depth, disabled.selective_depth);
    try std.testing.expectEqual(enabled.completed.?.depth, disabled.completed.?.depth);
    try std.testing.expectEqual(enabled.completed.?.nodes, disabled.completed.?.nodes);
    try std.testing.expectEqualSlices(
        chess.move.Move,
        enabled.completed.?.pv.slice(),
        disabled.completed.?.pv.slice(),
    );
    try expectLegalPv(fen_text, enabled.completed.?.pv.slice());
    try std.testing.expect(chess.state.isConsistent(&enabled_position));
    try std.testing.expect(chess.state.isConsistent(&disabled_position));

    try std.testing.expectEqual(enabled.nodes, enabled_counters.context_nodes);
    try std.testing.expectEqual(enabled.nodes, enabled_counters.outcomes);
    try std.testing.expectEqual(
        enabled_counters.context_nodes,
        sumCounts(enabled_counters.context_by_route),
    );
    try std.testing.expectEqual(
        enabled_counters.context_nodes,
        sumCounts(enabled_counters.context_by_arrival),
    );
    try std.testing.expectEqual(
        enabled_counters.outcomes,
        sumCounts(enabled_counters.outcomes_by_disposition),
    );
    try std.testing.expectEqual(
        enabled_counters.outcomes,
        sumCounts(enabled_counters.outcomes_by_producer),
    );
    try std.testing.expectEqual(
        enabled_counters.quiescence_nodes,
        enabled_counters.context_by_route[@intFromEnum(search.types.EntryRoute.quiescence)],
    );
    try std.testing.expectEqual(
        enabled_counters.lmr_probes,
        enabled_counters.context_by_route[@intFromEnum(search.types.EntryRoute.reduced_probe)],
    );
    try std.testing.expectEqual(@as(u64, 0), enabled_counters.extended_depth_intents);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.context_nodes);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.outcomes);
}

test "check extension is independently ablatable and preserves legal evasion publication" {
    // A checked root must search legal evasions one ply farther when the
    // component is enabled; disabling only this producer must leave the rest
    // of the depth-authority family available without leaking board state.
    const fen_text = "4k3/8/8/8/8/8/4R3/4K3 b - - 0 1";
    var enabled_root: chess.position.PositionState = .{};
    var disabled_root: chess.position.PositionState = .{};
    var enabled_position = try chess.fen.parse(fen_text, &enabled_root);
    var disabled_position = try chess.fen.parse(fen_text, &disabled_root);
    var enabled_harness: Harness = .{};
    var disabled_harness: Harness = .{};
    var enabled_counters: search.diagnostics.Counters = .{};
    var disabled_counters: search.diagnostics.Counters = .{};
    var enabled_control: search.types.NeverStop = .{};
    var disabled_control: search.types.NeverStop = .{};

    const enabled = search.baseline.runWithFeatures(
        .{ .shallow_selectivity = false },
        &enabled_position,
        enabled_harness.binding(),
        .{ .depth = 2 },
        &enabled_control,
        &enabled_harness.thread,
        null,
        null,
        &enabled_counters,
    );
    const disabled = search.baseline.runWithFeatures(
        .{ .check_extension = false, .shallow_selectivity = false },
        &disabled_position,
        disabled_harness.binding(),
        .{ .depth = 2 },
        &disabled_control,
        &disabled_harness.thread,
        null,
        null,
        &disabled_counters,
    );

    try std.testing.expect(enabled_counters.extensions_by_cause[@intFromEnum(search.diagnostics.ExtensionCause.check)] != 0);
    try std.testing.expectEqual(
        @as(u64, 0),
        disabled_counters.extensions_by_cause[@intFromEnum(search.diagnostics.ExtensionCause.check)],
    );
    try std.testing.expectEqual(@as(u16, 2), enabled.completed.?.depth);
    try std.testing.expectEqual(@as(u16, 2), disabled.completed.?.depth);
    try expectLegalPv(fen_text, enabled.completed.?.pv.slice());
    try expectLegalPv(fen_text, disabled.completed.?.pv.slice());
    try std.testing.expect(chess.state.isConsistent(&enabled_position));
    try std.testing.expect(chess.state.isConsistent(&disabled_position));
}

test "MAN-S31 preserves root extension and removes only interior check increments" {
    // The checked root is entered once per completed iteration. With the
    // interior producer disabled, those are the only check-extension events.
    // A non-checked mating root exercises checked children but must emit none.
    const cases = [_]struct { fen: []const u8, root_checked: bool }{
        .{ .fen = "4k3/8/8/8/8/8/4R3/4K3 b - - 0 1", .root_checked = true },
        .{ .fen = "7k/8/5KQ1/8/8/8/8/8 w - - 0 1", .root_checked = false },
    };
    for (cases) |case| {
        var root: chess.position.PositionState = .{};
        var position = try chess.fen.parse(case.fen, &root);
        const original_key = position.current.key;
        var harness: Harness = .{};
        var counters: search.diagnostics.Counters = .{};
        var control: search.types.NeverStop = .{};
        const result = search.baseline.runWithFeatures(
            .{ .nonroot_check_extension = false },
            &position,
            harness.binding(),
            .{ .depth = 2 },
            &control,
            &harness.thread,
            null,
            null,
            &counters,
        );
        try std.testing.expectEqual(@as(u16, 2), result.completed.?.depth);
        try std.testing.expectEqual(@as(u64, if (case.root_checked) 2 else 0), counters.extensions_by_cause[@intFromEnum(search.diagnostics.ExtensionCause.check)]);
        try std.testing.expect(counters.context_in_check != 0);
        if (!case.root_checked)
            try std.testing.expectEqual(@as(?i32, 1), result.evidence.value.mateDistance());
        try expectLegalPv(case.fen, result.completed.?.pv.slice());
        try std.testing.expect(chess.state.isConsistent(&position));
        try std.testing.expectEqual(original_key, position.current.key);
    }
}

test "MAN-S31 preserves terminal rules and special-move forcing outcomes" {
    // Independent chess oracles: checkmate/stalemate, a free queen capture,
    // and legal special moves at a restricted root. Both arms must restore
    // the full root and publish a sequentially legal PV; scores need not match.
    const cases = [_]struct {
        fen: []const u8,
        only: ?[]const u8 = null,
        terminal: ?i32 = null,
        positive: bool = false,
    }{
        .{ .fen = "7k/6Q1/5K2/8/8/8/8/8 b - - 100 1", .terminal = -32000 },
        .{ .fen = "7k/5K2/6Q1/8/8/8/8/8 b - - 0 1", .terminal = 0 },
        .{ .fen = "4k3/8/8/8/8/8/3q4/3RK3 w - - 0 1", .positive = true },
        .{ .fen = "4k3/P7/8/8/8/8/8/4K3 w - - 0 1", .only = "a7a8q" },
        .{ .fen = "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", .only = "e5d6" },
        .{ .fen = "4k3/8/8/8/8/8/8/4K2R w K - 0 1", .only = "e1g1" },
    };
    inline for (.{ true, false }) |nonroot_extension| {
        for (cases) |case| {
            var root: chess.position.PositionState = .{};
            var position = try chess.fen.parse(case.fen, &root);
            const original = root;
            var harness: Harness = .{};
            var counters: search.diagnostics.Counters = .{};
            var control: search.types.NeverStop = .{};
            const only = if (case.only) |text| try chess.notation.parseLegal(&position, text) else chess.move.Move.none;
            const result = search.baseline.runRestrictedWithFeatures(
                .{ .nonroot_check_extension = nonroot_extension },
                &position,
                harness.binding(),
                .{ .depth = 3 },
                &control,
                &harness.thread,
                null,
                null,
                &counters,
                if (case.only != null) &.{only} else null,
            );
            if (case.terminal) |expected| {
                try std.testing.expectEqual(expected, result.evidence.value.raw());
                try std.testing.expectEqual(search.types.Provenance.terminal, result.evidence.provenance);
                try std.testing.expectEqual(@as(?chess.move.Move, null), result.best_move);
            } else {
                if (case.positive) try std.testing.expect(result.evidence.value.raw() > 0);
                if (case.only != null) try std.testing.expectEqual(only, result.best_move.?);
                try expectLegalPv(case.fen, result.completed.?.pv.slice());
            }
            try std.testing.expectEqualDeep(original, root);
            try std.testing.expect(chess.state.isConsistent(&position));
        }
    }
}

test "IIR reduces only a non-root PV node without TT move authority" {
    // With no table, the first child of the depth-six restricted root is a
    // non-root depth-five PV node lacking a legal TT move. That is precisely
    // the confidence gap IIR represents; the root iteration itself must still
    // complete at the requested depth.
    const fen_text = "8/8/p1p5/1p5p/1P5P/P1P5/8/K1k5 w - - 0 1";
    var enabled_root: chess.position.PositionState = .{};
    var disabled_root: chess.position.PositionState = .{};
    var enabled_position = try chess.fen.parse(fen_text, &enabled_root);
    var disabled_position = try chess.fen.parse(fen_text, &disabled_root);
    const only_enabled = try chess.notation.parseLegal(&enabled_position, "a1a2");
    const only_disabled = try chess.notation.parseLegal(&disabled_position, "a1a2");
    var enabled_harness: Harness = .{};
    var disabled_harness: Harness = .{};
    var enabled_counters: search.diagnostics.Counters = .{};
    var disabled_counters: search.diagnostics.Counters = .{};
    var enabled_control: search.types.NeverStop = .{};
    var disabled_control: search.types.NeverStop = .{};

    const enabled = search.baseline.runRestrictedWithFeatures(
        .{ .shallow_selectivity = false },
        &enabled_position,
        enabled_harness.binding(),
        .{ .depth = 6 },
        &enabled_control,
        &enabled_harness.thread,
        null,
        null,
        &enabled_counters,
        &.{only_enabled},
    );
    const disabled = search.baseline.runRestrictedWithFeatures(
        .{ .internal_iterative_reduction = false, .shallow_selectivity = false },
        &disabled_position,
        disabled_harness.binding(),
        .{ .depth = 6 },
        &disabled_control,
        &disabled_harness.thread,
        null,
        null,
        &disabled_counters,
        &.{only_disabled},
    );

    try std.testing.expect(enabled_counters.internal_iterative_reductions != 0);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.internal_iterative_reductions);
    try std.testing.expectEqual(@as(u16, 6), enabled.completed.?.depth);
    try std.testing.expectEqual(@as(u16, 6), disabled.completed.?.depth);
    try expectLegalPv(fen_text, enabled.completed.?.pv.slice());
    try expectLegalPv(fen_text, disabled.completed.?.pv.slice());
    try std.testing.expect(chess.state.isConsistent(&enabled_position));
    try std.testing.expect(chess.state.isConsistent(&disabled_position));
}

test "singular verification excludes only its legal TT move and leaks no TT authority" {
    // A deliberately strong but one-ply-shallow exact TT record is usable for
    // ordering and singular evidence at the depth-seven iteration, not as a
    // cutoff. The artificial score isolates the exclusion contract: every
    // alternative must fail below the threshold before the TT move extends.
    const fen_text = "8/8/p1p5/1p5p/1P5P/P1P5/8/K1k5 w - - 0 1";
    var seed_root: chess.position.PositionState = .{};
    var seed_position = try chess.fen.parse(fen_text, &seed_root);
    const root_move = try chess.notation.parseLegal(&seed_position, "a1a2");
    var child_state: chess.position.PositionState = undefined;
    chess.transition.makeMove(&seed_position, root_move, &child_state);
    const tt_move = try chess.notation.parseLegal(&seed_position, "c1d1");

    var storage: [256]search.tt.Cluster = undefined;
    var disabled_storage: [256]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    var disabled_table = search.tt.Table.init(&disabled_storage);
    _ = table.store(
        seed_position.current.key,
        tt_move,
        manta.score.Score.fromOrdinary(1_000).?,
        null,
        5,
        .exact,
        .full_search,
        1,
    );
    _ = disabled_table.store(
        seed_position.current.key,
        tt_move,
        manta.score.Score.fromOrdinary(1_000).?,
        null,
        5,
        .exact,
        .full_search,
        1,
    );

    var root_state: chess.position.PositionState = .{};
    var disabled_root_state: chess.position.PositionState = .{};
    var position = try chess.fen.parse(fen_text, &root_state);
    var disabled_position = try chess.fen.parse(fen_text, &disabled_root_state);
    const only = try chess.notation.parseLegal(&position, "a1a2");
    const disabled_only = try chess.notation.parseLegal(&disabled_position, "a1a2");
    var harness: Harness = .{};
    var disabled_harness: Harness = .{};
    var counters: search.diagnostics.Counters = .{};
    var disabled_counters: search.diagnostics.Counters = .{};
    var control: search.types.NeverStop = .{};
    var disabled_control: search.types.NeverStop = .{};
    const result = search.baseline.runRestrictedWithFeatures(
        .{ .shallow_selectivity = false },
        &position,
        harness.binding(),
        .{ .depth = 7 },
        &control,
        &harness.thread,
        &table,
        null,
        &counters,
        &.{only},
    );
    const disabled = search.baseline.runRestrictedWithFeatures(
        .{ .singular_extension = false, .shallow_selectivity = false },
        &disabled_position,
        disabled_harness.binding(),
        .{ .depth = 7 },
        &disabled_control,
        &disabled_harness.thread,
        &disabled_table,
        null,
        &disabled_counters,
        &.{disabled_only},
    );

    try std.testing.expect(counters.singular_attempts != 0);
    try std.testing.expect(counters.singular_extensions != 0);
    try std.testing.expectEqual(counters.singular_attempts, counters.exclusion_moves_skipped);
    try std.testing.expectEqual(
        counters.singular_attempts,
        counters.context_by_route[@intFromEnum(search.types.EntryRoute.singular_probe)],
    );
    try std.testing.expectEqual(
        @as(u64, 0),
        counters.tt_stores_by_producer[@intFromEnum(search.types.Provenance.exclusion_search)],
    );
    try std.testing.expectEqual(@as(u16, 7), result.completed.?.depth);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.singular_attempts);
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.singular_extensions);
    try std.testing.expectEqual(@as(u16, 7), disabled.completed.?.depth);
    try expectLegalPv(fen_text, result.completed.?.pv.slice());
    try expectLegalPv(fen_text, disabled.completed.?.pv.slice());
    try std.testing.expect(chess.state.isConsistent(&position));
    try std.testing.expect(chess.state.isConsistent(&disabled_position));
}

test "singular exclusion cancellation restores worker and board state" {
    // SCORE-022/QUAL-016: stop is first observed inside the same-position
    // exclusion search. Both the excluded-move marker and every parent chess/
    // evaluator transition must unwind before the incomplete result returns.
    const StopAtSingular = struct {
        counters: *const search.diagnostics.Counters,

        pub fn shouldStop(self: *@This()) bool {
            return self.counters.singular_attempts != 0;
        }
    };
    const fen_text = "8/8/p1p5/1p5p/1P5P/P1P5/8/K1k5 w - - 0 1";
    var seed_root: chess.position.PositionState = .{};
    var seed_position = try chess.fen.parse(fen_text, &seed_root);
    const root_move = try chess.notation.parseLegal(&seed_position, "a1a2");
    var child_state: chess.position.PositionState = undefined;
    chess.transition.makeMove(&seed_position, root_move, &child_state);
    const tt_move = try chess.notation.parseLegal(&seed_position, "c1d1");

    var storage: [256]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    _ = table.store(
        seed_position.current.key,
        tt_move,
        manta.score.Score.fromOrdinary(1_000).?,
        null,
        5,
        .exact,
        .full_search,
        1,
    );

    var root_state: chess.position.PositionState = .{};
    var position = try chess.fen.parse(fen_text, &root_state);
    const original_key = position.current.key;
    const only = try chess.notation.parseLegal(&position, "a1a2");
    var harness: Harness = .{};
    var counters: search.diagnostics.Counters = .{};
    var control = StopAtSingular{ .counters = &counters };
    const result = search.baseline.runRestrictedWithFeatures(
        .{ .shallow_selectivity = false },
        &position,
        harness.binding(),
        .{ .depth = 7 },
        &control,
        &harness.thread,
        &table,
        null,
        &counters,
        &.{only},
    );

    try std.testing.expectEqual(search.types.Termination.stopped, result.termination);
    try std.testing.expect(counters.singular_attempts != 0);
    try std.testing.expectEqual(chess.move.Move.none.raw(), harness.thread.ply_contexts[1].excluded_move.raw());
    try std.testing.expectEqual(original_key, position.current.key);
    try std.testing.expect(position.current.previous == null);
    try std.testing.expect(chess.state.isConsistent(&position));
}

test "balanced quiet outcomes feed ordering and conservative LMR confidence" {
    // A full-authority quiet cutoff rewards its move and penalizes only the
    // earlier quiet alternatives that were actually searched. Net-positive
    // history may protect a later quiet from reduction, but it never creates
    // score, PV, terminal, draw, or legality authority.
    const fen_text = "r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P4/2NBPN2/PPQ2PPP/R1B1K2R w KQ - 4 8";
    var candidate_state: chess.position.PositionState = .{};
    var legacy_state: chess.position.PositionState = .{};
    var candidate_position = try chess.fen.parse(fen_text, &candidate_state);
    var legacy_position = try chess.fen.parse(fen_text, &legacy_state);
    var candidate_harness: Harness = .{};
    var legacy_harness: Harness = .{};
    var candidate_storage: [1024]search.tt.Cluster = undefined;
    var legacy_storage: [1024]search.tt.Cluster = undefined;
    var candidate_table = search.tt.Table.init(&candidate_storage);
    var legacy_table = search.tt.Table.init(&legacy_storage);
    var candidate_ordering: search.ordering.State = .{};
    var legacy_ordering: search.ordering.State = .{};
    var candidate_counters: search.diagnostics.Counters = .{};
    var legacy_counters: search.diagnostics.Counters = .{};
    var candidate_control: search.types.NeverStop = .{};
    var legacy_control: search.types.NeverStop = .{};

    const candidate = search.baseline.runWithFeatures(
        .{
            .balanced_history = true,
            .history_lmr = true,
            .qsearch_see = false,
            .shallow_selectivity = false,
            .contextual_history = false,
        },
        &candidate_position,
        candidate_harness.binding(),
        .{ .depth = 7 },
        &candidate_control,
        &candidate_harness.thread,
        &candidate_table,
        &candidate_ordering,
        &candidate_counters,
    );
    const legacy = search.baseline.runWithFeatures(
        .{
            .balanced_history = false,
            .history_lmr = false,
            .qsearch_see = false,
            .shallow_selectivity = false,
            .contextual_history = false,
        },
        &legacy_position,
        legacy_harness.binding(),
        .{ .depth = 7 },
        &legacy_control,
        &legacy_harness.thread,
        &legacy_table,
        &legacy_ordering,
        &legacy_counters,
    );

    try std.testing.expect(candidate_counters.history_rewards != 0);
    try std.testing.expect(candidate_counters.history_penalties != 0);
    try std.testing.expect(candidate_counters.lmr_history_protections != 0);
    try std.testing.expectEqual(@as(u64, 0), legacy_counters.history_penalties);
    try std.testing.expectEqual(@as(u64, 0), legacy_counters.lmr_history_protections);
    try std.testing.expectEqual(search.types.Bound.exact, candidate.evidence.bound);
    try std.testing.expectEqual(search.types.Bound.exact, legacy.evidence.bound);
    try std.testing.expect(chess.movegen.isLegal(&candidate_position, candidate.best_move.?));
    try std.testing.expect(chess.movegen.isLegal(&legacy_position, legacy.best_move.?));
    try expectLegalPv(fen_text, candidate.completed.?.pv.slice());
    try expectLegalPv(fen_text, legacy.completed.?.pv.slice());
    try std.testing.expect(chess.state.isConsistent(&candidate_position));
    try std.testing.expect(chess.state.isConsistent(&legacy_position));
}

test "staged ordering puts a legal TT move before killers and quiet history" {
    // All moves in the initial position are unique quiets. This independently
    // protects one-shot TT emission, stage precedence and stable generation
    // order for equal-ranked tail moves.
    var root_state: chess.position.PositionState = .{};
    var value = try chess.fen.parse(chess.fen.start_position, &root_state);
    var moves = chess.position.MoveList.init();
    chess.movegen.generate(.all, &value, &moves);
    const tt_move = try chess.notation.parseLegal(&value, "e2e4");
    const killer = try chess.notation.parseLegal(&value, "d2d4");
    const history_move = try chess.notation.parseLegal(&value, "g1f3");
    var heuristics: search.ordering.State = .{};
    heuristics.killers[0][0] = killer;
    heuristics.quiet_history[chess.types.Color.white.index()][history_move.from().index()][history_move.to().index()] = 100;
    var harness: Harness = .{};
    const generated = moves;
    var picker = search.ordering.Picker.init(
        true,
        &moves,
        &value,
        harness.binding(),
        tt_move,
        &heuristics,
        .{},
        0,
        null,
        .{},
        true,
        true,
    );
    var selected: [chess.types.move_capacity]chess.move.Move = undefined;
    var selected_count: usize = 0;
    var tt_count: usize = 0;
    while (picker.next()) |selection| {
        try std.testing.expectEqual(selected_count, selection.index);
        selected[selected_count] = selection.chess_move;
        selected_count += 1;
        if (selection.source == .tt) tt_count += 1;
    }
    try std.testing.expectEqual(@as(usize, generated.count), selected_count);
    try std.testing.expectEqual(@as(usize, 1), tt_count);
    try std.testing.expectEqual(tt_move, selected[0]);
    try std.testing.expectEqual(killer, selected[1]);
    try std.testing.expectEqual(history_move, selected[2]);

    var tail_index: usize = 3;
    for (generated.slice()) |generated_move| {
        if (generated_move.raw() == tt_move.raw() or
            generated_move.raw() == killer.raw() or
            generated_move.raw() == history_move.raw()) continue;
        try std.testing.expectEqual(generated_move, selected[tail_index]);
        tail_index += 1;
    }
    try std.testing.expectEqual(selected_count, tail_index);
}

test "picker freezes sibling ranks before descendant history updates" {
    // SCORE-015/FUNC-005/QUAL-014: recursive child searches update shared
    // worker-local history. A parent's already-ranked legal siblings must keep
    // their node-entry order; observing later updates changes the deterministic
    // search tree even when move membership is identical.
    var root_state: chess.position.PositionState = .{};
    var value = try chess.fen.parse(chess.fen.start_position, &root_state);
    var moves = chess.position.MoveList.init();
    chess.movegen.generate(.all, &value, &moves);
    const generated = moves;
    const boosted = generated.moves[@as(usize, generated.count) - 1];
    var heuristics: search.ordering.State = .{};
    var harness: Harness = .{};
    var frozen = search.ordering.Picker.init(
        true,
        &moves,
        &value,
        harness.binding(),
        null,
        &heuristics,
        .{},
        0,
        null,
        .{},
        true,
        true,
    );

    heuristics.quiet_history[value.side_to_move.index()][boosted.from().index()][boosted.to().index()] = 1000;
    const frozen_first = frozen.next().?.chess_move;

    var fresh_moves = generated;
    var fresh = search.ordering.Picker.init(
        true,
        &fresh_moves,
        &value,
        harness.binding(),
        null,
        &heuristics,
        .{},
        0,
        null,
        .{},
        true,
        true,
    );
    const fresh_first = fresh.next().?.chess_move;

    try std.testing.expectEqual(generated.moves[0], frozen_first);
    try std.testing.expectEqual(boosted, fresh_first);
}

test "live-history staging ranks delayed quiets after descendant updates" {
    // Phase 6.5.1b/SCORE-015: a legal quiet TT move proves the node is not
    // terminal without forcing generation of its quiet siblings. Once that
    // move has been searched, the delayed stage must observe newer worker-
    // local history, emit the TT move only once and preserve the full legal
    // move set without allocation.
    var root_state: chess.position.PositionState = .{};
    var value = try chess.fen.parse(chess.fen.start_position, &root_state);
    var expected = chess.position.MoveList.init();
    chess.movegen.generate(.all, &value, &expected);
    const tt_move = try chess.notation.parseLegal(&value, "e2e4");
    const boosted = try chess.notation.parseLegal(&value, "g1f3");
    var staged = chess.position.MoveList.init();
    staged.append(tt_move);
    var heuristics: search.ordering.State = .{};
    var harness: Harness = .{};
    var picker = search.ordering.LiveHistoryPicker.init(
        true,
        &staged,
        &value,
        harness.binding(),
        tt_move,
        &heuristics,
        .{},
        0,
        null,
        .{},
        true,
        true,
        true,
    );

    var emitted: [chess.types.move_capacity]chess.move.Move = undefined;
    var emitted_count: usize = 0;
    emitted[emitted_count] = picker.next().?.chess_move;
    emitted_count += 1;
    try std.testing.expectEqual(tt_move, emitted[0]);
    try std.testing.expect(picker.next() == null);

    heuristics.quiet_history[value.side_to_move.index()][boosted.from().index()][boosted.to().index()] = 1000;
    const generated = picker.enterQuiets(
        true,
        &value,
        harness.binding(),
        tt_move,
        &heuristics,
        .{},
        0,
        null,
        .{},
    ).?;
    try std.testing.expectEqual(expected.count - 1, generated);
    emitted[emitted_count] = picker.next().?.chess_move;
    try std.testing.expectEqual(boosted, emitted[emitted_count]);
    emitted_count += 1;
    while (picker.next()) |selection| {
        emitted[emitted_count] = selection.chess_move;
        emitted_count += 1;
    }

    try std.testing.expectEqual(expected.count, emitted_count);
    for (emitted[0..emitted_count], 0..) |left, index| {
        var found = false;
        for (expected.slice()) |right| {
            if (left.raw() == right.raw()) found = true;
        }
        try std.testing.expect(found);
        for (emitted[index + 1 .. emitted_count]) |right|
            try std.testing.expect(left.raw() != right.raw());
    }
}

test "live-history staged search is deterministic legal and observable" {
    // FUNC-004/FUNC-005/PERF-006: the candidate may change its tree and PV,
    // but two cleared 1T runs must agree exactly, publish a sequentially legal
    // PV, restore the root and populate both delayed-generation stages.
    const fen_text = chess.fen.start_position;
    var first_root: chess.position.PositionState = .{};
    var second_root: chess.position.PositionState = .{};
    var first_position = try chess.fen.parse(fen_text, &first_root);
    var second_position = try chess.fen.parse(fen_text, &second_root);
    var first_harness: Harness = .{};
    var second_harness: Harness = .{};
    var first_storage: [4096]search.tt.Cluster = undefined;
    var second_storage: [4096]search.tt.Cluster = undefined;
    var first_table = search.tt.Table.init(&first_storage);
    var second_table = search.tt.Table.init(&second_storage);
    var first_ordering: search.ordering.State = .{};
    var second_ordering: search.ordering.State = .{};
    var first_counters: search.diagnostics.Counters = .{};
    var second_counters: search.diagnostics.Counters = .{};
    var first_control: search.types.NeverStop = .{};
    var second_control: search.types.NeverStop = .{};
    const candidate = search.types.Features{ .live_history_staging = true };

    const first = search.baseline.runWithFeatures(
        candidate,
        &first_position,
        first_harness.binding(),
        .{ .depth = 6 },
        &first_control,
        &first_harness.thread,
        &first_table,
        &first_ordering,
        &first_counters,
    );
    const second = search.baseline.runWithFeatures(
        candidate,
        &second_position,
        second_harness.binding(),
        .{ .depth = 6 },
        &second_control,
        &second_harness.thread,
        &second_table,
        &second_ordering,
        &second_counters,
    );

    try std.testing.expectEqual(first.nodes, second.nodes);
    try std.testing.expectEqual(first.evidence, second.evidence);
    try std.testing.expectEqual(first.best_move.?, second.best_move.?);
    try std.testing.expectEqualSlices(
        chess.move.Move,
        first.completed.?.pv.slice(),
        second.completed.?.pv.slice(),
    );
    try std.testing.expect(first_counters.live_history_staged_nodes != 0);
    try std.testing.expect(first_counters.live_history_tacticals_generated != 0);
    try std.testing.expect(first_counters.live_history_quiet_stages != 0);
    try std.testing.expect(first_counters.live_history_quiets_generated != 0);
    try std.testing.expectEqual(
        first_counters.live_history_staged_nodes,
        second_counters.live_history_staged_nodes,
    );
    try expectLegalPv(fen_text, first.completed.?.pv.slice());
    try expectLegalPv(fen_text, second.completed.?.pv.slice());
    try std.testing.expect(chess.state.isConsistent(&first_position));
    try std.testing.expect(chess.state.isConsistent(&second_position));
}

test "full-depth LMR false positives train reply ordering only" {
    // SCORE-002/QUAL-014: a reduced probe is not training evidence. Only its
    // mandatory full-depth upper-bound re-search may penalize the quiet reply;
    // disabling this consumer must remove every such update while both legal
    // searches restore their root positions.
    const fen_text = chess.fen.start_position;
    var enabled_root: chess.position.PositionState = .{};
    var disabled_root: chess.position.PositionState = .{};
    var enabled_position = try chess.fen.parse(fen_text, &enabled_root);
    var disabled_position = try chess.fen.parse(fen_text, &disabled_root);
    var enabled_harness: Harness = .{};
    var disabled_harness: Harness = .{};
    var enabled_storage: [4096]search.tt.Cluster = undefined;
    var disabled_storage: [4096]search.tt.Cluster = undefined;
    var enabled_table = search.tt.Table.init(&enabled_storage);
    var disabled_table = search.tt.Table.init(&disabled_storage);
    var enabled_ordering: search.ordering.State = .{};
    var disabled_ordering: search.ordering.State = .{};
    var enabled_counters: search.diagnostics.Counters = .{};
    var disabled_counters: search.diagnostics.Counters = .{};
    var enabled_control: search.types.NeverStop = .{};
    var disabled_control: search.types.NeverStop = .{};

    const enabled = search.baseline.runWithFeatures(
        .{ .lmr_synchronization = false, .lmr_reply_feedback = true },
        &enabled_position,
        enabled_harness.binding(),
        .{ .depth = 9 },
        &enabled_control,
        &enabled_harness.thread,
        &enabled_table,
        &enabled_ordering,
        &enabled_counters,
    );
    const disabled = search.baseline.runWithFeatures(
        .{},
        &disabled_position,
        disabled_harness.binding(),
        .{ .depth = 9 },
        &disabled_control,
        &disabled_harness.thread,
        &disabled_table,
        &disabled_ordering,
        &disabled_counters,
    );

    try std.testing.expect(enabled_counters.contextual_history_lmr_failures != 0);
    try std.testing.expect(
        enabled_counters.contextual_history_lmr_failures <= enabled_counters.lmr_researches,
    );
    try std.testing.expectEqual(@as(u64, 0), disabled_counters.contextual_history_lmr_failures);
    try expectLegalPv(fen_text, enabled.completed.?.pv.slice());
    try expectLegalPv(fen_text, disabled.completed.?.pv.slice());
    try std.testing.expect(chess.state.isConsistent(&enabled_position));
    try std.testing.expect(chess.state.isConsistent(&disabled_position));
}

test "immediate stop diagnostics identify zero unpublished node work" {
    const StopNow = struct {
        pub fn shouldStop(_: *@This()) bool {
            return true;
        }
    };
    var root_state: chess.position.PositionState = .{};
    var value = try chess.fen.parse(chess.fen.start_position, &root_state);
    var harness: Harness = .{};
    var control: StopNow = .{};
    var counters: search.diagnostics.Counters = .{};
    const result = search.baseline.runWith(
        &value,
        harness.binding(),
        .{ .depth = 3 },
        &control,
        &harness.thread,
        null,
        null,
        &counters,
    );
    try std.testing.expectEqual(search.types.Termination.stopped, result.termination);
    try std.testing.expectEqual(@as(?u64, 0), counters.abort_node);
    try std.testing.expectEqual(@as(u64, 1), counters.stop_checks);
}

test "ProbCut cancellation unwinds the tactical move and evaluator state" {
    // QUAL-014/016: cancellation is first observed inside the qsearch entered
    // after a ProbCut capture has been made. The error path must undo both the
    // chess transition and incremental evaluator update before publication.
    const StopAtProbCut = struct {
        counters: *const search.diagnostics.Counters,

        pub fn shouldStop(self: *@This()) bool {
            return self.counters.probcut_moves != 0;
        }
    };
    var root_state: chess.position.PositionState = .{};
    var position = try chess.fen.parse(chess.fen.start_position, &root_state);
    const original_key = position.current.key;
    var harness: Harness = .{};
    var counters: search.diagnostics.Counters = .{};
    var control = StopAtProbCut{ .counters = &counters };
    const result = search.baseline.runWith(
        &position,
        harness.binding(),
        .{ .depth = 9 },
        &control,
        &harness.thread,
        null,
        null,
        &counters,
    );

    try std.testing.expectEqual(search.types.Termination.stopped, result.termination);
    try std.testing.expect(counters.probcut_moves != 0);
    try std.testing.expectEqual(original_key, position.current.key);
    try std.testing.expect(position.current.previous == null);
    try std.testing.expect(chess.state.isConsistent(&position));
}

fn expectLegalPv(fen_text: []const u8, pv: []const chess.move.Move) !void {
    // Legal PV replay is an independent consumer of the published root line;
    // every move must remain legal after each preceding transition.
    var states: [chess.types.max_ply]chess.position.PositionState = undefined;
    var root_state: chess.position.PositionState = .{};
    var position = try chess.fen.parse(fen_text, &root_state);
    for (pv, 0..) |chess_move, ply| {
        try std.testing.expect(chess.movegen.isLegal(&position, chess_move));
        chess.transition.makeMove(&position, chess_move, &states[ply]);
    }
}

fn sumCounts(values: anytype) @typeInfo(@TypeOf(values)).array.child {
    const Value = @typeInfo(@TypeOf(values)).array.child;
    var total: Value = 0;
    for (values) |value| total += value;
    return total;
}

/// Independent stand-in for a loaded tablebase.
///
/// Real Syzygy files are a multi-hundred-megabyte external asset, so the search
/// integration is exercised against a prober that answers from an explicit
/// rule rather than from disk. This is deliberately not a reimplementation of
/// the format: it asserts only what search is allowed to assume about *any*
/// conforming prober, which is exactly the contract boundary under test.
const StubProber = struct {
    verdict: search.tablebase.Wdl,
    max_pieces: u8 = 5,
    probes: usize = 0,

    pub fn isLoaded(self: *const StubProber) bool {
        _ = self;
        return true;
    }

    pub fn probeWdl(
        self: *StubProber,
        position: *const chess.position.Position,
    ) search.tablebase.ProbeResult {
        self.probes += 1;
        const pieces: u8 = @intCast(@popCount(position.physical.occupied()));
        if (search.tablebase.wdlPrecondition(
            pieces,
            self.max_pieces,
            position.current.castling_rights != .none,
            position.current.rule50,
        )) |reason| return .{ .unavailable = reason };
        return .{ .available = self.verdict };
    }
};

test "a loaded tablebase supplies exact evidence with its own provenance" {
    // SCORE-005/FUNC-004: a proven result must reach the root as tablebase
    // evidence rather than a searched score, must land inside the reserved
    // band, and must still publish a legal move and a legal PV.
    const fen_text = "8/8/8/4k3/8/8/4P3/4K3 w - - 0 1";
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parse(fen_text, &root);
    var harness: Harness = .{};
    var storage: [4096]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    var heuristics: search.ordering.State = .{};
    var counters: search.diagnostics.Counters = .{};
    var control: search.types.NeverStop = .{};
    var prober = StubProber{ .verdict = .win };

    const result = search.baseline.runRestrictedWithTablebase(
        .{},
        &position,
        harness.binding(),
        .{ .depth = 4 },
        &control,
        &harness.thread,
        &table,
        &heuristics,
        &counters,
        null,
        &prober,
    );

    try std.testing.expect(prober.probes != 0);
    try std.testing.expect(counters.tablebase_hits != 0);
    try std.testing.expectEqual(
        counters.tablebase_hits,
        counters.tablebase_hits_by_wdl[@intFromEnum(search.tablebase.Wdl.win)],
    );
    // Interior evidence must never be published as the root's own producer.
    try std.testing.expect(result.best_move != null);
    try std.testing.expect(chess.movegen.isLegal(&position, result.best_move.?));
    try expectLegalPv(fen_text, result.completed.?.pv.slice());
    try std.testing.expect(chess.state.isConsistent(&position));
    // The winning side must not be told the position is merely equal.
    try std.testing.expect(result.evidence.value.raw() > 0);
}

test "tablebase probing is inert without a loaded prober" {
    // The accepted MAN-S19 head must be reproduced exactly whenever no
    // tablebase is configured, which is the normal deployment.
    const fen_text = "r2qr1k1/p4ppp/1pn1bn2/2b1p3/4P3/1BN1BN2/PPP2PPP/R2QR1K1 b - - 6 10";
    var enabled_state: chess.position.PositionState = .{};
    var disabled_state: chess.position.PositionState = .{};
    var enabled_position = try chess.fen.parse(fen_text, &enabled_state);
    var disabled_position = try chess.fen.parse(fen_text, &disabled_state);
    var enabled_harness: Harness = .{};
    var disabled_harness: Harness = .{};
    var enabled_storage: [4096]search.tt.Cluster = undefined;
    var disabled_storage: [4096]search.tt.Cluster = undefined;
    var enabled_table = search.tt.Table.init(&enabled_storage);
    var disabled_table = search.tt.Table.init(&disabled_storage);
    var enabled_ordering: search.ordering.State = .{};
    var disabled_ordering: search.ordering.State = .{};
    var enabled_counters: search.diagnostics.Counters = .{};
    var disabled_counters: search.diagnostics.Counters = .{};
    var enabled_control: search.types.NeverStop = .{};
    var disabled_control: search.types.NeverStop = .{};

    const enabled = search.baseline.runWithFeatures(
        .{ .syzygy = true },
        &enabled_position,
        enabled_harness.binding(),
        .{ .depth = 6 },
        &enabled_control,
        &enabled_harness.thread,
        &enabled_table,
        &enabled_ordering,
        &enabled_counters,
    );
    const disabled = search.baseline.runWithFeatures(
        .{ .syzygy = false },
        &disabled_position,
        disabled_harness.binding(),
        .{ .depth = 6 },
        &disabled_control,
        &disabled_harness.thread,
        &disabled_table,
        &disabled_ordering,
        &disabled_counters,
    );

    try std.testing.expectEqual(@as(u64, 0), enabled_counters.tablebase_hits);
    try std.testing.expectEqual(disabled.nodes, enabled.nodes);
    try std.testing.expectEqual(disabled.evidence.value.raw(), enabled.evidence.value.raw());
    try std.testing.expectEqual(disabled.evidence.provenance, enabled.evidence.provenance);
    try std.testing.expectEqual(disabled.best_move.?.raw(), enabled.best_move.?.raw());
    try std.testing.expectEqual(disabled.completed.?.depth, enabled.completed.?.depth);
}

test "a rules-decided draw at the root is not replaced by tablebase evidence" {
    // The fifty-move rule is decided by the rules of chess, not by a table. A
    // prober insisting the position is won must not change the published
    // result, so the root draw check has to precede any probing.
    //
    // Note the interior contrast: once a pawn move or capture resets the
    // halfmove clock, deeper nodes legitimately become probeable again. That
    // is correct, and it is why the clock is a per-node precondition rather
    // than a property of the search as a whole.
    const fen_text = "8/8/8/4k3/8/8/4P3/4K3 w - - 100 60";
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parse(fen_text, &root);
    var harness: Harness = .{};
    var counters: search.diagnostics.Counters = .{};
    var control: search.types.NeverStop = .{};
    var prober = StubProber{ .verdict = .win };

    const result = search.baseline.runRestrictedWithTablebase(
        .{},
        &position,
        harness.binding(),
        .{ .depth = 4 },
        &control,
        &harness.thread,
        null,
        null,
        &counters,
        null,
        &prober,
    );

    try std.testing.expectEqual(search.types.Termination.root_draw, result.termination);
    try std.testing.expectEqual(@as(i32, 0), result.evidence.value.raw());
    try std.testing.expectEqual(search.types.Provenance.terminal, result.evidence.provenance);
    try std.testing.expectEqual(@as(u64, 0), counters.tablebase_hits);
    try std.testing.expect(result.best_move != null);
    try std.testing.expect(chess.movegen.isLegal(&position, result.best_move.?));
    try std.testing.expect(chess.state.isConsistent(&position));
}

test "a nonzero halfmove clock suppresses probing at that node" {
    // Syzygy WDL tables are indexed at a reset clock only. This is the
    // per-node precondition in isolation, independent of any search shape.
    var root: chess.position.PositionState = .{};
    const position = try chess.fen.parse("8/8/8/4k3/8/8/4P3/4K3 w - - 7 40", &root);
    var prober = StubProber{ .verdict = .win };
    try std.testing.expectEqual(
        search.tablebase.ProbeResult{ .unavailable = .halfmove_clock },
        prober.probeWdl(&position),
    );
}
