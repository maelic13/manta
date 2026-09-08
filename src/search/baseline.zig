//! Deterministic one-thread iterative PVS and quiescence correctness baseline.
const std = @import("std");
const chess = @import("../chess/root.zig");
const score = @import("../score.zig");
const eval_contract = @import("../eval/contract.zig");
const diagnostics = @import("diagnostics.zig");
const ordering = @import("ordering.zig");
const params = @import("params.zig");
const tablebase = @import("tablebase.zig");
const tt = @import("tt.zig");
const types = @import("types.zig");

const Abort = error{Stopped};

const NodeValue = struct {
    raw: i32,
    bound: types.Bound,
    provenance: types.Provenance,
};

const NodeResolution = struct {
    value: NodeValue,
    depth: types.DepthIntent,
};

fn Context(comptime Observer: type, comptime Prober: type) type {
    return struct {
        limits: types.Limits,
        thread: *types.ThreadState,
        table: ?*tt.Table,
        heuristics: ?*ordering.State,
        root_moves: ?[]const chess.move.Move,
        root_iteration: *types.RootIterationEvidence,
        params: params.Values,
        observer: *Observer,
        /// Caller-owned tablebase prober. Search never constructs or imports
        /// one, so the inward layer keeps no file or library dependency.
        prober: *Prober,

        fn visit(
            self: *@This(),
            control: anytype,
            ply: usize,
            kind: diagnostics.NodeKind,
            expectation: types.NodeExpectation,
        ) Abort!void {
            self.observer.stopCheck(self.thread.nodes);
            if (control.shouldStop()) {
                const reason: types.Termination = if (@hasDecl(@TypeOf(control.*), "terminationReason"))
                    control.terminationReason()
                else
                    .stopped;
                self.thread.abort_reason = reason;
                self.observer.abort(reason, self.thread.nodes);
                return error.Stopped;
            }
            if (@hasDecl(@TypeOf(control.*), "claimNode")) {
                if (!control.claimNode()) {
                    self.thread.abort_reason = .node_limit;
                    self.observer.abort(.node_limit, self.thread.nodes);
                    return error.Stopped;
                }
            } else if (self.limits.nodes) |limit| {
                if (self.thread.nodes >= limit) {
                    self.thread.abort_reason = .node_limit;
                    self.observer.abort(.node_limit, self.thread.nodes);
                    return error.Stopped;
                }
            }
            self.thread.nodes += 1;
            self.thread.selective_depth = @max(self.thread.selective_depth, @as(u16, @intCast(ply)));
            self.observer.node(kind, expectation.isPrincipal());
        }
    };
}

/// Searches a borrowed root in place and restores it before returning. The
/// evaluator binding and stop policy are statically dispatched concrete types.
pub fn run(
    root: *chess.position.Position,
    binding: anytype,
    limits: types.Limits,
    control: anytype,
    thread: *types.ThreadState,
) types.Result {
    var observer: diagnostics.Disabled = .{};
    return runWithFeatures(.{}, root, binding, limits, control, thread, null, null, &observer);
}

/// Adds caller-owned TT, ordering state and a statically dispatched observer.
pub fn runWith(
    root: *chess.position.Position,
    binding: anytype,
    limits: types.Limits,
    control: anytype,
    thread: *types.ThreadState,
    table: ?*tt.Table,
    heuristics: ?*ordering.State,
    observer: anytype,
) types.Result {
    return runWithFeatures(.{}, root, binding, limits, control, thread, table, heuristics, observer);
}

/// Selects independently ablatable search mechanisms at compile time.
pub fn runWithFeatures(
    comptime features: types.Features,
    root: *chess.position.Position,
    binding: anytype,
    limits: types.Limits,
    control: anytype,
    thread: *types.ThreadState,
    table: ?*tt.Table,
    heuristics: ?*ordering.State,
    observer: anytype,
) types.Result {
    return runRestrictedWithFeatures(
        features,
        root,
        binding,
        limits,
        control,
        thread,
        table,
        heuristics,
        observer,
        null,
    );
}

/// Adds explicit immutable parameters for diagnostic reconstruction. Ordinary
/// production callers use `runWithFeatures` and therefore the accepted
/// defaults; archived fingerprint tests may supply their historical vector.
pub fn runWithFeaturesAndParams(
    comptime features: types.Features,
    root: *chess.position.Position,
    binding: anytype,
    limits: types.Limits,
    control: anytype,
    thread: *types.ThreadState,
    table: ?*tt.Table,
    heuristics: ?*ordering.State,
    observer: anytype,
    search_params: params.Values,
) types.Result {
    return runRestrictedWithTablebaseAndParams(
        features,
        root,
        binding,
        limits,
        control,
        thread,
        table,
        heuristics,
        observer,
        null,
        &tablebase.disabled,
        search_params,
    );
}

/// Restricts only root expansion to a validated nonempty legal move set.
pub fn runRestricted(
    root: *chess.position.Position,
    binding: anytype,
    limits: types.Limits,
    control: anytype,
    thread: *types.ThreadState,
    table: ?*tt.Table,
    heuristics: ?*ordering.State,
    observer: anytype,
    restricted_root_moves: ?[]const chess.move.Move,
) types.Result {
    return runRestrictedWithFeatures(
        .{},
        root,
        binding,
        limits,
        control,
        thread,
        table,
        heuristics,
        observer,
        restricted_root_moves,
    );
}

/// Restricts root expansion while selecting search mechanisms at compile time.
///
/// Callers that configure no tablebase reach the inert shared prober, so this
/// signature and every published result stay exactly as they were before
/// Step 5.2 added probing.
pub fn runRestrictedWithFeatures(
    comptime features: types.Features,
    root: *chess.position.Position,
    binding: anytype,
    limits: types.Limits,
    control: anytype,
    thread: *types.ThreadState,
    table: ?*tt.Table,
    heuristics: ?*ordering.State,
    observer: anytype,
    restricted_root_moves: ?[]const chess.move.Move,
) types.Result {
    return runRestrictedWithTablebase(
        features,
        root,
        binding,
        limits,
        control,
        thread,
        table,
        heuristics,
        observer,
        restricted_root_moves,
        &tablebase.disabled,
    );
}

/// Adds a caller-owned tablebase prober to the fully specified entry point.
///
/// The prober is statically dispatched exactly like the evaluator binding and
/// stop control, so an unloaded or inert prober compiles to no interior work
/// and reproduces the accepted search head byte for byte.
pub fn runRestrictedWithTablebase(
    comptime features: types.Features,
    root: *chess.position.Position,
    binding: anytype,
    limits: types.Limits,
    control: anytype,
    thread: *types.ThreadState,
    table: ?*tt.Table,
    heuristics: ?*ordering.State,
    observer: anytype,
    restricted_root_moves: ?[]const chess.move.Move,
    prober: anytype,
) types.Result {
    return runRestrictedWithTablebaseAndParams(
        features,
        root,
        binding,
        limits,
        control,
        thread,
        table,
        heuristics,
        observer,
        restricted_root_moves,
        prober,
        .{},
    );
}

/// Adds immutable runtime search values for tune builds. Production callers
/// use the defaulted wrapper above, which preserves the accepted policy.
pub fn runRestrictedWithTablebaseAndParams(
    comptime features: types.Features,
    root: *chess.position.Position,
    binding: anytype,
    limits: types.Limits,
    control: anytype,
    thread: *types.ThreadState,
    table: ?*tt.Table,
    heuristics: ?*ordering.State,
    observer: anytype,
    restricted_root_moves: ?[]const chess.move.Move,
    prober: anytype,
    search_params: params.Values,
) types.Result {
    return runRestrictedWorkerWithTablebaseAndParams(
        features,
        root,
        binding,
        limits,
        control,
        thread,
        table,
        heuristics,
        observer,
        restricted_root_moves,
        prober,
        search_params,
        .{},
    );
}

/// SMP-only execution controls. Ordinary callers retain the default entry
/// point above, including its generation advance and depth-one start.
pub const WorkerExecution = struct {
    start_depth: u16 = 1,
    advance_table_generation: bool = true,
};

pub fn runRestrictedWorkerWithTablebaseAndParams(
    comptime features: types.Features,
    root: *chess.position.Position,
    binding: anytype,
    limits: types.Limits,
    control: anytype,
    thread: *types.ThreadState,
    table: ?*tt.Table,
    heuristics: ?*ordering.State,
    observer: anytype,
    restricted_root_moves: ?[]const chess.move.Move,
    prober: anytype,
    search_params: params.Values,
    execution: WorkerExecution,
) types.Result {
    thread.reset();
    observer.reset();
    if (execution.advance_table_generation) if (table) |active| active.nextGeneration();
    binding.refresh(root);

    var root_moves = chess.position.MoveList.init();
    if (restricted_root_moves) |restricted| {
        std.debug.assert(restricted.len != 0 and restricted.len <= chess.types.move_capacity);
        for (restricted) |chess_move| {
            std.debug.assert(chess.movegen.isLegal(root, chess_move));
            root_moves.append(chess_move);
        }
    } else {
        chess.movegen.generate(.all, root, &root_moves);
    }
    if (root_moves.count == 0) return terminalRoot(root);

    // Tablebase root filtering restricts the root to the moves that preserve
    // the proven outcome, then lets ordinary search choose among them. It is
    // skipped when the caller already restricted the root, because an explicit
    // `searchmoves` list is a user instruction that outranks a table.
    var filtered_root_storage: [chess.types.move_capacity]chess.move.Move = undefined;
    // The effective restriction also governs root transposition use: an entry
    // stored for the unrestricted root does not describe a narrowed root, which
    // is the same reason an explicit `searchmoves` list suppresses root TT.
    var effective_root_restriction = restricted_root_moves;
    if (comptime features.syzygy) {
        if (restricted_root_moves == null and @hasDecl(@TypeOf(prober.*), "probeRootMoves")) {
            var ranked: [chess.types.move_capacity]tablebase.RankedRootMove = undefined;
            if (prober.probeRootMoves(root, root_moves.slice(), &ranked)) |ranked_count| {
                // The tables resolved the root, so this counts as a hit for
                // reporting even when every move turns out to be equally good
                // and nothing is filtered away.
                thread.tablebase_hits += 1;
                const kept = tablebase.retainBestRanked(
                    ranked[0..ranked_count],
                    &filtered_root_storage,
                );
                // Never empty the root, and never bother when nothing is
                // excluded: an unusable filter is simply ignored.
                if (kept != 0 and kept < root_moves.count) {
                    observer.tablebaseRootFilter(root_moves.count, kept);
                    root_moves = chess.position.MoveList.init();
                    for (filtered_root_storage[0..kept]) |chess_move| root_moves.append(chess_move);
                    effective_root_restriction = filtered_root_storage[0..kept];
                }
            }
        }
    }

    const fallback = root_moves.slice()[0];
    if (chess.draw.isSearchDraw(root, 0)) {
        return .{
            .best_move = fallback,
            .evidence = evidence(0, .exact, .terminal),
            .completed = null,
            .termination = .root_draw,
            .nodes = 0,
            .tablebase_hits = 0,
            .selective_depth = 0,
        };
    }

    const fallback_raw = if (root.current.checkers == 0) binding.evaluate(root).raw() else 0;
    var result = types.Result{
        .best_move = fallback,
        .evidence = evidence(fallback_raw, .exact, .fallback),
        .completed = null,
        .termination = .depth_limit,
        .nodes = 0,
        .tablebase_hits = 0,
        .selective_depth = 0,
    };
    const normalized_depth = limits.normalizedDepth();
    var root_iteration = types.RootIterationEvidence.init();
    var context = Context(@TypeOf(observer.*), @TypeOf(prober.*)){
        .limits = limits,
        .thread = thread,
        .table = table,
        .heuristics = heuristics,
        .root_moves = effective_root_restriction,
        .root_iteration = &root_iteration,
        .params = search_params,
        .observer = observer,
        .prober = prober,
    };
    if (comptime features.search_context)
        thread.ply_contexts[0] = types.PlyContext.root(root.current.checkers != 0);

    var depth: u16 = @max(execution.start_depth, 1);
    while (depth <= normalized_depth) : (depth += 1) {
        var window = AspirationWindow.full();
        if (comptime features.aspiration) {
            if (result.completed) |previous| {
                if (aspirationCenter(previous.evidence, previous.root_confidence)) |center| {
                    window = AspirationWindow.around(center);
                }
            }
        }
        const iteration = while (true) {
            root_iteration.reset();
            observer.rootSearch(!window.isFull());
            const attempt = negamax(
                features,
                true,
                &context,
                root,
                binding,
                control,
                types.DepthIntent.full(depth),
                0,
                window.alpha,
                window.beta,
                .principal,
                .root,
            ) catch {
                result.termination = thread.abort_reason orelse .stopped;
                result.nodes = thread.nodes;
                result.selective_depth = thread.selective_depth;
                return result;
            };
            if (attempt.bound == .exact) break attempt;
            std.debug.assert(!window.isFull());
            observer.aspirationFailure(attempt.bound);
            window.widen();
        };

        var completed = types.CompletedIteration{
            .depth = depth,
            .selective_depth = thread.selective_depth,
            .nodes = thread.nodes,
            .evidence = evidence(iteration.raw, iteration.bound, iteration.provenance),
            .pv = types.PrincipalVariation.init(),
            .root_confidence = .{},
        };
        completed.pv.length = thread.pv_lengths[0];
        @memcpy(completed.pv.moves[0..completed.pv.length], thread.pv_moves[0][0..completed.pv.length]);
        std.debug.assert(completed.pv.length != 0);
        completed.root_confidence = thread.root_confidence.recordCompleted(
            depth,
            root_iteration.slice(),
            completed.pv.moves[0],
        );
        result.best_move = completed.pv.moves[0];
        result.evidence = completed.evidence;
        result.completed = completed;
        result.nodes = thread.nodes;
        result.tablebase_hits = thread.tablebase_hits;
        result.selective_depth = thread.selective_depth;
        observer.iteration(depth, result.best_move.?, completed.evidence);
        if (@hasDecl(@TypeOf(control.*), "completedIteration"))
            control.completedIteration(completed);
        if (@hasDecl(@TypeOf(control.*), "shouldStopAfterIteration") and
            control.shouldStopAfterIteration(completed))
        {
            result.termination = if (@hasDecl(@TypeOf(control.*), "terminationReason"))
                control.terminationReason()
            else
                .stopped;
            return result;
        }
    }
    return result;
}

/// One pawn is a scale-derived uncertainty unit rather than an imported or
/// fitted engine constant. Symmetric doubling guarantees a full-window retry.
const AspirationWindow = struct {
    alpha: i32,
    beta: i32,
    radius: i32,
    center: i32,

    fn full() AspirationWindow {
        return .{
            .alpha = -score.infinity_raw,
            .beta = score.infinity_raw,
            .radius = score.infinity_raw,
            .center = 0,
        };
    }

    fn around(center: i32) AspirationWindow {
        return bounded(center, score.units_per_pawn);
    }

    fn isFull(self: AspirationWindow) bool {
        return self.alpha == -score.infinity_raw and self.beta == score.infinity_raw;
    }

    fn widen(self: *AspirationWindow) void {
        const next_radius = self.radius * 2;
        self.* = if (next_radius >= score.infinity_raw)
            full()
        else
            bounded(self.center, next_radius);
    }

    fn bounded(center: i32, radius: i32) AspirationWindow {
        const lower = @max(-@as(i64, score.infinity_raw), @as(i64, center) - radius);
        const upper = @min(@as(i64, score.infinity_raw), @as(i64, center) + radius);
        return .{
            .alpha = @intCast(lower),
            .beta = @intCast(upper),
            .radius = radius,
            .center = center,
        };
    }
};

/// A narrow window is useful only after two honest root populations agree on
/// the best move and their latest exact scores remain within one pawn. The
/// completed result supplies the center; decisive and bounded evidence retain
/// the full root window.
fn aspirationCenter(
    previous: types.Evidence,
    confidence: types.RootConfidenceSnapshot,
) ?i32 {
    if (previous.bound != .exact or !previous.value.isOrdinary()) return null;
    if (confidence.root_move_count == 0 or
        confidence.completed_iterations < 2 or
        confidence.stable_best_iterations < 2)
    {
        return null;
    }
    const delta = confidence.best_score_delta orelse return null;
    if (@abs(@as(i64, delta)) > score.units_per_pawn) return null;
    return previous.value.raw();
}

test "aspiration windows use the search scale and widen to full bounds" {
    // SCORE-008/PERF-010: the candidate begins with one evaluator pawn of
    // uncertainty and must terminate in an ordinary full-window search.
    var window = AspirationWindow.around(score.ordinary_max_raw);
    try std.testing.expectEqual(score.ordinary_max_raw - score.units_per_pawn, window.alpha);
    try std.testing.expectEqual(score.ordinary_max_raw + score.units_per_pawn, window.beta);
    var widenings: u8 = 0;
    while (!window.isFull()) {
        window.widen();
        widenings += 1;
        try std.testing.expect(widenings < 16);
    }
}

test "aspiration requires populated stable ordinary root evidence" {
    // SCORE-029: the candidate consumes completed-root facts rather than
    // narrowing merely because an earlier iteration happened to finish.
    const ordinary = evidence(37, .exact, .full_search);
    const stable = types.RootConfidenceSnapshot{
        .root_move_count = 20,
        .completed_iterations = 2,
        .stable_best_iterations = 2,
        .best_score_delta = score.units_per_pawn,
    };
    try std.testing.expectEqual(@as(?i32, 37), aspirationCenter(ordinary, stable));

    var rejected = stable;
    rejected.root_move_count = 0;
    try std.testing.expectEqual(@as(?i32, null), aspirationCenter(ordinary, rejected));
    rejected = stable;
    rejected.stable_best_iterations = 1;
    try std.testing.expectEqual(@as(?i32, null), aspirationCenter(ordinary, rejected));
    rejected = stable;
    rejected.best_score_delta = score.units_per_pawn + 1;
    try std.testing.expectEqual(@as(?i32, null), aspirationCenter(ordinary, rejected));
    try std.testing.expectEqual(
        @as(?i32, null),
        aspirationCenter(evidence(37, .lower, .full_search), stable),
    );
    try std.testing.expectEqual(
        @as(?i32, null),
        aspirationCenter(evidence(score.mate_raw - 1, .exact, .terminal), stable),
    );
}

fn negamax(
    comptime features: types.Features,
    comptime allow_null: bool,
    context: anytype,
    value: *chess.position.Position,
    binding: anytype,
    control: anytype,
    depth_intent: types.DepthIntent,
    ply: usize,
    alpha_initial: i32,
    beta: i32,
    expectation: types.NodeExpectation,
    route: types.EntryRoute,
) Abort!NodeValue {
    var active_depth = depth_intent;
    if (comptime features.search_context and features.depth_authority and features.check_extension) {
        if ((features.nonroot_check_extension or ply == 0) and
            checkExtensionEligible(value.current.checkers != 0, depth_intent, ply))
        {
            active_depth.extension +|= 1;
            context.observer.extension(.check);
        }
    }
    const result = try negamaxNode(
        features,
        allow_null,
        context,
        value,
        binding,
        control,
        active_depth,
        ply,
        alpha_initial,
        beta,
        expectation,
        route,
    );
    if (comptime features.search_context)
        context.observer.nodeOutcome(types.OutcomeAttribution.init(
            route,
            result.depth,
            expectation,
            evidence(result.value.raw, result.value.bound, result.value.provenance),
        ));
    return result.value;
}

fn negamaxNode(
    comptime features: types.Features,
    comptime allow_null: bool,
    context: anytype,
    value: *chess.position.Position,
    binding: anytype,
    control: anytype,
    depth_intent: types.DepthIntent,
    ply: usize,
    alpha_initial: i32,
    beta: i32,
    expectation: types.NodeExpectation,
    route: types.EntryRoute,
) Abort!NodeResolution {
    const pv_node = expectation.isPrincipal();
    std.debug.assert(pv_node or beta == alpha_initial + 1);
    var active_depth = depth_intent;
    var depth = active_depth.searched();
    const excluded_move = if (comptime features.search_context and features.depth_authority and features.singular_extension)
        context.thread.ply_contexts[ply].excluded_move
    else
        chess.move.Move.none;
    const exclusion_node = excluded_move.isChessMove();
    try context.visit(control, ply, .main, expectation);
    if (comptime features.search_context)
        context.observer.nodeContext(
            .main,
            ply,
            context.thread.ply_contexts[ply],
            route,
            active_depth,
            expectation,
        );
    context.thread.pv_lengths[ply] = 0;

    if (ply != 0 and chess.draw.isSearchDraw(value, @intCast(ply)))
        return resolved(.{ .raw = 0, .bound = .exact, .provenance = .terminal }, active_depth);
    if (ply >= chess.types.max_ply - 1)
        return resolved(
            .{ .raw = binding.evaluate(value).raw(), .bound = .exact, .provenance = .static_eval },
            active_depth,
        );

    const table_evidence = if (exclusion_node)
        TableEvidence{}
    else
        probeTable(context, value, depth, ply, alpha_initial, beta);
    if (table_evidence.cutoff) |cutoff| {
        // A transposition value was proven under whatever halfmove clock the
        // storing visit had, and the key records no clock. Close to the
        // fifty-move boundary that difference decides the game, so the cached
        // verdict is refused and the node is searched for real.
        if (comptime features.tt_rule_fifty_guard) {
            if (value.current.rule50 < tt_rule_fifty_guard_clock)
                return resolved(cutoff, active_depth);
        } else {
            return resolved(cutoff, active_depth);
        }
    }

    // Tablebase evidence is probed after the transposition table because a
    // cached hit is far cheaper than a file-backed lookup, and after the draw
    // and terminal checks above because repetition and the fifty-move rule are
    // decided by the rules of chess, not by a table.
    if (comptime features.syzygy) {
        if (tablebase.interiorProbeEligible(
            ply,
            depth,
            exclusion_node,
            context.limits.tablebase_probe_depth,
            @intCast(@popCount(value.physical.occupied())),
            context.limits.tablebase_probe_limit,
        )) {
            switch (context.prober.probeWdl(value)) {
                .unavailable => {},
                .available => |wdl| {
                    context.thread.tablebase_hits += 1;
                    context.observer.tablebaseHit(wdl);
                    const evidence_value = tablebase.toEvidence(
                        wdl,
                        ply,
                        context.limits.tablebase_use_rule_fifty,
                    );
                    const hit = NodeValue{
                        .raw = evidence_value.value.raw(),
                        .bound = evidence_value.bound,
                        .provenance = evidence_value.provenance,
                    };
                    // A verdict that does not settle this node against its
                    // window is still returned only when it cuts. Returning a
                    // non-cutting bound would abandon the node with no
                    // principal variation and no value more precise than the
                    // band edge, so it falls through to an ordinary search.
                    if (tablebase.settlesNode(hit.bound, hit.raw, alpha_initial, beta)) {
                        // A proven result does not become more true with
                        // depth, so its record earns a bonus and outlives
                        // shallow searched entries instead of being re-probed
                        // from disk at every revisit.
                        //
                        // No static evaluation is cached: a tablebase hit never
                        // ran the evaluator, and inventing a value here would
                        // feed MAN-S19's pruning-evaluation refinement a number
                        // that no producer actually computed.
                        const stored_depth = @min(
                            depth +| tablebase.table_depth_bonus,
                            chess.types.max_ply - 1,
                        );
                        storeTable(context, value.current.key, .none, hit, null, stored_depth, ply);
                        return resolved(hit, active_depth);
                    }
                },
            }
        }
    }

    if (comptime features.search_context and features.depth_authority and features.internal_iterative_reduction) {
        if (internalIterativeReductionEligible(
            features,
            depth,
            ply,
            expectation,
            value.current.checkers != 0,
            table_evidence.chess_move != null,
            exclusion_node,
        )) {
            active_depth.reduction +|= 1;
            depth = active_depth.searched();
            context.observer.internalIterativeReduction(expectation);
        }
    }
    if (depth == 0)
        return resolved(try quiescence(
            features,
            context,
            value,
            binding,
            control,
            ply,
            alpha_initial,
            beta,
            expectation,
        ), active_depth);

    const shallow: ShallowEvidence = if (comptime features.shallow_selectivity or features.probcut or
        features.lmr_synchronization or features.eval_qsearch_sync)
        shallowEvidence(features, false, context, value, binding, ply, value.current.checkers != 0, exclusion_node, table_evidence.record)
    else
        .{};
    // Shared zugzwang guard: a position with no non-pawn material for the
    // side to move can reverse under a single tempo, so no shallow-
    // selectivity consumer below may treat a quiet move as safely futile.
    const shallow_has_non_pawn_material = if (comptime features.shallow_selectivity or features.probcut)
        hasNonPawnMaterial(value)
    else
        false;
    if (comptime features.shallow_selectivity and features.reverse_futility) {
        if (shallow.known and reverseFutilityEligible(
            features,
            depth,
            pv_node,
            value.current.checkers != 0,
            beta == alpha_initial + 1,
            shallow_has_non_pawn_material,
            score.Score{ .raw_value = beta },
        )) {
            const cutoff = shallow.pruning_eval >= beta + reverseFutilityMargin(context.params, depth);
            context.observer.reverseFutility(cutoff);
            if (cutoff) {
                context.observer.prune(.reverse_futility);
                return resolved(
                    .{ .raw = beta, .bound = .lower, .provenance = .speculative_cutoff },
                    active_depth,
                );
            }
        }
    }
    if (comptime features.shallow_selectivity and features.razoring) {
        if (shallow.known and razoringEligible(
            features,
            depth,
            pv_node,
            exclusion_node,
            shallow_has_non_pawn_material,
            score.Score{ .raw_value = alpha_initial },
        )) {
            const triggered = shallow.pruning_eval + razoringMargin(depth, shallow.improving) <= alpha_initial;
            context.observer.razoring(triggered);
            if (triggered) {
                context.observer.prune(.razoring);
                return resolved(try quiescence(
                    features,
                    context,
                    value,
                    binding,
                    control,
                    ply,
                    alpha_initial,
                    beta,
                    expectation,
                ), active_depth);
            }
        }
    }

    if (comptime features.null_move and allow_null) {
        const beta_score = score.Score{ .raw_value = beta };
        const after_null = value.current.previous != null and value.current.plies_from_null == 0;
        const null_eval = if (comptime features.shallow_selectivity)
            if (shallow.known) shallow.pruning_eval else binding.evaluate(value).raw()
        else
            binding.evaluate(value).raw();
        const null_reduction: u16 = if (comptime features.main_selectivity_sync and
            features.dynamic_null_move)
            if (depth >= null_move_min_depth)
                dynamicNullMoveReduction(depth, null_eval, beta)
            else
                fixed_null_move_reduction
        else
            fixed_null_move_reduction;
        if (!pv_node and beta == alpha_initial + 1 and depth > null_reduction + 1 and
            value.current.checkers == 0 and !after_null and beta_score.isOrdinary() and
            hasNonPawnMaterial(value) and null_eval >= beta)
        {
            context.observer.nullMoveAttempt();
            if (comptime features.main_selectivity_sync and features.dynamic_null_move)
                context.observer.nullMoveReduction(null_reduction);
            makeNull(value, binding, context.thread, ply);
            if (comptime features.search_context)
                context.thread.ply_contexts[ply + 1] = types.PlyContext.afterNull(
                    value.current.checkers != 0,
                );
            const child = negamax(
                features,
                true,
                context,
                value,
                binding,
                control,
                types.DepthIntent.reduced(depth - 1, null_reduction),
                ply + 1,
                -beta,
                -beta + 1,
                .all,
                .null_probe,
            ) catch |err| {
                unmakeNull(value, binding);
                return err;
            };
            const null_value = negated(child);
            unmakeNull(value, binding);
            if ((null_value.bound == .lower or null_value.bound == .exact) and null_value.raw >= beta) {
                context.observer.nullMoveFailHigh();
                const verification = try negamax(
                    features,
                    false,
                    context,
                    value,
                    binding,
                    control,
                    types.DepthIntent.reduced(depth, null_reduction),
                    ply,
                    beta - 1,
                    beta,
                    expectation,
                    .null_verification,
                );
                const verified = (verification.bound == .lower or verification.bound == .exact) and
                    verification.raw >= beta;
                context.observer.nullMoveVerification(verified);
                if (verified) {
                    context.observer.prune(.null_move);
                    const cutoff = NodeValue{ .raw = beta, .bound = .lower, .provenance = .null_move };
                    if (!exclusion_node)
                        storeTable(context, value.current.key, .none, cutoff, tableStaticEval(features, shallow), depth, ply);
                    return resolved(cutoff, active_depth);
                }
            }
        }
    }

    if (comptime features.probcut) {
        if (try tryProbCut(
            features,
            context,
            value,
            binding,
            control,
            depth,
            ply,
            alpha_initial,
            beta,
            pv_node,
            exclusion_node,
            shallow,
            shallow_has_non_pawn_material,
            table_evidence,
        )) |cutoff| return resolved(cutoff, active_depth);
    }

    var moves = chess.position.MoveList.init();
    var delay_non_tactical_quiets = if (comptime features.live_history_staging)
        ply != 0 and value.current.checkers == 0 and !exclusion_node and
            context.heuristics != null
    else
        false;
    if (ply == 0) {
        if (context.root_moves) |restricted| {
            for (restricted) |chess_move| moves.append(chess_move);
        } else {
            chess.movegen.generate(.all, value, &moves);
        }
    } else if (delay_non_tactical_quiets) {
        chess.movegen.generate(.tacticals, value, &moves);
        context.observer.liveHistoryTacticals(moves.count);
        if (table_evidence.chess_move) |tt_move| {
            if (!chess.movegen.isTactical(value, tt_move)) moves.append(tt_move);
        }
        // With no legal TT/tactical move, the quiet subset is required now to
        // distinguish an ordinary quiet node from stalemate. No descendant
        // can update history before that proof, so delaying it adds no value.
        if (moves.count == 0) {
            chess.movegen.generateAppend(.non_tactical_quiets, value, &moves);
            context.observer.liveHistoryQuiets(moves.count);
            delay_non_tactical_quiets = false;
        }
    } else {
        chess.movegen.generate(.all, value, &moves);
    }
    context.observer.generated(moves.count);
    if (moves.count == 0) {
        const terminal = terminalNode(value, ply);
        if (!exclusion_node)
            storeTable(context, value.current.key, .none, terminal, tableStaticEval(features, shallow), depth, ply);
        return resolved(terminal, active_depth);
    }

    var singular_move: chess.move.Move = .none;
    var singular_extension_plies: u16 = 0;
    if (comptime features.search_context and features.depth_authority and features.singular_extension) {
        const singular_eligibility = singularExtensionEligibility(
            features,
            depth,
            ply,
            value.current.checkers != 0,
            exclusion_node,
            table_evidence,
        );
        if (singular_eligibility == .provenance_rejected)
            context.observer.singularProvenanceRejection();
        if (singular_eligibility == .eligible) {
            const tt_move = table_evidence.chess_move.?;
            const record = table_evidence.record.?;
            const threshold = singularThreshold(record.value);
            const saved_context = context.thread.ply_contexts[ply];
            context.thread.ply_contexts[ply] = saved_context.withExcluded(tt_move);
            context.observer.singularAttempt();
            // The exclusion search re-enters this ply, so the observer's
            // per-ply path facts are saved and restored around it exactly like
            // the ply context itself.
            context.observer.exclusionEnter(ply);
            const alternatives = negamax(
                features,
                false,
                context,
                value,
                binding,
                control,
                types.DepthIntent.reduced(depth, 2),
                ply,
                threshold - 1,
                threshold,
                .all,
                .singular_probe,
            ) catch |err| {
                context.observer.exclusionExit(ply);
                context.thread.ply_contexts[ply] = saved_context;
                context.thread.pv_lengths[ply] = 0;
                return err;
            };
            context.observer.exclusionExit(ply);
            context.thread.ply_contexts[ply] = saved_context;
            context.thread.pv_lengths[ply] = 0;
            singular_extension_plies = singularExtensionPlies(
                features,
                depth,
                expectation,
                record,
                alternatives,
                threshold,
            );
            const singular = singular_extension_plies != 0;
            context.observer.singularVerification(singular);
            if (singular) {
                singular_move = tt_move;
                if (singular_extension_plies == 2)
                    context.observer.singularDoubleExtension();
            } else if (comptime features.depth_authority_sync and features.singular_multi_cut) {
                // The TT value poses the multi-cut question but never answers
                // it. A searched exclusion lower bound must first establish
                // the singular target and, when needed, beta itself.
                if (expectation == .cut and (score.Score{ .raw_value = beta }).isOrdinary() and
                    exclusionProvesAtLeast(alternatives, threshold))
                {
                    if (threshold >= beta) {
                        context.observer.singularMultiCut(true);
                        context.observer.prune(.multi_cut);
                        return resolved(
                            .{ .raw = beta, .bound = .lower, .provenance = .speculative_cutoff },
                            active_depth,
                        );
                    }
                    if (record.value.raw() >= beta) {
                        const verification_depth = @max(@as(u16, 1), (depth + 1) / 2);
                        context.thread.ply_contexts[ply] = saved_context.withExcluded(tt_move);
                        context.observer.singularMultiCutProbe();
                        context.observer.exclusionEnter(ply);
                        const verification = negamax(
                            features,
                            false,
                            context,
                            value,
                            binding,
                            control,
                            types.DepthIntent.reduced(depth, depth - verification_depth),
                            ply,
                            beta - 1,
                            beta,
                            .cut,
                            .singular_probe,
                        ) catch |err| {
                            context.observer.exclusionExit(ply);
                            context.thread.ply_contexts[ply] = saved_context;
                            context.thread.pv_lengths[ply] = 0;
                            return err;
                        };
                        context.observer.exclusionExit(ply);
                        context.thread.ply_contexts[ply] = saved_context;
                        context.thread.pv_lengths[ply] = 0;
                        const cutoff = exclusionProvesAtLeast(verification, beta);
                        context.observer.singularMultiCut(cutoff);
                        if (cutoff) {
                            context.observer.prune(.multi_cut);
                            return resolved(
                                .{ .raw = beta, .bound = .lower, .provenance = .speculative_cutoff },
                                active_depth,
                            );
                        }
                    }
                }
            }
        }
    }
    const reply_context = if (comptime features.search_context and features.contextual_history)
        if (context.thread.ply_contexts[ply].arrival == .move)
            ordering.replyContext(value, context.thread.ply_contexts[ply].previous_move)
        else
            null
    else
        null;
    const continuation_contexts = continuationSet(features, context.thread, ply, value.side_to_move);
    var picker = if (comptime features.live_history_staging)
        ordering.LiveHistoryPicker.init(
            features.capture_history,
            &moves,
            value,
            binding,
            table_evidence.chess_move,
            context.heuristics,
            context.params,
            ply,
            reply_context,
            continuation_contexts,
            context.heuristics != null,
            @TypeOf(context.observer.*).observes_move_sources,
            delay_non_tactical_quiets,
        )
    else
        ordering.Picker.init(
            features.capture_history,
            &moves,
            value,
            binding,
            table_evidence.chess_move,
            context.heuristics,
            context.params,
            ply,
            reply_context,
            continuation_contexts,
            context.heuristics != null,
            @TypeOf(context.observer.*).observes_move_sources,
        );

    const original_alpha = alpha_initial;
    var alpha = alpha_initial;
    var best = -score.infinity_raw;
    var best_provenance: types.Provenance = .full_search;
    var best_reduction: u16 = 1;
    var best_move: chess.move.Move = .none;
    var searched_move_count: usize = 0;
    var pruned_late_move = false;
    var searched_quiets: [
        if (features.search_context and features.contextual_history)
            chess.types.move_capacity
        else
            0
    ]chess.move.Move = undefined;
    var searched_quiet_count: usize = 0;
    var lmr_positive_feedback: [
        if (features.search_context and features.contextual_history and features.lmr_synchronization)
            chess.types.move_capacity
        else
            0
    ]chess.move.Move = undefined;
    var lmr_positive_feedback_count: usize = 0;
    var searched_captures: [
        if (features.capture_history) chess.types.move_capacity else 0
    ]chess.move.Move = undefined;
    var searched_capture_count: usize = 0;
    while (true) {
        const maybe_selection = picker.next();
        if (comptime features.live_history_staging) {
            if (maybe_selection == null) {
                if (picker.enterQuiets(
                    features.capture_history,
                    value,
                    binding,
                    table_evidence.chess_move,
                    context.heuristics,
                    context.params,
                    ply,
                    reply_context,
                    continuation_contexts,
                )) |generated| {
                    context.observer.generated(generated);
                    context.observer.liveHistoryQuiets(generated);
                    continue;
                }
            }
        }
        const selection = maybe_selection orelse break;
        const chess_move = selection.chess_move;
        const move_index = selection.index;
        if (exclusion_node and chess_move.raw() == excluded_move.raw()) {
            context.observer.exclusionMoveSkipped();
            continue;
        }
        const search_index = searched_move_count;
        searched_move_count += 1;
        const root_nodes_before = if (ply == 0) context.thread.nodes else 0;
        if (ply == 0 and @hasDecl(@TypeOf(control.*), "rootMove"))
            control.rootMove(depth, chess_move, searched_move_count, context.thread.nodes);
        const in_check = value.current.checkers != 0;
        const is_capture = chess.movegen.isCapture(value, chess_move);
        const is_promotion = chess_move.kind() == .promotion;
        const quiet = !is_capture and !is_promotion;
        if (comptime features.capture_history and @TypeOf(context.observer.*).observes_capture_history) {
            if (is_capture) if (context.heuristics) |heuristics|
                context.observer.captureHistorySelection(
                    .main,
                    heuristics.captureScore(value, chess_move) != 0,
                );
        }
        if (comptime features.search_context and features.contextual_history) {
            if (quiet) if (reply_context) |reply| if (context.heuristics) |heuristics|
                context.observer.contextualHistoryLookup(
                    heuristics.replyScore(value, reply, chess_move) != 0,
                );
        }
        if (comptime features.search_context and features.contextual_history and
            features.continuation_history)
        {
            if (quiet) if (context.heuristics) |heuristics|
                for (continuation_contexts.items, 0..) |maybe_continuation, slot| {
                    const continuation = maybe_continuation orelse continue;
                    context.observer.continuationHistoryLookup(
                        @enumFromInt(slot),
                        heuristics.continuationScore(value, continuation, chess_move) != 0,
                        continuation.from_check,
                        continuation.tactical,
                    );
                };
        }
        const move_source = selection.source;
        const history_confident = if (comptime features.history_lmr)
            if (quiet)
                if (context.heuristics) |heuristics|
                    heuristics.quietScore(value.side_to_move, chess_move) > 0
                else
                    false
            else
                false
        else
            false;
        const synchronized_history = if (comptime features.lmr_synchronization and
            features.lmr_sync_history)
            if (quiet)
                if (context.heuristics) |heuristics|
                    heuristics.quietConfidence(
                        value,
                        reply_context,
                        continuation_contexts,
                        chess_move,
                    )
                else
                    ordering.HistoryConfidence.neutral
            else
                ordering.HistoryConfidence.neutral
        else
            ordering.HistoryConfidence.neutral;
        const selectivity_history = if (comptime features.main_selectivity_sync and
            features.history_pruning)
            if (quiet)
                if (context.heuristics) |heuristics|
                    heuristics.quietConfidence(
                        value,
                        reply_context,
                        continuation_contexts,
                        chess_move,
                    )
                else
                    ordering.HistoryConfidence.neutral
            else
                ordering.HistoryConfidence.neutral
        else
            ordering.HistoryConfidence.neutral;
        if (history_confident and search_index == 3 and lateMoveEligible(
            features,
            depth,
            search_index,
            quiet,
            in_check,
            value.current.checkers != 0,
        )) context.observer.lmrHistoryProtection();

        var shallow_cause: ?diagnostics.PruneCause = null;
        var main_see_candidate = false;
        var capture_futility_candidate = false;
        var capture_futility_failed = false;
        if (comptime features.shallow_selectivity) {
            if (quiet) {
                if (lateMovePruneEligible(
                    features,
                    shallow,
                    pv_node,
                    depth,
                    search_index,
                    shallow_has_non_pawn_material,
                    alpha,
                    beta,
                )) {
                    context.observer.lateMovePruningCandidate();
                    if (comptime features.main_selectivity_sync and features.history_pruning)
                        context.observer.selectivityHistory(selectivity_history);
                    const base_threshold = lateMovePruneThreshold(context.params, depth, shallow.improving);
                    const threshold = historyLateMovePruneThreshold(
                        features,
                        base_threshold,
                        selectivity_history,
                    );
                    const base_pruned = search_index >= base_threshold;
                    const pruned = search_index >= threshold;
                    if (selectivity_history == .positive and base_pruned and !pruned) {
                        context.observer.historyPruningProtection();
                    } else if (selectivity_history == .negative and threshold != base_threshold) {
                        context.observer.historyPruningTightening(pruned and !base_pruned);
                    }
                    if (pruned) shallow_cause = .late_move;
                }
                if (shallow_cause == null and quietFutilityEligible(
                    features,
                    shallow,
                    pv_node,
                    depth,
                    search_index,
                    shallow_has_non_pawn_material,
                    alpha,
                    beta,
                )) {
                    context.observer.quietFutilityCandidate();
                    if (shallow.pruning_eval + quietFutilityMargin(context.params, depth, shallow.improving) <= alpha) {
                        if (selectivity_history == .positive)
                            context.observer.historyPruningProtection()
                        else
                            shallow_cause = .futility;
                    }
                }
            } else if (seePruneEligible(
                features,
                shallow,
                pv_node,
                depth,
                search_index,
                is_capture,
                is_promotion,
                shallow_has_non_pawn_material,
                alpha,
                beta,
            )) {
                const base_threshold = seePruningThreshold(context.params, depth);
                const synchronized_threshold = synchronizedSeePruningThreshold(
                    features,
                    context.params,
                    shallow.pruning_eval,
                    alpha,
                    depth,
                );
                const base_passed = binding.seeAtLeast(value, chess_move, base_threshold);
                const see_pruned = if (!base_passed)
                    true
                else if (synchronized_threshold > base_threshold) blk: {
                    capture_futility_candidate = true;
                    const passed = binding.seeAtLeast(value, chess_move, synchronized_threshold);
                    capture_futility_failed = !passed;
                    break :blk !passed;
                } else false;
                main_see_candidate = true;
                if (see_pruned) shallow_cause = .see;
            }
        }

        make(value, binding, context.thread, ply, chess_move);
        if (comptime features.search_context)
            context.thread.ply_contexts[ply + 1] = types.PlyContext.afterMove(
                chess_move,
                value.physical.pieceOn(chess_move.to()).pieceType(),
                in_check,
                is_capture or is_promotion,
                value.current.checkers != 0,
            );
        const gives_check = value.current.checkers != 0;
        if (main_see_candidate)
            context.observer.mainSeePruning(shallow_cause == .see and !gives_check);
        if (capture_futility_candidate)
            context.observer.captureFutility(
                capture_futility_failed and !gives_check,
                capture_futility_failed and gives_check,
            );
        if (shallow_cause) |cause| {
            if (!gives_check) {
                unmake(value, binding, context.thread, ply, chess_move);
                context.observer.prune(cause);
                pruned_late_move = true;
                continue;
            }
        }
        if (comptime features.search_context and features.contextual_history) {
            if (quiet and !exclusion_node and reply_context != null) {
                searched_quiets[searched_quiet_count] = chess_move;
                searched_quiet_count += 1;
            }
        }
        if (comptime features.capture_history) {
            if (is_capture and !exclusion_node and context.heuristics != null) {
                searched_captures[searched_capture_count] = chess_move;
                searched_capture_count += 1;
            }
        }
        context.observer.searched(.main);
        context.observer.moveSource(move_source);
        // SAFETY: each branch below initializes `child` before it is read.
        var child: NodeValue = undefined;
        // SAFETY: the same exhaustive branch initializes `candidate`.
        var candidate: NodeValue = undefined;
        var full_width = search_index == 0 or !pv_node;
        var reduced_only = false;
        var reduction: u16 = 0;
        var lmr_full_depth_fail_low = false;
        var lmr_researched = false;
        const singular = singular_move.isChessMove() and chess_move.raw() == singular_move.raw();
        if (singular) context.observer.extension(.singular);
        const full_child_depth = if (singular)
            types.DepthIntent.extended(depth - 1, singular_extension_plies)
        else
            types.DepthIntent.full(depth - 1);
        const reduce = !singular and shouldReduceLateMove(
            features,
            depth,
            search_index,
            quiet,
            in_check,
            value.current.checkers != 0,
            history_confident,
        );
        if (reduce) {
            reduction = synchronizedLateMoveReduction(
                features,
                context.params,
                depth,
                search_index,
                .{
                    .improving = if (shallow.known) shallow.improving else null,
                    .expectation = expectation,
                    .has_tt_move = table_evidence.chess_move != null,
                    .singular_context = singular_move.isChessMove(),
                    .history = synchronized_history,
                },
                context.observer,
            );
            context.observer.lmrProbe(reduction);
            child = negamax(
                features,
                true,
                context,
                value,
                binding,
                control,
                types.DepthIntent.reduced(depth - 1, reduction),
                ply + 1,
                -alpha - 1,
                -alpha,
                expectation.child(false),
                .reduced_probe,
            ) catch |err| {
                unmake(value, binding, context.thread, ply, chess_move);
                return err;
            };
            candidate = negated(child);
            if (candidate.raw > alpha) {
                context.observer.lmrResearch();
                lmr_researched = true;
                child = negamax(
                    features,
                    true,
                    context,
                    value,
                    binding,
                    control,
                    full_child_depth,
                    ply + 1,
                    if (pv_node) -alpha - 1 else -beta,
                    -alpha,
                    expectation.child(false),
                    .reduction_research,
                ) catch |err| {
                    unmake(value, binding, context.thread, ply, chess_move);
                    return err;
                };
                candidate = negated(child);
                lmr_full_depth_fail_low = candidate.bound == .upper and candidate.raw <= alpha;
            } else {
                reduced_only = true;
                context.observer.lmrAccepted();
            }
        } else if (search_index == 0 or !pv_node) {
            child = negamax(
                features,
                true,
                context,
                value,
                binding,
                control,
                full_child_depth,
                ply + 1,
                -beta,
                -alpha,
                expectation.child(search_index == 0 and pv_node),
                if (search_index == 0) .first_move else .scout,
            ) catch |err| {
                unmake(value, binding, context.thread, ply, chess_move);
                return err;
            };
            candidate = negated(child);
        } else {
            child = negamax(
                features,
                true,
                context,
                value,
                binding,
                control,
                full_child_depth,
                ply + 1,
                -alpha - 1,
                -alpha,
                expectation.child(false),
                .scout,
            ) catch |err| {
                unmake(value, binding, context.thread, ply, chess_move);
                return err;
            };
            candidate = negated(child);
        }
        if (search_index != 0 and pv_node and candidate.raw > alpha and candidate.raw < beta) {
            full_width = true;
            child = negamax(
                features,
                true,
                context,
                value,
                binding,
                control,
                full_child_depth,
                ply + 1,
                -beta,
                -alpha,
                expectation.child(true),
                .pv_research,
            ) catch |err| {
                unmake(value, binding, context.thread, ply, chess_move);
                return err;
            };
            candidate = negated(child);
        }
        unmake(value, binding, context.thread, ply, chess_move);
        if (ply == 0) {
            context.root_iteration.append(.{
                .chess_move = chess_move,
                .evidence = evidence(candidate.raw, candidate.bound, candidate.provenance),
                .nodes = context.thread.nodes - root_nodes_before,
            });
        }
        if (comptime features.search_context and features.contextual_history and
            features.lmr_synchronization)
        {
            if (lmr_researched and quiet and !exclusion_node) {
                const positive = candidate.raw > alpha;
                const enabled = if (positive)
                    features.lmr_sync_positive_feedback
                else
                    features.lmr_sync_negative_feedback;
                if (enabled) if (reply_context) |reply| if (context.heuristics) |heuristics| {
                    // Feedback owns this move's contextual training for this
                    // node. Remove it from the later winner/loser population;
                    // a confirmed alpha rise is remembered so an eventual
                    // exact/cutoff outcome does not reward it a second time.
                    std.debug.assert(searched_quiet_count != 0);
                    std.debug.assert(searched_quiets[searched_quiet_count - 1].raw() == chess_move.raw());
                    searched_quiet_count -= 1;
                    recordLmrContextFeedback(
                        heuristics,
                        value,
                        reply,
                        continuation_contexts,
                        chess_move,
                        depth,
                        positive,
                        context.observer,
                    );
                    if (positive) {
                        lmr_positive_feedback[lmr_positive_feedback_count] = chess_move;
                        lmr_positive_feedback_count += 1;
                    }
                };
            }
        }
        if (comptime features.search_context and features.contextual_history and
            features.lmr_reply_feedback and !features.lmr_synchronization)
        {
            if (lmr_full_depth_fail_low and quiet and !exclusion_node) {
                if (reply_context) |reply| if (context.heuristics) |heuristics| {
                    // The current quiet was appended last after it survived
                    // pruning. It receives this one authoritative penalty now,
                    // so remove it from any later exact/cutoff loser set and
                    // avoid double training the same node outcome.
                    std.debug.assert(searched_quiet_count != 0);
                    std.debug.assert(searched_quiets[searched_quiet_count - 1].raw() == chess_move.raw());
                    heuristics.recordReplyFailure(value, reply, chess_move, depth);
                    searched_quiet_count -= 1;
                    context.observer.contextualHistoryLmrFailure();
                };
            }
        }

        if (candidate.raw > best) {
            best = candidate.raw;
            best_move = chess_move;
            best_provenance = if (reduced_only)
                .reduced_search
            else if (full_width)
                .full_search
            else
                .pvs_probe;
            best_reduction = if (reduced_only) reduction else 1;
            if (!reduced_only and !exclusion_node) extendPv(context.thread, ply, chess_move);
        }
        if (candidate.raw > alpha) alpha = candidate.raw;
        if (alpha >= beta) {
            context.observer.cutoff(.main);
            context.observer.failHigh(search_index, move_source);
            if (quiet and !exclusion_node) {
                if (context.heuristics) |heuristics| {
                    if (comptime features.search_context and features.contextual_history) {
                        if (reply_context) |reply|
                            recordContextualQuietOutcome(
                                heuristics,
                                value,
                                reply,
                                continuation_contexts,
                                chess_move,
                                searched_quiets[0..searched_quiet_count],
                                lmr_positive_feedback[0..lmr_positive_feedback_count],
                                depth,
                                .cutoff,
                                context.observer,
                            );
                    }
                    if (comptime features.balanced_history)
                        heuristics.recordQuietCutoff(value.side_to_move, chess_move, depth, ply)
                    else
                        heuristics.recordLegacyQuietCutoff(value.side_to_move, chess_move, depth, ply);
                    context.observer.historyReward(depth);
                    if (comptime features.balanced_history) {
                        for (moves.slice()[0..move_index]) |prior_move| {
                            if (!chess.movegen.isCapture(value, prior_move) and
                                prior_move.kind() != .promotion)
                            {
                                heuristics.recordQuietFailure(value.side_to_move, prior_move, depth);
                                context.observer.historyPenalty(depth);
                            }
                        }
                    }
                }
            }
            if (comptime features.capture_history) {
                if (is_capture and !exclusion_node and ply != 0) {
                    if (context.heuristics) |heuristics|
                        recordCaptureOutcome(
                            heuristics,
                            value,
                            chess_move,
                            searched_captures[0..searched_capture_count],
                            depth,
                            .cutoff,
                            context.observer,
                        );
                }
            }
            const cutoff = NodeValue{
                .raw = best,
                .bound = .lower,
                .provenance = if (exclusion_node) .exclusion_search else best_provenance,
            };
            if (!exclusion_node)
                storeTable(context, value.current.key, best_move, cutoff, tableStaticEval(features, shallow), depth, ply);
            if (!exclusion_node) if (table_evidence.chess_move) |tt_move|
                context.observer.ttBest(tt_move.raw() == best_move.raw());
            recordCorrectionEvidence(features, context, value, shallow, cutoff, depth, exclusion_node, false);
            return resolved(cutoff, active_depth);
        }
    }
    if (exclusion_node and searched_move_count == 0) {
        return resolved(.{
            .raw = alpha_initial,
            .bound = .upper,
            .provenance = .exclusion_search,
        }, active_depth);
    }
    const result = NodeValue{
        .raw = best,
        .bound = if (best <= original_alpha) .upper else .exact,
        .provenance = if (exclusion_node) .exclusion_search else best_provenance,
    };
    if (comptime features.search_context and features.contextual_history) {
        if (!exclusion_node and result.bound == .exact and best_move.isChessMove() and
            !chess.movegen.isCapture(value, best_move) and best_move.kind() != .promotion)
        {
            if (reply_context) |reply| if (context.heuristics) |heuristics|
                recordContextualQuietOutcome(
                    heuristics,
                    value,
                    reply,
                    continuation_contexts,
                    best_move,
                    searched_quiets[0..searched_quiet_count],
                    lmr_positive_feedback[0..lmr_positive_feedback_count],
                    depth,
                    .exact,
                    context.observer,
                );
        }
    }
    if (comptime features.capture_history) {
        if (!exclusion_node and ply != 0 and result.bound == .exact and best_move.isChessMove() and
            chess.movegen.isCapture(value, best_move))
        {
            if (context.heuristics) |heuristics|
                recordCaptureOutcome(
                    heuristics,
                    value,
                    best_move,
                    searched_captures[0..searched_capture_count],
                    depth,
                    .exact,
                    context.observer,
                );
        }
    }
    if (!exclusion_node) {
        // A fail-low that skipped a late move under shallow selectivity is
        // speculative in the same sense as a reduced fail-low: some legal
        // sibling was never searched, so it cannot claim full nominal-depth
        // TT authority even though the winning move's own evidence is exact.
        const stored_result = speculativeStoreValue(result, pruned_late_move);
        storeTableWithReduction(
            context,
            value.current.key,
            best_move,
            stored_result,
            tableStaticEval(features, shallow),
            depth,
            if (result.provenance == .reduced_search) best_reduction else 1,
            ply,
        );
    }
    if (!exclusion_node) if (table_evidence.chess_move) |tt_move|
        context.observer.ttBest(tt_move.raw() == best_move.raw());
    recordCorrectionEvidence(features, context, value, shallow, result, depth, exclusion_node, pruned_late_move);
    return resolved(result, active_depth);
}

fn continuationSet(
    comptime features: types.Features,
    thread: *const types.ThreadState,
    ply: usize,
    side: chess.types.Color,
) ordering.ContinuationSet {
    var result: ordering.ContinuationSet = .{};
    if (comptime !features.search_context or !features.contextual_history or
        !features.continuation_history) return result;
    if (comptime features.continuation_distance_2)
        result.items[@intFromEnum(ordering.ContinuationDistance.two)] =
            continuationAt(thread, ply, side, 2);
    if (comptime features.continuation_distance_4)
        result.items[@intFromEnum(ordering.ContinuationDistance.four)] =
            continuationAt(thread, ply, side, 4);
    if (comptime features.continuation_distance_6)
        result.items[@intFromEnum(ordering.ContinuationDistance.six)] =
            continuationAt(thread, ply, side, 6);
    return result;
}

fn continuationAt(
    thread: *const types.ThreadState,
    ply: usize,
    side: chess.types.Color,
    comptime distance: usize,
) ?ordering.ContinuationContext {
    if (ply < distance) return null;
    const source_ply = ply + 1 - distance;
    var cursor = source_ply;
    while (cursor <= ply) : (cursor += 1)
        if (thread.ply_contexts[cursor].arrival != .move) return null;
    const source = thread.ply_contexts[source_ply];
    return ordering.continuationContext(
        side,
        source.previous_piece,
        source.previous_to,
        source.previous_from_check,
        source.previous_tactical,
    );
}

fn recordContextualQuietOutcome(
    heuristics: *ordering.State,
    value: *const chess.position.Position,
    reply: ordering.ReplyContext,
    continuations: ordering.ContinuationSet,
    winner: chess.move.Move,
    searched_quiets: []const chess.move.Move,
    pretrained_winners: []const chess.move.Move,
    depth: u16,
    disposition: types.NodeDisposition,
    observer: anytype,
) void {
    std.debug.assert(disposition == .exact or disposition == .cutoff);
    std.debug.assert(!chess.movegen.isCapture(value, winner) and winner.kind() != .promotion);
    const winner_pretrained = containsMove(pretrained_winners, winner);
    var winner_seen = winner_pretrained;
    var penalty_count: usize = 0;
    for (searched_quiets) |candidate| {
        if (candidate.raw() == winner.raw()) {
            winner_seen = true;
            continue;
        }
        // Piece-to continuation keys intentionally generalize across origins.
        // Do not reward and penalize the same key when two equal piece types
        // can reach the same destination in one position.
        if (sameReplyMoveKey(value, winner, candidate)) continue;
        heuristics.recordReplyFailure(value, reply, candidate, depth);
        penalty_count += 1;
    }
    std.debug.assert(winner_seen);
    if (!winner_pretrained) heuristics.recordReplySuccess(value, reply, winner, depth);
    observer.contextualHistoryUpdate(disposition, penalty_count, !winner_pretrained);
    for (continuations.items, 0..) |maybe_continuation, slot| {
        const continuation = maybe_continuation orelse continue;
        var continuation_penalties: usize = 0;
        for (searched_quiets) |candidate| {
            if (candidate.raw() == winner.raw() or sameReplyMoveKey(value, winner, candidate))
                continue;
            heuristics.recordContinuationFailure(value, continuation, candidate, depth);
            continuation_penalties += 1;
        }
        if (!winner_pretrained)
            heuristics.recordContinuationSuccess(value, continuation, winner, depth);
        observer.continuationHistoryUpdate(
            @enumFromInt(slot),
            disposition,
            continuation_penalties,
            !winner_pretrained,
        );
    }
}

fn recordLmrContextFeedback(
    heuristics: *ordering.State,
    value: *const chess.position.Position,
    reply: ordering.ReplyContext,
    continuations: ordering.ContinuationSet,
    chess_move: chess.move.Move,
    depth: u16,
    positive: bool,
    observer: anytype,
) void {
    if (positive)
        heuristics.recordReplySuccess(value, reply, chess_move, depth)
    else
        heuristics.recordReplyFailure(value, reply, chess_move, depth);
    observer.contextualHistoryLmrFeedback(positive);
    for (continuations.items, 0..) |maybe_continuation, slot| {
        const continuation = maybe_continuation orelse continue;
        if (positive)
            heuristics.recordContinuationSuccess(value, continuation, chess_move, depth)
        else
            heuristics.recordContinuationFailure(value, continuation, chess_move, depth);
        observer.continuationHistoryLmrFeedback(@enumFromInt(slot), positive);
    }
}

fn containsMove(moves: []const chess.move.Move, needle: chess.move.Move) bool {
    for (moves) |candidate| if (candidate.raw() == needle.raw()) return true;
    return false;
}

fn recordCaptureOutcome(
    heuristics: *ordering.State,
    value: *const chess.position.Position,
    winner: chess.move.Move,
    searched_captures: []const chess.move.Move,
    depth: u16,
    disposition: types.NodeDisposition,
    observer: anytype,
) void {
    std.debug.assert(disposition == .exact or disposition == .cutoff);
    std.debug.assert(chess.movegen.isCapture(value, winner));
    heuristics.recordCaptureSuccess(value, winner, depth);
    var winner_seen = false;
    var penalty_count: usize = 0;
    for (searched_captures) |candidate| {
        if (candidate.raw() == winner.raw()) {
            winner_seen = true;
            continue;
        }
        // Promotion variants and transposing movers can otherwise address the
        // same relation. Do not reward and penalize one key for one outcome.
        if (ordering.sameCaptureKey(value, winner, candidate)) continue;
        heuristics.recordCaptureFailure(value, candidate, depth);
        penalty_count += 1;
    }
    std.debug.assert(winner_seen);
    observer.captureHistoryUpdate(disposition, penalty_count);
}

fn sameReplyMoveKey(
    value: *const chess.position.Position,
    first: chess.move.Move,
    second: chess.move.Move,
) bool {
    const first_piece = value.physical.pieceOn(first.from());
    const second_piece = value.physical.pieceOn(second.from());
    std.debug.assert(first_piece != .none and second_piece != .none);
    return first_piece.pieceType() == second_piece.pieceType() and first.to() == second.to();
}

fn quiescence(
    comptime features: types.Features,
    context: anytype,
    value: *chess.position.Position,
    binding: anytype,
    control: anytype,
    ply: usize,
    alpha_initial: i32,
    beta: i32,
    expectation: types.NodeExpectation,
) Abort!NodeValue {
    const result = try quiescenceNode(
        features,
        context,
        value,
        binding,
        control,
        ply,
        alpha_initial,
        beta,
        expectation,
    );
    if (comptime features.search_context)
        context.observer.nodeOutcome(types.OutcomeAttribution.init(
            .quiescence,
            types.DepthIntent.full(0),
            expectation,
            evidence(result.raw, result.bound, result.provenance),
        ));
    return result;
}

fn quiescenceNode(
    comptime features: types.Features,
    context: anytype,
    value: *chess.position.Position,
    binding: anytype,
    control: anytype,
    ply: usize,
    alpha_initial: i32,
    beta: i32,
    expectation: types.NodeExpectation,
) Abort!NodeValue {
    const pv_node = expectation.isPrincipal();
    std.debug.assert(pv_node or beta == alpha_initial + 1);
    try context.visit(control, ply, .quiescence, expectation);
    if (comptime features.search_context)
        context.observer.nodeContext(
            .quiescence,
            ply,
            context.thread.ply_contexts[ply],
            .quiescence,
            types.DepthIntent.full(0),
            expectation,
        );
    context.thread.pv_lengths[ply] = 0;
    if (chess.draw.isSearchDraw(value, @intCast(ply)))
        return .{ .raw = 0, .bound = .exact, .provenance = .terminal };
    if (ply >= chess.types.max_ply - 1)
        return .{ .raw = binding.evaluate(value).raw(), .bound = .exact, .provenance = .static_eval };

    const table_evidence = probeTable(context, value, 0, ply, alpha_initial, beta);
    if (table_evidence.cutoff) |cutoff| return cutoff;

    const in_check = value.current.checkers != 0;
    var moves = chess.position.MoveList.init();
    chess.movegen.generate(.all, value, &moves);
    context.observer.generated(moves.count);
    if (moves.count == 0) {
        const terminal = terminalNode(value, ply);
        storeTable(context, value.current.key, .none, terminal, null, 0, ply);
        return terminal;
    }
    var picker = ordering.Picker.init(
        features.capture_history,
        &moves,
        value,
        binding,
        table_evidence.chess_move,
        context.heuristics,
        context.params,
        ply,
        null,
        .{},
        context.heuristics != null,
        @TypeOf(context.observer.*).observes_move_sources,
    );

    const original_alpha = alpha_initial;
    var alpha = alpha_initial;
    var best = -score.infinity_raw;
    var best_move: chess.move.Move = .none;
    var static_evidence: ShallowEvidence = .{};
    var baseline_provenance: types.Provenance = .qsearch_move;
    if (!in_check) {
        static_evidence = shallowEvidence(
            features,
            true,
            context,
            value,
            binding,
            ply,
            false,
            false,
            table_evidence.record,
        );
        // Step 5.4.1 gives correction history evaluation authority only. The
        // corrected value is therefore the qsearch stand-pat score, while
        // delta/SEE pruning below continues to consume `pruning_eval`, which
        // is derived from the uncorrected HCE and ordinary TT refinement.
        best = static_evidence.static_eval;
        baseline_provenance = qsearchBaselineProvenance(static_evidence, table_evidence.record);
        if (best >= beta) {
            context.observer.qsearchStandPat(true, false);
            const cutoff = NodeValue{ .raw = best, .bound = .lower, .provenance = baseline_provenance };
            storeTable(context, value.current.key, .none, cutoff, tableStaticEval(features, static_evidence), 0, ply);
            return cutoff;
        }
        if (best > alpha) alpha = best;
    }

    var searched_index: usize = 0;
    while (picker.next()) |selection| {
        const chess_move = selection.chess_move;
        const is_capture = chess.movegen.isCapture(value, chess_move);
        const is_promotion = chess_move.kind() == .promotion;
        if (comptime features.capture_history and @TypeOf(context.observer.*).observes_capture_history) {
            if (is_capture) if (context.heuristics) |heuristics|
                context.observer.captureHistorySelection(
                    .quiescence,
                    heuristics.captureScore(value, chess_move) != 0,
                );
        }
        if (!in_check and !is_capture and !is_promotion)
            continue;
        const move_source = selection.source;
        const see_non_losing = if (comptime features.qsearch_see)
            if (!in_check and is_capture and !is_promotion)
                binding.seeAtLeast(value, chess_move, 0)
            else
                true
        else
            true;
        const negative_see_candidate = qsearchSeeCandidate(
            features,
            in_check,
            is_capture,
            is_promotion,
            see_non_losing,
        );
        const delta_threshold = qsearchDeltaThreshold(
            features,
            context.params,
            pv_node,
            in_check,
            is_capture,
            is_promotion,
            static_evidence.pruning_eval,
            alpha,
            see_non_losing,
        );
        const delta_candidate = if (delta_threshold) |threshold|
            !binding.seeAtLeast(value, chess_move, threshold)
        else
            false;
        make(value, binding, context.thread, ply, chess_move);
        if (comptime features.search_context)
            context.thread.ply_contexts[ply + 1] = types.PlyContext.afterMove(
                chess_move,
                value.physical.pieceOn(chess_move.to()).pieceType(),
                in_check,
                is_capture or is_promotion,
                value.current.checkers != 0,
            );
        if (negative_see_candidate or delta_candidate) {
            const gives_check = value.current.checkers != 0;
            if (negative_see_candidate) context.observer.qsearchSee(gives_check);
            if (delta_candidate) context.observer.qsearchDelta(gives_check);
            if (!gives_check) {
                context.observer.prune(if (negative_see_candidate) .see else .qsearch_delta);
                unmake(value, binding, context.thread, ply, chess_move);
                continue;
            }
        }
        context.observer.searched(.quiescence);
        context.observer.moveSource(move_source);
        const child = quiescence(
            features,
            context,
            value,
            binding,
            control,
            ply + 1,
            -beta,
            -alpha,
            if (pv_node) .principal else expectation.child(false),
        ) catch |err| {
            unmake(value, binding, context.thread, ply, chess_move);
            return err;
        };
        const candidate = negated(child);
        unmake(value, binding, context.thread, ply, chess_move);
        if (candidate.raw > best) {
            best = candidate.raw;
            best_move = chess_move;
            extendPv(context.thread, ply, chess_move);
        }
        if (candidate.raw > alpha) alpha = candidate.raw;
        if (alpha >= beta) {
            if (!in_check) context.observer.qsearchStandPat(false, false);
            context.observer.cutoff(.quiescence);
            context.observer.failHigh(searched_index, move_source);
            const cutoff = NodeValue{ .raw = best, .bound = .lower, .provenance = .qsearch_move };
            storeTable(context, value.current.key, best_move, cutoff, tableStaticEval(features, static_evidence), 0, ply);
            if (table_evidence.chess_move) |tt_move|
                context.observer.ttBest(tt_move.raw() == best_move.raw());
            return cutoff;
        }
        searched_index += 1;
    }
    const final_provenance = qsearchFinalProvenance(in_check, best_move, baseline_provenance);
    if (final_provenance == .stand_pat) {
        context.observer.qsearchStandPat(false, true);
        const result = NodeValue{
            .raw = best,
            .bound = if (best <= original_alpha) .upper else .exact,
            .provenance = .stand_pat,
        };
        storeTable(context, value.current.key, .none, result, tableStaticEval(features, static_evidence), 0, ply);
        return result;
    }
    if (!in_check) context.observer.qsearchStandPat(false, false);
    const result = NodeValue{
        .raw = best,
        .bound = if (best <= original_alpha) .upper else .exact,
        .provenance = final_provenance,
    };
    storeTable(context, value.current.key, best_move, result, tableStaticEval(features, static_evidence), 0, ply);
    if (table_evidence.chess_move) |tt_move|
        context.observer.ttBest(tt_move.raw() == best_move.raw());
    return result;
}

const TableEvidence = struct {
    chess_move: ?chess.move.Move = null,
    record: ?tt.Record = null,
    cutoff: ?NodeValue = null,
};

fn probeTable(
    context: anytype,
    value: *const chess.position.Position,
    depth: u16,
    ply: usize,
    alpha: i32,
    beta: i32,
) TableEvidence {
    if (ply == 0 and context.root_moves != null) {
        context.observer.ttLookup(.unavailable);
        return .{};
    }
    const table = context.table orelse {
        context.observer.ttLookup(.unavailable);
        return .{};
    };
    const record = table.probe(value.current.key, ply, value.current.rule50) orelse {
        context.observer.ttLookup(.miss);
        return .{};
    };
    var chess_move: ?chess.move.Move = null;
    if (record.chess_move.raw() == chess.move.Move.none.raw()) {
        chess_move = null;
    } else if (record.chess_move.isChessMove() and chess.movegen.isLegal(value, record.chess_move)) {
        chess_move = record.chess_move;
    } else {
        context.observer.ttLookup(.illegal_move);
        return .{};
    }
    const sufficient_depth = record.depth >= depth;
    const usable_bound = switch (record.bound) {
        .exact => ply != 0 or chess_move != null,
        .lower => record.value.raw() >= beta,
        .upper => record.value.raw() <= alpha,
    };
    const usable = sufficient_depth and usable_bound;
    context.observer.ttProbe(record.producer, record.bound, usable);
    context.observer.ttLookup(if (!sufficient_depth)
        .depth_rejected
    else if (!usable_bound)
        .bound_rejected
    else
        .usable);
    if (!usable) return .{ .chess_move = chess_move, .record = record };
    // A TT record owns only its stored move, not a continuation. The next PV
    // row may still describe an earlier sibling because no child search ran
    // for this cutoff. Copying that row can splice two individually legal
    // lines into an illegal published sequence.
    if (chess_move) |move_value| setPvMove(context.thread, ply, move_value);
    return .{
        .chess_move = chess_move,
        .record = record,
        .cutoff = .{
            .raw = record.value.raw(),
            .bound = record.bound,
            .provenance = if (record.bound == .exact) .tt_exact else .tt_bound,
        },
    };
}

fn storeTable(
    context: anytype,
    key: chess.types.Key,
    chess_move: chess.move.Move,
    result: NodeValue,
    static_eval: ?i32,
    depth: u16,
    ply: usize,
) void {
    storeTableWithReduction(context, key, chess_move, result, static_eval, depth, 1, ply);
}

fn storeTableWithReduction(
    context: anytype,
    key: chess.types.Key,
    chess_move: chess.move.Move,
    result: NodeValue,
    static_eval: ?i32,
    depth: u16,
    reduction: u16,
    ply: usize,
) void {
    if (ply == 0 and context.root_moves != null) return;
    const table = context.table orelse return;
    const value = score.Score{ .raw_value = result.raw };
    if (!value.isValid() or value.isNone() or value.raw() == score.infinity_raw) return;
    const stored_depth = tableDepth(result.provenance, depth, reduction);
    const cached_eval = if (static_eval) |raw| score.Score.fromOrdinary(raw) else null;
    const outcome = table.store(key, chess_move, value, cached_eval, @intCast(stored_depth), result.bound, result.provenance, ply);
    context.observer.ttStore(result.provenance, result.bound, outcome);
}

fn make(
    value: *chess.position.Position,
    binding: anytype,
    thread: *types.ThreadState,
    ply: usize,
    chess_move: chess.move.Move,
) void {
    chess.transition.makeMove(value, chess_move, &thread.states[ply]);
    binding.update(value, .{ .delta = &thread.states[ply].delta, .direction = .forward });
}

fn unmake(
    value: *chess.position.Position,
    binding: anytype,
    thread: *types.ThreadState,
    ply: usize,
    chess_move: chess.move.Move,
) void {
    binding.update(value, .{ .delta = &thread.states[ply].delta, .direction = .backward });
    chess.transition.unmakeMove(value, chess_move);
}

fn makeNull(
    value: *chess.position.Position,
    binding: anytype,
    thread: *types.ThreadState,
    ply: usize,
) void {
    chess.transition.makeNull(value, &thread.states[ply]);
    binding.update(value, .{ .delta = &thread.states[ply].delta, .direction = .forward });
}

fn unmakeNull(value: *chess.position.Position, binding: anytype) void {
    const delta = &value.current.delta;
    binding.update(value, .{ .delta = delta, .direction = .backward });
    chess.transition.unmakeNull(value);
}

/// Step-5.1.4.4 ProbCut is a bounded tactical proof attempt, not a static
/// cutoff. At an ordinary non-PV zero-window node it considers at most two
/// ordered non-promotion captures. Quiescence must first clear a raised beta;
/// only then does a three-ply-reduced main search verify the same threshold.
/// The enclosing node returns fail-hard beta and stores only the verified
/// reduced horizon. Step 5.1.5.7 additionally permits compatible ordinary TT
/// evidence at that same reduced horizon to prove the raised bound directly
/// or suppress a redundant probe; shallower/speculative evidence remains only
/// a legal ordering hint.
fn tryProbCut(
    comptime features: types.Features,
    context: anytype,
    value: *chess.position.Position,
    binding: anytype,
    control: anytype,
    depth: u16,
    ply: usize,
    alpha: i32,
    beta: i32,
    pv_node: bool,
    exclusion_node: bool,
    shallow: ShallowEvidence,
    has_non_pawn_material: bool,
    table_evidence: TableEvidence,
) Abort!?NodeValue {
    const threshold = probCutThreshold(context.params, beta) orelse return null;
    if (!probCutEligible(
        features,
        depth,
        ply,
        pv_node,
        value.current.checkers != 0,
        exclusion_node,
        beta == alpha + 1,
        shallow.known,
        has_non_pawn_material,
    )) return null;

    context.observer.probCutNode();
    if (comptime features.main_selectivity_sync and features.probcut_tt) {
        switch (probCutTableDecision(table_evidence.record, depth, threshold)) {
            .cutoff => {
                context.observer.probCutTableCutoff();
                context.observer.prune(.probcut);
                return .{ .raw = beta, .bound = .lower, .provenance = .probcut };
            },
            .skip => {
                context.observer.probCutTableSkip();
                return null;
            },
            .search => {},
        }
    }
    var moves = chess.position.MoveList.init();
    chess.movegen.generate(.captures, value, &moves);
    context.observer.generated(moves.count);
    var picker = ordering.Picker.init(
        features.capture_history,
        &moves,
        value,
        binding,
        table_evidence.chess_move,
        context.heuristics,
        context.params,
        ply,
        null,
        .{},
        true,
        @TypeOf(context.observer.*).observes_move_sources,
    );

    const max_moves: usize = 2;
    var searched: usize = 0;
    while (picker.next()) |selection| {
        const chess_move = selection.chess_move;
        if (comptime features.capture_history and @TypeOf(context.observer.*).observes_capture_history) {
            if (chess.movegen.isCapture(value, chess_move)) if (context.heuristics) |heuristics|
                context.observer.captureHistorySelection(
                    .probcut,
                    heuristics.captureScore(value, chess_move) != 0,
                );
        }
        // Promotions have discontinuous material semantics and remain in the
        // full search. En passant is an ordinary capture here; SEE and the
        // normal transition path account for the removed pawn and king safety.
        if (chess_move.kind() == .promotion) continue;
        if (searched == max_moves) break;
        searched += 1;
        context.observer.probCutMove();

        make(value, binding, context.thread, ply, chess_move);
        if (comptime features.search_context)
            context.thread.ply_contexts[ply + 1] = types.PlyContext.afterMove(
                chess_move,
                value.physical.pieceOn(chess_move.to()).pieceType(),
                false,
                true,
                value.current.checkers != 0,
            );
        const q_child = quiescence(
            features,
            context,
            value,
            binding,
            control,
            ply + 1,
            -threshold,
            -threshold + 1,
            .all,
        ) catch |err| {
            unmake(value, binding, context.thread, ply, chess_move);
            return err;
        };
        const q_value = negated(q_child);
        const q_passed = (q_value.bound == .lower or q_value.bound == .exact) and
            q_value.raw >= threshold;
        context.observer.probCutQuiescence(q_passed);
        if (!q_passed) {
            unmake(value, binding, context.thread, ply, chess_move);
            continue;
        }

        const child = negamax(
            features,
            true,
            context,
            value,
            binding,
            control,
            types.DepthIntent.reduced(depth - 1, probcut_reduction),
            ply + 1,
            -threshold,
            -threshold + 1,
            .all,
            .probcut_probe,
        ) catch |err| {
            unmake(value, binding, context.thread, ply, chess_move);
            return err;
        };
        const verified_value = negated(child);
        const verified = (verified_value.bound == .lower or verified_value.bound == .exact) and
            verified_value.raw >= threshold;
        unmake(value, binding, context.thread, ply, chess_move);
        context.observer.probCutVerification(verified);
        if (!verified) continue;

        context.observer.prune(.probcut);
        const cutoff = NodeValue{ .raw = beta, .bound = .lower, .provenance = .probcut };
        storeTable(context, value.current.key, chess_move, cutoff, tableStaticEval(features, shallow), probCutStoreDepth(depth), ply);
        return cutoff;
    }
    return null;
}

fn hasNonPawnMaterial(value: *const chess.position.Position) bool {
    const side = value.side_to_move;
    return value.physical.pieces(side, .knight) |
        value.physical.pieces(side, .bishop) |
        value.physical.pieces(side, .rook) |
        value.physical.pieces(side, .queen) != 0;
}

const fixed_null_move_reduction: u16 = 2;
const null_move_min_depth: u16 = fixed_null_move_reduction + 2;

/// MAN-S03's verified null search remains the authority; only its speculative
/// probe depth changes. Nominal depth and an independently strong static-eval
/// margin may each add one ply, while at least one probe ply and two same-node
/// verification plies are retained. Verification uses the identical reduction.
fn dynamicNullMoveReduction(depth: u16, pruning_eval: i32, beta: i32) u16 {
    std.debug.assert(depth >= null_move_min_depth);
    var reduction = fixed_null_move_reduction;
    if (depth >= 8) reduction += 1;
    if (@as(i64, pruning_eval) - @as(i64, beta) >= 2 * score.units_per_pawn)
        reduction += 1;
    return @min(reduction, depth - 2);
}

const probcut_min_depth: u16 = 5;
const probcut_reduction: u16 = 3;

const ProbCutTableDecision = enum { search, skip, cutoff };

/// A TT result can replace the two-stage tactical probe only when it already
/// owns at least ProbCut's reduced horizon and came from an ordinary searched
/// result. A lower/exact result over the raised threshold proves the cutoff;
/// an upper/exact result below it proves only that this speculative probe is
/// redundant. Neither decision upgrades the TT result to full nominal depth.
fn probCutTableDecision(record: ?tt.Record, depth: u16, threshold: i32) ProbCutTableDecision {
    const table_record = record orelse return .search;
    if (@as(u16, table_record.depth) < probCutStoreDepth(depth) or
        !table_record.value.isOrdinary() or !probCutTableProvenance(table_record.producer))
        return .search;
    if ((table_record.bound == .lower or table_record.bound == .exact) and
        table_record.value.raw() >= threshold)
        return .cutoff;
    if ((table_record.bound == .upper or table_record.bound == .exact) and
        table_record.value.raw() < threshold)
        return .skip;
    return .search;
}

fn probCutTableProvenance(producer: types.Provenance) bool {
    return switch (producer) {
        .qsearch_move, .pvs_probe, .full_search, .tt_exact, .tt_bound, .probcut => true,
        .terminal,
        .static_eval,
        .stand_pat,
        .fallback,
        .null_move,
        .reduced_search,
        .speculative_cutoff,
        .exclusion_search,
        .tablebase,
        => false,
    };
}

fn probCutEligible(
    comptime features: types.Features,
    depth: u16,
    ply: usize,
    pv_node: bool,
    in_check: bool,
    exclusion_node: bool,
    zero_window: bool,
    static_known: bool,
    has_non_pawn_material: bool,
) bool {
    return features.probcut and depth >= probcut_min_depth and ply != 0 and
        !pv_node and !in_check and !exclusion_node and zero_window and
        static_known and has_non_pawn_material;
}

fn probCutThreshold(search_params: params.Values, beta: i32) ?i32 {
    const beta_score = score.Score{ .raw_value = beta };
    if (!beta_score.isOrdinary()) return null;
    // One evaluator pawn is the tactical confidence gap. The full reduced
    // verification, rather than the positional improving trend, owns the
    // second and decisive proof.
    const widened = @as(i64, beta) + search_params.probcut_margin;
    if (widened > score.ordinary_max_raw) return null;
    return @intCast(widened);
}

fn probCutStoreDepth(depth: u16) u16 {
    // The verified child searches nominal depth-1 with a three-ply reduction;
    // adding the capture ply back gives parent authority depth-3.
    return depth -| probcut_reduction;
}

fn resolved(value: NodeValue, depth: types.DepthIntent) NodeResolution {
    return .{ .value = value, .depth = depth };
}

fn checkExtensionEligible(in_check: bool, depth: types.DepthIntent, ply: usize) bool {
    return in_check and depth.searched() < chess.types.max_ply - 1 and
        ply < chess.types.max_ply - 1;
}

fn internalIterativeReductionEligible(
    comptime features: types.Features,
    depth: u16,
    ply: usize,
    expectation: types.NodeExpectation,
    in_check: bool,
    has_tt_move: bool,
    exclusion_node: bool,
) bool {
    // Five plies leaves four after the one-ply confidence reduction, matching
    // the first depth at which Manta's accepted LMR has mature move ordering.
    // A cut node needs two additional plies: its null-window result is useful
    // only when a missing TT move makes ordering uncertainty material.
    if (ply == 0 or in_check or has_tt_move or exclusion_node) return false;
    if (expectation == .principal) return depth >= 5;
    return features.depth_authority_sync and features.iir_cut_expectation and
        expectation == .cut and depth >= 7;
}

const SingularEligibility = enum { ineligible, provenance_rejected, eligible };

fn singularExtensionEligibility(
    comptime features: types.Features,
    depth: u16,
    ply: usize,
    in_check: bool,
    exclusion_node: bool,
    table_evidence: TableEvidence,
) SingularEligibility {
    if (depth < 6 or ply == 0 or in_check or exclusion_node) return .ineligible;
    const record = table_evidence.record orelse return .ineligible;
    const tt_move = table_evidence.chess_move orelse return .ineligible;
    if (!tt_move.isChessMove() or !record.value.isOrdinary()) return .ineligible;
    if (record.bound != .lower and record.bound != .exact) return .ineligible;
    if (@as(u16, record.depth) + 1 < depth) return .ineligible;
    if (features.depth_authority_sync and features.singular_tt_provenance and
        !singularTableProvenance(record.producer)) return .provenance_rejected;
    return .eligible;
}

fn singularTableProvenance(producer: types.Provenance) bool {
    return switch (producer) {
        .full_search, .pvs_probe => true,
        .terminal,
        .static_eval,
        .stand_pat,
        .qsearch_move,
        .tt_exact,
        .tt_bound,
        .fallback,
        .reduced_search,
        .null_move,
        .probcut,
        .speculative_cutoff,
        .exclusion_search,
        .tablebase,
        => false,
    };
}

fn singularThreshold(tt_value: score.Score) i32 {
    std.debug.assert(tt_value.isOrdinary());
    return @max(-score.ordinary_max_raw, tt_value.raw() - score.units_per_pawn);
}

fn singularExtensionPlies(
    comptime features: types.Features,
    depth: u16,
    expectation: types.NodeExpectation,
    record: tt.Record,
    alternatives: NodeValue,
    threshold: i32,
) u16 {
    if (alternatives.bound != .upper or alternatives.raw >= threshold) return 0;
    if (!features.depth_authority_sync or !features.singular_double_extension)
        return 1;
    const double_threshold = @max(
        -score.ordinary_max_raw,
        threshold - score.units_per_pawn,
    );
    return if (depth >= 9 and expectation == .principal and record.bound == .exact and
        @as(u16, record.depth) + 1 >= depth and alternatives.raw < double_threshold)
        2
    else
        1;
}

fn exclusionProvesAtLeast(result: NodeValue, threshold: i32) bool {
    return (result.bound == .lower or result.bound == .exact) and
        result.raw >= threshold;
}

test "depth-authority synchronization consumes only typed expectation and TT provenance" {
    // SCORE-022: missing move evidence may reduce a mature PV or cut node, but
    // check, root, exclusion and any legal TT move preserve the full horizon.
    try std.testing.expect(internalIterativeReductionEligible(.{}, 5, 1, .principal, false, false, false));
    try std.testing.expect(internalIterativeReductionEligible(.{ .depth_authority_sync = true }, 7, 1, .cut, false, false, false));
    try std.testing.expect(!internalIterativeReductionEligible(.{ .depth_authority_sync = false }, 7, 1, .cut, false, false, false));
    try std.testing.expect(!internalIterativeReductionEligible(.{}, 7, 1, .all, false, false, false));
    try std.testing.expect(!internalIterativeReductionEligible(.{}, 7, 0, .cut, false, false, false));
    try std.testing.expect(!internalIterativeReductionEligible(.{}, 7, 1, .cut, true, false, false));
    try std.testing.expect(!internalIterativeReductionEligible(.{}, 7, 1, .cut, false, true, false));
    try std.testing.expect(!internalIterativeReductionEligible(.{}, 7, 1, .cut, false, false, true));

    const chess_move = chess.move.Move.normal(.e2, .e4);
    const ordinary = score.Score.fromOrdinary(300).?;
    var record = tt.Record{
        .chess_move = chess_move,
        .value = ordinary,
        .static_eval = null,
        .depth = 8,
        .bound = .exact,
        .generation = 0,
        .producer = .full_search,
    };
    const table_evidence = TableEvidence{ .chess_move = chess_move, .record = record };
    try std.testing.expectEqual(
        SingularEligibility.eligible,
        singularExtensionEligibility(.{}, 8, 1, false, false, table_evidence),
    );
    record.producer = .null_move;
    const speculative = TableEvidence{ .chess_move = chess_move, .record = record };
    try std.testing.expectEqual(
        SingularEligibility.provenance_rejected,
        singularExtensionEligibility(.{ .depth_authority_sync = true }, 8, 1, false, false, speculative),
    );
    try std.testing.expectEqual(
        SingularEligibility.eligible,
        singularExtensionEligibility(.{ .depth_authority_sync = false }, 8, 1, false, false, speculative),
    );
}

test "singular separation gives bounded extension and searched multi-cut authority" {
    // SCORE-022: only an exclusion upper bound below its null-window target is
    // singular. A second ply needs deep exact principal evidence and another
    // pawn of separation. Conversely only a searched lower/exact exclusion
    // result can prove a multi-cut target.
    const record = tt.Record{
        .chess_move = chess.move.Move.normal(.e2, .e4),
        .value = score.Score.fromOrdinary(500).?,
        .static_eval = null,
        .depth = 8,
        .bound = .exact,
        .generation = 0,
        .producer = .full_search,
    };
    const threshold = 400;
    const separated = NodeValue{ .raw = 250, .bound = .upper, .provenance = .exclusion_search };
    try std.testing.expectEqual(
        @as(u16, 2),
        singularExtensionPlies(.{ .depth_authority_sync = true }, 9, .principal, record, separated, threshold),
    );
    try std.testing.expectEqual(
        @as(u16, 1),
        singularExtensionPlies(.{}, 9, .cut, record, separated, threshold),
    );
    try std.testing.expectEqual(
        @as(u16, 1),
        singularExtensionPlies(.{ .singular_double_extension = false }, 9, .principal, record, separated, threshold),
    );
    try std.testing.expectEqual(
        @as(u16, 0),
        singularExtensionPlies(.{}, 9, .principal, record, .{ .raw = threshold, .bound = .lower, .provenance = .exclusion_search }, threshold),
    );
    try std.testing.expect(exclusionProvesAtLeast(
        .{ .raw = threshold, .bound = .lower, .provenance = .exclusion_search },
        threshold,
    ));
    try std.testing.expect(!exclusionProvesAtLeast(
        .{ .raw = threshold - 1, .bound = .upper, .provenance = .exclusion_search },
        threshold,
    ));
}

fn shouldReduceLateMove(
    comptime features: types.Features,
    depth: u16,
    move_index: usize,
    quiet: bool,
    in_check: bool,
    gives_check: bool,
    history_confident: bool,
) bool {
    return lateMoveEligible(features, depth, move_index, quiet, in_check, gives_check) and
        !(history_confident and move_index == 3);
}

fn lateMoveEligible(
    comptime features: types.Features,
    depth: u16,
    move_index: usize,
    quiet: bool,
    in_check: bool,
    gives_check: bool,
) bool {
    return features.lmr and depth >= 4 and move_index >= 3 and quiet and !in_check and !gives_check;
}

/// Manta's base LMR surface advances only when both independent confidence
/// signals advance: another three nominal plies make a deeper omission safer,
/// while each doubling of the searched legal-move prefix makes a late quiet
/// less likely to refute the current alpha. The balanced minimum prevents one
/// extreme from authorizing a large reduction by itself. At least one child
/// main-search ply is retained; the alpha-rise path above always verifies the
/// move at `full_child_depth` before its score can become authoritative.
fn lateMoveReduction(
    comptime features: types.Features,
    depth: u16,
    move_index: usize,
) u16 {
    return lateMoveReductionWithParams(features, .{}, depth, move_index);
}

fn lateMoveReductionWithParams(
    comptime features: types.Features,
    search_params: params.Values,
    depth: u16,
    move_index: usize,
) u16 {
    std.debug.assert(depth >= 4);
    std.debug.assert(move_index >= 3);
    if (!features.dynamic_lmr) return 1;

    const depth_band = (depth - 3) / 3;
    const move_band = @as(u16, std.math.log2_int(usize, move_index + 1) - 2);
    var extra = @min(depth_band, move_band);

    if (comptime features.lmr_desaturation) {
        // Both signals are logarithmic in their own argument and are composed
        // as a product, so neither caps the other: each doubling of the nominal
        // depth and each doubling of the searched legal-move prefix multiply
        // the confidence that omitting a late quiet is safe, rather than one
        // merely licensing what the other already allowed. Depth is at least
        // four and the move index at least three, so the product is at least
        // four and the subtraction cannot underflow.
        //
        // The accepted minimum stays as a floor. Lifting the cap is the whole
        // hypothesis; re-deciding the shallow policy that `MAN-S15` and
        // `MAN-S19` already gated is not, and a candidate that reduced LESS
        // anywhere would make an H0 unattributable between cutting too hard in
        // one region and too softly in another. The product surface alone is
        // weaker than the accepted one between depths six and fifteen at
        // middling move indices, so the floor is load-bearing rather than
        // defensive.
        const depth_term: u16 = std.math.log2_int(u16, depth);
        const move_term: u16 = @intCast(std.math.log2_int(usize, move_index + 1));
        extra = @max(extra, (depth_term * move_term - 4) / 4);
    }

    // Scale only the evidence-derived extra plies. The one-ply conservative
    // LMR floor remains authoritative, and the accepted default 100 is exact.
    const scaled_extra: u16 = @intCast(@divTrunc(
        @as(i32, extra) * search_params.lmr_extra_scale + 50,
        100,
    ));
    return @min(1 + scaled_extra, depth - 2);
}

const LmrEvidence = struct {
    improving: ?bool,
    expectation: types.NodeExpectation,
    has_tt_move: bool,
    singular_context: bool,
    history: ordering.HistoryConfidence,
};

/// Synchronization changes the accepted MAN-S15 surface only when at least
/// two independent position/search facts agree. Positive votes protect one
/// child ply; negative votes deepen the reduction by one. Ties and isolated
/// signals preserve the base surface, and every path retains at least one
/// ordinary child ply before quiescence.
fn synchronizedLateMoveReduction(
    comptime features: types.Features,
    search_params: params.Values,
    depth: u16,
    move_index: usize,
    lmr_evidence: LmrEvidence,
    observer: anytype,
) u16 {
    const base = lateMoveReductionWithParams(features, search_params, depth, move_index);
    if (!features.lmr_synchronization) return base;

    var votes: i4 = 0;
    if (features.lmr_sync_improving) if (lmr_evidence.improving) |improving| {
        const direction: diagnostics.LmrDirection = if (improving) .protect else .deepen;
        votes += direction.vote();
        observer.lmrModifier(.improving, direction);
    };
    if (features.lmr_sync_expectation) switch (lmr_evidence.expectation) {
        .principal => {
            votes += diagnostics.LmrDirection.protect.vote();
            observer.lmrModifier(.expectation, .protect);
        },
        .cut => {
            votes += diagnostics.LmrDirection.deepen.vote();
            observer.lmrModifier(.expectation, .deepen);
        },
        .all => {},
    };
    // A legal TT move is reusable but not necessarily exact or current, so it
    // protects later alternatives from extra reduction. A verified singular
    // move is stronger same-position evidence: alternatives may be searched
    // one ply less deeply when another independent signal agrees.
    if (features.lmr_sync_tt_move and lmr_evidence.has_tt_move) {
        votes += diagnostics.LmrDirection.protect.vote();
        observer.lmrModifier(.tt_move, .protect);
    }
    if (features.lmr_sync_singular and lmr_evidence.singular_context) {
        votes += diagnostics.LmrDirection.deepen.vote();
        observer.lmrModifier(.singular_context, .deepen);
    }
    if (features.lmr_sync_history) switch (lmr_evidence.history) {
        .positive => {
            votes += diagnostics.LmrDirection.protect.vote();
            observer.lmrModifier(.history, .protect);
        },
        .negative => {
            votes += diagnostics.LmrDirection.deepen.vote();
            observer.lmrModifier(.history, .deepen);
        },
        .neutral => {},
    };

    const adjusted = if (votes >= 2)
        base -| 1
    else if (votes <= -2)
        @min(base + 1, depth - 2)
    else
        base;
    // LMR eligibility guarantees depth >= 4, and zero reduction would turn
    // this route into a mislabeled full-depth probe.
    const bounded = @max(@as(u16, 1), adjusted);
    observer.lmrAdjustment(base, bounded);
    return bounded;
}

/// Halfmove clock from which a transposition cutoff is no longer trusted.
/// Ten halfmoves of margin leaves search room to find the capture or pawn move
/// that resets the clock, or to establish that none exists.
const tt_rule_fifty_guard_clock: u16 = 90;

fn tableDepth(provenance: types.Provenance, nominal_depth: u16, reduction: u16) u16 {
    std.debug.assert(reduction != 0);
    return if (provenance == .reduced_search) nominal_depth -| reduction else nominal_depth;
}

/// A fail-low that skipped at least one late move under shallow selectivity
/// cannot claim full nominal-depth TT authority: the omitted siblings were
/// never shown not to raise alpha. Only a genuine fail-low is speculative in
/// this sense; an exact result already came from a fully searched move and
/// keeps its true provenance regardless of unrelated moves pruned afterward.
fn speculativeStoreValue(result: NodeValue, pruned_late_move: bool) NodeValue {
    if (!pruned_late_move or result.bound != .upper) return result;
    return .{ .raw = result.raw, .bound = result.bound, .provenance = .reduced_search };
}

fn reverseFutilityEligible(
    comptime features: types.Features,
    depth: u16,
    pv_node: bool,
    in_check: bool,
    zero_window: bool,
    has_non_pawn_material: bool,
    beta: score.Score,
) bool {
    return features.shallow_selectivity and features.reverse_futility and
        depth == 1 and !pv_node and !in_check and
        zero_window and has_non_pawn_material and beta.isOrdinary();
}

fn reverseFutilityMargin(search_params: params.Values, depth: u16) i32 {
    std.debug.assert(depth == 1);
    return search_params.reverse_futility_margin * @as(i32, depth);
}

/// Step-5.1.4.3 shallow-selectivity family: every consumer below shares this
/// depth ceiling, and each reads only raw static evaluation plus the
/// improving trend, never TT, terminal, draw or reusable score authority.
const shallow_selectivity_max_depth: u16 = 3;
const razoring_max_depth: u16 = 1;

/// Raw position evaluation, optional TT-refined pruning evaluation and the
/// raw two-ply improving trend. The raw value remains the only history/trend
/// producer; a directionally compatible searched TT bound may influence only
/// pruning consumers. `known` is false in check or exclusion search.
const ShallowEvidence = struct {
    static_eval: i32 = 0,
    /// What the evaluator said before any correction. This is the only value
    /// the transposition table ever stores: a corrected evaluation written back
    /// would be corrected again on every reuse, compounding without bound.
    table_eval: i32 = 0,
    pruning_eval: i32 = 0,
    improving: bool = false,
    known: bool = false,
    cached: bool = false,
    refined: bool = false,

    fn raw(self: ShallowEvidence) ?i32 {
        return if (self.known) self.static_eval else null;
    }
};

fn tableStaticEval(comptime features: types.Features, shallow: ShallowEvidence) ?i32 {
    if (!features.eval_qsearch_sync or !features.tt_static_eval) return null;
    return if (shallow.known) shallow.table_eval else null;
}

fn shallowEvidence(
    comptime features: types.Features,
    comptime apply_correction: bool,
    context: anytype,
    value: *const chess.position.Position,
    binding: anytype,
    ply: usize,
    in_check: bool,
    exclusion_node: bool,
    table_record: ?tt.Record,
) ShallowEvidence {
    // Exclusion searches manufacture no reusable score authority; leaving the
    // ply's cached evaluation untouched preserves the enclosing singular
    // probe's own value for any grandchild's improving lookup.
    if (exclusion_node) return .{};
    if (in_check) {
        context.thread.static_evals[ply] = types.static_eval_unknown;
        return .{};
    }
    const cached = comptime features.eval_qsearch_sync and features.tt_static_eval;
    const cached_value = if (cached)
        if (table_record) |record| record.static_eval else null
    else
        null;
    const table_eval = if (cached_value) |value_score| value_score.raw() else binding.evaluate(value).raw();
    // The evaluation consumer sees the corrected value; the pruning consumer
    // below deliberately does not, because 5.4.1 gates the producer before it
    // is allowed to control selectivity.
    const corrected_eval = if (comptime features.correction_history and apply_correction)
        correctedStaticEval(context, value, table_eval)
    else
        table_eval;
    // Improving is a pruning/reduction input, so it deliberately remains a
    // relation between uncorrected evaluations until a later gate explicitly
    // grants correction history selectivity authority.
    const previous = if (ply >= 2) context.thread.static_evals[ply - 2] else types.static_eval_unknown;
    const improving = previous != types.static_eval_unknown and table_eval > previous;
    context.thread.static_evals[ply] = table_eval;
    const pruning_eval = if (comptime features.eval_qsearch_sync and features.tt_eval_refinement)
        refinedStaticEval(table_eval, table_record)
    else
        table_eval;
    // Preserve MAN-S19's accepted qsearch TT refinement in both arms. With
    // correction enabled the same authenticated bound refines the corrected
    // stand-pat value only when its proven direction actually reaches beyond
    // that value; pruning independently refines the raw HCE above.
    const static_eval = if (comptime features.eval_qsearch_sync and features.tt_eval_refinement)
        refinedStaticEval(corrected_eval, table_record)
    else
        corrected_eval;
    const refined = static_eval != corrected_eval;
    context.observer.staticEvaluation(cached_value != null, pruning_eval != table_eval);
    return .{
        .static_eval = static_eval,
        .table_eval = table_eval,
        .pruning_eval = pruning_eval,
        .improving = improving,
        .known = true,
        .cached = cached_value != null,
        .refined = refined,
    };
}

/// Applies the correction this side and pawn structure has earned, clamped to
/// the ordinary score band so a correction can never manufacture a mate claim.
fn correctedStaticEval(context: anytype, value: *const chess.position.Position, raw: i32) i32 {
    const heuristics = context.heuristics orelse return raw;
    const adjustment = heuristics.correction(value.side_to_move, value.current.pawn_key);
    context.observer.correctionLookup(adjustment);
    if (adjustment == 0) return raw;
    return std.math.clamp(raw + adjustment, -score.ordinary_max_raw, score.ordinary_max_raw);
}

/// Feeds a completed search result back to the correction producer. Only a
/// node whose evaluation was known, that was not in check and not an exclusion
/// search, and whose result actually contradicts the evaluator in the direction
/// its bound authorizes, is evidence about evaluator bias.
fn recordCorrectionEvidence(
    comptime features: types.Features,
    context: anytype,
    value: *const chess.position.Position,
    shallow: ShallowEvidence,
    result: NodeValue,
    depth: u16,
    exclusion_node: bool,
    incomplete_fail_low: bool,
) void {
    if (comptime !features.correction_history) return;
    if (exclusion_node or !shallow.known or depth == 0) return;
    // A reduced fail-low has only reduced-horizon authority. A fail-low after
    // shallow pruning did not search every sibling. Neither can teach a
    // nominal-depth upper correction even though both remain valid inputs to
    // their separately typed reduced/speculative TT policies.
    if (result.provenance == .reduced_search) return;
    if (result.bound == .upper and incomplete_fail_low) return;
    const searched = score.Score{ .raw_value = result.raw };
    if (!searched.isValid() or !searched.isOrdinary()) return;
    const delta = searched.raw() - shallow.table_eval;
    // A lower bound only proves the value is at least this high, so it is
    // evidence only when it exceeds the evaluator; an upper bound likewise.
    const authoritative = switch (result.bound) {
        .exact => true,
        .lower => delta > 0,
        .upper => delta < 0,
    };
    if (!authoritative or delta == 0) return;
    const heuristics = context.heuristics orelse return;
    const prior = heuristics.correction(value.side_to_move, value.current.pawn_key);
    context.observer.correctionEvidence(result.bound, delta, prior, depth);
    heuristics.recordCorrection(
        value.side_to_move,
        value.current.pawn_key,
        delta,
        depth,
    );
}

fn refinedStaticEval(raw: i32, table_record: ?tt.Record) i32 {
    const record = table_record orelse return raw;
    if (!record.value.isOrdinary() or !searchedEvalProvenance(record.producer)) return raw;
    return switch (record.bound) {
        .exact => record.value.raw(),
        .lower => if (record.value.raw() > raw) record.value.raw() else raw,
        .upper => if (record.value.raw() < raw) record.value.raw() else raw,
    };
}

fn searchedEvalProvenance(producer: types.Provenance) bool {
    return switch (producer) {
        .qsearch_move, .pvs_probe, .full_search, .tt_exact, .tt_bound, .reduced_search, .probcut => true,
        .terminal, .static_eval, .stand_pat, .fallback, .null_move, .speculative_cutoff, .exclusion_search, .tablebase => false,
    };
}

/// A trustworthy (improving) static evaluation needs a smaller cushion before
/// search may act on it; an unconfirmed one needs a larger cushion. Every
/// margin/threshold below applies this same one-pawn adjustment uniformly.
fn shallowConfidenceBonus(improving: bool) i32 {
    return if (improving) 0 else score.units_per_pawn;
}

fn razoringEligible(
    comptime features: types.Features,
    depth: u16,
    pv_node: bool,
    exclusion_node: bool,
    has_non_pawn_material: bool,
    alpha: score.Score,
) bool {
    return features.shallow_selectivity and features.razoring and
        depth <= razoring_max_depth and !pv_node and !exclusion_node and
        has_non_pawn_material and alpha.isOrdinary();
}

fn razoringMargin(depth: u16, improving: bool) i32 {
    const base = score.units_per_pawn * (@as(i32, depth) + 1);
    return base + shallowConfidenceBonus(improving);
}

fn lateMovePruneEligible(
    comptime features: types.Features,
    shallow: ShallowEvidence,
    pv_node: bool,
    depth: u16,
    search_index: usize,
    has_non_pawn_material: bool,
    alpha: i32,
    beta: i32,
) bool {
    // The first searched move at every node keeps full authority: pruning it
    // could leave a node with no fully searched move and no honest bound.
    return features.shallow_selectivity and features.late_move_pruning and
        shallowMovePruneEligible(
            shallow,
            pv_node,
            depth,
            search_index,
            has_non_pawn_material,
            alpha,
            beta,
        );
}

fn lateMovePruneThreshold(search_params: params.Values, depth: u16, improving: bool) usize {
    const base = @as(usize, @intCast(search_params.late_move_base)) +
        @as(usize, depth) * @as(usize, @intCast(search_params.late_move_depth_scale));
    return if (improving)
        base + @as(usize, @intCast(search_params.late_move_improving_bonus))
    else
        base;
}

fn historyLateMovePruneThreshold(
    comptime features: types.Features,
    base: usize,
    confidence: ordering.HistoryConfidence,
) usize {
    if (!features.main_selectivity_sync or !features.history_pruning) return base;
    return switch (confidence) {
        // One searched legal move in either direction is the smallest
        // discrete adjustment and can never cross the first-move guard.
        .positive => base + 1,
        .neutral => base,
        .negative => @max(@as(usize, 2), base - 1),
    };
}

fn quietFutilityEligible(
    comptime features: types.Features,
    shallow: ShallowEvidence,
    pv_node: bool,
    depth: u16,
    search_index: usize,
    has_non_pawn_material: bool,
    alpha: i32,
    beta: i32,
) bool {
    return features.shallow_selectivity and features.quiet_futility and
        shallowMovePruneEligible(
            shallow,
            pv_node,
            depth,
            search_index,
            has_non_pawn_material,
            alpha,
            beta,
        );
}

fn quietFutilityMargin(search_params: params.Values, depth: u16, improving: bool) i32 {
    const base = search_params.quiet_futility_unit * (@as(i32, depth) + 1);
    return base + shallowConfidenceBonus(improving);
}

fn seePruneEligible(
    comptime features: types.Features,
    shallow: ShallowEvidence,
    pv_node: bool,
    depth: u16,
    search_index: usize,
    is_capture: bool,
    is_promotion: bool,
    has_non_pawn_material: bool,
    alpha: i32,
    beta: i32,
) bool {
    return features.shallow_selectivity and features.see_pruning and
        shallowMovePruneEligible(
            shallow,
            pv_node,
            depth,
            search_index,
            has_non_pawn_material,
            alpha,
            beta,
        ) and is_capture and !is_promotion;
}

fn shallowMovePruneEligible(
    shallow: ShallowEvidence,
    pv_node: bool,
    depth: u16,
    search_index: usize,
    has_non_pawn_material: bool,
    alpha: i32,
    beta: i32,
) bool {
    return shallow.known and !pv_node and search_index != 0 and
        depth <= shallow_selectivity_max_depth and has_non_pawn_material and
        beta == alpha + 1 and
        (score.Score{ .raw_value = alpha }).isOrdinary() and
        (score.Score{ .raw_value = beta }).isOrdinary();
}

/// Objective material arithmetic, not a positional trend: only depth widens
/// how much loss a shallow node tolerates before pruning a losing capture.
fn seePruningThreshold(search_params: params.Values, depth: u16) i32 {
    return -search_params.see_pruning_unit * @as(i32, depth);
}

/// Main-search capture futility asks SEE to bridge the gap between MAN-S19's
/// TT-refined pruning evaluation and alpha, with one pawn of uncertainty per
/// remaining ply. It can only tighten the accepted depth-only SEE threshold;
/// the caller still makes the move before exempting checks.
fn synchronizedSeePruningThreshold(
    comptime features: types.Features,
    search_params: params.Values,
    pruning_eval: i32,
    alpha: i32,
    depth: u16,
) i32 {
    const base = seePruningThreshold(search_params, depth);
    if (!features.main_selectivity_sync or !features.capture_futility) return base;
    const eval_score = score.Score{ .raw_value = pruning_eval };
    const alpha_score = score.Score{ .raw_value = alpha };
    if (!eval_score.isOrdinary() or !alpha_score.isOrdinary()) return base;
    const cushion = score.units_per_pawn * @as(i32, depth + 1);
    return @max(base, alpha - pruning_eval - cushion);
}

fn qsearchSeeCandidate(
    comptime features: types.Features,
    in_check: bool,
    is_capture: bool,
    is_promotion: bool,
    see_non_losing: bool,
) bool {
    return features.qsearch_see and !in_check and is_capture and !is_promotion and !see_non_losing;
}

/// Returns the minimum net tactical gain needed to rise above alpha after a
/// one-pawn positional cushion. Negative-SEE moves belong to the established
/// SEE filter; checks, evasions, promotions, PV qsearch and decisive windows
/// are never delta-pruned.
fn qsearchDeltaThreshold(
    comptime features: types.Features,
    search_params: params.Values,
    pv_node: bool,
    in_check: bool,
    is_capture: bool,
    is_promotion: bool,
    pruning_eval: i32,
    alpha: i32,
    see_non_losing: bool,
) ?i32 {
    if (!features.eval_qsearch_sync or !features.qsearch_delta or pv_node or
        in_check or !is_capture or is_promotion or !see_non_losing) return null;
    const eval_score = score.Score{ .raw_value = pruning_eval };
    const alpha_score = score.Score{ .raw_value = alpha };
    if (!eval_score.isOrdinary() or !alpha_score.isOrdinary()) return null;
    const threshold = alpha - pruning_eval - search_params.qsearch_delta_cushion;
    return if (threshold > 0) threshold else null;
}

fn qsearchBaselineProvenance(shallow: ShallowEvidence, table_record: ?tt.Record) types.Provenance {
    if (!shallow.refined) return .stand_pat;
    const record = table_record orelse unreachable;
    return if (record.bound == .exact) .tt_exact else .tt_bound;
}

fn qsearchFinalProvenance(
    in_check: bool,
    best_move: chess.move.Move,
    baseline: types.Provenance,
) types.Provenance {
    return if (!in_check and best_move.raw() == chess.move.Move.none.raw()) baseline else .qsearch_move;
}

test "continuation distances stop at root and null boundaries" {
    // A synthetic null move is not a legal chess predecessor and must sever
    // every relation that would cross it, while nearer all-move paths remain.
    var thread = types.ThreadState.init();
    const previous = chess.move.Move.normal(.e2, .e3);
    var ply: usize = 1;
    while (ply <= 6) : (ply += 1)
        thread.ply_contexts[ply] = types.PlyContext.afterMove(
            previous,
            .pawn,
            ply == 1,
            ply == 2,
            false,
        );

    const populated = continuationSet(.{}, &thread, 6, .white);
    for (populated.items) |item| try std.testing.expect(item != null);
    try std.testing.expect(continuationSet(.{}, &thread, 1, .white).items[@intFromEnum(ordering.ContinuationDistance.two)] == null);
    const disabled = continuationSet(.{ .continuation_history = false }, &thread, 6, .white);
    for (disabled.items) |item| try std.testing.expect(item == null);
    const no_four = continuationSet(.{ .continuation_distance_4 = false }, &thread, 6, .white);
    try std.testing.expect(no_four.items[@intFromEnum(ordering.ContinuationDistance.two)] != null);
    try std.testing.expect(no_four.items[@intFromEnum(ordering.ContinuationDistance.four)] == null);
    try std.testing.expect(no_four.items[@intFromEnum(ordering.ContinuationDistance.six)] != null);

    thread.ply_contexts[4] = types.PlyContext.afterNull(false);
    const broken = continuationSet(.{}, &thread, 6, .white);
    try std.testing.expect(broken.items[@intFromEnum(ordering.ContinuationDistance.two)] != null);
    try std.testing.expect(broken.items[@intFromEnum(ordering.ContinuationDistance.four)] == null);
    try std.testing.expect(broken.items[@intFromEnum(ordering.ContinuationDistance.six)] == null);
}

test "ProbCut eligibility protects authoritative and zugzwang-sensitive nodes" {
    // SCORE-010/011 and QUAL-014: only an interior ordinary scout node with a
    // known static context and side-to-move non-pawn material may begin the
    // tactical proof. Checked, PV, root, exclusion and pawn-only positions
    // retain the ordinary search path.
    const enabled = types.Features{ .probcut = true };
    try std.testing.expect(probCutEligible(enabled, 5, 1, false, false, false, true, true, true));
    try std.testing.expect(!probCutEligible(.{ .probcut = false }, 5, 1, false, false, false, true, true, true));
    try std.testing.expect(!probCutEligible(enabled, 4, 1, false, false, false, true, true, true));
    try std.testing.expect(!probCutEligible(enabled, 5, 0, false, false, false, true, true, true));
    try std.testing.expect(!probCutEligible(enabled, 5, 1, true, false, false, true, true, true));
    try std.testing.expect(!probCutEligible(enabled, 5, 1, false, true, false, true, true, true));
    try std.testing.expect(!probCutEligible(enabled, 5, 1, false, false, true, true, true, true));
    try std.testing.expect(!probCutEligible(enabled, 5, 1, false, false, false, false, true, true));
    try std.testing.expect(!probCutEligible(enabled, 5, 1, false, false, false, true, false, true));
    try std.testing.expect(!probCutEligible(enabled, 5, 1, false, false, false, true, true, false));
}

test "ProbCut threshold and TT authority stay inside the proven horizon" {
    // SCORE-002/010/011: the raised tactical target never crosses into a
    // decisive score band, and a verified reduced child owns exactly the
    // parent horizon reconstructed by adding its capture ply.
    const search_params: params.Values = .{};
    try std.testing.expectEqual(
        @as(?i32, 50 + search_params.probcut_margin),
        probCutThreshold(search_params, 50),
    );
    try std.testing.expect(probCutThreshold(.{}, score.ordinary_max_raw) == null);
    try std.testing.expectEqual(@as(u16, 2), probCutStoreDepth(5));
    try std.testing.expectEqual(@as(u16, 5), probCutStoreDepth(8));
}

test "late-move reduction eligibility protects tactical and authoritative moves" {
    // PERF-010/QUAL-014: only sufficiently late, quiet, non-checking moves are
    // speculative; full-depth re-search remains the authority on an alpha rise.
    const enabled = types.Features{ .lmr = true };
    try std.testing.expect(shouldReduceLateMove(enabled, 4, 3, true, false, false, false));
    try std.testing.expect(!shouldReduceLateMove(enabled, 3, 3, true, false, false, false));
    try std.testing.expect(!shouldReduceLateMove(enabled, 4, 2, true, false, false, false));
    try std.testing.expect(!shouldReduceLateMove(enabled, 4, 3, false, false, false, false));
    try std.testing.expect(!shouldReduceLateMove(enabled, 4, 3, true, true, false, false));
    try std.testing.expect(!shouldReduceLateMove(enabled, 4, 3, true, false, true, false));
    try std.testing.expect(!shouldReduceLateMove(enabled, 4, 3, true, false, false, true));
    try std.testing.expect(shouldReduceLateMove(enabled, 4, 4, true, false, false, true));
    try std.testing.expect(!shouldReduceLateMove(.{ .lmr = false }, 8, 8, true, false, false, false));
}

test "dynamic base LMR is monotone bounded and switch-off restores one ply" {
    // PERF-010/QUAL-014: nominal depth and searched legal-move ordinal are the
    // only magnitude producers. Neither may make a later/deeper eligible move
    // search more deeply, and every probe retains one main-search child ply.
    const dynamic = types.Features{ .dynamic_lmr = true };
    const fixed = types.Features{ .dynamic_lmr = false };
    var saw_multi_ply = false;
    var depth: u16 = 4;
    while (depth <= 64) : (depth += 1) {
        var previous: u16 = 0;
        var move_index: usize = 3;
        while (move_index < 256) : (move_index += 1) {
            const reduction = lateMoveReduction(dynamic, depth, move_index);
            try std.testing.expect(reduction >= 1);
            try std.testing.expect(reduction <= depth - 2);
            try std.testing.expect(reduction >= previous);
            try std.testing.expectEqual(@as(u16, 1), lateMoveReduction(fixed, depth, move_index));
            saw_multi_ply = saw_multi_ply or reduction > 1;
            previous = reduction;
        }
    }
    var move_index: usize = 3;
    while (move_index < 256) : (move_index += 1) {
        var previous: u16 = 0;
        depth = 4;
        while (depth <= 64) : (depth += 1) {
            const reduction = lateMoveReduction(dynamic, depth, move_index);
            try std.testing.expect(reduction >= previous);
            previous = reduction;
        }
    }
    try std.testing.expect(saw_multi_ply);
}

test "LMR tuning scales only extra plies and preserves authority bounds" {
    // SCORE-016: tuning may change how aggressively established depth/move
    // evidence cuts, but it cannot remove the one-ply floor, exceed the child
    // horizon, change eligibility, or affect the fixed-LMR ablation.
    const features = types.Features{ .dynamic_lmr = true };
    const conservative = params.Values{ .lmr_extra_scale = 50 };
    const accepted = params.Values{};
    const aggressive = params.Values{ .lmr_extra_scale = 200 };
    var depth: u16 = 4;
    while (depth <= 64) : (depth += 1) {
        var move_index: usize = 3;
        while (move_index < 256) : (move_index += 1) {
            const low = lateMoveReductionWithParams(features, conservative, depth, move_index);
            const middle = lateMoveReductionWithParams(features, accepted, depth, move_index);
            const high = lateMoveReductionWithParams(features, aggressive, depth, move_index);
            try std.testing.expect(low >= 1 and high <= depth - 2);
            try std.testing.expect(low <= middle and middle <= high);
            try std.testing.expectEqual(lateMoveReduction(features, depth, move_index), middle);
            try std.testing.expectEqual(
                @as(u16, 1),
                lateMoveReductionWithParams(.{ .dynamic_lmr = false }, aggressive, depth, move_index),
            );
        }
    }
}

test "MAN-S23 desaturated LMR keeps every accepted bound and stops saturating" {
    // The candidate may only change reduction magnitude. It must keep the same
    // monotonicity, the one-ply floor and the child-ply ceiling the accepted
    // surface guarantees, and switching it off must reproduce that surface
    // exactly rather than approximately.
    // Both fixtures pin the switch explicitly so this test states the same
    // contract whichever way the production default currently points.
    const accepted = types.Features{ .dynamic_lmr = true, .lmr_desaturation = false };
    const candidate = types.Features{ .dynamic_lmr = true, .lmr_desaturation = true };
    const accepted_params = params.Values{ .lmr_extra_scale = 100 };

    var depth: u16 = 4;
    while (depth <= 64) : (depth += 1) {
        var previous: u16 = 0;
        var move_index: usize = 3;
        while (move_index < 256) : (move_index += 1) {
            const reduction = lateMoveReductionWithParams(candidate, accepted_params, depth, move_index);
            try std.testing.expect(reduction >= 1);
            try std.testing.expect(reduction <= depth - 2);
            try std.testing.expect(reduction >= previous);
            // The candidate never searches an eligible late move MORE deeply
            // than the accepted head would: it only ever cuts further.
            try std.testing.expect(reduction >= lateMoveReductionWithParams(accepted, accepted_params, depth, move_index));
            previous = reduction;
        }
    }

    var move_index: usize = 3;
    while (move_index < 256) : (move_index += 1) {
        var previous: u16 = 0;
        depth = 4;
        while (depth <= 64) : (depth += 1) {
            const reduction = lateMoveReductionWithParams(candidate, accepted_params, depth, move_index);
            try std.testing.expect(reduction >= previous);
            previous = reduction;
        }
    }

    // The defect being repaired, stated as a test. Across the move counts real
    // positions produce, the accepted surface never exceeds four plies because
    // its minimum is bounded by a move band that stops at three there. It does
    // reach higher in positions with more than sixty-three legal moves, which
    // is why the bound is asserted over a stated range rather than absolutely.
    var accepted_peak: u16 = 0;
    var candidate_peak: u16 = 0;
    depth = 4;
    while (depth <= 64) : (depth += 1) {
        var index: usize = 3;
        while (index <= 40) : (index += 1) {
            accepted_peak = @max(accepted_peak, lateMoveReductionWithParams(accepted, accepted_params, depth, index));
            candidate_peak = @max(candidate_peak, lateMoveReductionWithParams(candidate, accepted_params, depth, index));
        }
    }
    try std.testing.expectEqual(@as(u16, 4), accepted_peak);
    try std.testing.expectEqual(@as(u16, 7), candidate_peak);

    // Shallow, early moves are unchanged: this repairs deep late-move behaviour
    // and must not quietly become a different shallow policy.
    try std.testing.expectEqual(
        lateMoveReductionWithParams(accepted, accepted_params, 4, 3),
        lateMoveReductionWithParams(candidate, accepted_params, 4, 3),
    );
    try std.testing.expectEqual(
        lateMoveReductionWithParams(accepted, accepted_params, 6, 4),
        lateMoveReductionWithParams(candidate, accepted_params, 6, 4),
    );
}

test "LMR synchronization requires agreement and bounds every adjustment" {
    // PERF-010/QUAL-014: typed position/search evidence can move the accepted
    // surface by only one child ply, needs two agreeing sources, and the
    // umbrella-off path is byte-for-byte MAN-S17 policy. Every component is
    // counted independently so a compiled but unreachable arm is visible.
    const base = lateMoveReduction(.{}, 10, 15);
    try std.testing.expectEqual(@as(u16, 3), base);

    var observer: diagnostics.Counters = .{};
    const protected = synchronizedLateMoveReduction(
        .{ .lmr_synchronization = true },
        .{},
        10,
        15,
        .{
            .improving = true,
            .expectation = .principal,
            .has_tt_move = true,
            .singular_context = false,
            .history = .neutral,
        },
        &observer,
    );
    try std.testing.expectEqual(@as(u16, 2), protected);
    try std.testing.expectEqual(@as(u64, 1), observer.lmr_adjusted_shallower);

    observer.reset();
    const deepened = synchronizedLateMoveReduction(
        .{ .lmr_synchronization = true },
        .{},
        10,
        15,
        .{
            .improving = false,
            .expectation = .cut,
            .has_tt_move = false,
            .singular_context = true,
            .history = .negative,
        },
        &observer,
    );
    try std.testing.expectEqual(@as(u16, 4), deepened);
    try std.testing.expectEqual(@as(u64, 1), observer.lmr_adjusted_deeper);
    try std.testing.expectEqual(
        @as(u64, 1),
        observer.lmr_modifier_deepen[@intFromEnum(diagnostics.LmrModifier.singular_context)],
    );

    observer.reset();
    const tied = synchronizedLateMoveReduction(
        .{ .lmr_synchronization = true },
        .{},
        10,
        15,
        .{
            .improving = true,
            .expectation = .cut,
            .has_tt_move = false,
            .singular_context = false,
            .history = .neutral,
        },
        &observer,
    );
    try std.testing.expectEqual(base, tied);
    try std.testing.expectEqual(@as(u64, 0), observer.lmr_adjusted_shallower);
    try std.testing.expectEqual(@as(u64, 0), observer.lmr_adjusted_deeper);

    observer.reset();
    const disabled = synchronizedLateMoveReduction(
        .{ .lmr_synchronization = false },
        .{},
        10,
        15,
        .{
            .improving = false,
            .expectation = .cut,
            .has_tt_move = false,
            .singular_context = true,
            .history = .negative,
        },
        &observer,
    );
    try std.testing.expectEqual(base, disabled);
    try std.testing.expectEqual(@as(u64, 0), observer.lmr_adjusted_deeper);
}

test "reduced fail-low evidence receives only reduced TT depth authority" {
    // SCORE-001/PERF-006: a speculative fail-low may order later searches but
    // cannot masquerade as evidence produced at the nominal full depth.
    try std.testing.expectEqual(@as(u16, 5), tableDepth(.reduced_search, 6, 1));
    try std.testing.expectEqual(@as(u16, 3), tableDepth(.reduced_search, 6, 3));
    try std.testing.expectEqual(@as(u16, 6), tableDepth(.full_search, 6, 3));
    try std.testing.expectEqual(@as(u16, 0), tableDepth(.reduced_search, 0, 3));
}

test "dynamic verified null reduction is bounded by depth and eval margin" {
    // SCORE-021: only the speculative probe becomes shallower. The same-node
    // verification remains mandatory, and at least one probe ply plus two
    // verification plies survive every depth/margin combination.
    try std.testing.expectEqual(@as(u16, 2), dynamicNullMoveReduction(4, 0, 0));
    try std.testing.expectEqual(@as(u16, 2), dynamicNullMoveReduction(7, 199, 0));
    try std.testing.expectEqual(@as(u16, 3), dynamicNullMoveReduction(8, 0, 0));
    try std.testing.expectEqual(@as(u16, 4), dynamicNullMoveReduction(8, 200, 0));
    try std.testing.expectEqual(@as(u16, 3), dynamicNullMoveReduction(5, 400, 0));
    for (null_move_min_depth..16) |raw_depth| {
        const depth: u16 = @intCast(raw_depth);
        const reduction = dynamicNullMoveReduction(depth, 1_000, 0);
        try std.testing.expect(reduction >= fixed_null_move_reduction);
        try std.testing.expect(reduction <= depth - 2);
        try std.testing.expect(depth - 1 - reduction >= 1);
        try std.testing.expect(depth - reduction >= 2);
    }
}

test "shallow-selectivity fail-low with pruned siblings receives only reduced TT depth authority" {
    // SCORE-001/PERF-006: skipping a late move never proves it would fail to
    // raise alpha, so only a genuine fail-low downgrades; an exact result
    // already came from a fully searched move and keeps its true provenance.
    const fail_low = NodeValue{ .raw = -37, .bound = .upper, .provenance = .full_search };
    const exact = NodeValue{ .raw = 12, .bound = .exact, .provenance = .full_search };
    try std.testing.expectEqual(types.Provenance.reduced_search, speculativeStoreValue(fail_low, true).provenance);
    try std.testing.expectEqual(types.Provenance.full_search, speculativeStoreValue(fail_low, false).provenance);
    try std.testing.expectEqual(types.Provenance.full_search, speculativeStoreValue(exact, true).provenance);
    try std.testing.expectEqual(@as(i32, -37), speculativeStoreValue(fail_low, true).raw);
    try std.testing.expectEqual(types.Bound.upper, speculativeStoreValue(fail_low, true).bound);
}

test "qsearch SEE eligibility and final provenance preserve authority guards" {
    // SCORE-001/FUNC-004: SEE may omit only a losing ordinary capture; it
    // cannot decide evasions or promotions, and stand pat remains the producer
    // whenever no searched continuation supplies the best score.
    const enabled = types.Features{ .qsearch_see = true };
    try std.testing.expect(qsearchSeeCandidate(enabled, false, true, false, false));
    try std.testing.expect(!qsearchSeeCandidate(enabled, true, true, false, false));
    try std.testing.expect(!qsearchSeeCandidate(enabled, false, false, false, false));
    try std.testing.expect(!qsearchSeeCandidate(enabled, false, true, true, false));
    try std.testing.expect(!qsearchSeeCandidate(enabled, false, true, false, true));
    try std.testing.expect(!qsearchSeeCandidate(.{ .qsearch_see = false }, false, true, false, false));
    try std.testing.expectEqual(types.Provenance.stand_pat, qsearchFinalProvenance(false, .none, .stand_pat));
    try std.testing.expectEqual(
        types.Provenance.qsearch_move,
        qsearchFinalProvenance(false, chess.move.Move.normal(.e2, .e4), .tt_bound),
    );
    try std.testing.expectEqual(types.Provenance.tt_bound, qsearchFinalProvenance(false, .none, .tt_bound));
    try std.testing.expectEqual(types.Provenance.qsearch_move, qsearchFinalProvenance(true, .none, .stand_pat));
}

test "TT refinement preserves raw evaluation and follows bound direction" {
    // SCORE-020: searched bounds may strengthen pruning evaluation only in
    // their proven direction. Terminal/stand-pat evidence and decisive values
    // cannot masquerade as static evaluation.
    const raw: i32 = 20;
    const base = tt.Record{
        .chess_move = .none,
        .value = score.Score.fromOrdinary(80).?,
        .static_eval = score.Score.fromOrdinary(raw),
        .depth = 2,
        .bound = .lower,
        .generation = 0,
        .producer = .full_search,
    };
    try std.testing.expectEqual(@as(i32, 80), refinedStaticEval(raw, base));
    var wrong_direction = base;
    wrong_direction.value = score.Score.fromOrdinary(10).?;
    try std.testing.expectEqual(raw, refinedStaticEval(raw, wrong_direction));
    var upper = base;
    upper.bound = .upper;
    upper.value = score.Score.fromOrdinary(-30).?;
    try std.testing.expectEqual(@as(i32, -30), refinedStaticEval(raw, upper));
    var exact = base;
    exact.bound = .exact;
    exact.value = score.Score.fromOrdinary(7).?;
    try std.testing.expectEqual(@as(i32, 7), refinedStaticEval(raw, exact));
    var terminal = base;
    terminal.producer = .terminal;
    try std.testing.expectEqual(raw, refinedStaticEval(raw, terminal));
    var decisive = base;
    decisive.value = score.Score.mateIn(4).?;
    try std.testing.expectEqual(raw, refinedStaticEval(raw, decisive));
}

test "correction changes evaluation while improving pruning and TT stay raw" {
    // SCORE-020/SCORE-023: MAN-S25 may correct qsearch stand pat, but the
    // producer is not yet licensed to steer pruning or reductions. Seed a
    // positive correction large enough to reverse the apparent improving
    // relation and prove the selectivity input remains the raw relation.
    var root_state: chess.position.PositionState = .{};
    var position = try chess.fen.parse(
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        &root_state,
    );
    var heuristics: ordering.State = .{};
    var index: usize = 0;
    while (index < 4096) : (index += 1)
        heuristics.recordCorrection(position.side_to_move, position.current.pawn_key, 10_000, 64);

    var thread = types.ThreadState.init();
    thread.static_evals[0] = 20;
    var observer: diagnostics.Disabled = .{};
    var context = .{
        .thread = &thread,
        .heuristics = @as(?*ordering.State, &heuristics),
        .observer = &observer,
    };
    const FixedBinding = struct {
        pub fn evaluate(_: @This(), _: *const chess.position.Position) score.Score {
            return score.Score.fromOrdinary(10).?;
        }
    };
    const features = types.Features{ .correction_history = true };
    const shallow = shallowEvidence(
        features,
        true,
        &context,
        &position,
        FixedBinding{},
        2,
        false,
        false,
        null,
    );

    try std.testing.expect(shallow.static_eval > shallow.table_eval);
    try std.testing.expectEqual(@as(i32, 10), shallow.table_eval);
    try std.testing.expectEqual(@as(i32, 10), shallow.pruning_eval);
    try std.testing.expect(!shallow.improving);
    try std.testing.expectEqual(@as(i32, 10), thread.static_evals[2]);
    try std.testing.expectEqual(@as(?i32, 10), tableStaticEval(features, shallow));
}

test "correction producer accepts only directional ordinary search authority" {
    // SCORE-023: a search bound can teach only what it proves relative to raw
    // evaluation. Check/exclusion/depth-zero nodes and non-ordinary values
    // contribute nothing.
    var root_state: chess.position.PositionState = .{};
    var position = try chess.fen.parse(
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        &root_state,
    );
    var heuristics: ordering.State = .{};
    var observer: diagnostics.Disabled = .{};
    var context = .{
        .heuristics = @as(?*ordering.State, &heuristics),
        .observer = &observer,
    };
    const features = types.Features{ .correction_history = true };
    const known = ShallowEvidence{ .table_eval = 100, .known = true };

    recordCorrectionEvidence(features, &context, &position, known, .{
        .raw = 90,
        .bound = .lower,
        .provenance = .full_search,
    }, 8, false, false);
    try std.testing.expectEqual(@as(i32, 0), heuristics.correction(position.side_to_move, position.current.pawn_key));
    recordCorrectionEvidence(features, &context, &position, known, .{
        .raw = 140,
        .bound = .lower,
        .provenance = .full_search,
    }, 8, false, false);
    try std.testing.expect(heuristics.correction(position.side_to_move, position.current.pawn_key) > 0);

    heuristics.clear();
    recordCorrectionEvidence(features, &context, &position, known, .{
        .raw = 110,
        .bound = .upper,
        .provenance = .full_search,
    }, 8, false, false);
    try std.testing.expectEqual(@as(i32, 0), heuristics.correction(position.side_to_move, position.current.pawn_key));
    recordCorrectionEvidence(features, &context, &position, known, .{
        .raw = 60,
        .bound = .upper,
        .provenance = .full_search,
    }, 8, false, false);
    try std.testing.expect(heuristics.correction(position.side_to_move, position.current.pawn_key) < 0);

    heuristics.clear();
    recordCorrectionEvidence(features, &context, &position, known, .{
        .raw = 140,
        .bound = .exact,
        .provenance = .full_search,
    }, 0, false, false);
    recordCorrectionEvidence(features, &context, &position, known, .{
        .raw = 140,
        .bound = .exact,
        .provenance = .full_search,
    }, 8, true, false);
    recordCorrectionEvidence(features, &context, &position, .{}, .{
        .raw = 140,
        .bound = .exact,
        .provenance = .full_search,
    }, 8, false, false);
    recordCorrectionEvidence(features, &context, &position, known, .{
        .raw = score.mate_raw,
        .bound = .exact,
        .provenance = .full_search,
    }, 8, false, false);
    recordCorrectionEvidence(features, &context, &position, known, .{
        .raw = 60,
        .bound = .upper,
        .provenance = .reduced_search,
    }, 8, false, false);
    recordCorrectionEvidence(features, &context, &position, known, .{
        .raw = 60,
        .bound = .upper,
        .provenance = .pvs_probe,
    }, 8, false, true);
    try std.testing.expectEqual(@as(i32, 0), heuristics.correction(position.side_to_move, position.current.pawn_key));
}

test "ProbCut TT reuse requires compatible searched reduced-horizon evidence" {
    // SCORE-021: a sufficient ordinary lower/exact bound proves the raised
    // threshold, while upper/exact evidence may only suppress that speculative
    // probe. Reduced fail-low and nonsearched producers have no authority.
    const base = tt.Record{
        .chess_move = chess.move.Move.normal(.e2, .e4),
        .value = score.Score.fromOrdinary(250).?,
        .static_eval = null,
        .depth = 3,
        .bound = .lower,
        .generation = 0,
        .producer = .full_search,
    };
    try std.testing.expectEqual(ProbCutTableDecision.cutoff, probCutTableDecision(base, 6, 200));
    var upper = base;
    upper.bound = .upper;
    upper.value = score.Score.fromOrdinary(150).?;
    try std.testing.expectEqual(ProbCutTableDecision.skip, probCutTableDecision(upper, 6, 200));
    var shallow = base;
    shallow.depth = 2;
    try std.testing.expectEqual(ProbCutTableDecision.search, probCutTableDecision(shallow, 6, 200));
    var reduced = base;
    reduced.producer = .reduced_search;
    try std.testing.expectEqual(ProbCutTableDecision.search, probCutTableDecision(reduced, 6, 200));
    var terminal = base;
    terminal.producer = .terminal;
    try std.testing.expectEqual(ProbCutTableDecision.search, probCutTableDecision(terminal, 6, 200));
    try std.testing.expectEqual(ProbCutTableDecision.search, probCutTableDecision(null, 6, 200));
}

test "history and eval synchronize pruning without crossing authority guards" {
    // SCORE-021: accepted history changes only late-quiet selectivity and the
    // TT-refined evaluation can only tighten capture SEE. Component and
    // umbrella switches restore the accepted MAN-S19 thresholds exactly.
    const enabled: types.Features = .{ .main_selectivity_sync = true };
    const base_see = seePruningThreshold(.{}, 2);
    try std.testing.expectEqual(@as(usize, 6), historyLateMovePruneThreshold(enabled, 7, .negative));
    try std.testing.expectEqual(@as(usize, 8), historyLateMovePruneThreshold(enabled, 7, .positive));
    try std.testing.expectEqual(@as(usize, 7), historyLateMovePruneThreshold(enabled, 7, .neutral));
    try std.testing.expectEqual(
        @as(usize, 7),
        historyLateMovePruneThreshold(.{ .main_selectivity_sync = false }, 7, .negative),
    );
    try std.testing.expectEqual(@as(i32, -200), synchronizedSeePruningThreshold(enabled, .{}, 0, 100, 2));
    try std.testing.expectEqual(@as(i32, 100), synchronizedSeePruningThreshold(enabled, .{}, -300, 100, 2));
    try std.testing.expectEqual(
        base_see,
        synchronizedSeePruningThreshold(.{ .capture_futility = false }, .{}, -300, 100, 2),
    );
    const mate_alpha = score.Score.mateIn(3).?.raw();
    try std.testing.expectEqual(base_see, synchronizedSeePruningThreshold(enabled, .{}, 0, mate_alpha, 2));
}

test "qsearch delta threshold protects authoritative and special move paths" {
    // SCORE-020/FUNC-004: only a non-PV ordinary nonchecking capture whose
    // nonnegative SEE still cannot bridge alpha beyond a pawn cushion is a
    // candidate. Promotions, evasions, losing captures and decisive bands are
    // owned by their existing search rules.
    const enabled: types.Features = .{};
    const search_params: params.Values = .{};
    try std.testing.expectEqual(
        @as(?i32, 150 - search_params.qsearch_delta_cushion),
        qsearchDeltaThreshold(enabled, search_params, false, false, true, false, 0, 150, true),
    );
    try std.testing.expectEqual(@as(?i32, null), qsearchDeltaThreshold(enabled, .{}, true, false, true, false, 0, 150, true));
    try std.testing.expectEqual(@as(?i32, null), qsearchDeltaThreshold(enabled, .{}, false, true, true, false, 0, 150, true));
    try std.testing.expectEqual(@as(?i32, null), qsearchDeltaThreshold(enabled, .{}, false, false, false, false, 0, 150, true));
    try std.testing.expectEqual(@as(?i32, null), qsearchDeltaThreshold(enabled, .{}, false, false, true, true, 0, 150, true));
    try std.testing.expectEqual(@as(?i32, null), qsearchDeltaThreshold(enabled, .{}, false, false, true, false, 0, 150, false));
    try std.testing.expectEqual(@as(?i32, null), qsearchDeltaThreshold(.{ .eval_qsearch_sync = false }, .{}, false, false, true, false, 0, 150, true));
    try std.testing.expectEqual(@as(?i32, null), qsearchDeltaThreshold(.{ .qsearch_delta = false }, .{}, false, false, true, false, 0, 150, true));
    try std.testing.expectEqual(@as(?i32, null), qsearchDeltaThreshold(enabled, .{}, false, false, true, false, 100, 150, true));
    const mate_alpha = score.Score.mateIn(3).?.raw();
    try std.testing.expectEqual(@as(?i32, null), qsearchDeltaThreshold(enabled, .{}, false, false, true, false, 0, mate_alpha, true));
}

test "reverse futility eligibility excludes authoritative and zugzwang-sensitive nodes" {
    // SCORE-001/FUNC-004: raw evaluation may support only a shallow heuristic
    // lower bound. PV, check, pawn-only and decisive-score nodes retain normal
    // move search, while the margin derives from Manta's public pawn scale.
    const enabled = types.Features{ .reverse_futility = true };
    const ordinary = score.Score.fromOrdinary(50).?;
    try std.testing.expect(reverseFutilityEligible(enabled, 1, false, false, true, true, ordinary));
    try std.testing.expect(!reverseFutilityEligible(enabled, 3, false, false, true, true, ordinary));
    try std.testing.expect(!reverseFutilityEligible(enabled, 4, false, false, true, true, ordinary));
    try std.testing.expect(!reverseFutilityEligible(enabled, 1, true, false, true, true, ordinary));
    try std.testing.expect(!reverseFutilityEligible(enabled, 1, false, true, true, true, ordinary));
    try std.testing.expect(!reverseFutilityEligible(enabled, 1, false, false, false, true, ordinary));
    try std.testing.expect(!reverseFutilityEligible(enabled, 1, false, false, true, false, ordinary));
    try std.testing.expect(!reverseFutilityEligible(
        enabled,
        1,
        false,
        false,
        true,
        true,
        score.Score.mateIn(4).?,
    ));
    try std.testing.expect(!reverseFutilityEligible(
        .{ .shallow_selectivity = true, .reverse_futility = false },
        1,
        false,
        false,
        true,
        true,
        ordinary,
    ));
    const search_params: params.Values = .{};
    try std.testing.expectEqual(search_params.reverse_futility_margin, reverseFutilityMargin(search_params, 1));
}

test "razoring eligibility excludes PV, exclusion, pawn-only and decisive-alpha nodes" {
    // SCORE-001/FUNC-004: razoring only ever substitutes a real, fully
    // searched quiescence result for this node, so its guard must exclude
    // every node whose alpha-side static comparison cannot be trusted.
    const enabled = types.Features{ .shallow_selectivity = true, .razoring = true };
    const ordinary = score.Score.fromOrdinary(-20).?;
    try std.testing.expect(razoringEligible(enabled, 1, false, false, true, ordinary));
    try std.testing.expect(!razoringEligible(enabled, 2, false, false, true, ordinary));
    try std.testing.expect(!razoringEligible(enabled, 1, true, false, true, ordinary));
    try std.testing.expect(!razoringEligible(enabled, 1, false, true, true, ordinary));
    try std.testing.expect(!razoringEligible(enabled, 1, false, false, false, ordinary));
    try std.testing.expect(!razoringEligible(enabled, 1, false, false, true, score.Score.mateIn(4).?));
    try std.testing.expect(!razoringEligible(.{ .shallow_selectivity = true, .razoring = false }, 1, false, false, true, ordinary));
    try std.testing.expect(!razoringEligible(.{ .shallow_selectivity = false, .razoring = true }, 1, false, false, true, ordinary));
    try std.testing.expect(razoringMargin(1, true) < razoringMargin(1, false));
    try std.testing.expect(razoringMargin(1, true) < razoringMargin(2, true));
}

test "late-move pruning and quiet futility protect the first move, PV and pawn-only nodes" {
    // PERF-010/QUAL-014: the first searched move at any node must always
    // receive full authority so a node can never finish with no honestly
    // searched move; PV and zugzwang-sensitive pawn-only nodes never accept
    // speculative move-count or static evidence.
    const enabled = types.Features{ .shallow_selectivity = true, .late_move_pruning = true, .quiet_futility = true };
    const known = ShallowEvidence{ .static_eval = -400, .pruning_eval = -400, .improving = false, .known = true };
    try std.testing.expect(lateMovePruneEligible(enabled, known, false, 1, 1, true, 0, 1));
    try std.testing.expect(!lateMovePruneEligible(enabled, known, false, 1, 0, true, 0, 1));
    try std.testing.expect(!lateMovePruneEligible(enabled, known, true, 1, 1, true, 0, 1));
    try std.testing.expect(!lateMovePruneEligible(enabled, known, false, 1, 1, false, 0, 1));
    try std.testing.expect(!lateMovePruneEligible(enabled, .{}, false, 1, 1, true, 0, 1));
    try std.testing.expect(!lateMovePruneEligible(enabled, known, false, 4, 1, true, 0, 1));
    try std.testing.expect(!lateMovePruneEligible(enabled, known, false, 1, 1, true, 0, 2));
    const mate_alpha = score.Score.mateIn(4).?.raw();
    try std.testing.expect(!lateMovePruneEligible(enabled, known, false, 1, 1, true, mate_alpha, mate_alpha + 1));
    try std.testing.expect(!lateMovePruneEligible(.{ .shallow_selectivity = true, .late_move_pruning = false }, known, false, 1, 1, true, 0, 1));
    try std.testing.expect(quietFutilityEligible(enabled, known, false, 3, 1, true, 0, 1));
    try std.testing.expect(!quietFutilityEligible(enabled, known, false, 4, 1, true, 0, 1));
    try std.testing.expect(!quietFutilityEligible(enabled, known, false, 3, 0, true, 0, 1));
    try std.testing.expect(!quietFutilityEligible(enabled, known, true, 3, 1, true, 0, 1));
    try std.testing.expect(!quietFutilityEligible(enabled, known, false, 3, 1, false, 0, 1));
    const search_params: params.Values = .{};
    const ordinary_threshold: usize = @intCast(search_params.late_move_base + search_params.late_move_depth_scale);
    try std.testing.expectEqual(ordinary_threshold, lateMovePruneThreshold(search_params, 1, false));
    try std.testing.expectEqual(
        ordinary_threshold + @as(usize, @intCast(search_params.late_move_improving_bonus)),
        lateMovePruneThreshold(search_params, 1, true),
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        lateMovePruneThreshold(.{ .late_move_base = 1, .late_move_depth_scale = 2 }, 1, false),
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        lateMovePruneThreshold(.{ .late_move_base = 3, .late_move_depth_scale = 0 }, 3, false),
    );
    try std.testing.expectEqual(
        @as(usize, 9),
        lateMovePruneThreshold(.{ .late_move_base = 3, .late_move_depth_scale = 2, .late_move_improving_bonus = 4 }, 1, true),
    );
    try std.testing.expect(quietFutilityMargin(.{}, 1, true) < quietFutilityMargin(.{}, 1, false));
}

test "main-search SEE pruning excludes promotions, wide windows, PV and pawn-only nodes" {
    // SCORE-001/FUNC-004: SEE is a fallible local exchange predicate, so main
    // search may only use it as capture eligibility, exactly as accepted
    // qsearch SEE already does, and never at a PV, already-authoritative or
    // zugzwang-sensitive pawn-only node.
    const enabled = types.Features{ .shallow_selectivity = true, .see_pruning = true };
    const known = ShallowEvidence{ .static_eval = 0, .pruning_eval = 0, .improving = false, .known = true };
    try std.testing.expect(seePruneEligible(enabled, known, false, 2, 1, true, false, true, 0, 1));
    try std.testing.expect(!seePruneEligible(enabled, known, true, 2, 1, true, false, true, 0, 1));
    try std.testing.expect(!seePruneEligible(enabled, known, false, 2, 0, true, false, true, 0, 1));
    try std.testing.expect(!seePruneEligible(enabled, known, false, 4, 1, true, false, true, 0, 1));
    try std.testing.expect(!seePruneEligible(enabled, known, false, 2, 1, true, true, true, 0, 1));
    try std.testing.expect(!seePruneEligible(enabled, known, false, 2, 1, false, false, true, 0, 1));
    try std.testing.expect(!seePruneEligible(enabled, known, false, 2, 1, true, false, false, 0, 1));
    try std.testing.expect(!seePruneEligible(enabled, known, false, 2, 1, true, false, true, 0, 2));
    try std.testing.expect(!seePruneEligible(enabled, .{}, false, 2, 1, true, false, true, 0, 1));
    const search_params: params.Values = .{};
    try std.testing.expectEqual(-search_params.see_pruning_unit, seePruningThreshold(search_params, 1));
    try std.testing.expectEqual(-3 * search_params.see_pruning_unit, seePruningThreshold(search_params, 3));
}

/// Extends the current PV with the continuation produced by the child search
/// that just returned from this exact position transition.
fn extendPv(thread: *types.ThreadState, ply: usize, chess_move: chess.move.Move) void {
    thread.pv_moves[ply][0] = chess_move;
    const child_length = thread.pv_lengths[ply + 1];
    @memcpy(thread.pv_moves[ply][1 .. child_length + 1], thread.pv_moves[ply + 1][0..child_length]);
    thread.pv_lengths[ply] = child_length + 1;
}

/// Publishes the only legal continuation evidence carried by a TT cutoff.
fn setPvMove(thread: *types.ThreadState, ply: usize, chess_move: chess.move.Move) void {
    thread.pv_moves[ply][0] = chess_move;
    thread.pv_lengths[ply] = 1;
}

fn terminalRoot(value: *const chess.position.Position) types.Result {
    const raw = if (value.current.checkers != 0) score.Score.matedIn(0).?.raw() else 0;
    return .{
        .best_move = null,
        .evidence = evidence(raw, .exact, .terminal),
        .completed = null,
        .termination = .terminal,
        .nodes = 0,
        .tablebase_hits = 0,
        .selective_depth = 0,
    };
}

fn terminalNode(value: *const chess.position.Position, ply: usize) NodeValue {
    return .{
        .raw = if (value.current.checkers != 0) score.Score.matedIn(ply).?.raw() else 0,
        .bound = .exact,
        .provenance = .terminal,
    };
}

fn negated(child: NodeValue) NodeValue {
    return .{
        .raw = -child.raw,
        .bound = switch (child.bound) {
            .exact => .exact,
            .lower => .upper,
            .upper => .lower,
        },
        .provenance = child.provenance,
    };
}

fn evidence(raw: i32, bound: types.Bound, provenance: types.Provenance) types.Evidence {
    const value = score.Score{ .raw_value = raw };
    std.debug.assert(value.isValid() and !value.isNone());
    return .{ .value = value, .bound = bound, .provenance = provenance };
}

comptime {
    _ = eval_contract.Update;
}
