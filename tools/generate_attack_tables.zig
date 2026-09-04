//! Regenerates Manta's embedded scalar sliding-attack tables from the checked
//! magic multipliers. Run with `zig build generate-attacks`; this is an offline
//! maintenance tool, not engine startup.
const std = @import("std");
const magics = @import("magics");

const Bitboard = u64;
const Slider = enum { bishop, rook };
const header_size = 16;

pub fn main(init: std.process.Init) !void {
    try writeTable(init, .rook, "src/chess/generated/rook_attacks.bin");
    try writeTable(init, .bishop, "src/chess/generated/bishop_attacks.bin");
}

fn writeTable(init: std.process.Init, comptime slider: Slider, path: []const u8) !void {
    const allocator = init.gpa;
    const entry_count = tableSize(slider);
    const values = try allocator.alloc(Bitboard, entry_count);
    defer allocator.free(values);
    @memset(values, 0);

    var offset: usize = 0;
    for (0..64) |square_usize| {
        const square: u6 = @intCast(square_usize);
        const mask = relevantMask(slider, square);
        const shift: u6 = @intCast(64 - @popCount(mask));
        const magic = switch (slider) {
            .rook => magics.rook[square],
            .bishop => magics.bishop[square],
        };
        var subset: Bitboard = 0;
        while (true) {
            const index: usize = @intCast((subset *% magic) >> shift);
            const attack = slidingOracle(slider, square, subset);
            if (values[offset + index] == 0) {
                values[offset + index] = attack;
            } else if (values[offset + index] != attack) {
                return error.InvalidMagic;
            }
            subset = (subset -% mask) & mask;
            if (subset == 0) break;
        }
        offset += @as(usize, 1) << @intCast(@popCount(mask));
    }
    std.debug.assert(offset == entry_count);

    const bytes = try allocator.alloc(u8, header_size + values.len * @sizeOf(Bitboard));
    defer allocator.free(bytes);
    @memcpy(bytes[0..8], "MANTAATK");
    std.mem.writeInt(u32, bytes[8..12], 1, .little);
    std.mem.writeInt(u32, bytes[12..16], @intCast(values.len), .little);
    for (values, 0..) |value, index| {
        const start = header_size + index * @sizeOf(Bitboard);
        std.mem.writeInt(u64, bytes[start..][0..8], value, .little);
    }

    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = bytes });
}

fn tableSize(comptime slider: Slider) usize {
    var result: usize = 0;
    for (0..64) |square| {
        result += @as(usize, 1) << @intCast(@popCount(relevantMask(slider, @intCast(square))));
    }
    return result;
}

fn relevantMask(comptime slider: Slider, square: u6) Bitboard {
    const origin_rank: i8 = @intCast(square / 8);
    const origin_file: i8 = @intCast(square % 8);
    const directions = directionsFor(slider);
    var result: Bitboard = 0;
    for (directions) |direction| {
        var rank = origin_rank + direction[0];
        var file = origin_file + direction[1];
        while (inside(rank, file)) {
            if (!inside(rank + direction[0], file + direction[1])) break;
            result |= bit(rank, file);
            rank += direction[0];
            file += direction[1];
        }
    }
    return result;
}

fn slidingOracle(comptime slider: Slider, square: u6, occupied: Bitboard) Bitboard {
    const origin_rank: i8 = @intCast(square / 8);
    const origin_file: i8 = @intCast(square % 8);
    const directions = directionsFor(slider);
    var result: Bitboard = 0;
    for (directions) |direction| {
        var rank = origin_rank + direction[0];
        var file = origin_file + direction[1];
        while (inside(rank, file)) {
            const target = bit(rank, file);
            result |= target;
            if (occupied & target != 0) break;
            rank += direction[0];
            file += direction[1];
        }
    }
    return result;
}

fn directionsFor(comptime slider: Slider) [4][2]i8 {
    return switch (slider) {
        .bishop => .{ .{ 1, 1 }, .{ 1, -1 }, .{ -1, 1 }, .{ -1, -1 } },
        .rook => .{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } },
    };
}

fn bit(rank: i8, file: i8) Bitboard {
    return @as(Bitboard, 1) << @as(u6, @intCast(rank * 8 + file));
}

fn inside(rank: i8, file: i8) bool {
    return rank >= 0 and rank < 8 and file >= 0 and file < 8;
}
