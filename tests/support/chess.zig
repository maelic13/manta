//! Deterministic chess fixtures and randomness shared by property campaigns.
const std = @import("std");
const manta = @import("manta");

pub const roots = [_][]const u8{
    manta.chess.fen.start_position,
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
    "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
    "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
    "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
    "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
    "1r5k/P7/8/8/8/8/8/7K w - - 0 1",
};

pub const Rng = struct {
    state: u64,

    pub fn init(seed: u64) Rng {
        std.debug.assert(seed != 0);
        return .{ .state = seed };
    }

    pub fn next(self: *Rng) u64 {
        var value = self.state;
        value ^= value >> 12;
        value ^= value << 25;
        value ^= value >> 27;
        self.state = value;
        return value *% 0x2545_F491_4F6C_DD1D;
    }

    pub fn below(self: *Rng, limit: usize) usize {
        std.debug.assert(limit != 0);
        return @intCast(self.next() % limit);
    }
};
