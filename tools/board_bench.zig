//! Versioned, allocation-free board-operation benchmark and work manifest.
const std = @import("std");
const builtin = @import("builtin");
const manta = @import("manta");

const chess = manta.chess;
const schema = "manta-board-bench-v1";
const sample_count = 11;
const timed_sample_ns = 150 * std.time.ns_per_ms;

const Workload = enum {
    legal_moves,
    legal_captures,
    make_unmake,
    threshold_see,
    check_detection,
    perft_startpos_d4,
    two_ply_simulation,

    fn label(self: Workload) []const u8 {
        return switch (self) {
            .legal_moves => "legal moves",
            .legal_captures => "legal captures",
            .make_unmake => "make/unmake",
            .threshold_see => "threshold SEE",
            .check_detection => "check detection",
            .perft_startpos_d4 => "perft(4) startpos",
            .two_ply_simulation => "two-ply simulation",
        };
    }

    fn unit(self: Workload) []const u8 {
        return switch (self) {
            .legal_moves, .legal_captures, .make_unmake, .two_ply_simulation => "moves",
            .threshold_see => "captures",
            .check_detection => "positions",
            .perft_startpos_d4 => "nodes",
        };
    }
};

const Estimator = enum { timed_median_mad, fixed_median_mad, best_of_three };

const WorkSpec = struct {
    workload: Workload,
    iterations: usize,
    warmups: usize,
    expected_ops: u64,
};

const Profile = struct {
    name: []const u8,
    fens: *const [5][]const u8,
    specs: [6]WorkSpec,
    estimator: Estimator,
};

const corpus_a = [5][]const u8{
    chess.fen.start_position,
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    "rnbq1k1r/pppp1ppp/4pn2/8/1b1PP3/2N2N2/PPP2PPP/R1BQKB1R w KQ - 2 5",
    "8/2p5/3p4/KP5r/8/8/8/7k w - - 0 1",
    "rnbqkb1r/pppp1ppp/5n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 3 3",
};

const corpus_b = [5][]const u8{
    chess.fen.start_position,
    corpus_a[1],
    corpus_a[2],
    "8/8/3p4/KPp4r/8/8/8/7k w - c6 0 1",
    corpus_a[4],
};

const see_values = chess.see.PieceValues{
    .pawn = 100,
    .knight = 300,
    .bishop = 300,
    .rook = 500,
    .queen = 900,
    .king = 20_000,
};

const expected_a = [6]u64{ 128, 10, 128, 10, 197_281, 4_597 };
const expected_b = [6]u64{ 129, 10, 129, 5, 197_281, 4_603 };

fn crossProfile() Profile {
    return .{
        .name = "cross-engine-board-v1",
        .fens = &corpus_a,
        .estimator = .timed_median_mad,
        .specs = fixedSpecs(expected_a),
    };
}

fn legacyAProfile() Profile {
    return .{
        .name = "legacy-board-a-v1",
        .fens = &corpus_a,
        .estimator = .fixed_median_mad,
        .specs = fixedSpecs(expected_a),
    };
}

fn legacyBProfile() Profile {
    const debug = builtin.mode == .Debug;
    return .{
        .name = "legacy-board-b-v1",
        .fens = &corpus_b,
        .estimator = .best_of_three,
        .specs = .{
            .{ .workload = .legal_moves, .iterations = if (debug) 20 else 5_000, .warmups = 5, .expected_ops = expected_b[0] },
            .{ .workload = .legal_captures, .iterations = if (debug) 50 else 10_000, .warmups = 5, .expected_ops = expected_b[1] },
            .{ .workload = .make_unmake, .iterations = if (debug) 10 else 2_000, .warmups = 5, .expected_ops = expected_b[2] },
            .{ .workload = .check_detection, .iterations = if (debug) 500 else 500_000, .warmups = 5, .expected_ops = expected_b[3] },
            .{ .workload = .perft_startpos_d4, .iterations = if (debug) 1 else 30, .warmups = 1, .expected_ops = expected_b[4] },
            .{ .workload = .two_ply_simulation, .iterations = if (debug) 3 else 300, .warmups = 3, .expected_ops = expected_b[5] },
        },
    };
}

fn fixedSpecs(expected: [6]u64) [6]WorkSpec {
    return .{
        .{ .workload = .legal_moves, .iterations = 5_000, .warmups = 50, .expected_ops = expected[0] },
        .{ .workload = .legal_captures, .iterations = 10_000, .warmups = 100, .expected_ops = expected[1] },
        .{ .workload = .make_unmake, .iterations = 2_000, .warmups = 20, .expected_ops = expected[2] },
        .{ .workload = .threshold_see, .iterations = 20_000, .warmups = 200, .expected_ops = expected[3] },
        .{ .workload = .perft_startpos_d4, .iterations = 30, .warmups = 3, .expected_ops = expected[4] },
        .{ .workload = .two_ply_simulation, .iterations = 300, .warmups = 10, .expected_ops = expected[5] },
    };
}

const ProfileKind = enum { cross, legacy_a, legacy_b };

const Options = struct {
    profile: ProfileKind = .cross,
    preflight_only: bool = false,
    see_signature: bool = false,
};

const BoardSlot = struct {
    root: chess.position.PositionState,
    child: chess.position.PositionState,
    position: chess.position.Position,
};

const Suite = struct {
    slots: [5]BoardSlot,
    perft_states: [4]chess.position.PositionState,
    scratch: chess.position.MoveList,
    outer: chess.position.MoveList,
    inner: chess.position.MoveList,

    fn init(self: *Suite, fens: *const [5][]const u8) !void {
        self.scratch = chess.position.MoveList.init();
        self.outer = chess.position.MoveList.init();
        self.inner = chess.position.MoveList.init();
        for (fens, 0..) |fen_text, index| {
            self.slots[index].root = .{};
            self.slots[index].child = .{};
            self.slots[index].position = try chess.fen.parse(
                fen_text,
                &self.slots[index].root,
            );
            self.slots[index].position.rebind(&self.slots[index].root);
            if (!chess.state.isConsistent(&self.slots[index].position)) {
                return error.InconsistentPosition;
            }
        }
    }
};

const Result = struct {
    workload: Workload,
    estimate: f64,
    mad: f64,
    operations_per_iteration: u64,
    iterations: usize,
};

pub fn main(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const options = parseOptions(args) catch |err| {
        std.debug.print("board benchmark: {s}\n", .{@errorName(err)});
        printUsage();
        return 2;
    };
    const profile = selectProfile(options.profile);
    if (options.see_signature and options.profile != .cross) {
        std.debug.print("board benchmark: --see-signature requires cross-engine-board-v1\n", .{});
        return 2;
    }
    run(init.io, profile, options.preflight_only, options.see_signature) catch |err| {
        std.debug.print("board benchmark: FAIL ({s})\n", .{@errorName(err)});
        return 1;
    };
    return 0;
}

fn run(io: std.Io, profile: Profile, preflight_only: bool, see_signature: bool) !void {
    var suite: Suite = undefined;
    try suite.init(profile.fens);
    try preflight(&suite, profile);

    std.debug.print(
        "Manta board benchmark\nschema: {s}\nprofile: {s}\nbuild: {s}\ntarget: {s}-{s}\npositions: 5\n",
        .{ schema, profile.name, @tagName(builtin.mode), @tagName(builtin.cpu.arch), @tagName(builtin.os.tag) },
    );
    switch (profile.estimator) {
        .timed_median_mad => std.debug.print("samples: 11 x 150 ms (median +/- MAD)\n", .{}),
        .fixed_median_mad => std.debug.print("samples: 11 fixed-work samples (median +/- MAD)\n", .{}),
        .best_of_three => std.debug.print("samples: 3 fixed-work samples (best throughput)\n", .{}),
    }
    std.debug.print("preflight: PASS\n", .{});
    if (see_signature) try writeSeeSignature(&suite);
    if (preflight_only) return;

    var results: [6]Result = undefined;
    for (profile.specs, 0..) |spec, index| {
        results[index] = try measureDispatch(io, &suite, spec, profile.estimator);
    }
    std.debug.print(
        "{s: <22} {s: >15} {s: >15} {s: >10} {s: >12} {s: >10}\n",
        .{ "workload", "estimate ops/s", "MAD ops/s", "MAD %", "ops/iter", "total iters" },
    );
    for (results) |result| {
        const spread = if (result.estimate == 0) 0 else 100.0 * result.mad / result.estimate;
        std.debug.print(
            "{s: <22} {d: >15.0} {d: >15.0} {d: >9.2}% {d: >12} {d: >10} {s}\n",
            .{
                result.workload.label(),
                result.estimate,
                result.mad,
                spread,
                result.operations_per_iteration,
                result.iterations,
                result.workload.unit(),
            },
        );
    }
}

/// Emits the pruning-hot threshold-SEE decisions over the exact frozen capture
/// population. The comparison tool sorts by position/move, so generation order
/// remains a separately tested Manta contract rather than a cross-engine target.
fn writeSeeSignature(suite: *Suite) !void {
    var count: usize = 0;
    for (&suite.slots, 0..) |*slot, position_index| {
        chess.movegen.generate(.captures, &slot.position, &suite.scratch);
        for (suite.scratch.slice()) |chess_move| {
            const text = try chess.notation.format(chess_move);
            const decision = chess.see.atLeast(&slot.position, chess_move, 0, see_values);
            std.debug.print(
                "SEE-CONTRACT-V1 position={d} move={s} result={s}\n",
                .{ position_index, text.slice(), if (decision) "true" else "false" },
            );
            count += 1;
        }
    }
    if (count != expected_a[3]) return error.WorkMismatch;
    std.debug.print("SEE-CONTRACT-V1 count={d}\n", .{count});
}

fn preflight(suite: *Suite, profile: Profile) !void {
    var matches = true;
    for (profile.specs) |spec| {
        const actual = try execute(suite, spec.workload);
        if (actual != spec.expected_ops) {
            std.debug.print(
                "work mismatch for {s}: expected {d}, received {d}\n",
                .{ spec.workload.label(), spec.expected_ops, actual },
            );
            matches = false;
        }
        try expectRestored(suite);
    }
    if (!matches) return error.WorkMismatch;
}

/// Choose an inner batch size so the deadline clock is read about once per
/// millisecond. A monotonic clock read costs tens of nanoseconds, while the
/// ten-operation workloads complete an iteration in roughly a hundred, so
/// testing the deadline every iteration would leave a double-digit percentage
/// of clock overhead inside the timed region and report it as board
/// throughput.
fn calibrateBatch(
    comptime workload: Workload,
    io: std.Io,
    suite: *Suite,
    spec: WorkSpec,
) !u64 {
    const probes = 32;
    const target_ns = std.time.ns_per_ms;
    const max_batch = 1_000_000;

    const started = std.Io.Clock.awake.now(io).nanoseconds;
    for (0..probes) |_| {
        const operations = executeKnown(workload, suite);
        if (operations != spec.expected_ops) return error.WorkMismatch;
        std.mem.doNotOptimizeAway(operations);
    }
    const elapsed = std.Io.Clock.awake.now(io).nanoseconds - started;
    if (elapsed <= 0) return max_batch;
    const per_iteration = @divTrunc(elapsed, probes);
    if (per_iteration == 0) return max_batch;
    const batch = @divTrunc(@as(@TypeOf(elapsed), target_ns), per_iteration);
    return @intCast(std.math.clamp(batch, 1, max_batch));
}

fn measureDispatch(
    io: std.Io,
    suite: *Suite,
    spec: WorkSpec,
    estimator: Estimator,
) !Result {
    return switch (spec.workload) {
        inline else => |workload| measure(workload, io, suite, spec, estimator),
    };
}

fn measure(
    comptime workload: Workload,
    io: std.Io,
    suite: *Suite,
    spec: WorkSpec,
    estimator: Estimator,
) !Result {
    var batch: u64 = 1;
    if (estimator == .timed_median_mad) {
        const warmup_started = std.Io.Clock.awake.now(io).nanoseconds;
        while (std.Io.Clock.awake.now(io).nanoseconds - warmup_started < timed_sample_ns) {
            const operations = executeKnown(workload, suite);
            if (operations != spec.expected_ops) return error.WorkMismatch;
            std.mem.doNotOptimizeAway(operations);
        }
        batch = try calibrateBatch(workload, io, suite, spec);
    } else {
        for (0..spec.warmups) |_| {
            const operations = executeKnown(workload, suite);
            if (operations != spec.expected_ops) return error.WorkMismatch;
            std.mem.doNotOptimizeAway(operations);
        }
    }

    const count: usize = switch (estimator) {
        .timed_median_mad, .fixed_median_mad => sample_count,
        .best_of_three => 3,
    };
    var samples: [sample_count]f64 = @splat(0);
    var total_iterations: usize = 0;
    for (samples[0..count]) |*sample| {
        var total: u64 = 0;
        var iterations: usize = 0;
        const started = std.Io.Clock.awake.now(io).nanoseconds;
        if (estimator == .timed_median_mad) {
            while (std.Io.Clock.awake.now(io).nanoseconds - started < timed_sample_ns) {
                for (0..batch) |_| total += executeKnown(workload, suite);
                iterations += batch;
            }
        } else {
            for (0..spec.iterations) |_| {
                total += executeKnown(workload, suite);
            }
            iterations = spec.iterations;
        }
        const finished = std.Io.Clock.awake.now(io).nanoseconds;
        if (total != spec.expected_ops * iterations or finished <= started) {
            return error.InvalidMeasurement;
        }
        total_iterations += iterations;
        std.mem.doNotOptimizeAway(total);
        const seconds = @as(f64, @floatFromInt(finished - started)) / std.time.ns_per_s;
        sample.* = @as(f64, @floatFromInt(total)) / seconds;
    }

    var point = samples[0];
    var mad: f64 = 0;
    switch (estimator) {
        .timed_median_mad, .fixed_median_mad => {
            point = median(samples[0..count]);
            var deviations: [sample_count]f64 = undefined;
            for (samples[0..count], deviations[0..count]) |sample, *deviation| {
                deviation.* = @abs(sample - point);
            }
            mad = median(deviations[0..count]);
        },
        .best_of_three => for (samples[1..count]) |sample| {
            point = @max(point, sample);
        },
    }
    return .{
        .workload = spec.workload,
        .estimate = point,
        .mad = mad,
        .operations_per_iteration = spec.expected_ops,
        .iterations = total_iterations,
    };
}

fn median(values: []const f64) f64 {
    var copy: [sample_count]f64 = undefined;
    @memcpy(copy[0..values.len], values);
    std.mem.sort(f64, copy[0..values.len], {}, std.sort.asc(f64));
    return copy[values.len / 2];
}

fn execute(suite: *Suite, workload: Workload) !u64 {
    return switch (workload) {
        .legal_moves => legalMoves(suite),
        .legal_captures => legalCaptures(suite),
        .make_unmake => makeUnmake(suite),
        .threshold_see => thresholdSee(suite),
        .check_detection => checkDetection(suite),
        .perft_startpos_d4 => try perftStart(suite),
        .two_ply_simulation => twoPlySimulation(suite),
    };
}

/// The timed loop is specialized per workload so it measures the frozen board
/// operation, not a runtime benchmark dispatcher or an error-union branch.
fn executeKnown(comptime workload: Workload, suite: *Suite) u64 {
    return switch (workload) {
        .legal_moves => legalMoves(suite),
        .legal_captures => legalCaptures(suite),
        .make_unmake => makeUnmake(suite),
        .threshold_see => thresholdSee(suite),
        .check_detection => checkDetection(suite),
        .perft_startpos_d4 => perftStart(suite) catch unreachable,
        .two_ply_simulation => twoPlySimulation(suite),
    };
}

fn legalMoves(suite: *Suite) u64 {
    var total: u64 = 0;
    for (&suite.slots) |*slot| {
        chess.movegen.generate(.all, &slot.position, &suite.scratch);
        total += suite.scratch.count;
        std.mem.doNotOptimizeAway(&suite.scratch);
    }
    return total;
}

fn legalCaptures(suite: *Suite) u64 {
    var total: u64 = 0;
    for (&suite.slots) |*slot| {
        chess.movegen.generate(.captures, &slot.position, &suite.scratch);
        total += suite.scratch.count;
        std.mem.doNotOptimizeAway(&suite.scratch);
    }
    return total;
}

fn makeUnmake(suite: *Suite) u64 {
    var total: u64 = 0;
    for (&suite.slots) |*slot| {
        chess.movegen.generate(.all, &slot.position, &suite.scratch);
        for (suite.scratch.slice()) |chess_move| {
            chess.transition.makeMove(&slot.position, chess_move, &slot.child);
            std.mem.doNotOptimizeAway(slot.position.physical.occupied());
            chess.transition.unmakeMove(&slot.position, chess_move);
            total += 1;
        }
    }
    return total;
}

fn thresholdSee(suite: *Suite) u64 {
    var total: u64 = 0;
    for (&suite.slots) |*slot| {
        chess.movegen.generate(.captures, &slot.position, &suite.scratch);
        for (suite.scratch.slice()) |chess_move| {
            std.mem.doNotOptimizeAway(chess.see.atLeast(
                &slot.position,
                chess_move,
                0,
                see_values,
            ));
            total += 1;
        }
    }
    return total;
}

fn checkDetection(suite: *Suite) u64 {
    for (&suite.slots) |*slot| {
        std.mem.doNotOptimizeAway(slot.position.current.checkers != 0);
    }
    return suite.slots.len;
}

fn perftStart(suite: *Suite) !u64 {
    return chess.perft.count(&suite.slots[0].position, 4, &suite.perft_states);
}

fn twoPlySimulation(suite: *Suite) u64 {
    var total: u64 = 0;
    for (&suite.slots) |*slot| {
        chess.movegen.generate(.all, &slot.position, &suite.outer);
        for (suite.outer.slice()) |chess_move| {
            chess.transition.makeMove(&slot.position, chess_move, &slot.child);
            chess.movegen.generate(.all, &slot.position, &suite.inner);
            total += suite.inner.count;
            std.mem.doNotOptimizeAway(&suite.inner);
            chess.transition.unmakeMove(&slot.position, chess_move);
        }
    }
    return total;
}

fn expectRestored(suite: *const Suite) !void {
    for (&suite.slots) |*slot| {
        if (slot.position.current != &slot.root or
            !chess.state.isConsistent(&slot.position)) return error.StateNotRestored;
    }
}

fn parseOptions(args: []const []const u8) !Options {
    var result: Options = .{};
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--preflight-only")) {
            result.preflight_only = true;
        } else if (std.mem.eql(u8, args[index], "--see-signature")) {
            result.see_signature = true;
        } else if (std.mem.eql(u8, args[index], "--profile")) {
            index += 1;
            if (index == args.len) return error.MissingProfile;
            result.profile = if (std.mem.eql(u8, args[index], "cross-engine-board-v1"))
                .cross
            else if (std.mem.eql(u8, args[index], "legacy-board-a-v1"))
                .legacy_a
            else if (std.mem.eql(u8, args[index], "legacy-board-b-v1"))
                .legacy_b
            else
                return error.InvalidProfile;
        } else {
            return error.UnknownArgument;
        }
    }
    return result;
}

fn selectProfile(profile: ProfileKind) Profile {
    return switch (profile) {
        .cross => crossProfile(),
        .legacy_a => legacyAProfile(),
        .legacy_b => legacyBProfile(),
    };
}

fn printUsage() void {
    std.debug.print(
        "usage: zig build board-bench [-Doptimize=Debug|ReleaseFast] -- " ++
            "[--profile cross-engine-board-v1|legacy-board-a-v1|legacy-board-b-v1] " ++
            "[--preflight-only] [--see-signature]\n",
        .{},
    );
}

test "board profiles freeze exact work and restore every position" {
    for ([_]Profile{ crossProfile(), legacyAProfile(), legacyBProfile() }) |profile| {
        var suite: Suite = undefined;
        try suite.init(profile.fens);
        try preflight(&suite, profile);
    }
}

test "board benchmark options are explicit" {
    const defaults = try parseOptions(&.{"tool"});
    try std.testing.expectEqual(.cross, defaults.profile);
    const legacy = try parseOptions(&.{
        "tool",
        "--profile",
        "legacy-board-b-v1",
        "--preflight-only",
        "--see-signature",
    });
    try std.testing.expectEqual(.legacy_b, legacy.profile);
    try std.testing.expect(legacy.preflight_only);
    try std.testing.expect(legacy.see_signature);
    try std.testing.expectError(error.InvalidProfile, parseOptions(&.{
        "tool",
        "--profile",
        "unknown",
    }));
}
