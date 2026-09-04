//! Versioned, allocation-free scalar HCE throughput benchmark.
const std = @import("std");
const builtin = @import("builtin");
const manta = @import("manta");

const schema = "manta-hce-bench-v2";
const sample_count = 11;
const sample_ns = 150 * std.time.ns_per_ms;
// Re-recorded at each evaluator change: 354 at the Step-3.2 bootstrap, 100
// once Step 5.3.1 scored unwinnable material as drawn, 80 for the Step-5.3.3
// to 5.3.5 king-safety work and 86 for Step-5.3.6 threats and space. Step
// 5.3.8 imbalance left it at 86 because the only corpus position it moves is
// the one the unwinnable clamp already forces to zero, Step 5.3.10 pawn
// completion took it to 60 Step 5.3.11 piece detail to 2 and
// Step 5.3.12 threat and king-safety completion to -95, Step 5.3.13 endgame
// recognition to -85 through the supported KPK case and Step 5.3.14
// winnability to -82 through the pawn ending and Step 5.3.15R.1 pawn ownership
// and graded passer paths to -44, then Step 5.3.15R.2 legal attacks and central
// space to 23. Step 5.3.15R.3 leaves the sum at 23 because its king-safety
// changes offset across the corpus. Step 5.3.15R.4 exact KPK and completed
// winnability move it to -166. The constrained Step-5.3.16 fit moves it to
// -260 through the intentionally changed coefficient vector. The corpus
// itself is unchanged throughout, so throughput stays comparable across all of
// them.
// See `docs/EVAL_BENCHMARK.md` for the full history and the schema contract.
const expected_checksum: i64 = -260;
const fens = [_][]const u8{
    manta.chess.fen.start_position,
    "r3k2r/p1ppqpb1/bn2pnp1/2pP4/1p2P3/2N2N2/PPQBBPPP/R3K2R w KQkq - 0 1",
    "8/2p5/3p4/1P1P4/8/4k3/8/4K3 w - - 0 40",
    "4k3/8/8/3P4/8/8/4K3/8 w - - 0 1",
    "4k3/8/8/8/8/2n5/3P4/4K3 b - - 0 1",
};

const Options = struct { preflight_only: bool = false };

const Slot = struct {
    root: manta.chess.position.PositionState,
    position: manta.chess.position.Position,
};

const Suite = struct {
    slots: [fens.len]Slot,
    /// One evaluator state has the same lifetime as one search worker. Step
    /// 5.3.13 made that state nonzero with a pawn cache; rebuilding it per
    /// iteration would benchmark cache clearing rather than evaluation.
    evaluator_state: manta.eval.hce.Hce.State,

    fn init(self: *Suite) !void {
        self.evaluator_state = .{};
        for (fens, 0..) |fen_text, index| {
            self.slots[index].root = .{};
            self.slots[index].position = try manta.chess.fen.parse(fen_text, &self.slots[index].root);
            self.slots[index].position.rebind(&self.slots[index].root);
        }
    }
};

pub fn main(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const options = parseOptions(args) catch |err| {
        std.debug.print("HCE benchmark: {s}\n", .{@errorName(err)});
        printUsage();
        return 2;
    };
    run(init.io, options.preflight_only) catch |err| {
        std.debug.print("HCE benchmark: FAIL ({s})\n", .{@errorName(err)});
        return 1;
    };
    return 0;
}

fn run(io: std.Io, preflight_only: bool) !void {
    // SAFETY: `Suite.init` initializes every slot before preflight or timing.
    var suite: Suite = undefined;
    try suite.init();
    try preflight(&suite);
    const scores = evaluateScores(&suite);
    std.debug.print(
        "Manta HCE benchmark\nschema: {s}\nbuild: {s}\ntarget: {s}-{s}\n" ++
            "positions: {d}\nwork: {d} full-refresh scalar evaluations/iteration\n" ++
            "scores: {d},{d},{d},{d},{d}\n" ++
            "samples: 11 x 150 ms (median +/- MAD)\npreflight: PASS\n",
        .{
            schema,
            @tagName(builtin.mode),
            @tagName(builtin.cpu.arch),
            @tagName(builtin.os.tag),
            fens.len,
            fens.len,
            scores[0],
            scores[1],
            scores[2],
            scores[3],
            scores[4],
        },
    );
    if (preflight_only) return;

    const result = try measure(io, &suite);
    std.debug.print(
        "throughput: {d:.0} eval/s\nMAD: {d:.0} eval/s ({d:.2}%)\n" ++
            "total iterations: {d}\nchecksum/iteration: {d}\n",
        .{
            result.estimate,
            result.mad,
            100.0 * result.mad / result.estimate,
            result.iterations,
            expected_checksum,
        },
    );
}

const Result = struct { estimate: f64, mad: f64, iterations: u64 };

fn preflight(suite: *Suite) !void {
    const actual = evaluateCorpus(suite);
    if (actual != expected_checksum) {
        std.debug.print("checksum mismatch: expected {d}, actual {d}\n", .{ expected_checksum, actual });
        return error.ChecksumMismatch;
    }
}

fn measure(io: std.Io, suite: *Suite) !Result {
    const warmup_started = std.Io.Clock.awake.now(io).nanoseconds;
    while (std.Io.Clock.awake.now(io).nanoseconds - warmup_started < sample_ns) {
        if (evaluateCorpus(suite) != expected_checksum) return error.ChecksumMismatch;
    }
    const batch = try calibrateBatch(io, suite);

    var samples: [sample_count]f64 = undefined;
    var total_iterations: u64 = 0;
    for (&samples) |*sample| {
        var iterations: u64 = 0;
        var checksum: i64 = 0;
        const started = std.Io.Clock.awake.now(io).nanoseconds;
        while (std.Io.Clock.awake.now(io).nanoseconds - started < sample_ns) {
            for (0..batch) |_| checksum +%= evaluateCorpus(suite);
            iterations += batch;
        }
        const finished = std.Io.Clock.awake.now(io).nanoseconds;
        if (finished <= started or checksum != expected_checksum *% @as(i64, @intCast(iterations)))
            return error.InvalidMeasurement;
        std.mem.doNotOptimizeAway(checksum);
        total_iterations += iterations;
        const seconds = @as(f64, @floatFromInt(finished - started)) / std.time.ns_per_s;
        sample.* = @as(f64, @floatFromInt(iterations * fens.len)) / seconds;
    }

    const estimate = median(&samples);
    var deviations: [sample_count]f64 = undefined;
    for (samples, &deviations) |sample, *deviation| deviation.* = @abs(sample - estimate);
    return .{ .estimate = estimate, .mad = median(&deviations), .iterations = total_iterations };
}

fn calibrateBatch(io: std.Io, suite: *Suite) !u64 {
    const probes = 32;
    const started = std.Io.Clock.awake.now(io).nanoseconds;
    for (0..probes) |_| {
        if (evaluateCorpus(suite) != expected_checksum) return error.ChecksumMismatch;
    }
    const elapsed = std.Io.Clock.awake.now(io).nanoseconds - started;
    if (elapsed <= 0) return 1_000_000;
    const per_iteration = @divTrunc(elapsed, probes);
    if (per_iteration == 0) return 1_000_000;
    const batch = @divTrunc(@as(@TypeOf(elapsed), std.time.ns_per_ms), per_iteration);
    return @intCast(std.math.clamp(batch, 1, 1_000_000));
}

fn evaluateCorpus(suite: *Suite) i64 {
    var checksum: i64 = 0;
    var sink: manta.eval.trace.Disabled = .{};
    for (&suite.slots) |*slot| {
        std.mem.doNotOptimizeAway(&slot.position);
        const value = manta.eval.hce.Hce.evaluate(
            manta.eval.trace.Disabled,
            &.{},
            &suite.evaluator_state,
            &slot.position,
            &sink,
        );
        std.mem.doNotOptimizeAway(value);
        checksum += value.raw();
    }
    return checksum;
}

fn evaluateScores(suite: *Suite) [fens.len]i32 {
    var result: [fens.len]i32 = undefined;
    var sink: manta.eval.trace.Disabled = .{};
    for (&suite.slots, &result) |*slot, *entry| {
        entry.* = manta.eval.hce.Hce.evaluate(
            manta.eval.trace.Disabled,
            &.{},
            &suite.evaluator_state,
            &slot.position,
            &sink,
        ).raw();
    }
    return result;
}

fn median(values: []const f64) f64 {
    var copy: [sample_count]f64 = undefined;
    @memcpy(copy[0..values.len], values);
    std.mem.sort(f64, copy[0..values.len], {}, std.sort.asc(f64));
    return copy[values.len / 2];
}

fn parseOptions(args: []const []const u8) !Options {
    var result: Options = .{};
    for (args[1..]) |argument| {
        if (std.mem.eql(u8, argument, "--preflight-only"))
            result.preflight_only = true
        else
            return error.UnknownArgument;
    }
    return result;
}

fn printUsage() void {
    std.debug.print(
        "usage: zig build eval-bench [-Doptimize=Debug|ReleaseFast] -- [--preflight-only]\n",
        .{},
    );
}

test "HCE benchmark freezes corpus checksum and options" {
    // SAFETY: `Suite.init` initializes every slot before the test observes it.
    var suite: Suite = undefined;
    try suite.init();
    try preflight(&suite);
    try std.testing.expectEqual(expected_checksum, evaluateCorpus(&suite));
    try std.testing.expect(!(try parseOptions(&.{"tool"})).preflight_only);
    try std.testing.expect((try parseOptions(&.{ "tool", "--preflight-only" })).preflight_only);
    try std.testing.expectError(error.UnknownArgument, parseOptions(&.{ "tool", "--other" }));
}
