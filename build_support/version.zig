const std = @import("std");

pub const current = "1.0.0";

test "release version is valid semantic versioning" {
    const parsed = try std.SemanticVersion.parse(current);
    try std.testing.expect(parsed.major == 1);
    try std.testing.expect(parsed.minor == 0);
    try std.testing.expect(parsed.patch == 0);
}
