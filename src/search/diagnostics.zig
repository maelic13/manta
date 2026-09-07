//! Compile-time search-observer sinks and bounded diagnostic counters.
const std = @import("std");
const chess = @import("../chess/root.zig");
const ordering = @import("ordering.zig");
const tablebase = @import("tablebase.zig");
const types = @import("types.zig");

pub const NodeKind = enum { main, quiescence };
pub const TacticalConsumer = enum { main, quiescence, probcut };
pub const LmrModifier = enum { improving, expectation, tt_move, singular_context, history };
pub const LmrDirection = enum {
    protect,
    deepen,

    pub inline fn vote(self: LmrDirection) i4 {
        return if (self == .protect) 1 else -1;
    }
};
const provenance_count = @typeInfo(types.Provenance).@"enum".fields.len;
const bound_count = @typeInfo(types.Bound).@"enum".fields.len;
const source_count = @typeInfo(ordering.Source).@"enum".fields.len;
const wdl_count = @typeInfo(tablebase.Wdl).@"enum".fields.len;
const route_count = @typeInfo(types.EntryRoute).@"enum".fields.len;
const arrival_count = @typeInfo(types.Arrival).@"enum".fields.len;
const disposition_count = @typeInfo(types.NodeDisposition).@"enum".fields.len;
const expectation_count = @typeInfo(types.NodeExpectation).@"enum".fields.len;
const tactical_consumer_count = @typeInfo(TacticalConsumer).@"enum".fields.len;
const lmr_modifier_count = @typeInfo(LmrModifier).@"enum".fields.len;

pub const FailHighBucket = enum { first, second, third, fourth_to_eighth, later };
pub const PruneCause = enum { null_move, reverse_futility, razoring, probcut, multi_cut, late_move, futility, see, qsearch_delta };
pub const ExtensionCause = enum { check, singular, recapture, passed_pawn };

const fail_high_count = @typeInfo(FailHighBucket).@"enum".fields.len;
const prune_count = @typeInfo(PruneCause).@"enum".fields.len;
const extension_count = @typeInfo(ExtensionCause).@"enum".fields.len;

pub const Disabled = struct {
    pub const observes_move_sources = false;
    pub const observes_capture_history = false;

    pub inline fn reset(_: *Disabled) void {}
    pub inline fn stopCheck(_: *Disabled, _: u64) void {}
    pub inline fn abort(_: *Disabled, _: types.Termination, _: u64) void {}
    pub inline fn node(_: *Disabled, _: NodeKind, _: bool) void {}
    pub inline fn nodeContext(_: *Disabled, _: NodeKind, _: types.PlyContext, _: types.EntryRoute, _: types.DepthIntent, _: types.NodeExpectation) void {}
    pub inline fn nodeOutcome(_: *Disabled, _: types.OutcomeAttribution) void {}
    pub inline fn generated(_: *Disabled, _: usize) void {}
    pub inline fn liveHistoryTacticals(_: *Disabled, _: usize) void {}
    pub inline fn liveHistoryQuiets(_: *Disabled, _: usize) void {}
    pub inline fn searched(_: *Disabled, _: NodeKind) void {}
    pub inline fn cutoff(_: *Disabled, _: NodeKind) void {}
    pub inline fn ttProbe(_: *Disabled, _: types.Provenance, _: types.Bound, _: bool) void {}
    pub inline fn ttStore(_: *Disabled, _: types.Provenance, _: types.Bound) void {}
    pub inline fn ttBest(_: *Disabled, _: bool) void {}
    pub inline fn moveSource(_: *Disabled, _: ordering.Source) void {}
    pub inline fn failHigh(_: *Disabled, _: usize, _: ordering.Source) void {}
    pub inline fn historyReward(_: *Disabled, _: u16) void {}
    pub inline fn historyPenalty(_: *Disabled, _: u16) void {}
    pub inline fn contextualHistoryLookup(_: *Disabled, _: bool) void {}
    pub inline fn contextualHistoryUpdate(_: *Disabled, _: types.NodeDisposition, _: usize, _: bool) void {}
    pub inline fn contextualHistoryLmrFailure(_: *Disabled) void {}
    pub inline fn contextualHistoryLmrFeedback(_: *Disabled, _: bool) void {}
    pub inline fn continuationHistoryLookup(_: *Disabled, _: ordering.ContinuationDistance, _: bool, _: bool, _: bool) void {}
    pub inline fn continuationHistoryUpdate(_: *Disabled, _: ordering.ContinuationDistance, _: types.NodeDisposition, _: usize, _: bool) void {}
    pub inline fn continuationHistoryLmrFeedback(_: *Disabled, _: ordering.ContinuationDistance, _: bool) void {}
    pub inline fn captureHistorySelection(_: *Disabled, _: TacticalConsumer, _: bool) void {}
    pub inline fn captureHistoryUpdate(_: *Disabled, _: types.NodeDisposition, _: usize) void {}
    pub inline fn lmrHistoryProtection(_: *Disabled) void {}
    pub inline fn staticEvaluation(_: *Disabled, _: bool, _: bool) void {}
    pub inline fn correctionLookup(_: *Disabled, _: i32) void {}
    pub inline fn correctionEvidence(_: *Disabled, _: types.Bound, _: i32, _: i32, _: u16) void {}
    pub inline fn qsearchStandPat(_: *Disabled, _: bool, _: bool) void {}
    pub inline fn qsearchSee(_: *Disabled, _: bool) void {}
    pub inline fn qsearchDelta(_: *Disabled, _: bool) void {}
    pub inline fn reverseFutility(_: *Disabled, _: bool) void {}
    pub inline fn tablebaseHit(_: *Disabled, _: tablebase.Wdl) void {}
    pub inline fn tablebaseRootFilter(_: *Disabled, _: usize, _: usize) void {}
    pub inline fn razoring(_: *Disabled, _: bool) void {}
    pub inline fn quietFutilityCandidate(_: *Disabled) void {}
    pub inline fn lateMovePruningCandidate(_: *Disabled) void {}
    pub inline fn mainSeePruning(_: *Disabled, _: bool) void {}
    pub inline fn selectivityHistory(_: *Disabled, _: ordering.HistoryConfidence) void {}
    pub inline fn historyPruningProtection(_: *Disabled) void {}
    pub inline fn historyPruningTightening(_: *Disabled, _: bool) void {}
    pub inline fn captureFutility(_: *Disabled, _: bool, _: bool) void {}
    pub inline fn prune(_: *Disabled, _: PruneCause) void {}
    pub inline fn extension(_: *Disabled, _: ExtensionCause) void {}
    pub inline fn rootSearch(_: *Disabled, _: bool) void {}
    pub inline fn aspirationFailure(_: *Disabled, _: types.Bound) void {}
    pub inline fn nullMoveAttempt(_: *Disabled) void {}
    pub inline fn nullMoveReduction(_: *Disabled, _: u16) void {}
    pub inline fn nullMoveFailHigh(_: *Disabled) void {}
    pub inline fn nullMoveVerification(_: *Disabled, _: bool) void {}
    pub inline fn probCutNode(_: *Disabled) void {}
    pub inline fn probCutTableCutoff(_: *Disabled) void {}
    pub inline fn probCutTableSkip(_: *Disabled) void {}
    pub inline fn probCutMove(_: *Disabled) void {}
    pub inline fn probCutQuiescence(_: *Disabled, _: bool) void {}
    pub inline fn probCutVerification(_: *Disabled, _: bool) void {}
    pub inline fn lmrProbe(_: *Disabled, _: u16) void {}
    pub inline fn lmrResearch(_: *Disabled) void {}
    pub inline fn lmrAccepted(_: *Disabled) void {}
    pub inline fn lmrModifier(_: *Disabled, _: LmrModifier, _: LmrDirection) void {}
    pub inline fn lmrAdjustment(_: *Disabled, _: u16, _: u16) void {}
    pub inline fn internalIterativeReduction(_: *Disabled, _: types.NodeExpectation) void {}
    pub inline fn singularAttempt(_: *Disabled) void {}
    pub inline fn singularVerification(_: *Disabled, _: bool) void {}
    pub inline fn singularProvenanceRejection(_: *Disabled) void {}
    pub inline fn singularDoubleExtension(_: *Disabled) void {}
    pub inline fn singularMultiCutProbe(_: *Disabled) void {}
    pub inline fn singularMultiCut(_: *Disabled, _: bool) void {}
    pub inline fn exclusionMoveSkipped(_: *Disabled) void {}
    pub inline fn iteration(_: *Disabled, _: u16, _: chess.move.Move, _: types.Evidence) void {}
    pub inline fn pruning(_: *Disabled, _: u8, _: u8) void {}
};

pub const Counters = struct {
    pub const observes_move_sources = true;
    pub const observes_capture_history = true;

    main_nodes: u64 = 0,
    quiescence_nodes: u64 = 0,
    pv_nodes: u64 = 0,
    non_pv_nodes: u64 = 0,
    context_nodes: u64 = 0,
    context_in_check: u64 = 0,
    reduced_depth_intents: u64 = 0,
    extended_depth_intents: u64 = 0,
    context_nominal_depth: u64 = 0,
    context_searched_depth: u64 = 0,
    context_by_route: [route_count]u64 = @splat(0),
    context_by_arrival: [arrival_count]u64 = @splat(0),
    context_by_expectation: [expectation_count]u64 = @splat(0),
    outcomes: u64 = 0,
    outcomes_by_disposition: [disposition_count]u64 = @splat(0),
    outcomes_by_producer: [provenance_count]u64 = @splat(0),
    generated_moves: u64 = 0,
    live_history_staged_nodes: u64 = 0,
    live_history_tacticals_generated: u64 = 0,
    live_history_quiet_stages: u64 = 0,
    live_history_quiets_generated: u64 = 0,
    searched_main_moves: u64 = 0,
    searched_quiescence_moves: u64 = 0,
    main_cutoffs: u64 = 0,
    quiescence_cutoffs: u64 = 0,
    tt_probes_by_producer: [provenance_count]u64 = @splat(0),
    tt_usable_by_producer: [provenance_count]u64 = @splat(0),
    tt_stores_by_producer: [provenance_count]u64 = @splat(0),
    tt_probes_by_bound: [bound_count]u64 = @splat(0),
    tt_usable_by_bound: [bound_count]u64 = @splat(0),
    tt_stores_by_bound: [bound_count]u64 = @splat(0),
    tt_move_available: u64 = 0,
    tt_move_best: u64 = 0,
    searched_by_source: [source_count]u64 = @splat(0),
    cutoffs_by_source: [source_count]u64 = @splat(0),
    fail_high_by_index: [fail_high_count]u64 = @splat(0),
    history_rewards: u64 = 0,
    history_reward_depth: u64 = 0,
    history_penalties: u64 = 0,
    history_penalty_depth: u64 = 0,
    contextual_history_lookups: u64 = 0,
    contextual_history_nonzero: u64 = 0,
    contextual_history_rewards: u64 = 0,
    contextual_history_penalties: u64 = 0,
    contextual_history_lmr_failures: u64 = 0,
    contextual_history_lmr_positive: u64 = 0,
    contextual_history_lmr_negative: u64 = 0,
    contextual_history_pretrained_winners: u64 = 0,
    contextual_history_updates_by_disposition: [disposition_count]u64 = @splat(0),
    continuation_history_lookups: [ordering.continuation_distance_count]u64 = @splat(0),
    continuation_history_nonzero: [ordering.continuation_distance_count]u64 = @splat(0),
    continuation_history_from_check: [ordering.continuation_distance_count]u64 = @splat(0),
    continuation_history_tactical: [ordering.continuation_distance_count]u64 = @splat(0),
    continuation_history_rewards: [ordering.continuation_distance_count]u64 = @splat(0),
    continuation_history_penalties: [ordering.continuation_distance_count]u64 = @splat(0),
    continuation_history_updates_by_disposition: [ordering.continuation_distance_count][disposition_count]u64 = @splat(@splat(0)),
    continuation_history_lmr_positive: [ordering.continuation_distance_count]u64 = @splat(0),
    continuation_history_lmr_negative: [ordering.continuation_distance_count]u64 = @splat(0),
    continuation_history_pretrained_winners: [ordering.continuation_distance_count]u64 = @splat(0),
    capture_history_selections: u64 = 0,
    capture_history_nonzero: u64 = 0,
    capture_history_selections_by_consumer: [tactical_consumer_count]u64 = @splat(0),
    capture_history_rewards: u64 = 0,
    capture_history_penalties: u64 = 0,
    capture_history_updates_by_disposition: [disposition_count]u64 = @splat(0),
    prunes_by_cause: [prune_count]u64 = @splat(0),
    extensions_by_cause: [extension_count]u64 = @splat(0),
    root_searches: u64 = 0,
    aspiration_searches: u64 = 0,
    aspiration_fail_lows: u64 = 0,
    aspiration_fail_highs: u64 = 0,
    null_move_attempts: u64 = 0,
    null_move_dynamic_reductions: u64 = 0,
    null_move_extra_reduction_plies: u64 = 0,
    null_move_max_reduction: u16 = 0,
    null_move_fail_highs: u64 = 0,
    null_move_verifications: u64 = 0,
    null_move_cutoffs: u64 = 0,
    probcut_nodes: u64 = 0,
    probcut_tt_cutoffs: u64 = 0,
    probcut_tt_skips: u64 = 0,
    probcut_moves: u64 = 0,
    probcut_qsearch_passes: u64 = 0,
    probcut_verifications: u64 = 0,
    probcut_cutoffs: u64 = 0,
    lmr_probes: u64 = 0,
    lmr_reduction_plies: u64 = 0,
    lmr_multi_ply_probes: u64 = 0,
    lmr_max_reduction: u16 = 0,
    lmr_researches: u64 = 0,
    lmr_accepted: u64 = 0,
    lmr_history_protections: u64 = 0,
    lmr_modifier_protect: [lmr_modifier_count]u64 = @splat(0),
    lmr_modifier_deepen: [lmr_modifier_count]u64 = @splat(0),
    lmr_adjusted_shallower: u64 = 0,
    lmr_adjusted_deeper: u64 = 0,
    internal_iterative_reductions: u64 = 0,
    internal_iterative_reductions_by_expectation: [expectation_count]u64 = @splat(0),
    singular_attempts: u64 = 0,
    singular_extensions: u64 = 0,
    singular_double_extensions: u64 = 0,
    singular_rejections: u64 = 0,
    singular_provenance_rejections: u64 = 0,
    singular_multicut_probes: u64 = 0,
    singular_multicut_candidates: u64 = 0,
    singular_multicut_cutoffs: u64 = 0,
    exclusion_moves_skipped: u64 = 0,
    qsearch_stand_pat_nodes: u64 = 0,
    qsearch_stand_pat_cutoffs: u64 = 0,
    qsearch_stand_pat_results: u64 = 0,
    qsearch_see_candidates: u64 = 0,
    qsearch_see_prunes: u64 = 0,
    qsearch_see_check_exemptions: u64 = 0,
    static_eval_computes: u64 = 0,
    static_eval_tt_hits: u64 = 0,
    static_eval_tt_refinements: u64 = 0,
    correction_lookups: u64 = 0,
    correction_nonzero_lookups: u64 = 0,
    correction_updates_by_bound: [bound_count]u64 = @splat(0),
    correction_positive_updates: u64 = 0,
    correction_negative_updates: u64 = 0,
    correction_exact_raw_abs_error: u64 = 0,
    correction_exact_corrected_abs_error: u64 = 0,
    correction_exact_samples: u64 = 0,
    correction_max_abs: i32 = 0,
    correction_max_depth: u16 = 0,
    qsearch_delta_candidates: u64 = 0,
    qsearch_delta_prunes: u64 = 0,
    qsearch_delta_check_exemptions: u64 = 0,
    tablebase_hits: u64 = 0,
    tablebase_root_filters: u64 = 0,
    tablebase_root_moves_before: u64 = 0,
    tablebase_root_moves_kept: u64 = 0,
    tablebase_hits_by_wdl: [wdl_count]u64 = @splat(0),
    reverse_futility_candidates: u64 = 0,
    reverse_futility_cutoffs: u64 = 0,
    razoring_candidates: u64 = 0,
    razoring_triggers: u64 = 0,
    quiet_futility_candidates: u64 = 0,
    late_move_pruning_candidates: u64 = 0,
    main_see_pruning_candidates: u64 = 0,
    main_see_pruning_prunes: u64 = 0,
    selectivity_history_positive: u64 = 0,
    selectivity_history_negative: u64 = 0,
    selectivity_history_neutral: u64 = 0,
    history_pruning_protections: u64 = 0,
    history_pruning_tightenings: u64 = 0,
    history_pruning_tightened_prunes: u64 = 0,
    capture_futility_candidates: u64 = 0,
    capture_futility_prunes: u64 = 0,
    capture_futility_check_exemptions: u64 = 0,
    completed_iterations: u16 = 0,
    completed_depth: u16 = 0,
    completed_by_bound: [bound_count]u16 = @splat(0),
    completed_by_producer: [provenance_count]u16 = @splat(0),
    root_best_changes: u16 = 0,
    root_score_changes: u16 = 0,
    stop_checks: u64 = 0,
    max_nodes_between_stop_checks: u64 = 0,
    abort_node: ?u64 = null,
    pruning_candidates: u64 = 0,
    pruning_applied: u64 = 0,
    pruning_overlaps: u64 = 0,
    previous_root_best: ?chess.move.Move = null,
    previous_root_score: ?i32 = null,
    previous_stop_check: u64 = 0,

    pub fn reset(self: *Counters) void {
        self.* = .{};
    }

    pub inline fn stopCheck(self: *Counters, nodes: u64) void {
        self.stop_checks += 1;
        self.max_nodes_between_stop_checks = @max(self.max_nodes_between_stop_checks, nodes - self.previous_stop_check);
        self.previous_stop_check = nodes;
    }

    pub inline fn abort(self: *Counters, _: types.Termination, nodes: u64) void {
        self.abort_node = nodes;
    }

    pub inline fn node(self: *Counters, kind: NodeKind, pv: bool) void {
        switch (kind) {
            .main => self.main_nodes += 1,
            .quiescence => self.quiescence_nodes += 1,
        }
        if (pv) self.pv_nodes += 1 else self.non_pv_nodes += 1;
    }

    pub inline fn nodeContext(
        self: *Counters,
        kind: NodeKind,
        ply_context: types.PlyContext,
        route: types.EntryRoute,
        depth: types.DepthIntent,
        expectation: types.NodeExpectation,
    ) void {
        std.debug.assert((kind == .quiescence) == (route == .quiescence));
        self.context_nodes += 1;
        self.context_by_route[@intFromEnum(route)] += 1;
        self.context_by_arrival[@intFromEnum(ply_context.arrival)] += 1;
        self.context_by_expectation[@intFromEnum(expectation)] += 1;
        if (ply_context.in_check) self.context_in_check += 1;
        if (depth.reduction != 0) self.reduced_depth_intents += 1;
        if (depth.extension != 0) self.extended_depth_intents += 1;
        self.context_nominal_depth += depth.nominal;
        self.context_searched_depth += depth.searched();
    }

    pub inline fn nodeOutcome(self: *Counters, outcome: types.OutcomeAttribution) void {
        self.outcomes += 1;
        self.outcomes_by_disposition[@intFromEnum(outcome.disposition)] += 1;
        self.outcomes_by_producer[@intFromEnum(outcome.evidence.provenance)] += 1;
    }

    pub inline fn generated(self: *Counters, count: usize) void {
        self.generated_moves += count;
    }

    pub inline fn liveHistoryTacticals(self: *Counters, count: usize) void {
        self.live_history_staged_nodes += 1;
        self.live_history_tacticals_generated += count;
    }

    pub inline fn liveHistoryQuiets(self: *Counters, count: usize) void {
        self.live_history_quiet_stages += 1;
        self.live_history_quiets_generated += count;
    }

    pub inline fn searched(self: *Counters, kind: NodeKind) void {
        switch (kind) {
            .main => self.searched_main_moves += 1,
            .quiescence => self.searched_quiescence_moves += 1,
        }
    }

    pub inline fn cutoff(self: *Counters, kind: NodeKind) void {
        switch (kind) {
            .main => self.main_cutoffs += 1,
            .quiescence => self.quiescence_cutoffs += 1,
        }
    }

    pub inline fn ttProbe(self: *Counters, producer: types.Provenance, bound: types.Bound, usable: bool) void {
        self.tt_probes_by_producer[@intFromEnum(producer)] += 1;
        self.tt_probes_by_bound[@intFromEnum(bound)] += 1;
        if (usable) {
            self.tt_usable_by_producer[@intFromEnum(producer)] += 1;
            self.tt_usable_by_bound[@intFromEnum(bound)] += 1;
        }
    }

    pub inline fn ttStore(self: *Counters, producer: types.Provenance, bound: types.Bound) void {
        self.tt_stores_by_producer[@intFromEnum(producer)] += 1;
        self.tt_stores_by_bound[@intFromEnum(bound)] += 1;
    }

    pub inline fn ttBest(self: *Counters, recalled: bool) void {
        self.tt_move_available += 1;
        if (recalled) self.tt_move_best += 1;
    }

    pub inline fn moveSource(self: *Counters, source_value: ordering.Source) void {
        self.searched_by_source[@intFromEnum(source_value)] += 1;
    }

    pub inline fn failHigh(self: *Counters, move_index: usize, source_value: ordering.Source) void {
        self.cutoffs_by_source[@intFromEnum(source_value)] += 1;
        const bucket: FailHighBucket = switch (move_index) {
            0 => .first,
            1 => .second,
            2 => .third,
            3...7 => .fourth_to_eighth,
            else => .later,
        };
        self.fail_high_by_index[@intFromEnum(bucket)] += 1;
    }

    pub inline fn historyReward(self: *Counters, depth: u16) void {
        self.history_rewards += 1;
        self.history_reward_depth += depth;
    }

    pub inline fn historyPenalty(self: *Counters, depth: u16) void {
        self.history_penalties += 1;
        self.history_penalty_depth += depth;
    }

    pub inline fn contextualHistoryLookup(self: *Counters, nonzero: bool) void {
        self.contextual_history_lookups += 1;
        if (nonzero) self.contextual_history_nonzero += 1;
    }

    pub inline fn contextualHistoryUpdate(
        self: *Counters,
        disposition: types.NodeDisposition,
        penalties: usize,
        rewarded: bool,
    ) void {
        std.debug.assert(disposition == .exact or disposition == .cutoff);
        self.contextual_history_rewards += @intFromBool(rewarded);
        self.contextual_history_pretrained_winners += @intFromBool(!rewarded);
        self.contextual_history_penalties += penalties;
        self.contextual_history_updates_by_disposition[@intFromEnum(disposition)] += 1;
    }

    pub inline fn contextualHistoryLmrFailure(self: *Counters) void {
        self.contextual_history_penalties += 1;
        self.contextual_history_lmr_failures += 1;
    }

    pub inline fn contextualHistoryLmrFeedback(self: *Counters, positive: bool) void {
        if (positive) {
            self.contextual_history_rewards += 1;
            self.contextual_history_lmr_positive += 1;
        } else {
            self.contextual_history_penalties += 1;
            self.contextual_history_lmr_negative += 1;
        }
    }

    pub inline fn continuationHistoryLookup(
        self: *Counters,
        distance: ordering.ContinuationDistance,
        nonzero: bool,
        from_check: bool,
        tactical: bool,
    ) void {
        const index = @intFromEnum(distance);
        self.continuation_history_lookups[index] += 1;
        if (nonzero) self.continuation_history_nonzero[index] += 1;
        if (from_check) self.continuation_history_from_check[index] += 1;
        if (tactical) self.continuation_history_tactical[index] += 1;
    }

    pub inline fn continuationHistoryUpdate(
        self: *Counters,
        distance: ordering.ContinuationDistance,
        disposition: types.NodeDisposition,
        penalties: usize,
        rewarded: bool,
    ) void {
        std.debug.assert(disposition == .exact or disposition == .cutoff);
        const index = @intFromEnum(distance);
        self.continuation_history_rewards[index] += @intFromBool(rewarded);
        self.continuation_history_pretrained_winners[index] += @intFromBool(!rewarded);
        self.continuation_history_penalties[index] += penalties;
        self.continuation_history_updates_by_disposition[index][@intFromEnum(disposition)] += 1;
    }

    pub inline fn continuationHistoryLmrFeedback(
        self: *Counters,
        distance: ordering.ContinuationDistance,
        positive: bool,
    ) void {
        const index = @intFromEnum(distance);
        if (positive) {
            self.continuation_history_rewards[index] += 1;
            self.continuation_history_lmr_positive[index] += 1;
        } else {
            self.continuation_history_penalties[index] += 1;
            self.continuation_history_lmr_negative[index] += 1;
        }
    }

    pub inline fn captureHistorySelection(
        self: *Counters,
        consumer: TacticalConsumer,
        nonzero: bool,
    ) void {
        self.capture_history_selections += 1;
        self.capture_history_selections_by_consumer[@intFromEnum(consumer)] += 1;
        if (nonzero) self.capture_history_nonzero += 1;
    }

    pub inline fn captureHistoryUpdate(
        self: *Counters,
        disposition: types.NodeDisposition,
        penalties: usize,
    ) void {
        std.debug.assert(disposition == .exact or disposition == .cutoff);
        self.capture_history_rewards += 1;
        self.capture_history_penalties += penalties;
        self.capture_history_updates_by_disposition[@intFromEnum(disposition)] += 1;
    }

    pub inline fn lmrHistoryProtection(self: *Counters) void {
        self.lmr_history_protections += 1;
    }

    pub inline fn lmrModifier(
        self: *Counters,
        modifier: LmrModifier,
        direction: LmrDirection,
    ) void {
        const index = @intFromEnum(modifier);
        if (direction == .protect)
            self.lmr_modifier_protect[index] += 1
        else
            self.lmr_modifier_deepen[index] += 1;
    }

    pub inline fn lmrAdjustment(self: *Counters, base: u16, adjusted: u16) void {
        if (adjusted < base) self.lmr_adjusted_shallower += 1;
        if (adjusted > base) self.lmr_adjusted_deeper += 1;
    }

    pub inline fn staticEvaluation(self: *Counters, cached: bool, refined: bool) void {
        if (cached)
            self.static_eval_tt_hits += 1
        else
            self.static_eval_computes += 1;
        if (refined) self.static_eval_tt_refinements += 1;
    }

    /// Observe the correction available before a node consumes it. This is
    /// diagnostic-only and compiles away with `Disabled`.
    pub inline fn correctionLookup(self: *Counters, adjustment: i32) void {
        self.correction_lookups += 1;
        if (adjustment != 0) self.correction_nonzero_lookups += 1;
        self.correction_max_abs = @max(self.correction_max_abs, @as(i32, @intCast(@abs(adjustment))));
    }

    /// Measure online prediction quality before the current observation is
    /// learned. Exact bounds provide a two-sided residual; lower and upper
    /// bounds are still counted for population and direction but cannot supply
    /// an absolute-error oracle.
    pub inline fn correctionEvidence(
        self: *Counters,
        bound: types.Bound,
        delta: i32,
        prior: i32,
        depth: u16,
    ) void {
        self.correction_updates_by_bound[@intFromEnum(bound)] += 1;
        if (delta > 0) self.correction_positive_updates += 1;
        if (delta < 0) self.correction_negative_updates += 1;
        self.correction_max_depth = @max(self.correction_max_depth, depth);
        if (bound == .exact) {
            self.correction_exact_samples += 1;
            self.correction_exact_raw_abs_error += @intCast(@abs(@as(i64, delta)));
            self.correction_exact_corrected_abs_error += @intCast(@abs(@as(i64, delta) - prior));
        }
    }

    pub inline fn qsearchStandPat(self: *Counters, caused_cutoff: bool, final: bool) void {
        self.qsearch_stand_pat_nodes += 1;
        if (caused_cutoff) self.qsearch_stand_pat_cutoffs += 1;
        if (final) self.qsearch_stand_pat_results += 1;
    }

    pub inline fn qsearchSee(self: *Counters, checking_exemption: bool) void {
        self.qsearch_see_candidates += 1;
        if (checking_exemption)
            self.qsearch_see_check_exemptions += 1
        else
            self.qsearch_see_prunes += 1;
    }

    pub inline fn qsearchDelta(self: *Counters, checking_exemption: bool) void {
        self.qsearch_delta_candidates += 1;
        if (checking_exemption)
            self.qsearch_delta_check_exemptions += 1
        else
            self.qsearch_delta_prunes += 1;
    }

    pub inline fn tablebaseRootFilter(self: *Counters, before: usize, kept: usize) void {
        self.tablebase_root_filters += 1;
        self.tablebase_root_moves_before += before;
        self.tablebase_root_moves_kept += kept;
    }

    pub inline fn tablebaseHit(self: *Counters, wdl: tablebase.Wdl) void {
        self.tablebase_hits += 1;
        self.tablebase_hits_by_wdl[@intFromEnum(wdl)] += 1;
    }

    pub inline fn reverseFutility(self: *Counters, caused_cutoff: bool) void {
        self.reverse_futility_candidates += 1;
        if (caused_cutoff) self.reverse_futility_cutoffs += 1;
    }

    pub inline fn razoring(self: *Counters, triggered: bool) void {
        self.razoring_candidates += 1;
        if (triggered) self.razoring_triggers += 1;
    }

    pub inline fn quietFutilityCandidate(self: *Counters) void {
        self.quiet_futility_candidates += 1;
    }

    pub inline fn lateMovePruningCandidate(self: *Counters) void {
        self.late_move_pruning_candidates += 1;
    }

    /// Mirrors `qsearchSee`'s dedicated accounting: main search shares the
    /// `.see` `PruneCause` tag with quiescence, so this field lets each phase
    /// be audited independently of that shared aggregate.
    pub inline fn mainSeePruning(self: *Counters, pruned: bool) void {
        self.main_see_pruning_candidates += 1;
        if (pruned) self.main_see_pruning_prunes += 1;
    }

    pub inline fn selectivityHistory(self: *Counters, confidence: ordering.HistoryConfidence) void {
        switch (confidence) {
            .positive => self.selectivity_history_positive += 1,
            .negative => self.selectivity_history_negative += 1,
            .neutral => self.selectivity_history_neutral += 1,
        }
    }

    pub inline fn historyPruningProtection(self: *Counters) void {
        self.history_pruning_protections += 1;
    }

    pub inline fn historyPruningTightening(self: *Counters, caused_prune: bool) void {
        self.history_pruning_tightenings += 1;
        if (caused_prune) self.history_pruning_tightened_prunes += 1;
    }

    pub inline fn captureFutility(self: *Counters, pruned: bool, checking_exemption: bool) void {
        self.capture_futility_candidates += 1;
        if (checking_exemption)
            self.capture_futility_check_exemptions += 1
        else if (pruned)
            self.capture_futility_prunes += 1;
    }

    pub inline fn prune(self: *Counters, cause: PruneCause) void {
        self.prunes_by_cause[@intFromEnum(cause)] += 1;
    }

    pub inline fn extension(self: *Counters, cause: ExtensionCause) void {
        self.extensions_by_cause[@intFromEnum(cause)] += 1;
    }

    pub inline fn rootSearch(self: *Counters, aspirated: bool) void {
        self.root_searches += 1;
        if (aspirated) self.aspiration_searches += 1;
    }

    pub inline fn aspirationFailure(self: *Counters, bound: types.Bound) void {
        switch (bound) {
            .upper => self.aspiration_fail_lows += 1,
            .lower => self.aspiration_fail_highs += 1,
            .exact => unreachable,
        }
    }

    pub inline fn nullMoveAttempt(self: *Counters) void {
        self.null_move_attempts += 1;
    }

    pub inline fn nullMoveReduction(self: *Counters, reduction: u16) void {
        std.debug.assert(reduction >= 2);
        self.null_move_dynamic_reductions += 1;
        self.null_move_extra_reduction_plies += reduction - 2;
        self.null_move_max_reduction = @max(self.null_move_max_reduction, reduction);
    }

    pub inline fn nullMoveFailHigh(self: *Counters) void {
        self.null_move_fail_highs += 1;
    }

    pub inline fn nullMoveVerification(self: *Counters, accepted: bool) void {
        self.null_move_verifications += 1;
        if (accepted) self.null_move_cutoffs += 1;
    }

    pub inline fn probCutNode(self: *Counters) void {
        self.probcut_nodes += 1;
    }

    pub inline fn probCutTableCutoff(self: *Counters) void {
        self.probcut_tt_cutoffs += 1;
        self.probcut_cutoffs += 1;
    }

    pub inline fn probCutTableSkip(self: *Counters) void {
        self.probcut_tt_skips += 1;
    }

    pub inline fn probCutMove(self: *Counters) void {
        self.probcut_moves += 1;
    }

    pub inline fn probCutQuiescence(self: *Counters, passed: bool) void {
        if (passed) self.probcut_qsearch_passes += 1;
    }

    pub inline fn probCutVerification(self: *Counters, accepted: bool) void {
        self.probcut_verifications += 1;
        if (accepted) self.probcut_cutoffs += 1;
    }

    pub inline fn lmrProbe(self: *Counters, reduction: u16) void {
        std.debug.assert(reduction != 0);
        self.lmr_probes += 1;
        self.lmr_reduction_plies += reduction;
        if (reduction > 1) self.lmr_multi_ply_probes += 1;
        self.lmr_max_reduction = @max(self.lmr_max_reduction, reduction);
    }

    pub inline fn lmrResearch(self: *Counters) void {
        self.lmr_researches += 1;
    }

    pub inline fn lmrAccepted(self: *Counters) void {
        self.lmr_accepted += 1;
    }

    pub inline fn internalIterativeReduction(self: *Counters, expectation: types.NodeExpectation) void {
        self.internal_iterative_reductions += 1;
        self.internal_iterative_reductions_by_expectation[@intFromEnum(expectation)] += 1;
    }

    pub inline fn singularAttempt(self: *Counters) void {
        self.singular_attempts += 1;
    }

    pub inline fn singularVerification(self: *Counters, extended: bool) void {
        if (extended)
            self.singular_extensions += 1
        else
            self.singular_rejections += 1;
    }

    pub inline fn singularProvenanceRejection(self: *Counters) void {
        self.singular_provenance_rejections += 1;
    }

    pub inline fn singularDoubleExtension(self: *Counters) void {
        self.singular_double_extensions += 1;
    }

    pub inline fn singularMultiCutProbe(self: *Counters) void {
        self.singular_multicut_probes += 1;
    }

    pub inline fn singularMultiCut(self: *Counters, did_cutoff: bool) void {
        self.singular_multicut_candidates += 1;
        if (did_cutoff) self.singular_multicut_cutoffs += 1;
    }

    pub inline fn exclusionMoveSkipped(self: *Counters) void {
        self.exclusion_moves_skipped += 1;
    }

    pub inline fn iteration(self: *Counters, depth: u16, best: chess.move.Move, result: types.Evidence) void {
        if (self.previous_root_best) |previous| {
            if (previous.raw() != best.raw()) self.root_best_changes += 1;
        }
        if (self.previous_root_score) |previous| {
            if (previous != result.value.raw()) self.root_score_changes += 1;
        }
        self.previous_root_best = best;
        self.previous_root_score = result.value.raw();
        self.completed_iterations += 1;
        self.completed_depth = depth;
        self.completed_by_bound[@intFromEnum(result.bound)] += 1;
        self.completed_by_producer[@intFromEnum(result.provenance)] += 1;
    }

    pub inline fn pruning(self: *Counters, candidate_mask: u8, applied_mask: u8) void {
        self.pruning_candidates += @popCount(candidate_mask);
        self.pruning_applied += @popCount(applied_mask);
        if (@popCount(candidate_mask) > 1) self.pruning_overlaps += 1;
    }
};

test "diagnostic overlap and root stability counters describe without deciding" {
    var counters: Counters = .{};
    counters.pruning(0b101, 0b001);
    counters.rootSearch(true);
    counters.aspirationFailure(.upper);
    counters.aspirationFailure(.lower);
    counters.nullMoveAttempt();
    counters.nullMoveReduction(4);
    counters.nullMoveFailHigh();
    counters.nullMoveVerification(true);
    counters.probCutNode();
    counters.probCutTableCutoff();
    counters.probCutTableSkip();
    counters.probCutMove();
    counters.probCutQuiescence(true);
    counters.probCutVerification(true);
    counters.prune(.probcut);
    counters.prune(.probcut);
    counters.prune(.null_move);
    counters.lmrProbe(2);
    counters.lmrResearch();
    counters.lmrAccepted();
    counters.internalIterativeReduction(.cut);
    counters.singularAttempt();
    counters.singularVerification(true);
    counters.singularVerification(false);
    counters.singularProvenanceRejection();
    counters.singularDoubleExtension();
    counters.singularMultiCutProbe();
    counters.singularMultiCut(true);
    counters.exclusionMoveSkipped();
    counters.moveSource(.tt);
    counters.failHigh(4, .tt);
    counters.historyReward(5);
    counters.historyPenalty(5);
    counters.contextualHistoryLookup(false);
    counters.contextualHistoryLookup(true);
    counters.contextualHistoryUpdate(.exact, 2, true);
    counters.contextualHistoryUpdate(.cutoff, 3, true);
    counters.contextualHistoryLmrFailure();
    counters.contextualHistoryLmrFeedback(true);
    counters.contextualHistoryLmrFeedback(false);
    counters.continuationHistoryLookup(.two, false, true, false);
    counters.continuationHistoryLookup(.two, true, false, true);
    counters.continuationHistoryUpdate(.two, .exact, 2, true);
    counters.continuationHistoryUpdate(.four, .cutoff, 3, true);
    counters.continuationHistoryLmrFeedback(.two, true);
    counters.continuationHistoryLmrFeedback(.two, false);
    counters.captureHistorySelection(.main, false);
    counters.captureHistorySelection(.quiescence, true);
    counters.captureHistorySelection(.probcut, false);
    counters.captureHistoryUpdate(.exact, 2);
    counters.captureHistoryUpdate(.cutoff, 1);
    counters.lmrHistoryProtection();
    counters.lmrModifier(.improving, .protect);
    counters.lmrModifier(.tt_move, .deepen);
    counters.lmrAdjustment(2, 1);
    counters.lmrAdjustment(2, 3);
    counters.staticEvaluation(false, false);
    counters.staticEvaluation(true, true);
    counters.correctionLookup(0);
    counters.correctionLookup(-12);
    counters.correctionEvidence(.exact, 40, 10, 8);
    counters.correctionEvidence(.lower, 20, 5, 6);
    counters.correctionEvidence(.upper, -30, -4, 7);
    counters.qsearchStandPat(true, false);
    counters.qsearchStandPat(false, true);
    counters.qsearchSee(false);
    counters.qsearchSee(true);
    counters.qsearchDelta(false);
    counters.qsearchDelta(true);
    counters.reverseFutility(true);
    counters.razoring(true);
    counters.quietFutilityCandidate();
    counters.lateMovePruningCandidate();
    counters.mainSeePruning(true);
    counters.selectivityHistory(.positive);
    counters.selectivityHistory(.negative);
    counters.selectivityHistory(.neutral);
    counters.historyPruningProtection();
    counters.historyPruningTightening(true);
    counters.captureFutility(true, false);
    counters.captureFutility(false, true);
    counters.prune(.razoring);
    counters.prune(.futility);
    counters.prune(.late_move);
    counters.iteration(1, chess.move.Move.normal(.e2, .e4), .{
        .value = @import("../score.zig").Score.zero,
        .bound = .exact,
        .provenance = .full_search,
    });
    counters.iteration(2, chess.move.Move.normal(.d2, .d4), .{
        .value = @import("../score.zig").Score.fromOrdinary(10).?,
        .bound = .exact,
        .provenance = .full_search,
    });
    try @import("std").testing.expectEqual(@as(u64, 2), counters.pruning_candidates);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.pruning_overlaps);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.aspiration_searches);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.aspiration_fail_lows);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.aspiration_fail_highs);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.null_move_attempts);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.null_move_dynamic_reductions);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.null_move_extra_reduction_plies);
    try @import("std").testing.expectEqual(@as(u16, 4), counters.null_move_max_reduction);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.null_move_cutoffs);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.probcut_nodes);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.probcut_moves);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.probcut_qsearch_passes);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.probcut_verifications);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.probcut_tt_cutoffs);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.probcut_tt_skips);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.probcut_cutoffs);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.prunes_by_cause[@intFromEnum(PruneCause.probcut)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.lmr_probes);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.lmr_reduction_plies);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.lmr_multi_ply_probes);
    try @import("std").testing.expectEqual(@as(u16, 2), counters.lmr_max_reduction);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.lmr_researches);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.lmr_accepted);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.internal_iterative_reductions);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.singular_attempts);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.singular_extensions);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.singular_rejections);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.singular_provenance_rejections);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.singular_double_extensions);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.singular_multicut_probes);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.singular_multicut_candidates);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.singular_multicut_cutoffs);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.exclusion_moves_skipped);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.searched_by_source[@intFromEnum(ordering.Source.tt)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.fail_high_by_index[@intFromEnum(FailHighBucket.fourth_to_eighth)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.history_rewards);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.history_penalties);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.contextual_history_lookups);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.contextual_history_nonzero);
    try @import("std").testing.expectEqual(@as(u64, 3), counters.contextual_history_rewards);
    try @import("std").testing.expectEqual(@as(u64, 7), counters.contextual_history_penalties);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.contextual_history_lmr_failures);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.contextual_history_lmr_positive);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.contextual_history_lmr_negative);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.continuation_history_lookups[@intFromEnum(ordering.ContinuationDistance.two)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.continuation_history_nonzero[@intFromEnum(ordering.ContinuationDistance.two)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.continuation_history_from_check[@intFromEnum(ordering.ContinuationDistance.two)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.continuation_history_tactical[@intFromEnum(ordering.ContinuationDistance.two)]);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.continuation_history_rewards[@intFromEnum(ordering.ContinuationDistance.two)]);
    try @import("std").testing.expectEqual(@as(u64, 3), counters.continuation_history_penalties[@intFromEnum(ordering.ContinuationDistance.two)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.continuation_history_updates_by_disposition[@intFromEnum(ordering.ContinuationDistance.four)][@intFromEnum(types.NodeDisposition.cutoff)]);
    try @import("std").testing.expectEqual(@as(u64, 3), counters.capture_history_selections);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.capture_history_nonzero);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.capture_history_selections_by_consumer[@intFromEnum(TacticalConsumer.main)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.capture_history_selections_by_consumer[@intFromEnum(TacticalConsumer.quiescence)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.capture_history_selections_by_consumer[@intFromEnum(TacticalConsumer.probcut)]);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.capture_history_rewards);
    try @import("std").testing.expectEqual(@as(u64, 3), counters.capture_history_penalties);
    try @import("std").testing.expectEqual(
        @as(u64, 1),
        counters.capture_history_updates_by_disposition[@intFromEnum(types.NodeDisposition.exact)],
    );
    try @import("std").testing.expectEqual(
        @as(u64, 1),
        counters.capture_history_updates_by_disposition[@intFromEnum(types.NodeDisposition.cutoff)],
    );
    try @import("std").testing.expectEqual(
        @as(u64, 1),
        counters.contextual_history_updates_by_disposition[@intFromEnum(types.NodeDisposition.exact)],
    );
    try @import("std").testing.expectEqual(
        @as(u64, 1),
        counters.contextual_history_updates_by_disposition[@intFromEnum(types.NodeDisposition.cutoff)],
    );
    try @import("std").testing.expectEqual(
        @as(u64, 0),
        counters.contextual_history_updates_by_disposition[@intFromEnum(types.NodeDisposition.fail_low)],
    );
    try @import("std").testing.expectEqual(@as(u64, 1), counters.lmr_history_protections);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.lmr_modifier_protect[@intFromEnum(LmrModifier.improving)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.lmr_modifier_deepen[@intFromEnum(LmrModifier.tt_move)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.lmr_adjusted_shallower);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.lmr_adjusted_deeper);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.qsearch_stand_pat_nodes);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.qsearch_stand_pat_cutoffs);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.qsearch_stand_pat_results);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.qsearch_see_candidates);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.qsearch_see_prunes);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.qsearch_see_check_exemptions);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.static_eval_computes);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.static_eval_tt_hits);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.static_eval_tt_refinements);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.correction_lookups);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.correction_nonzero_lookups);
    try @import("std").testing.expectEqual(@as(i32, 12), counters.correction_max_abs);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.correction_updates_by_bound[@intFromEnum(types.Bound.exact)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.correction_updates_by_bound[@intFromEnum(types.Bound.lower)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.correction_updates_by_bound[@intFromEnum(types.Bound.upper)]);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.correction_positive_updates);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.correction_negative_updates);
    try @import("std").testing.expectEqual(@as(u64, 40), counters.correction_exact_raw_abs_error);
    try @import("std").testing.expectEqual(@as(u64, 30), counters.correction_exact_corrected_abs_error);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.correction_exact_samples);
    try @import("std").testing.expectEqual(@as(u16, 8), counters.correction_max_depth);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.qsearch_delta_candidates);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.qsearch_delta_prunes);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.qsearch_delta_check_exemptions);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.reverse_futility_candidates);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.reverse_futility_cutoffs);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.razoring_candidates);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.razoring_triggers);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.quiet_futility_candidates);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.late_move_pruning_candidates);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.main_see_pruning_candidates);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.main_see_pruning_prunes);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.selectivity_history_positive);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.selectivity_history_negative);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.selectivity_history_neutral);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.history_pruning_protections);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.history_pruning_tightenings);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.history_pruning_tightened_prunes);
    try @import("std").testing.expectEqual(@as(u64, 2), counters.capture_futility_candidates);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.capture_futility_prunes);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.capture_futility_check_exemptions);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.prunes_by_cause[@intFromEnum(PruneCause.razoring)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.prunes_by_cause[@intFromEnum(PruneCause.futility)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.prunes_by_cause[@intFromEnum(PruneCause.late_move)]);
    try @import("std").testing.expectEqual(@as(u64, 1), counters.prunes_by_cause[@intFromEnum(PruneCause.null_move)]);
    try @import("std").testing.expectEqual(@as(u16, 1), counters.root_best_changes);
    try @import("std").testing.expectEqual(@as(u16, 1), counters.root_score_changes);
}
