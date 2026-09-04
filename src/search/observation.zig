//! Versioned fixed-position population for search-mechanism observation.
const std = @import("std");
const chess = @import("../chess/root.zig");

pub const version = "manta-search-observation-v22";
pub const hash_mib: u64 = 16;

pub const Cohort = enum {
    opening,
    quiet_middlegame,
    tactical,
    check_evasion,
    zugzwang,
    endgame,
};

pub const Case = struct {
    id: []const u8,
    cohort: Cohort,
    fen: []const u8,
    depth: u16,
};

/// Each case is searched from cleared TT and ordering state. The population is
/// descriptive: exact counters may change only with a version bump or a
/// causally recorded search change, and never constitute strength evidence.
pub const cases = [_]Case{
    .{
        .id = "opening-start",
        .cohort = .opening,
        .fen = chess.fen.start_position,
        // Bounded depth nine makes every ProbCut stage observable while
        // retaining one fixed legal opening root and deterministic state.
        .depth = 10,
    },
    .{
        .id = "opening-castling-pressure",
        .cohort = .opening,
        .fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        .depth = 4,
    },
    .{
        .id = "quiet-piece-tension",
        .cohort = .quiet_middlegame,
        .fen = "r2qr1k1/p4ppp/1pn1bn2/2b1p3/4P3/1BN1BN2/PPP2PPP/R2QR1K1 b - - 6 10",
        .depth = 4,
    },
    .{
        .id = "quiet-closed-center",
        .cohort = .quiet_middlegame,
        .fen = "3r1rk1/1ppb1pb1/p2npqnp/P5p1/3P4/1BN1BN1P/1PP2PP1/3RQR1K w - - 3 10",
        .depth = 4,
    },
    .{
        .id = "tactical-wac001",
        .cohort = .tactical,
        .fen = "2rr3k/pp3pp1/1nnqbN1p/3pN3/2pP4/2P3Q1/PPB4P/R4RK1 w - - 0 1",
        .depth = 4,
    },
    .{
        .id = "tactical-hanging-queen",
        .cohort = .tactical,
        .fen = "4k3/8/8/8/8/8/3q4/3RK3 w - - 0 1",
        .depth = 4,
    },
    .{
        .id = "evasion-rook-file-check",
        .cohort = .check_evasion,
        .fen = "4k3/8/8/8/8/8/4R3/4K3 b - - 0 1",
        .depth = 4,
    },
    .{
        .id = "evasion-queen-file-check",
        .cohort = .check_evasion,
        .fen = "4k3/8/8/8/8/4Q3/8/4K3 b - - 0 1",
        .depth = 4,
    },
    .{
        .id = "zugzwang-opposition",
        .cohort = .zugzwang,
        .fen = "8/pp2k3/8/2p5/2P5/1P2K3/P7/8 w - - 0 1",
        .depth = 4,
    },
    .{
        .id = "zugzwang-locked-wings",
        .cohort = .zugzwang,
        .fen = "8/8/p1p5/1p5p/1P5P/P1P5/8/K1k5 w - - 0 1",
        // This low-branching pawn ending reaches non-root depth six without
        // turning the suite into a large timing job. It therefore exercises
        // TT-dependent singular exclusion under zugzwang-sensitive material,
        // where null move remains unavailable. Focused no-TT tests own IIR.
        .depth = 7,
    },
    .{
        .id = "endgame-bishop-knight-mate",
        .cohort = .endgame,
        .fen = "k7/8/8/8/8/2B1N3/8/4K3 w - - 0 1",
        .depth = 4,
    },
    .{
        .id = "endgame-rook-pawns",
        .cohort = .endgame,
        .fen = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
        .depth = 4,
    },
};

test "observation population is legal balanced and nonterminal" {
    // QUAL-013/014: legal parsing and generated moves independently protect
    // the fixed workload; cohort balance prevents one search shape from
    // silently replacing another when the suite is revised.
    const cohort_count = @typeInfo(Cohort).@"enum".fields.len;
    var counts: [cohort_count]u8 = @splat(0);
    for (cases) |case| {
        var root: chess.position.PositionState = .{};
        const value = try chess.fen.parse(case.fen, &root);
        try std.testing.expect(chess.state.isConsistent(&value));
        var moves = chess.position.MoveList.init();
        chess.movegen.generate(.all, &value, &moves);
        try std.testing.expect(moves.count != 0);
        if (case.cohort == .check_evasion)
            try std.testing.expect(value.current.checkers != 0);
        counts[@intFromEnum(case.cohort)] += 1;
    }
    for (counts) |count| try std.testing.expectEqual(@as(u8, 2), count);
}
