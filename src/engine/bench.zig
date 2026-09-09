//! Versioned deterministic whole-search benchmark contract and records.
const std = @import("std");
const search_build_options = @import("search_build_options");
const chess = @import("../chess/root.zig");
const eval = @import("../eval/root.zig");
const search = @import("../search/root.zig");

pub const version = "manta-search-bench-v1";
pub const default_depth: u16 = 6;
pub const max_repeats: u16 = 16;
pub const hash_bytes: usize = 16 * 1024 * 1024;
pub const position_count = positions.len;

pub const Spec = struct {
    depth: u16 = default_depth,
    repeats: u16 = 1,
    threads: u16 = 1,
};

pub const PositionRecord = struct {
    score: i32 = 0,
    nodes: u64 = 0,
    time_ms: u64 = 0,
    completed_depth: u16 = 0,
};

pub const RunRecord = struct {
    nodes: u64 = 0,
    time_ms: u64 = 0,
};

pub const Report = struct {
    spec: Spec,
    positions: [position_count]PositionRecord = @splat(.{}),
    runs: [max_repeats]RunRecord = @splat(.{}),
    completed_runs: u16 = 0,
    completed_positions: u16 = 0,
    current_nodes: u64 = 0,
    fingerprint_nodes: u64 = 0,
    geomean_ebf_milli: u64 = 0,
    median_nodes: u64 = 0,
    maximum_nodes: u64 = 0,
    top_share_million: u64 = 0,
    cancelled: bool = false,
    failed: bool = false,

    pub fn init(spec: Spec) Report {
        return .{ .spec = spec };
    }

    pub fn finishFirstRun(self: *Report) void {
        self.fingerprint_nodes = self.runs[0].nodes;
        var sorted: [position_count]u64 = undefined;
        var log_sum: f64 = 0;
        var ebf_count: u64 = 0;
        var maximum: u64 = 0;
        for (self.positions, 0..) |record, index| {
            sorted[index] = record.nodes;
            maximum = @max(maximum, record.nodes);
            if (record.nodes != 0 and record.completed_depth != 0) {
                log_sum += @log(@as(f64, @floatFromInt(record.nodes))) /
                    @as(f64, @floatFromInt(record.completed_depth));
                ebf_count += 1;
            }
        }
        self.maximum_nodes = maximum;
        std.mem.sort(u64, &sorted, {}, std.sort.asc(u64));
        self.median_nodes = sorted[sorted.len / 2];
        if (ebf_count != 0) {
            const mean = @exp(log_sum / @as(f64, @floatFromInt(ebf_count)));
            self.geomean_ebf_milli = @intFromFloat(@round(mean * 1000.0));
        }
        if (self.fingerprint_nodes != 0) {
            const scaled = @as(u128, maximum) * 1_000_000;
            self.top_share_million = @intCast(scaled / self.fingerprint_nodes);
        }
    }
};

pub fn nps(nodes: u64, time_ms: u64) u64 {
    if (time_ms == 0) return nodes;
    return @intCast((@as(u128, nodes) * 1000) / time_ms);
}

pub fn positionEbfMilli(record: PositionRecord) u64 {
    if (record.nodes == 0 or record.completed_depth == 0) return 0;
    const value = @exp(@log(@as(f64, @floatFromInt(record.nodes))) /
        @as(f64, @floatFromInt(record.completed_depth)));
    return @intFromFloat(@round(value * 1000.0));
}

pub fn positionEbfCenti(record: PositionRecord) u64 {
    if (record.nodes == 0 or record.completed_depth == 0) return 0;
    const value = @exp(@log(@as(f64, @floatFromInt(record.nodes))) /
        @as(f64, @floatFromInt(record.completed_depth)));
    return @intFromFloat(@round(value * 100.0));
}

pub fn topShareTenthsPercent(report: *const Report) u64 {
    if (report.fingerprint_nodes == 0) return 0;
    const numerator = @as(u128, report.maximum_nodes) * 1000;
    return @intCast((numerator + report.fingerprint_nodes / 2) / report.fingerprint_nodes);
}

/// Runs the real scalar search with caller-owned resources. `clock` affects
/// descriptive timing only; `control` owns cancellation and neither can change
/// the deterministic completed-search node fingerprint.
pub fn run(
    spec: Spec,
    clock: anytype,
    control: anytype,
    thread: *search.types.ThreadState,
    table: *search.tt.Table,
    heuristics: *search.ordering.State,
) Report {
    return runWithFeatures(
        .{
            .correction_history = search_build_options.correction_history,
            .aspiration = search_build_options.stability_aspiration,
            .live_history_staging = search_build_options.live_history_staging,
            .nonroot_check_extension = search_build_options.nonroot_check_extension,
            .mate_distance_pruning = search_build_options.mate_distance_pruning,
            .singular_exclusion_horizon = search_build_options.singular_exclusion_horizon,
            .qsearch_tactical_generation = search_build_options.qsearch_tactical_generation,
        },
        spec,
        clock,
        control,
        thread,
        table,
        heuristics,
    );
}

/// Runs the frozen workload with a compile-time search-feature selection for
/// decision-worthy ablations. Production callers use `run`.
pub fn runWithFeatures(
    comptime features: search.types.Features,
    spec: Spec,
    clock: anytype,
    control: anytype,
    thread: *search.types.ThreadState,
    table: *search.tt.Table,
    heuristics: *search.ordering.State,
) Report {
    return runWithFeaturesAndParams(features, spec, clock, control, thread, table, heuristics, .{});
}

/// Reconstructs an archived feature arm with its frozen parameter vector.
/// Production callers use `runWithFeatures` and therefore accepted defaults.
pub fn runWithFeaturesAndParams(
    comptime features: search.types.Features,
    spec: Spec,
    clock: anytype,
    control: anytype,
    thread: *search.types.ThreadState,
    table: *search.tt.Table,
    heuristics: *search.ordering.State,
    search_params: search.params.Values,
) Report {
    var report = Report.init(spec);
    for (0..spec.repeats) |repeat| {
        table.clear();
        heuristics.clear();
        report.completed_positions = 0;
        report.current_nodes = 0;
        var run_time_ms: u64 = 0;

        for (positions, 0..) |fen_text, position_index| {
            if (control.shouldStop()) {
                report.cancelled = true;
                return report;
            }

            var root_state: chess.position.PositionState = .{};
            var position = chess.fen.parse(fen_text, &root_state) catch {
                report.failed = true;
                return report;
            };
            var evaluator: eval.hce.Hce = .{};
            var evaluator_state: eval.hce.Hce.State = .{};
            var sink: eval.trace.Disabled = .{};
            const Binding = eval.contract.Binding(eval.hce.Hce, eval.trace.Disabled);
            const binding = Binding{ .evaluator = &evaluator, .state = &evaluator_state, .sink = &sink };
            var observer: search.diagnostics.Disabled = .{};
            const started_ns = clock.nowNs();
            const result = search.baseline.runWithFeaturesAndParams(
                features,
                &position,
                binding,
                .{ .depth = spec.depth },
                control,
                thread,
                table,
                heuristics,
                &observer,
                search_params,
            );
            const elapsed_ms = (clock.nowNs() -| started_ns) / std.time.ns_per_ms;
            if (result.termination == .stopped) {
                report.cancelled = true;
                return report;
            }
            report.current_nodes +|= result.nodes;
            run_time_ms +|= elapsed_ms;

            if (repeat == 0) {
                report.positions[position_index] = .{
                    .score = result.evidence.value.raw(),
                    .nodes = result.nodes,
                    .time_ms = elapsed_ms,
                    .completed_depth = if (result.completed) |completed| completed.depth else 0,
                };
            }
            report.completed_positions += 1;
        }

        report.runs[repeat] = .{ .nodes = report.current_nodes, .time_ms = run_time_ms };
        report.completed_runs += 1;
        if (repeat == 0) report.finishFirstRun();
    }
    return report;
}

/// Shared ordered corpus. TT and ordering histories are cleared once before
/// each complete pass; positions within a pass deliberately share those caches.
pub const positions = [_][]const u8{
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
    "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
    "r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1",
    "8/pp2k3/8/2p5/2P5/1P2K3/P7/8 w - - 0 1",
    "r1bq1r2/pp2n3/4N2k/3pPppP/1b1n2Q1/2N5/PP3PP1/R1B1K2R w KQ g6 0 20",
    "r4rk1/pp1n1pp1/2p1pn1p/q7/3P4/2NB4/PP3PPP/R2QR1K1 w - - 0 1",
    "5k2/5p1p/p3B1p1/Pp6/1P6/5P1P/4K1P1/8 b - - 0 1",
    "6k1/p3q2p/1nr3p1/8/3Q4/7P/PP4P1/4R1K1 b - - 0 1",
    "2r3k1/1q2Rp1p/p2p2p1/1p1P4/1Pp1P3/2Q5/1P4PP/6K1 w - - 0 1",
    "1r3rk1/p4ppp/2p5/3Nb3/1p1bP3/1B4P1/PP3P1P/R2R2K1 b - - 0 1",
    "r2qr1k1/p4ppp/1pn1bn2/2b1p3/4P3/1BN1BN2/PPP2PPP/R2QR1K1 b - - 6 10",
    "r1bqkb1r/pp1p1ppp/2n1pn2/2p5/4P3/2NP1N2/PPP2PPP/R1BQKB1R w KQkq - 0 5",
    "8/8/p1p5/1p5p/1P5P/P1P5/8/K1k5 w - - 0 1",
    "1k6/1b6/8/5p2/p1p2p2/P7/1P3P2/K7 b - - 0 1",
    "1k1rr3/pb3n2/1pnpqbp1/2pNp2p/2P1P2P/P2Q1P2/1PN1BBP1/1K1RR3 b - - 5 10",
    "3r1rk1/1ppb1pb1/p2npqnp/P5p1/3P4/1BN1BN1P/1PP2PP1/3RQR1K w - - 3 10",
    "1b2qrk1/rp3pp1/2p1p2p/p1Pp4/P2Pn3/1Q2PN1P/1P2BPP1/1KR2R2 w - - 3 11",
    "1r3rk1/1pqb1p2/pN1p1bp1/P1pPp3/2P1P2p/1P2QN1P/4RPP1/3R2K1 w - - 2 12",
    "1k1r1r2/pp3pp1/4qn1p/P1p1p3/2p1P3/3PPN1P/1PP3P1/2RQ1RK1 b - - 0 9",
    "1r1q1rk1/3np2p/1n1p2pb/pP1P4/4BP2/2p1BN1P/Q1P1N1P1/5RK1 b - - 0 11",
    "1k1r1n2/1pq1n1b1/2p1p1p1/p2p4/PP1P1PP1/2PB1N2/5B2/2Q1K2R w - - 0 12",
    "1kr1rq2/2p2pR1/p1n1pP2/n2pP3/3P3p/1P3N1P/2P1NQ2/1K1R4 w - - 4 13",
    "1b1rr1k1/1p4q1/1Qp1b1pp/p3p3/P7/2PBN3/1P1R1P2/3R2K1 b - - 1 9",
    "1kr2r2/1p1n1pp1/4p1p1/p2p2P1/3P3P/6P1/PPP3B1/1K1R1R2 b - - 0 10",
    "1Q2n1k1/4bp2/4p1p1/pB1pP2p/q2P1P1P/2P1KNP1/8/8 b - - 6 14",
    "1k2r3/1pp1bpKp/p7/8/2PNr3/1P2P1P1/P4P1P/3R3R b - - 2 9",
    "1B6/1p6/p1p2k2/P1P1p1p1/1P1nPp1p/5P1P/1K4P1/8 b - - 48 110",
    "1k1r4/1b4r1/p3P1n1/1p3pp1/2p5/2N5/1P2R1P1/4RBK1 b - - 4 11",
    "1Q4bk/3R2pp/p7/3p3P/1p6/1B6/P2q1PP1/6K1 w - - 2 17",
    "1R6/5ppk/2N1p2p/4P2P/P3P3/1P3KP1/1r2r3/8 b - - 1 25",
    "1B6/5p1k/3P1b2/p7/2r3Pp/2P4P/1P2R2K/8 b - - 0 9",
    "1R6/5pkp/4qp1b/3p4/7P/6P1/5Q1K/2r2B2 w - - 1 14",
    "1K6/1P1rkp2/B3p3/8/1R1Pb3/5p2/5P2/8 b - - 17 12",
    "1R6/5k2/3ppp2/4p3/P7/1P4P1/2P2r2/1K6 w - - 0 16",
    "1B6/8/1P1nk1p1/3b1p2/3K1P2/3B4/8/8 w - - 9 10",
    "1R6/3q1k2/6p1/7p/4p2P/6P1/5P2/6K1 b - - 3 37",
    "1Q4R1/5k2/4rpp1/3K4/8/7p/8/8 b - - 2 9",
    "1R6/8/4r3/6P1/1pk1b2P/8/3K4/8 b - - 0 11",
};
