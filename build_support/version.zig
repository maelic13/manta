const std = @import("std");

pub const current = "1.1.0";

test "release version is valid semantic versioning" {
    const parsed = try std.SemanticVersion.parse(current);
    try std.testing.expect(parsed.major == 1);
    try std.testing.expect(parsed.minor == 1);
    try std.testing.expect(parsed.patch == 0);
    // A release carries neither a prerelease tag nor build metadata.
    try std.testing.expect(parsed.pre == null);
    try std.testing.expect(parsed.build == null);
}
