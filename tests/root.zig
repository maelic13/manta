const std = @import("std");
const bench_qualification = @import("bench_qualification.zig");
const chess_differential = @import("chess_differential.zig");
const eval_invariants = @import("eval_invariants.zig");
const eval_reference = @import("eval_reference.zig");
const search_baseline = @import("search_baseline.zig");
const search_qualification = @import("search_qualification.zig");
const search_substrate = @import("search_substrate.zig");
const state_invariants = @import("state_invariants.zig");
const tablebase_probe = @import("tablebase_probe.zig");
const manta = @import("manta");
const seeds = @import("support/seeds.zig");

test "the library facade is independently importable" {
    std.testing.refAllDecls(manta);
    _ = manta.chess;
    _ = bench_qualification;
    _ = chess_differential;
    _ = eval_invariants;
    _ = eval_reference;
    _ = search_baseline;
    _ = search_qualification;
    _ = search_substrate;
    _ = state_invariants;
    _ = tablebase_probe;
    std.testing.refAllDecls(seeds);
}
