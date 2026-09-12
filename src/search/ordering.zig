//! Deterministic staged move ordering and caller-owned quiet heuristics.
const std = @import("std");
const chess = @import("../chess/root.zig");
const params = @import("params.zig");

pub const State = struct {
    quiet_history: [2][64][64]i16 = @splat(@splat(@splat(0))),
    /// One-ply quiet reply evidence. Piece types exclude `.none`; both
    /// destinations are normalized to the current side's perspective so one
    /// color-symmetric table serves both sides without conflating directions.
    reply_history: [6][64][6][64]i16 = @splat(@splat(@splat(@splat(0)))),
    /// Multi-distance continuation evidence. One shared table deliberately
    /// generalizes the same relation across distances; the prior node's check
    /// and tactical state keep materially different search situations apart.
    continuation_history: [2][2][6][64][6][64]i16 = @splat(@splat(@splat(@splat(@splat(@splat(0)))))),
    /// Tactical outcome evidence keyed by the resulting mover type, a
    /// color-normalized destination and the captured victim type. Quiet
    /// promotions have no victim and therefore do not enter this table.
    capture_history: [6][64][6]i16 = @splat(@splat(@splat(0))),
    killers: [chess.types.max_ply][2]chess.move.Move = @splat(@splat(.none)),
    /// Step-5.4.1 static-evaluation correction evidence. The evaluator is
    /// systematically wrong in some position classes rather than randomly
    /// wrong, and the residual harness shows searched values departing from raw
    /// ones by far more than noise. Pawn structure is the explicit feature: it
    /// changes slowly, survives most moves, and is what the evaluator most
    /// often misprices. The table records where search has previously disagreed
    /// with the evaluator for this side and this pawn structure.
    correction_history: [2][correction_slots]i16 = @splat(@splat(0)),

    pub const history_limit: i32 = 16 * 1024;
    /// A power of two so the key reduces by mask rather than division.
    const correction_slots: usize = 16 * 1024;
    /// Fixed-point denominator for a stored correction, so an entry carries
    /// sub-centipawn resolution while remaining an `i16`.
    const correction_scale: i32 = 256;
    /// A correction may move the evaluator by at most this many centipawns.
    /// The producer is evidence about a bias, never a licence to overrule the
    /// evaluator, and an unbounded correction would eventually do the latter.
    pub const correction_cap: i32 = 48;
    const correction_limit: i32 = correction_cap * correction_scale;
    /// Depth weight ceiling. A deep search is better evidence than a shallow
    /// one, but past this the extra authority is not worth the slower response
    /// to a genuinely changed position class.
    const correction_depth_cap: i32 = 16;
    const correction_weight_total: i32 = 256;

    inline fn correctionSlot(pawn_key: chess.types.Key) usize {
        return @intCast(pawn_key & (correction_slots - 1));
    }

    /// The correction this side and pawn structure has earned, in centipawns.
    pub fn correction(self: *const State, side: chess.types.Color, pawn_key: chess.types.Key) i32 {
        const entry: i32 = self.correction_history[side.index()][correctionSlot(pawn_key)];
        return @divTrunc(entry, correction_scale);
    }

    pub const CorrectionSummary = struct {
        populated: usize = 0,
        positive: usize = 0,
        negative: usize = 0,
        near_cap: usize = 0,
        max_abs_cp: i32 = 0,
        sum_abs_fixed: u64 = 0,
    };

    /// Scan correction state outside search. This gives deterministic evidence
    /// that the fixed table populated without turning its cap into the normal
    /// operating point; it adds no node-path work.
    pub fn correctionSummary(self: *const State) CorrectionSummary {
        var summary: CorrectionSummary = .{};
        for (self.correction_history) |side_entries| {
            for (side_entries) |entry| {
                if (entry == 0) continue;
                summary.populated += 1;
                if (entry > 0) summary.positive += 1 else summary.negative += 1;
                const magnitude: i32 = @intCast(@abs(@as(i32, entry)));
                summary.sum_abs_fixed += @intCast(magnitude);
                summary.max_abs_cp = @max(summary.max_abs_cp, @divTrunc(magnitude, correction_scale));
                if (magnitude >= correction_limit - correction_scale) summary.near_cap += 1;
            }
        }
        return summary;
    }

    /// Record that a completed search valued this node `delta` centipawns away
    /// from what the evaluator said. `depth` is the authority of that search.
    pub fn recordCorrection(
        self: *State,
        side: chess.types.Color,
        pawn_key: chess.types.Key,
        delta: i32,
        depth: u16,
    ) void {
        const slot = correctionSlot(pawn_key);
        const entry: *i16 = &self.correction_history[side.index()][slot];
        const current: i32 = entry.*;
        const weight = @min(@as(i32, @intCast(depth)), correction_depth_cap);
        const target = std.math.clamp(delta * correction_scale, -correction_limit, correction_limit);
        // Exponential moving average in fixed point: heavier weight for a
        // deeper search, and the same relation for every slot so one loud
        // position cannot capture a structure class.
        const moved = current + @divTrunc((target - current) * weight, correction_weight_total);
        entry.* = @intCast(std.math.clamp(moved, -correction_limit, correction_limit));
    }

    pub fn clear(self: *State) void {
        self.* = .{};
    }

    pub fn recordQuietCutoff(
        self: *State,
        side: chess.types.Color,
        chess_move: chess.move.Move,
        depth: u16,
        ply: usize,
        comptime core: bool,
    ) void {
        self.updateQuiet(side, chess_move, historyBonus(core, depth));
        if (self.killers[ply][0].raw() != chess_move.raw()) {
            self.killers[ply][1] = self.killers[ply][0];
            self.killers[ply][0] = chess_move;
        }
    }

    pub fn recordLegacyQuietCutoff(
        self: *State,
        side: chess.types.Color,
        chess_move: chess.move.Move,
        depth: u16,
        ply: usize,
    ) void {
        const value = &self.quiet_history[side.index()][chess_move.from().index()][chess_move.to().index()];
        value.* = std.math.add(i16, value.*, @intCast(@min(depth, std.math.maxInt(i16)))) catch
            std.math.maxInt(i16);
        if (self.killers[ply][0].raw() != chess_move.raw()) {
            self.killers[ply][1] = self.killers[ply][0];
            self.killers[ply][0] = chess_move;
        }
    }

    pub fn recordQuietFailure(
        self: *State,
        side: chess.types.Color,
        chess_move: chess.move.Move,
        depth: u16,
        comptime core: bool,
    ) void {
        self.updateQuiet(side, chess_move, -historyBonus(core, depth));
    }

    pub fn quietScore(
        self: *const State,
        side: chess.types.Color,
        chess_move: chess.move.Move,
    ) i16 {
        return self.quiet_history[side.index()][chess_move.from().index()][chess_move.to().index()];
    }

    pub fn recordReplySuccess(
        self: *State,
        value: *const chess.position.Position,
        reply: ReplyContext,
        chess_move: chess.move.Move,
        depth: u16,
        comptime core: bool,
    ) void {
        self.updateReply(value, reply, chess_move, historyBonus(core, depth));
    }

    pub fn recordReplyFailure(
        self: *State,
        value: *const chess.position.Position,
        reply: ReplyContext,
        chess_move: chess.move.Move,
        depth: u16,
        comptime core: bool,
    ) void {
        self.updateReply(value, reply, chess_move, -historyBonus(core, depth));
    }

    pub fn replyScore(
        self: *const State,
        value: *const chess.position.Position,
        reply: ReplyContext,
        chess_move: chess.move.Move,
    ) i16 {
        const current_piece = value.physical.pieceOn(chess_move.from());
        std.debug.assert(current_piece != .none and current_piece.color() == value.side_to_move);
        return self.reply_history[pieceIndex(reply.previous_piece)][reply.previous_to.index()][pieceIndex(current_piece.pieceType())][normalizeSquare(value.side_to_move, chess_move.to()).index()];
    }

    pub fn continuationScore(
        self: *const State,
        value: *const chess.position.Position,
        continuation: ContinuationContext,
        chess_move: chess.move.Move,
    ) i16 {
        const current_piece = value.physical.pieceOn(chess_move.from());
        std.debug.assert(current_piece != .none and current_piece.color() == value.side_to_move);
        return self.continuation_history[@intFromBool(continuation.from_check)][@intFromBool(continuation.tactical)][pieceIndex(continuation.previous_piece)][continuation.previous_to.index()][pieceIndex(current_piece.pieceType())][normalizeSquare(value.side_to_move, chess_move.to()).index()];
    }

    pub fn continuationTotal(
        self: *const State,
        value: *const chess.position.Position,
        continuations: ContinuationSet,
        chess_move: chess.move.Move,
    ) i32 {
        var total: i32 = 0;
        for (continuations.items) |maybe_context| {
            if (maybe_context) |continuation| {
                total += self.continuationScore(value, continuation, chess_move);
            }
        }
        return total;
    }

    /// LMR consumes the direction on which the populated quiet-history
    /// relations agree, not their incomparable raw magnitudes. A tie or an
    /// entirely unknown relation is neutral. This keeps one saturated table
    /// from overruling every other accepted context.
    pub fn quietConfidence(
        self: *const State,
        value: *const chess.position.Position,
        reply: ?ReplyContext,
        continuations: ContinuationSet,
        chess_move: chess.move.Move,
    ) HistoryConfidence {
        var positive: u3 = 0;
        var negative: u3 = 0;
        countHistoryVote(self.quietScore(value.side_to_move, chess_move), &positive, &negative);
        if (reply) |active_reply|
            countHistoryVote(self.replyScore(value, active_reply, chess_move), &positive, &negative);
        for (continuations.items) |maybe_context|
            if (maybe_context) |continuation|
                countHistoryVote(self.continuationScore(value, continuation, chess_move), &positive, &negative);
        return if (positive > negative)
            .positive
        else if (negative > positive)
            .negative
        else
            .neutral;
    }

    pub fn recordCaptureSuccess(
        self: *State,
        value: *const chess.position.Position,
        chess_move: chess.move.Move,
        depth: u16,
    ) void {
        self.updateCapture(value, chess_move, historyBonus(false, depth));
    }

    pub fn recordCaptureFailure(
        self: *State,
        value: *const chess.position.Position,
        chess_move: chess.move.Move,
        depth: u16,
    ) void {
        self.updateCapture(value, chess_move, -historyBonus(false, depth));
    }

    pub fn captureScore(
        self: *const State,
        value: *const chess.position.Position,
        chess_move: chess.move.Move,
    ) i16 {
        const key = captureKey(value, chess_move);
        return self.capture_history[pieceIndex(key.mover)][key.destination.index()][pieceIndex(key.victim)];
    }

    fn updateQuiet(
        self: *State,
        side: chess.types.Color,
        chess_move: chess.move.Move,
        bonus: i32,
    ) void {
        const value = &self.quiet_history[side.index()][chess_move.from().index()][chess_move.to().index()];
        updateBounded(value, bonus);
    }

    fn updateReply(
        self: *State,
        value: *const chess.position.Position,
        reply: ReplyContext,
        chess_move: chess.move.Move,
        bonus: i32,
    ) void {
        const current_piece = value.physical.pieceOn(chess_move.from());
        std.debug.assert(current_piece != .none and current_piece.color() == value.side_to_move);
        const entry = &self.reply_history[pieceIndex(reply.previous_piece)][reply.previous_to.index()][pieceIndex(current_piece.pieceType())][normalizeSquare(value.side_to_move, chess_move.to()).index()];
        updateBounded(entry, bonus);
    }

    pub fn recordContinuationSuccess(
        self: *State,
        value: *const chess.position.Position,
        continuation: ContinuationContext,
        chess_move: chess.move.Move,
        depth: u16,
        comptime core: bool,
    ) void {
        self.updateContinuation(value, continuation, chess_move, historyBonus(core, depth));
    }

    pub fn recordContinuationFailure(
        self: *State,
        value: *const chess.position.Position,
        continuation: ContinuationContext,
        chess_move: chess.move.Move,
        depth: u16,
        comptime core: bool,
    ) void {
        self.updateContinuation(value, continuation, chess_move, -historyBonus(core, depth));
    }

    fn updateContinuation(
        self: *State,
        value: *const chess.position.Position,
        continuation: ContinuationContext,
        chess_move: chess.move.Move,
        bonus: i32,
    ) void {
        const current_piece = value.physical.pieceOn(chess_move.from());
        std.debug.assert(current_piece != .none and current_piece.color() == value.side_to_move);
        const entry = &self.continuation_history[@intFromBool(continuation.from_check)][@intFromBool(continuation.tactical)][pieceIndex(continuation.previous_piece)][continuation.previous_to.index()][pieceIndex(current_piece.pieceType())][normalizeSquare(value.side_to_move, chess_move.to()).index()];
        updateBounded(entry, bonus);
    }

    fn updateCapture(
        self: *State,
        value: *const chess.position.Position,
        chess_move: chess.move.Move,
        bonus: i32,
    ) void {
        const key = captureKey(value, chess_move);
        const entry = &self.capture_history[pieceIndex(key.mover)][key.destination.index()][pieceIndex(key.victim)];
        updateBounded(entry, bonus);
    }

    pub fn updateBounded(value: *i16, bonus: i32) void {
        const current: i32 = value.*;
        const magnitude: i32 = @intCast(@abs(bonus));
        const next = current + bonus - @divTrunc(current * magnitude, history_limit);
        std.debug.assert(next >= -history_limit and next <= history_limit);
        value.* = @intCast(next);
    }

    fn historyBonus(comptime core: bool, depth: u16) i32 {
        return historyBonusFor(core, depth);
    }
};

/// One depth-to-magnitude scale for every quiet history producer.
///
/// The accepted `depth^2` curve tops out near `196` for the depths a real
/// search reaches, so an entry never travels far inside the `16384` range and
/// relative history says little beyond coarse ordering. ADR-0071 A replaces it
/// with a linear curve that saturates at `2048`: a depth-one outcome still
/// moves an entry by about `90`, and by depth fourteen the producer is writing
/// an eighth of the range. That is what makes history informative enough to
/// carry a reduction and a pruning decision rather than only a rank.
pub fn historyBonusFor(comptime core: bool, depth: u16) i32 {
    if (comptime core) {
        const bounded: i32 = @intCast(@min(depth, 128));
        return @min(2048, 150 * bounded - 60);
    }
    const bounded: i32 = @intCast(@min(depth, 128));
    return @min(bounded * bounded, State.history_limit);
}

/// The shadow outcome uses the accepted history scale only as a bounded sample
/// encoding. It has no ordering or depth consumer in Step 6.5.9.
pub fn shadowOutcomeBonus(depth: u16) i32 {
    const bounded: i32 = @intCast(@min(depth, 128));
    return @max(@as(i32, 1), @min(bounded * bounded, 16 * 1024));
}

pub const HistoryConfidence = enum { negative, neutral, positive };

fn countHistoryVote(value: i16, positive: *u3, negative: *u3) void {
    if (value > 0) positive.* += 1 else if (value < 0) negative.* += 1;
}

pub const ReplyContext = struct {
    previous_piece: chess.types.PieceType,
    previous_to: chess.types.Square,
};

pub const ContinuationDistance = enum { two, four, six };
pub const continuation_distance_count = @typeInfo(ContinuationDistance).@"enum".fields.len;

pub const ContinuationContext = struct {
    previous_piece: chess.types.PieceType,
    previous_to: chess.types.Square,
    from_check: bool,
    tactical: bool,
};

pub const ContinuationSet = struct {
    items: [continuation_distance_count]?ContinuationContext = @splat(null),
};

pub fn continuationContext(
    side: chess.types.Color,
    previous_piece: chess.types.PieceType,
    previous_to: chess.types.Square,
    from_check: bool,
    tactical: bool,
) ContinuationContext {
    std.debug.assert(previous_piece.isPiece());
    return .{
        .previous_piece = previous_piece,
        .previous_to = normalizeSquare(side, previous_to),
        .from_check = from_check,
        .tactical = tactical,
    };
}

const CaptureKey = struct {
    mover: chess.types.PieceType,
    destination: chess.types.Square,
    victim: chess.types.PieceType,
};

/// Capture-history facts are derived before make. En passant names the pawn
/// removed off-destination. Promotions use their resulting piece type so four
/// semantically different captures do not reward and penalize one shared key.
fn captureKey(
    value: *const chess.position.Position,
    chess_move: chess.move.Move,
) CaptureKey {
    std.debug.assert(chess.movegen.isCapture(value, chess_move));
    const moving = value.physical.pieceOn(chess_move.from());
    std.debug.assert(moving != .none and moving.color() == value.side_to_move);
    const victim = if (chess_move.kind() == .en_passant)
        chess.types.PieceType.pawn
    else
        value.physical.pieceOn(chess_move.to()).pieceType();
    return .{
        .mover = if (chess_move.kind() == .promotion) chess_move.promotionPiece() else moving.pieceType(),
        .destination = normalizeSquare(value.side_to_move, chess_move.to()),
        .victim = victim,
    };
}

pub fn sameCaptureKey(
    value: *const chess.position.Position,
    first: chess.move.Move,
    second: chess.move.Move,
) bool {
    return std.meta.eql(captureKey(value, first), captureKey(value, second));
}

/// Derives a relation key only from a real immediately preceding move. The
/// moved piece is read from the resulting position, which naturally makes a
/// promotion a promoted-piece context and castling a king context.
pub fn replyContext(
    value: *const chess.position.Position,
    previous_move: chess.move.Move,
) ReplyContext {
    std.debug.assert(previous_move.isChessMove());
    const previous_piece = value.physical.pieceOn(previous_move.to());
    std.debug.assert(previous_piece != .none and previous_piece.color() == value.side_to_move.opposite());
    return .{
        .previous_piece = previous_piece.pieceType(),
        .previous_to = normalizeSquare(value.side_to_move, previous_move.to()),
    };
}

fn normalizeSquare(side: chess.types.Color, square: chess.types.Square) chess.types.Square {
    return if (side == .white) square else square.flipRank();
}

/// Stable diagnostic keys for Step-6.5.9 shadow outcomes. They encode the
/// existing relations exactly; continuation distance is intentionally absent
/// because all three distances read one shared production table.
pub fn quietEvidenceKey(side: chess.types.Color, chess_move: chess.move.Move) u64 {
    std.debug.assert(chess_move.isChessMove());
    return (@as(u64, 1) << 62) |
        (@as(u64, side.index()) << 16) |
        (@as(u64, chess_move.from().index()) << 6) |
        @as(u64, chess_move.to().index());
}

pub fn replyEvidenceKey(
    value: *const chess.position.Position,
    reply: ReplyContext,
    chess_move: chess.move.Move,
) u64 {
    const current_piece = value.physical.pieceOn(chess_move.from());
    std.debug.assert(current_piece != .none and current_piece.color() == value.side_to_move);
    return (@as(u64, 2) << 62) |
        (@as(u64, @intFromEnum(reply.previous_piece)) << 24) |
        (@as(u64, reply.previous_to.index()) << 18) |
        (@as(u64, @intFromEnum(current_piece.pieceType())) << 12) |
        (@as(u64, normalizeSquare(value.side_to_move, chess_move.to()).index()) << 6);
}

pub fn continuationEvidenceKey(
    value: *const chess.position.Position,
    continuation: ContinuationContext,
    chess_move: chess.move.Move,
) u64 {
    const current_piece = value.physical.pieceOn(chess_move.from());
    std.debug.assert(current_piece != .none and current_piece.color() == value.side_to_move);
    return (@as(u64, 3) << 62) |
        (@as(u64, @intFromBool(continuation.from_check)) << 31) |
        (@as(u64, @intFromBool(continuation.tactical)) << 30) |
        (@as(u64, @intFromEnum(continuation.previous_piece)) << 24) |
        (@as(u64, continuation.previous_to.index()) << 18) |
        (@as(u64, @intFromEnum(current_piece.pieceType())) << 12) |
        (@as(u64, normalizeSquare(value.side_to_move, chess_move.to()).index()) << 6);
}

fn pieceIndex(piece_type: chess.types.PieceType) usize {
    std.debug.assert(piece_type.isPiece());
    return piece_type.index() - 1;
}

comptime {
    // The exact contextual table costs 1.125 MiB per worker; the complete
    // state stays below 1.5 MiB so later SMP budgeting remains explicit.
    std.debug.assert(@sizeOf(State) <= 1536 * 1024);
}

/// Names the evidence that placed a move in its current stage. Diagnostics
/// consume this after ordering; search policy never branches on the label.
pub const Source = enum {
    tt,
    good_tactical,
    primary_killer,
    secondary_killer,
    quiet_history,
    bad_tactical,
};

const Rank = struct {
    source: Source,
    history: i32,

    fn before(self: Rank, other: Rank) bool {
        const self_stage = stage(self.source);
        const other_stage = stage(other.source);
        if (self_stage != other_stage) return self_stage > other_stage;
        return self.history > other.history;
    }
};

pub const Selection = struct {
    chess_move: chess.move.Move,
    source: Source,
    index: usize,
    /// The composite quiet-history value this move was ranked with, captured
    /// at selection. Zero for every source that does not rank by history; a
    /// consumer that needs the value for a TT or killer quiet asks
    /// `quietHistoryValue` on demand.
    history: i32,
};

/// Allocation-free incremental selection over one generated move list. Each
/// call exposes the best remaining rank while stably preserving equal-ranked
/// generation order. Extracting into the consumed prefix makes a complete
/// drain byte-for-byte equivalent to the accepted stable full sort, while a
/// cutoff need not sort a tail the search will never inspect.
pub const Picker = struct {
    moves: *chess.position.MoveList,
    ranks: [chess.types.move_capacity]Rank,
    cursor: usize = 0,
    select_best: bool,

    pub inline fn init(
        comptime use_capture_history: bool,
        moves: *chess.position.MoveList,
        value: *const chess.position.Position,
        binding: anytype,
        tt_move: ?chess.move.Move,
        state: ?*const State,
        search_params: params.Values,
        ply: usize,
        reply: ?ReplyContext,
        continuations: ContinuationSet,
        select_best: bool,
        classify_sources: bool,
    ) Picker {
        // SAFETY: only the initialized move-list prefix receives and later
        // reads a rank. A generation-order-only disabled search needs neither
        // SEE nor history classification and uses an inert rank.
        var ranks: [chess.types.move_capacity]Rank = undefined;
        for (moves.slice(), 0..) |chess_move, index| {
            ranks[index] = if (select_best or classify_sources)
                rank(use_capture_history, value, binding, chess_move, tt_move, state, search_params, ply, reply, continuations)
            else
                .{ .source = .quiet_history, .history = 0 };
        }
        return .{
            .moves = moves,
            .ranks = ranks,
            .select_best = select_best,
        };
    }

    pub fn next(self: *Picker) ?Selection {
        const selected_index = self.bestRemainingIndex() orelse return null;
        return self.takeAt(selected_index);
    }

    /// Ranks moves appended to the list after `init`, so a caller that learns
    /// only later which extra moves it wants can still select over one list in
    /// one order. ADR-0071 F's quiescence checks are decided after stand-pat.
    pub fn rankAppended(
        self: *Picker,
        comptime use_capture_history: bool,
        value: *const chess.position.Position,
        binding: anytype,
        tt_move: ?chess.move.Move,
        state: ?*const State,
        search_params: params.Values,
        ply: usize,
        appended_start: usize,
    ) void {
        for (appended_start..self.moves.count) |index| {
            self.ranks[index] = if (self.select_best)
                rank(
                    use_capture_history,
                    value,
                    binding,
                    self.moves.moves[index],
                    tt_move,
                    state,
                    search_params,
                    ply,
                    null,
                    .{},
                )
            else
                .{ .source = .quiet_history, .history = 0 };
        }
    }

    fn bestRemainingIndex(self: *const Picker) ?usize {
        if (self.cursor >= self.moves.count) return null;
        var selected_index = self.cursor;
        if (self.select_best) {
            var candidate = self.cursor + 1;
            while (candidate < self.moves.count) : (candidate += 1) {
                // Strict comparison keeps the earliest equal-ranked move and
                // therefore preserves generation order within every stage.
                if (self.ranks[candidate].before(self.ranks[selected_index]))
                    selected_index = candidate;
            }
        }
        return selected_index;
    }

    fn takeAt(self: *Picker, selected_index: usize) Selection {
        std.debug.assert(selected_index >= self.cursor and selected_index < self.moves.count);
        const selected_move = self.moves.moves[selected_index];
        const selected_rank = self.ranks[selected_index];
        var shift = selected_index;
        while (shift > self.cursor) : (shift -= 1) {
            self.moves.moves[shift] = self.moves.moves[shift - 1];
            self.ranks[shift] = self.ranks[shift - 1];
        }
        self.moves.moves[self.cursor] = selected_move;
        self.ranks[self.cursor] = selected_rank;

        const result = Selection{
            .chess_move = selected_move,
            .source = selected_rank.source,
            .index = self.cursor,
            .history = selected_rank.history,
        };
        self.cursor += 1;
        return result;
    }
};

/// Candidate-only staged selection for ordinary non-check interior nodes.
/// Tactical ranks are frozen at node entry. Non-tactical quiets are generated
/// and ranked only when no TT or good tactical move remains, so their ranking
/// deliberately observes history learned by completed descendant searches.
/// The caller retains terminal, score, pruning and thread authority.
pub const LiveHistoryPicker = struct {
    inner: Picker,
    phase: Phase,
    classify_sources: bool,
    /// ADR-0071 C. Once a node's late-move count triggers, the remaining
    /// quiets are dropped without being made. Bad tacticals keep being
    /// emitted: the count says the node has seen enough quiet alternatives,
    /// not that it has seen enough of everything.
    skip_quiets: bool = false,
    skipped_quiets: usize = 0,

    const Phase = enum { tactical, complete };

    pub inline fn init(
        comptime use_capture_history: bool,
        moves: *chess.position.MoveList,
        value: *const chess.position.Position,
        binding: anytype,
        tt_move: ?chess.move.Move,
        state: ?*const State,
        search_params: params.Values,
        ply: usize,
        reply: ?ReplyContext,
        continuations: ContinuationSet,
        select_best: bool,
        classify_sources: bool,
        staged: bool,
    ) LiveHistoryPicker {
        return .{
            .inner = Picker.init(
                use_capture_history,
                moves,
                value,
                binding,
                tt_move,
                state,
                search_params,
                ply,
                reply,
                continuations,
                select_best,
                classify_sources,
            ),
            .phase = if (staged) .tactical else .complete,
            .classify_sources = classify_sources,
        };
    }

    pub fn next(self: *LiveHistoryPicker) ?Selection {
        while (true) {
            const selected_index = self.inner.bestRemainingIndex() orelse return null;
            if (self.phase == .tactical and
                self.inner.ranks[selected_index].source == .bad_tactical) return null;
            if (self.skip_quiets) switch (self.inner.ranks[selected_index].source) {
                // A quiet TT move is emitted first and therefore always before
                // any count can trigger, so it is never dropped here.
                .primary_killer, .secondary_killer, .quiet_history => {
                    _ = self.inner.takeAt(selected_index);
                    self.skipped_quiets += 1;
                    continue;
                },
                else => {},
            };
            return self.inner.takeAt(selected_index);
        }
    }

    pub fn skipRemainingQuiets(self: *LiveHistoryPicker) void {
        self.skip_quiets = true;
    }

    pub fn skippedQuiets(self: *const LiveHistoryPicker) usize {
        return self.skipped_quiets;
    }

    /// Opens the delayed quiet stage exactly once and returns the number of
    /// newly generated unique moves for observation accounting. A quiet TT
    /// move was already emitted from the initial list and is removed from the
    /// appended subset before ranking.
    pub fn enterQuiets(
        self: *LiveHistoryPicker,
        comptime use_capture_history: bool,
        value: *const chess.position.Position,
        binding: anytype,
        tt_move: ?chess.move.Move,
        state: ?*const State,
        search_params: params.Values,
        ply: usize,
        reply: ?ReplyContext,
        continuations: ContinuationSet,
    ) ?usize {
        if (self.phase != .tactical) return null;
        self.phase = .complete;

        const appended_start = self.inner.moves.count;
        chess.movegen.generateAppend(.non_tactical_quiets, value, self.inner.moves);
        if (tt_move) |candidate| {
            if (!chess.movegen.isTactical(value, candidate))
                removeAppendedDuplicate(self.inner.moves, appended_start, candidate);
        }
        const generated = self.inner.moves.count - appended_start;
        for (appended_start..self.inner.moves.count) |index| {
            self.inner.ranks[index] = if (self.inner.select_best or self.classify_sources)
                rank(
                    use_capture_history,
                    value,
                    binding,
                    self.inner.moves.moves[index],
                    tt_move,
                    state,
                    search_params,
                    ply,
                    reply,
                    continuations,
                )
            else
                .{ .source = .quiet_history, .history = 0 };
        }
        return generated;
    }
};

fn removeAppendedDuplicate(
    moves: *chess.position.MoveList,
    appended_start: usize,
    duplicate: chess.move.Move,
) void {
    var index = appended_start;
    while (index < moves.count) : (index += 1) {
        if (moves.moves[index].raw() != duplicate.raw()) continue;
        var shift = index;
        while (shift + 1 < moves.count) : (shift += 1)
            moves.moves[shift] = moves.moves[shift + 1];
        moves.count -= 1;
        return;
    }
}

fn stage(source_value: Source) u3 {
    return switch (source_value) {
        .tt => 6,
        .good_tactical => 5,
        .primary_killer => 4,
        .secondary_killer => 3,
        .quiet_history => 2,
        .bad_tactical => 0,
    };
}

pub fn order(
    moves: *chess.position.MoveList,
    value: *const chess.position.Position,
    binding: anytype,
    tt_move: ?chess.move.Move,
    state: ?*const State,
    ply: usize,
) void {
    orderImpl(moves, value, binding, tt_move, state, ply, null, .{}, null);
}

pub fn orderWithReply(
    moves: *chess.position.MoveList,
    value: *const chess.position.Position,
    binding: anytype,
    tt_move: ?chess.move.Move,
    state: ?*const State,
    ply: usize,
    reply: ReplyContext,
) void {
    orderImpl(moves, value, binding, tt_move, state, ply, reply, .{}, null);
}

/// Orders identically to `order` and returns the source assigned to every
/// sorted move. Only an enabled diagnostic specialization calls this entry.
pub fn orderObserved(
    moves: *chess.position.MoveList,
    value: *const chess.position.Position,
    binding: anytype,
    tt_move: ?chess.move.Move,
    state: ?*const State,
    ply: usize,
    sources: *[chess.types.move_capacity]Source,
) void {
    orderImpl(moves, value, binding, tt_move, state, ply, null, .{}, sources);
}

pub fn orderObservedWithReply(
    moves: *chess.position.MoveList,
    value: *const chess.position.Position,
    binding: anytype,
    tt_move: ?chess.move.Move,
    state: ?*const State,
    ply: usize,
    reply: ReplyContext,
    sources: *[chess.types.move_capacity]Source,
) void {
    orderImpl(moves, value, binding, tt_move, state, ply, reply, .{}, sources);
}

fn orderImpl(
    moves: *chess.position.MoveList,
    value: *const chess.position.Position,
    binding: anytype,
    tt_move: ?chess.move.Move,
    state: ?*const State,
    ply: usize,
    reply: ?ReplyContext,
    continuations: ContinuationSet,
    sources: ?*[chess.types.move_capacity]Source,
) void {
    var picker = Picker.init(true, moves, value, binding, tt_move, state, .{}, ply, reply, continuations, true, true);
    while (picker.next()) |selection| {
        if (sources) |output| output[selection.index] = selection.source;
    }
}

fn rank(
    comptime use_capture_history: bool,
    value: *const chess.position.Position,
    binding: anytype,
    chess_move: chess.move.Move,
    tt_move: ?chess.move.Move,
    state: ?*const State,
    search_params: params.Values,
    ply: usize,
    reply: ?ReplyContext,
    continuations: ContinuationSet,
) Rank {
    if (tt_move) |candidate| {
        if (candidate.raw() == chess_move.raw()) return .{ .source = .tt, .history = 0 };
    }
    const tactical = chess.movegen.isTactical(value, chess_move);
    if (tactical) {
        return .{
            .source = if (binding.seeAtLeast(value, chess_move, 0)) .good_tactical else .bad_tactical,
            .history = if (use_capture_history and chess.movegen.isCapture(value, chess_move))
                if (state) |active| active.captureScore(value, chess_move) else 0
            else
                0,
        };
    }
    if (state) |active| {
        if (active.killers[ply][0].raw() == chess_move.raw()) return .{ .source = .primary_killer, .history = 0 };
        if (active.killers[ply][1].raw() == chess_move.raw()) return .{ .source = .secondary_killer, .history = 0 };
    }
    return .{
        .source = .quiet_history,
        .history = if (state) |active|
            quietHistoryValue(active, value, chess_move, search_params, reply, continuations)
        else
            0,
    };
}

/// The composite the picker ranks quiets by: main history plus the weighted
/// reply and continuation contributions. ADR-0071 B reads the same number as
/// the reduction surface's per-move evidence, so ranking and reduction cannot
/// disagree about what the tables say for a move.
pub fn quietHistoryValue(
    state: *const State,
    value: *const chess.position.Position,
    chess_move: chess.move.Move,
    search_params: params.Values,
    reply: ?ReplyContext,
    continuations: ContinuationSet,
) i32 {
    const main: i32 = state.quiet_history[value.side_to_move.index()][chess_move.from().index()][chess_move.to().index()];
    const contextual: i32 = if (reply) |active_reply|
        weightedHistory(state.replyScore(value, active_reply, chess_move), search_params.reply_history_weight)
    else
        0;
    const continuation = weightedHistory(
        state.continuationTotal(value, continuations, chess_move),
        search_params.continuation_history_weight,
    );
    return main + contextual + continuation;
}

fn weightedHistory(value: i32, weight: i32) i32 {
    std.debug.assert(weight >= 0 and weight <= 200);
    return @intCast(@divTrunc(@as(i64, value) * weight, 100));
}

/// Reconstructs the already-defined ordering source only for an enabled
/// observer. The disabled search specialization never calls this function.
pub fn source(
    value: *const chess.position.Position,
    binding: anytype,
    chess_move: chess.move.Move,
    tt_move: ?chess.move.Move,
    state: ?*const State,
    ply: usize,
) Source {
    return rank(true, value, binding, chess_move, tt_move, state, .{}, ply, null, .{}).source;
}

test "the core history bonus is bounded, monotone and informative" {
    // ADR-0071 A. The oracle is the stated curve and the table's own range,
    // not the implementation: a producer that cannot move an entry across a
    // useful fraction of [-16384, 16384] cannot carry a pruning decision.
    try std.testing.expectEqual(@as(i32, 90), historyBonusFor(true, 1));
    try std.testing.expectEqual(@as(i32, 240), historyBonusFor(true, 2));
    // 150*14 - 60 = 2040; the cap first binds at depth 15. The ADR's prose
    // rounds this to "saturates at 2048"; the formula is the contract.
    try std.testing.expectEqual(@as(i32, 2040), historyBonusFor(true, 14));
    try std.testing.expectEqual(@as(i32, 2048), historyBonusFor(true, 15));

    var depth: u16 = 1;
    var previous = historyBonusFor(true, 0);
    while (depth <= 128) : (depth += 1) {
        const bonus = historyBonusFor(true, depth);
        try std.testing.expect(bonus >= previous);
        try std.testing.expect(bonus > 0 and bonus <= 2048);
        previous = bonus;
    }
    // Saturation is reached inside the depths a real search visits, and the
    // accepted curve does not reach a comparable share of the range there.
    try std.testing.expect(historyBonusFor(true, 20) == 2048);
    try std.testing.expect(historyBonusFor(true, 8) > historyBonusFor(false, 8));
}

test "the core gravity update stays inside the history range under saturation" {
    // Property: repeated same-direction updates converge inside the bound and
    // never leave it, and the opposite direction moves the entry back. The
    // bound is the table's own declared range, which the update must respect
    // for every reachable bonus magnitude.
    inline for (.{ true, false }) |core| {
        var entry: i16 = 0;
        for (0..4096) |_| {
            State.updateBounded(&entry, historyBonusFor(core, 14));
            try std.testing.expect(entry >= -State.history_limit and entry <= State.history_limit);
        }
        const saturated = entry;
        try std.testing.expect(saturated > 0);
        for (0..4096) |_| {
            State.updateBounded(&entry, -historyBonusFor(core, 14));
            try std.testing.expect(entry >= -State.history_limit and entry <= State.history_limit);
        }
        // The fixed point of the gravity update is the bound itself, so the
        // entry may land exactly on it; it may never pass it.
        try std.testing.expect(entry < 0);
        try std.testing.expect(entry >= -State.history_limit);
    }
}

test "balanced quiet outcomes remain bounded and rotate killers deterministically" {
    // Search ordering evidence must remain bounded and responsive across
    // arbitrarily long games; only successful quiets become killers.
    var state: State = .{};
    const first = chess.move.Move.normal(.g1, .f3);
    const second = chess.move.Move.normal(.b1, .c3);
    state.recordQuietCutoff(.white, first, std.math.maxInt(u16), 2, false);
    state.recordQuietCutoff(.white, first, std.math.maxInt(u16), 2, false);
    state.recordQuietFailure(.white, first, std.math.maxInt(u16), false);
    state.recordQuietCutoff(.white, second, 3, 2, false);
    try std.testing.expectEqual(@as(i16, -16 * 1024), state.quietScore(.white, first));
    try std.testing.expectEqual(second, state.killers[2][0]);
    try std.testing.expectEqual(first, state.killers[2][1]);
}

test "opposite quiet outcomes age prior evidence toward the latest result" {
    // A touched entry uses bounded gravity rather than irreversible saturation.
    var state: State = .{};
    const chess_move = chess.move.Move.normal(.g1, .f3);
    state.recordQuietCutoff(.white, chess_move, 8, 0, false);
    const rewarded = state.quietScore(.white, chess_move);
    state.recordQuietFailure(.white, chess_move, 8, false);
    const balanced = state.quietScore(.white, chess_move);
    try std.testing.expect(rewarded > 0);
    try std.testing.expect(balanced < rewarded);
}

test "reply keys use resulting pieces and color-symmetric destinations" {
    // The relation is derived from board facts after the previous legal move:
    // promotions use the promoted piece, while mirrored colors share one key.
    var white_root: chess.position.PositionState = .{};
    var white = try chess.fen.parse("4k3/8/5n2/8/8/8/7P/4K3 w - - 0 1", &white_root);
    const white_reply = replyContext(&white, chess.move.Move.normal(.g8, .f6));
    try std.testing.expectEqual(chess.types.PieceType.knight, white_reply.previous_piece);

    var black_root: chess.position.PositionState = .{};
    var black = try chess.fen.parse("4k3/7p/8/8/8/5N2/8/4K3 b - - 0 1", &black_root);
    const black_reply = replyContext(&black, chess.move.Move.normal(.g1, .f3));
    try std.testing.expectEqual(white_reply, black_reply);

    var state: State = .{};
    const white_move = chess.move.Move.normal(.h2, .h3);
    const black_move = chess.move.Move.normal(.h7, .h6);
    state.recordReplySuccess(&white, white_reply, white_move, 4, false);
    try std.testing.expectEqual(
        state.replyScore(&white, white_reply, white_move),
        state.replyScore(&black, black_reply, black_move),
    );

    var promoted_root: chess.position.PositionState = .{};
    var promoted_child: chess.position.PositionState = .{};
    var promoted = try chess.fen.parse("4k3/P7/8/8/8/8/7K/8 w - - 0 1", &promoted_root);
    const promotion = chess.move.Move.promotion(.a7, .a8, .queen);
    try std.testing.expect(chess.movegen.isLegal(&promoted, promotion));
    chess.transition.makeMove(&promoted, promotion, &promoted_child);
    const promotion_reply = replyContext(&promoted, promotion);
    try std.testing.expectEqual(chess.types.PieceType.queen, promotion_reply.previous_piece);

    var castling_root: chess.position.PositionState = .{};
    var castling_child: chess.position.PositionState = .{};
    var castled = try chess.fen.parse("4k3/8/8/8/8/8/8/4K2R w K - 0 1", &castling_root);
    const castling = chess.move.Move.castling(.e1, .g1);
    try std.testing.expect(chess.movegen.isLegal(&castled, castling));
    chess.transition.makeMove(&castled, castling, &castling_child);
    try std.testing.expectEqual(chess.types.PieceType.king, replyContext(&castled, castling).previous_piece);

    var ep_root: chess.position.PositionState = .{};
    var ep_child: chess.position.PositionState = .{};
    var ep = try chess.fen.parse("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", &ep_root);
    const en_passant = chess.move.Move.enPassant(.e5, .d6);
    try std.testing.expect(chess.movegen.isLegal(&ep, en_passant));
    chess.transition.makeMove(&ep, en_passant, &ep_child);
    try std.testing.expectEqual(chess.types.PieceType.pawn, replyContext(&ep, en_passant).previous_piece);
}

test "reply outcomes are bounded context-specific quiet ordering evidence" {
    // A reply reward must reorder only the matching quiet relation and bounded
    // gravity must remain reversible under arbitrarily deep updates.
    var root: chess.position.PositionState = .{};
    var value = try chess.fen.parse("4k3/8/5n2/8/8/8/4P2P/4K3 w - - 0 1", &root);
    const reply = replyContext(&value, chess.move.Move.normal(.g8, .f6));
    const preferred = chess.move.Move.normal(.h2, .h3);
    const other = chess.move.Move.normal(.e2, .e3);
    var state: State = .{};
    state.recordReplySuccess(&value, reply, preferred, std.math.maxInt(u16), false);
    try std.testing.expectEqual(@as(i16, 16 * 1024), state.replyScore(&value, reply, preferred));
    try std.testing.expectEqual(@as(i16, 0), state.replyScore(&value, reply, other));

    var moves = chess.position.MoveList.init();
    moves.append(other);
    moves.append(preferred);
    const Binding = struct {
        pub fn seeAtLeast(
            _: @This(),
            _: *const chess.position.Position,
            _: chess.move.Move,
            _: i32,
        ) bool {
            unreachable;
        }
    };
    orderWithReply(&moves, &value, Binding{}, null, &state, 0, reply);
    try std.testing.expectEqual(preferred, moves.slice()[0]);

    state.recordReplyFailure(&value, reply, preferred, std.math.maxInt(u16), false);
    try std.testing.expectEqual(@as(i16, -16 * 1024), state.replyScore(&value, reply, preferred));
    state.clear();
    try std.testing.expectEqual(@as(i16, 0), state.replyScore(&value, reply, preferred));
}

test "history tuning weights only contextual quiet-ordering evidence" {
    // SCORE-013/SCORE-018: zeroing the reply coordinate must leave the stable
    // list order intact, while the accepted 100% scale reproduces the existing
    // contextual preference. Scaling is signed, linear and allocation-free.
    try std.testing.expectEqual(@as(i32, 37), weightedHistory(37, 100));
    try std.testing.expectEqual(@as(i32, -37), weightedHistory(-37, 100));
    try std.testing.expectEqual(@as(i32, 0), weightedHistory(37, 0));
    try std.testing.expectEqual(@as(i32, 74), weightedHistory(37, 200));

    var root: chess.position.PositionState = .{};
    var value = try chess.fen.parse("4k3/8/5n2/8/8/8/4P2P/4K3 w - - 0 1", &root);
    const reply = replyContext(&value, chess.move.Move.normal(.g8, .f6));
    const preferred = chess.move.Move.normal(.h2, .h3);
    const other = chess.move.Move.normal(.e2, .e3);
    var state: State = .{};
    state.recordReplySuccess(&value, reply, preferred, 8, false);
    const Binding = struct {
        pub fn seeAtLeast(_: @This(), _: *const chess.position.Position, _: chess.move.Move, _: i32) bool {
            unreachable;
        }
    };

    var unweighted_moves = chess.position.MoveList.init();
    unweighted_moves.append(other);
    unweighted_moves.append(preferred);
    var unweighted = Picker.init(
        false,
        &unweighted_moves,
        &value,
        Binding{},
        null,
        &state,
        .{ .reply_history_weight = 0 },
        0,
        reply,
        .{},
        true,
        true,
    );
    try std.testing.expectEqual(other, unweighted.next().?.chess_move);

    var accepted_moves = chess.position.MoveList.init();
    accepted_moves.append(other);
    accepted_moves.append(preferred);
    var accepted = Picker.init(
        false,
        &accepted_moves,
        &value,
        Binding{},
        null,
        &state,
        .{},
        0,
        reply,
        .{},
        true,
        true,
    );
    try std.testing.expectEqual(preferred, accepted.next().?.chess_move);
}

test "continuation evidence separates check tactical and color-symmetric facts" {
    // Historical move facts are immutable relation inputs: check and tactical
    // contexts must not alias, while rank-flipped colors address one entry.
    var white_root: chess.position.PositionState = .{};
    var white = try chess.fen.parse("4k3/8/8/8/8/8/4P2P/4K3 w - - 0 1", &white_root);
    var black_root: chess.position.PositionState = .{};
    var black = try chess.fen.parse("4k3/4p2p/8/8/8/8/8/4K3 b - - 0 1", &black_root);
    const white_move = chess.move.Move.normal(.h2, .h3);
    const black_move = chess.move.Move.normal(.h7, .h6);
    const ordinary = continuationContext(.white, .knight, .f6, false, false);
    const mirrored = continuationContext(.black, .knight, .f3, false, false);
    const from_check = continuationContext(.white, .knight, .f6, true, false);
    const tactical = continuationContext(.white, .knight, .f6, false, true);
    try std.testing.expectEqual(ordinary, mirrored);

    var state: State = .{};
    state.recordContinuationSuccess(&white, ordinary, white_move, std.math.maxInt(u16), false);
    try std.testing.expectEqual(
        state.continuationScore(&white, ordinary, white_move),
        state.continuationScore(&black, mirrored, black_move),
    );
    try std.testing.expectEqual(@as(i16, 16 * 1024), state.continuationScore(&white, ordinary, white_move));
    try std.testing.expectEqual(@as(i16, 0), state.continuationScore(&white, from_check, white_move));
    try std.testing.expectEqual(@as(i16, 0), state.continuationScore(&white, tactical, white_move));
    state.recordContinuationFailure(&white, ordinary, white_move, std.math.maxInt(u16), false);
    try std.testing.expectEqual(@as(i16, -16 * 1024), state.continuationScore(&white, ordinary, white_move));
}

test "quiet confidence uses relation consensus rather than raw magnitude" {
    // PERF-010: one saturated relation cannot dominate two independently
    // populated contrary relations. Unknown and tied evidence remain neutral,
    // while a strict majority supplies only a direction to LMR.
    var root: chess.position.PositionState = .{};
    var value = try chess.fen.parse("4k3/8/8/8/8/8/4P2P/4K3 w - - 0 1", &root);
    const chess_move = chess.move.Move.normal(.h2, .h3);
    const reply = ReplyContext{ .previous_piece = .knight, .previous_to = .f6 };
    const first = continuationContext(.white, .bishop, .c5, false, false);
    const second = continuationContext(.white, .rook, .e8, false, false);
    const continuations = ContinuationSet{ .items = .{ first, second, null } };
    var state: State = .{};
    try std.testing.expectEqual(
        HistoryConfidence.neutral,
        state.quietConfidence(&value, reply, continuations, chess_move),
    );

    state.recordReplySuccess(&value, reply, chess_move, std.math.maxInt(u16), false);
    state.recordContinuationFailure(&value, first, chess_move, 2, false);
    try std.testing.expectEqual(
        HistoryConfidence.neutral,
        state.quietConfidence(&value, reply, continuations, chess_move),
    );
    state.recordContinuationFailure(&value, second, chess_move, 2, false);
    try std.testing.expectEqual(
        HistoryConfidence.negative,
        state.quietConfidence(&value, reply, continuations, chess_move),
    );
}

test "capture keys are color symmetric and preserve special-move facts" {
    // SCORE-017/QUAL-014: the key is derived from legal pre-move board facts.
    // Mirrored colors share evidence, en passant names its off-square pawn,
    // and promotion results remain distinct rather than colliding as pawns.
    var white_root: chess.position.PositionState = .{};
    var white = try chess.fen.parse("4k3/8/3p4/8/4N3/8/8/4K3 w - - 0 1", &white_root);
    const white_capture = chess.move.Move.normal(.e4, .d6);
    try std.testing.expect(chess.movegen.isLegal(&white, white_capture));

    var black_root: chess.position.PositionState = .{};
    var black = try chess.fen.parse("4k3/8/8/4n3/8/3P4/8/4K3 b - - 0 1", &black_root);
    const black_capture = chess.move.Move.normal(.e5, .d3);
    try std.testing.expect(chess.movegen.isLegal(&black, black_capture));

    var state: State = .{};
    state.recordCaptureSuccess(&white, white_capture, 5);
    try std.testing.expectEqual(
        state.captureScore(&white, white_capture),
        state.captureScore(&black, black_capture),
    );

    var ep_root: chess.position.PositionState = .{};
    var ep = try chess.fen.parse("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", &ep_root);
    const en_passant = chess.move.Move.enPassant(.e5, .d6);
    try std.testing.expect(chess.movegen.isLegal(&ep, en_passant));
    state.recordCaptureSuccess(&ep, en_passant, 4);
    try std.testing.expect(state.captureScore(&ep, en_passant) > 0);

    var promotion_root: chess.position.PositionState = .{};
    var promotion = try chess.fen.parse("1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1", &promotion_root);
    const queen_capture = chess.move.Move.promotion(.a7, .b8, .queen);
    const knight_capture = chess.move.Move.promotion(.a7, .b8, .knight);
    try std.testing.expect(chess.movegen.isLegal(&promotion, queen_capture));
    try std.testing.expect(chess.movegen.isLegal(&promotion, knight_capture));
    state.recordCaptureSuccess(&promotion, queen_capture, 6);
    try std.testing.expect(state.captureScore(&promotion, queen_capture) > 0);
    try std.testing.expectEqual(@as(i16, 0), state.captureScore(&promotion, knight_capture));
}

test "capture outcomes reorder only their tactical stage and remain bounded" {
    // SCORE-017: learned evidence breaks ties inside an existing SEE stage;
    // disabling its consumer preserves generation order exactly.
    var root: chess.position.PositionState = .{};
    var value = try chess.fen.parse("4k3/8/8/1p1p4/8/2N5/8/4K3 w - - 0 1", &root);
    const first = chess.move.Move.normal(.c3, .b5);
    const preferred = chess.move.Move.normal(.c3, .d5);
    try std.testing.expect(chess.movegen.isLegal(&value, first));
    try std.testing.expect(chess.movegen.isLegal(&value, preferred));

    var state: State = .{};
    state.recordCaptureSuccess(&value, preferred, std.math.maxInt(u16));
    try std.testing.expectEqual(@as(i16, State.history_limit), state.captureScore(&value, preferred));
    state.recordCaptureFailure(&value, first, std.math.maxInt(u16));
    try std.testing.expectEqual(@as(i16, -State.history_limit), state.captureScore(&value, first));

    const Binding = struct {
        pub fn seeAtLeast(
            _: @This(),
            _: *const chess.position.Position,
            _: chess.move.Move,
            _: i32,
        ) bool {
            return true;
        }
    };
    var disabled_moves = chess.position.MoveList.init();
    disabled_moves.append(first);
    disabled_moves.append(preferred);
    var disabled = Picker.init(false, &disabled_moves, &value, Binding{}, null, &state, .{}, 0, null, .{}, true, true);
    try std.testing.expectEqual(first, disabled.next().?.chess_move);

    var enabled_moves = chess.position.MoveList.init();
    enabled_moves.append(first);
    enabled_moves.append(preferred);
    var enabled = Picker.init(true, &enabled_moves, &value, Binding{}, null, &state, .{}, 0, null, .{}, true, true);
    try std.testing.expectEqual(preferred, enabled.next().?.chess_move);
    state.clear();
    try std.testing.expectEqual(@as(i16, 0), state.captureScore(&value, preferred));
}

test "correction history is bounded, side-separated and cleared" {
    var state: State = .{};
    const key: chess.types.Key = 0x0123_4567_89AB_CDEF;

    try std.testing.expectEqual(@as(i32, 0), state.correction(.white, key));

    // One observation moves the entry toward the evidence without reaching it:
    // a single search is evidence about a bias, not proof of its size.
    state.recordCorrection(.white, key, 40, 16);
    const first = state.correction(.white, key);
    try std.testing.expect(first > 0);
    try std.testing.expect(first < 40);

    // The other side's entry for the same structure is untouched. A pawn
    // structure that favours one side is not the same fact for its opponent.
    try std.testing.expectEqual(@as(i32, 0), state.correction(.black, key));

    // Repeated agreeing evidence converges on the cap and never passes it,
    // whatever the evidence claims. Integer division leaves the entry a little
    // short of the cap, so the contract asserted here is the bound itself.
    var index: usize = 0;
    while (index < 4096) : (index += 1) state.recordCorrection(.white, key, 10_000, 64);
    const saturated = state.correction(.white, key);
    try std.testing.expect(saturated <= State.correction_cap);
    try std.testing.expect(saturated >= State.correction_cap - 1);

    index = 0;
    while (index < 4096) : (index += 1) state.recordCorrection(.black, key, -10_000, 64);
    const negative = state.correction(.black, key);
    try std.testing.expect(negative >= -State.correction_cap);
    try std.testing.expect(negative <= -State.correction_cap + 1);

    // A deeper search moves the entry further than a shallow one from the same
    // starting point, which is the whole reason depth is passed in.
    var shallow: State = .{};
    var deep: State = .{};
    shallow.recordCorrection(.white, key, 400, 1);
    deep.recordCorrection(.white, key, 400, 16);
    try std.testing.expect(deep.correction(.white, key) > shallow.correction(.white, key));

    state.clear();
    try std.testing.expectEqual(@as(i32, 0), state.correction(.white, key));
    try std.testing.expectEqual(@as(i32, 0), state.correction(.black, key));
}

test "correction slots stay inside the table for any key" {
    var state: State = .{};
    // The slot reduction must be total: a key is an arbitrary 64-bit value and
    // an out-of-range slot would be memory corruption, not a wrong score.
    const keys = [_]chess.types.Key{
        0,
        1,
        std.math.maxInt(chess.types.Key),
        State.correction_slots,
        State.correction_slots - 1,
    };
    for (keys) |key| {
        try std.testing.expect(State.correctionSlot(key) < State.correction_slots);
        var index: usize = 0;
        while (index < 64) : (index += 1) state.recordCorrection(.white, key, 25, 16);
        try std.testing.expect(state.correction(.white, key) > 0);
    }
}
