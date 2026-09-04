//! Deterministic compile-time Zobrist identity data.
const std = @import("std");
const types = @import("types.zig");

pub const seed: u64 = 0x4d61_6e74_612d_7a62;

pub const Tables = struct {
    piece_square: [15][64]types.Key,
    castling: [16]types.Key,
    en_passant_file: [8]types.Key,
    side: types.Key,
};

pub const tables = generate(seed);

fn generate(initial_seed: u64) Tables {
    @setEvalBranchQuota(20_000);
    var generator = SplitMix64{ .state = initial_seed };
    var result = Tables{
        .piece_square = @splat(@splat(0)),
        .castling = @splat(0),
        .en_passant_file = @splat(0),
        .side = 0,
    };

    for (0..15) |piece_index| {
        const piece: types.Piece = @enumFromInt(piece_index);
        if (piece == .none or !piece.isValid()) continue;
        for (0..64) |square_index| {
            result.piece_square[piece_index][square_index] = generator.next();
        }
    }
    for (&result.castling) |*key| key.* = generator.next();
    for (&result.en_passant_file) |*key| key.* = generator.next();
    result.side = generator.next();
    return result;
}

const SplitMix64 = struct {
    state: u64,

    fn next(self: *SplitMix64) u64 {
        self.state +%= 0x9e37_79b9_7f4a_7c15;
        var value = self.state;
        value = (value ^ (value >> 30)) *% 0xbf58_476d_1ce4_e5b9;
        value = (value ^ (value >> 27)) *% 0x94d0_49bb_1331_11eb;
        return value ^ (value >> 31);
    }
};

test "Zobrist data covers exactly the legal piece encodings" {
    // A legal piece/square fact must affect identity; gaps in the compact piece
    // encoding must never become observable chess state.
    var seen: [800]types.Key = undefined;
    var seen_count: usize = 0;

    for (0..15) |piece_index| {
        const piece: types.Piece = @enumFromInt(piece_index);
        for (tables.piece_square[piece_index]) |key| {
            if (piece == .none or !piece.isValid()) {
                try std.testing.expectEqual(@as(types.Key, 0), key);
            } else {
                try std.testing.expect(key != 0);
                try expectUnique(seen[0..seen_count], key);
                seen[seen_count] = key;
                seen_count += 1;
            }
        }
    }
    for (tables.castling) |key| {
        try std.testing.expect(key != 0);
        try expectUnique(seen[0..seen_count], key);
        seen[seen_count] = key;
        seen_count += 1;
    }
    for (tables.en_passant_file) |key| {
        try std.testing.expect(key != 0);
        try expectUnique(seen[0..seen_count], key);
        seen[seen_count] = key;
        seen_count += 1;
    }
    try std.testing.expect(tables.side != 0);
    try expectUnique(seen[0..seen_count], tables.side);
}

test "Zobrist generation is deterministic and runtime-state-free" {
    // Rebuilding from the fixed project seed yields the same complete identity
    // domain without consulting time, OS randomness, or mutable globals.
    const regenerated = generate(seed);
    try std.testing.expectEqualDeep(tables, regenerated);
}

fn expectUnique(previous: []const types.Key, key: types.Key) !void {
    for (previous) |existing| try std.testing.expect(existing != key);
}
