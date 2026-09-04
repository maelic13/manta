//! Typed Syzygy WDL/DTZ probe contract and reserved-band score conversion.
//!
//! This module is the inward boundary: it owns what tablebase evidence *means*
//! to search and carries no file, library or allocation dependency. The vendored
//! probe implementation lives behind the engine-layer adapter, so search policy
//! stays testable without any tablebase file present.
const std = @import("std");
const chess = @import("../chess/root.zig");
const score = @import("../score.zig");
const types = @import("types.zig");

/// Win/draw/loss from the side to move, as Syzygy defines it. The cursed and
/// blessed variants are positions that are theoretically won or lost but whose
/// conversion needs more than the fifty-move allowance, so ordinary play scores
/// them as draws. Manta keeps them as distinct inputs rather than collapsing
/// them at the boundary: the rule-50 decision belongs to score conversion,
/// where it can be stated and tested, not to the probe adapter.
pub const Wdl = enum(u3) {
    loss = 0,
    blessed_loss = 1,
    draw = 2,
    cursed_win = 3,
    win = 4,

    /// Mirrors the value for the opponent. Used only by callers that probe a
    /// child position; it performs no rule-50 or score reasoning.
    pub fn negate(self: Wdl) Wdl {
        return switch (self) {
            .loss => .win,
            .blessed_loss => .cursed_win,
            .draw => .draw,
            .cursed_win => .blessed_loss,
            .win => .loss,
        };
    }

    /// True when the fifty-move rule, not the position, decides the outcome.
    pub fn isRuleFiftyBounded(self: Wdl) bool {
        return self == .cursed_win or self == .blessed_loss;
    }
};

/// Why a probe produced no usable evidence. Every variant is an ordinary,
/// expected outcome rather than an error condition: search continues normally.
pub const Unavailable = enum {
    /// No tablebase files are loaded, or the adapter is not initialized.
    not_loaded,
    /// The position has more pieces than the loaded tables cover.
    too_many_pieces,
    /// Syzygy tables assume no castling rights exist.
    castling_rights,
    /// WDL tables are indexed at a reset halfmove clock only.
    halfmove_clock,
    /// The probe reached the tables but they could not answer.
    probe_failed,
};

pub const ProbeResult = union(enum) {
    available: Wdl,
    unavailable: Unavailable,
};

/// Preconditions a WDL probe requires before the adapter is called at all.
///
/// These are contract facts, not tuning: Syzygy indexes positions without
/// castling rights, and the WDL tables are only valid where the halfmove clock
/// has been reset, because a nonzero clock changes which wins are reachable
/// within the fifty-move allowance. Checking them here keeps the reasoning in
/// the inward layer and means the adapter never has to interpret chess rules.
pub fn wdlPrecondition(
    piece_count: u8,
    largest: u8,
    castling_rights: bool,
    halfmove_clock: u16,
) ?Unavailable {
    if (largest == 0) return .not_loaded;
    if (piece_count > largest) return .too_many_pieces;
    if (castling_rights) return .castling_rights;
    if (halfmove_clock != 0) return .halfmove_clock;
    return null;
}

/// Converts tablebase evidence into a search score inside the reserved band.
///
/// The band holds exactly one value per search ply, so a win found closer to
/// the root outscores a deeper one and the engine still prefers to convert.
/// Tablebase magnitudes stay strictly below the mate band, because a proven
/// mate is more specific evidence than a proven win, and strictly above the
/// ordinary band, so no evaluation can imitate a proven result.
///
/// Cursed wins and blessed losses score exactly zero. Under the fifty-move
/// rule the game is drawn, and inventing a small bonus would let search chase
/// a conversion the rules do not allow.
pub fn toScore(wdl: Wdl, ply: usize, use_rule_fifty: bool) score.Score {
    std.debug.assert(ply < chess.types.max_ply);
    const distance: i32 = @intCast(@min(ply, chess.types.max_ply - 1));
    return switch (effectiveWdl(wdl, use_rule_fifty)) {
        .win => .{ .raw_value = score.tablebase_max_raw - distance },
        .loss => .{ .raw_value = -(score.tablebase_max_raw - distance) },
        .draw, .cursed_win, .blessed_loss => score.Score.zero,
    };
}

/// Collapses the fifty-move-bounded verdicts according to whether the rule is
/// being honoured. Analysis sometimes wants the theoretical result, which is
/// what disabling the rule asks for; ordinary play always honours it.
pub fn effectiveWdl(wdl: Wdl, use_rule_fifty: bool) Wdl {
    if (use_rule_fifty) return wdl;
    return switch (wdl) {
        .cursed_win => .win,
        .blessed_loss => .loss,
        else => wdl,
    };
}

/// The bound a tablebase verdict actually justifies.
///
/// A proven win is a *lower* bound, not an exact score. The tables report the
/// outcome, not the true distance to mate, so the score Manta constructs is a
/// stand-in whose magnitude is not the real value: the position is at least
/// this good. A proven loss is the mirror upper bound. Only a draw is exact,
/// because zero is the actual value of a drawn position.
pub fn toBound(wdl: Wdl, use_rule_fifty: bool) types.Bound {
    return switch (effectiveWdl(wdl, use_rule_fifty)) {
        .win => .lower,
        .loss => .upper,
        .draw, .cursed_win, .blessed_loss => .exact,
    };
}

/// Typed evidence a tablebase hit contributes to a node. It carries
/// `tablebase` provenance so no consumer can mistake it for a searched score,
/// and so the transposition table can apply its own storage authority rules.
pub fn toEvidence(wdl: Wdl, ply: usize, use_rule_fifty: bool) types.Evidence {
    return .{
        .value = toScore(wdl, ply, use_rule_fifty),
        .bound = toBound(wdl, use_rule_fifty),
        .provenance = .tablebase,
    };
}

/// True when a tablebase verdict already settles the node against its window.
///
/// A bound that does not cut is still information, but returning on it would
/// abandon the search without a principal variation and without a value more
/// precise than the band edge. The reference makes the same distinction, so a
/// non-cutting bound falls through to an ordinary search.
pub fn settlesNode(bound: types.Bound, value: i32, alpha: i32, beta: i32) bool {
    return switch (bound) {
        .exact => true,
        .lower => value >= beta,
        .upper => value <= alpha,
    };
}

/// Extra transposition depth a tablebase verdict earns. A proven result does
/// not become more true with depth, so its entry should outlive shallow
/// searched records instead of being re-probed from disk repeatedly.
pub const table_depth_bonus: u16 = 6;

/// The prober search consumes, supplied by the caller exactly like the
/// evaluator binding and stop control. Search never imports the probe adapter,
/// so the inward layer keeps no file or library dependency and every test can
/// run the complete policy without a tablebase present.
///
/// A conforming prober exposes `isLoaded()` and `probeWdl()`.
pub const Disabled = struct {
    pub inline fn isLoaded(_: *const Disabled) bool {
        return false;
    }

    pub inline fn probeWdl(
        _: *const Disabled,
        _: *const chess.position.Position,
    ) ProbeResult {
        return .{ .unavailable = .not_loaded };
    }
};

/// Shared inert prober for every caller that configures no tablebase.
pub var disabled: Disabled = .{};

/// Interior probing is worth its file-backed cost only where a hit can still
/// prune real work, and it must never claim authority a rules decision or an
/// exclusion probe already owns.
///
/// The root is excluded because root evidence has its own owner: publishing a
/// bare tablebase score there would replace the completed-iteration contract
/// that UCI, time management and the legal fallback all consume. Exclusion
/// nodes are excluded for the reason ADR-0029 already fixed: a same-position
/// singular probe produces no reusable evidence.
pub fn interiorProbeEligible(
    ply: usize,
    depth: u16,
    exclusion_node: bool,
    minimum_depth: u16,
    piece_count: u8,
    probe_limit: u8,
) bool {
    return ply != 0 and !exclusion_node and depth >= minimum_depth and
        piece_count <= probe_limit;
}

/// Largest table set Syzygy defines, and therefore the widest probe limit a
/// caller can meaningfully request.
pub const max_probe_limit: u8 = 7;

/// Default interior probe floor. Syzygy probing reads memory-mapped table
/// files, so probing the enormous shallow frontier would spend more time in
/// page faults than the saved subtrees are worth. This is a cost boundary, not
/// a chess claim: a deeper floor never changes which results are correct.
pub const default_probe_depth: u16 = 1;

/// One legal root move together with the rank the tables gave it. Higher is
/// strictly better; equal ranks are equally good outcomes.
pub const RankedRootMove = struct {
    move: chess.move.Move,
    rank: i32,
};

/// Keeps only the root moves that preserve the best available outcome.
///
/// This is the deliberate choice of *filtering* over *obeying*. The tables can
/// name a single distance-to-zero optimal move, but that move is frequently
/// bizarre to human eyes and throws away practical chances against imperfect
/// opposition, so Fathom itself recommends filtering. Restricting the root to
/// every equally-optimal move preserves the proven result while leaving the
/// choice among them to ordinary search.
///
/// Returns the number of moves written to `out`. A rank set that is empty, or
/// that would keep every move anyway, still writes the surviving moves so the
/// caller can treat the result uniformly.
pub fn retainBestRanked(
    ranked: []const RankedRootMove,
    out: *[chess.types.move_capacity]chess.move.Move,
) usize {
    if (ranked.len == 0) return 0;
    var best: i32 = ranked[0].rank;
    for (ranked[1..]) |candidate| best = @max(best, candidate.rank);
    var count: usize = 0;
    for (ranked) |candidate| {
        if (candidate.rank != best) continue;
        out[count] = candidate.move;
        count += 1;
    }
    return count;
}

test "root filtering keeps every equally optimal move and drops worse ones" {
    // FUNC-004/QUAL-014: filtering must never empty the root move list and
    // must never prefer one winning move over another equally winning one.
    // Search, not the table, chooses among proven-equal moves.
    const a = chess.move.Move.normal(.e2, .e4);
    const b = chess.move.Move.normal(.d2, .d4);
    const c = chess.move.Move.normal(.g1, .f3);
    var out: [chess.types.move_capacity]chess.move.Move = undefined;

    // Two winning moves and one losing move: both wins survive.
    const mixed = [_]RankedRootMove{
        .{ .move = a, .rank = 1000 },
        .{ .move = b, .rank = -1000 },
        .{ .move = c, .rank = 1000 },
    };
    try std.testing.expectEqual(@as(usize, 2), retainBestRanked(&mixed, &out));
    try std.testing.expectEqual(a.raw(), out[0].raw());
    try std.testing.expectEqual(c.raw(), out[1].raw());

    // All equal: nothing is filtered away, so search behaves normally.
    const equal = [_]RankedRootMove{
        .{ .move = a, .rank = 0 },
        .{ .move = b, .rank = 0 },
    };
    try std.testing.expectEqual(@as(usize, 2), retainBestRanked(&equal, &out));

    // A lost position still yields a legal move to play rather than nothing.
    const lost = [_]RankedRootMove{
        .{ .move = a, .rank = -1000 },
        .{ .move = b, .rank = -900 },
    };
    try std.testing.expectEqual(@as(usize, 1), retainBestRanked(&lost, &out));
    try std.testing.expectEqual(b.raw(), out[0].raw());

    try std.testing.expectEqual(@as(usize, 0), retainBestRanked(&.{}, &out));
}

test "interior probe eligibility protects root and exclusion authority" {
    // SCORE-011/FUNC-004: root publication and exclusion probes own their
    // evidence. A tablebase hit may prune interior work but must not overwrite
    // either, regardless of how certain the tablebase result is.
    try std.testing.expect(interiorProbeEligible(1, 4, false, 1, 3, 7));
    try std.testing.expect(!interiorProbeEligible(0, 4, false, 1, 3, 7));
    try std.testing.expect(!interiorProbeEligible(1, 4, true, 1, 3, 7));
    try std.testing.expect(!interiorProbeEligible(1, 0, false, 1, 3, 7));
    try std.testing.expect(interiorProbeEligible(1, 6, false, 6, 3, 7));
    try std.testing.expect(!interiorProbeEligible(1, 5, false, 6, 3, 7));
}

test "the disabled prober answers without a tablebase and never reports loaded" {
    // Every caller that configures no tablebase must reach a normal, typed
    // "no evidence" answer rather than a special case inside search.
    var probe = Disabled{};
    try std.testing.expect(!probe.isLoaded());
    var root: chess.position.PositionState = .{};
    const position = try chess.fen.parse(chess.fen.start_position, &root);
    try std.testing.expectEqual(
        ProbeResult{ .unavailable = .not_loaded },
        probe.probeWdl(&position),
    );
}

test "WDL negation is an involution that preserves rule-fifty structure" {
    // Mirroring evidence for the opponent must not silently upgrade a
    // fifty-move-bounded result into an ordinary win or loss.
    const all = [_]Wdl{ .loss, .blessed_loss, .draw, .cursed_win, .win };
    for (all) |wdl| {
        try std.testing.expectEqual(wdl, wdl.negate().negate());
        try std.testing.expectEqual(wdl.isRuleFiftyBounded(), wdl.negate().isRuleFiftyBounded());
    }
    try std.testing.expectEqual(Wdl.loss, Wdl.win.negate());
    try std.testing.expectEqual(Wdl.cursed_win, Wdl.blessed_loss.negate());
    try std.testing.expectEqual(Wdl.draw, Wdl.draw.negate());
}

test "WDL preconditions enforce the Syzygy indexing contract" {
    // FUNC-004/SCORE-001: these are chess-rule facts about what the tables
    // index, not tunable policy. A violated precondition must report why
    // rather than let the adapter probe an unindexable position.
    try std.testing.expectEqual(@as(?Unavailable, .not_loaded), wdlPrecondition(3, 0, false, 0));
    try std.testing.expectEqual(@as(?Unavailable, .too_many_pieces), wdlPrecondition(8, 6, false, 0));
    try std.testing.expectEqual(@as(?Unavailable, .castling_rights), wdlPrecondition(5, 6, true, 0));
    try std.testing.expectEqual(@as(?Unavailable, .halfmove_clock), wdlPrecondition(5, 6, false, 1));
    try std.testing.expectEqual(@as(?Unavailable, null), wdlPrecondition(5, 6, false, 0));
    // Exactly at the loaded limit is probeable; one piece beyond is not.
    try std.testing.expectEqual(@as(?Unavailable, null), wdlPrecondition(6, 6, false, 0));
}

test "tablebase scores occupy the reserved band and prefer nearer conversions" {
    // SCORE-005: the band is documented as one distinct value per search ply.
    // A proven win must outrank every ordinary evaluation and stay below every
    // mate, so no consumer can confuse proven with searched or forced evidence.
    const near = toScore(.win, 0, true);
    const far = toScore(.win, chess.types.max_ply - 1, true);
    try std.testing.expectEqual(score.tablebase_max_raw, near.raw());
    try std.testing.expectEqual(score.tablebase_min_raw, far.raw());
    try std.testing.expect(near.raw() > far.raw());
    try std.testing.expect(near.isTablebase() and far.isTablebase());
    try std.testing.expect(!near.isMate() and !near.isOrdinary());
    try std.testing.expect(far.raw() > score.ordinary_max_raw);
    try std.testing.expect(near.raw() < score.mate_min_raw);

    // Losses mirror exactly, so the score is antisymmetric under side to move.
    try std.testing.expectEqual(-near.raw(), toScore(.loss, 0, true).raw());
    try std.testing.expectEqual(-far.raw(), toScore(.loss, chess.types.max_ply - 1, true).raw());
}

test "fifty-move-bounded results score as draws rather than partial wins" {
    // A cursed win is drawn under the rules actually being played. Scoring it
    // as a small advantage would make search pursue a conversion the fifty-move
    // rule forbids, so the conversion is deliberately exact zero at every ply.
    for ([_]usize{ 0, 1, 37, chess.types.max_ply - 1 }) |ply| {
        try std.testing.expectEqual(@as(i32, 0), toScore(.cursed_win, ply, true).raw());
        try std.testing.expectEqual(@as(i32, 0), toScore(.blessed_loss, ply, true).raw());
        try std.testing.expectEqual(@as(i32, 0), toScore(.draw, ply, true).raw());
    }
}

test "tablebase evidence carries the bound its verdict justifies" {
    // A proven win says the position is at least this good, not that the
    // constructed magnitude is its true value, so it is a lower bound. Only a
    // drawn verdict is exact, because zero really is the position's value.
    try std.testing.expectEqual(types.Bound.lower, toBound(.win, true));
    try std.testing.expectEqual(types.Bound.upper, toBound(.loss, true));
    try std.testing.expectEqual(types.Bound.exact, toBound(.draw, true));
    try std.testing.expectEqual(types.Bound.exact, toBound(.cursed_win, true));
    try std.testing.expectEqual(types.Bound.exact, toBound(.blessed_loss, true));
    const evidence = toEvidence(.win, 4, true);
    try std.testing.expectEqual(types.Bound.lower, evidence.bound);
    try std.testing.expectEqual(types.Provenance.tablebase, evidence.provenance);
    try std.testing.expectEqual(score.tablebase_max_raw - 4, evidence.value.raw());
    try std.testing.expect(evidence.value.isValid() and !evidence.value.isNone());
}

test "disabling the fifty-move rule reports the theoretical result" {
    // The option selects which question the tables answer. Honouring the rule
    // is correct for play, because a cursed win really is drawn; ignoring it
    // answers the analyst's question about the position itself.
    try std.testing.expectEqual(@as(i32, 0), toScore(.cursed_win, 0, true).raw());
    try std.testing.expectEqual(types.Bound.exact, toBound(.cursed_win, true));
    try std.testing.expectEqual(score.tablebase_max_raw, toScore(.cursed_win, 0, false).raw());
    try std.testing.expectEqual(types.Bound.lower, toBound(.cursed_win, false));
    try std.testing.expectEqual(-score.tablebase_max_raw, toScore(.blessed_loss, 0, false).raw());
    try std.testing.expectEqual(types.Bound.upper, toBound(.blessed_loss, false));
    // Ordinary verdicts are unaffected either way.
    for ([_]bool{ true, false }) |honour| {
        try std.testing.expectEqual(score.tablebase_max_raw, toScore(.win, 0, honour).raw());
        try std.testing.expectEqual(@as(i32, 0), toScore(.draw, 0, honour).raw());
    }
}

test "a probe limit caps coverage below the loaded set" {
    // The limit is a cost control independent of what the tables cover, so a
    // position wider than the limit is skipped even when it could be probed.
    try std.testing.expect(interiorProbeEligible(1, 4, false, 1, 5, 7));
    try std.testing.expect(!interiorProbeEligible(1, 4, false, 1, 6, 5));
    try std.testing.expect(interiorProbeEligible(1, 4, false, 1, 5, 5));
    try std.testing.expect(!interiorProbeEligible(1, 4, false, 1, 3, 0));
}

test "only a verdict that settles the node against its window returns early" {
    // A non-cutting bound is real information but returning on it would leave
    // the node with no principal variation and no value better than the band
    // edge, so it must fall through to an ordinary search.
    try std.testing.expect(settlesNode(.exact, 0, -100, 100));
    try std.testing.expect(settlesNode(.lower, 150, -100, 100));
    try std.testing.expect(!settlesNode(.lower, 50, -100, 100));
    try std.testing.expect(settlesNode(.upper, -150, -100, 100));
    try std.testing.expect(!settlesNode(.upper, -50, -100, 100));
}
