//! Regenerates Manta's exact KPK win/draw bitbase. Run with
//! `zig build generate-kpk`; this is offline maintenance, not engine startup.
const std = @import("std");
const kpk = @import("eval/kpk.zig");

pub fn main(init: std.process.Init) !void {
    const words = kpk.buildWins();
    var bytes: [kpk.byte_count]u8 = undefined;
    for (words, 0..) |word, index| {
        const start = index * @sizeOf(u64);
        std.mem.writeInt(u64, bytes[start..][0..8], word, .little);
    }
    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = "src/eval/kpk.bin",
        .data = &bytes,
    });
}
