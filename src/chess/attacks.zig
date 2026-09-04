//! Allocation-free, statically initialized attack geometry.
const std = @import("std");
const builtin = @import("builtin");
const magics = @import("generated/magics.zig");
const types = @import("types.zig");

const Slider = enum { bishop, rook };
const Bitboard = types.Bitboard;

const Magic = struct {
    mask: Bitboard,
    magic: u64,
    shift: u6,
    table: [*]const Bitboard,
};

const Pext = struct {
    mask: Bitboard,
    table: [*]const Bitboard,
};

pub const knight = makeLeaperTable(.knight);
pub const king = makeLeaperTable(.king);
pub const pawn = makePawnTable();
pub const bishop_rays = makeSliderRayTable(.bishop);
pub const rook_rays = makeSliderRayTable(.rook);
pub const line = makeRelationTable(.line);
pub const between = makeRelationTable(.between);

const rook_table_size = totalTableSize(.rook);
const bishop_table_size = totalTableSize(.bishop);
const rook_blob = @embedFile("generated/rook_attacks.bin");
const bishop_blob = @embedFile("generated/bishop_attacks.bin");
const embedded_header_size = 16;
const use_pext = builtin.cpu.arch == .x86_64 and
    std.Target.x86.featureSetHas(builtin.cpu.features, .bmi2);
const Lookup = if (use_pext) Pext else Magic;
const rook_magic_table: [rook_table_size]Bitboard align(64) = @bitCast(
    @as(
        *const [rook_table_size * @sizeOf(Bitboard)]u8,
        @ptrCast(rook_blob[embedded_header_size..].ptr),
    ).*,
);
const bishop_magic_table: [bishop_table_size]Bitboard align(64) = @bitCast(
    @as(
        *const [bishop_table_size * @sizeOf(Bitboard)]u8,
        @ptrCast(bishop_blob[embedded_header_size..].ptr),
    ).*,
);
const rook_table: [rook_table_size]Bitboard align(64) = if (use_pext)
    makePextTable(.rook, rook_magic_table)
else
    rook_magic_table;
const bishop_table: [bishop_table_size]Bitboard align(64) = if (use_pext)
    makePextTable(.bishop, bishop_magic_table)
else
    bishop_magic_table;
const rook_lookups: [64]Lookup align(64) = makeLookupTable(.rook);
const bishop_lookups: [64]Lookup align(64) = makeLookupTable(.bishop);

const rank_masks = makeLineMasks(.rank);
const file_masks = makeLineMasks(.file);
const diagonal_masks = makeLineMasks(.diagonal);
const anti_diagonal_masks = makeLineMasks(.anti_diagonal);

pub fn rook(square: types.Square, occupied: Bitboard) Bitboard {
    return if (builtin.cpu.arch == .aarch64)
        hyperbola(square, occupied, file_masks[square.index()]) |
            hyperbola(square, occupied, rank_masks[square.index()])
    else
        magicAttack(.rook, square, occupied);
}

pub fn bishop(square: types.Square, occupied: Bitboard) Bitboard {
    return if (builtin.cpu.arch == .aarch64)
        hyperbola(square, occupied, diagonal_masks[square.index()]) |
            hyperbola(square, occupied, anti_diagonal_masks[square.index()])
    else
        magicAttack(.bishop, square, occupied);
}

pub fn queen(square: types.Square, occupied: Bitboard) Bitboard {
    return rook(square, occupied) | bishop(square, occupied);
}

pub fn forPiece(piece_type: types.PieceType, color: types.Color, square: types.Square, occupied: Bitboard) Bitboard {
    return switch (piece_type) {
        .none => 0,
        .pawn => pawn[color.index()][square.index()],
        .knight => knight[square.index()],
        .bishop => bishop(square, occupied),
        .rook => rook(square, occupied),
        .queen => queen(square, occupied),
        .king => king[square.index()],
    };
}

fn magicAttack(comptime slider: Slider, square: types.Square, occupied: Bitboard) Bitboard {
    const entry = switch (slider) {
        .rook => &rook_lookups[square.index()],
        .bishop => &bishop_lookups[square.index()],
    };
    const index: usize = if (comptime use_pext)
        @intCast(pext(occupied, entry.mask))
    else
        @intCast(((occupied & entry.mask) *% entry.magic) >> entry.shift);
    return entry.table[index];
}

/// Converts the checked magic-order asset to the dense PEXT order at compile
/// time. Native BMI2 builds therefore pay neither runtime initialization nor a
/// second embedded asset; portable x86-64 and ARM64 retain their scalar paths.
fn makePextTable(
    comptime slider: Slider,
    comptime magic_table: [totalTableSize(slider)]Bitboard,
) [totalTableSize(slider)]Bitboard {
    @setEvalBranchQuota(20_000_000);
    var result: [totalTableSize(slider)]Bitboard = undefined;
    var offset: usize = 0;
    for (0..64) |square_usize| {
        const square: u6 = @intCast(square_usize);
        const mask = relevantMask(slider, square);
        const magic = switch (slider) {
            .rook => magics.rook[square],
            .bishop => magics.bishop[square],
        };
        const shift: u6 = @intCast(64 - @popCount(mask));
        var subset: Bitboard = 0;
        while (true) {
            const magic_index: usize = @intCast((subset *% magic) >> shift);
            const pext_index: usize = @intCast(pextSoftware(subset, mask));
            result[offset + pext_index] = magic_table[offset + magic_index];
            subset = (subset -% mask) & mask;
            if (subset == 0) break;
        }
        offset += @as(usize, 1) << @intCast(@popCount(mask));
    }
    return result;
}

inline fn pext(value: Bitboard, mask: Bitboard) Bitboard {
    return asm ("pextq %[mask], %[value], %[result]"
        : [result] "=r" (-> Bitboard),
        : [value] "r" (value),
          [mask] "r" (mask),
    );
}

fn pextSoftware(value: Bitboard, initial_mask: Bitboard) Bitboard {
    var mask = initial_mask;
    var result: Bitboard = 0;
    var destination: Bitboard = 1;
    while (mask != 0) {
        const source = mask & (~mask +% 1);
        if (value & source != 0) result |= destination;
        mask &= mask - 1;
        destination <<= 1;
    }
    return result;
}

fn hyperbola(square: types.Square, occupied_value: Bitboard, mask: Bitboard) Bitboard {
    const piece = square.bit();
    const occupied = (occupied_value | piece) & mask;
    const forward = occupied -% (piece *% 2);
    const reversed = @bitReverse(occupied) -% (@bitReverse(piece) *% 2);
    return (forward ^ @bitReverse(reversed)) & mask;
}

fn makeLookupTable(comptime slider: Slider) [64]Lookup {
    @setEvalBranchQuota(50_000);
    var result: [64]Lookup = undefined;
    var offset: usize = 0;
    for (0..64) |square| {
        const mask = relevantMask(slider, @intCast(square));
        const table = switch (slider) {
            .rook => rook_table[offset..].ptr,
            .bishop => bishop_table[offset..].ptr,
        };
        result[square] = if (use_pext)
            .{ .mask = mask, .table = table }
        else
            .{
                .mask = mask,
                .magic = switch (slider) {
                    .rook => magics.rook[square],
                    .bishop => magics.bishop[square],
                },
                .shift = @intCast(64 - @popCount(mask)),
                .table = table,
            };
        offset += @as(usize, 1) << @intCast(@popCount(mask));
    }
    return result;
}

fn totalTableSize(comptime slider: Slider) usize {
    @setEvalBranchQuota(20_000);
    var result: usize = 0;
    for (0..64) |square| {
        result += @as(usize, 1) << @intCast(@popCount(relevantMask(slider, @intCast(square))));
    }
    return result;
}

fn relevantMask(comptime slider: Slider, square: u6) Bitboard {
    return rayMask(slider, square, true);
}

fn slidingOracle(comptime slider: Slider, square: u6, occupied: Bitboard) Bitboard {
    return rayAttacks(slider, square, occupied);
}

fn rayMask(comptime slider: Slider, square: u6, comptime exclude_edge: bool) Bitboard {
    const coordinate = coordinates(square);
    const directions = sliderDirections(slider);
    var result: Bitboard = 0;
    for (directions) |direction| {
        var rank = coordinate.rank + direction[0];
        var file = coordinate.file + direction[1];
        while (inside(rank, file)) {
            if (exclude_edge and !inside(rank + direction[0], file + direction[1])) break;
            result |= coordinateBit(rank, file);
            rank += direction[0];
            file += direction[1];
        }
    }
    return result;
}

fn rayAttacks(comptime slider: Slider, square: u6, occupied: Bitboard) Bitboard {
    const coordinate = coordinates(square);
    const directions = sliderDirections(slider);
    var result: Bitboard = 0;
    for (directions) |direction| {
        var rank = coordinate.rank + direction[0];
        var file = coordinate.file + direction[1];
        while (inside(rank, file)) {
            const bit = coordinateBit(rank, file);
            result |= bit;
            if (occupied & bit != 0) break;
            rank += direction[0];
            file += direction[1];
        }
    }
    return result;
}

const Leaper = enum { knight, king };

fn makeLeaperTable(comptime leaper: Leaper) [64]Bitboard {
    @setEvalBranchQuota(20_000);
    var result: [64]Bitboard = @splat(0);
    const steps = switch (leaper) {
        .knight => [_][2]i8{ .{ 2, 1 }, .{ 2, -1 }, .{ 1, 2 }, .{ 1, -2 }, .{ -1, 2 }, .{ -1, -2 }, .{ -2, 1 }, .{ -2, -1 } },
        .king => [_][2]i8{ .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ -1, 1 }, .{ -1, 0 }, .{ -1, -1 }, .{ 0, -1 }, .{ 1, -1 } },
    };
    for (0..64) |square| {
        const coordinate = coordinates(@intCast(square));
        for (steps) |step| {
            const rank = coordinate.rank + step[0];
            const file = coordinate.file + step[1];
            if (inside(rank, file)) result[square] |= coordinateBit(rank, file);
        }
    }
    return result;
}

fn makePawnTable() [2][64]Bitboard {
    @setEvalBranchQuota(20_000);
    var result: [2][64]Bitboard = @splat(@splat(0));
    for (0..64) |square| {
        const coordinate = coordinates(@intCast(square));
        for ([_]types.Color{ .white, .black }) |color| {
            const rank_step: i8 = if (color == .white) 1 else -1;
            for ([_]i8{ -1, 1 }) |file_step| {
                const rank = coordinate.rank + rank_step;
                const file = coordinate.file + file_step;
                if (inside(rank, file)) result[color.index()][square] |= coordinateBit(rank, file);
            }
        }
    }
    return result;
}

fn makeSliderRayTable(comptime slider: Slider) [64]Bitboard {
    @setEvalBranchQuota(20_000);
    var result: [64]Bitboard = undefined;
    for (0..64) |square| result[square] = rayAttacks(slider, @intCast(square), 0);
    return result;
}

const LineKind = enum { rank, file, diagonal, anti_diagonal };

fn makeLineMasks(comptime kind: LineKind) [64]Bitboard {
    @setEvalBranchQuota(20_000);
    var result: [64]Bitboard = undefined;
    const slider: Slider = if (kind == .rank or kind == .file) .rook else .bishop;
    const chosen = switch (kind) {
        .rank => [_]usize{ 2, 3 },
        .file => [_]usize{ 0, 1 },
        .diagonal => [_]usize{ 0, 3 },
        .anti_diagonal => [_]usize{ 1, 2 },
    };
    const directions = sliderDirections(slider);
    for (0..64) |square| {
        const coordinate = coordinates(@intCast(square));
        var mask = @as(Bitboard, 1) << @intCast(square);
        for (chosen) |direction_index| {
            const direction = directions[direction_index];
            var rank = coordinate.rank + direction[0];
            var file = coordinate.file + direction[1];
            while (inside(rank, file)) {
                mask |= coordinateBit(rank, file);
                rank += direction[0];
                file += direction[1];
            }
        }
        result[square] = mask;
    }
    return result;
}

const Relation = enum { line, between };

fn makeRelationTable(comptime relation: Relation) [64][64]Bitboard {
    @setEvalBranchQuota(500_000);
    var result: [64][64]Bitboard = @splat(@splat(0));
    for (0..64) |from| {
        for (0..64) |to| {
            if (from == to) continue;
            const a = coordinates(@intCast(from));
            const b = coordinates(@intCast(to));
            const rank_delta = b.rank - a.rank;
            const file_delta = b.file - a.file;
            const direction = normalizedDirection(rank_delta, file_delta) orelse continue;
            if (relation == .between) {
                var rank = a.rank + direction[0];
                var file = a.file + direction[1];
                while (rank != b.rank or file != b.file) {
                    result[from][to] |= coordinateBit(rank, file);
                    rank += direction[0];
                    file += direction[1];
                }
            } else {
                var rank = a.rank;
                var file = a.file;
                while (inside(rank - direction[0], file - direction[1])) {
                    rank -= direction[0];
                    file -= direction[1];
                }
                while (inside(rank, file)) {
                    result[from][to] |= coordinateBit(rank, file);
                    rank += direction[0];
                    file += direction[1];
                }
            }
        }
    }
    return result;
}

fn normalizedDirection(rank_delta: i8, file_delta: i8) ?[2]i8 {
    if (rank_delta == 0 and file_delta != 0) return .{ 0, sign(file_delta) };
    if (file_delta == 0 and rank_delta != 0) return .{ sign(rank_delta), 0 };
    if (absolute(rank_delta) == absolute(file_delta)) return .{ sign(rank_delta), sign(file_delta) };
    return null;
}

fn sliderDirections(comptime slider: Slider) [4][2]i8 {
    return switch (slider) {
        .bishop => .{ .{ 1, 1 }, .{ 1, -1 }, .{ -1, 1 }, .{ -1, -1 } },
        .rook => .{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } },
    };
}

const Coordinates = struct { rank: i8, file: i8 };

fn coordinates(square: u6) Coordinates {
    return .{ .rank = @intCast(square / 8), .file = @intCast(square % 8) };
}

fn coordinateBit(rank: i8, file: i8) Bitboard {
    std.debug.assert(inside(rank, file));
    const square: u6 = @intCast(rank * 8 + file);
    return @as(Bitboard, 1) << square;
}

fn inside(rank: i8, file: i8) bool {
    return rank >= 0 and rank < 8 and file >= 0 and file < 8;
}

fn sign(value: i8) i8 {
    return if (value < 0) -1 else 1;
}

fn absolute(value: i8) i8 {
    return if (value < 0) -value else value;
}

test "sliding backends match an independent coordinate oracle exhaustively" {
    // Every blocker subset that can change an attack is checked. Edge blockers
    // are included by the oracle but cannot change squares beyond the board.
    inline for ([_]Slider{ .bishop, .rook }) |slider| {
        for (0..64) |square_usize| {
            const square_index: u6 = @intCast(square_usize);
            const square = types.Square.fromIndex(square_index);
            const mask = relevantMask(slider, square_index);
            var occupied: Bitboard = 0;
            while (true) {
                const expected = independentSlider(slider, square_index, occupied);
                const magic_actual = magicAttack(slider, square, occupied);
                const hq_actual = switch (slider) {
                    .rook => hyperbola(square, occupied, file_masks[square_index]) |
                        hyperbola(square, occupied, rank_masks[square_index]),
                    .bishop => hyperbola(square, occupied, diagonal_masks[square_index]) |
                        hyperbola(square, occupied, anti_diagonal_masks[square_index]),
                };
                try std.testing.expectEqual(expected, magic_actual);
                try std.testing.expectEqual(expected, hq_actual);
                occupied = (occupied -% mask) & mask;
                if (occupied == 0) break;
            }
        }
    }
}

fn independentSlider(slider: Slider, square: u6, occupied: Bitboard) Bitboard {
    // Test oracle uses explicit rank/file coordinates and does not use masks,
    // magic indexing, bit reversal, or production table construction.
    const origin_rank: i8 = @intCast(square / 8);
    const origin_file: i8 = @intCast(square % 8);
    const directions = switch (slider) {
        .bishop => [_][2]i8{ .{ -1, -1 }, .{ -1, 1 }, .{ 1, -1 }, .{ 1, 1 } },
        .rook => [_][2]i8{ .{ -1, 0 }, .{ 0, -1 }, .{ 0, 1 }, .{ 1, 0 } },
    };
    var result: Bitboard = 0;
    for (directions) |direction| {
        var rank = origin_rank + direction[0];
        var file = origin_file + direction[1];
        while (rank >= 0 and rank <= 7 and file >= 0 and file <= 7) {
            const target: u6 = @intCast(rank * 8 + file);
            const bit = @as(Bitboard, 1) << target;
            result |= bit;
            if (occupied & bit != 0) break;
            rank += direction[0];
            file += direction[1];
        }
    }
    return result;
}

test "leaper and relation tables preserve chess geometry" {
    try std.testing.expectEqual(@as(u7, 2), @popCount(knight[types.Square.a1.index()]));
    try std.testing.expectEqual(@as(u7, 8), @popCount(knight[types.Square.d4.index()]));
    try std.testing.expectEqual(@as(u7, 3), @popCount(king[types.Square.a1.index()]));
    try std.testing.expectEqual(types.Square.d5.bit() | types.Square.f5.bit(), pawn[types.Color.white.index()][types.Square.e4.index()]);
    try std.testing.expectEqual(types.Square.d3.bit() | types.Square.f3.bit(), pawn[types.Color.black.index()][types.Square.e4.index()]);

    try std.testing.expectEqual(
        types.Square.d2.bit() | types.Square.c3.bit() | types.Square.b4.bit(),
        between[types.Square.e1.index()][types.Square.a5.index()],
    );
    try std.testing.expectEqual(@as(Bitboard, 0), between[types.Square.a1.index()][types.Square.b3.index()]);
    try std.testing.expect(line[types.Square.a1.index()][types.Square.h8.index()] & types.Square.d4.bit() != 0);
}

comptime {
    std.debug.assert(rook_table_size == 102400);
    std.debug.assert(bishop_table_size == 5248);
    std.debug.assert(rook_blob.len == embedded_header_size + rook_table_size * @sizeOf(Bitboard));
    std.debug.assert(bishop_blob.len == embedded_header_size + bishop_table_size * @sizeOf(Bitboard));
    std.debug.assert(std.mem.eql(u8, rook_blob[0..8], "MANTAATK"));
    std.debug.assert(std.mem.eql(u8, bishop_blob[0..8], "MANTAATK"));
    std.debug.assert(std.mem.readInt(u32, rook_blob[8..12], .little) == 1);
    std.debug.assert(std.mem.readInt(u32, bishop_blob[8..12], .little) == 1);
    std.debug.assert(std.mem.readInt(u32, rook_blob[12..16], .little) == rook_table_size);
    std.debug.assert(std.mem.readInt(u32, bishop_blob[12..16], .little) == bishop_table_size);
    _ = @as(*align(64) const [rook_table_size]Bitboard, &rook_table);
    _ = @as(*align(64) const [bishop_table_size]Bitboard, &bishop_table);
    _ = @as(*align(64) const [64]Lookup, &rook_lookups);
    _ = @as(*align(64) const [64]Lookup, &bishop_lookups);
    std.debug.assert(@sizeOf(Magic) == 32);
    std.debug.assert(@sizeOf(Pext) == 16);
}
