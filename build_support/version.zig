const std = @import("std");

/// Development version between the 1.0.0 release and the next one. The
/// `-dev` prerelease tag is deliberate: builds from this tree must be
/// distinguishable from the 1.0.0 release without claiming to be a release
/// themselves.
pub const current = "1.1.0-dev";

test "development version is valid semantic versioning" {
    const parsed = try std.SemanticVersion.parse(current);
    try std.testing.expect(parsed.major == 1);
    try std.testing.expect(parsed.minor == 1);
    try std.testing.expect(parsed.patch == 0);
    // A prerelease tag is what keeps this from reading as a release.
    try std.testing.expect(parsed.pre != null);
    try std.testing.expectEqualStrings("dev", parsed.pre.?);
}
