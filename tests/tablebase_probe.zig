//! Integration probes against a real Syzygy tablebase set.
//!
//! Tablebase files are a large external asset kept out of the repository by
//! `FILE-001`, so these tests are opt-in: set `MANTA_SYZYGY_PATH` to a Syzygy
//! directory to run them. Without it every test reports skipped, which keeps
//! CI and fresh clones green while still giving the maintainer a real check.
//!
//!     MANTA_SYZYGY_PATH=D:/chess/tablebases/syzygy3456 zig build test
const std = @import("std");
const manta = @import("manta");
const test_options = @import("test_options");

const chess = manta.chess;
const search = manta.search;
const tablebase = manta.search.tablebase;
const Handle = manta.engine.syzygy.Handle;

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

/// Returns the configured Syzygy directory, or null when the asset is absent.
fn loadTables() !?Handle {
    const path = test_options.syzygy_path;
    if (path.len == 0) return null;
    return try Handle.init(path);
}

test "a real tablebase set loads and reports its covered piece count" {
    var handle = try loadTables() orelse return error.SkipZigTest;
    defer handle.deinit();
    try std.testing.expect(handle.isLoaded());
    // Any usable Syzygy set covers at least the three-piece endings; the
    // exact ceiling depends on which files the maintainer installed.
    try std.testing.expect(handle.largest >= 3);
    try std.testing.expect(handle.largest <= 7);
}

test "known elementary endgame outcomes match established endgame theory" {
    // QUAL-014: the oracle here is chess theory, not another Manta component.
    // These outcomes are textbook and independent of any Manta code path, so a
    // mismatch means the probe translation is wrong rather than the tables.
    var handle = try loadTables() orelse return error.SkipZigTest;
    defer handle.deinit();

    const cases = [_]struct {
        fen: []const u8,
        expected: tablebase.Wdl,
        why: []const u8,
    }{
        .{ .fen = "4k3/8/8/8/8/8/8/KQ6 w - - 0 1", .expected = .win, .why = "KQ vs K mates" },
        .{ .fen = "4k3/8/8/8/8/8/8/KR6 w - - 0 1", .expected = .win, .why = "KR vs K mates" },
        .{ .fen = "4k3/8/8/8/8/8/8/KB6 w - - 0 1", .expected = .draw, .why = "KB vs K cannot mate" },
        .{ .fen = "4k3/8/8/8/8/8/8/KN6 w - - 0 1", .expected = .draw, .why = "KN vs K cannot mate" },
        .{ .fen = "4k3/8/8/8/8/8/8/KNN5 w - - 0 1", .expected = .draw, .why = "KNN vs K cannot force mate" },
        .{ .fen = "4k3/8/8/8/8/8/8/KBN5 w - - 0 1", .expected = .win, .why = "KBN vs K mates" },
        // The same material from the defending side must be the mirror verdict.
        .{ .fen = "4k3/8/8/8/8/8/8/KQ6 b - - 0 1", .expected = .loss, .why = "bare king is lost" },
        .{ .fen = "4k3/8/8/8/8/8/8/KB6 b - - 0 1", .expected = .draw, .why = "bare king holds vs KB" },
    };

    for (cases) |case| {
        var root: chess.position.PositionState = .{};
        const position = try chess.fen.parse(case.fen, &root);
        switch (handle.probeWdl(&position)) {
            .unavailable => |reason| {
                std.debug.print(
                    "probe unavailable for {s} ({s}): {s}\n",
                    .{ case.fen, case.why, @tagName(reason) },
                );
                return error.ProbeUnavailable;
            },
            .available => |wdl| {
                if (wdl != case.expected) {
                    std.debug.print(
                        "{s} ({s}): expected {s}, tables said {s}\n",
                        .{ case.fen, case.why, @tagName(case.expected), @tagName(wdl) },
                    );
                    return error.WrongVerdict;
                }
            },
        }
    }
}

test "probe verdicts are antisymmetric under colour mirroring" {
    // A metamorphic property: mirroring every piece's colour and rank, and
    // swapping the side to move, describes the same game from the other side.
    // The verdict must therefore be identical, which catches a translation that
    // swaps the white and black bitboards or the side-to-move flag.
    var handle = try loadTables() orelse return error.SkipZigTest;
    defer handle.deinit();

    const pairs = [_]struct { white: []const u8, mirrored: []const u8 }{
        .{ .white = "4k3/8/8/8/8/8/8/KQ6 w - - 0 1", .mirrored = "kq6/8/8/8/8/8/8/4K3 b - - 0 1" },
        .{ .white = "4k3/8/8/8/8/8/8/KR6 w - - 0 1", .mirrored = "kr6/8/8/8/8/8/8/4K3 b - - 0 1" },
        .{ .white = "4k3/8/8/8/8/8/8/KBN5 w - - 0 1", .mirrored = "kbn5/8/8/8/8/8/8/4K3 b - - 0 1" },
        .{ .white = "4k3/8/8/8/8/8/8/KB6 w - - 0 1", .mirrored = "kb6/8/8/8/8/8/8/4K3 b - - 0 1" },
    };

    for (pairs) |pair| {
        var first_state: chess.position.PositionState = .{};
        var second_state: chess.position.PositionState = .{};
        const first = try chess.fen.parse(pair.white, &first_state);
        const second = try chess.fen.parse(pair.mirrored, &second_state);
        const a = handle.probeWdl(&first);
        const b = handle.probeWdl(&second);
        try std.testing.expectEqual(a, b);
    }
}

test "tablebase verdicts agree with an independent deep search" {
    // A cross-check between two systems that share no code: the tables say a
    // position is won, and Manta's own search must independently reach a
    // decisive score for the same side. Disagreement means either the probe
    // translation or the score conversion is wrong.
    var handle = try loadTables() orelse return error.SkipZigTest;
    defer handle.deinit();

    const cases = [_][]const u8{
        "4k3/8/8/8/8/8/8/KQ6 w - - 0 1",
        "4k3/8/8/8/8/8/8/KR6 w - - 0 1",
        "4k3/8/8/8/8/8/8/KB6 w - - 0 1",
        "4k3/8/8/8/8/8/8/KN6 w - - 0 1",
    };

    for (cases) |fen_text| {
        var root: chess.position.PositionState = .{};
        var position = try chess.fen.parse(fen_text, &root);
        const probed = switch (handle.probeWdl(&position)) {
            .unavailable => return error.ProbeUnavailable,
            .available => |wdl| wdl,
        };

        var harness: Harness = .{};
        var storage: [1 << 14]search.tt.Cluster = undefined;
        var table = search.tt.Table.init(&storage);
        var heuristics: search.ordering.State = .{};
        var observer: search.diagnostics.Disabled = .{};
        var control: search.types.NeverStop = .{};
        // Searched without any tablebase, so the two verdicts are independent.
        const result = search.baseline.runWithFeatures(
            .{ .syzygy = false },
            &position,
            harness.binding(),
            .{ .depth = 12 },
            &control,
            &harness.thread,
            &table,
            &heuristics,
            &observer,
        );

        const raw = result.evidence.value.raw();
        switch (probed) {
            .win => try std.testing.expect(raw > manta.score.units_per_pawn * 3),
            .loss => try std.testing.expect(raw < -manta.score.units_per_pawn * 3),
            // A drawn ending must not look like a decisive advantage even
            // though the material count is lopsided.
            .draw => try std.testing.expect(@abs(raw) < manta.score.units_per_pawn * 3),
            .cursed_win, .blessed_loss => {},
        }
    }
}

test "interior probing reaches a proven score through the search integration" {
    // End to end: real tables, the real adapter and the real search policy.
    // The engine must convert a proven win into reserved-band evidence and
    // still publish a legal move and a legal principal variation.
    var handle = try loadTables() orelse return error.SkipZigTest;
    defer handle.deinit();

    const fen_text = "8/8/8/4k3/8/8/4P3/4K3 w - - 0 1";
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parse(fen_text, &root);
    var harness: Harness = .{};
    var storage: [1 << 14]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    var heuristics: search.ordering.State = .{};
    var counters: search.diagnostics.Counters = .{};
    var control: search.types.NeverStop = .{};

    const result = search.baseline.runRestrictedWithTablebase(
        .{},
        &position,
        harness.binding(),
        .{ .depth = 8 },
        &control,
        &harness.thread,
        &table,
        &heuristics,
        &counters,
        null,
        &handle,
    );

    try std.testing.expect(counters.tablebase_hits != 0);
    try std.testing.expect(result.best_move != null);
    try std.testing.expect(chess.movegen.isLegal(&position, result.best_move.?));
    try std.testing.expect(chess.state.isConsistent(&position));

    var states: [chess.types.max_ply]chess.position.PositionState = undefined;
    var replay_state: chess.position.PositionState = .{};
    var replay = try chess.fen.parse(fen_text, &replay_state);
    for (result.completed.?.pv.slice(), 0..) |chess_move, ply| {
        try std.testing.expect(chess.movegen.isLegal(&replay, chess_move));
        chess.transition.makeMove(&replay, chess_move, &states[ply]);
    }
}

test "root filtering keeps only moves that preserve the proven outcome" {
    // The rook stands next to the enemy king, so some legal moves hang it and
    // convert a won ending into a draw. Filtering must retain a strict subset.
    var handle = try loadTables() orelse return error.SkipZigTest;
    defer handle.deinit();

    const fen_text = "8/8/8/8/8/4k3/3R4/K7 w - - 0 1";
    var root: chess.position.PositionState = .{};
    const position = try chess.fen.parse(fen_text, &root);

    var legal = chess.position.MoveList.init();
    chess.movegen.generate(.all, &position, &legal);
    try std.testing.expect(legal.count != 0);

    var ranked: [chess.types.move_capacity]tablebase.RankedRootMove = undefined;
    const count = handle.probeRootMoves(&position, legal.slice(), &ranked) orelse
        return error.RootProbeUnavailable;
    // Every legal move must be ranked; a partial ranking would silently hide
    // legal options from search.
    try std.testing.expectEqual(@as(usize, legal.count), count);

    var kept: [chess.types.move_capacity]chess.move.Move = undefined;
    const kept_count = tablebase.retainBestRanked(ranked[0..count], &kept);
    try std.testing.expect(kept_count != 0);
    try std.testing.expect(kept_count < legal.count);
    for (kept[0..kept_count]) |chess_move|
        try std.testing.expect(chess.movegen.isLegal(&position, chess_move));

    // The side to move is winning, so the best rank must be a winning rank.
    var best: i32 = ranked[0].rank;
    for (ranked[0..count]) |candidate| best = @max(best, candidate.rank);
    try std.testing.expect(best > 0);
}

test "a filtered root still publishes a legal move and never empties" {
    // End to end through search: root filtering must preserve the published
    // contract exactly, including a legal best move and a legal PV.
    var handle = try loadTables() orelse return error.SkipZigTest;
    defer handle.deinit();

    const fen_text = "8/8/8/8/8/4k3/3R4/K7 w - - 0 1";
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parse(fen_text, &root);
    var harness: Harness = .{};
    var storage: [1 << 14]search.tt.Cluster = undefined;
    var table = search.tt.Table.init(&storage);
    var heuristics: search.ordering.State = .{};
    var counters: search.diagnostics.Counters = .{};
    var control: search.types.NeverStop = .{};

    const result = search.baseline.runRestrictedWithTablebase(
        .{},
        &position,
        harness.binding(),
        .{ .depth = 6 },
        &control,
        &harness.thread,
        &table,
        &heuristics,
        &counters,
        null,
        &handle,
    );

    try std.testing.expect(counters.tablebase_root_filters != 0);
    try std.testing.expect(counters.tablebase_root_moves_kept != 0);
    try std.testing.expect(
        counters.tablebase_root_moves_kept < counters.tablebase_root_moves_before,
    );
    try std.testing.expect(result.best_move != null);
    try std.testing.expect(chess.movegen.isLegal(&position, result.best_move.?));
    try std.testing.expect(chess.state.isConsistent(&position));

    // The retained move must actually keep the win rather than hang the rook.
    var after_state: chess.position.PositionState = .{};
    var after = try chess.fen.parse(fen_text, &after_state);
    var applied: chess.position.PositionState = .{};
    chess.transition.makeMove(&after, result.best_move.?, &applied);
    switch (handle.probeWdl(&after)) {
        .unavailable => {},
        // After the move it is Black to move, so a preserved white win reads
        // as a loss from the side now to move.
        .available => |wdl| try std.testing.expectEqual(tablebase.Wdl.loss, wdl),
    }

    var states: [chess.types.max_ply]chess.position.PositionState = undefined;
    var replay_state: chess.position.PositionState = .{};
    var replay = try chess.fen.parse(fen_text, &replay_state);
    for (result.completed.?.pv.slice(), 0..) |chess_move, ply| {
        try std.testing.expect(chess.movegen.isLegal(&replay, chess_move));
        chess.transition.makeMove(&replay, chess_move, &states[ply]);
    }
}

test "an explicit searchmoves restriction outranks tablebase filtering" {
    // A user instruction must win: when the caller restricts the root, the
    // tables may not silently widen or narrow that list.
    var handle = try loadTables() orelse return error.SkipZigTest;
    defer handle.deinit();

    const fen_text = "8/8/8/8/8/4k3/3R4/K7 w - - 0 1";
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parse(fen_text, &root);
    var legal = chess.position.MoveList.init();
    chess.movegen.generate(.all, &position, &legal);

    const chosen = [_]chess.move.Move{legal.slice()[0]};
    var harness: Harness = .{};
    var counters: search.diagnostics.Counters = .{};
    var control: search.types.NeverStop = .{};

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
        &chosen,
        &handle,
    );

    try std.testing.expectEqual(@as(u64, 0), counters.tablebase_root_filters);
    try std.testing.expectEqual(chosen[0].raw(), result.best_move.?.raw());
}
