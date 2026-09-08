//! Controller-owned search workers, immutable jobs, and joined lifecycle.
const std = @import("std");
const search_build_options = @import("search_build_options");
const chess = @import("../chess/root.zig");
const eval = @import("../eval/root.zig");
const search = @import("../search/root.zig");
const bench = @import("bench.zig");
const options = @import("options.zig");
const syzygy = @import("syzygy.zig");
const time = @import("time.zig");

pub const worker_stack_bytes = 4 * 1024 * 1024;
pub const default_hash_mb: u64 = options.get(.hash).kind.spin.default;
pub const default_threads: u16 = @intCast(options.get(.threads).kind.spin.default);
pub const default_move_overhead_ms: u64 = options.get(.move_overhead).kind.spin.default;
pub const default_syzygy_probe_depth: u16 = options.get(.syzygy_probe_depth).kind.spin.default;
pub const max_syzygy_probe_depth: u16 = options.get(.syzygy_probe_depth).kind.spin.max;

pub const GameState = struct {
    position: chess.position.Position,
    states: []chess.position.PositionState,
    moves: []chess.move.Move,

    pub fn initial(allocator: std.mem.Allocator) !GameState {
        const states = try allocator.alloc(chess.position.PositionState, 1);
        errdefer allocator.free(states);
        const moves = try allocator.alloc(chess.move.Move, 0);
        errdefer allocator.free(moves);
        return .{
            .position = try chess.fen.parse(chess.fen.start_position, &states[0]),
            .states = states,
            .moves = moves,
        };
    }

    pub fn deinit(self: *GameState, allocator: std.mem.Allocator) void {
        allocator.free(self.states);
        allocator.free(self.moves);
        self.* = undefined;
    }
};

pub const HashResource = struct {
    storage: []search.tt.Cluster,
    table: search.tt.Table,

    pub fn init(allocator: std.mem.Allocator, megabytes: u64) !HashResource {
        const bytes = try std.math.mul(u64, megabytes, 1024 * 1024);
        const cluster_count_u64 = @max(bytes / @sizeOf(search.tt.Cluster), 1);
        if (cluster_count_u64 > std.math.maxInt(usize)) return error.OutOfMemory;
        const storage = try allocator.alloc(search.tt.Cluster, @intCast(cluster_count_u64));
        return .{ .storage = storage, .table = search.tt.Table.init(storage) };
    }

    pub fn deinit(self: *HashResource, allocator: std.mem.Allocator) void {
        allocator.free(self.storage);
        self.* = undefined;
    }
};

pub const SearchSpec = struct {
    limits: search.types.Limits,
    root_moves: chess.position.MoveList,
    legal_root_move_count: u16 = 0,
    restricted: bool,
    time_input: ?time.Input,
    received_ns: u64,
    ponder: bool = false,
};
pub const SearchResult = search.types.Result;

pub const SearchProgress = union(enum) {
    root_move: struct {
        depth: u16,
        chess_move: chess.move.Move,
        number: u16,
        nodes: u64,
        observed_ns: u64,
    },
    iteration: struct {
        completed: search.types.CompletedIteration,
        tablebase_hits: u64,
        observed_ns: u64,
    },
};

/// One bounded coalescible worker-to-controller information slot. Search
/// completion has its separate non-droppable event and is never stored here.
pub const ProgressSlot = struct {
    mutex: std.Io.Mutex = .init,
    value: ?SearchProgress = null,

    pub fn offer(self: *ProgressSlot, io: std.Io, progress: SearchProgress) bool {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const needs_wake = self.value == null;
        self.value = progress;
        return needs_wake;
    }

    pub fn take(self: *ProgressSlot, io: std.Io) ?SearchProgress {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const value = self.value;
        self.value = null;
        return value;
    }
};

pub const Job = union(enum) {
    normal: SearchSpec,
    perft: u16,
    bench: bench.Spec,
};

pub const Completion = union(enum) {
    normal: search.types.Result,
    perft: chess.perft.Divide,
    perft_failed,
    bench: bench.Report,
};

pub const Finished = struct {
    job: Job,
    completion: Completion,
    time_telemetry: ?time.Telemetry,
};

pub const WorkerState = struct {
    search: search.types.ThreadState = search.types.ThreadState.init(),
    // SAFETY: perft initializes a state slot before each transition reads it;
    // ordinary search never accesses this array.
    perft_states: [chess.types.max_ply]chess.position.PositionState = undefined,
};

const Helper = struct {
    index: usize,
    worker: WorkerState = .{},
    heuristics: search.ordering.State = .{},
    wake: std.Io.Semaphore = .{},
    shutdown: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
};

pub const Active = struct {
    epoch: u64,
    io: std.Io,
    cancel_epoch: *const std.atomic.Value(u64),
    ponderhit_epoch: *const std.atomic.Value(u64),
    ponderhit_received_ns: *const std.atomic.Value(u64),
    table: *search.tt.Table,
    bench_storage: ?[]search.tt.Cluster = null,
    bench_table: ?search.tt.Table = null,
    heuristics: *search.ordering.State,
    /// Borrowed for the lifetime of this search. Replacement is confined to
    /// the no-active-search path, so probing needs no synchronization.
    tablebase: *syzygy.Handle,
    move_overhead_ms: u64,
    search_params: search.params.Values,
    time_params: time.Params,
    job: Job,
    position: chess.position.Position,
    root_states: []chess.position.PositionState,
    worker: *WorkerState,
    helper_positions: []chess.position.Position,
    helper_root_states: []chess.position.PositionState,
    helper_count: usize,
    helper_stop: std.atomic.Value(bool) = .init(false),
    /// Helpers publish only a bounded count of completed ordinary root
    /// instability events. No move, score, PV or result crosses this boundary.
    helper_instability_events: std.atomic.Value(u64) = .init(0),
    remaining_workers: std.atomic.Value(usize),
    aggregate_nodes: std.atomic.Value(u64) = .init(0),
    controller_wake: *std.Io.Semaphore,
    progress: ProgressSlot = .{},
    last_published_iteration_nodes: ?u64 = null,
    ponder_completion_waiting: bool = false,
    /// Controller-owned storage keeps this event alive until every persistent
    /// worker has returned from its completion signal.
    done: *std.Io.Event,
    completion: Completion = .perft_failed,
    /// Final worker-zero timing snapshot; absent in production/default builds.
    time_telemetry: ?time.Telemetry = null,
};

pub const Controller = struct {
    allocator: std.mem.Allocator,
    game: GameState,
    hash: HashResource,
    ordering: search.ordering.State = .{},
    worker: *WorkerState,
    helpers: []Helper,
    /// Tablebase handle. It follows the same resource-generation rule as the
    /// transposition table: replaced only while no search is active, because
    /// Fathom's initialization is not thread safe.
    tablebase: syzygy.Handle = .{},
    hash_mb: u64 = default_hash_mb,
    threads: u16 = default_threads,
    move_overhead_ms: u64 = default_move_overhead_ms,
    ponder_enabled: bool = options.get(.ponder).kind.check,
    search_params: search.params.Values = .{},
    time_params: time.Params = .{},
    syzygy_probe_depth: u16 = default_syzygy_probe_depth,
    syzygy_probe_limit: u8 = search.tablebase.max_probe_limit,
    syzygy_fifty_move_rule: bool = true,
    next_epoch: u64 = 1,
    fail_next_hash_allocation: bool = false,
    fail_next_thread_allocation: bool = false,
    active: ?Active = null,
    /// Stable across active-search replacement. A completion event embedded in
    /// `Active` can be freed by the waiting controller while the last worker is
    /// still returning from `Event.set`.
    completion_done: std.Io.Event = .unset,
    worker_io: ?std.Io = null,
    worker_wake: std.Io.Semaphore = .{},
    worker_shutdown: std.atomic.Value(bool) = .init(false),
    worker_thread: ?std.Thread = null,

    pub fn init(allocator: std.mem.Allocator) !Controller {
        var game = try GameState.initial(allocator);
        errdefer game.deinit(allocator);
        const worker = try allocator.create(WorkerState);
        errdefer allocator.destroy(worker);
        worker.* = .{};
        const helpers = try allocator.alloc(Helper, 0);
        errdefer allocator.free(helpers);
        return .{
            .allocator = allocator,
            .game = game,
            .hash = try HashResource.init(allocator, default_hash_mb),
            .worker = worker,
            .helpers = helpers,
        };
    }

    pub fn deinit(self: *Controller) void {
        std.debug.assert(self.active == null);
        self.stopWorker();
        self.game.deinit(self.allocator);
        self.hash.deinit(self.allocator);
        self.tablebase.deinit();
        self.allocator.destroy(self.worker);
        self.allocator.free(self.helpers);
    }

    pub fn startWorker(self: *Controller, io: std.Io) !void {
        std.debug.assert(self.worker_thread == null);
        self.worker_io = io;
        self.worker_shutdown.store(false, .release);
        self.worker_thread = std.Thread.spawn(
            .{ .stack_size = worker_stack_bytes },
            workerLoop,
            .{self},
        ) catch |err| {
            self.worker_io = null;
            return err;
        };
    }

    fn stopWorker(self: *Controller) void {
        self.stopHelpers(self.helpers);
        const thread = self.worker_thread orelse return;
        const io = self.worker_io.?;
        self.worker_shutdown.store(true, .release);
        self.worker_wake.post(io);
        thread.join();
        self.worker_thread = null;
        self.worker_io = null;
    }

    pub fn resizeThreads(self: *Controller, count: u16) !void {
        std.debug.assert(self.active == null);
        std.debug.assert(self.worker_io != null);
        std.debug.assert(count >= 1);
        if (count == self.threads) return;
        if (self.fail_next_thread_allocation) {
            self.fail_next_thread_allocation = false;
            return error.OutOfMemory;
        }

        const helper_count: usize = @as(usize, count) - 1;
        const replacement = try self.allocator.alloc(Helper, helper_count);
        var initialized: usize = 0;
        errdefer {
            self.stopHelpers(replacement[0..initialized]);
            self.allocator.free(replacement);
        }
        for (replacement, 0..) |*helper, index| {
            helper.* = .{ .index = index };
            helper.thread = try std.Thread.spawn(
                .{ .stack_size = worker_stack_bytes },
                helperLoop,
                .{ self, helper },
            );
            initialized += 1;
        }

        const previous = self.helpers;
        self.helpers = replacement;
        self.threads = count;
        self.stopHelpers(previous);
        self.allocator.free(previous);
    }

    pub fn clearSearchState(self: *Controller) void {
        self.ordering.clear();
        for (self.helpers) |*helper| helper.heuristics.clear();
    }

    fn stopHelpers(self: *Controller, helpers: []Helper) void {
        const io = self.worker_io orelse return;
        for (helpers) |*helper| {
            helper.shutdown.store(true, .release);
            helper.wake.post(io);
        }
        for (helpers) |*helper| {
            if (helper.thread) |thread| thread.join();
            helper.thread = null;
        }
    }
};

pub fn start(
    controller: *Controller,
    io: std.Io,
    cancel_epoch: *const std.atomic.Value(u64),
    ponderhit_epoch: *const std.atomic.Value(u64),
    ponderhit_received_ns: *const std.atomic.Value(u64),
    controller_wake: *std.Io.Semaphore,
    job: Job,
) !u64 {
    std.debug.assert(controller.active == null);
    std.debug.assert(controller.worker_thread != null);
    controller.completion_done.reset();
    const context = repetitionContext(&controller.game);
    const states = try controller.allocator.alloc(chess.position.PositionState, context.len);
    errdefer controller.allocator.free(states);
    const helper_count = switch (job) {
        .normal => controller.helpers.len,
        .perft, .bench => 0,
    };
    const helper_positions = try controller.allocator.alloc(chess.position.Position, helper_count);
    errdefer controller.allocator.free(helper_positions);
    const helper_state_count = try std.math.mul(usize, context.len, helper_count);
    const helper_states = try controller.allocator.alloc(chess.position.PositionState, helper_state_count);
    errdefer controller.allocator.free(helper_states);
    const bench_storage = switch (job) {
        .bench => try controller.allocator.alloc(
            search.tt.Cluster,
            bench.hash_bytes / @sizeOf(search.tt.Cluster),
        ),
        .normal, .perft => null,
    };
    errdefer if (bench_storage) |storage| controller.allocator.free(storage);
    @memcpy(states, context);
    for (states, 0..) |*item, index| item.previous = if (index == 0) null else &states[index - 1];
    var position = controller.game.position;
    position.current = &states[states.len - 1];
    for (helper_positions, 0..) |*helper_position, index| {
        const helper_context = helper_states[index * context.len ..][0..context.len];
        @memcpy(helper_context, context);
        for (helper_context, 0..) |*item, state_index|
            item.previous = if (state_index == 0) null else &helper_context[state_index - 1];
        helper_position.* = controller.game.position;
        helper_position.current = &helper_context[helper_context.len - 1];
    }
    const epoch = controller.next_epoch;
    controller.next_epoch +%= 1;
    if (controller.next_epoch == 0) controller.next_epoch = 1;
    controller.active = .{
        .epoch = epoch,
        .io = io,
        .cancel_epoch = cancel_epoch,
        .ponderhit_epoch = ponderhit_epoch,
        .ponderhit_received_ns = ponderhit_received_ns,
        .table = &controller.hash.table,
        .bench_storage = bench_storage,
        .heuristics = &controller.ordering,
        .tablebase = &controller.tablebase,
        .move_overhead_ms = controller.move_overhead_ms,
        .search_params = controller.search_params,
        .time_params = controller.time_params,
        .job = job,
        .position = position,
        .root_states = states,
        .worker = controller.worker,
        .helper_positions = helper_positions,
        .helper_root_states = helper_states,
        .helper_count = helper_count,
        .remaining_workers = .init(helper_count + 1),
        .controller_wake = controller_wake,
        .done = &controller.completion_done,
    };
    if (bench_storage) |storage| {
        controller.active.?.bench_table = search.tt.Table.init(storage);
        controller.active.?.table = &controller.active.?.bench_table.?;
    }
    // The configured probe floor is a controller-owned resource setting, so it
    // is applied here rather than by the pure `go` parser, which has no access
    // to controller state. Bench keeps its own frozen limits untouched.
    if (controller.active.?.job == .normal) {
        controller.active.?.job.normal.limits.tablebase_probe_depth = controller.syzygy_probe_depth;
        controller.active.?.job.normal.limits.tablebase_probe_limit = controller.syzygy_probe_limit;
        controller.active.?.job.normal.limits.tablebase_use_rule_fifty = controller.syzygy_fifty_move_rule;
        if (helper_count != 0) controller.active.?.table.nextGeneration();
    }
    for (controller.helpers[0..helper_count]) |*helper| helper.wake.post(io);
    controller.worker_wake.post(io);
    return epoch;
}

pub fn cancel(controller: *const Controller, cancel_epoch: *std.atomic.Value(u64)) void {
    if (controller.active) |active| cancel_epoch.store(active.epoch, .release);
}

pub fn finish(controller: *Controller, io: std.Io) Finished {
    const active = &controller.active.?;
    if (!active.done.isSet()) active.done.waitUncancelable(io);
    if (active.job == .normal and active.helper_count != 0) {
        var nodes = active.worker.search.nodes;
        var tablebase_hits = active.worker.search.tablebase_hits;
        var selective_depth = active.worker.search.selective_depth;
        for (controller.helpers[0..active.helper_count]) |*helper| {
            nodes +|= helper.worker.search.nodes;
            tablebase_hits +|= helper.worker.search.tablebase_hits;
            selective_depth = @max(selective_depth, helper.worker.search.selective_depth);
        }
        var result = &active.completion.normal;
        result.nodes = nodes;
        result.tablebase_hits = tablebase_hits;
        result.selective_depth = selective_depth;
        if (result.completed) |*completed| {
            completed.nodes = nodes;
            completed.selective_depth = selective_depth;
        }
    }
    const result = Finished{
        .job = active.job,
        .completion = active.completion,
        .time_telemetry = active.time_telemetry,
    };
    controller.allocator.free(active.root_states);
    controller.allocator.free(active.helper_positions);
    controller.allocator.free(active.helper_root_states);
    if (active.bench_storage) |storage| controller.allocator.free(storage);
    controller.active = null;
    return result;
}

fn workerLoop(controller: *Controller) void {
    const io = controller.worker_io.?;
    while (true) {
        controller.worker_wake.waitUncancelable(io);
        if (controller.worker_shutdown.load(.acquire)) return;
        const active = &controller.active.?;
        runJob(active);
        if (active.helper_count != 0) active.helper_stop.store(true, .release);
        workerFinished(active);
    }
}

fn helperLoop(controller: *Controller, helper: *Helper) void {
    const io = controller.worker_io.?;
    while (true) {
        helper.wake.waitUncancelable(io);
        if (helper.shutdown.load(.acquire)) return;
        const active = &controller.active.?;
        runHelper(active, helper);
        workerFinished(active);
    }
}

fn workerFinished(active: *Active) void {
    if (active.remaining_workers.fetchSub(1, .acq_rel) == 1) {
        // `done` may immediately let the controller release `Active`. Copy
        // every stable dependency before signaling and never dereference
        // `active` afterwards.
        const io = active.io;
        const done = active.done;
        const controller_wake = active.controller_wake;
        done.set(io);
        controller_wake.post(io);
    }
}

fn runJob(active: *Active) void {
    switch (active.job) {
        .normal => |spec| {
            const Clock = struct {
                io: std.Io,
                pub fn nowNs(self: *@This()) u64 {
                    return monotonicNs(self.io);
                }
            };
            var clock = Clock{ .io = active.io };
            const maybe_budget = if (spec.time_input) |input_value|
                // Keep Manta's simple Phase-4 allocation, but give ordinary
                // clocks a separate scheduling/publication reserve. Using the
                // configured Move Overhead for both reserves matches the UCI
                // operator's latency choice without adding a hidden constant.
                time.budgetWithParams(
                    input_value,
                    active.move_overhead_ms,
                    active.move_overhead_ms,
                    active.time_params,
                )
            else
                null;
            const integrated_budget = if (spec.time_input) |input_value| switch (input_value) {
                .clock => maybe_budget,
                .movetime_ms => null,
            } else null;
            const timing = time.Control(
                Clock,
                search_build_options.root_confidence_time,
                search_build_options.integrated_time,
            ){
                .clock = &clock,
                .cancel_epoch = active.cancel_epoch,
                .ponderhit_epoch = active.ponderhit_epoch,
                .ponderhit_received_ns = active.ponderhit_received_ns,
                .epoch = active.epoch,
                .pondering = spec.ponder,
                .received_ns = spec.received_ns,
                .initial_budget = maybe_budget,
                .integrated_budget = integrated_budget,
                .params = active.time_params,
                .legal_root_move_count = spec.legal_root_move_count,
                .soft_deadline_ns = if (maybe_budget) |budget_value|
                    time.deadline(spec.received_ns, budget_value.optimum_ms)
                else
                    null,
                .hard_deadline_ns = if (maybe_budget) |budget_value|
                    time.deadline(spec.received_ns, budget_value.maximum_ms)
                else
                    null,
            };
            if (active.helper_count == 0) {
                const Control = SearchControl(
                    Clock,
                    search_build_options.root_confidence_time,
                    search_build_options.integrated_time,
                );
                var control = Control{ .active = active, .timing = timing };
                const result = executeSearch(
                    active,
                    spec,
                    &active.position,
                    active.worker,
                    active.heuristics,
                    &control,
                    null,
                );
                control.timing.finish(result.termination, .{});
                active.time_telemetry = control.timing.telemetry();
                active.completion = .{ .normal = result };
            } else {
                const Control = SmpMainControl(
                    Clock,
                    search_build_options.root_confidence_time,
                    search_build_options.integrated_time,
                );
                var control = Control{
                    .main = .{ .active = active, .timing = timing },
                    .node_limit = spec.limits.nodes,
                };
                const result = executeSearch(
                    active,
                    spec,
                    &active.position,
                    active.worker,
                    active.heuristics,
                    &control,
                    .{ .advance_table_generation = false },
                );
                const final_smp: time.SmpEvidence = if (comptime search_build_options.integrated_time)
                    .{
                        .helper_instability_events = active.helper_instability_events.swap(0, .acq_rel),
                        .helper_count = @intCast(active.helper_count),
                    }
                else
                    .{};
                control.main.timing.finish(result.termination, final_smp);
                active.time_telemetry = control.main.timing.telemetry();
                active.completion = .{ .normal = result };
            }
        },
        .perft => |depth| {
            const Cancel = struct {
                cancel_epoch: *const std.atomic.Value(u64),
                epoch: u64,
                pub fn shouldStop(self: *@This()) bool {
                    return self.cancel_epoch.load(.acquire) == self.epoch;
                }
            };
            var control = Cancel{ .cancel_epoch = active.cancel_epoch, .epoch = active.epoch };
            const result = chess.perft.divideControlled(
                &active.position,
                depth,
                &active.worker.perft_states,
                &control,
            ) catch {
                active.completion = .perft_failed;
                return;
            };
            active.completion = .{ .perft = result };
        },
        .bench => |spec| runBench(active, spec),
    }
}

fn runHelper(active: *Active, helper: *Helper) void {
    const spec = active.job.normal;
    const Clock = struct {
        io: std.Io,
        pub fn nowNs(self: *@This()) u64 {
            return monotonicNs(self.io);
        }
    };
    var clock = Clock{ .io = active.io };
    const maybe_budget = if (spec.time_input) |input_value|
        time.budgetWithParams(
            input_value,
            active.move_overhead_ms,
            active.move_overhead_ms,
            active.time_params,
        )
    else
        null;
    const integrated_budget = if (spec.time_input) |input_value| switch (input_value) {
        .clock => maybe_budget,
        .movetime_ms => null,
    } else null;
    const Control = HelperSearchControl(
        Clock,
        search_build_options.root_confidence_time,
        search_build_options.integrated_time,
    );
    var control = Control{
        .active = active,
        .node_limit = spec.limits.nodes,
        .timing = .{
            .clock = &clock,
            .cancel_epoch = active.cancel_epoch,
            .ponderhit_epoch = active.ponderhit_epoch,
            .ponderhit_received_ns = active.ponderhit_received_ns,
            .epoch = active.epoch,
            .pondering = spec.ponder,
            .received_ns = spec.received_ns,
            .initial_budget = maybe_budget,
            .integrated_budget = integrated_budget,
            .params = active.time_params,
            .legal_root_move_count = spec.legal_root_move_count,
            .soft_deadline_ns = if (maybe_budget) |budget_value|
                time.deadline(spec.received_ns, budget_value.optimum_ms)
            else
                null,
            .hard_deadline_ns = if (maybe_budget) |budget_value|
                time.deadline(spec.received_ns, budget_value.maximum_ms)
            else
                null,
        },
    };
    _ = executeSearch(
        active,
        spec,
        &active.helper_positions[helper.index],
        &helper.worker,
        &helper.heuristics,
        &control,
        .{
            .start_depth = 2 + @as(u16, @intCast(helper.index % 2)),
            .advance_table_generation = false,
        },
    );
}

fn executeSearch(
    active: *Active,
    spec: SearchSpec,
    position: *chess.position.Position,
    worker: *WorkerState,
    heuristics: *search.ordering.State,
    control: anytype,
    execution: ?search.baseline.WorkerExecution,
) search.types.Result {
    var evaluator: eval.hce.Hce = .{};
    var evaluator_state: eval.hce.Hce.State = .{};
    var sink: eval.trace.Disabled = .{};
    const Binding = eval.contract.Binding(eval.hce.Hce, eval.trace.Disabled);
    const binding = Binding{ .evaluator = &evaluator, .state = &evaluator_state, .sink = &sink };
    var observer: search.diagnostics.Disabled = .{};
    const features: search.types.Features = .{
        .correction_history = search_build_options.correction_history,
        .aspiration = search_build_options.stability_aspiration,
        .live_history_staging = search_build_options.live_history_staging,
        .nonroot_check_extension = search_build_options.nonroot_check_extension,
        .mate_distance_pruning = search_build_options.mate_distance_pruning,
    };
    if (execution) |worker_execution| return search.baseline.runRestrictedWorkerWithTablebaseAndParams(
        features,
        position,
        binding,
        spec.limits,
        control,
        &worker.search,
        active.table,
        heuristics,
        &observer,
        if (spec.restricted) spec.root_moves.slice() else null,
        active.tablebase,
        active.search_params,
        worker_execution,
    );
    return search.baseline.runRestrictedWithTablebaseAndParams(
        features,
        position,
        binding,
        spec.limits,
        control,
        &worker.search,
        active.table,
        heuristics,
        &observer,
        if (spec.restricted) spec.root_moves.slice() else null,
        active.tablebase,
        active.search_params,
    );
}

fn SearchControl(
    comptime Clock: type,
    comptime root_confidence_time: bool,
    comptime integrated_time: bool,
) type {
    return struct {
        active: *Active,
        timing: time.Control(Clock, root_confidence_time, integrated_time),

        pub inline fn shouldStop(self: *@This()) bool {
            return self.timing.shouldStop();
        }

        pub inline fn shouldStopAfterIteration(
            self: *@This(),
            completed: search.types.CompletedIteration,
        ) bool {
            return self.timing.shouldStopAfterIteration(completed, .{});
        }

        pub inline fn terminationReason(self: *const @This()) search.types.Termination {
            return self.timing.terminationReason();
        }

        /// Exact receipt-to-hit interval available to the later integrated
        /// time policy. It is observational in Step 6.0.4.
        pub inline fn ponderCreditNs(self: *const @This()) ?u64 {
            return self.timing.ponderCreditNs();
        }

        pub fn rootMove(
            self: *@This(),
            depth: u16,
            chess_move: chess.move.Move,
            number: usize,
            nodes: u64,
        ) void {
            self.publish(.{ .root_move = .{
                .depth = depth,
                .chess_move = chess_move,
                .number = @intCast(number),
                .nodes = nodes,
                .observed_ns = monotonicNs(self.active.io),
            } });
        }

        pub fn completedIteration(
            self: *@This(),
            completed: search.types.CompletedIteration,
        ) void {
            self.publish(.{ .iteration = .{
                .completed = completed,
                .tablebase_hits = self.active.worker.search.tablebase_hits,
                .observed_ns = monotonicNs(self.active.io),
            } });
        }

        fn publish(self: *@This(), progress: SearchProgress) void {
            if (self.active.progress.offer(self.active.io, progress))
                self.active.controller_wake.post(self.active.io);
        }
    };
}

fn SmpMainControl(
    comptime Clock: type,
    comptime root_confidence_time: bool,
    comptime integrated_time: bool,
) type {
    return struct {
        main: SearchControl(Clock, root_confidence_time, integrated_time),
        node_limit: ?u64,

        pub inline fn shouldStop(self: *@This()) bool {
            return self.main.shouldStop();
        }

        pub inline fn shouldStopAfterIteration(
            self: *@This(),
            completed: search.types.CompletedIteration,
        ) bool {
            const events = if (comptime integrated_time)
                self.main.active.helper_instability_events.swap(0, .acq_rel)
            else
                0;
            return self.main.timing.shouldStopAfterIteration(completed, .{
                .helper_instability_events = events,
                .helper_count = @intCast(self.main.active.helper_count),
            });
        }

        pub inline fn terminationReason(self: *const @This()) search.types.Termination {
            return self.main.terminationReason();
        }

        pub inline fn ponderCreditNs(self: *const @This()) ?u64 {
            return self.main.ponderCreditNs();
        }

        pub inline fn claimNode(self: *@This()) bool {
            return claimAggregateNode(self.main.active, self.node_limit);
        }

        pub fn rootMove(
            self: *@This(),
            depth: u16,
            chess_move: chess.move.Move,
            number: usize,
            nodes: u64,
        ) void {
            self.main.rootMove(depth, chess_move, number, nodes);
        }

        pub fn completedIteration(
            self: *@This(),
            completed: search.types.CompletedIteration,
        ) void {
            self.main.completedIteration(completed);
        }
    };
}

fn HelperSearchControl(
    comptime Clock: type,
    comptime root_confidence_time: bool,
    comptime integrated_time: bool,
) type {
    return struct {
        active: *Active,
        node_limit: ?u64,
        timing: time.Control(Clock, root_confidence_time, integrated_time),

        pub inline fn shouldStop(self: *@This()) bool {
            return self.active.helper_stop.load(.acquire) or self.timing.shouldStop();
        }

        pub inline fn terminationReason(self: *const @This()) search.types.Termination {
            if (self.active.helper_stop.load(.acquire)) return .stopped;
            return self.timing.terminationReason();
        }

        pub fn completedIteration(
            self: *@This(),
            completed: search.types.CompletedIteration,
        ) void {
            if (comptime integrated_time) {
                if (time.rootInstability(completed))
                    _ = self.active.helper_instability_events.fetchAdd(1, .monotonic);
            }
        }

        pub inline fn claimNode(self: *@This()) bool {
            return claimAggregateNode(self.active, self.node_limit);
        }
    };
}

fn claimAggregateNode(active: *Active, limit: ?u64) bool {
    const cap = limit orelse return true;
    var current = active.aggregate_nodes.load(.monotonic);
    while (current < cap) {
        if (active.aggregate_nodes.cmpxchgWeak(current, current + 1, .monotonic, .monotonic)) |observed| {
            current = observed;
        } else {
            return true;
        }
    }
    return false;
}

fn runBench(active: *Active, spec: bench.Spec) void {
    const Clock = struct {
        io: std.Io,

        pub fn nowNs(self: *@This()) u64 {
            return monotonicNs(self.io);
        }
    };
    const Control = struct {
        cancel_epoch: *const std.atomic.Value(u64),
        epoch: u64,

        pub fn shouldStop(self: *@This()) bool {
            return self.cancel_epoch.load(.acquire) == self.epoch;
        }
    };

    var clock = Clock{ .io = active.io };
    var control = Control{ .cancel_epoch = active.cancel_epoch, .epoch = active.epoch };
    active.completion = .{ .bench = bench.run(
        spec,
        &clock,
        &control,
        &active.worker.search,
        active.table,
        active.heuristics,
    ) };
}

fn repetitionContext(game: *const GameState) []const chess.position.PositionState {
    const current_index = game.states.len - 1;
    const reversible = @min(@as(usize, game.position.current.rule50), current_index);
    return game.states[current_index - reversible ..];
}

fn monotonicNs(io: std.Io) u64 {
    const value = std.Io.Clock.awake.now(io).nanoseconds;
    if (value <= 0) return 0;
    return @intCast(@min(value, std.math.maxInt(u64)));
}
