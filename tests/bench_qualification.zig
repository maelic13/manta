//! Independent contracts for the built-in whole-search benchmark.
//!
//! Every total below is a search-shape snapshot taken under the evaluator of
//! its day, so all of them moved when Steps 5.3.3 to 5.3.5 added shelter,
//! storm and king safety, and all of them moved again when Step 5.3.8 added
//! nonlinear material imbalance, when Step 5.3.13 added exact-signature
//! endgame values and scale factors, when Step 5.3.14 added winnability, and
//! when Step 5.3.16 baked the constrained joint coefficient fit.
//! The archived switches
//! still reproduce a distinct recorded tree, which preserves their refutation
//! history; the exact integers were re-recorded together and none was edited
//! to make a failure disappear.
//!
//! The Step-5.3.8 cost work is deliberately absent from that list. Constant-
//! time repetition state and the fused attack and pawn producers changed no
//! evaluation and no search decision, so they left every total untouched;
//! that is the evidence which separates them from the imbalance term.
const std = @import("std");
const builtin = @import("builtin");
const manta = @import("manta");
const bench = manta.engine.bench;
const chess = manta.chess;

fn runArchived(
    comptime features: manta.search.types.Features,
    spec: bench.Spec,
    clock: anytype,
    control: anytype,
    thread: *manta.search.types.ThreadState,
    table: *manta.search.tt.Table,
    ordering: *manta.search.ordering.State,
) bench.Report {
    // Every archived total below was recorded before Step 6.5.1b promoted the
    // live-history staged picker, so faithful reconstruction restores the
    // MAN-S19-era eager picker alongside the MAN-S19 parameter vector.
    comptime var archived = features;
    archived.live_history_staging = false;
    return bench.runWithFeaturesAndParams(
        archived,
        spec,
        clock,
        control,
        thread,
        table,
        ordering,
        manta.search.params.man_s19,
    );
}

test "bench corpus is the frozen ordered set of forty legal positions" {
    // A malformed or illegal FEN changes the search workload before any node
    // fingerprint can reveal why, so every input is parsed independently.
    try std.testing.expectEqual(@as(usize, 40), bench.positions.len);
    for (bench.positions) |fen_text| {
        var state: chess.position.PositionState = .{};
        _ = try chess.fen.parse(fen_text, &state);
    }
}

test "bench aggregate metrics use upper median and fixed decimal scales" {
    var report = bench.Report.init(.{ .depth = 1 });
    for (&report.positions, 1..) |*record, nodes| {
        record.* = .{ .nodes = nodes, .completed_depth = 1 };
        report.runs[0].nodes += nodes;
    }
    report.finishFirstRun();
    try std.testing.expectEqual(@as(u64, 820), report.fingerprint_nodes);
    try std.testing.expectEqual(@as(u64, 21), report.median_nodes);
    try std.testing.expectEqual(@as(u64, 48_780), report.top_share_million);
    try std.testing.expectEqual(@as(u64, 15_769), report.geomean_ebf_milli);
}

test "bench repeats reset shared search state" {
    // Every mode exercises the complete corpus twice at a cheap depth so the
    // equality check is independent of wall time and optimization mode.
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = bench.run(
        .{ .depth = 1, .repeats = 2 },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u16, 2), report.completed_runs);
    try std.testing.expect(report.fingerprint_nodes != 0);
    try std.testing.expectEqual(report.fingerprint_nodes, report.runs[1].nodes);
}

test "optimized safety and production modes preserve the accepted MAN-S30 fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = bench.run(
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    // This exact total was frozen only after MAN-S30 accepted H1 and moved
    // production from `799,610`. It is a diagnostic tree-shape contract, not
    // the evidence that promoted it.
    try std.testing.expectEqual(@as(u64, 775_451), report.fingerprint_nodes);
}

test "archived depth-authority cluster reproduces the MAN-S21 fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{ .depth_authority_sync = true },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u64, 735_200), report.fingerprint_nodes);
}

test "default-off candidate heads build and search" {
    if (builtin.mode == .Debug) return;
    // Both switches default off, so nothing else in the suite instantiates the
    // search generic with them on. A candidate path that does not compile is
    // invisible until someone tries to build the candidate, which is exactly
    // what happened to correction history: it referenced a field on the wrong
    // struct and every default build passed. These fingerprints are candidate
    // evidence, not frozen production contracts.
    inline for (.{
        .{ manta.search.types.Features{ .lmr_desaturation = true }, @as(u64, 724_776) },
        // MAN-S25 moved from 735,679 when the audit repaired its consumer
        // boundary: correction now changes qsearch stand pat, while raw HCE
        // continues to own improving, pruning and TT storage.
        .{ manta.search.types.Features{ .correction_history = true }, @as(u64, 760_161) },
    }) |candidate| {
        var hash = try manta.engine.runtime.HashResource.init(
            std.testing.allocator,
            bench.hash_bytes / (1024 * 1024),
        );
        defer hash.deinit(std.testing.allocator);
        var thread = manta.search.types.ThreadState.init();
        var ordering: manta.search.ordering.State = .{};
        var control: manta.search.types.NeverStop = .{};
        var clock = IncrementingClock{};
        const report = runArchived(
            candidate[0],
            .{ .depth = bench.default_depth },
            &clock,
            &control,
            &thread,
            &hash.table,
            &ordering,
        );
        try std.testing.expect(!report.cancelled and !report.failed);
        try std.testing.expectEqual(candidate[1], report.fingerprint_nodes);
    }
}

test "disabling MAN-S30 staging reconstructs the archived MAN-S29 fingerprint" {
    if (builtin.mode == .Debug) return;
    // MAN-S30 accepted H1 and became production, so the switch now runs the
    // other way: turning live-history staging off must still rebuild the
    // superseded eager picker exactly on the unchanged MAN-S29 parameter head.
    // That keeps the promoted mechanism independently ablatable and preserves
    // the causal ledger entry for the `799,610` to `775,451` tree change.
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = bench.runWithFeatures(
        .{ .live_history_staging = false },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u64, 799_610), report.fingerprint_nodes);
}

test "MAN-R02 stability aspiration builds on the MAN-S29 picker it was qualified under" {
    if (builtin.mode == .Debug) return;
    // This exact total proves that the default-off candidate is live and
    // buildable on MAN-S29, not that fewer nodes are speed or Elo. Step 6.5.1b
    // changed the production picker after MAN-R02 was archived, so the switch
    // stays off here rather than re-recording a rejected candidate's total on
    // a head it was never measured against.
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = bench.runWithFeatures(
        .{ .aspiration = true, .live_history_staging = false },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u64, 777_105), report.fingerprint_nodes);
}

test "archived main-selectivity cluster reproduces the rejected MAN-S20 fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{ .depth_authority_sync = false, .main_selectivity_sync = true },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u64, 784_030), report.fingerprint_nodes);
}

test "evaluation qsearch cluster switch restores the accepted MAN-S17 fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{ .depth_authority_sync = false, .main_selectivity_sync = false, .eval_qsearch_sync = false },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u64, 819_474), report.fingerprint_nodes);
}

test "rejected MAN-S18 switch retains its qualified diagnostic fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{ .depth_authority_sync = false, .main_selectivity_sync = false, .eval_qsearch_sync = false, .lmr_synchronization = true },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u64, 866_632), report.fingerprint_nodes);
}

test "continuation-history switch restores the accepted MAN-S15 fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{ .depth_authority_sync = false, .main_selectivity_sync = false, .eval_qsearch_sync = false, .lmr_synchronization = false, .continuation_history = false },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u64, 789_378), report.fingerprint_nodes);
}

test "capture-history switch preserves the rejected MAN-S16 fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{ .depth_authority_sync = false, .main_selectivity_sync = false, .eval_qsearch_sync = false, .lmr_synchronization = false, .capture_history = true, .continuation_history = false },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u64, 856_924), report.fingerprint_nodes);
}

test "dynamic LMR switch restores the accepted MAN-S13 fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{ .depth_authority_sync = false, .main_selectivity_sync = false, .eval_qsearch_sync = false, .lmr_synchronization = false, .capture_history = false, .dynamic_lmr = false, .continuation_history = false },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u64, 944_932), report.fingerprint_nodes);
}

test "LMR reply-feedback switch reproduces the archived MAN-S14 candidate fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{ .depth_authority_sync = false, .main_selectivity_sync = false, .eval_qsearch_sync = false, .lmr_synchronization = false, .capture_history = false, .dynamic_lmr = false, .continuation_history = false, .lmr_reply_feedback = true },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u64, 976_202), report.fingerprint_nodes);
}

test "contextual-history switch restores the accepted MAN-S12 fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{ .depth_authority_sync = false, .main_selectivity_sync = false, .eval_qsearch_sync = false, .lmr_synchronization = false, .capture_history = false, .dynamic_lmr = false, .contextual_history = false },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u64, 1_026_575), report.fingerprint_nodes);
}

test "depth-authority family switch restores the accepted MAN-S07 fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{
            .depth_authority_sync = false,
            .main_selectivity_sync = false,
            .capture_history = false,
            .eval_qsearch_sync = false,
            .lmr_synchronization = false,
            .depth_authority = false,
            .dynamic_lmr = false,
            .shallow_selectivity = false,
            .probcut = false,
            .contextual_history = false,
        },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u64, 2_908_959), report.fingerprint_nodes);
}

test "ProbCut switch restores the accepted MAN-S11 fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{
            .depth_authority_sync = false,
            .main_selectivity_sync = false,
            .capture_history = false,
            .eval_qsearch_sync = false,
            .lmr_synchronization = false,
            .dynamic_lmr = false,
            .shallow_selectivity = true,
            .probcut = false,
            .contextual_history = false,
        },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    // Disabling only ProbCut recovers the accepted shallow-selectivity policy;
    // the exact total is a diagnostic tree-shape contract, not strength.
    try std.testing.expectEqual(@as(u64, 1_049_740), report.fingerprint_nodes);
}

test "shallow-selectivity family switch restores the accepted MAN-S10 fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{
            .depth_authority_sync = false,
            .main_selectivity_sync = false,
            .capture_history = false,
            .eval_qsearch_sync = false,
            .lmr_synchronization = false,
            .dynamic_lmr = false,
            .shallow_selectivity = false,
            .probcut = false,
            .contextual_history = false,
        },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    try std.testing.expectEqual(@as(u64, 4_804_886), report.fingerprint_nodes);
}

test "parked razoring component retains its own qualified diagnostic fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{
            .depth_authority_sync = false,
            .main_selectivity_sync = false,
            .capture_history = false,
            .eval_qsearch_sync = false,
            .lmr_synchronization = false,
            .shallow_selectivity = true,
            .dynamic_lmr = false,
            .razoring = true,
            .probcut = false,
            .contextual_history = false,
        },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    try std.testing.expect(!report.cancelled and !report.failed);
    // Preserve the component checkpoint without making it production policy.
    // A depth-one verified-qsearch razor still changed the WAC.001 canary, so
    // it is not enabled by any accepted feature combination above.
    try std.testing.expectEqual(@as(u64, 947_497), report.fingerprint_nodes);
}

test "search-context switch preserves the accepted MAN-S07 fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{
            .depth_authority_sync = false,
            .main_selectivity_sync = false,
            .capture_history = false,
            .eval_qsearch_sync = false,
            .lmr_synchronization = false,
            .search_context = false,
            .dynamic_lmr = false,
            .shallow_selectivity = false,
            .probcut = false,
            .contextual_history = false,
        },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    // The infrastructure switch removes context, its dependent family, and
    // all observation calls, restoring the accepted playing baseline exactly.
    try std.testing.expectEqual(@as(u64, 2_908_959), report.fingerprint_nodes);
}

test "parked MAN-S08 switch retains its qualified diagnostic fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{
            .depth_authority_sync = false,
            .main_selectivity_sync = false,
            .capture_history = false,
            .eval_qsearch_sync = false,
            .lmr_synchronization = false,
            .depth_authority = false,
            .dynamic_lmr = false,
            .shallow_selectivity = true,
            .reverse_futility = true,
            .quiet_futility = false,
            .late_move_pruning = false,
            .see_pruning = false,
            .probcut = false,
            .contextual_history = false,
        },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    // Preserve the component checkpoint without making it production policy.
    // Its tree reduction did not receive an isolated playing verdict.
    try std.testing.expectEqual(@as(u64, 2_552_965), report.fingerprint_nodes);
}

test "qsearch SEE switch restores the accepted MAN-S04 fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{
            .depth_authority_sync = false,
            .main_selectivity_sync = false,
            .capture_history = false,
            .eval_qsearch_sync = false,
            .lmr_synchronization = false,
            .depth_authority = false,
            .dynamic_lmr = false,
            .qsearch_see = false,
            .reverse_futility = false,
            .shallow_selectivity = false,
            .probcut = false,
            .contextual_history = false,
        },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    // Disabling only this candidate must recover the accepted engine exactly;
    // the frozen node total is a tree-shape diagnostic, not strength evidence.
    try std.testing.expectEqual(@as(u64, 3_265_805), report.fingerprint_nodes);
}

test "rejected MAN-S06 switches retain their qualified diagnostic fingerprint" {
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(
        std.testing.allocator,
        bench.hash_bytes / (1024 * 1024),
    );
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control: manta.search.types.NeverStop = .{};
    var clock = IncrementingClock{};
    const report = runArchived(
        .{
            .depth_authority_sync = false,
            .main_selectivity_sync = false,
            .capture_history = false,
            .eval_qsearch_sync = false,
            .lmr_synchronization = false,
            .depth_authority = false,
            .dynamic_lmr = false,
            .balanced_history = true,
            .history_lmr = true,
            .qsearch_see = false,
            .reverse_futility = false,
            .shallow_selectivity = false,
            .probcut = false,
            .contextual_history = false,
        },
        .{ .depth = bench.default_depth },
        &clock,
        &control,
        &thread,
        &hash.table,
        &ordering,
    );
    // This archives the rejected candidate's deterministic tree shape so later
    // work cannot silently reinterpret or rediscover it as accepted behavior.
    try std.testing.expectEqual(@as(u64, 3_322_009), report.fingerprint_nodes);
}

test "bench cancellation publishes no incomplete position as completed" {
    var hash = try manta.engine.runtime.HashResource.init(std.testing.allocator, 1);
    defer hash.deinit(std.testing.allocator);
    var thread = manta.search.types.ThreadState.init();
    var ordering: manta.search.ordering.State = .{};
    var control = ImmediateStop{};
    var clock = IncrementingClock{};
    const report = bench.run(.{ .depth = 1 }, &clock, &control, &thread, &hash.table, &ordering);
    try std.testing.expect(report.cancelled);
    try std.testing.expectEqual(@as(u16, 0), report.completed_positions);
    try std.testing.expectEqual(@as(u64, 0), report.current_nodes);
}

const IncrementingClock = struct {
    value: u64 = 0,

    pub fn nowNs(self: *@This()) u64 {
        self.value += std.time.ns_per_ms;
        return self.value;
    }
};

const ImmediateStop = struct {
    pub fn shouldStop(_: *@This()) bool {
        return true;
    }
};
