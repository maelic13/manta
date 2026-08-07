const std = @import("std");
const manta = @import("manta");

test "the library facade is independently importable" {
    std.testing.refAllDecls(manta);
}
