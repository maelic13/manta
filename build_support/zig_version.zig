const std = @import("std");

pub const required = "0.17.0";

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
    try std.testing.expect(isSupported("0.17.0"));
}

test "other stable and development compiler versions are rejected" {
    const rejected = .{
        "0.16.0",
        "0.17.1",
        "0.18.0",
        "0.18.0-dev.120+9fe22a29b",
    };

    inline for (rejected) |version| {
        try std.testing.expect(!isSupported(version));
    }
}
