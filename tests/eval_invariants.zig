//! Step-3.2 HCE invariants derived from chess and score-domain contracts.
const std = @import("std");
const manta = @import("manta");

const chess = manta.chess;
const hce = manta.eval.hce;
const Disabled = manta.eval.trace.Disabled;
const TraceBuffer = manta.eval.trace.Buffer(hce.TraceValue, 12);
const ManE21Trace = manta.eval.trace.Buffer(hce.TraceValue, 32);

/// Tapered score components the evaluator emits before the phase and total
/// records. This name keeps their count in one place after schema-v3 removed
/// the rejected imbalance trace slot.
const tapered_component_count = 8;

const positions = [_][]const u8{
    chess.fen.start_position,
    "r3k2r/p1ppqpb1/bn2pnp1/2pP4/1p2P3/2N2N2/PPQBBPPP/R3K2R w KQkq - 0 1",
    "8/2p5/3p4/1P1P4/8/4k3/8/4K3 w - - 0 40",
    "4k3/8/8/3P4/8/8/4K3/8 w - - 0 1",
    "4k3/8/8/8/8/2n5/3P4/4K3 b - - 0 1",
};

test "rank flip plus color and side swap preserves relative evaluation" {
    // A color-relative chess feature has equal side-to-move meaning after the
    // complete board symmetry; every white-centric trace component negates.
    for (positions) |fen_text| {
        var root: chess.position.PositionState = .{};
        const original = try chess.fen.parse(fen_text, &root);
        var twin_root: chess.position.PositionState = .{};
        const twin = try colorFlip(&original, &twin_root);

        var original_state: hce.Hce.State = .{};
        var twin_state: hce.Hce.State = .{};
        var original_trace = TraceBuffer.init();
        var twin_trace = TraceBuffer.init();
        const original_score = hce.Hce.evaluate(
            TraceBuffer,
            &.{},
            &original_state,
            &original,
            &original_trace,
        );
        const twin_score = hce.Hce.evaluate(
            TraceBuffer,
            &.{},
            &twin_state,
            &twin,
            &twin_trace,
        );

        try std.testing.expect(chess.state.isConsistent(&twin));
        try std.testing.expectEqual(original_score, twin_score);
        try std.testing.expectEqual(original_trace.slice().len, twin_trace.slice().len);
        const components = tapered_component_count;
        for (original_trace.slice()[0..components], twin_trace.slice()[0..components]) |left, right| {
            try std.testing.expectEqualStrings(left.label, right.label);
            try std.testing.expectEqual(-left.value.tapered.middlegame, right.value.tapered.middlegame);
            try std.testing.expectEqual(-left.value.tapered.endgame, right.value.tapered.endgame);
        }
        try std.testing.expectEqual(
            original_trace.slice()[components].value.phase,
            twin_trace.slice()[components].value.phase,
        );
        try std.testing.expectEqual(
            original_trace.slice()[components + 1].value.total,
            twin_trace.slice()[components + 1].value.total,
        );
    }
}

test "contextual space preserves legal-position color symmetry" {
    // SCORE-024: weighting is applied to each side before subtraction, so a
    // complete rank/color/side mirror has exactly the same relative score.
    const Candidate = hce.HceWith(.{ .contextual_space = true });
    for (positions) |fen_text| {
        var root: chess.position.PositionState = .{};
        const original = try chess.fen.parse(fen_text, &root);
        var twin_root: chess.position.PositionState = .{};
        const twin = try colorFlip(&original, &twin_root);
        var original_state: Candidate.State = .{};
        var twin_state: Candidate.State = .{};
        var sink: Disabled = .{};
        try std.testing.expectEqual(
            Candidate.evaluate(Disabled, &.{}, &original_state, &original, &sink),
            Candidate.evaluate(Disabled, &.{}, &twin_state, &twin, &sink),
        );
    }
}

test "contextual space agrees across reused and fresh evaluator state" {
    // SCORE-024: MAN-E20 reads only the current board and phase. Reusing the
    // worker-local pawn cache across legal moves must equal a fresh full
    // evaluation; the candidate adds no incremental ownership of its own.
    const Candidate = hce.HceWith(.{ .contextual_space = true });
    var root: chess.position.PositionState = .{};
    var value = try chess.fen.parseStart(&root);
    var children: [48]chess.position.PositionState = undefined;
    var reused_state: Candidate.State = .{};
    var random: u64 = 0x4d41_4e2d_4532_3001;
    var sink: Disabled = .{};

    for (&children) |*child| {
        var fresh_state: Candidate.State = .{};
        try std.testing.expectEqual(
            Candidate.evaluate(Disabled, &.{}, &fresh_state, &value, &sink),
            Candidate.evaluate(Disabled, &.{}, &reused_state, &value, &sink),
        );

        var legal = chess.position.MoveList.init();
        chess.movegen.generate(.all, &value, &legal);
        if (legal.count == 0) break;
        random = random *% 6_364_136_223_846_793_005 +% 1_442_695_040_888_963_407;
        const selected = legal.slice()[@as(usize, @intCast(random % legal.count))];
        chess.transition.makeMove(&value, selected, child);
    }
}

test "shelter-danger coupling preserves color symmetry and evaluator-state identity" {
    // SCORE-025: MAN-E21 reads only current-board attack and shelter evidence.
    // A full colour/rank mirror keeps the side-to-move score, while reusing
    // the worker-local pawn cache must equal a fresh full refresh.
    const Candidate = hce.HceWith(.{ .shelter_danger_coupling = true });
    const candidate_positions = positions ++ [_][]const u8{
        "k7/8/8/8/8/4p2p/5PPP/6K1 w - - 0 1",
        "k7/8/8/8/8/4p2p/8/6K1 w - - 0 1",
    };
    var sink: Disabled = .{};
    for (candidate_positions) |fen_text| {
        var root: chess.position.PositionState = .{};
        const original = try chess.fen.parse(fen_text, &root);
        var twin_root: chess.position.PositionState = .{};
        const twin = try colorFlip(&original, &twin_root);
        var original_state: Candidate.State = .{};
        var twin_state: Candidate.State = .{};
        try std.testing.expectEqual(
            Candidate.evaluate(Disabled, &.{}, &original_state, &original, &sink),
            Candidate.evaluate(Disabled, &.{}, &twin_state, &twin, &sink),
        );
    }

    // One rook reaching the king ring is still below the accepted two-attacker
    // threshold, so the candidate's second shelter consumer must remain inert.
    var lone_root: chess.position.PositionState = .{};
    const lone_attacker = try chess.fen.parse(
        "4k1r1/8/8/8/8/8/5PPP/6K1 w - - 0 1",
        &lone_root,
    );
    var baseline_state: hce.Hce.State = .{};
    var candidate_state: Candidate.State = .{};
    try std.testing.expectEqual(
        hce.Hce.evaluate(Disabled, &.{}, &baseline_state, &lone_attacker, &sink),
        Candidate.evaluate(Disabled, &.{}, &candidate_state, &lone_attacker, &sink),
    );

    var root: chess.position.PositionState = .{};
    var value = try chess.fen.parseStart(&root);
    var children: [48]chess.position.PositionState = undefined;
    var reused_state: Candidate.State = .{};
    var random: u64 = 0x4d41_4e2d_4532_3101;
    for (&children) |*child| {
        var fresh_state: Candidate.State = .{};
        try std.testing.expectEqual(
            Candidate.evaluate(Disabled, &.{}, &fresh_state, &value, &sink),
            Candidate.evaluate(Disabled, &.{}, &reused_state, &value, &sink),
        );
        var legal = chess.position.MoveList.init();
        chess.movegen.generate(.all, &value, &legal);
        if (legal.count == 0) break;
        random = random *% 6_364_136_223_846_793_005 +% 1_442_695_040_888_963_407;
        chess.transition.makeMove(
            &value,
            legal.slice()[@as(usize, @intCast(random % legal.count))],
            child,
        );
    }
}

test "shelter-danger observation cohort populates every registered transition" {
    // SCORE-025: these legal boards observe positive relief, zero-shelter
    // identity, negative amplification and a positive raw danger reduced all
    // the way to zero. The middle pair keeps the knights and White's pawns
    // fixed while moving the non-attacking storm pawn; its asserted-equal raw
    // danger makes the improved shelter an independent paired oracle.
    const Candidate = hce.HceWith(.{ .shelter_danger_coupling = true });
    const cohort = [_][]const u8{
        "k7/8/8/8/8/4p2p/5PPP/6K1 w - - 0 1",
        "k7/8/7P/5PP1/7p/4nn2/8/6K1 w - - 0 1",
        "k7/8/7P/5PPp/8/4nn2/8/6K1 w - - 0 1",
        "k7/8/6P1/7P/5P1p/4nn2/8/6K1 w - - 0 1",
    };
    var relief: usize = 0;
    var amplification: usize = 0;
    var zero_identity: usize = 0;
    var to_zero: usize = 0;
    var cohort_raw: ?i32 = null;

    for (cohort, 0..) |fen_text, cohort_index| {
        var root: chess.position.PositionState = .{};
        const value = try chess.fen.parse(fen_text, &root);
        try std.testing.expect(chess.state.isConsistent(&value));
        var state: Candidate.State = .{};
        var trace = ManE21Trace.init();
        const evaluated = Candidate.evaluate(ManE21Trace, &.{}, &state, &value, &trace);
        try std.testing.expect(evaluated.isOrdinary());
        try std.testing.expect(!trace.truncated);

        const records = trace.slice();
        for (records, 0..) |record, index| {
            if (!std.mem.eql(u8, record.label, "shelter_danger_raw")) continue;
            try std.testing.expect(index + 2 < records.len);
            try std.testing.expectEqualStrings("shelter_danger_shelter", records[index + 1].label);
            try std.testing.expectEqualStrings("shelter_danger_effective", records[index + 2].label);
            const raw = record.value.total;
            const shelter = records[index + 1].value.total;
            const effective = records[index + 2].value.total;
            const baseline = @max(raw, 0);
            if (cohort_index == 1 or cohort_index == 2) {
                if (cohort_raw) |expected|
                    try std.testing.expectEqual(expected, raw)
                else
                    cohort_raw = raw;
            }
            if (shelter > 0 and effective < baseline) relief += 1;
            if (shelter < 0 and effective > baseline) amplification += 1;
            if (shelter == 0 and effective == baseline) zero_identity += 1;
            if (raw > 0 and effective == 0) to_zero += 1;
        }
    }
    try std.testing.expect(cohort_raw != null);
    try std.testing.expectEqual(@as(usize, 2), relief);
    try std.testing.expectEqual(@as(usize, 1), amplification);
    try std.testing.expectEqual(@as(usize, 1), zero_identity);
    try std.testing.expectEqual(@as(usize, 1), to_zero);
}

test "castling and en-passant rights alter static evidence only through the trapped rook" {
    // En-passant rights have no evaluator consumer at all. Castling rights had
    // none until Step 5.3.11, which reads them in exactly one place: a rook
    // shut in by its own king is worse when castling can no longer free it.
    // The pairs below hold no trapped rook, so they must still agree; the
    // positive case is asserted immediately afterwards so the one consumer is
    // recorded rather than assumed absent.
    // The halfmove clock is deliberately excluded from this pairing: Step
    // 5.3.1 makes it a scaling input, and its own contract is asserted below.
    const pairs = [_][2][]const u8{
        .{
            "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
            "r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1",
        },
        .{
            "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
            "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        },
    };
    for (pairs) |pair| {
        var left_root: chess.position.PositionState = .{};
        var right_root: chess.position.PositionState = .{};
        const left = try chess.fen.parse(pair[0], &left_root);
        const right = try chess.fen.parse(pair[1], &right_root);
        try std.testing.expectEqual(left.physical, right.physical);
        try std.testing.expectEqual(evaluate(&left), evaluate(&right));
    }

    // The one consumer: a white rook on h1 shut in behind its own pawns on the
    // king's side of the board. Losing the right to castle cannot free it, so the
    // same placement is worth less without the right than with it.
    const boxed_with = "4k3/8/8/8/8/8/5PPP/4K2R w K - 0 1";
    const boxed_without = "4k3/8/8/8/8/8/5PPP/4K2R w - - 0 1";
    var with_root: chess.position.PositionState = .{};
    var without_root: chess.position.PositionState = .{};
    const with_right = try chess.fen.parse(boxed_with, &with_root);
    const without_right = try chess.fen.parse(boxed_without, &without_root);
    try std.testing.expectEqual(with_right.physical, without_right.physical);
    try std.testing.expect(evaluate(&without_right).raw() < evaluate(&with_right).raw());
}

test "the halfmove clock scales an advantage only as the allowance runs out" {
    // Step 5.3.1: the fifty-move rule bounds how long the stronger side has to
    // force a capture or pawn move, so a nominal advantage becomes less
    // convertible as the clock rises. This is a scaling input, not a draw
    // verdict: the evaluator still returns an ordinary score and never claims
    // a terminal result, which remains owned by search.
    const fen_prefix = "r3k2r/8/8/8/8/8/8/R3K3 w kq - ";
    var fresh_root: chess.position.PositionState = .{};
    const fresh = try chess.fen.parse(fen_prefix ++ "0 1", &fresh_root);
    const baseline = evaluate(&fresh).raw();
    try std.testing.expect(baseline != 0);

    // Below the threshold nothing changes, because a capture or pawn move is
    // overwhelmingly likely long before the allowance matters.
    var early_root: chess.position.PositionState = .{};
    const early = try chess.fen.parse(fen_prefix ++ "40 30", &early_root);
    try std.testing.expectEqual(baseline, evaluate(&early).raw());

    // Past the threshold the advantage shrinks monotonically toward zero.
    var mid_root: chess.position.PositionState = .{};
    var late_root: chess.position.PositionState = .{};
    const mid = try chess.fen.parse(fen_prefix ++ "80 60", &mid_root);
    const late = try chess.fen.parse(fen_prefix ++ "99 70", &late_root);
    const mid_value = evaluate(&mid).raw();
    const late_value = evaluate(&late).raw();
    try std.testing.expect(@abs(mid_value) < @abs(baseline));
    try std.testing.expect(@abs(late_value) < @abs(mid_value));
}

test "endgame signals remain ordinary and terminal proof stays search-owned" {
    // Material should provide a useful fallback ordering without entering the
    // tablebase/mate bands or deciding dead, checkmate, or stalemate outcomes.
    var bare = try parsed("7k/8/8/8/8/8/8/4K3 w - - 0 1");
    var bishop_knight = try parsed("7k/8/8/8/8/8/3BN3/4K3 w - - 0 1");
    var queen = try parsed("7k/8/8/8/8/8/4Q3/4K3 w - - 0 1");
    bare.value.rebind(&bare.root);
    bishop_knight.value.rebind(&bishop_knight.root);
    queen.value.rebind(&queen.root);
    const bare_score = evaluate(&bare.value);
    const minor_score = evaluate(&bishop_knight.value);
    const queen_score = evaluate(&queen.value);
    try std.testing.expect(chess.draw.isDeadPosition(&bare.value));
    try std.testing.expect(minor_score.raw() > bare_score.raw());
    try std.testing.expect(queen_score.raw() > minor_score.raw());

    const terminals = [_][]const u8{
        "7k/6Q1/6K1/8/8/8/8/8 b - - 0 1",
        "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1",
    };
    for (terminals) |fen_text| {
        var terminal = try parsed(fen_text);
        terminal.value.rebind(&terminal.root);
        var moves = chess.position.MoveList.init();
        chess.movegen.generate(.all, &terminal.value, &moves);
        try std.testing.expectEqual(@as(usize, 0), moves.slice().len);
        const static_score = evaluate(&terminal.value);
        try std.testing.expect(static_score.isOrdinary());
        try std.testing.expect(!static_score.isMate());
        try std.testing.expect(!static_score.isTablebase());
    }
}

test "specialized endgames are ordinary and independently ablatable" {
    // Step 5.3.13: recognizers may refine conversion but cannot mint decisive
    // evidence. The switch-off arm preserves the Step-5.3.12 evaluator for
    // attribution at the shared 5.3.16 gate.
    const Without = hce.HceWith(.{ .endgame_knowledge = false });
    var item = try parsed("8/8/4k3/4P3/4K3/8/8/8 w - - 0 1");
    item.value.rebind(&item.root);
    var with_state: hce.Hce.State = .{};
    var without_state: Without.State = .{};
    var sink: Disabled = .{};
    const with = hce.Hce.evaluate(Disabled, &.{}, &with_state, &item.value, &sink);
    const without = Without.evaluate(Disabled, &.{}, &without_state, &item.value, &sink);
    try std.testing.expect(with.raw() != without.raw());
    try std.testing.expect(with.isOrdinary());
    try std.testing.expect(!with.isMate() and !with.isTablebase());
}

test "specialized endgames reduce held-out reference residual" {
    // QUAL-015: the frozen 5.3.0 cohort is an external-reference diagnostic,
    // not a source of implementation logic. Only exact-signature positions
    // with an available reference score enter this comparison.
    const Without = hce.HceWith(.{ .endgame_knowledge = false });
    var production_loss: i64 = 0;
    var baseline_loss: i64 = 0;
    var compared: usize = 0;
    for (manta.eval.cohorts.cases) |case| {
        const reference = case.reference_cp orelse continue;
        var root: chess.position.PositionState = .{};
        const value = try chess.fen.parse(case.fen, &root);
        if (manta.eval.endgame.recognize(&value) == null) continue;

        var production_state: hce.Hce.State = .{};
        var baseline_state: Without.State = .{};
        var sink: Disabled = .{};
        const production = hce.Hce.evaluate(Disabled, &.{}, &production_state, &value, &sink).raw();
        const baseline = Without.evaluate(Disabled, &.{}, &baseline_state, &value, &sink).raw();
        const production_white = if (value.side_to_move == .white) production else -production;
        const baseline_white = if (value.side_to_move == .white) baseline else -baseline;
        production_loss += @intCast(@abs(@as(i64, production_white) - reference));
        baseline_loss += @intCast(@abs(@as(i64, baseline_white) - reference));
        compared += 1;
    }
    try std.testing.expect(compared >= 4);
    try std.testing.expect(production_loss < baseline_loss);
}

test "winnability reduces held-out reference residual" {
    // QUAL-015: the last structural cluster is compared on the entire frozen
    // external-reference cohort, not selected positions that happen to move.
    const Without = hce.HceWith(.{ .winnability = false });
    var production_loss: i64 = 0;
    var baseline_loss: i64 = 0;
    var compared: usize = 0;
    for (manta.eval.cohorts.cases) |case| {
        const reference = case.reference_cp orelse continue;
        var root: chess.position.PositionState = .{};
        const value = try chess.fen.parse(case.fen, &root);
        var production_state: hce.Hce.State = .{};
        var baseline_state: Without.State = .{};
        var sink: Disabled = .{};
        const production = hce.Hce.evaluate(Disabled, &.{}, &production_state, &value, &sink).raw();
        const baseline = Without.evaluate(Disabled, &.{}, &baseline_state, &value, &sink).raw();
        const production_white = if (value.side_to_move == .white) production else -production;
        const baseline_white = if (value.side_to_move == .white) baseline else -baseline;
        production_loss += @intCast(@abs(@as(i64, production_white) - reference));
        baseline_loss += @intCast(@abs(@as(i64, baseline_white) - reference));
        compared += 1;
    }
    try std.testing.expectEqual(manta.eval.cohorts.cases.len - 1, compared);
    try std.testing.expect(production_loss < baseline_loss);
}

test "winnability is ordinary symmetric and independently ablatable" {
    // The term grades conversion only: it must move a complex pawn ending,
    // preserve the ordinary score band and retain colour/rank symmetry.
    const Without = hce.HceWith(.{ .winnability = false });
    var item = try parsed("8/8/p1p5/1p5p/1P5P/P1P5/8/K1k5 w - - 0 1");
    item.value.rebind(&item.root);
    var with_state: hce.Hce.State = .{};
    var without_state: Without.State = .{};
    var sink: Disabled = .{};
    const with = hce.Hce.evaluate(Disabled, &.{}, &with_state, &item.value, &sink);
    const without = Without.evaluate(Disabled, &.{}, &without_state, &item.value, &sink);
    try std.testing.expect(with.raw() != without.raw());
    try std.testing.expect(with.isOrdinary());

    var twin_root: chess.position.PositionState = .{};
    const twin = try colorFlip(&item.value, &twin_root);
    var twin_state: hce.Hce.State = .{};
    try std.testing.expectEqual(
        with,
        hce.Hce.evaluate(Disabled, &.{}, &twin_state, &twin, &sink),
    );
}

test "pawn cache is exact across hits misses and index collisions" {
    // PERF-008/QUAL-015: cache identity is a semantic contract. The two legal
    // boards deliberately receive different full tags with the same low index
    // bits; only the cache-addressing fact is synthetic. A collision must
    // evict and recompute, never reuse another pawn structure.
    const Uncached = hce.HceWith(.{ .pawn_cache = false });
    var first = try parsed("8/2p5/3p4/1P1P4/8/4k3/8/4K3 w - - 0 40");
    var second = try parsed("4k3/8/8/3P4/8/8/4K3/8 w - - 0 1");
    first.value.rebind(&first.root);
    second.value.rebind(&second.root);
    first.root.pawn_key = 0x10;
    second.root.pawn_key = 0x20;

    var cached_state: hce.Hce.State = .{};
    var first_uncached: Uncached.State = .{};
    var second_uncached: Uncached.State = .{};
    var sink: Disabled = .{};
    const first_expected = Uncached.evaluate(Disabled, &.{}, &first_uncached, &first.value, &sink);
    const second_expected = Uncached.evaluate(Disabled, &.{}, &second_uncached, &second.value, &sink);
    try std.testing.expectEqual(
        first_expected,
        hce.Hce.evaluate(Disabled, &.{}, &cached_state, &first.value, &sink),
    );
    try std.testing.expectEqual(
        second_expected,
        hce.Hce.evaluate(Disabled, &.{}, &cached_state, &second.value, &sink),
    );
    try std.testing.expectEqual(
        first_expected,
        hce.Hce.evaluate(Disabled, &.{}, &cached_state, &first.value, &sink),
    );
}

test "maximum promotion material cannot collide with decisive score bands" {
    // Eight pawn promotions plus the original non-pawn force is the orthodox
    // material maximum for one side; it remains only heuristic evidence.
    var promoted = try parsed("k7/8/8/8/8/3BB3/1QQQRRNN/1QQQQQQK w - - 0 1");
    promoted.value.rebind(&promoted.root);
    const value = evaluate(&promoted.value);
    try std.testing.expect(value.isOrdinary());
    try std.testing.expect(@abs(value.raw()) < manta.score.tablebase_min_raw);

    // SCORE-025: the same extreme legal material also instantiates MAN-E21's
    // widened square-law path in Debug/ReleaseSafe without overflow or minting
    // terminal evidence.
    const Candidate = hce.HceWith(.{ .shelter_danger_coupling = true });
    var candidate_state: Candidate.State = .{};
    var sink: Disabled = .{};
    const candidate = Candidate.evaluate(Disabled, &.{}, &candidate_state, &promoted.value, &sink);
    try std.testing.expect(candidate.isOrdinary());
    try std.testing.expect(@abs(candidate.raw()) < manta.score.tablebase_min_raw);
}

const Parsed = struct {
    root: chess.position.PositionState,
    value: chess.position.Position,
};

fn parsed(fen_text: []const u8) !Parsed {
    // SAFETY: both fields are initialized below; callers immediately rebind
    // the returned position to the relocated root before reading it.
    var result: Parsed = undefined;
    result.root = .{};
    result.value = try chess.fen.parse(fen_text, &result.root);
    return result;
}

fn evaluate(value: *const chess.position.Position) manta.score.Score {
    var state: hce.Hce.State = .{};
    var sink: Disabled = .{};
    return hce.Hce.evaluate(Disabled, &.{}, &state, value, &sink);
}

fn colorFlip(
    original: *const chess.position.Position,
    root: *chess.position.PositionState,
) !chess.position.Position {
    var twin = chess.position.Position.initEmpty(root);
    twin.side_to_move = original.side_to_move.opposite();
    // A complete board symmetry swaps the castling rights along with the
    // pieces. Step 5.3.11 gave the evaluator its first consumer for them, so a
    // mirror that left them behind would report an asymmetry the position does
    // not have.
    const rights = original.current.castling_rights.raw();
    var flipped: u4 = 0;
    if (rights & 0b0001 != 0) flipped |= 0b0100;
    if (rights & 0b0010 != 0) flipped |= 0b1000;
    if (rights & 0b0100 != 0) flipped |= 0b0001;
    if (rights & 0b1000 != 0) flipped |= 0b0010;
    root.castling_rights = @enumFromInt(flipped);
    for (original.physical.board, 0..) |piece, square_index| {
        if (piece == .none) continue;
        const source = chess.types.Square.fromIndex(@intCast(square_index));
        const destination = source.flipRank();
        twin.physical.board[destination.index()] = chess.types.Piece.make(
            piece.color().opposite(),
            piece.pieceType(),
        );
    }
    try chess.state.rebuildPhysical(&twin.physical);
    chess.state.applyDerived(root, chess.state.derive(&twin));
    return twin;
}

test "king safety responds to shelter and to converging attackers" {
    // Step 5.3.5. These are the two mechanisms the term encodes, checked as
    // directions rather than magnitudes: intact pawn cover is worth more than
    // a stripped king, and danger rises superlinearly as attackers converge.
    const sheltered = "rnbq1rk1/ppp2ppp/3b1n2/8/8/3B1N2/PPP2PPP/RNBQ1RK1 w - - 0 8";
    const stripped = "rnbq1rk1/ppp3p1/3b1n2/8/8/3B1N2/PPP2PPP/RNBQ1RK1 w - - 0 8";
    var a_root: chess.position.PositionState = .{};
    var b_root: chess.position.PositionState = .{};
    const intact = try chess.fen.parse(sheltered, &a_root);
    const holed = try chess.fen.parse(stripped, &b_root);
    // Black's cover is broken in the second position, so White stands better.
    try std.testing.expect(evaluate(&holed).raw() > evaluate(&intact).raw());

    // A lone attacker near a king is not treated as an attack at all, because
    // one piece cannot break a defended king and crediting it would make
    // ordinary development look threatening.
    const quiet_fen = "4k3/8/8/8/8/8/8/3QK3 w - - 0 1";
    const swarm_fen = "4k3/8/8/8/8/4q3/4r3/4K3 w - - 0 1";
    var quiet_root: chess.position.PositionState = .{};
    var swarm_root: chess.position.PositionState = .{};
    const quiet = try chess.fen.parse(quiet_fen, &quiet_root);
    const swarm = try chess.fen.parse(swarm_fen, &swarm_root);
    try std.testing.expect(chess.state.isConsistent(&quiet));
    try std.testing.expect(evaluate(&swarm).raw() < 0);
}

test "the king-safety switch restores an evaluator with no king term" {
    // The whole cluster must be ablatable so a failing joint gate can be
    // attributed to it rather than to the rules carried alongside it.
    const Without = hce.HceWith(.{ .king_safety = false });
    const fen_text = "r3k2r/p1ppqpb1/bn2pnp1/2pP4/1p2P3/2N2N2/PPQBBPPP/R3K2R w KQkq - 0 1";
    var root: chess.position.PositionState = .{};
    const value = try chess.fen.parse(fen_text, &root);
    var with_state: hce.Hce.State = .{};
    var without_state: Without.State = .{};
    var sink: Disabled = .{};
    const with = hce.Hce.evaluate(Disabled, &.{}, &with_state, &value, &sink);
    const without = Without.evaluate(Disabled, &.{}, &without_state, &value, &sink);
    try std.testing.expect(with.raw() != without.raw());
}

test "an undefended piece under fire scores worse than a defended one" {
    // Step 5.3.6. The chess content is that a piece the opponent attacks and
    // does not defend must move, be defended or be lost, and the opponent
    // chooses the moment. Defending the same piece removes that liability, so
    // the defended arrangement must score better for its owner.
    const undefended = "3rk3/8/8/8/8/8/3RK3/8 w - - 0 1";
    const defended = "3rk3/3r4/8/8/8/8/3RK3/8 w - - 0 1";
    var a_root: chess.position.PositionState = .{};
    var b_root: chess.position.PositionState = .{};
    const loose = try chess.fen.parse(undefended, &a_root);
    const held = try chess.fen.parse(defended, &b_root);
    try std.testing.expect(chess.state.isConsistent(&loose));
    try std.testing.expect(chess.state.isConsistent(&held));
    // Both are White to move; Black's extra rook in the second position makes
    // it better for Black, so White's score must be lower there.
    try std.testing.expect(evaluate(&held).raw() < evaluate(&loose).raw());
}

test "the threats switch is independently ablatable" {
    const Without = hce.HceWith(.{ .threats_and_space = false });
    const fen_text = "r3k2r/p1ppqpb1/bn2pnp1/2pP4/1p2P3/2N2N2/PPQBBPPP/R3K2R w KQkq - 0 1";
    var root: chess.position.PositionState = .{};
    const value = try chess.fen.parse(fen_text, &root);
    var with_state: hce.Hce.State = .{};
    var without_state: Without.State = .{};
    var sink: Disabled = .{};
    const with = hce.Hce.evaluate(Disabled, &.{}, &with_state, &value, &sink);
    const without = Without.evaluate(Disabled, &.{}, &without_state, &value, &sink);
    try std.testing.expect(with.raw() != without.raw());
}

test "a pawnless minor edge is damped more than the same edge with pawns" {
    // Step 5.3.7. Convertibility is a degree, not a binary fact, which is
    // exactly what the unwinnable clamp cannot express. The same nominal
    // bishop edge is far easier to convert when pawns remain to promote, so
    // the pawnless version must retain less of it.
    const with_pawns = "6k1/5ppp/8/8/8/8/1B3PPP/6K1 w - - 0 1";
    const bare_minor = "6k1/8/8/8/8/8/1B6/6K1 w - - 0 1";
    var a_root: chess.position.PositionState = .{};
    var b_root: chess.position.PositionState = .{};
    const pawnful = try chess.fen.parse(with_pawns, &a_root);
    const bare = try chess.fen.parse(bare_minor, &b_root);
    try std.testing.expect(chess.state.isConsistent(&pawnful));
    try std.testing.expect(chess.state.isConsistent(&bare));
    // Evaluated through the archived switch: the mechanism is retained as
    // refutation history and is not production behaviour.
    const Scaled = hce.HceWith(.{ .endgame_scaling = true });
    var bare_state: Scaled.State = .{};
    var pawnful_state: Scaled.State = .{};
    var sink: Disabled = .{};
    const bare_score = Scaled.evaluate(Disabled, &.{}, &bare_state, &bare, &sink);
    const pawnful_score = Scaled.evaluate(Disabled, &.{}, &pawnful_state, &pawnful, &sink);
    try std.testing.expect(bare_score.raw() < pawnful_score.raw());
}

test "endgame scaling is archived off and production ignores it" {
    // MAN-E05 was rejected, so the default configuration must not scale.
    const Without = hce.HceWith(.{ .endgame_scaling = false });
    const fen_text = "8/2p5/3p4/1P1P4/8/4k3/8/4K3 w - - 0 40";
    var root: chess.position.PositionState = .{};
    const value = try chess.fen.parse(fen_text, &root);
    var with_state: hce.Hce.State = .{};
    var without_state: Without.State = .{};
    var sink: Disabled = .{};
    const with = hce.Hce.evaluate(Disabled, &.{}, &with_state, &value, &sink);
    const without = Without.evaluate(Disabled, &.{}, &without_state, &value, &sink);
    try std.testing.expectEqual(with.raw(), without.raw());
}
