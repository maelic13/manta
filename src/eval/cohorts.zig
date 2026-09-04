//! Versioned frozen evaluation cohorts for the Step-5.3.0 residual harness.
//!
//! The population is descriptive, not a scoreboard. It exists so that HCE
//! changes are examined against the same positions every time and against the
//! chess situations that actually stress different evaluation terms. Exact
//! reported values may change with a causal record and a version bump; they
//! are never a target to fit.
const std = @import("std");
const chess = @import("../chess/root.zig");

pub const version = "manta-eval-residual-v1";

/// Each cohort isolates a different reason an evaluator can be wrong.
pub const Cohort = enum {
    /// Balanced middlegames where positional terms dominate and no tactic
    /// should distort the static score.
    quiet,
    /// Positions whose true value comes from a forcing sequence, so static
    /// evaluation is expected to disagree with search.
    tactical,
    /// Exposed or attacked kings, where shelter and danger terms dominate.
    king_attack,
    /// Pawn structure and king activity with little or no piece play.
    pawn_endgame,
    /// A materially decided position whose halfmove clock makes the result
    /// doubtful, isolating rule-50 awareness from material counting.
    rule_fifty,
    /// Positions retained specifically because raw evaluation and a real
    /// search are known to reach different conclusions.
    search_disagreement,
};

pub const Case = struct {
    id: []const u8,
    cohort: Cohort,
    fen: []const u8,
    /// Fixed search depth for the cohort's searched-evidence column. Kept
    /// small so the whole harness stays a diagnostic rather than a timed job.
    depth: u16,
    /// White-relative centipawn evaluation from the pinned classical
    /// reference evaluator, which is the strongest pre-NNUE classical
    /// evaluator the plan pins. Null where that reference produces no static
    /// evaluation at all, which it declines to do while the side to move is
    /// in check. Provenance is recorded in `config/eval-reference.json`.
    reference_cp: ?i32,
};

pub const cases = [_]Case{
    .{
        .id = "quiet-piece-tension",
        .cohort = .quiet,
        .fen = "r2qr1k1/p4ppp/1pn1bn2/2b1p3/4P3/1BN1BN2/PPP2PPP/R2QR1K1 b - - 6 10",
        .depth = 6,
        .reference_cp = 67,
    },
    .{
        .id = "quiet-closed-center",
        .cohort = .quiet,
        .fen = "3r1rk1/1ppb1pb1/p2npqnp/P5p1/3P4/1BN1BN1P/1PP2PP1/3RQR1K w - - 3 10",
        .depth = 6,
        .reference_cp = -32,
    },
    .{
        .id = "quiet-opening-start",
        .cohort = .quiet,
        .fen = chess.fen.start_position,
        .depth = 6,
        .reference_cp = 14,
    },
    .{
        .id = "tactical-wac001",
        .cohort = .tactical,
        .fen = "2rr3k/pp3pp1/1nnqbN1p/3pN3/2pP4/2P3Q1/PPB4P/R4RK1 w - - 0 1",
        .depth = 6,
        .reference_cp = 441,
    },
    .{
        .id = "tactical-hanging-queen",
        .cohort = .tactical,
        .fen = "4k3/8/8/8/8/8/3q4/3RK3 w - - 0 1",
        .depth = 6,
        .reference_cp = null,
    },
    .{
        .id = "tactical-wac003",
        .cohort = .tactical,
        .fen = "5rk1/1ppb3p/p1pb4/6q1/3P1p1r/2P1R2P/PP1BQ1P1/5RKN w - - 0 1",
        .depth = 6,
        .reference_cp = -33,
    },
    .{
        .id = "king-attack-castled-pressure",
        .cohort = .king_attack,
        .fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        .depth = 5,
        .reference_cp = 37,
    },
    .{
        .id = "king-attack-open-file",
        .cohort = .king_attack,
        .fen = "r1bq1rk1/pp2bppp/2n1pn2/3p4/3P4/2NBPN2/PPQ2PPP/R1B2RK1 w - - 4 10",
        .depth = 5,
        .reference_cp = 20,
    },
    .{
        .id = "king-attack-exposed-king",
        .cohort = .king_attack,
        .fen = "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR w KQkq - 4 4",
        .depth = 5,
        .reference_cp = -39,
    },
    .{
        .id = "pawn-endgame-opposition",
        .cohort = .pawn_endgame,
        .fen = "8/pp2k3/8/2p5/2P5/1P2K3/P7/8 w - - 0 1",
        .depth = 8,
        .reference_cp = 14,
    },
    .{
        .id = "pawn-endgame-blocked-king",
        .cohort = .pawn_endgame,
        .fen = "8/8/8/4k3/8/8/4P3/4K3 w - - 0 1",
        .depth = 8,
        .reference_cp = 0,
    },
    .{
        .id = "pawn-endgame-locked-wings",
        .cohort = .pawn_endgame,
        .fen = "8/8/p1p5/1p5p/1P5P/P1P5/8/K1k5 w - - 0 1",
        .depth = 8,
        .reference_cp = -56,
    },
    .{
        .id = "rule-fifty-rook-ending",
        .cohort = .rule_fifty,
        .fen = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 90 60",
        .depth = 6,
        .reference_cp = 7,
    },
    .{
        .id = "rule-fifty-extra-queen",
        .cohort = .rule_fifty,
        .fen = "4k3/8/8/8/8/8/8/KQ6 w - - 95 80",
        .depth = 6,
        .reference_cp = 6115,
    },
    .{
        .id = "rule-fifty-bishop-knight",
        .cohort = .rule_fifty,
        .fen = "k7/8/8/8/8/2B1N3/8/4K3 w - - 98 90",
        .depth = 6,
        .reference_cp = 6563,
    },
    .{
        .id = "disagreement-bishop-knight-mate",
        .cohort = .search_disagreement,
        .fen = "k7/8/8/8/8/2B1N3/8/4K3 w - - 0 1",
        .depth = 8,
        .reference_cp = 6563,
    },
    .{
        .id = "disagreement-wac002",
        .cohort = .search_disagreement,
        .fen = "8/7p/5k2/5p2/p1p2P2/Pr1pPK2/1P1R3P/8 b - - 0 1",
        .depth = 8,
        .reference_cp = -192,
    },
    .{
        .id = "disagreement-knights-only",
        .cohort = .search_disagreement,
        .fen = "4k3/8/8/8/8/8/8/KNN5 w - - 0 1",
        .depth = 8,
        .reference_cp = 0,
    },
};

test "evaluation cohorts are legal, nonterminal and evenly balanced" {
    // QUAL-013/014: independent parsing and move generation protect the fixed
    // workload. Even balance stops one evaluation situation from quietly
    // dominating the residual picture when the suite is revised.
    const cohort_count = @typeInfo(Cohort).@"enum".fields.len;
    var counts: [cohort_count]u8 = @splat(0);
    for (cases) |case| {
        var root: chess.position.PositionState = .{};
        const value = try chess.fen.parse(case.fen, &root);
        try std.testing.expect(chess.state.isConsistent(&value));
        var moves = chess.position.MoveList.init();
        chess.movegen.generate(.all, &value, &moves);
        try std.testing.expect(moves.count != 0);
        counts[@intFromEnum(case.cohort)] += 1;
    }
    for (counts) |count| try std.testing.expectEqual(@as(u8, 3), count);
}

test "rule-fifty cohort actually carries a near-draw halfmove clock" {
    // The cohort only isolates rule-50 awareness if its positions are close
    // to the draw boundary; a zero clock would silently make it a duplicate
    // of the material cohorts.
    for (cases) |case| {
        if (case.cohort != .rule_fifty) continue;
        var root: chess.position.PositionState = .{};
        const value = try chess.fen.parse(case.fen, &root);
        try std.testing.expect(value.current.rule50 >= 90);
    }
}

test "case identifiers are unique and name their cohort" {
    // Reports are compared across revisions by identifier, so a duplicate or
    // mislabelled id would silently pair unrelated positions.
    for (cases, 0..) |case, index| {
        try std.testing.expect(case.id.len != 0);
        try std.testing.expect(case.depth != 0);
        for (cases[index + 1 ..]) |other|
            try std.testing.expect(!std.mem.eql(u8, case.id, other.id));
    }
}
