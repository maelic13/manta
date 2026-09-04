//! Search score domain, decisive bands, and evaluator-scale conversion.
const std = @import("std");
const chess_types = @import("chess/types.zig");

pub const max_ply: usize = chess_types.max_ply;
pub const units_per_pawn: i32 = 100;

pub const mate_raw: i32 = 32_000;
pub const infinity_raw: i32 = 32_001;
pub const none_raw: i32 = 32_002;
pub const mate_min_raw: i32 = mate_raw - max_ply;

// Future tablebase scores have one distinct value per possible search ply.
// Search owns their eventual distance semantics; evaluation may not enter them.
pub const tablebase_max_raw: i32 = mate_min_raw - 1;
pub const tablebase_min_raw: i32 = mate_min_raw - max_ply;
pub const ordinary_max_raw: i32 = tablebase_min_raw - 1;

pub const Score = struct {
    raw_value: i32,

    pub const zero: Score = .{ .raw_value = 0 };
    pub const mate: Score = .{ .raw_value = mate_raw };
    pub const infinity: Score = .{ .raw_value = infinity_raw };
    pub const none: Score = .{ .raw_value = none_raw };

    pub fn fromOrdinary(raw_value: i32) ?Score {
        if (raw_value < -ordinary_max_raw or raw_value > ordinary_max_raw) return null;
        return .{ .raw_value = raw_value };
    }

    pub fn mateIn(plies: usize) ?Score {
        if (plies > max_ply) return null;
        return .{ .raw_value = mate_raw - @as(i32, @intCast(plies)) };
    }

    pub fn matedIn(plies: usize) ?Score {
        if (plies > max_ply) return null;
        return .{ .raw_value = -mate_raw + @as(i32, @intCast(plies)) };
    }

    pub fn raw(self: Score) i32 {
        return self.raw_value;
    }

    pub fn isOrdinary(self: Score) bool {
        return self.raw_value >= -ordinary_max_raw and self.raw_value <= ordinary_max_raw;
    }

    pub fn isValid(self: Score) bool {
        return (self.raw_value >= -infinity_raw and self.raw_value <= infinity_raw) or self.isNone();
    }

    pub fn isTablebase(self: Score) bool {
        const magnitude = magnitudeOf(self.raw_value);
        return magnitude >= @as(u32, tablebase_min_raw) and magnitude <= @as(u32, tablebase_max_raw);
    }

    pub fn isMate(self: Score) bool {
        const magnitude = magnitudeOf(self.raw_value);
        return magnitude >= @as(u32, mate_min_raw) and magnitude <= @as(u32, mate_raw);
    }

    pub fn isNone(self: Score) bool {
        return self.raw_value == none_raw;
    }

    pub fn mateDistance(self: Score) ?i32 {
        if (!self.isMate()) return null;
        if (self.raw_value > 0) return mate_raw - self.raw_value;
        return -(mate_raw + self.raw_value);
    }

    pub fn negate(self: Score) ?Score {
        if (!self.isValid() or self.isNone()) return null;
        return .{ .raw_value = -self.raw_value };
    }
};

pub const EvaluatorScale = struct {
    internal_units_per_pawn: u32,

    /// Converts an evaluator-local value to Manta's stable search/cp scale.
    /// Division truncates toward zero, preserving exact color antisymmetry.
    pub fn toSearch(self: EvaluatorScale, internal_value: i32) ?Score {
        if (self.internal_units_per_pawn == 0) return null;
        const numerator = @as(i64, internal_value) * units_per_pawn;
        const converted = @divTrunc(numerator, @as(i64, self.internal_units_per_pawn));
        if (converted < -ordinary_max_raw or converted > ordinary_max_raw) return null;
        return Score.fromOrdinary(@intCast(converted));
    }
};

pub fn toCentipawns(value: Score) ?i32 {
    if (!value.isOrdinary()) return null;
    return value.raw();
}

fn magnitudeOf(value: i32) u32 {
    const widened = @as(i64, value);
    return @intCast(if (widened < 0) -widened else widened);
}

comptime {
    std.debug.assert(@sizeOf(Score) == @sizeOf(i32));
    std.debug.assert(max_ply == 256);
    std.debug.assert(mate_min_raw == 31_744);
    std.debug.assert(tablebase_min_raw == 31_488);
    std.debug.assert(ordinary_max_raw < tablebase_min_raw);
    std.debug.assert(tablebase_max_raw < mate_min_raw);
}

test "score bands separate static evaluation, tablebases, mates, and sentinels" {
    // SCORE-002/SCORE-005: evaluator output cannot collide with decisive proof.
    try std.testing.expect(Score.fromOrdinary(ordinary_max_raw) != null);
    try std.testing.expect(Score.fromOrdinary(tablebase_min_raw) == null);
    try std.testing.expect((Score{ .raw_value = tablebase_min_raw }).isTablebase());
    try std.testing.expect((Score{ .raw_value = -tablebase_max_raw }).isTablebase());
    try std.testing.expect(!(Score{ .raw_value = tablebase_max_raw }).isMate());
    try std.testing.expect((Score.mateIn(max_ply) orelse unreachable).isMate());
    try std.testing.expectEqual(@as(i32, mate_min_raw), (Score.mateIn(max_ply) orelse unreachable).raw());
    try std.testing.expect(Score.mateIn(max_ply + 1) == null);
    try std.testing.expect(Score.none.negate() == null);
    try std.testing.expect(!(Score{ .raw_value = std.math.minInt(i32) }).isMate());
    try std.testing.expect((Score{ .raw_value = std.math.minInt(i32) }).negate() == null);
}

test "mate distance follows signed side-to-move ply semantics" {
    // SCORE-004: wins and losses preserve their distance and ordering bands.
    const win = Score.mateIn(7) orelse unreachable;
    const loss = Score.matedIn(7) orelse unreachable;
    try std.testing.expectEqual(@as(?i32, 7), win.mateDistance());
    try std.testing.expectEqual(@as(?i32, -7), loss.mateDistance());
    try std.testing.expectEqual(loss, win.negate().?);
    try std.testing.expectEqual(Score.matedIn(0).?, Score.mate.negate().?);
}

test "evaluator scale conversion is color-antisymmetric and cp-safe" {
    // SCORE-001/SCORE-008: later internal scales cross one explicit boundary.
    const scale = EvaluatorScale{ .internal_units_per_pawn = 256 };
    const positive = scale.toSearch(385) orelse unreachable;
    const negative = scale.toSearch(-385) orelse unreachable;
    try std.testing.expectEqual(@as(i32, 150), positive.raw());
    try std.testing.expectEqual(-positive.raw(), negative.raw());
    try std.testing.expectEqual(positive.raw(), toCentipawns(positive).?);
    try std.testing.expect(toCentipawns(Score.mate) == null);
    try std.testing.expect((EvaluatorScale{ .internal_units_per_pawn = 0 }).toSearch(1) == null);
}
