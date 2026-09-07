//! Lock-free, caller-allocated transposition storage and score normalization.
const std = @import("std");
const chess = @import("../chess/root.zig");
const score = @import("../score.zig");
const types = @import("types.zig");

pub const ways = 4;

/// Exact partition of one store. `retained` is a declined write against an
/// authenticated same-key entry; the two eviction cases separate ordinary
/// ageing from genuine current-generation pressure. Purely diagnostic.
pub const StoreOutcome = enum {
    refreshed,
    retained,
    filled,
    evicted_stale,
    evicted_current,
};

pub const Record = struct {
    chess_move: chess.move.Move,
    value: score.Score,
    /// Exact raw HCE for this keyed position when it fits the compact cache.
    /// This is position evidence, never a searched bound.
    static_eval: ?score.Score,
    depth: u8,
    bound: types.Bound,
    generation: u8,
    producer: types.Provenance,
};

const Entry = struct {
    payload: std.atomic.Value(u64) = .init(0),
    guard: std.atomic.Value(u64) = .init(0),

    fn clear(self: *Entry) void {
        self.guard.store(0, .release);
        self.payload.store(0, .monotonic);
    }

    fn probe(self: *const Entry, key: chess.types.Key, ply: usize, rule50: u16) ?Record {
        const guard_before = self.guard.load(.acquire);
        if (guard_before == 0) return null;
        const payload = self.payload.load(.monotonic);
        const guard_after = self.guard.load(.acquire);
        if (guard_before != guard_after or guard_after != validation(key, payload)) return null;
        return decode(payload, ply, rule50);
    }

    fn snapshot(self: *const Entry) ?Record {
        const guard_before = self.guard.load(.acquire);
        if (guard_before == 0) return null;
        const payload = self.payload.load(.monotonic);
        if (guard_before != self.guard.load(.acquire)) return null;
        return decode(payload, 0, 0);
    }

    fn store(self: *Entry, key: chess.types.Key, record: Record, ply: usize) void {
        const payload = encode(record, ply);
        // Invalidate first. Release/acquire makes the earlier payload visible
        // after the final guard; the repeated guard and key checksum reject a
        // mixed observation as a miss.
        self.guard.store(0, .release);
        self.payload.store(payload, .monotonic);
        self.guard.store(validation(key, payload), .release);
    }
};

pub const Cluster = struct {
    entries: [ways]Entry align(64) = @splat(.{}),
};

pub const Table = struct {
    clusters: []Cluster,
    generation: u8 = 0,

    pub fn init(storage: []Cluster) Table {
        std.debug.assert(storage.len != 0);
        var result = Table{ .clusters = storage };
        result.clear();
        return result;
    }

    pub fn clear(self: *Table) void {
        for (self.clusters) |*cluster| {
            for (&cluster.entries) |*entry| entry.clear();
        }
        self.generation = 0;
    }

    pub fn nextGeneration(self: *Table) void {
        self.generation +%= 1;
    }

    pub fn probe(self: *const Table, key: chess.types.Key, ply: usize, rule50: u16) ?Record {
        const cluster = &self.clusters[index(self, key)];
        for (&cluster.entries) |*entry| {
            if (entry.probe(key, ply, rule50)) |record| return record;
        }
        return null;
    }

    /// Returns which replacement path the write took. The outcome is
    /// diagnostic only: it names the branch that was already taken and can
    /// change no stored value, so an observer may read table pressure without
    /// the table gaining a dependency on one.
    pub fn store(
        self: *Table,
        key: chess.types.Key,
        chess_move: chess.move.Move,
        value: score.Score,
        static_eval: ?score.Score,
        depth: u8,
        bound: types.Bound,
        producer: types.Provenance,
        ply: usize,
    ) StoreOutcome {
        var record = Record{
            .chess_move = chess_move,
            .value = value,
            .static_eval = compactStaticEval(static_eval),
            .depth = depth,
            .bound = bound,
            .generation = self.generation,
            .producer = producer,
        };
        const cluster = &self.clusters[index(self, key)];

        for (&cluster.entries) |*entry| {
            if (entry.probe(key, ply, 0)) |old| {
                // A later search store may not have evaluated a checked or
                // terminal path. Preserve an earlier exact raw evaluation of
                // the same authenticated position rather than erasing it.
                if (record.static_eval == null) record.static_eval = old.static_eval;
                if (depth >= old.depth or bound == .exact or old.generation != self.generation) {
                    entry.store(key, record, ply);
                    return .refreshed;
                }
                return .retained;
            }
        }
        for (&cluster.entries) |*entry| {
            if (entry.snapshot() == null) {
                entry.store(key, record, ply);
                return .filled;
            }
        }

        var victim: usize = 0;
        var victim_record = cluster.entries[0].snapshot().?;
        for (cluster.entries[1..], 1..) |*entry, slot| {
            const candidate = entry.snapshot() orelse {
                victim = slot;
                break;
            };
            if (preferVictim(self.generation, candidate, victim_record)) {
                victim = slot;
                victim_record = candidate;
            }
        }
        cluster.entries[victim].store(key, record, ply);
        return if (victim_record.generation == self.generation) .evicted_current else .evicted_stale;
    }

    fn index(self: *const Table, key: chess.types.Key) usize {
        return @intCast(key % self.clusters.len);
    }
};

fn preferVictim(current: u8, candidate: Record, incumbent: Record) bool {
    const candidate_age = current -% candidate.generation;
    const incumbent_age = current -% incumbent.generation;
    if (candidate_age != incumbent_age) return candidate_age > incumbent_age;
    if (candidate.depth != incumbent.depth) return candidate.depth < incumbent.depth;
    if ((candidate.bound == .exact) != (incumbent.bound == .exact)) return candidate.bound != .exact;
    return false;
}

/// Distance-relative scores are stored relative to the searched position
/// rather than the root, because the same position transposes to different
/// plies. Tablebase scores need this exactly as much as mate scores do: both
/// encode a distance in their magnitude, and the transposition key contains no
/// ply. Only ordinary evaluations are stored verbatim.
fn isDistanceRelative(value: score.Score) bool {
    return value.isMate() or value.isTablebase();
}

pub fn scoreToTable(value: score.Score, ply: usize) score.Score {
    std.debug.assert(value.isValid() and !value.isNone() and value.raw() != score.infinity_raw);
    if (!isDistanceRelative(value)) return value;
    return .{ .raw_value = if (value.raw() > 0)
        value.raw() + @as(i32, @intCast(ply))
    else
        value.raw() - @as(i32, @intCast(ply)) };
}

/// Decodes a stored score back to this node's perspective.
///
/// `rule50` guards against publishing a mate the fifty-move rule forbids. A
/// mate stored `d` plies away is only deliverable if `d` fits in the remaining
/// allowance; otherwise the game is drawn first and the stored distance is a
/// promise the rules will not honour. Such a score is demoted to the edge of
/// the mate band, which keeps it decisive without asserting a false distance.
pub fn scoreFromTableWithClock(value: score.Score, ply: usize, rule50: u16) score.Score {
    std.debug.assert(value.isValid() and !value.isNone() and value.raw() != score.infinity_raw);
    if (value.isMate()) {
        const distance = score.mate_raw - @as(i32, @intCast(@abs(value.raw())));
        const remaining: i32 = 99 - @as(i32, @intCast(@min(rule50, 99)));
        if (distance > remaining) {
            return .{ .raw_value = if (value.raw() > 0)
                score.mate_min_raw
            else
                -score.mate_min_raw };
        }
    }
    return scoreFromTable(value, ply);
}

pub fn scoreFromTable(value: score.Score, ply: usize) score.Score {
    std.debug.assert(value.isValid() and !value.isNone() and value.raw() != score.infinity_raw);
    if (!isDistanceRelative(value)) return value;
    return .{ .raw_value = if (value.raw() > 0)
        value.raw() - @as(i32, @intCast(ply))
    else
        value.raw() + @as(i32, @intCast(ply)) };
}

fn encode(record: Record, ply: usize) u64 {
    const stored = scoreToTable(record.value, ply);
    std.debug.assert(stored.raw() >= std.math.minInt(i16) and stored.raw() <= std.math.maxInt(i16));
    const score_bits: u16 = @bitCast(@as(i16, @intCast(stored.raw())));
    const static_bits = encodeStaticEval(record.static_eval);
    return @as(u64, record.chess_move.raw()) |
        (@as(u64, score_bits) << 16) |
        (@as(u64, record.depth) << 32) |
        (@as(u64, @intFromEnum(record.bound)) << 40) |
        (@as(u64, record.generation) << 42) |
        (@as(u64, @intFromEnum(record.producer)) << 50) |
        (@as(u64, static_bits) << 55);
}

fn decode(payload: u64, ply: usize, rule50: u16) Record {
    const stored_bits: u16 = @truncate(payload >> 16);
    const stored_raw: i16 = @bitCast(stored_bits);
    return .{
        .chess_move = .{ .raw_value = @truncate(payload) },
        .value = scoreFromTableWithClock(.{ .raw_value = stored_raw }, ply, rule50),
        .static_eval = decodeStaticEval(@truncate(payload >> 55)),
        .depth = @truncate(payload >> 32),
        .bound = @enumFromInt(@as(u2, @truncate(payload >> 40))),
        .generation = @truncate(payload >> 42),
        .producer = @enumFromInt(@as(u5, @truncate(payload >> 50))),
    };
}

// Nine previously unused payload bits cache every ordinary HCE value in
// [-255, 255] exactly. Zero is reserved for "not cached"; outliers remain
// valid searched scores but deliberately carry no static evidence. Keeping
// every existing bit in place makes the feature-off payload and replacement
// behavior exact MAN-S17 while preserving the 16-byte entry/four-way cluster.
const static_eval_limit: i32 = 255;

fn compactStaticEval(value: ?score.Score) ?score.Score {
    const present = value orelse return null;
    if (!present.isOrdinary() or present.raw() < -static_eval_limit or
        present.raw() > static_eval_limit) return null;
    return present;
}

fn encodeStaticEval(value: ?score.Score) u9 {
    const present = compactStaticEval(value) orelse return 0;
    return @intCast(present.raw() + static_eval_limit + 1);
}

fn decodeStaticEval(bits: u9) ?score.Score {
    if (bits == 0) return null;
    return score.Score.fromOrdinary(@as(i32, bits) - static_eval_limit - 1).?;
}

fn validation(key: chess.types.Key, payload: u64) u64 {
    return key ^ payload;
}

comptime {
    std.debug.assert(@sizeOf(Entry) == 16);
    std.debug.assert(@sizeOf(Cluster) == 64);
    std.debug.assert(@alignOf(Cluster) == 64);
    std.debug.assert(@typeInfo(types.Provenance).@"enum".fields.len <= 16);
}

test "mate normalization is independent of storage ply" {
    // SCORE-004: the same node-relative mate must decode at a new root ply.
    const win = score.Score.mateIn(11).?;
    const loss = score.Score.matedIn(13).?;
    try std.testing.expectEqual(win, scoreFromTable(scoreToTable(win, 7), 7));
    try std.testing.expectEqual(loss, scoreFromTable(scoreToTable(loss, 5), 5));
    try std.testing.expectEqual(score.Score.mateIn(15).?, scoreFromTable(scoreToTable(win, 7), 11));
    try std.testing.expectEqual(score.Score.matedIn(16).?, scoreFromTable(scoreToTable(loss, 5), 8));
}

test "atomic payload validation turns mixed observations into misses" {
    // SAFE-009: a payload not authenticated by both guard reads is never trusted.
    var storage: [1]Cluster = undefined;
    var table = Table.init(&storage);
    const key: u64 = 0x1234_5678_9abc_def0;
    _ = table.store(key, chess.move.Move.normal(.e2, .e4), score.Score.fromOrdinary(42).?, score.Score.fromOrdinary(-17), 6, .exact, .full_search, 3);
    try std.testing.expectEqual(@as(i32, -17), table.probe(key, 3, 0).?.static_eval.?.raw());
    storage[0].entries[0].payload.store(0xfeed_face, .monotonic);
    try std.testing.expect(table.probe(key, 3, 0) == null);
}

test "same-position store preserves an unavailable raw evaluation" {
    // SCORE-020: checked/terminal search paths cannot erase exact position
    // evidence previously cached under the same authenticated key.
    var storage: [1]Cluster = undefined;
    var table = Table.init(&storage);
    const key: u64 = 0x8765_4321;
    try std.testing.expectEqual(
        StoreOutcome.filled,
        table.store(key, .none, score.Score.fromOrdinary(12).?, score.Score.fromOrdinary(31), 2, .upper, .full_search, 0),
    );
    try std.testing.expectEqual(
        StoreOutcome.refreshed,
        table.store(key, .none, score.Score.fromOrdinary(40).?, null, 3, .exact, .full_search, 0),
    );
    const record = table.probe(key, 0, 0).?;
    try std.testing.expectEqual(@as(i32, 40), record.value.raw());
    try std.testing.expectEqual(@as(i32, 31), record.static_eval.?.raw());
}

test "replacement is deterministic and prefers oldest then shallowest" {
    // Deterministic 1T replacement protects deeper current-generation evidence.
    var storage: [1]Cluster = undefined;
    var table = Table.init(&storage);
    table.nextGeneration();
    for (0..ways) |slot| {
        _ = table.store(slot + 1, chess.move.Move.normal(.a2, .a3), score.Score.zero, null, @intCast(slot + 1), .upper, .full_search, 0);
    }
    table.nextGeneration();
    // The reported outcome must name the branch actually taken: every way is
    // full and the victim belongs to the previous generation.
    try std.testing.expectEqual(
        StoreOutcome.evicted_stale,
        table.store(99, chess.move.Move.normal(.b2, .b3), score.Score.zero, null, 1, .lower, .full_search, 0),
    );
    try std.testing.expect(table.probe(99, 0, 0) != null);
    try std.testing.expect(table.probe(1, 0, 0) == null);
    try std.testing.expect(table.probe(4, 0, 0) != null);
}

test "compact static evaluation round-trips exactly without changing cluster layout" {
    // SCORE-020/PERF-006: raw HCE is separately recoverable from searched
    // value/bound evidence, while the hot TT remains one cache line per four
    // ways. Out-of-range values become an explicit miss, never a clipped eval.
    inline for (.{ -255, -1, 0, 1, 255 }) |raw| {
        const value = score.Score.fromOrdinary(raw).?;
        try std.testing.expectEqual(value, decodeStaticEval(encodeStaticEval(value)).?);
    }
    try std.testing.expectEqual(@as(?score.Score, null), compactStaticEval(score.Score.fromOrdinary(256)));
    try std.testing.expectEqual(@as(?score.Score, null), decodeStaticEval(0));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Entry));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(Cluster));
}

test "tablebase distances survive storage at a different ply" {
    // SCORE-004/SCORE-005: a tablebase score encodes a distance in its
    // magnitude exactly as a mate score does, and the transposition key holds
    // no ply. Storing at one ply and reading at another must therefore
    // reproduce the node-relative distance, not the storing node's.
    const win = @import("tablebase.zig").toScore(.win, 6, true);
    const stored = scoreToTable(win, 6);
    try std.testing.expectEqual(score.tablebase_max_raw, stored.raw());
    try std.testing.expectEqual(win.raw(), scoreFromTable(stored, 6).raw());
    // Read three plies nearer the root: the win is three plies closer.
    try std.testing.expectEqual(
        @import("tablebase.zig").toScore(.win, 3, true).raw(),
        scoreFromTable(stored, 3).raw(),
    );

    const loss = @import("tablebase.zig").toScore(.loss, 6, true);
    const stored_loss = scoreToTable(loss, 6);
    try std.testing.expectEqual(loss.raw(), scoreFromTable(stored_loss, 6).raw());
    try std.testing.expectEqual(
        @import("tablebase.zig").toScore(.loss, 3, true).raw(),
        scoreFromTable(stored_loss, 3).raw(),
    );

    // An ordinary evaluation carries no distance and must be stored verbatim.
    const ordinary = score.Score.fromOrdinary(37).?;
    try std.testing.expectEqual(ordinary.raw(), scoreToTable(ordinary, 9).raw());
    try std.testing.expectEqual(ordinary.raw(), scoreFromTable(ordinary, 9).raw());
}

test "a stored mate the fifty-move rule forbids is not published as mate distance" {
    // SCORE-004: a mate stored eight plies away cannot be delivered when only
    // three halfmoves of allowance remain, because the draw arrives first.
    // Publishing the stored distance would promise a win the rules refuse.
    const mate_in_8 = score.Score.mateIn(8).?;
    const fresh = scoreFromTableWithClock(mate_in_8, 0, 0);
    try std.testing.expectEqual(mate_in_8.raw(), fresh.raw());

    const starved = scoreFromTableWithClock(mate_in_8, 0, 96);
    try std.testing.expect(starved.isMate());
    try std.testing.expect(starved.raw() < mate_in_8.raw());
    try std.testing.expectEqual(score.mate_min_raw, starved.raw());

    // The mirrored loss is demoted symmetrically.
    const mated_in_8 = score.Score.matedIn(8).?;
    const starved_loss = scoreFromTableWithClock(mated_in_8, 0, 96);
    try std.testing.expectEqual(-score.mate_min_raw, starved_loss.raw());

    // An ordinary score carries no distance and is never demoted.
    const ordinary = score.Score.fromOrdinary(120).?;
    try std.testing.expectEqual(ordinary.raw(), scoreFromTableWithClock(ordinary, 4, 99).raw());
}
