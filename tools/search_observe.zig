//! Deterministic fixed-depth search-observation report; never a strength gate.
const std = @import("std");
const manta = @import("manta");
const search_build_options = @import("search_build_options");

const chess = manta.chess;
const search = manta.search;
const EvalBinding = manta.eval.contract.Binding(manta.eval.hce.Hce, manta.eval.trace.Disabled);

const Harness = struct {
    evaluator: manta.eval.hce.Hce = .{},
    evaluator_state: manta.eval.hce.Hce.State = .{},
    sink: manta.eval.trace.Disabled = .{},

    fn binding(self: *Harness) EvalBinding {
        return .{ .evaluator = &self.evaluator, .state = &self.evaluator_state, .sink = &self.sink };
    }
};

const Record = struct {
    result: search.types.Result,
    counters: search.diagnostics.Counters,
};

pub fn main(init: std.process.Init) !u8 {
    var hash = manta.engine.runtime.HashResource.init(
        init.arena.allocator(),
        search.observation.hash_mib,
    ) catch |err| {
        std.debug.print("search observation: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer hash.deinit(init.arena.allocator());

    var thread = search.types.ThreadState.init();
    var heuristics: search.ordering.State = .{};
    std.debug.print(
        "Manta search observation\nschema: {s}\npositions: {d}\ndepth: per-case fixed\nhash: {d} MiB\nreset: TT and ordering before every case\n",
        .{ search.observation.version, search.observation.cases.len, search.observation.hash_mib },
    );
    for (search.observation.cases) |case| {
        const record = observe(case, &thread, &hash.table, &heuristics) catch |err| {
            std.debug.print("case={s} FAIL={s}\n", .{ case.id, @errorName(err) });
            return 1;
        };
        printRecord(case, record);
    }
    std.debug.print("search observation: PASS\n", .{});
    return 0;
}

fn observe(
    case: search.observation.Case,
    thread: *search.types.ThreadState,
    table: *search.tt.Table,
    heuristics: *search.ordering.State,
) !Record {
    table.clear();
    heuristics.clear();
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parse(case.fen, &root);
    var harness: Harness = .{};
    var control: search.types.NeverStop = .{};
    var counters: search.diagnostics.Counters = .{};
    const result = search.baseline.runWithFeatures(
        .{
            .correction_history = search_build_options.correction_history,
            .aspiration = search_build_options.stability_aspiration,
            .live_history_staging = search_build_options.live_history_staging,
            .nonroot_check_extension = search_build_options.nonroot_check_extension,
            .mate_distance_pruning = search_build_options.mate_distance_pruning,
            .singular_exclusion_horizon = search_build_options.singular_exclusion_horizon,
        },
        &position,
        harness.binding(),
        .{ .depth = case.depth },
        &control,
        thread,
        table,
        heuristics,
        &counters,
    );
    try validate(case, &position, result, counters);
    return .{ .result = result, .counters = counters };
}

fn validate(
    case: search.observation.Case,
    position: *const chess.position.Position,
    result: search.types.Result,
    counters: search.diagnostics.Counters,
) !void {
    if (!chess.state.isConsistent(position)) return error.PositionNotRestored;
    const best = result.best_move orelse return error.MissingBestMove;
    if (!chess.movegen.isLegal(position, best)) return error.IllegalBestMove;
    const completed = result.completed orelse return error.MissingCompletedIteration;
    if (completed.depth != case.depth or counters.completed_depth != case.depth)
        return error.IncompleteDepth;
    try validatePv(case.fen, completed.pv.slice());
    if (result.nodes != counters.main_nodes + counters.quiescence_nodes)
        return error.NodeAccounting;
    if (result.nodes != counters.pv_nodes + counters.non_pv_nodes)
        return error.NodeTypeAccounting;
    if (counters.searched_main_moves + counters.searched_quiescence_moves != sum(counters.searched_by_source))
        return error.MoveSourceAccounting;
    if (comptime search_build_options.live_history_staging) {
        if (counters.live_history_quiet_stages > counters.live_history_staged_nodes)
            return error.LiveHistoryStageAccounting;
    } else if (counters.live_history_staged_nodes != 0 or
        counters.live_history_tacticals_generated != 0 or
        counters.live_history_quiet_stages != 0 or
        counters.live_history_quiets_generated != 0)
    {
        return error.LiveHistoryStageAccounting;
    }
    if (counters.main_cutoffs + counters.quiescence_cutoffs != sum(counters.fail_high_by_index) or
        counters.main_cutoffs + counters.quiescence_cutoffs != sum(counters.cutoffs_by_source))
    {
        return error.FailHighAccounting;
    }
    if (counters.lmr_probes != counters.lmr_accepted + counters.lmr_researches)
        return error.ReductionAccounting;
    if (counters.lmr_reduction_plies < counters.lmr_probes or
        counters.lmr_multi_ply_probes > counters.lmr_probes or
        (counters.lmr_probes == 0) != (counters.lmr_max_reduction == 0) or
        (counters.lmr_multi_ply_probes != 0 and counters.lmr_max_reduction < 2) or
        counters.lmr_adjusted_shallower + counters.lmr_adjusted_deeper > counters.lmr_probes)
    {
        return error.ReductionMagnitudeAccounting;
    }
    if (sum(counters.tt_probes_by_producer) != sum(counters.tt_probes_by_bound) or
        sum(counters.tt_usable_by_producer) != sum(counters.tt_usable_by_bound) or
        sum(counters.tt_stores_by_producer) != sum(counters.tt_stores_by_bound))
    {
        return error.TableAccounting;
    }
    if (counters.completed_iterations != sum(counters.completed_by_bound) or
        counters.completed_iterations != sum(counters.completed_by_producer))
    {
        return error.RootAccounting;
    }
    if (counters.null_move_cutoffs !=
        counters.prunes_by_cause[@intFromEnum(search.diagnostics.PruneCause.null_move)])
    {
        return error.PruneAccounting;
    }
    if (counters.probcut_tt_cutoffs > counters.probcut_cutoffs)
        return error.ProbCutAccounting;
    const searched_probcut_cutoffs = counters.probcut_cutoffs - counters.probcut_tt_cutoffs;
    if (counters.probcut_cutoffs !=
        counters.prunes_by_cause[@intFromEnum(search.diagnostics.PruneCause.probcut)] or
        searched_probcut_cutoffs > counters.probcut_verifications or
        counters.probcut_verifications > counters.probcut_qsearch_passes or
        counters.probcut_qsearch_passes > counters.probcut_moves or
        counters.probcut_tt_cutoffs + counters.probcut_tt_skips > counters.probcut_nodes or
        counters.context_by_route[@intFromEnum(search.types.EntryRoute.probcut_probe)] !=
            counters.probcut_verifications or
        counters.tt_stores_by_producer[@intFromEnum(search.types.Provenance.probcut)] !=
            searched_probcut_cutoffs)
    {
        return error.ProbCutAccounting;
    }
    if (counters.qsearch_see_candidates !=
        counters.qsearch_see_prunes + counters.qsearch_see_check_exemptions or
        counters.qsearch_stand_pat_cutoffs > counters.qsearch_stand_pat_nodes or
        counters.qsearch_stand_pat_results > counters.qsearch_stand_pat_nodes)
    {
        return error.QuiescenceAccounting;
    }
    if (counters.reverse_futility_cutoffs !=
        counters.prunes_by_cause[@intFromEnum(search.diagnostics.PruneCause.reverse_futility)] or
        counters.reverse_futility_cutoffs > counters.reverse_futility_candidates)
    {
        return error.ReverseFutilityAccounting;
    }
    // `.see` is shared by quiescence (accepted MAN-S07) and Step-5.1.4.3 main
    // search: each phase keeps its own dedicated counter, and only their sum
    // must equal the cross-cutting `prunes_by_cause` aggregate.
    if (counters.qsearch_see_prunes + counters.main_see_pruning_prunes !=
        counters.prunes_by_cause[@intFromEnum(search.diagnostics.PruneCause.see)] or
        counters.main_see_pruning_prunes > counters.main_see_pruning_candidates or
        counters.razoring_triggers > counters.razoring_candidates or
        counters.razoring_triggers !=
            counters.prunes_by_cause[@intFromEnum(search.diagnostics.PruneCause.razoring)] or
        counters.late_move_pruning_candidates <
            counters.prunes_by_cause[@intFromEnum(search.diagnostics.PruneCause.late_move)] or
        counters.quiet_futility_candidates <
            counters.prunes_by_cause[@intFromEnum(search.diagnostics.PruneCause.futility)] or
        counters.history_pruning_tightened_prunes > counters.history_pruning_tightenings or
        counters.capture_futility_prunes + counters.capture_futility_check_exemptions >
            counters.capture_futility_candidates)
    {
        return error.ShallowSelectivityAccounting;
    }
    // Step 6.5.2: the whole-tree charge is an exact partition of the visited
    // tree, and both chain histograms must account for every node that was
    // actually in check or actually extended. A charge that leaks nodes would
    // silently misattribute the cost of one mechanism to another.
    var charge_index: usize = 0;
    while (charge_index < counters.nodes_by_charge.len) : (charge_index += 1) {
        if (counters.nodes_under_charge[charge_index] < counters.nodes_by_charge[charge_index])
            return error.AttributionAccounting;
    }
    if (sum(counters.nodes_by_charge) != counters.context_nodes or
        counters.nodes_under_charge[@intFromEnum(search.diagnostics.WorkCharge.ordinary)] !=
            counters.nodes_by_charge[@intFromEnum(search.diagnostics.WorkCharge.ordinary)] or
        sum(counters.check_chain_lengths) != counters.context_in_check or
        sum(counters.extension_chain_lengths) != counters.extended_depth_intents or
        (counters.context_in_check == 0) != (counters.check_chain_max == 0) or
        (counters.extended_depth_intents == 0) != (counters.extension_chain_max == 0))
    {
        return error.AttributionAccounting;
    }
    const lookup_outcomes = counters.tt_lookups_by_outcome;
    const authenticated = lookup_outcomes[@intFromEnum(search.diagnostics.TableLookup.depth_rejected)] +
        lookup_outcomes[@intFromEnum(search.diagnostics.TableLookup.bound_rejected)] +
        lookup_outcomes[@intFromEnum(search.diagnostics.TableLookup.usable)];
    if (authenticated != sum(counters.tt_probes_by_bound) or
        lookup_outcomes[@intFromEnum(search.diagnostics.TableLookup.usable)] !=
            sum(counters.tt_usable_by_bound) or
        sum(counters.tt_stores_by_outcome) != sum(counters.tt_stores_by_bound))
    {
        return error.TableLookupAccounting;
    }
    if (counters.context_nodes != result.nodes or counters.outcomes != result.nodes or
        sum(counters.context_by_route) != counters.context_nodes or
        sum(counters.context_by_arrival) != counters.context_nodes or
        sum(counters.context_by_expectation) != counters.context_nodes or
        counters.context_by_expectation[@intFromEnum(search.types.NodeExpectation.principal)] !=
            counters.pv_nodes or
        counters.context_by_expectation[@intFromEnum(search.types.NodeExpectation.cut)] +
            counters.context_by_expectation[@intFromEnum(search.types.NodeExpectation.all)] !=
            counters.non_pv_nodes or
        sum(counters.outcomes_by_disposition) != counters.outcomes or
        sum(counters.outcomes_by_producer) != counters.outcomes)
    {
        return error.ContextAccounting;
    }
    if (counters.contextual_history_rewards + counters.contextual_history_pretrained_winners !=
        counters.contextual_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.exact)] +
            counters.contextual_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.cutoff)] +
            counters.contextual_history_lmr_positive or
        counters.contextual_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.fail_low)] != 0 or
        counters.contextual_history_lmr_failures > counters.lmr_researches or
        counters.contextual_history_lmr_positive + counters.contextual_history_lmr_negative > counters.lmr_researches or
        counters.contextual_history_lmr_failures > counters.contextual_history_penalties or
        counters.contextual_history_nonzero > counters.contextual_history_lookups)
    {
        return error.ContextualHistoryAccounting;
    }
    for (0..search.ordering.continuation_distance_count) |distance| {
        if (counters.continuation_history_rewards[distance] +
            counters.continuation_history_pretrained_winners[distance] !=
            counters.continuation_history_updates_by_disposition[distance][@intFromEnum(search.types.NodeDisposition.exact)] +
                counters.continuation_history_updates_by_disposition[distance][@intFromEnum(search.types.NodeDisposition.cutoff)] +
                counters.continuation_history_lmr_positive[distance] or
            counters.continuation_history_updates_by_disposition[distance][@intFromEnum(search.types.NodeDisposition.fail_low)] != 0 or
            counters.continuation_history_lmr_positive[distance] +
                counters.continuation_history_lmr_negative[distance] > counters.lmr_researches or
            counters.continuation_history_nonzero[distance] > counters.continuation_history_lookups[distance] or
            counters.continuation_history_from_check[distance] > counters.continuation_history_lookups[distance] or
            counters.continuation_history_tactical[distance] > counters.continuation_history_lookups[distance])
        {
            return error.ContinuationHistoryAccounting;
        }
    }
    if (counters.capture_history_rewards !=
        counters.capture_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.exact)] +
            counters.capture_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.cutoff)] or
        counters.capture_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.fail_low)] != 0 or
        counters.capture_history_nonzero > counters.capture_history_selections or
        sum(counters.capture_history_selections_by_consumer) != counters.capture_history_selections)
    {
        return error.CaptureHistoryAccounting;
    }
    if (counters.context_by_route[@intFromEnum(search.types.EntryRoute.root)] != counters.root_searches)
        return error.RootRouteAccounting;
    if (counters.root_searches != counters.completed_iterations +
        counters.aspiration_fail_lows + counters.aspiration_fail_highs or
        counters.aspiration_fail_lows + counters.aspiration_fail_highs > counters.aspiration_searches)
    {
        return error.AspirationAccounting;
    }
    if (counters.context_by_route[@intFromEnum(search.types.EntryRoute.quiescence)] != counters.quiescence_nodes)
        return error.QuiescenceRouteAccounting;
    if (counters.context_by_route[@intFromEnum(search.types.EntryRoute.null_probe)] != counters.null_move_attempts or
        counters.context_by_route[@intFromEnum(search.types.EntryRoute.null_verification)] != counters.null_move_verifications)
        return error.NullRouteAccounting;
    if (counters.context_by_route[@intFromEnum(search.types.EntryRoute.reduced_probe)] != counters.lmr_probes or
        counters.context_by_route[@intFromEnum(search.types.EntryRoute.reduction_research)] != counters.lmr_researches)
        return error.LmrRouteAccounting;
    if (counters.context_by_route[@intFromEnum(search.types.EntryRoute.singular_probe)] !=
        counters.singular_attempts + counters.singular_multicut_probes or
        counters.singular_attempts != counters.singular_extensions + counters.singular_rejections or
        // A legal same-position exclusion probe may terminate as a search draw
        // before move generation; every observed skip still belongs to one
        // attempt, but not every attempt must physically reach its TT move.
        counters.exclusion_moves_skipped > counters.singular_attempts + counters.singular_multicut_probes)
        return error.SingularRouteAccounting;
    if (counters.extended_depth_intents >
        counters.extensions_by_cause[@intFromEnum(search.diagnostics.ExtensionCause.check)] +
            counters.extensions_by_cause[@intFromEnum(search.diagnostics.ExtensionCause.singular)])
        return error.ExtensionAccounting;
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

fn compareDisabled(
    case: search.observation.Case,
    observed: Record,
    thread: *search.types.ThreadState,
    table: *search.tt.Table,
    heuristics: *search.ordering.State,
) !void {
    table.clear();
    heuristics.clear();
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parse(case.fen, &root);
    var harness: Harness = .{};
    var control: search.types.NeverStop = .{};
    var disabled: search.diagnostics.Disabled = .{};
    const result = search.baseline.runWithFeatures(
        .{
            .correction_history = search_build_options.correction_history,
            .aspiration = search_build_options.stability_aspiration,
            .live_history_staging = search_build_options.live_history_staging,
            .nonroot_check_extension = search_build_options.nonroot_check_extension,
            .mate_distance_pruning = search_build_options.mate_distance_pruning,
            .singular_exclusion_horizon = search_build_options.singular_exclusion_horizon,
        },
        &position,
        harness.binding(),
        .{ .depth = case.depth },
        &control,
        thread,
        table,
        heuristics,
        &disabled,
    );
    if (!optionalMoveEqual(result.best_move, observed.result.best_move) or
        result.evidence.value.raw() != observed.result.evidence.value.raw() or
        result.evidence.bound != observed.result.evidence.bound or
        result.evidence.provenance != observed.result.evidence.provenance or
        result.nodes != observed.result.nodes or
        result.selective_depth != observed.result.selective_depth)
    {
        return error.ObserverChangedResult;
    }
    const expected = observed.result.completed orelse return error.MissingCompletedIteration;
    const actual = result.completed orelse return error.MissingCompletedIteration;
    if (actual.depth != expected.depth or actual.nodes != expected.nodes or
        !moveSlicesEqual(actual.pv.slice(), expected.pv.slice()))
    {
        return error.ObserverChangedCompletedIteration;
    }
}

fn optionalMoveEqual(lhs: ?chess.move.Move, rhs: ?chess.move.Move) bool {
    if (lhs == null or rhs == null) return lhs == null and rhs == null;
    return lhs.?.raw() == rhs.?.raw();
}

fn moveSlicesEqual(lhs: []const chess.move.Move, rhs: []const chess.move.Move) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |left, right| {
        if (left.raw() != right.raw()) return false;
    }
    return true;
}

fn sum(values: anytype) @typeInfo(@TypeOf(values)).array.child {
    const Value = @typeInfo(@TypeOf(values)).array.child;
    var total: Value = 0;
    for (values) |value| total += value;
    return total;
}

fn printRecord(case: search.observation.Case, record: Record) void {
    const completed = record.result.completed.?;
    const move_text = chess.notation.format(record.result.best_move.?) catch unreachable;
    std.debug.print(
        "case={s} cohort={s} depth={d} best={s} score={d} bound={s} producer={s} nodes={d} main={d} q={d} generated={d} searched={d} cutoffs={d} root_changes={d} score_changes={d}\n",
        .{
            case.id,
            @tagName(case.cohort),
            case.depth,
            move_text.slice(),
            completed.evidence.value.raw(),
            @tagName(completed.evidence.bound),
            @tagName(completed.evidence.provenance),
            record.result.nodes,
            record.counters.main_nodes,
            record.counters.quiescence_nodes,
            record.counters.generated_moves,
            record.counters.searched_main_moves + record.counters.searched_quiescence_moves,
            record.counters.main_cutoffs + record.counters.quiescence_cutoffs,
            record.counters.root_best_changes,
            record.counters.root_score_changes,
        },
    );
    printEnumCounts(search.ordering.Source, "sources", record.counters.searched_by_source);
    printEnumCounts(search.ordering.Source, "cutoff_sources", record.counters.cutoffs_by_source);
    printEnumCounts(search.diagnostics.FailHighBucket, "fail_high_index", record.counters.fail_high_by_index);
    printEnumCounts(search.types.Bound, "tt_probes_bound", record.counters.tt_probes_by_bound);
    printEnumCounts(search.types.Bound, "tt_usable_bound", record.counters.tt_usable_by_bound);
    printEnumCounts(search.types.Bound, "tt_stores_bound", record.counters.tt_stores_by_bound);
    printEnumCounts(search.types.Provenance, "tt_probes_producer", record.counters.tt_probes_by_producer);
    printEnumCounts(search.types.Provenance, "tt_usable_producer", record.counters.tt_usable_by_producer);
    printEnumCounts(search.types.Provenance, "tt_stores_producer", record.counters.tt_stores_by_producer);
    printEnumCounts(search.diagnostics.PruneCause, "prunes", record.counters.prunes_by_cause);
    printEnumCounts(search.diagnostics.ExtensionCause, "extensions", record.counters.extensions_by_cause);
    printEnumCounts(search.types.EntryRoute, "routes", record.counters.context_by_route);
    printEnumCounts(search.diagnostics.WorkCharge, "charged_nodes", record.counters.nodes_by_charge);
    printEnumCounts(search.diagnostics.WorkCharge, "nodes_under", record.counters.nodes_under_charge);
    printEnumCounts(search.diagnostics.TableLookup, "tt_lookups", record.counters.tt_lookups_by_outcome);
    printEnumCounts(search.tt.StoreOutcome, "tt_store_outcomes", record.counters.tt_stores_by_outcome);
    printEnumCounts(search.types.Arrival, "arrivals", record.counters.context_by_arrival);
    printEnumCounts(
        search.types.NodeExpectation,
        "expectations",
        record.counters.context_by_expectation,
    );
    printEnumCounts(
        search.types.NodeDisposition,
        "outcomes",
        record.counters.outcomes_by_disposition,
    );
    printEnumCounts(
        search.types.Provenance,
        "outcome_producers",
        record.counters.outcomes_by_producer,
    );
    std.debug.print(
        "context nodes={d} check={d} reduced={d} extended={d} nominal_depth={d} searched_depth={d}\n",
        .{
            record.counters.context_nodes,
            record.counters.context_in_check,
            record.counters.reduced_depth_intents,
            record.counters.extended_depth_intents,
            record.counters.context_nominal_depth,
            record.counters.context_searched_depth,
        },
    );
    printBuckets("check_chain", record.counters.check_chain_max, record.counters.check_chain_lengths);
    printBuckets("extension_chain", record.counters.extension_chain_max, record.counters.extension_chain_lengths);
    std.debug.print(
        "mechanisms null={d}/{d}/{d}/{d} lmr={d}/{d}/{d}/{d} lmr_depth={d}/{d}/{d} history={d}/{d}/{d}/{d} tt_move={d}/{d}\n",
        .{
            record.counters.null_move_attempts,
            record.counters.null_move_fail_highs,
            record.counters.null_move_verifications,
            record.counters.null_move_cutoffs,
            record.counters.lmr_probes,
            record.counters.lmr_researches,
            record.counters.lmr_accepted,
            record.counters.lmr_history_protections,
            record.counters.lmr_reduction_plies,
            record.counters.lmr_multi_ply_probes,
            record.counters.lmr_max_reduction,
            record.counters.history_rewards,
            record.counters.history_reward_depth,
            record.counters.history_penalties,
            record.counters.history_penalty_depth,
            record.counters.tt_move_best,
            record.counters.tt_move_available,
        },
    );
    std.debug.print(
        "live_history_staging nodes={d} tacticals={d} quiet_stages={d} quiets={d}\n",
        .{
            record.counters.live_history_staged_nodes,
            record.counters.live_history_tacticals_generated,
            record.counters.live_history_quiet_stages,
            record.counters.live_history_quiets_generated,
        },
    );
    std.debug.print(
        "contextual_history lookup={d}/{d} updates={d}/{d} lmr_failures={d} penalties={d}\n",
        .{
            record.counters.contextual_history_lookups,
            record.counters.contextual_history_nonzero,
            record.counters.contextual_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.exact)],
            record.counters.contextual_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.cutoff)],
            record.counters.contextual_history_lmr_failures,
            record.counters.contextual_history_penalties,
        },
    );
    printEnumCounts(search.diagnostics.LmrModifier, "lmr_modifier_protect", record.counters.lmr_modifier_protect);
    printEnumCounts(search.diagnostics.LmrModifier, "lmr_modifier_deepen", record.counters.lmr_modifier_deepen);
    std.debug.print(
        "lmr_sync adjusted={d}/{d} feedback={d}/{d} pretrained={d}\n",
        .{
            record.counters.lmr_adjusted_shallower,
            record.counters.lmr_adjusted_deeper,
            record.counters.contextual_history_lmr_positive,
            record.counters.contextual_history_lmr_negative,
            record.counters.contextual_history_pretrained_winners,
        },
    );
    std.debug.print(
        "capture_history selections={d}/{d} consumers={d}/{d}/{d} updates={d}/{d} penalties={d}\n",
        .{
            record.counters.capture_history_selections,
            record.counters.capture_history_nonzero,
            record.counters.capture_history_selections_by_consumer[@intFromEnum(search.diagnostics.TacticalConsumer.main)],
            record.counters.capture_history_selections_by_consumer[@intFromEnum(search.diagnostics.TacticalConsumer.quiescence)],
            record.counters.capture_history_selections_by_consumer[@intFromEnum(search.diagnostics.TacticalConsumer.probcut)],
            record.counters.capture_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.exact)],
            record.counters.capture_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.cutoff)],
            record.counters.capture_history_penalties,
        },
    );
    printEnumCounts(search.ordering.ContinuationDistance, "continuation_lookups", record.counters.continuation_history_lookups);
    printEnumCounts(search.ordering.ContinuationDistance, "continuation_nonzero", record.counters.continuation_history_nonzero);
    printEnumCounts(search.ordering.ContinuationDistance, "continuation_from_check", record.counters.continuation_history_from_check);
    printEnumCounts(search.ordering.ContinuationDistance, "continuation_tactical", record.counters.continuation_history_tactical);
    printEnumCounts(search.ordering.ContinuationDistance, "continuation_rewards", record.counters.continuation_history_rewards);
    printEnumCounts(search.ordering.ContinuationDistance, "continuation_penalties", record.counters.continuation_history_penalties);
    std.debug.print(
        "depth_authority iir={d}/{d}/{d} singular={d}/{d}/{d} provenance_reject={d} double={d} multicut={d}/{d}/{d} exclusion_skips={d}\n",
        .{
            record.counters.internal_iterative_reductions,
            record.counters.internal_iterative_reductions_by_expectation[@intFromEnum(search.types.NodeExpectation.principal)],
            record.counters.internal_iterative_reductions_by_expectation[@intFromEnum(search.types.NodeExpectation.cut)],
            record.counters.singular_attempts,
            record.counters.singular_extensions,
            record.counters.singular_rejections,
            record.counters.singular_provenance_rejections,
            record.counters.singular_double_extensions,
            record.counters.singular_multicut_candidates,
            record.counters.singular_multicut_probes,
            record.counters.singular_multicut_cutoffs,
            record.counters.exclusion_moves_skipped,
        },
    );
    std.debug.print(
        "probcut nodes={d} tt={d}/{d} moves={d} qpass={d} verification={d} cutoffs={d}\n",
        .{
            record.counters.probcut_nodes,
            record.counters.probcut_tt_cutoffs,
            record.counters.probcut_tt_skips,
            record.counters.probcut_moves,
            record.counters.probcut_qsearch_passes,
            record.counters.probcut_verifications,
            record.counters.probcut_cutoffs,
        },
    );
    std.debug.print(
        "static_eval compute={d} tt_hit={d} refined={d}\nqsearch stand_pat={d}/{d}/{d} see={d}/{d}/{d} delta={d}/{d}/{d}\n",
        .{
            record.counters.static_eval_computes,
            record.counters.static_eval_tt_hits,
            record.counters.static_eval_tt_refinements,
            record.counters.qsearch_stand_pat_nodes,
            record.counters.qsearch_stand_pat_cutoffs,
            record.counters.qsearch_stand_pat_results,
            record.counters.qsearch_see_candidates,
            record.counters.qsearch_see_prunes,
            record.counters.qsearch_see_check_exemptions,
            record.counters.qsearch_delta_candidates,
            record.counters.qsearch_delta_prunes,
            record.counters.qsearch_delta_check_exemptions,
        },
    );
    std.debug.print(
        "reverse_futility candidates={d} cutoffs={d}\n",
        .{ record.counters.reverse_futility_candidates, record.counters.reverse_futility_cutoffs },
    );
    std.debug.print(
        "shallow_selectivity razoring={d}/{d} futility={d} late_move={d} see={d}/{d}\n",
        .{
            record.counters.razoring_candidates,
            record.counters.razoring_triggers,
            record.counters.quiet_futility_candidates,
            record.counters.late_move_pruning_candidates,
            record.counters.main_see_pruning_candidates,
            record.counters.main_see_pruning_prunes,
        },
    );
    std.debug.print(
        "main_selectivity null_dynamic={d}/{d}/{d} history={d}/{d}/{d} protect={d} tighten={d}/{d} capture_futility={d}/{d}/{d}\n",
        .{
            record.counters.null_move_dynamic_reductions,
            record.counters.null_move_extra_reduction_plies,
            record.counters.null_move_max_reduction,
            record.counters.selectivity_history_positive,
            record.counters.selectivity_history_negative,
            record.counters.selectivity_history_neutral,
            record.counters.history_pruning_protections,
            record.counters.history_pruning_tightenings,
            record.counters.history_pruning_tightened_prunes,
            record.counters.capture_futility_candidates,
            record.counters.capture_futility_prunes,
            record.counters.capture_futility_check_exemptions,
        },
    );
    std.debug.print(
        "root aspiration={d} fail_low={d} fail_high={d} populations={d} stable={d} delta={any}\n",
        .{
            record.counters.aspiration_searches,
            record.counters.aspiration_fail_lows,
            record.counters.aspiration_fail_highs,
            completed.root_confidence.completed_iterations,
            completed.root_confidence.stable_best_iterations,
            completed.root_confidence.best_score_delta,
        },
    );
}

/// Chain lengths are an open-ended histogram: bucket `i` counts runs of
/// exactly `i + 1`, and the last bucket absorbs everything longer.
fn printBuckets(label: []const u8, longest: u16, values: [search.diagnostics.max_chain_bucket]u64) void {
    std.debug.print("{s} max={d}", .{ label, longest });
    for (values, 1..) |count, length| {
        if (length == values.len)
            std.debug.print(" {d}+={d}", .{ length, count })
        else
            std.debug.print(" {d}={d}", .{ length, count });
    }
    std.debug.print("\n", .{});
}

fn printEnumCounts(comptime Enum: type, label: []const u8, values: anytype) void {
    std.debug.print("{s}", .{label});
    inline for (@typeInfo(Enum).@"enum".fields, 0..) |field, index|
        std.debug.print(" {s}={d}", .{ field.name, values[index] });
    std.debug.print("\n", .{});
}

test "fixed observation suite has complete behavior-neutral accounting" {
    // PERF-006/QUAL-013: the offline observer must describe every searched
    // move and cutoff without changing legal root/PV evidence or node work.
    var hash = try manta.engine.runtime.HashResource.init(std.testing.allocator, 1);
    defer hash.deinit(std.testing.allocator);
    var thread = search.types.ThreadState.init();
    var heuristics: search.ordering.State = .{};
    var probcut_nodes: u64 = 0;
    var probcut_moves: u64 = 0;
    var probcut_verifications: u64 = 0;
    var probcut_cutoffs: u64 = 0;
    var probcut_tt_decisions: u64 = 0;
    var contextual_lookups: u64 = 0;
    var contextual_nonzero: u64 = 0;
    var contextual_exact: u64 = 0;
    var contextual_cutoff: u64 = 0;
    var contextual_lmr_failures: u64 = 0;
    var lmr_feedback_positive: u64 = 0;
    var lmr_feedback_negative: u64 = 0;
    var lmr_adjusted_shallower: u64 = 0;
    var lmr_adjusted_deeper: u64 = 0;
    var static_eval_hits: u64 = 0;
    var static_eval_refinements: u64 = 0;
    var qsearch_delta_candidates: u64 = 0;
    var qsearch_delta_prunes: u64 = 0;
    var dynamic_null_reductions: u64 = 0;
    var dynamic_null_extra: u64 = 0;
    var history_selectivity: u64 = 0;
    var history_pruning_effects: u64 = 0;
    var capture_futility_candidates: u64 = 0;
    var cut_iir: u64 = 0;
    var singular_attempts: u64 = 0;
    var singular_multicut_candidates: u64 = 0;
    var singular_multicut_probes: u64 = 0;
    var singular_multicut_cutoffs: u64 = 0;
    var lmr_modifier_protect: [@typeInfo(search.diagnostics.LmrModifier).@"enum".fields.len]u64 = @splat(0);
    var lmr_modifier_deepen: [@typeInfo(search.diagnostics.LmrModifier).@"enum".fields.len]u64 = @splat(0);
    var continuation_lookups: [search.ordering.continuation_distance_count]u64 = @splat(0);
    var continuation_nonzero: [search.ordering.continuation_distance_count]u64 = @splat(0);
    var continuation_rewards: [search.ordering.continuation_distance_count]u64 = @splat(0);
    var capture_selections: [@typeInfo(search.diagnostics.TacticalConsumer).@"enum".fields.len]u64 = @splat(0);
    var capture_nonzero: u64 = 0;
    var capture_exact: u64 = 0;
    var capture_cutoff: u64 = 0;
    var expectations: [@typeInfo(search.types.NodeExpectation).@"enum".fields.len]u64 = @splat(0);
    var aspiration_searches: u64 = 0;
    for (search.observation.cases) |case| {
        const observed = try observe(case, &thread, &hash.table, &heuristics);
        try compareDisabled(case, observed, &thread, &hash.table, &heuristics);
        probcut_nodes += observed.counters.probcut_nodes;
        probcut_moves += observed.counters.probcut_moves;
        probcut_verifications += observed.counters.probcut_verifications;
        probcut_cutoffs += observed.counters.probcut_cutoffs;
        probcut_tt_decisions += observed.counters.probcut_tt_cutoffs + observed.counters.probcut_tt_skips;
        contextual_lookups += observed.counters.contextual_history_lookups;
        contextual_nonzero += observed.counters.contextual_history_nonzero;
        contextual_exact += observed.counters.contextual_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.exact)];
        contextual_cutoff += observed.counters.contextual_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.cutoff)];
        contextual_lmr_failures += observed.counters.contextual_history_lmr_failures;
        lmr_feedback_positive += observed.counters.contextual_history_lmr_positive;
        lmr_feedback_negative += observed.counters.contextual_history_lmr_negative;
        lmr_adjusted_shallower += observed.counters.lmr_adjusted_shallower;
        lmr_adjusted_deeper += observed.counters.lmr_adjusted_deeper;
        static_eval_hits += observed.counters.static_eval_tt_hits;
        static_eval_refinements += observed.counters.static_eval_tt_refinements;
        qsearch_delta_candidates += observed.counters.qsearch_delta_candidates;
        qsearch_delta_prunes += observed.counters.qsearch_delta_prunes;
        dynamic_null_reductions += observed.counters.null_move_dynamic_reductions;
        dynamic_null_extra += observed.counters.null_move_extra_reduction_plies;
        history_selectivity += observed.counters.selectivity_history_positive +
            observed.counters.selectivity_history_negative + observed.counters.selectivity_history_neutral;
        history_pruning_effects += observed.counters.history_pruning_protections +
            observed.counters.history_pruning_tightenings;
        capture_futility_candidates += observed.counters.capture_futility_candidates;
        cut_iir += observed.counters.internal_iterative_reductions_by_expectation[@intFromEnum(search.types.NodeExpectation.cut)];
        singular_attempts += observed.counters.singular_attempts;
        singular_multicut_candidates += observed.counters.singular_multicut_candidates;
        singular_multicut_probes += observed.counters.singular_multicut_probes;
        singular_multicut_cutoffs += observed.counters.singular_multicut_cutoffs;
        for (&lmr_modifier_protect, observed.counters.lmr_modifier_protect) |*total, count| total.* += count;
        for (&lmr_modifier_deepen, observed.counters.lmr_modifier_deepen) |*total, count| total.* += count;
        for (0..search.ordering.continuation_distance_count) |distance| {
            continuation_lookups[distance] += observed.counters.continuation_history_lookups[distance];
            continuation_nonzero[distance] += observed.counters.continuation_history_nonzero[distance];
            continuation_rewards[distance] += observed.counters.continuation_history_rewards[distance];
        }
        for (&capture_selections, observed.counters.capture_history_selections_by_consumer) |*total, count| total.* += count;
        capture_nonzero += observed.counters.capture_history_nonzero;
        capture_exact += observed.counters.capture_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.exact)];
        capture_cutoff += observed.counters.capture_history_updates_by_disposition[@intFromEnum(search.types.NodeDisposition.cutoff)];
        for (&expectations, observed.counters.context_by_expectation) |*total, count| total.* += count;
        aspiration_searches += observed.counters.aspiration_searches;
    }
    // PERF-010/QUAL-014: the fixed legal population must reach every accepted
    // production stage. Rejected candidates must remain entirely inactive.
    try std.testing.expect(probcut_nodes != 0);
    try std.testing.expect(probcut_moves != 0);
    try std.testing.expect(probcut_verifications != 0);
    try std.testing.expect(probcut_cutoffs != 0);
    try std.testing.expectEqual(@as(u64, 0), probcut_tt_decisions);
    try std.testing.expect(contextual_lookups != 0);
    try std.testing.expect(contextual_nonzero != 0);
    try std.testing.expect(contextual_exact != 0);
    try std.testing.expect(contextual_cutoff != 0);
    try std.testing.expectEqual(@as(u64, 0), contextual_lmr_failures);
    try std.testing.expectEqual(@as(u64, 0), lmr_feedback_positive);
    try std.testing.expectEqual(@as(u64, 0), lmr_feedback_negative);
    try std.testing.expectEqual(@as(u64, 0), lmr_adjusted_shallower);
    try std.testing.expectEqual(@as(u64, 0), lmr_adjusted_deeper);
    for (lmr_modifier_protect) |count| try std.testing.expectEqual(@as(u64, 0), count);
    for (lmr_modifier_deepen) |count| try std.testing.expectEqual(@as(u64, 0), count);
    try std.testing.expect(static_eval_hits != 0);
    try std.testing.expect(static_eval_refinements != 0);
    try std.testing.expect(qsearch_delta_candidates != 0);
    try std.testing.expect(qsearch_delta_prunes != 0);
    // Rejected MAN-S20 remains compiled behind component switches, but exact
    // MAN-S19 production must exercise none of its consumers.
    try std.testing.expectEqual(@as(u64, 0), dynamic_null_reductions);
    try std.testing.expectEqual(@as(u64, 0), dynamic_null_extra);
    try std.testing.expectEqual(@as(u64, 0), history_selectivity);
    try std.testing.expectEqual(@as(u64, 0), history_pruning_effects);
    try std.testing.expectEqual(@as(u64, 0), capture_futility_candidates);
    try std.testing.expectEqual(@as(u64, 0), cut_iir);
    try std.testing.expect(singular_attempts != 0);
    try std.testing.expectEqual(@as(u64, 0), singular_multicut_candidates);
    try std.testing.expectEqual(@as(u64, 0), singular_multicut_probes);
    try std.testing.expectEqual(@as(u64, 0), singular_multicut_cutoffs);
    for (0..search.ordering.continuation_distance_count) |distance| {
        try std.testing.expect(continuation_lookups[distance] != 0);
        try std.testing.expect(continuation_nonzero[distance] != 0);
        try std.testing.expect(continuation_rewards[distance] != 0);
    }
    // Rejected MAN-S16 remains compiled behind a feature switch, but the
    // production report must prove that no producer or consumer stays active.
    for (capture_selections) |count| try std.testing.expectEqual(@as(u64, 0), count);
    try std.testing.expectEqual(@as(u64, 0), capture_nonzero);
    try std.testing.expectEqual(@as(u64, 0), capture_exact);
    try std.testing.expectEqual(@as(u64, 0), capture_cutoff);
    for (expectations) |count| try std.testing.expect(count != 0);
    if (search_build_options.stability_aspiration)
        try std.testing.expect(aspiration_searches != 0)
    else
        try std.testing.expectEqual(@as(u64, 0), aspiration_searches);
}
