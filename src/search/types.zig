//! Search result, limit, provenance, and caller-owned worker values.
const std = @import("std");
const chess = @import("../chess/root.zig");
const score = @import("../score.zig");
const search_build_options = @import("search_build_options");

pub const Bound = enum {
    exact,
    lower,
    upper,
};

/// Names the producer whose evidence may reach a consumer. Future pruning
/// mechanisms receive distinct variants instead of inheriting full-search
/// authority merely because they also return a score.
pub const Provenance = enum {
    terminal,
    static_eval,
    stand_pat,
    qsearch_move,
    pvs_probe,
    full_search,
    tt_exact,
    tt_bound,
    fallback,
    reduced_search,
    null_move,
    probcut,
    speculative_cutoff,
    exclusion_search,
    tablebase,
    /// Proved from mate distance alone: the node's window cannot contain any
    /// reachable score, because a mate cannot be delivered sooner than the next
    /// ply nor suffered sooner than this one. It carries a true bound and no
    /// position knowledge, so it never gains ordinary search authority.
    mate_distance,
};

pub const Evidence = struct {
    value: score.Score,
    bound: Bound,
    provenance: Provenance,
};

/// Describes why a recursive search entered a node. Routes are factual
/// attribution only; Step 5.1.4.1 gives them no policy authority.
pub const EntryRoute = enum {
    root,
    first_move,
    scout,
    pv_research,
    reduced_probe,
    reduction_research,
    null_probe,
    null_verification,
    singular_probe,
    probcut_probe,
    quiescence,
};

/// Separates the nominal child horizon from extensions and reductions. Search
/// composes these fields only through `searched()` while completed root depth
/// remains nominal.
pub const DepthIntent = struct {
    nominal: u16,
    extension: u16 = 0,
    reduction: u16 = 0,

    pub fn full(nominal: u16) DepthIntent {
        return .{ .nominal = nominal };
    }

    pub fn reduced(nominal: u16, reduction: u16) DepthIntent {
        return .{ .nominal = nominal, .reduction = reduction };
    }

    pub fn extended(nominal: u16, extension: u16) DepthIntent {
        return .{ .nominal = nominal, .extension = extension };
    }

    pub fn searched(self: DepthIntent) u16 {
        return (self.nominal +| self.extension) -| self.reduction;
    }
};

pub const Arrival = enum { root, move, null_move };

/// Worker-local chess-ply context. Arrivals preserve exact encoded moves,
/// including castling, en-passant and promotion kinds. `excluded_move` controls
/// only an owning singular probe; the context never supplies score evidence.
pub const PlyContext = struct {
    arrival: Arrival,
    previous_move: chess.move.Move,
    /// Persistent facts about the move that produced this position. Historical
    /// continuation consumers must not reconstruct these from the current
    /// board because the mover may since have moved or been captured.
    previous_piece: chess.types.PieceType,
    previous_to: chess.types.Square,
    previous_from_check: bool,
    previous_tactical: bool,
    excluded_move: chess.move.Move,
    in_check: bool,

    pub fn root(in_check: bool) PlyContext {
        return .{
            .arrival = .root,
            .previous_move = .none,
            .previous_piece = .none,
            .previous_to = .a1,
            .previous_from_check = false,
            .previous_tactical = false,
            .excluded_move = .none,
            .in_check = in_check,
        };
    }

    pub fn afterMove(
        previous_move: chess.move.Move,
        previous_piece: chess.types.PieceType,
        previous_from_check: bool,
        previous_tactical: bool,
        in_check: bool,
    ) PlyContext {
        std.debug.assert(previous_move.isChessMove());
        std.debug.assert(previous_piece.isPiece());
        return .{
            .arrival = .move,
            .previous_move = previous_move,
            .previous_piece = previous_piece,
            .previous_to = previous_move.to(),
            .previous_from_check = previous_from_check,
            .previous_tactical = previous_tactical,
            .excluded_move = .none,
            .in_check = in_check,
        };
    }

    pub fn afterNull(in_check: bool) PlyContext {
        return .{
            .arrival = .null_move,
            .previous_move = .null_move,
            .previous_piece = .none,
            .previous_to = .a1,
            .previous_from_check = false,
            .previous_tactical = false,
            .excluded_move = .none,
            .in_check = in_check,
        };
    }

    pub fn withExcluded(self: PlyContext, excluded_move: chess.move.Move) PlyContext {
        std.debug.assert(excluded_move.isChessMove());
        var result = self;
        result.excluded_move = excluded_move;
        return result;
    }
};

pub const NodeDisposition = enum { fail_low, exact, cutoff };

/// Prospective alpha-beta node role. This is caller-supplied search context,
/// not evidence: it cannot establish a score, bound, cutoff or TT record.
/// Non-principal child roles invert under negamax because a likely cutoff for
/// one side is a likely fail-low (`all`) for the opponent.
pub const NodeExpectation = enum {
    principal,
    cut,
    all,

    pub fn isPrincipal(self: NodeExpectation) bool {
        return self == .principal;
    }

    pub fn child(self: NodeExpectation, principal_child: bool) NodeExpectation {
        if (principal_child) {
            std.debug.assert(self == .principal);
            return .principal;
        }
        if (self == .cut) return .all;
        return .cut;
    }
};

/// Typed, read-only attribution for a completed node. Consumers can distinguish
/// route, prospective depth and evidence producer without inferring authority
/// from a raw numeric score.
pub const OutcomeAttribution = struct {
    route: EntryRoute,
    depth: DepthIntent,
    expectation: NodeExpectation,
    disposition: NodeDisposition,
    evidence: Evidence,

    pub fn init(
        route: EntryRoute,
        depth: DepthIntent,
        expectation: NodeExpectation,
        result: Evidence,
    ) OutcomeAttribution {
        return .{
            .route = route,
            .depth = depth,
            .expectation = expectation,
            .disposition = switch (result.bound) {
                .upper => .fail_low,
                .exact => .exact,
                .lower => .cutoff,
            },
            .evidence = result,
        };
    }
};

/// Locality carried by searched evidence. A numeric bound never widens this
/// scope when it is returned, negated, or stored.
pub const EvidenceScope = enum {
    ordinary,
    restricted_root,
    exclusion,
    null_probe,
    null_verification,
    probcut,
    history_local,
    quiescence,
};

pub const EvalTrend = struct {
    current: i32,
    previous: i32,

    pub fn improving(self: EvalTrend) bool {
        return self.current > self.previous;
    }
};

/// Behavior-neutral view of values which existing static consumers currently
/// derive independently. Missing evidence remains optional rather than zero.
pub const StaticFacts = struct {
    raw_hce: ?i32 = null,
    raw_hce_cached: bool = false,
    ordinary_tt_refinement: ?i32 = null,
    corrected: ?i32 = null,
    own_trend: ?EvalTrend = null,
    opponent_trend: ?EvalTrend = null,
};

/// Authenticated TT facts retain the stored producer. The present TT format
/// has no independent PV-origin bit, so `pv_origin` is deliberately unknown.
pub const TtFacts = struct {
    authenticated: bool = false,
    chess_move: ?chess.move.Move = null,
    value: ?score.Score = null,
    static_eval: ?score.Score = null,
    bound: ?Bound = null,
    producer: ?Provenance = null,
    stored_depth: ?u8 = null,
    generation: ?u8 = null,
    current_generation: ?u8 = null,
    fresh: ?bool = null,
    scope_compatible: bool = false,
    cutoff_authorized: bool = false,
    pv_origin: ?bool = null,
};

pub const WindowFacts = struct {
    alpha: i32,
    beta: i32,
    width: u32,
    root_reference_width: ?u32,
    expectation: NodeExpectation,

    pub fn init(alpha: i32, beta: i32, root_reference_width: ?u32, expectation: NodeExpectation) WindowFacts {
        std.debug.assert(alpha < beta);
        return .{
            .alpha = alpha,
            .beta = beta,
            .width = @intCast(@as(i64, beta) - alpha),
            .root_reference_width = root_reference_width,
            .expectation = expectation,
        };
    }
};

pub const MoveFacts = struct {
    chess_move: chess.move.Move,
    resulting_piece: chess.types.PieceType,
    victim: chess.types.PieceType,
    tactical: bool,
    tt_move: bool,
    evasion: bool,
    gives_check: bool,
    selected_ordinal: u16,
    searched_before: u16,
};

/// One live ordering relation and its optional observation-only outcome cell.
/// The key names the exact production table cell; missing context remains null.
pub const HistoryRelation = struct {
    key: u64,
    value: i16,
    shadow: ?OutcomeSupportCell = null,
};

pub const HistoryObservationPoint = enum { ranking, depth };

/// One history snapshot from either the instant a quiet is ranked or the
/// later per-move depth decision. Continuation slots retain their shared-table
/// aliases; the explicit point prevents the two lifetimes being conflated.
pub const HistoryFacts = struct {
    point: HistoryObservationPoint,
    main: HistoryRelation,
    reply: ?HistoryRelation = null,
    continuations: [3]?HistoryRelation = @splat(null),
};

pub const NodeDepthPlan = struct {
    requested: DepthIntent,
    active: DepthIntent,
    admitted_check_extension: u16,
    admitted_iir_reduction: u16,
    ply_capacity: u16,
    scope: EvidenceScope = .ordinary,
};

/// Observes the horizons selected by the accepted search. It does not yet
/// replace any depth, pruning, or dispatch formula.
pub const MoveDepthPlan = struct {
    full: DepthIntent,
    probe: DepthIntent,
    prune_depth: u16,
    selected_ordinal: u16,
    searched_before: u16,
    singular_extension: u16,
    child_check_extension: u16 = 0,
    proposed_reduction: u16,
    shallow_omitted: bool,
};

pub const Verification = enum { not_required, reduced_only, completed };

pub const SearchOutcome = struct {
    attribution: ?OutcomeAttribution,
    scope: EvidenceScope,
    requested_horizon: u16,
    searched_horizon: u16,
    verification: Verification,
    omitted_siblings: bool,
    complete: bool,
    original_producer: ?Provenance = null,
    /// Some searched sibling was only a reduced probe. This is distinct from
    /// `omitted_siblings`, which means a legal sibling was never searched, and
    /// from `verification`, which describes how this result itself was
    /// established. An exact or cutoff result keeps its winner's horizon and
    /// reports probe-only siblings here rather than shortening that horizon.
    reduced_siblings: bool = false,
};

/// Shadow admission is counted per node depth so the admitted/refused profile
/// of the paired relation stays measurable without a temporary probe. Depths
/// at or above the last bucket saturate into it.
pub const shadow_depth_buckets = 17;

/// Signed outcome and support are updated as one diagnostic sample. Support is
/// a saturated admitted-update count, not a probability or recency estimate.
pub const OutcomeSupportCell = struct {
    value: i16 = 0,
    support: u8 = 0,

    pub const limit: i32 = 16 * 1024;

    pub fn apply(self: *OutcomeSupportCell, bonus_unbounded: i32) void {
        const bonus = std.math.clamp(bonus_unbounded, -limit, limit);
        const magnitude: i32 = @intCast(@abs(bonus));
        const current: i32 = self.value;
        const next = current + bonus - @divTrunc(current * magnitude, limit);
        std.debug.assert(next >= -limit and next <= limit);
        self.value = @intCast(next);
        self.support +|= 1;
    }
};

pub const search_evidence_observation_compiled = search_build_options.search_evidence_observation;
const observation_slot_count = 4096;

fn observationIndex(key: u64) u64 {
    // Mix every encoded relation component before taking the bounded-table
    // index. Linear probing still drops after eight occupied, unequal keys;
    // it never merges their samples.
    var mixed = key;
    mixed ^= mixed >> 30;
    mixed *%= 0xbf58476d1ce4e5b9;
    mixed ^= mixed >> 27;
    mixed *%= 0x94d049bb133111eb;
    mixed ^= mixed >> 31;
    return mixed & (observation_slot_count - 1);
}

const ObservationStorage = if (search_evidence_observation_compiled) struct {
    const Entry = struct {
        key: u64 = 0,
        sample: OutcomeSupportCell = .{},
    };

    entries: [observation_slot_count]Entry = @splat(.{}),
    static_facts: u64 = 0,
    tt_facts: u64 = 0,
    windows: u64 = 0,
    node_plans: u64 = 0,
    move_plans: u64 = 0,
    history_facts: u64 = 0,
    ranking_history_facts: u64 = 0,
    depth_history_facts: u64 = 0,
    outcomes: u64 = 0,
    qsearch_outcomes_with_omissions: u64 = 0,
    reduced_only_outcomes: u64 = 0,
    reduced_sibling_outcomes: u64 = 0,
    shadow_admitted: u64 = 0,
    shadow_refused: u64 = 0,
    shadow_admitted_by_depth: [shadow_depth_buckets]u64 = @splat(0),
    shadow_refused_by_depth: [shadow_depth_buckets]u64 = @splat(0),
    updates: u64 = 0,
    dropped: u64 = 0,
    last_static: ?StaticFacts = null,
    last_tt: ?TtFacts = null,
    last_window: ?WindowFacts = null,
    last_node_plan: ?NodeDepthPlan = null,
    last_move_facts: ?MoveFacts = null,
    last_move_plan: ?MoveDepthPlan = null,
    last_history: ?HistoryFacts = null,
    last_ranking_history: ?HistoryFacts = null,
    last_depth_history: ?HistoryFacts = null,
    last_outcome: ?SearchOutcome = null,
} else struct {};

pub const SearchEvidenceSummary = struct {
    static_facts: u64 = 0,
    tt_facts: u64 = 0,
    windows: u64 = 0,
    node_plans: u64 = 0,
    move_plans: u64 = 0,
    history_facts: u64 = 0,
    ranking_history_facts: u64 = 0,
    depth_history_facts: u64 = 0,
    outcomes: u64 = 0,
    qsearch_outcomes_with_omissions: u64 = 0,
    reduced_only_outcomes: u64 = 0,
    reduced_sibling_outcomes: u64 = 0,
    shadow_admitted: u64 = 0,
    shadow_refused: u64 = 0,
    shadow_admitted_by_depth: [shadow_depth_buckets]u64 = @splat(0),
    shadow_refused_by_depth: [shadow_depth_buckets]u64 = @splat(0),
    updates: u64 = 0,
    dropped: u64 = 0,
};

pub const SearchEvidenceSnapshot = struct {
    static_facts: ?StaticFacts = null,
    tt_facts: ?TtFacts = null,
    window: ?WindowFacts = null,
    node_plan: ?NodeDepthPlan = null,
    move_facts: ?MoveFacts = null,
    move_plan: ?MoveDepthPlan = null,
    history: ?HistoryFacts = null,
    ranking_history: ?HistoryFacts = null,
    depth_history: ?HistoryFacts = null,
    outcome: ?SearchOutcome = null,
};

/// Build-time-erased worker-local Step-6.5.9 observation state. Keys are
/// produced by ordering from already validated chess/context facts.
pub const SearchEvidenceObservation = struct {
    storage: ObservationStorage = .{},

    pub fn reset(self: *SearchEvidenceObservation) void {
        self.* = .{};
    }

    pub fn observeStatic(self: *SearchEvidenceObservation, facts: StaticFacts) void {
        if (comptime search_evidence_observation_compiled) {
            self.storage.static_facts += 1;
            self.storage.last_static = facts;
        }
    }

    pub fn observeTt(self: *SearchEvidenceObservation, facts: TtFacts) void {
        if (comptime search_evidence_observation_compiled) {
            self.storage.tt_facts += 1;
            self.storage.last_tt = facts;
        }
    }

    pub fn observeWindow(self: *SearchEvidenceObservation, facts: WindowFacts) void {
        if (comptime search_evidence_observation_compiled) {
            self.storage.windows += 1;
            self.storage.last_window = facts;
        }
    }

    pub fn observeNodePlan(self: *SearchEvidenceObservation, plan: NodeDepthPlan) void {
        if (comptime search_evidence_observation_compiled) {
            self.storage.node_plans += 1;
            self.storage.last_node_plan = plan;
        }
    }

    pub fn observeMovePlan(self: *SearchEvidenceObservation, facts: MoveFacts, plan: MoveDepthPlan) void {
        if (comptime search_evidence_observation_compiled) {
            self.storage.move_plans += 1;
            self.storage.last_move_facts = facts;
            self.storage.last_move_plan = plan;
        }
    }

    pub fn observeHistory(self: *SearchEvidenceObservation, facts: HistoryFacts) void {
        if (comptime search_evidence_observation_compiled) {
            self.storage.history_facts += 1;
            self.storage.last_history = facts;
            switch (facts.point) {
                .ranking => {
                    self.storage.ranking_history_facts += 1;
                    self.storage.last_ranking_history = facts;
                },
                .depth => {
                    self.storage.depth_history_facts += 1;
                    self.storage.last_depth_history = facts;
                },
            }
        }
    }

    pub fn observeOutcome(self: *SearchEvidenceObservation, outcome: SearchOutcome) void {
        if (comptime search_evidence_observation_compiled) {
            self.storage.outcomes += 1;
            self.storage.last_outcome = outcome;
            if (outcome.attribution != null and outcome.attribution.?.route == .quiescence and
                outcome.omitted_siblings)
                self.storage.qsearch_outcomes_with_omissions += 1;
            if (outcome.verification == .reduced_only)
                self.storage.reduced_only_outcomes += 1;
            if (outcome.reduced_siblings)
                self.storage.reduced_sibling_outcomes += 1;
        }
    }

    /// Records whether one completed quiet outcome reached the shadow relation,
    /// keyed by the node depth that produced it.
    pub fn observeShadowAdmission(
        self: *SearchEvidenceObservation,
        depth: u16,
        admitted: bool,
    ) void {
        if (comptime search_evidence_observation_compiled) {
            const bucket = @min(@as(usize, depth), shadow_depth_buckets - 1);
            if (admitted) {
                self.storage.shadow_admitted += 1;
                self.storage.shadow_admitted_by_depth[bucket] += 1;
            } else {
                self.storage.shadow_refused += 1;
                self.storage.shadow_refused_by_depth[bucket] += 1;
            }
        }
    }

    pub fn record(self: *SearchEvidenceObservation, key: u64, bonus: i32) void {
        if (comptime search_evidence_observation_compiled) {
            std.debug.assert(key != 0);
            const start: usize = @intCast(observationIndex(key));
            for (0..8) |offset| {
                const entry = &self.storage.entries[(start + offset) & (observation_slot_count - 1)];
                if (entry.key == 0) entry.key = key;
                if (entry.key == key) {
                    entry.sample.apply(bonus);
                    self.storage.updates += 1;
                    return;
                }
            }
            self.storage.dropped += 1;
        }
    }

    pub fn sample(self: *const SearchEvidenceObservation, key: u64) ?OutcomeSupportCell {
        if (comptime search_evidence_observation_compiled) {
            if (key == 0) return null;
            const start: usize = @intCast(observationIndex(key));
            for (0..8) |offset| {
                const entry = self.storage.entries[(start + offset) & (observation_slot_count - 1)];
                if (entry.key == key) return entry.sample;
                if (entry.key == 0) return null;
            }
        }
        return null;
    }

    pub fn summary(self: *const SearchEvidenceObservation) SearchEvidenceSummary {
        if (comptime search_evidence_observation_compiled) return .{
            .static_facts = self.storage.static_facts,
            .tt_facts = self.storage.tt_facts,
            .windows = self.storage.windows,
            .node_plans = self.storage.node_plans,
            .move_plans = self.storage.move_plans,
            .history_facts = self.storage.history_facts,
            .ranking_history_facts = self.storage.ranking_history_facts,
            .depth_history_facts = self.storage.depth_history_facts,
            .outcomes = self.storage.outcomes,
            .qsearch_outcomes_with_omissions = self.storage.qsearch_outcomes_with_omissions,
            .reduced_only_outcomes = self.storage.reduced_only_outcomes,
            .reduced_sibling_outcomes = self.storage.reduced_sibling_outcomes,
            .shadow_admitted = self.storage.shadow_admitted,
            .shadow_refused = self.storage.shadow_refused,
            .shadow_admitted_by_depth = self.storage.shadow_admitted_by_depth,
            .shadow_refused_by_depth = self.storage.shadow_refused_by_depth,
            .updates = self.storage.updates,
            .dropped = self.storage.dropped,
        };
        return .{};
    }

    pub fn snapshot(self: *const SearchEvidenceObservation) SearchEvidenceSnapshot {
        if (comptime search_evidence_observation_compiled) return .{
            .static_facts = self.storage.last_static,
            .tt_facts = self.storage.last_tt,
            .window = self.storage.last_window,
            .node_plan = self.storage.last_node_plan,
            .move_facts = self.storage.last_move_facts,
            .move_plan = self.storage.last_move_plan,
            .history = self.storage.last_history,
            .ranking_history = self.storage.last_ranking_history,
            .depth_history = self.storage.last_depth_history,
            .outcome = self.storage.last_outcome,
        };
        return .{};
    }
};

/// Compile-time switches keep each playing mechanism independently ablatable
/// without adding policy branches to recursive search.
pub const Features = struct {
    search_context: bool = true,
    /// Step-6.5.9 compile-time-only observation. It has no policy consumer and
    /// defaults off in both the feature ledger and the build configuration.
    search_evidence_observation: bool = false,
    depth_authority: bool = true,
    check_extension: bool = true,
    /// MAN-S31 disables only the non-root blanket increment. Root check
    /// extension and the existing whole-producer ablation remain independent.
    nonroot_check_extension: bool = true,
    internal_iterative_reduction: bool = true,
    singular_extension: bool = true,
    /// Step-6.0.3 stability-gated root aspiration candidate. It consumes only
    /// completed confidence evidence and remains default-off until its gate.
    aspiration: bool = false,
    null_move: bool = true,
    /// Step-5.1.4.4 tactical selectivity. This remains independently
    /// ablatable so disabling it restores accepted MAN-S11 exactly.
    probcut: bool = true,
    lmr: bool = true,
    /// Step-5.1.5.2 candidate. Disabling only this switch retains the accepted
    /// fixed one-ply MAN-S13 reduction while keeping LMR itself enabled.
    dynamic_lmr: bool = true,
    /// Rejected MAN-S18 dependency-complete LMR synchronization bundle. The
    /// archived umbrella/component switches reproduce the measured candidate
    /// without runtime hot-path dispatch; production remains exact MAN-S17.
    /// Reduction changes remain bounded to one child ply.
    lmr_synchronization: bool = false,
    lmr_sync_improving: bool = true,
    lmr_sync_expectation: bool = true,
    lmr_sync_tt_move: bool = true,
    lmr_sync_singular: bool = true,
    lmr_sync_history: bool = true,
    lmr_sync_positive_feedback: bool = true,
    lmr_sync_negative_feedback: bool = true,
    /// Rejected MAN-S16 candidate retained for diagnostic ablation. Production
    /// keeps accepted MAN-S15 capture ordering.
    capture_history: bool = false,
    balanced_history: bool = false,
    history_lmr: bool = false,
    /// Step-5.1.4.5 normalized one-ply reply history. This affects quiet
    /// ordering only and remains independently ablatable to frozen MAN-S12.
    contextual_history: bool = true,
    /// Step-5.1.5.4 dependency-complete continuation producer. The accepted
    /// one-ply reply table remains independent; these switches add populated
    /// two-, four- and six-ply contexts through one shared contextual table.
    continuation_history: bool = true,
    continuation_distance_2: bool = true,
    continuation_distance_4: bool = true,
    continuation_distance_6: bool = true,
    /// Accepted Step-6.5.10.1 `MAN-S35` production policy. Every non-root
    /// main-search node clips its own window to the band the rules of chess
    /// still allow at that ply, `[matedIn(ply), mateIn(ply + 1)]`. A window
    /// that no longer holds a reachable score returns the proven bound;
    /// otherwise the clipped window is the one the table probe, forward
    /// proofs, move loop and bound classification read. This supersedes
    /// `MAN-S32`, whose crossing-only path tightened nothing in an open
    /// window. Switching it off reconstructs that superseded tree at
    /// fingerprint `775,451` for archived diagnostics.
    mate_windows: bool = true,
    /// Step-6.5.5 singular-exclusion-horizon candidate. The same-position
    /// search still excludes exactly the legal ordinary TT move and alone
    /// decides whether that move extends; this switch only replaces the
    /// historical depth-minus-two horizon with a bounded half-depth horizon.
    singular_exclusion_horizon: bool = false,
    /// Accepted Step-6.5.1b playing head. Ordinary non-check interior nodes
    /// emit TT and good tactical moves before generating non-tactical quiets.
    /// The delayed quiet rank observes descendant-completed worker-local
    /// history; legality, score, bound, pruning and thread ownership remain
    /// unchanged. Disabling it reconstructs the archived MAN-S29 picker.
    live_history_staging: bool = true,
    /// Accepted Step-6.5.7 exact-cost path. Non-check qsearch generates only the
    /// tactical partition; when it is empty, the disjoint quiet partition is
    /// generated only as a legal-move witness and is not ranked or searched.
    qsearch_tactical_generation: bool = true,
    /// Archived rejected MAN-S14 switch, default off. Only an authoritative
    /// full-depth fail-low after an LMR false positive may add one negative
    /// reply-history update; history still has no reduction authority.
    lmr_reply_feedback: bool = false,
    qsearch_see: bool = true,
    /// Step-5.2 interior Syzygy WDL probing. Enabling this adds no behavior
    /// unless the caller also supplies a loaded prober, so the accepted MAN-S19
    /// head is reproduced exactly whenever no tablebase is configured.
    syzygy: bool = true,
    /// Suppress a transposition cutoff when the fifty-move allowance is nearly
    /// exhausted. A stored value was proven under a different halfmove clock,
    /// and the transposition key contains no clock, so near the boundary the
    /// cached verdict can assert a win the rules no longer permit. This is a
    /// search change against the frozen MAN-S22 head and therefore defaults
    /// off until its own gate accepts it.
    tt_rule_fifty_guard: bool = false,
    /// Step-5.1.5.6 evaluation/provenance cluster. The umbrella and producer/
    /// consumer switches are compile-time ablatable to exact MAN-S17.
    eval_qsearch_sync: bool = true,
    tt_static_eval: bool = true,
    tt_eval_refinement: bool = true,
    qsearch_delta: bool = true,
    /// Step-5.1.5.7 dependency-complete main-selectivity cluster. The
    /// umbrella restores accepted MAN-S19 exactly; components remain
    /// independently ablatable for decision-useful diagnosis.
    main_selectivity_sync: bool = false,
    dynamic_null_move: bool = true,
    probcut_tt: bool = true,
    history_pruning: bool = true,
    capture_futility: bool = true,
    /// Step-5.1.5.8 extension/depth-authority cluster. The umbrella adds
    /// expectation-aware IIR and stronger, provenance-checked singular
    /// decisions while restoring accepted MAN-S19 exactly when disabled.
    depth_authority_sync: bool = false,
    iir_cut_expectation: bool = true,
    singular_tt_provenance: bool = true,
    singular_multi_cut: bool = true,
    singular_double_extension: bool = true,
    /// Step-5.1.4.3 shallow-selectivity family umbrella. Disabling this alone
    /// restores accepted MAN-S10 exactly. Each producer below remains
    /// independently ablatable for diagnosis.
    shallow_selectivity: bool = true,
    reverse_futility: bool = true,
    /// Parked component: a verified-qsearch depth-one razoring implementation
    /// still changed the WAC.001 forcing-move canary at root depth three, the
    /// same failure mode already refuted for wider reverse-futility scope.
    /// Kept ablatable for future re-evaluation; not part of the default family.
    razoring: bool = false,
    quiet_futility: bool = true,
    late_move_pruning: bool = true,
    see_pruning: bool = true,
    /// Step-5.4.2 `MAN-S23` late-move reduction desaturation, default off until
    /// its gate. The accepted surface takes the minimum of a linear depth band
    /// and a logarithmic move band, and a minimum is bounded by its smaller
    /// argument: the move band never exceeds three for any legal move count, so
    /// the whole surface caps at four plies however deep the search goes. This
    /// composes the two confidence signals multiplicatively instead, so a
    /// deeper search and a later move each keep raising the reduction. The
    /// one-ply floor and the `depth - 2` ceiling are unchanged, so every path
    /// still retains an ordinary child ply before quiescence.
    lmr_desaturation: bool = false,
    /// Step-5.4.1 `MAN-S25` static-evaluation correction history, default off
    /// until its gate. A worker-local table keyed by side and pawn structure
    /// records where completed searches have previously disagreed with the
    /// evaluator, and the evaluation consumer applies that bias correction.
    /// **The pruning consumer is deliberately not wired.** PLAN 5.4.1 requires
    /// the structural producer to be gated before it controls selectivity, so
    /// `pruning_eval` and the improving stack continue to derive from the
    /// uncorrected evaluation, so correction has no direct pruning or reduction
    /// authority. Its changed qsearch values may still change the later tree,
    /// as any evaluation change can.
    correction_history: bool = false,
};

test "production feature ledger freezes the MAN-S19 search policy" {
    // Step 5.1.5.9 treats default construction as a checked configuration
    // contract. This is intentionally an exact policy assertion, not a node
    // fingerprint: changing one of these defaults opens a new playing
    // candidate and must not silently alter the frozen production head.
    const features: Features = .{};

    try std.testing.expect(features.search_context);
    try std.testing.expect(!features.search_evidence_observation);
    try std.testing.expect(features.depth_authority);
    try std.testing.expect(features.check_extension);
    try std.testing.expect(features.nonroot_check_extension);
    try std.testing.expect(features.internal_iterative_reduction);
    try std.testing.expect(features.singular_extension);
    try std.testing.expect(features.null_move);
    try std.testing.expect(features.probcut);
    try std.testing.expect(features.lmr);
    try std.testing.expect(features.dynamic_lmr);
    try std.testing.expect(features.contextual_history);
    try std.testing.expect(features.continuation_history);
    try std.testing.expect(features.continuation_distance_2);
    try std.testing.expect(features.continuation_distance_4);
    try std.testing.expect(features.continuation_distance_6);
    try std.testing.expect(features.qsearch_see);
    try std.testing.expect(features.eval_qsearch_sync);
    try std.testing.expect(features.tt_static_eval);
    try std.testing.expect(features.tt_eval_refinement);
    try std.testing.expect(features.qsearch_delta);
    // Step 6.5.1b is the first accepted default that changes the searched tree
    // since MAN-S22 froze this ledger, so its promotion is asserted here.
    try std.testing.expect(features.live_history_staging);
    try std.testing.expect(features.qsearch_tactical_generation);
    // Step 6.5.10.1 is the accepted head's second tree-changing default. It was
    // promoted on a neutral registered gate by explicit maintainer exception,
    // so its default-on state is asserted rather than inferred.
    try std.testing.expect(features.mate_windows);
    try std.testing.expect(features.shallow_selectivity);
    try std.testing.expect(features.reverse_futility);
    try std.testing.expect(features.quiet_futility);
    try std.testing.expect(features.late_move_pruning);
    try std.testing.expect(features.see_pruning);
    // MAN-S23 is rejected and MAN-S25 is a registered candidate, not
    // production. Neither dormant switch may silently change the accepted head.
    try std.testing.expect(!features.lmr_desaturation);
    try std.testing.expect(!features.correction_history);

    try std.testing.expect(!features.aspiration);
    try std.testing.expect(!features.lmr_synchronization);
    try std.testing.expect(!features.capture_history);
    try std.testing.expect(!features.balanced_history);
    try std.testing.expect(!features.history_lmr);
    try std.testing.expect(!features.lmr_reply_feedback);
    try std.testing.expect(!features.singular_exclusion_horizon);
    try std.testing.expect(!features.main_selectivity_sync);
    try std.testing.expect(!features.depth_authority_sync);
    try std.testing.expect(!features.razoring);
}

pub const PrincipalVariation = struct {
    moves: [chess.types.max_ply]chess.move.Move,
    length: u16 = 0,

    pub fn init() PrincipalVariation {
        // SAFETY: `length` is zero and `slice` exposes only the initialized
        // prefix copied from the worker PV table.
        return .{ .moves = undefined };
    }

    pub fn slice(self: *const PrincipalVariation) []const chess.move.Move {
        return self.moves[0..self.length];
    }
};

/// Typed work attributed to one legal root move in one completed search
/// attempt. A bound remains a bound: later confidence consumers must not treat
/// a scout fail-low as an exact score merely because it is stored here.
pub const RootMoveSample = struct {
    chess_move: chess.move.Move,
    evidence: Evidence,
    nodes: u64,
};

/// Fixed-capacity scratch evidence for the current root attempt. Search resets
/// it before an aspiration retry and commits it only after the whole iteration
/// returns exact, so cancellation cannot leak a partial root population.
pub const RootIterationEvidence = struct {
    items: [chess.types.move_capacity]RootMoveSample,
    count: u16 = 0,

    pub fn init() RootIterationEvidence {
        // SAFETY: `count` is zero and append initializes an item before slice
        // can expose it.
        return .{ .items = undefined };
    }

    pub fn reset(self: *RootIterationEvidence) void {
        self.count = 0;
    }

    pub fn append(self: *RootIterationEvidence, sample: RootMoveSample) void {
        std.debug.assert(sample.chess_move.isChessMove());
        std.debug.assert(self.count < self.items.len);
        self.items[self.count] = sample;
        self.count += 1;
    }

    pub fn slice(self: *const RootIterationEvidence) []const RootMoveSample {
        return self.items[0..self.count];
    }
};

/// Persistent evidence for one legal root move across completed iterative-
/// deepening iterations. Exact-score moments exclude upper/lower bounds; the
/// typed last evidence still preserves those observations for later design.
pub const RootMoveHistory = struct {
    chess_move: chess.move.Move = .none,
    observations: u16 = 0,
    exact_observations: u16 = 0,
    last_depth: u16 = 0,
    last_evidence: ?Evidence = null,
    last_effort: u64 = 0,
    total_effort: u64 = 0,
    exact_score_sum: i64 = 0,
    exact_score_square_sum: u64 = 0,

    /// Population variance in squared centipawns, rounded down. One exact
    /// observation has no variance yet; bounded scout results never enter it.
    pub fn exactScoreVariance(self: RootMoveHistory) ?u64 {
        if (self.exact_observations < 2) return null;
        const n: u128 = self.exact_observations;
        const square_sum: u128 = self.exact_score_square_sum;
        const signed_sum = self.exact_score_sum;
        const sum_magnitude: u128 = @intCast(if (signed_sum < 0) -signed_sum else signed_sum);
        const numerator = n * square_sum - sum_magnitude * sum_magnitude;
        return @intCast(numerator / (n * n));
    }
};

/// Compact completed-iteration view. It is published with the ordinary search
/// result for diagnostics. The default production build gives it no behavior
/// authority; later Step-6.0 consumers may read only the fields their own
/// explicit contracts authorize.
pub const RootConfidenceSnapshot = struct {
    root_move_count: u16 = 0,
    completed_iterations: u16 = 0,
    best_move_changes: u16 = 0,
    stable_best_iterations: u16 = 0,
    best_score_delta: ?i32 = null,
    best_effort: u64 = 0,
    total_effort: u64 = 0,
};

/// Worker-local root evidence, reset for every new search and updated only by
/// complete exact root iterations. Linear lookup is bounded by the legal root
/// move capacity and occurs outside recursive node expansion.
pub const RootConfidence = struct {
    moves: [chess.types.move_capacity]RootMoveHistory,
    count: u16 = 0,
    completed_iterations: u16 = 0,
    previous_best: chess.move.Move = .none,
    previous_best_score: ?i32 = null,
    previous_best_score_ordinary: bool = false,
    best_move_changes: u16 = 0,
    stable_best_iterations: u16 = 0,

    pub fn init() RootConfidence {
        // SAFETY: `count` is zero and findOrAppend initializes each history
        // before any lookup or iteration can expose it.
        return .{ .moves = undefined };
    }

    pub fn reset(self: *RootConfidence) void {
        self.count = 0;
        self.completed_iterations = 0;
        self.previous_best = .none;
        self.previous_best_score = null;
        self.previous_best_score_ordinary = false;
        self.best_move_changes = 0;
        self.stable_best_iterations = 0;
    }

    pub fn history(self: *const RootConfidence, chess_move: chess.move.Move) ?*const RootMoveHistory {
        for (self.moves[0..self.count]) |*entry| {
            if (entry.chess_move.raw() == chess_move.raw()) return entry;
        }
        return null;
    }

    pub fn recordCompleted(
        self: *RootConfidence,
        depth: u16,
        samples: []const RootMoveSample,
        best_move: chess.move.Move,
    ) RootConfidenceSnapshot {
        std.debug.assert(samples.len <= chess.types.move_capacity);
        std.debug.assert(best_move.isChessMove());
        // A warm root TT exact hit can complete without searching a root
        // child. It remains valid score/PV evidence, but supplies no honest
        // move-effort population and therefore cannot train confidence.
        if (samples.len == 0) return .{
            .root_move_count = self.count,
            .completed_iterations = self.completed_iterations,
            .best_move_changes = self.best_move_changes,
            .stable_best_iterations = self.stable_best_iterations,
        };

        var total_effort: u64 = 0;
        var best_effort: u64 = 0;
        var best_score: ?i32 = null;
        var best_score_ordinary = false;
        for (samples) |sample| {
            var entry = self.findOrAppend(sample.chess_move);
            entry.observations += 1;
            entry.last_depth = depth;
            entry.last_evidence = sample.evidence;
            entry.last_effort = sample.nodes;
            entry.total_effort +|= sample.nodes;
            total_effort +|= sample.nodes;
            if (sample.evidence.bound == .exact) {
                const raw: i64 = sample.evidence.value.raw();
                entry.exact_observations += 1;
                entry.exact_score_sum += raw;
                entry.exact_score_square_sum += @intCast(raw * raw);
            }
            if (sample.chess_move.raw() == best_move.raw()) {
                best_effort = sample.nodes;
                best_score = sample.evidence.value.raw();
                best_score_ordinary = sample.evidence.value.isOrdinary();
                std.debug.assert(sample.evidence.bound == .exact);
            }
        }
        std.debug.assert(best_score != null);

        const delta = if (self.previous_best_score) |previous|
            if (self.previous_best_score_ordinary and best_score_ordinary)
                best_score.? - previous
            else
                null
        else
            null;
        if (self.previous_best.isChessMove()) {
            if (self.previous_best.raw() == best_move.raw()) {
                self.stable_best_iterations += 1;
            } else {
                self.best_move_changes += 1;
                self.stable_best_iterations = 1;
            }
        } else {
            self.stable_best_iterations = 1;
        }
        self.previous_best = best_move;
        self.previous_best_score = best_score;
        self.previous_best_score_ordinary = best_score_ordinary;
        self.completed_iterations += 1;

        return .{
            .root_move_count = @intCast(samples.len),
            .completed_iterations = self.completed_iterations,
            .best_move_changes = self.best_move_changes,
            .stable_best_iterations = self.stable_best_iterations,
            .best_score_delta = delta,
            .best_effort = best_effort,
            .total_effort = total_effort,
        };
    }

    fn findOrAppend(self: *RootConfidence, chess_move: chess.move.Move) *RootMoveHistory {
        for (self.moves[0..self.count]) |*entry| {
            if (entry.chess_move.raw() == chess_move.raw()) return entry;
        }
        std.debug.assert(self.count < self.moves.len);
        const entry = &self.moves[self.count];
        entry.* = .{ .chess_move = chess_move };
        self.count += 1;
        return entry;
    }
};

pub const CompletedIteration = struct {
    depth: u16,
    selective_depth: u16,
    nodes: u64,
    evidence: Evidence,
    pv: PrincipalVariation,
    root_confidence: RootConfidenceSnapshot,
};

pub const Termination = enum {
    depth_limit,
    node_limit,
    time_limit,
    stopped,
    terminal,
    root_draw,
};

pub const Result = struct {
    best_move: ?chess.move.Move,
    evidence: Evidence,
    completed: ?CompletedIteration,
    termination: Termination,
    nodes: u64,
    tablebase_hits: u64,
    selective_depth: u16,
};

pub const Limits = struct {
    depth: u16 = 1,
    nodes: ?u64 = null,
    /// Minimum searched depth at which an interior tablebase probe is worth
    /// its file-backed cost. This is a cost boundary supplied by the caller,
    /// never a chess claim: a deeper floor changes how much work probing
    /// saves, not which results are correct.
    tablebase_probe_depth: u16 = 1,
    /// Largest piece count that may be probed. Caps probing below whatever the
    /// loaded set covers, which is useful when the widest tables are slow.
    tablebase_probe_limit: u8 = 7,
    /// Whether tablebase verdicts honour the fifty-move rule. Ordinary play
    /// always does; analysis may ask for the theoretical result instead.
    tablebase_use_rule_fifty: bool = true,

    pub fn normalizedDepth(self: Limits) u16 {
        return @min(self.depth, chess.types.max_ply - 1);
    }
};

pub const NeverStop = struct {
    pub inline fn shouldStop(_: *NeverStop) bool {
        return false;
    }
};

/// Sentinel for an unrecorded per-ply static evaluation. Outside the ordinary
/// score band, so it can never collide with a real evaluator-scale value.
pub const static_eval_unknown: i32 = std.math.minInt(i32);

pub const ThreadState = struct {
    states: [chess.types.max_ply]chess.position.PositionState,
    ply_contexts: [chess.types.max_ply]PlyContext,
    pv_moves: [chess.types.max_ply + 1][chess.types.max_ply]chess.move.Move,
    pv_lengths: [chess.types.max_ply + 1]u16,
    /// Per-ply raw static evaluation trail consumed only by the Step-5.1.4.3
    /// shallow-selectivity family's improving signal. `static_eval_unknown`
    /// marks a ply that is in check or was never visited this search.
    static_evals: [chess.types.max_ply]i32,
    nodes: u64,
    /// Tablebase hits are reported by UCI, so they are counted here rather
    /// than in the diagnostic observer, which is disabled in production.
    tablebase_hits: u64,
    selective_depth: u16,
    abort_reason: ?Termination,
    root_confidence: RootConfidence,
    search_evidence: SearchEvidenceObservation,

    pub fn init() ThreadState {
        // SAFETY: search initializes a state slot before makeMove consumes it,
        // and PV access is restricted by the zeroed per-row lengths.
        return .{
            .states = undefined,
            .ply_contexts = undefined,
            .pv_moves = undefined,
            .pv_lengths = @splat(0),
            .static_evals = @splat(static_eval_unknown),
            .nodes = 0,
            .tablebase_hits = 0,
            .selective_depth = 0,
            .abort_reason = null,
            .root_confidence = RootConfidence.init(),
            .search_evidence = .{},
        };
    }

    pub fn reset(self: *ThreadState) void {
        self.pv_lengths = @splat(0);
        self.static_evals = @splat(static_eval_unknown);
        self.nodes = 0;
        self.tablebase_hits = 0;
        self.selective_depth = 0;
        self.abort_reason = null;
        self.root_confidence.reset();
        self.search_evidence.reset();
    }
};

test "depth intent composes extensions and reductions without underflow" {
    // Prospective depth is an arithmetic contract, not a tuned search formula.
    try std.testing.expectEqual(@as(u16, 5), DepthIntent.full(5).searched());
    try std.testing.expectEqual(@as(u16, 3), DepthIntent.reduced(5, 2).searched());
    try std.testing.expectEqual(@as(u16, 6), DepthIntent.extended(5, 1).searched());
    try std.testing.expectEqual(@as(u16, 0), DepthIntent.reduced(1, 2).searched());
}

test "search evidence values preserve unknown authority and bounded arithmetic" {
    // Step 6.5.9: missing PV/trend evidence remains optional, depth components
    // stay distinct, and paired support saturates without escaping its domain.
    const tt_facts: TtFacts = .{ .authenticated = true };
    try std.testing.expectEqual(@as(?bool, null), tt_facts.pv_origin);
    const window = WindowFacts.init(-10, 21, null, .principal);
    try std.testing.expectEqual(@as(u32, 31), window.width);

    var cell: OutcomeSupportCell = .{};
    cell.apply(OutcomeSupportCell.limit);
    try std.testing.expectEqual(@as(i16, 16 * 1024), cell.value);
    for (0..300) |_| cell.apply(-OutcomeSupportCell.limit);
    try std.testing.expectEqual(@as(i16, -16 * 1024), cell.value);
    try std.testing.expectEqual(std.math.maxInt(u8), cell.support);
}

test "disabled search evidence storage has zero worker footprint" {
    // The production build must not allocate the diagnostic shadow table.
    if (comptime !search_evidence_observation_compiled)
        try std.testing.expectEqual(@as(usize, 0), @sizeOf(SearchEvidenceObservation));
}

test "enabled search evidence storage is explicitly bounded" {
    // The diagnostic remains worker-local and small beside the existing
    // ordering state; growth requires an intentional allocation review.
    if (comptime search_evidence_observation_compiled)
        try std.testing.expect(@sizeOf(SearchEvidenceObservation) <= 128 * 1024);
}

test "search evidence collisions drop rather than merge samples" {
    if (comptime !search_evidence_observation_compiled) return error.SkipZigTest;
    var colliding: [9]u64 = undefined;
    var count: usize = 0;
    var candidate: u64 = 1;
    const target = observationIndex(candidate);
    while (count < colliding.len) : (candidate += 1) {
        if (observationIndex(candidate) != target) continue;
        colliding[count] = candidate;
        count += 1;
    }
    var observation: SearchEvidenceObservation = .{};
    for (colliding) |key| observation.record(key, 7);
    for (colliding[0..8]) |key| {
        const sample_value = observation.sample(key).?;
        try std.testing.expectEqual(@as(u8, 1), sample_value.support);
        try std.testing.expectEqual(@as(i16, 7), sample_value.value);
    }
    try std.testing.expectEqual(@as(?OutcomeSupportCell, null), observation.sample(colliding[8]));
    try std.testing.expectEqual(@as(u64, 1), observation.summary().dropped);
}

test "ply context preserves special-move identity without chess authority" {
    // The context transports already-validated move facts. Rule code remains
    // the independent authority for what castling, en-passant and promotion do.
    const special_moves = [_]chess.move.Move{
        chess.move.Move.castling(.e1, .g1),
        chess.move.Move.enPassant(.e5, .d6),
        chess.move.Move.promotion(.a7, .a8, .queen),
    };
    for (special_moves) |special| {
        const context = PlyContext.afterMove(special, .queen, false, true, true);
        try std.testing.expectEqual(Arrival.move, context.arrival);
        try std.testing.expectEqual(special.raw(), context.previous_move.raw());
        try std.testing.expectEqual(chess.types.PieceType.queen, context.previous_piece);
        try std.testing.expectEqual(special.to(), context.previous_to);
        try std.testing.expect(context.previous_tactical);
        try std.testing.expect(context.in_check);
    }
    try std.testing.expectEqual(Arrival.null_move, PlyContext.afterNull(false).arrival);
    const root_context = PlyContext.root(false);
    try std.testing.expectEqual(Arrival.root, root_context.arrival);
    const excluded = chess.move.Move.normal(.e2, .e4);
    const exclusion_context = root_context.withExcluded(excluded);
    try std.testing.expectEqual(excluded.raw(), exclusion_context.excluded_move.raw());
    try std.testing.expectEqual(chess.move.Move.none.raw(), root_context.excluded_move.raw());
}

test "outcome attribution derives disposition only from typed bounds" {
    // The classification must not guess from numeric score magnitude or
    // provenance; Bound remains the independent authority.
    const ordinary = score.Score.fromOrdinary(17).?;
    const cases = [_]struct { bound: Bound, expected: NodeDisposition }{
        .{ .bound = .upper, .expected = .fail_low },
        .{ .bound = .exact, .expected = .exact },
        .{ .bound = .lower, .expected = .cutoff },
    };
    for (cases) |case| {
        const attributed = OutcomeAttribution.init(
            .scout,
            DepthIntent.full(3),
            .cut,
            .{
                .value = ordinary,
                .bound = case.bound,
                .provenance = .full_search,
            },
        );
        try std.testing.expectEqual(case.expected, attributed.disposition);
        try std.testing.expectEqual(NodeExpectation.cut, attributed.expectation);
        try std.testing.expectEqual(case.bound, attributed.evidence.bound);
        try std.testing.expectEqual(@as(u16, 3), attributed.depth.searched());
    }
}

test "node expectations preserve PV and invert non-principal negamax roles" {
    // This is prospective context only. The transition follows alpha-beta's
    // negated child objective and does not inspect a returned score or bound.
    try std.testing.expect(NodeExpectation.principal.isPrincipal());
    try std.testing.expect(!NodeExpectation.cut.isPrincipal());
    try std.testing.expectEqual(NodeExpectation.principal, NodeExpectation.principal.child(true));
    try std.testing.expectEqual(NodeExpectation.cut, NodeExpectation.principal.child(false));
    try std.testing.expectEqual(NodeExpectation.all, NodeExpectation.cut.child(false));
    try std.testing.expectEqual(NodeExpectation.cut, NodeExpectation.all.child(false));
}

test "root confidence retains typed completed evidence and exact variance" {
    // Exact score moments are an independent arithmetic property. A bounded
    // scout result remains visible as evidence but cannot contaminate variance.
    const e2e4 = chess.move.Move.normal(.e2, .e4);
    const d2d4 = chess.move.Move.normal(.d2, .d4);
    var confidence = RootConfidence.init();
    const first = [_]RootMoveSample{
        .{
            .chess_move = e2e4,
            .evidence = .{ .value = score.Score.fromOrdinary(10).?, .bound = .exact, .provenance = .full_search },
            .nodes = 70,
        },
        .{
            .chess_move = d2d4,
            .evidence = .{ .value = score.Score.fromOrdinary(5).?, .bound = .upper, .provenance = .pvs_probe },
            .nodes = 30,
        },
    };
    const first_snapshot = confidence.recordCompleted(1, &first, e2e4);
    try std.testing.expectEqual(@as(u16, 2), first_snapshot.root_move_count);
    try std.testing.expectEqual(@as(u64, 100), first_snapshot.total_effort);
    try std.testing.expectEqual(@as(u64, 70), first_snapshot.best_effort);
    try std.testing.expectEqual(@as(?i32, null), first_snapshot.best_score_delta);

    const second = [_]RootMoveSample{
        .{
            .chess_move = e2e4,
            .evidence = .{ .value = score.Score.fromOrdinary(20).?, .bound = .exact, .provenance = .full_search },
            .nodes = 90,
        },
        .{
            .chess_move = d2d4,
            .evidence = .{ .value = score.Score.fromOrdinary(30).?, .bound = .exact, .provenance = .full_search },
            .nodes = 110,
        },
    };
    const second_snapshot = confidence.recordCompleted(2, &second, d2d4);
    try std.testing.expectEqual(@as(u16, 2), second_snapshot.completed_iterations);
    try std.testing.expectEqual(@as(u16, 1), second_snapshot.best_move_changes);
    try std.testing.expectEqual(@as(u16, 1), second_snapshot.stable_best_iterations);
    try std.testing.expectEqual(@as(?i32, 20), second_snapshot.best_score_delta);
    const e4_history = confidence.history(e2e4).?;
    try std.testing.expectEqual(@as(u16, 2), e4_history.exact_observations);
    try std.testing.expectEqual(@as(?u64, 25), e4_history.exactScoreVariance());
    const d4_history = confidence.history(d2d4).?;
    try std.testing.expectEqual(@as(u16, 2), d4_history.observations);
    try std.testing.expectEqual(@as(u16, 1), d4_history.exact_observations);
    try std.testing.expectEqual(@as(?u64, null), d4_history.exactScoreVariance());
}

test "root iteration evidence preserves special move identity" {
    // Legality remains move generation's responsibility; this transport must
    // preserve the already-validated encoded move without normalization.
    const special_moves = [_]chess.move.Move{
        chess.move.Move.castling(.e1, .g1),
        chess.move.Move.enPassant(.e5, .d6),
        chess.move.Move.promotion(.a7, .a8, .queen),
    };
    var iteration = RootIterationEvidence.init();
    for (special_moves) |special| iteration.append(.{
        .chess_move = special,
        .evidence = .{ .value = score.Score.zero, .bound = .exact, .provenance = .full_search },
        .nodes = 1,
    });
    try std.testing.expectEqual(special_moves.len, iteration.slice().len);
    for (iteration.slice(), special_moves) |sample, expected|
        try std.testing.expectEqual(expected.raw(), sample.chess_move.raw());
}

test "root score trend excludes decisive-to-ordinary transitions" {
    // Step 6.3.1 provenance contract: a mate/tablebase band must not become a
    // huge synthetic falling-evaluation signal when ordinary search resumes.
    const move = chess.move.Move.normal(.e2, .e4);
    var confidence = RootConfidence.init();
    const decisive = [_]RootMoveSample{.{
        .chess_move = move,
        .evidence = .{ .value = score.Score.mateIn(3).?, .bound = .exact, .provenance = .full_search },
        .nodes = 10,
    }};
    _ = confidence.recordCompleted(1, &decisive, move);
    const ordinary = [_]RootMoveSample{.{
        .chess_move = move,
        .evidence = .{ .value = score.Score.fromOrdinary(40).?, .bound = .exact, .provenance = .full_search },
        .nodes = 20,
    }};
    const snapshot = confidence.recordCompleted(2, &ordinary, move);
    try std.testing.expectEqual(@as(?i32, null), snapshot.best_score_delta);
}

comptime {
    std.debug.assert(chess.types.max_ply == score.max_ply);
    std.debug.assert(@sizeOf(score.Score) == 4);
}
