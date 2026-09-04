const std = @import("std");

pub const required = "0.16.0";

pub fn isSupported(actual: []const u8) bool {
    return std.mem.eql(u8, actual, required);
}

pub fn requireExact(comptime actual: []const u8) void {
    comptime {
        if (!isSupported(actual)) {
            @compileError("Manta requires Zig " ++ required ++ "; found " ++ actual);
        }
    }
}

test "the required stable compiler version is accepted" {
    try std.testing.expect(isSupported("0.16.0"));
}

test "other stable and development compiler versions are rejected" {
    const rejected = .{
        "0.15.2",
        "0.16.1",
        "0.17.0",
        "0.17.0-dev.1476+91a29d707",
    };

    inline for (rejected) |version| {
        try std.testing.expect(!isSupported(version));
    }
}
