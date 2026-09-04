//! Offline generator for Manta's x86-64 scalar sliding-attack constants.
//! The generated constants are verified exhaustively by the normal test suite.
const std = @import("std");

const Bitboard = u64;
const square_count = 64;
const max_subsets = 4096;

const Slider = enum { bishop, rook };

var random_state: u64 = 0x4d61_6e74_612d_6d67;

pub fn main() void {
    printSet(.rook, "rook");
    printSet(.bishop, "bishop");
}

fn printSet(slider: Slider, name: []const u8) void {
    std.debug.print("pub const {s} = [64]u64{{\n", .{name});
    for (0..square_count) |square| {
        const magic = findMagic(slider, @intCast(square));
        std.debug.print("    0x{x:0>16},\n", .{magic});
    }
    std.debug.print("}};\n\n", .{});
}

fn findMagic(slider: Slider, square: u6) Bitboard {
    const mask = relevantMask(slider, square);
    const bit_count: u7 = @intCast(@popCount(mask));
    const subset_count: usize = @as(usize, 1) << @intCast(bit_count);
    const shift: u6 = @intCast(64 - bit_count);

    var occupancies: [max_subsets]Bitboard = undefined;
    var references: [max_subsets]Bitboard = undefined;
    var subset: Bitboard = 0;
    var index: usize = 0;
    while (true) {
        occupancies[index] = subset;
        references[index] = slidingOracle(slider, square, subset);
        index += 1;
        subset = (subset -% mask) & mask;
        if (subset == 0) break;
    }
    std.debug.assert(index == subset_count);

    var used: [max_subsets]Bitboard = undefined;
    var epoch: [max_subsets]u32 = @splat(0);
    var generation: u32 = 0;
    while (true) {
        const candidate = sparseRandom();
        if (@popCount((mask *% candidate) & 0xff00_0000_0000_0000) < 6) continue;
        generation +%= 1;
        if (generation == 0) {
            epoch = @splat(0);
            generation = 1;
        }

        var valid = true;
        for (occupancies[0..subset_count], references[0..subset_count]) |occupancy, reference| {
            const attack_index: usize = @intCast((occupancy *% candidate) >> shift);
            if (epoch[attack_index] != generation) {
                epoch[attack_index] = generation;
                used[attack_index] = reference;
            } else if (used[attack_index] != reference) {
                valid = false;
                break;
            }
        }
        if (valid) return candidate;
    }
}

fn sparseRandom() u64 {
    return nextRandom() & nextRandom() & nextRandom();
}

fn nextRandom() u64 {
    random_state +%= 0x9e37_79b9_7f4a_7c15;
    var value = random_state;
    value = (value ^ (value >> 30)) *% 0xbf58_476d_1ce4_e5b9;
    value = (value ^ (value >> 27)) *% 0x94d0_49bb_1331_11eb;
    return value ^ (value >> 31);
}

fn relevantMask(slider: Slider, square: u6) Bitboard {
    const rank: i8 = @intCast(square / 8);
    const file: i8 = @intCast(square % 8);
    const directions = switch (slider) {
        .bishop => [_][2]i8{ .{ 1, 1 }, .{ 1, -1 }, .{ -1, 1 }, .{ -1, -1 } },
        .rook => [_][2]i8{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } },
    };
    var result: Bitboard = 0;
    for (directions) |direction| {
        var next_rank = rank + direction[0];
        var next_file = file + direction[1];
        while (inside(next_rank, next_file)) {
            const after_rank = next_rank + direction[0];
            const after_file = next_file + direction[1];
            if (!inside(after_rank, after_file)) break;
            const next_square: u6 = @intCast(next_rank * 8 + next_file);
            result |= @as(Bitboard, 1) << next_square;
            next_rank += direction[0];
            next_file += direction[1];
        }
    }
    return result;
}

fn slidingOracle(slider: Slider, square: u6, occupied: Bitboard) Bitboard {
    const rank: i8 = @intCast(square / 8);
    const file: i8 = @intCast(square % 8);
    const directions = switch (slider) {
        .bishop => [_][2]i8{ .{ 1, 1 }, .{ 1, -1 }, .{ -1, 1 }, .{ -1, -1 } },
        .rook => [_][2]i8{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } },
    };
    var result: Bitboard = 0;
    for (directions) |direction| {
        var next_rank = rank + direction[0];
        var next_file = file + direction[1];
        while (inside(next_rank, next_file)) {
            const next_square: u6 = @intCast(next_rank * 8 + next_file);
            const bit = @as(Bitboard, 1) << next_square;
            result |= bit;
            if (occupied & bit != 0) break;
            next_rank += direction[0];
            next_file += direction[1];
        }
    }
    return result;
}

fn inside(rank: i8, file: i8) bool {
    return rank >= 0 and rank < 8 and file >= 0 and file < 8;
}
