//! Step-6.5.2 whole-tree attribution sweep over the frozen bench corpus.
//!
//! `search_observe.zig` answers whether the observer's accounting is coherent
//! on twelve fixed cases. This tool answers a different question: across the
//! forty-position search corpus and a range of depths, where does the tree
//! actually go, and how much of the answer is transposition pressure rather
//! than search policy. It therefore sweeps depth and `Hash` instead of freezing
//! them, reports one row per position so a single opening or ending cannot
//! decide the diagnosis, and writes machine-readable output for the report.
//!
//! Every position starts from a cleared table and cleared ordering state, so a
//! row never inherits the previous position's evidence. That is the in-process
//! equivalent of the fresh process per depth the cross-engine profile uses.
//! Nothing here decides playing strength: node totals, ratios and shares are
//! diagnostics that rank questions for later candidates.
const std = @import("std");
const builtin = @import("builtin");
const manta = @import("manta");
const search_build_options = @import("search_build_options");

const chess = manta.chess;
const search = manta.search;
const bench = manta.engine.bench;
const EvalBinding = manta.eval.contract.Binding(manta.eval.hce.Hce, manta.eval.trace.Disabled);

pub const schema = "manta-search-attribution-v1";

const charge_count = @typeInfo(search.diagnostics.WorkCharge).@"enum".fields.len;
const route_count = @typeInfo(search.types.EntryRoute).@"enum".fields.len;
const lookup_count = @typeInfo(search.diagnostics.TableLookup).@"enum".fields.len;
const store_outcome_count = @typeInfo(search.tt.StoreOutcome).@"enum".fields.len;

const Harness = struct {
    evaluator: manta.eval.hce.Hce = .{},
    evaluator_state: manta.eval.hce.Hce.State = .{},
    sink: manta.eval.trace.Disabled = .{},

    fn binding(self: *Harness) EvalBinding {
        return .{ .evaluator = &self.evaluator, .state = &self.evaluator_state, .sink = &self.sink };
    }
};

const Clock = struct {
    io: std.Io,

    fn nowNs(self: *const Clock) u64 {
        const value = std.Io.Clock.awake.now(self.io).nanoseconds;
        return if (value <= 0) 0 else @intCast(value);
    }
};

/// One position at one depth under one table size.
const Row = struct {
    position: usize,
    depth: u16,
    nodes: u64,
    main_nodes: u64,
    quiescence_nodes: u64,
    elapsed_ms: u64,
    generated_moves: u64,
    searched_moves: u64,
    searched_main_moves: u64,
    searched_quiescence_moves: u64,
    prunes_late_move: u64,
    prunes_quiet_futility: u64,
    prunes_see: u64,
    prunes_reverse_futility: u64,
    tt_move_available: u64,
    tt_move_best: u64,
    cutoffs: u64,
    first_move_cutoffs: u64,
    in_check_nodes: u64,
    check_chain_max: u16,
    extension_chain_max: u16,
    extended_nodes: u64,
    check_extensions: u64,
    singular_attempts: u64,
    singular_extensions: u64,
    lmr_probes: u64,
    lmr_researches: u64,
    null_attempts: u64,
    null_cutoffs: u64,
    probcut_nodes: u64,
    probcut_cutoffs: u64,
    aspiration_fail_lows: u64,
    aspiration_fail_highs: u64,
    charged: [charge_count]u64,
    under: [charge_count]u64,
    routes: [route_count]u64,
    lookups: [lookup_count]u64,
    stores: [store_outcome_count]u64,
};

const Options = struct {
    min_depth: u16 = 4,
    max_depth: u16 = 10,
    hash_mib: u64 = 64,
    position_limit: usize = bench.positions.len,
    json_path: ?[]const u8 = null,
};

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const options = parseOptions(args) catch |err| {
        std.debug.print("search attribution: {s}\n", .{@errorName(err)});
        printUsage();
        return 2;
    };

    var hash = manta.engine.runtime.HashResource.init(allocator, options.hash_mib) catch |err| {
        std.debug.print("search attribution: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer hash.deinit(allocator);

    var rows: std.ArrayList(Row) = .empty;
    defer rows.deinit(allocator);

    std.debug.print(
        "Manta search attribution\nschema: {s}\nbuild: {s}\npositions: {d}\ndepths: {d}..{d}\nhash: {d} MiB\nreset: table and ordering before every position\n\n",
        .{
            schema,
            @tagName(builtin.mode),
            options.position_limit,
            options.min_depth,
            options.max_depth,
            options.hash_mib,
        },
    );

    const clock = Clock{ .io = init.io };
    var thread = search.types.ThreadState.init();
    var heuristics: search.ordering.State = .{};
    var previous_nodes: u64 = 0;
    var depth = options.min_depth;
    while (depth <= options.max_depth) : (depth += 1) {
        const first_row = rows.items.len;
        for (bench.positions[0..options.position_limit], 0..) |fen_text, index| {
            const row = measure(&clock, fen_text, index, depth, &thread, &hash.table, &heuristics) catch |err| {
                std.debug.print("position {d} depth {d}: FAIL {s}\n", .{ index, depth, @errorName(err) });
                return 1;
            };
            try rows.append(allocator, row);
        }
        printDepthSummary(rows.items[first_row..], depth, &previous_nodes);
    }

    printCorpusSummary(rows.items, options);
    if (options.json_path) |path| {
        const data = try renderJson(allocator, rows.items, options);
        defer allocator.free(data);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = data });
        std.debug.print("\nreport -> {s}\n", .{path});
    }
    return 0;
}

fn measure(
    clock: anytype,
    fen_text: []const u8,
    index: usize,
    depth: u16,
    thread: *search.types.ThreadState,
    table: *search.tt.Table,
    heuristics: *search.ordering.State,
) !Row {
    table.clear();
    heuristics.clear();
    var root: chess.position.PositionState = .{};
    var position = try chess.fen.parse(fen_text, &root);
    var harness: Harness = .{};
    var control: search.types.NeverStop = .{};
    var counters: search.diagnostics.Counters = .{};
    const started_ns = clock.nowNs();
    const result = search.baseline.runWithFeatures(
        .{
            .correction_history = search_build_options.correction_history,
            .aspiration = search_build_options.stability_aspiration,
            .live_history_staging = search_build_options.live_history_staging,
            .nonroot_check_extension = search_build_options.nonroot_check_extension,
        },
        &position,
        harness.binding(),
        .{ .depth = depth },
        &control,
        thread,
        table,
        heuristics,
        &counters,
    );
    const elapsed_ns = clock.nowNs() -| started_ns;

    // The sweep is only worth reading if the search actually finished the
    // requested depth from a restored root, and if the charge partition still
    // accounts for every visited node.
    if (!chess.state.isConsistent(&position)) return error.PositionNotRestored;
    const completed = result.completed orelse return error.MissingCompletedIteration;
    if (completed.depth != depth) return error.IncompleteDepth;
    if (result.best_move == null) return error.MissingBestMove;
    if (counters.context_nodes != result.nodes) return error.NodeAccounting;
    if (sum(&counters.nodes_by_charge) != counters.context_nodes) return error.ChargeAccounting;

    const check_index = @intFromEnum(search.diagnostics.ExtensionCause.check);
    const singular_index = @intFromEnum(search.diagnostics.ExtensionCause.singular);
    const null_index = @intFromEnum(search.diagnostics.PruneCause.null_move);
    const probcut_index = @intFromEnum(search.diagnostics.PruneCause.probcut);
    const late_move_index = @intFromEnum(search.diagnostics.PruneCause.late_move);
    const futility_index = @intFromEnum(search.diagnostics.PruneCause.futility);
    const see_index = @intFromEnum(search.diagnostics.PruneCause.see);
    const reverse_index = @intFromEnum(search.diagnostics.PruneCause.reverse_futility);
    const first_index = @intFromEnum(search.diagnostics.FailHighBucket.first);
    return .{
        .position = index,
        .depth = depth,
        .nodes = result.nodes,
        .main_nodes = counters.main_nodes,
        .quiescence_nodes = counters.quiescence_nodes,
        .elapsed_ms = elapsed_ns / std.time.ns_per_ms,
        .generated_moves = counters.generated_moves,
        .searched_moves = counters.searched_main_moves + counters.searched_quiescence_moves,
        .searched_main_moves = counters.searched_main_moves,
        .searched_quiescence_moves = counters.searched_quiescence_moves,
        .prunes_late_move = counters.prunes_by_cause[late_move_index],
        .prunes_quiet_futility = counters.prunes_by_cause[futility_index],
        .prunes_see = counters.prunes_by_cause[see_index],
        .prunes_reverse_futility = counters.prunes_by_cause[reverse_index],
        .tt_move_available = counters.tt_move_available,
        .tt_move_best = counters.tt_move_best,
        .cutoffs = counters.main_cutoffs + counters.quiescence_cutoffs,
        .first_move_cutoffs = counters.fail_high_by_index[first_index],
        .in_check_nodes = counters.context_in_check,
        .check_chain_max = counters.check_chain_max,
        .extension_chain_max = counters.extension_chain_max,
        .extended_nodes = counters.extended_depth_intents,
        .check_extensions = counters.extensions_by_cause[check_index],
        .singular_attempts = counters.singular_attempts,
        .singular_extensions = counters.extensions_by_cause[singular_index],
        .lmr_probes = counters.lmr_probes,
        .lmr_researches = counters.lmr_researches,
        .null_attempts = counters.null_move_attempts,
        .null_cutoffs = counters.prunes_by_cause[null_index],
        .probcut_nodes = counters.probcut_nodes,
        .probcut_cutoffs = counters.prunes_by_cause[probcut_index],
        .aspiration_fail_lows = counters.aspiration_fail_lows,
        .aspiration_fail_highs = counters.aspiration_fail_highs,
        .charged = counters.nodes_by_charge,
        .under = counters.nodes_under_charge,
        .routes = counters.context_by_route,
        .lookups = counters.tt_lookups_by_outcome,
        .stores = counters.tt_stores_by_outcome,
    };
}

fn printDepthSummary(rows: []const Row, depth: u16, previous_nodes: *u64) void {
    var nodes: u64 = 0;
    var quiescence: u64 = 0;
    var elapsed_ms: u64 = 0;
    var charged: [charge_count]u64 = @splat(0);
    var under: [charge_count]u64 = @splat(0);
    for (rows) |row| {
        nodes += row.nodes;
        quiescence += row.quiescence_nodes;
        elapsed_ms += row.elapsed_ms;
        for (row.charged, 0..) |value, index| charged[index] += value;
        for (row.under, 0..) |value, index| under[index] += value;
    }
    std.debug.print("depth {d:>2}  nodes {d:>12}", .{ depth, nodes });
    if (previous_nodes.* != 0) {
        const ratio_milli = nodes * 1000 / previous_nodes.*;
        std.debug.print("  ratio {d}.{d:0>3}", .{ ratio_milli / 1000, ratio_milli % 1000 });
    } else {
        std.debug.print("  ratio     -", .{});
    }
    std.debug.print("  qsearch {d:>5}%  time {d:>7} ms\n", .{ percent(quiescence, nodes), elapsed_ms });
    printShares("  charged ", charged, nodes);
    printShares("  under   ", under, nodes);
    previous_nodes.* = nodes;
}

fn printShares(label: []const u8, values: [charge_count]u64, total: u64) void {
    std.debug.print("{s}", .{label});
    inline for (@typeInfo(search.diagnostics.WorkCharge).@"enum".fields, 0..) |field, index|
        std.debug.print(" {s}={d}%", .{ field.name, percent(values[index], total) });
    std.debug.print("\n", .{});
}

fn printCorpusSummary(rows: []const Row, options: Options) void {
    var lookups: [lookup_count]u64 = @splat(0);
    var stores: [store_outcome_count]u64 = @splat(0);
    var generated: u64 = 0;
    var searched: u64 = 0;
    var cutoffs: u64 = 0;
    var first_cutoffs: u64 = 0;
    var in_check: u64 = 0;
    var extended: u64 = 0;
    var singular_attempts: u64 = 0;
    var singular_extensions: u64 = 0;
    var lmr_probes: u64 = 0;
    var lmr_researches: u64 = 0;
    for (rows) |row| {
        for (row.lookups, 0..) |value, index| lookups[index] += value;
        for (row.stores, 0..) |value, index| stores[index] += value;
        generated += row.generated_moves;
        searched += row.searched_moves;
        cutoffs += row.cutoffs;
        first_cutoffs += row.first_move_cutoffs;
        in_check += row.in_check_nodes;
        extended += row.extended_nodes;
        singular_attempts += row.singular_attempts;
        singular_extensions += row.singular_extensions;
        lmr_probes += row.lmr_probes;
        lmr_researches += row.lmr_researches;
    }
    std.debug.print("\ncorpus totals over depths {d}..{d} at {d} MiB\n", .{
        options.min_depth,
        options.max_depth,
        options.hash_mib,
    });
    std.debug.print(
        "  moves generated={d} searched={d} ({d}% of generated) cutoffs={d} first_move={d}%\n",
        .{ generated, searched, percent(searched, generated), cutoffs, percent(first_cutoffs, cutoffs) },
    );
    std.debug.print(
        "  forcing in_check_nodes={d} extended_nodes={d} singular={d}/{d}\n",
        .{ in_check, extended, singular_extensions, singular_attempts },
    );
    std.debug.print(
        "  lmr probes={d} researches={d} ({d}%)\n",
        .{ lmr_probes, lmr_researches, percent(lmr_researches, lmr_probes) },
    );
    std.debug.print("  tt_lookups", .{});
    inline for (@typeInfo(search.diagnostics.TableLookup).@"enum".fields, 0..) |field, index|
        std.debug.print(" {s}={d}", .{ field.name, lookups[index] });
    std.debug.print("\n  tt_stores", .{});
    inline for (@typeInfo(search.tt.StoreOutcome).@"enum".fields, 0..) |field, index|
        std.debug.print(" {s}={d}", .{ field.name, stores[index] });
    std.debug.print("\n", .{});
}

fn renderJson(allocator: std.mem.Allocator, rows: []const Row, options: Options) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var buffer: [1024]u8 = undefined;
    try output.appendSlice(allocator, try std.fmt.bufPrint(
        &buffer,
        "{{\n  \"schema\": \"{s}\",\n  \"build\": \"{s}\",\n  \"hash_mib\": {d},\n  \"min_depth\": {d},\n  \"max_depth\": {d},\n  \"positions\": {d},\n  \"rows\": [\n",
        .{
            schema,
            @tagName(builtin.mode),
            options.hash_mib,
            options.min_depth,
            options.max_depth,
            options.position_limit,
        },
    ));
    for (rows, 0..) |row, index| {
        try output.appendSlice(allocator, try std.fmt.bufPrint(
            &buffer,
            "    {{\"position\": {d}, \"depth\": {d}, \"nodes\": {d}, \"main\": {d}, \"quiescence\": {d}, \"ms\": {d}, \"generated\": {d}, \"searched\": {d}, \"searched_main\": {d}, \"searched_quiescence\": {d}, \"tt_move_available\": {d}, \"tt_move_best\": {d}, \"cutoffs\": {d}, \"first_move_cutoffs\": {d}, \"in_check\": {d}, \"check_chain_max\": {d}, \"extension_chain_max\": {d}, \"extended\": {d}, \"check_extensions\": {d}, \"singular_attempts\": {d}, \"singular_extensions\": {d}, \"lmr_probes\": {d}, \"lmr_researches\": {d}, \"null_attempts\": {d}, \"null_cutoffs\": {d}, \"probcut_nodes\": {d}, \"probcut_cutoffs\": {d}, \"aspiration_fail_lows\": {d}, \"aspiration_fail_highs\": {d}",
            .{
                row.position,                  row.depth,                 row.nodes,
                row.main_nodes,                row.quiescence_nodes,      row.elapsed_ms,
                row.generated_moves,           row.searched_moves,        row.searched_main_moves,
                row.searched_quiescence_moves, row.tt_move_available,     row.tt_move_best,
                row.cutoffs,                   row.first_move_cutoffs,    row.in_check_nodes,
                row.check_chain_max,           row.extension_chain_max,   row.extended_nodes,
                row.check_extensions,          row.singular_attempts,     row.singular_extensions,
                row.lmr_probes,                row.lmr_researches,        row.null_attempts,
                row.null_cutoffs,              row.probcut_nodes,         row.probcut_cutoffs,
                row.aspiration_fail_lows,      row.aspiration_fail_highs,
            },
        ));
        try output.appendSlice(allocator, try std.fmt.bufPrint(
            &buffer,
            ", \"prunes_late_move\": {d}, \"prunes_quiet_futility\": {d}, \"prunes_see\": {d}, \"prunes_reverse_futility\": {d}",
            .{
                row.prunes_late_move,
                row.prunes_quiet_futility,
                row.prunes_see,
                row.prunes_reverse_futility,
            },
        ));
        try appendEnumObject(allocator, &output, search.diagnostics.WorkCharge, "charged", row.charged);
        try appendEnumObject(allocator, &output, search.diagnostics.WorkCharge, "under", row.under);
        try appendEnumObject(allocator, &output, search.types.EntryRoute, "routes", row.routes);
        try appendEnumObject(allocator, &output, search.diagnostics.TableLookup, "tt_lookups", row.lookups);
        try appendEnumObject(allocator, &output, search.tt.StoreOutcome, "tt_stores", row.stores);
        try output.appendSlice(allocator, if (index + 1 == rows.len) "}\n" else "},\n");
    }
    try output.appendSlice(allocator, "  ]\n}\n");
    return output.toOwnedSlice(allocator);
}

fn appendEnumObject(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    comptime Enum: type,
    name: []const u8,
    values: anytype,
) !void {
    var buffer: [256]u8 = undefined;
    try output.appendSlice(allocator, try std.fmt.bufPrint(&buffer, ", \"{s}\": {{", .{name}));
    inline for (@typeInfo(Enum).@"enum".fields, 0..) |field, index| {
        const separator = if (index == 0) "" else ", ";
        try output.appendSlice(allocator, try std.fmt.bufPrint(
            &buffer,
            "{s}\"{s}\": {d}",
            .{ separator, field.name, values[index] },
        ));
    }
    try output.appendSlice(allocator, "}");
}

fn percent(part: u64, whole: u64) u64 {
    if (whole == 0) return 0;
    return part * 100 / whole;
}

fn sum(values: []const u64) u64 {
    var total: u64 = 0;
    for (values) |value| total += value;
    return total;
}

fn parseOptions(args: []const []const u8) !Options {
    var result: Options = .{};
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const name = args[index];
        if (std.mem.eql(u8, name, "--min-depth")) {
            index += 1;
            if (index == args.len) return error.MissingValue;
            result.min_depth = try std.fmt.parseInt(u16, args[index], 10);
        } else if (std.mem.eql(u8, name, "--max-depth")) {
            index += 1;
            if (index == args.len) return error.MissingValue;
            result.max_depth = try std.fmt.parseInt(u16, args[index], 10);
        } else if (std.mem.eql(u8, name, "--hash")) {
            index += 1;
            if (index == args.len) return error.MissingValue;
            result.hash_mib = try std.fmt.parseInt(u64, args[index], 10);
        } else if (std.mem.eql(u8, name, "--positions")) {
            index += 1;
            if (index == args.len) return error.MissingValue;
            result.position_limit = try std.fmt.parseInt(usize, args[index], 10);
        } else if (std.mem.eql(u8, name, "--json")) {
            index += 1;
            if (index == args.len) return error.MissingValue;
            result.json_path = args[index];
        } else {
            return error.UnknownArgument;
        }
    }
    if (result.min_depth == 0 or result.max_depth < result.min_depth) return error.InvalidDepthRange;
    if (result.max_depth > chess.types.max_ply - 1) return error.InvalidDepthRange;
    if (result.position_limit == 0 or result.position_limit > bench.positions.len)
        return error.InvalidPositionLimit;
    if (result.hash_mib == 0) return error.InvalidHash;
    return result;
}

fn printUsage() void {
    std.debug.print(
        "usage: search-attribution [--min-depth N] [--max-depth N] [--hash MiB] [--positions N] [--json PATH]\n",
        .{},
    );
}

const TestClock = struct {
    ticks: u64 = 0,

    fn nowNs(self: *TestClock) u64 {
        self.ticks += std.time.ns_per_ms;
        return self.ticks;
    }
};

test "option parsing rejects ranges the corpus cannot answer" {
    // A silently clamped range would produce a report that does not describe
    // the sweep its header claims, which is worse than refusing to run.
    try std.testing.expectError(error.InvalidDepthRange, parseOptions(&.{ "tool", "--min-depth", "8", "--max-depth", "4" }));
    try std.testing.expectError(error.InvalidPositionLimit, parseOptions(&.{ "tool", "--positions", "0" }));
    try std.testing.expectError(error.InvalidHash, parseOptions(&.{ "tool", "--hash", "0" }));
    try std.testing.expectError(error.UnknownArgument, parseOptions(&.{ "tool", "--depth", "9" }));
    const parsed = try parseOptions(&.{ "tool", "--min-depth", "5", "--max-depth", "7", "--hash", "256" });
    try std.testing.expectEqual(@as(u16, 5), parsed.min_depth);
    try std.testing.expectEqual(@as(u16, 7), parsed.max_depth);
    try std.testing.expectEqual(@as(u64, 256), parsed.hash_mib);
    try std.testing.expectEqual(bench.positions.len, parsed.position_limit);
}

test "a shallow sweep keeps its charge partition exact on every position" {
    // The corpus rows are only comparable if each one is an exact partition of
    // its own tree. Depth two is cheap enough for the ordinary test gate and
    // still exercises quiescence, extensions and the transposition table.
    if (builtin.mode == .Debug) return;
    var hash = try manta.engine.runtime.HashResource.init(std.testing.allocator, 1);
    defer hash.deinit(std.testing.allocator);
    var thread = search.types.ThreadState.init();
    var heuristics: search.ordering.State = .{};
    // Wall time is descriptive here, so a synthetic monotonic clock keeps the
    // property under test independent of the host and of any real timer.
    var clock = TestClock{};
    for (bench.positions[0..8], 0..) |fen_text, index| {
        const row = try measure(&clock, fen_text, index, 2, &thread, &hash.table, &heuristics);
        try std.testing.expectEqual(row.nodes, sum(&row.charged));
        try std.testing.expect(row.main_nodes + row.quiescence_nodes == row.nodes);
        for (row.charged, row.under) |charged, under| try std.testing.expect(under >= charged);
    }
}
