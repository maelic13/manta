//! Frozen Step-3.1 evaluator conformance corpus.
const std = @import("std");
const manta = @import("manta");

const hce = manta.eval.hce;
const chess = manta.chess;
const TraceBuffer = manta.eval.trace.Buffer(hce.TraceValue, 12);

/// Labels of the tapered components, in emission order. Schema v3 removed the
/// rejected imbalance slot; `passed` follows the attack maps it reads and
/// `winnability` consumes all earlier structural facts.
const labels = [_][]const u8{
    "material_pst",
    "pawns",
    "activity",
    "passed",
    "king_safety",
    "pawn_threats",
    "threats_space",
    "winnability",
};

const Case = struct {
    fen: []const u8,
    components: [labels.len]hce.Tapered,
    phase: u8,
    reference_total: i32,
    total: i32,
};

const corpus = [_]Case{
    .{
        .fen = chess.fen.start_position,
        .components = @splat(.{}),
        .phase = 24,
        .reference_total = 20,
        // Step 5.3.16 fits the side-to-move tempo with every other supported
        // linear coordinate; all symmetric components remain exactly zero.
        .total = 15,
    },
    .{
        .fen = "r3k2r/p1ppqpb1/bn2pnp1/2pP4/1p2P3/2N2N2/PPQBBPPP/R3K2R w KQkq - 0 1",
        .components = .{
            .{ .middlegame = -32, .endgame = -159 },
            .{ .middlegame = -15, .endgame = -18 },
            .{ .middlegame = -74, .endgame = 3 },
            .{},
            .{ .middlegame = -17, .endgame = 0 },
            .{ .middlegame = -56, .endgame = -24 },
            .{ .middlegame = -62, .endgame = -8 },
            .{ .endgame = -3 },
        },
        .phase = 24,
        .reference_total = -73,
        // The joint fit intentionally moves all supported terms together.
        // This tiny corpus freezes component emission; the independent
        // 166,667-position validation split, not this one case, owns loss.
        .total = -241,
    },
    .{
        .fen = "8/2p5/3p4/1P1P4/8/4k3/8/4K3 w - - 0 40",
        .components = .{
            .{ .middlegame = 85, .endgame = -38 },
            .{ .middlegame = -8, .endgame = -18 },
            .{},
            .{},
            .{ .middlegame = -13, .endgame = -17 },
            .{},
            .{},
            .{ .endgame = 9 },
        },
        .phase = 0,
        .reference_total = -70,
        // Step 5.3.15R.1 gives each doubled, isolated or backward pawn one
        // weakness owner instead of charging overlapping classifications.
        .total = -49,
    },
    .{
        .fen = "4k3/8/8/3P4/8/8/4K3/8 w - - 0 1",
        .components = .{
            .{ .middlegame = 50, .endgame = 130 },
            .{ .middlegame = -5, .endgame = -18 },
            .{},
            .{ .middlegame = 19, .endgame = 57 },
            .{ .middlegame = 51, .endgame = -1 },
            .{},
            .{},
            .{ .endgame = -13 },
        },
        .phase = 0,
        .reference_total = 0,
        // The passer is scored where it stands: both kings are counted, and
        // each attacked or defended path square is graded independently.
        // Step 5.3.15R.4's exact KPK bitbase classifies this as drawn; only
        // the ordinary side-to-move tempo remains in the final score.
        .total = 15,
    },
    .{
        .fen = "4k3/8/8/8/8/2n5/3P4/4K3 b - - 0 1",
        .components = .{
            .{ .middlegame = -274, .endgame = -210 },
            .{ .middlegame = -5, .endgame = -18 },
            .{ .middlegame = -35, .endgame = -32 },
            .{ .middlegame = 6, .endgame = 9 },
            .{ .middlegame = 34, .endgame = -11 },
            .{ .middlegame = 56, .endgame = 24 },
            .{ .middlegame = 205, .endgame = 113 },
            .{ .endgame = 41 },
        },
        .phase = 1,
        .reference_total = 0,
        // Step 5.3.1: Black leads on material but owns only a knight and
        // cannot force mate, so the advantage is clamped to a draw.
        .total = 0,
    },
};

test "bootstrap HCE matches the frozen component corpus" {
    // QUAL-015: exact values are a named conformance snapshot. Update only
    // with an ADR, an EXPERIMENTS entry, and an intentional corpus review.
    for (corpus) |expected| {
        var root_state: chess.position.PositionState = .{};
        const value = try chess.fen.parse(expected.fen, &root_state);
        var state: hce.Hce.State = .{};
        var traced = TraceBuffer.init();
        const traced_score = hce.Hce.evaluate(TraceBuffer, &.{}, &state, &value, &traced);
        var disabled: manta.eval.trace.Disabled = .{};
        const plain_score = hce.Hce.evaluate(
            manta.eval.trace.Disabled,
            &.{},
            &state,
            &value,
            &disabled,
        );

        try std.testing.expectEqual(expected.total, traced_score.raw());
        try std.testing.expectEqual(traced_score, plain_score);
        try std.testing.expect(!traced.truncated);
        try std.testing.expectEqual(@as(usize, labels.len + 2), traced.slice().len);
        for (labels, expected.components, 0..) |label, component, index| {
            try std.testing.expectEqualStrings(label, traced.slice()[index].label);
            try std.testing.expectEqual(component, traced.slice()[index].value.tapered);
        }
        try std.testing.expectEqual(expected.phase, traced.slice()[labels.len].value.phase);
        try std.testing.expectEqual(expected.total, traced.slice()[labels.len + 1].value.total);
    }
}

test "corpus retains the pinned whole-score reference" {
    // This is comparative evidence only; ADR-0016 explains every non-parity
    // category and forbids treating either total as an independent oracle.
    const expected = [_]i32{ 20, -73, -70, 0, 0 };
    for (corpus, expected) |case, reference_total|
        try std.testing.expectEqual(reference_total, case.reference_total);
}

test "static evaluation scales by the fifty-move clock without claiming a draw" {
    // SCORE-001 forbids the evaluator from manufacturing terminal, repetition
    // or rule-draw *evidence*; it does not forbid reading the halfmove clock.
    // Step 5.3.1 uses the remaining allowance as a scaling input, so a stale
    // clock must reduce a nominal advantage while the result stays an ordinary
    // score that search alone can turn into a draw verdict.
    var fresh_state: chess.position.PositionState = .{};
    var old_state: chess.position.PositionState = .{};
    const fresh = try chess.fen.parse("4k3/8/8/3P4/8/8/4K3/8 w - - 0 1", &fresh_state);
    const old = try chess.fen.parse("4k3/8/8/3P4/8/8/4K3/8 w - - 99 80", &old_state);
    var evaluator_state: hce.Hce.State = .{};
    var sink: manta.eval.trace.Disabled = .{};
    const fresh_score = hce.Hce.evaluate(manta.eval.trace.Disabled, &.{}, &evaluator_state, &fresh, &sink);
    const old_score = hce.Hce.evaluate(manta.eval.trace.Disabled, &.{}, &evaluator_state, &old, &sink);
    try std.testing.expect(fresh_score.raw() > 0);
    try std.testing.expect(old_score.raw() >= 0);
    try std.testing.expect(old_score.raw() < fresh_score.raw());
    // Still an ordinary score: the evaluator never enters a decisive band.
    try std.testing.expect(old_score.isOrdinary() and fresh_score.isOrdinary());
}

test "an advantage its holder cannot force mate with is scored as drawn" {
    // Step 5.3.1: material a side cannot mate with is not convertible, so the
    // static score is exactly zero rather than a scaled remainder. This is a
    // statement about reachable outcomes, not a tuned discount, and it never
    // prevents search from reporting a real mate the defender walks into.
    const drawn = [_][]const u8{
        "4k3/8/8/8/8/8/8/KNN5 w - - 0 1",
        "4k3/8/8/8/8/8/8/KN6 w - - 0 1",
        "4k3/8/8/8/8/8/8/KB6 w - - 0 1",
        // Black leads by a knight but cannot mate with it, so the nominal
        // advantage is worthless even though White still owns a pawn.
        "4k3/8/8/8/8/2n5/3P4/4K3 b - - 0 1",
    };
    var evaluator_state: hce.Hce.State = .{};
    var sink: manta.eval.trace.Disabled = .{};
    for (drawn) |fen_text| {
        var root: chess.position.PositionState = .{};
        const value = try chess.fen.parse(fen_text, &root);
        const result = hce.Hce.evaluate(manta.eval.trace.Disabled, &.{}, &evaluator_state, &value, &sink);
        try std.testing.expectEqual(@as(i32, 0), result.raw());
    }

    // Material that can force mate keeps its advantage.
    const winnable = [_][]const u8{
        "4k3/8/8/8/8/8/8/KBN5 w - - 0 1",
        "4k3/8/8/8/8/8/8/KQ6 w - - 0 1",
        "4k3/8/8/8/8/8/8/KR6 w - - 0 1",
    };
    for (winnable) |fen_text| {
        var root: chess.position.PositionState = .{};
        const value = try chess.fen.parse(fen_text, &root);
        const result = hce.Hce.evaluate(manta.eval.trace.Disabled, &.{}, &evaluator_state, &value, &sink);
        try std.testing.expect(result.raw() > 0);
    }
}

test "disabling the score-foundation rules restores the earlier evaluator" {
    // Both mechanisms must be independently ablatable, so a future audit can
    // attribute any change in playing evidence to one rule rather than to the
    // pair. With both disabled the evaluator reproduces its pre-5.3.1 values.
    const Legacy = hce.HceWith(.{ .insufficient_material = false, .rule_fifty_scaling = false });
    var legacy_state: Legacy.State = .{};
    var sink: manta.eval.trace.Disabled = .{};

    // The unwinnable ending scored its full nominal material before 5.3.1.
    var knights_root: chess.position.PositionState = .{};
    const knights = try chess.fen.parse("4k3/8/8/8/8/8/8/KNN5 w - - 0 1", &knights_root);
    const legacy_knights = Legacy.evaluate(manta.eval.trace.Disabled, &.{}, &legacy_state, &knights, &sink);
    try std.testing.expect(legacy_knights.raw() > 0);

    // A stale clock had no effect on the score before 5.3.1.
    var fresh_root: chess.position.PositionState = .{};
    var stale_root: chess.position.PositionState = .{};
    const fresh = try chess.fen.parse("4k3/8/8/3P4/8/8/4K3/8 w - - 0 1", &fresh_root);
    const stale = try chess.fen.parse("4k3/8/8/3P4/8/8/4K3/8 w - - 99 80", &stale_root);
    try std.testing.expectEqual(
        Legacy.evaluate(manta.eval.trace.Disabled, &.{}, &legacy_state, &fresh, &sink),
        Legacy.evaluate(manta.eval.trace.Disabled, &.{}, &legacy_state, &stale, &sink),
    );

    // Each rule is separable: enabling only the clamp leaves the clock inert.
    const ClampOnly = hce.HceWith(.{ .insufficient_material = true, .rule_fifty_scaling = false });
    var clamp_state: ClampOnly.State = .{};
    try std.testing.expectEqual(
        ClampOnly.evaluate(manta.eval.trace.Disabled, &.{}, &clamp_state, &fresh, &sink),
        ClampOnly.evaluate(manta.eval.trace.Disabled, &.{}, &clamp_state, &stale, &sink),
    );
    var clamp_knights_state: ClampOnly.State = .{};
    const clamped = ClampOnly.evaluate(manta.eval.trace.Disabled, &.{}, &clamp_knights_state, &knights, &sink);
    try std.testing.expectEqual(@as(i32, 0), clamped.raw());
}
