//! Receipt-based time budgeting and completed-root allocation policy.
const std = @import("std");
const search_build_options = @import("search_build_options");
const score = @import("../score.zig");
const search = @import("../search/root.zig");

pub const sudden_death_initial_horizon: u64 = 36;
pub const sudden_death_minimum_horizon: u64 = 20;
pub const horizon_progress_plies: u64 = 8;
pub const maximum_horizon: u64 = 64;
pub const maximum_multiplier: u64 = 4;
pub const poll_interval_nodes: u16 = 1024;
pub const integrated_minimum_depth: u16 = 4;

const permille: u64 = 1000;
const minimum_dynamic_factor: u64 = 350;
const maximum_dynamic_factor: u64 = 2200;
const ponder_credit_permille: u64 = 750;

pub const tune_enabled = search_build_options.tune and search_build_options.integrated_time;

// Production consumes the sole nearest-integer bake of MAN-T04's complete
// theta. The explicit integrated-time-off arm reconstructs the pre-fit policy.
const horizon_scale_default = if (search_build_options.integrated_time) 1034 else 1000;
const increment_credit_default = if (search_build_options.integrated_time) 957 else 1000;
const maximum_ratio_default = if (search_build_options.integrated_time) 4291 else 4000;
const stability_response_default = if (search_build_options.integrated_time) 1036 else 1000;
const score_response_default = if (search_build_options.integrated_time) 1049 else 1000;
const effort_response_default = if (search_build_options.integrated_time) 1046 else 1000;

pub const ParamId = enum {
    horizon_scale,
    increment_credit,
    maximum_ratio,
    stability_response,
    score_response,
    effort_response,
};

pub const ParamSpec = struct {
    id: ParamId,
    name: []const u8,
    default: i32,
    min: i32,
    max: i32,
};

/// These are the complete continuously tunable one-thread surface of the
/// integrated policy. Safety reserves, evidence thresholds and categorical
/// switches deliberately remain outside the tuning interface.
pub const param_specs = [_]ParamSpec{
    .{ .id = .horizon_scale, .name = "TimeHorizonScale", .default = horizon_scale_default, .min = 700, .max = 1300 },
    .{ .id = .increment_credit, .name = "TimeIncrementCredit", .default = increment_credit_default, .min = 500, .max = 1500 },
    .{ .id = .maximum_ratio, .name = "TimeMaximumRatio", .default = maximum_ratio_default, .min = 2000, .max = 6000 },
    .{ .id = .stability_response, .name = "TimeStabilityResponse", .default = stability_response_default, .min = 0, .max = 2000 },
    .{ .id = .score_response, .name = "TimeScoreResponse", .default = score_response_default, .min = 0, .max = 2000 },
    .{ .id = .effort_response, .name = "TimeEffortResponse", .default = effort_response_default, .min = 0, .max = 2000 },
};

pub const Params = struct {
    horizon_scale: i32 = horizon_scale_default,
    increment_credit: i32 = increment_credit_default,
    maximum_ratio: i32 = maximum_ratio_default,
    stability_response: i32 = stability_response_default,
    score_response: i32 = score_response_default,
    effort_response: i32 = effort_response_default,

    pub fn get(self: Params, id: ParamId) i32 {
        return switch (id) {
            inline else => |tag| @field(self, @tagName(tag)),
        };
    }

    pub fn set(self: *Params, id: ParamId, value: i32) void {
        const spec = paramSpecFor(id);
        switch (id) {
            inline else => |tag| @field(self, @tagName(tag)) = std.math.clamp(value, spec.min, spec.max),
        }
    }
};

pub fn findParam(name: []const u8) ?ParamSpec {
    for (param_specs) |spec|
        if (std.ascii.eqlIgnoreCase(name, spec.name)) return spec;
    return null;
}

fn paramSpecFor(id: ParamId) ParamSpec {
    for (param_specs) |spec|
        if (spec.id == id) return spec;
    unreachable;
}

pub const Input = union(enum) {
    movetime_ms: u64,
    clock: struct {
        remaining_ms: u64,
        increment_ms: u64 = 0,
        moves_to_go: ?u64 = null,
        game_ply: u64 = 0,
    },
};

pub const Budget = struct {
    optimum_ms: u64,
    maximum_ms: u64,
};

/// Produces a preferred and absolute-maximum budget while leaving the explicit
/// current-move and scheduling reserves untouchable. Future increment is
/// credited across the estimated horizon only after reserving future command
/// overhead. Sudden-death horizons contract gradually with game progress;
/// explicit moves-to-go remains authoritative within a bounded arithmetic
/// range. Fixed movetime retains its single-overhead contract.
pub fn budget(input: Input, overhead_ms: u64, scheduling_reserve_ms: u64) Budget {
    return budgetWithParams(input, overhead_ms, scheduling_reserve_ms, .{});
}

pub fn budgetWithParams(
    input: Input,
    overhead_ms: u64,
    scheduling_reserve_ms: u64,
    params: Params,
) Budget {
    return switch (input) {
        .movetime_ms => |milliseconds| blk: {
            const usable = milliseconds -| overhead_ms;
            break :blk .{ .optimum_ms = usable, .maximum_ms = usable };
        },
        .clock => |clock| blk: {
            const usable = clock.remaining_ms -| overhead_ms -| scheduling_reserve_ms;
            if (usable == 0) break :blk .{ .optimum_ms = 0, .maximum_ms = 0 };
            const horizon = if (clock.moves_to_go) |moves|
                std.math.clamp(moves, 1, maximum_horizon)
            else blk_horizon: {
                const progress = @min(
                    clock.game_ply / horizon_progress_plies,
                    sudden_death_initial_horizon - sudden_death_minimum_horizon,
                );
                const base_horizon = sudden_death_initial_horizon - progress;
                break :blk_horizon std.math.clamp(
                    scalePermille(base_horizon, @intCast(params.horizon_scale)),
                    1,
                    maximum_horizon,
                );
            };
            const future_moves = horizon - 1;
            const credited_increment = scalePermille(
                clock.increment_ms,
                @intCast(params.increment_credit),
            );
            const projected = usable +| (credited_increment *| future_moves);
            const future_reserve = overhead_ms *| future_moves;
            const pool = projected -| future_reserve;
            const optimum = @min(usable, @max(pool / horizon, 1));
            const maximum = @min(
                usable,
                scalePermille(optimum, @intCast(params.maximum_ratio)),
            );
            break :blk .{
                .optimum_ms = optimum,
                .maximum_ms = @max(optimum, maximum),
            };
        },
    };
}

pub fn deadline(received_ns: u64, milliseconds: u64) u64 {
    return received_ns +| (milliseconds *| std.time.ns_per_ms);
}

/// Returns the latest permitted completed-iteration stop deadline. The base
/// soft deadline remains authoritative unless at least two independent signs
/// of root uncertainty agree: a newly changed best move, a falling best score,
/// or a majority of the iteration's effort concentrated in the best move.
/// Two signs spend half of the already-reserved soft-to-hard interval; all
/// three may spend the interval through the unchanged hard deadline.
pub fn confidenceDeadline(
    soft_deadline_ns: u64,
    hard_deadline_ns: u64,
    snapshot: search.types.RootConfidenceSnapshot,
) u64 {
    if (hard_deadline_ns <= soft_deadline_ns) return soft_deadline_ns;

    var uncertainty_signals: u2 = 0;
    if (snapshot.completed_iterations >= 2 and snapshot.stable_best_iterations == 1)
        uncertainty_signals += 1;
    if (snapshot.best_score_delta != null and snapshot.best_score_delta.? < 0)
        uncertainty_signals += 1;
    if (snapshot.total_effort != 0 and snapshot.best_effort > snapshot.total_effort / 2)
        uncertainty_signals += 1;

    const extension = hard_deadline_ns - soft_deadline_ns;
    return switch (uncertainty_signals) {
        0, 1 => soft_deadline_ns,
        2 => soft_deadline_ns + extension / 2,
        3 => hard_deadline_ns,
    };
}

pub const SmpEvidence = struct {
    helper_instability_events: u64 = 0,
    helper_count: u16 = 0,
};

pub const DynamicFactors = struct {
    root_permille: u64 = permille,
    stability_permille: u64 = permille,
    score_permille: u64 = permille,
    effort_permille: u64 = permille,
    smp_permille: u64 = permille,
    combined_permille: u64 = permille,
};

pub const StopReason = enum {
    none,
    minimum_depth,
    continue_search,
    optimum_reached,
    maximum_reached,
    hard_deadline,
    external,
    search_complete,
};

/// One fixed-size, worker-zero-owned diagnostic snapshot. It is populated only
/// in the integrated-time build and never grants stopping or result authority.
pub const Telemetry = struct {
    allocation: Budget,
    factors: DynamicFactors = .{},
    ponder_credit_ns: u64 = 0,
    helper_instability_events: u64 = 0,
    helper_count: u16 = 0,
    target_ns: u64 = 0,
    stop_reason: StopReason = .none,
    hard_overshoot_ns: u64 = 0,
};

fn scalePermille(value: u64, factor: u64) u64 {
    const wide = @as(u128, value) * @as(u128, factor) / permille;
    return @intCast(@min(wide, std.math.maxInt(u64)));
}

fn responseFactor(base_factor: u64, response: i32) u64 {
    const delta = @as(i64, @intCast(base_factor)) - @as(i64, @intCast(permille));
    const adjusted = @as(i64, @intCast(permille)) +
        @divTrunc(delta * @as(i64, response), @as(i64, @intCast(permille)));
    return @intCast(@max(adjusted, 0));
}

fn ordinaryRootEvidence(completed: search.types.CompletedIteration) bool {
    return completed.evidence.bound == .exact and
        completed.evidence.value.isOrdinary() and
        completed.root_confidence.root_move_count != 0;
}

/// A helper may contribute only this bounded categorical time observation.
/// It carries no move, score, PV or result authority.
pub fn rootInstability(completed: search.types.CompletedIteration) bool {
    return ordinaryRootEvidence(completed) and
        completed.root_confidence.completed_iterations >= 2 and
        completed.root_confidence.stable_best_iterations == 1;
}

/// Derives one bounded multiplier from a completed ordinary root iteration.
/// A single legal move is genuinely forced; a one-move `searchmoves`
/// restriction is not, because `legal_root_move_count` describes the position
/// before the restriction. Helper instability is normalized by helper count,
/// so adding workers cannot multiply the wall-time allocation.
pub fn dynamicFactors(
    completed: search.types.CompletedIteration,
    legal_root_move_count: u16,
    smp: SmpEvidence,
) DynamicFactors {
    return dynamicFactorsWithParams(completed, legal_root_move_count, smp, .{});
}

pub fn dynamicFactorsWithParams(
    completed: search.types.CompletedIteration,
    legal_root_move_count: u16,
    smp: SmpEvidence,
    params: Params,
) DynamicFactors {
    var factors: DynamicFactors = .{};
    if (!ordinaryRootEvidence(completed)) return factors;
    const snapshot = completed.root_confidence;
    if (legal_root_move_count == 1) {
        factors.root_permille = minimum_dynamic_factor;
        factors.combined_permille = minimum_dynamic_factor;
        return factors;
    }

    if (snapshot.completed_iterations >= 2 and snapshot.stable_best_iterations == 1) {
        factors.stability_permille = responseFactor(1300, params.stability_response);
    } else if (snapshot.stable_best_iterations >= 4) {
        factors.stability_permille = responseFactor(750, params.stability_response);
    } else if (snapshot.stable_best_iterations >= 2) {
        factors.stability_permille = responseFactor(875, params.stability_response);
    }

    if (snapshot.best_score_delta) |delta| {
        if (delta <= -score.units_per_pawn) {
            factors.score_permille = responseFactor(1400, params.score_response);
        } else if (delta < 0) {
            factors.score_permille = responseFactor(1150, params.score_response);
        } else if (delta >= score.units_per_pawn) {
            factors.score_permille = responseFactor(900, params.score_response);
        }
    }

    if (snapshot.root_move_count >= 2 and snapshot.total_effort != 0) {
        const effort_permille = @as(u128, snapshot.best_effort) * permille /
            snapshot.total_effort;
        if (effort_permille >= 700) {
            // Concentrated effort plus a stable choice is evidence that one
            // move dominates, not MAN-R01's rejected uncertainty reading.
            factors.effort_permille = responseFactor(800, params.effort_response);
        } else if (effort_permille <= 350) {
            factors.effort_permille = responseFactor(1150, params.effort_response);
        }
    }

    if (smp.helper_count != 0 and smp.helper_instability_events != 0) {
        const events = @min(smp.helper_instability_events, smp.helper_count);
        const addition = @as(u64, @intCast(
            @as(u128, 200) * events / smp.helper_count,
        ));
        factors.smp_permille = permille + addition;
    }
    var combined = factors.root_permille;
    combined = scalePermille(combined, factors.stability_permille);
    combined = scalePermille(combined, factors.score_permille);
    combined = scalePermille(combined, factors.effort_permille);
    combined = scalePermille(combined, factors.smp_permille);
    factors.combined_permille = std.math.clamp(
        combined,
        minimum_dynamic_factor,
        maximum_dynamic_factor,
    );
    return factors;
}

pub fn dynamicFactorPermille(
    completed: search.types.CompletedIteration,
    legal_root_move_count: u16,
    smp: SmpEvidence,
) u64 {
    return dynamicFactors(completed, legal_root_move_count, smp).combined_permille;
}

const IntegratedDecision = struct {
    deadline_ns: u64,
    target_ns: u64,
    factors: DynamicFactors,
};

fn integratedDecision(
    received_ns: u64,
    allocation: Budget,
    completed: search.types.CompletedIteration,
    legal_root_move_count: u16,
    smp: SmpEvidence,
    ponder_credit_ns: ?u64,
    params: Params,
) IntegratedDecision {
    const hard = deadline(received_ns, allocation.maximum_ms);
    if (completed.depth < integrated_minimum_depth) return .{
        .deadline_ns = hard,
        .target_ns = allocation.maximum_ms *| std.time.ns_per_ms,
        .factors = .{},
    };
    const factors = dynamicFactorsWithParams(completed, legal_root_move_count, smp, params);
    const preferred_ms = @min(
        allocation.maximum_ms,
        scalePermille(allocation.optimum_ms, factors.combined_permille),
    );
    const target_ns = preferred_ms *| std.time.ns_per_ms +| scalePermille(
        ponder_credit_ns orelse 0,
        permille - ponder_credit_permille,
    );
    return .{
        .deadline_ns = @min(hard, received_ns +| target_ns),
        .target_ns = @min(target_ns, allocation.maximum_ms *| std.time.ns_per_ms),
        .factors = factors,
    };
}

/// Preferred completed-iteration deadline for the integrated policy. Ponder
/// credit is consumed once at 75%: the remaining quarter acknowledges that a
/// ponder line may be wrong. Neither credit nor dynamic evidence can move the
/// immutable maximum deadline.
pub fn integratedDeadline(
    received_ns: u64,
    allocation: Budget,
    completed: search.types.CompletedIteration,
    legal_root_move_count: u16,
    smp: SmpEvidence,
    ponder_credit_ns: ?u64,
) u64 {
    return integratedDecision(
        received_ns,
        allocation,
        completed,
        legal_root_move_count,
        smp,
        ponder_credit_ns,
        .{},
    ).deadline_ns;
}

pub fn Control(
    comptime Clock: type,
    comptime root_confidence_time: bool,
    comptime integrated_time: bool,
) type {
    return struct {
        clock: *Clock,
        cancel_epoch: *const std.atomic.Value(u64),
        ponderhit_epoch: ?*const std.atomic.Value(u64) = null,
        ponderhit_received_ns: ?*const std.atomic.Value(u64) = null,
        epoch: u64,
        pondering: bool = false,
        received_ns: u64 = 0,
        ponder_credit_ns: ?u64 = null,
        initial_budget: ?Budget = null,
        integrated_budget: ?Budget = null,
        params: Params = .{},
        legal_root_move_count: u16 = 0,
        soft_deadline_ns: ?u64,
        hard_deadline_ns: ?u64,
        poll_countdown: u16 = 0,
        reason: search.types.Termination = .stopped,
        telemetry_state: if (integrated_time) ?Telemetry else void = if (integrated_time) null else {},

        fn baseTelemetry(self: *const @This()) ?Telemetry {
            if (comptime !integrated_time) return null;
            const allocation = self.initial_budget orelse return null;
            return .{
                .allocation = allocation,
                .ponder_credit_ns = self.ponder_credit_ns orelse 0,
                .target_ns = allocation.optimum_ms *| std.time.ns_per_ms,
            };
        }

        fn recordStop(self: *@This(), stop_reason: StopReason, overshoot_ns: u64) void {
            if (comptime !integrated_time) return;
            var snapshot = self.telemetry_state orelse self.baseTelemetry() orelse return;
            snapshot.stop_reason = stop_reason;
            snapshot.ponder_credit_ns = self.ponder_credit_ns orelse 0;
            snapshot.hard_overshoot_ns = overshoot_ns;
            self.telemetry_state = snapshot;
        }

        fn clockIsActive(self: *@This()) bool {
            if (!self.pondering) return true;
            const hit = self.ponderhit_epoch orelse return false;
            if (hit.load(.acquire) != self.epoch) return false;
            if (self.ponderhit_received_ns) |received| {
                // The epoch's acquire observes the timestamp stored before the
                // matching release. Saturation protects synthetic/faulty clocks
                // without ever manufacturing negative credit.
                self.ponder_credit_ns = received.load(.monotonic) -| self.received_ns;
            }
            self.pondering = false;
            return true;
        }

        pub fn shouldStop(self: *@This()) bool {
            if (self.cancel_epoch.load(.acquire) == self.epoch) {
                self.reason = .stopped;
                self.recordStop(.external, 0);
                return true;
            }
            // Ponder work may satisfy fixed depth/node limits, but its game
            // clock cannot terminate the search until this exact epoch is hit.
            // Deadlines remain rooted at `go` receipt, so a late hit can be
            // immediately out of time rather than receiving a fresh budget.
            if (!self.clockIsActive()) return false;
            if (self.hard_deadline_ns == null) return false;
            if (self.poll_countdown != 0) {
                self.poll_countdown -= 1;
                return false;
            }
            self.poll_countdown = poll_interval_nodes - 1;
            const now_ns = self.clock.nowNs();
            if (now_ns >= self.hard_deadline_ns.?) {
                self.reason = .time_limit;
                self.recordStop(.hard_deadline, now_ns - self.hard_deadline_ns.?);
                return true;
            }
            return false;
        }

        pub fn shouldStopAfterIteration(
            self: *@This(),
            completed: search.types.CompletedIteration,
            smp: SmpEvidence,
        ) bool {
            if (self.cancel_epoch.load(.acquire) == self.epoch) {
                self.reason = .stopped;
                self.recordStop(.external, 0);
                return true;
            }
            if (!self.clockIsActive()) return false;
            if (self.soft_deadline_ns) |soft| {
                const decision = if (comptime integrated_time)
                    if (self.integrated_budget) |allocation|
                        integratedDecision(
                            self.received_ns,
                            allocation,
                            completed,
                            self.legal_root_move_count,
                            smp,
                            self.ponder_credit_ns,
                            self.params,
                        )
                    else
                        IntegratedDecision{
                            .deadline_ns = soft,
                            .target_ns = soft -| self.received_ns,
                            .factors = .{},
                        }
                else if (comptime root_confidence_time) IntegratedDecision{
                    .deadline_ns = confidenceDeadline(
                        soft,
                        self.hard_deadline_ns orelse soft,
                        completed.root_confidence,
                    ),
                    .target_ns = soft -| self.received_ns,
                    .factors = .{},
                } else IntegratedDecision{
                    .deadline_ns = soft,
                    .target_ns = soft -| self.received_ns,
                    .factors = .{},
                };
                const now_ns = self.clock.nowNs();
                if (comptime integrated_time) if (self.baseTelemetry()) |base| {
                    var snapshot = base;
                    snapshot.factors = decision.factors;
                    snapshot.ponder_credit_ns = self.ponder_credit_ns orelse 0;
                    snapshot.helper_instability_events = smp.helper_instability_events;
                    snapshot.helper_count = smp.helper_count;
                    snapshot.target_ns = decision.target_ns;
                    const hard = self.hard_deadline_ns orelse decision.deadline_ns;
                    snapshot.stop_reason = if (completed.depth < integrated_minimum_depth)
                        .minimum_depth
                    else if (now_ns >= hard)
                        .maximum_reached
                    else if (now_ns >= decision.deadline_ns)
                        .optimum_reached
                    else
                        .continue_search;
                    if (now_ns >= hard) snapshot.hard_overshoot_ns = now_ns - hard;
                    self.telemetry_state = snapshot;
                };
                if (now_ns >= decision.deadline_ns) {
                    self.reason = .time_limit;
                    return true;
                }
            }
            return false;
        }

        pub fn terminationReason(self: *const @This()) search.types.Termination {
            return self.reason;
        }

        pub fn ponderCreditNs(self: *const @This()) ?u64 {
            return self.ponder_credit_ns;
        }

        pub fn finish(
            self: *@This(),
            termination: search.types.Termination,
            final_smp: SmpEvidence,
        ) void {
            if (comptime !integrated_time) return;
            var snapshot = self.telemetry_state orelse self.baseTelemetry() orelse return;
            switch (termination) {
                .stopped => snapshot.stop_reason = .external,
                .depth_limit, .node_limit, .terminal, .root_draw => snapshot.stop_reason = .search_complete,
                .time_limit => if (snapshot.stop_reason == .none or
                    snapshot.stop_reason == .continue_search or
                    snapshot.stop_reason == .minimum_depth)
                {
                    snapshot.stop_reason = .maximum_reached;
                },
            }
            snapshot.ponder_credit_ns = self.ponder_credit_ns orelse 0;
            snapshot.helper_count = final_smp.helper_count;
            if (final_smp.helper_instability_events != 0)
                snapshot.helper_instability_events = final_smp.helper_instability_events;
            self.telemetry_state = snapshot;
        }

        pub fn telemetry(self: *const @This()) ?Telemetry {
            if (comptime !integrated_time) return null;
            return self.telemetry_state orelse self.baseTelemetry();
        }
    };
}

const FakeClock = struct {
    now_ns: u64 = 0,

    fn nowNs(self: *FakeClock) u64 {
        return self.now_ns;
    }
};

fn completedIteration(
    depth: u16,
    snapshot: search.types.RootConfidenceSnapshot,
) search.types.CompletedIteration {
    return .{
        .depth = depth,
        .selective_depth = depth,
        .nodes = snapshot.total_effort,
        .evidence = .{
            .value = score.Score.zero,
            .bound = .exact,
            .provenance = .full_search,
        },
        .pv = search.types.PrincipalVariation.init(),
        .root_confidence = snapshot,
    };
}

test "movetime and clock budgets preserve overhead and hard ordering" {
    // Time safety: neither policy can spend its explicit reserved overhead.
    try std.testing.expectEqual(Budget{ .optimum_ms = 90, .maximum_ms = 90 }, budget(.{ .movetime_ms = 100 }, 10, 10));
    try std.testing.expectEqual(Budget{ .optimum_ms = 0, .maximum_ms = 0 }, budget(.{ .movetime_ms = 5 }, 10, 10));
    const clock = budget(.{ .clock = .{ .remaining_ms = 1010, .increment_ms = 32, .moves_to_go = 10 } }, 10, 10);
    const expected_clock: Budget = if (search_build_options.integrated_time)
        .{ .optimum_ms = 117, .maximum_ms = 502 }
    else
        .{ .optimum_ms = 118, .maximum_ms = 472 };
    try std.testing.expectEqual(expected_clock, clock);
    try std.testing.expect(clock.maximum_ms <= 990);
}

test "time parameter registry is complete bounded and default exact" {
    const values: Params = .{};
    inline for (param_specs) |spec| {
        try std.testing.expectEqual(spec.default, values.get(spec.id));
        try std.testing.expect(spec.min < spec.default and spec.default < spec.max);
        try std.testing.expectEqual(spec, findParam(spec.name).?);
        var changed = values;
        changed.set(spec.id, spec.max + 1);
        try std.testing.expectEqual(spec.max, changed.get(spec.id));
    }
    try std.testing.expectEqual(budget(.{ .clock = .{
        .remaining_ms = 10_000,
        .increment_ms = 100,
        .game_ply = 80,
    } }, 20, 20), budgetWithParams(.{ .clock = .{
        .remaining_ms = 10_000,
        .increment_ms = 100,
        .game_ply = 80,
    } }, 20, 20, values));
}

test "integrated-time policy is the sole rounded MAN-T04 bake" {
    // SCORE-030: the compile-time candidate owns the completed SPSA theta;
    // disabling it reconstructs the exact untuned policy for the game gate.
    const expected: Params = if (search_build_options.integrated_time)
        .{
            .horizon_scale = 1034,
            .increment_credit = 957,
            .maximum_ratio = 4291,
            .stability_response = 1036,
            .score_response = 1049,
            .effort_response = 1046,
        }
    else
        .{};
    try std.testing.expectEqual(expected, Params{});
}

test "allocation parameters affect only their declared continuous surface" {
    const input: Input = .{ .clock = .{
        .remaining_ms = 10_000,
        .increment_ms = 100,
        .game_ply = 0,
    } };
    const baseline = budget(input, 20, 20);
    const longer_horizon = budgetWithParams(input, 20, 20, .{ .horizon_scale = 1300 });
    const more_increment = budgetWithParams(input, 20, 20, .{ .increment_credit = 1500 });
    const lower_maximum = budgetWithParams(input, 20, 20, .{ .maximum_ratio = 2000 });
    try std.testing.expect(longer_horizon.optimum_ms < baseline.optimum_ms);
    try std.testing.expect(more_increment.optimum_ms > baseline.optimum_ms);
    try std.testing.expectEqual(baseline.optimum_ms, lower_maximum.optimum_ms);
    try std.testing.expect(lower_maximum.maximum_ms < baseline.maximum_ms);

    const explicit: Input = .{ .clock = .{
        .remaining_ms = 10_000,
        .increment_ms = 100,
        .moves_to_go = 10,
    } };
    try std.testing.expectEqual(
        budget(explicit, 20, 20),
        budgetWithParams(explicit, 20, 20, .{ .horizon_scale = 1300 }),
    );
}

test "sudden-death horizon responds to game progress without spending reserves" {
    // Step 6.3.1: later game phases may invest more per move, while the hard
    // cap remains inside the same spendable clock at every phase.
    const early = budget(.{ .clock = .{ .remaining_ms = 10_000, .increment_ms = 100, .game_ply = 0 } }, 20, 20);
    const late = budget(.{ .clock = .{ .remaining_ms = 10_000, .increment_ms = 100, .game_ply = 160 } }, 20, 20);
    try std.testing.expect(late.optimum_ms > early.optimum_ms);
    try std.testing.expect(early.optimum_ms <= early.maximum_ms);
    try std.testing.expect(late.optimum_ms <= late.maximum_ms);
    try std.testing.expect(early.maximum_ms <= 9960);
    try std.testing.expect(late.maximum_ms <= 9960);
}

test "receipt deadlines saturate instead of wrapping" {
    // RES-009/UCI-004: hostile u64 clocks cannot move a deadline backwards.
    try std.testing.expectEqual(std.math.maxInt(u64), deadline(std.math.maxInt(u64) - 2, 1));
}

test "fake clock distinguishes completed soft stop and polled hard stop" {
    var cancel = std.atomic.Value(u64).init(0);
    var fake: FakeClock = .{};
    const FakeControl = Control(FakeClock, false, false);
    var control = FakeControl{
        .clock = &fake,
        .cancel_epoch = &cancel,
        .epoch = 7,
        .soft_deadline_ns = 100,
        .hard_deadline_ns = 200,
    };
    try std.testing.expect(!control.shouldStop());
    fake.now_ns = 100;
    try std.testing.expect(control.shouldStopAfterIteration(completedIteration(4, .{}), .{}));
    try std.testing.expectEqual(search.types.Termination.time_limit, control.terminationReason());

    control.reason = .stopped;
    control.poll_countdown = 0;
    fake.now_ns = 200;
    try std.testing.expect(control.shouldStop());
    try std.testing.expectEqual(search.types.Termination.time_limit, control.terminationReason());
}

test "root uncertainty requires agreement and never exceeds hard deadline" {
    // SCORE-028: one isolated fact preserves the Phase-4 soft stop; agreement
    // spends only the pre-existing soft-to-hard safety interval.
    const soft: u64 = 100;
    const hard: u64 = 200;
    try std.testing.expectEqual(soft, confidenceDeadline(soft, hard, .{}));
    try std.testing.expectEqual(soft, confidenceDeadline(soft, hard, .{
        .completed_iterations = 2,
        .stable_best_iterations = 1,
    }));
    try std.testing.expectEqual(@as(u64, 150), confidenceDeadline(soft, hard, .{
        .completed_iterations = 2,
        .stable_best_iterations = 1,
        .best_score_delta = -1,
        .best_effort = 4,
        .total_effort = 10,
    }));
    try std.testing.expectEqual(hard, confidenceDeadline(soft, hard, .{
        .completed_iterations = 2,
        .stable_best_iterations = 1,
        .best_score_delta = -1,
        .best_effort = 6,
        .total_effort = 10,
    }));
    try std.testing.expectEqual(soft, confidenceDeadline(soft, soft, .{
        .completed_iterations = 2,
        .stable_best_iterations = 1,
        .best_score_delta = -1,
        .best_effort = 6,
        .total_effort = 10,
    }));
}

test "candidate soft stop consumes only completed root confidence" {
    // SCORE-028: two exact completed-iteration uncertainty signs delay the
    // soft stop to the interval midpoint without moving its hard boundary.
    var cancel = std.atomic.Value(u64).init(0);
    var fake: FakeClock = .{ .now_ns = 100 };
    const CandidateControl = Control(FakeClock, true, false);
    var control = CandidateControl{
        .clock = &fake,
        .cancel_epoch = &cancel,
        .epoch = 7,
        .soft_deadline_ns = 100,
        .hard_deadline_ns = 200,
    };
    const uncertain: search.types.RootConfidenceSnapshot = .{
        .completed_iterations = 2,
        .stable_best_iterations = 1,
        .best_score_delta = -1,
    };
    const completed = completedIteration(4, uncertain);
    try std.testing.expect(!control.shouldStopAfterIteration(completed, .{}));
    fake.now_ns = 149;
    try std.testing.expect(!control.shouldStopAfterIteration(completed, .{}));
    fake.now_ns = 150;
    try std.testing.expect(control.shouldStopAfterIteration(completed, .{}));
    try std.testing.expectEqual(search.types.Termination.time_limit, control.terminationReason());
}

test "default build ignores identical root confidence" {
    // Feature-off equivalence: candidate evidence cannot delay production's
    // accepted completed-iteration stop.
    var cancel = std.atomic.Value(u64).init(0);
    var fake: FakeClock = .{ .now_ns = 100 };
    const ProductionControl = Control(FakeClock, false, false);
    var control = ProductionControl{
        .clock = &fake,
        .cancel_epoch = &cancel,
        .epoch = 7,
        .soft_deadline_ns = 100,
        .hard_deadline_ns = 200,
    };
    try std.testing.expect(control.shouldStopAfterIteration(completedIteration(4, .{
        .root_move_count = 2,
        .completed_iterations = 2,
        .stable_best_iterations = 1,
        .best_score_delta = -1,
        .best_effort = 6,
        .total_effort = 10,
    }), .{}));
}

test "epoch cancellation cannot leak into another search" {
    var cancel = std.atomic.Value(u64).init(4);
    var fake: FakeClock = .{};
    const FakeControl = Control(FakeClock, false, false);
    var stale = FakeControl{
        .clock = &fake,
        .cancel_epoch = &cancel,
        .epoch = 5,
        .soft_deadline_ns = null,
        .hard_deadline_ns = null,
    };
    try std.testing.expect(!stale.shouldStop());
    cancel.store(5, .release);
    try std.testing.expect(stale.shouldStop());
}

test "ponder clock activates only for the matching hit epoch and keeps spent time" {
    // UCI-004/005: ponder may search past an expired deadline, but ponderhit
    // activates the original receipt-derived deadline without resetting it.
    var cancel = std.atomic.Value(u64).init(0);
    var hit = std.atomic.Value(u64).init(6);
    var hit_received = std.atomic.Value(u64).init(250);
    var fake: FakeClock = .{ .now_ns = 250 };
    const FakeControl = Control(FakeClock, false, false);
    var control = FakeControl{
        .clock = &fake,
        .cancel_epoch = &cancel,
        .ponderhit_epoch = &hit,
        .ponderhit_received_ns = &hit_received,
        .epoch = 7,
        .pondering = true,
        .received_ns = 25,
        .soft_deadline_ns = 100,
        .hard_deadline_ns = 200,
    };
    try std.testing.expect(!control.shouldStop());
    try std.testing.expect(!control.shouldStopAfterIteration(completedIteration(4, .{}), .{}));
    try std.testing.expectEqual(@as(?u64, null), control.ponderCreditNs());
    hit.store(7, .release);
    try std.testing.expect(control.shouldStop());
    try std.testing.expectEqual(@as(?u64, 225), control.ponderCreditNs());
    try std.testing.expectEqual(search.types.Termination.time_limit, control.terminationReason());
}

test "ponder credit is latched once and saturates a reversed timestamp" {
    // Step 6.0.4: only the matching transition produces credit, and later
    // timestamp mutation cannot double-count or rewrite that observation.
    var cancel = std.atomic.Value(u64).init(0);
    var hit = std.atomic.Value(u64).init(9);
    var hit_received = std.atomic.Value(u64).init(80);
    var fake: FakeClock = .{};
    const FakeControl = Control(FakeClock, false, false);
    var control = FakeControl{
        .clock = &fake,
        .cancel_epoch = &cancel,
        .ponderhit_epoch = &hit,
        .ponderhit_received_ns = &hit_received,
        .epoch = 9,
        .pondering = true,
        .received_ns = 100,
        .soft_deadline_ns = null,
        .hard_deadline_ns = null,
    };
    try std.testing.expect(!control.shouldStop());
    try std.testing.expectEqual(@as(?u64, 0), control.ponderCreditNs());
    hit_received.store(500, .monotonic);
    try std.testing.expect(!control.shouldStop());
    try std.testing.expectEqual(@as(?u64, 0), control.ponderCreditNs());
}

test "hard-clock reads are amortized at the frozen node interval" {
    const CountingClock = struct {
        calls: u32 = 0,
        pub fn nowNs(self: *@This()) u64 {
            self.calls += 1;
            return 0;
        }
    };
    var cancel = std.atomic.Value(u64).init(0);
    var clock: CountingClock = .{};
    const CountingControl = Control(CountingClock, false, false);
    var control = CountingControl{
        .clock = &clock,
        .cancel_epoch = &cancel,
        .epoch = 1,
        .soft_deadline_ns = null,
        .hard_deadline_ns = std.math.maxInt(u64),
    };
    for (0..poll_interval_nodes) |_| try std.testing.expect(!control.shouldStop());
    try std.testing.expectEqual(@as(u32, 1), clock.calls);
    try std.testing.expect(!control.shouldStop());
    try std.testing.expectEqual(@as(u32, 2), clock.calls);
}

test "budget table keeps every hard limit within spendable clock" {
    const cases = [_]struct { remaining: u64, increment: u64, overhead: u64, moves: ?u64 }{
        .{ .remaining = 0, .increment = 0, .overhead = 10, .moves = null },
        .{ .remaining = 9, .increment = 500, .overhead = 10, .moves = null },
        .{ .remaining = 10, .increment = 0, .overhead = 10, .moves = 1 },
        .{ .remaining = 11, .increment = 0, .overhead = 10, .moves = 1 },
        .{ .remaining = 60_000, .increment = 1000, .overhead = 25, .moves = null },
        .{ .remaining = std.math.maxInt(u64), .increment = std.math.maxInt(u64), .overhead = 5000, .moves = 1 },
    };
    for (cases) |case| {
        const result = budget(.{ .clock = .{
            .remaining_ms = case.remaining,
            .increment_ms = case.increment,
            .moves_to_go = case.moves,
        } }, case.overhead, case.overhead);
        const spendable = case.remaining -| case.overhead -| case.overhead;
        try std.testing.expect(result.optimum_ms <= result.maximum_ms);
        try std.testing.expect(result.maximum_ms <= spendable);
    }
}

test "ordinary clocks reserve scheduling latency independently of movetime" {
    // A GUI clock includes post-search publication latency; fixed movetime has
    // no game clock to forfeit and preserves the accepted Phase-4 behavior.
    try std.testing.expectEqual(
        Budget{ .optimum_ms = 90, .maximum_ms = 90 },
        budget(.{ .movetime_ms = 100 }, 10, 40),
    );
    try std.testing.expectEqual(
        Budget{ .optimum_ms = 20, .maximum_ms = 50 },
        budget(.{ .clock = .{ .remaining_ms = 100, .moves_to_go = 2 } }, 10, 40),
    );
}

test "integrated factors distinguish easy uncertain forced and decisive roots" {
    // Chess-policy oracle: stable concentrated ordinary evidence is easier
    // than neutral, while a changed/falling/dispersed root deserves more time.
    const easy = completedIteration(8, .{
        .root_move_count = 12,
        .completed_iterations = 5,
        .stable_best_iterations = 4,
        .best_score_delta = 12,
        .best_effort = 80,
        .total_effort = 100,
    });
    const uncertain = completedIteration(8, .{
        .root_move_count = 12,
        .completed_iterations = 5,
        .stable_best_iterations = 1,
        .best_score_delta = -score.units_per_pawn,
        .best_effort = 20,
        .total_effort = 100,
    });
    try std.testing.expect(dynamicFactorPermille(easy, 12, .{}) < permille);
    try std.testing.expect(dynamicFactorPermille(uncertain, 12, .{
        .helper_instability_events = 3,
        .helper_count = 3,
    }) > permille);
    try std.testing.expectEqual(minimum_dynamic_factor, dynamicFactorPermille(easy, 1, .{}));

    var decisive = uncertain;
    decisive.evidence.value = score.Score.mateIn(3).?;
    try std.testing.expectEqual(permille, dynamicFactorPermille(decisive, 12, .{}));
}

test "response parameters jointly scale independent completed-root evidence" {
    const uncertain = completedIteration(8, .{
        .root_move_count = 12,
        .completed_iterations = 5,
        .stable_best_iterations = 1,
        .best_score_delta = -score.units_per_pawn,
        .best_effort = 20,
        .total_effort = 100,
    });
    const neutralized = dynamicFactorsWithParams(uncertain, 12, .{}, .{
        .stability_response = 0,
        .score_response = 0,
        .effort_response = 0,
    });
    try std.testing.expectEqual(permille, neutralized.stability_permille);
    try std.testing.expectEqual(permille, neutralized.score_permille);
    try std.testing.expectEqual(permille, neutralized.effort_permille);
    try std.testing.expectEqual(permille, neutralized.combined_permille);

    const amplified = dynamicFactorsWithParams(uncertain, 12, .{}, .{
        .stability_response = 2000,
        .score_response = 2000,
        .effort_response = 2000,
    });
    try std.testing.expect(amplified.combined_permille > dynamicFactorPermille(uncertain, 12, .{}));
    try std.testing.expect(amplified.combined_permille <= maximum_dynamic_factor);
}

test "helper instability is normalized and cannot multiply wall time" {
    const changed = completedIteration(8, .{
        .root_move_count = 8,
        .completed_iterations = 3,
        .stable_best_iterations = 1,
        .best_effort = 50,
        .total_effort = 100,
    });
    const four_workers = dynamicFactorPermille(changed, 8, .{
        .helper_instability_events = 3,
        .helper_count = 3,
    });
    const many_events = dynamicFactorPermille(changed, 8, .{
        .helper_instability_events = 300,
        .helper_count = 3,
    });
    try std.testing.expectEqual(four_workers, many_events);
    try std.testing.expect(four_workers <= maximum_dynamic_factor);
    try std.testing.expect(rootInstability(changed));
}

test "integrated deadline preserves minimum depth ponder accounting and hard cap" {
    const allocation = Budget{ .optimum_ms = 100, .maximum_ms = 300 };
    const easy = completedIteration(8, .{
        .root_move_count = 4,
        .completed_iterations = 4,
        .stable_best_iterations = 4,
        .best_effort = 80,
        .total_effort = 100,
    });
    const shallow = completedIteration(3, easy.root_confidence);
    const hard = deadline(50, allocation.maximum_ms);
    try std.testing.expectEqual(hard, integratedDeadline(50, allocation, shallow, 4, .{}, null));
    const without_ponder = integratedDeadline(50, allocation, easy, 4, .{}, null);
    const with_ponder = integratedDeadline(50, allocation, easy, 4, .{}, 40 * std.time.ns_per_ms);
    try std.testing.expect(with_ponder >= without_ponder);
    try std.testing.expect(with_ponder <= hard);

    const uncertain = completedIteration(8, .{
        .root_move_count = 4,
        .completed_iterations = 4,
        .stable_best_iterations = 1,
        .best_score_delta = -score.units_per_pawn,
        .best_effort = 20,
        .total_effort = 100,
    });
    try std.testing.expectEqual(hard, integratedDeadline(50, allocation, uncertain, 4, .{
        .helper_instability_events = 3,
        .helper_count = 3,
    }, std.math.maxInt(u64)));
}

test "integrated telemetry exposes bounded factors and completed stop reason" {
    // SCORE-030: diagnostics report the independent inputs to the decision;
    // they do not infer authority from mate, bounded or partial evidence.
    var cancel = std.atomic.Value(u64).init(0);
    var fake: FakeClock = .{ .now_ns = 50 * std.time.ns_per_ms };
    const CandidateControl = Control(FakeClock, false, true);
    const allocation: Budget = .{ .optimum_ms = 100, .maximum_ms = 220 };
    var control = CandidateControl{
        .clock = &fake,
        .cancel_epoch = &cancel,
        .epoch = 4,
        .initial_budget = allocation,
        .integrated_budget = allocation,
        .legal_root_move_count = 8,
        .soft_deadline_ns = deadline(0, allocation.optimum_ms),
        .hard_deadline_ns = deadline(0, allocation.maximum_ms),
    };
    const uncertain = completedIteration(8, .{
        .root_move_count = 8,
        .completed_iterations = 3,
        .stable_best_iterations = 1,
        .best_score_delta = -score.units_per_pawn,
        .best_effort = 20,
        .total_effort = 100,
    });
    try std.testing.expect(!control.shouldStopAfterIteration(uncertain, .{
        .helper_instability_events = 3,
        .helper_count = 3,
    }));
    control.finish(.depth_limit, .{ .helper_count = 3 });
    const snapshot = control.telemetry().?;
    const expected_stability: u64 = if (search_build_options.integrated_time) 1310 else 1300;
    const expected_score: u64 = if (search_build_options.integrated_time) 1419 else 1400;
    const expected_effort: u64 = if (search_build_options.integrated_time) 1156 else 1150;
    try std.testing.expectEqual(expected_stability, snapshot.factors.stability_permille);
    try std.testing.expectEqual(expected_score, snapshot.factors.score_permille);
    try std.testing.expectEqual(expected_effort, snapshot.factors.effort_permille);
    try std.testing.expectEqual(@as(u64, 1200), snapshot.factors.smp_permille);
    try std.testing.expectEqual(@as(u16, 3), snapshot.helper_count);
    try std.testing.expectEqual(StopReason.search_complete, snapshot.stop_reason);
    try std.testing.expect(snapshot.target_ns <= allocation.maximum_ms * std.time.ns_per_ms);
}

test "hard-stop telemetry measures overshoot without moving the deadline" {
    // A delayed poll may observe a late clock, but reports exact lateness
    // against the immutable receipt-derived maximum.
    var cancel = std.atomic.Value(u64).init(0);
    var fake: FakeClock = .{ .now_ns = 225 * std.time.ns_per_ms };
    const CandidateControl = Control(FakeClock, false, true);
    const allocation: Budget = .{ .optimum_ms = 100, .maximum_ms = 200 };
    var control = CandidateControl{
        .clock = &fake,
        .cancel_epoch = &cancel,
        .epoch = 9,
        .initial_budget = allocation,
        .integrated_budget = allocation,
        .soft_deadline_ns = deadline(0, allocation.optimum_ms),
        .hard_deadline_ns = deadline(0, allocation.maximum_ms),
    };
    try std.testing.expect(control.shouldStop());
    const snapshot = control.telemetry().?;
    try std.testing.expectEqual(StopReason.hard_deadline, snapshot.stop_reason);
    try std.testing.expectEqual(25 * std.time.ns_per_ms, snapshot.hard_overshoot_ns);
    try std.testing.expectEqual(allocation, snapshot.allocation);
}

test "ponder polling does not write telemetry in the node path" {
    // Until the matching hit, clock polling is inactive and must remain a
    // read-only epoch check rather than a per-node diagnostic producer.
    var cancel = std.atomic.Value(u64).init(0);
    var hit = std.atomic.Value(u64).init(0);
    var fake: FakeClock = .{};
    const CandidateControl = Control(FakeClock, false, true);
    const allocation: Budget = .{ .optimum_ms = 100, .maximum_ms = 200 };
    var control = CandidateControl{
        .clock = &fake,
        .cancel_epoch = &cancel,
        .ponderhit_epoch = &hit,
        .epoch = 9,
        .pondering = true,
        .initial_budget = allocation,
        .integrated_budget = allocation,
        .soft_deadline_ns = deadline(0, allocation.optimum_ms),
        .hard_deadline_ns = deadline(0, allocation.maximum_ms),
    };
    try std.testing.expect(!control.shouldStop());
    try std.testing.expect(control.telemetry_state == null);
}

test "helper multiplier is normalized at qualified worker counts" {
    // One event per helper has the same bounded meaning at 2T, 4T and 8T;
    // more workers cannot multiply the time response.
    const changed = completedIteration(8, .{
        .root_move_count = 8,
        .completed_iterations = 3,
        .stable_best_iterations = 1,
        .best_effort = 50,
        .total_effort = 100,
    });
    const two = dynamicFactors(changed, 8, .{
        .helper_instability_events = 1,
        .helper_count = 1,
    });
    const four = dynamicFactors(changed, 8, .{
        .helper_instability_events = 3,
        .helper_count = 3,
    });
    const eight = dynamicFactors(changed, 8, .{
        .helper_instability_events = 7,
        .helper_count = 7,
    });
    try std.testing.expectEqual(@as(u64, 1200), two.smp_permille);
    try std.testing.expectEqual(two.smp_permille, four.smp_permille);
    try std.testing.expectEqual(two.smp_permille, eight.smp_permille);
}
