const std = @import("std");

pub const current = "1.2.0";

test "the reported version is a release triple with no prerelease tag" {
    // Hard-coded component numbers went stale silently once -- and this file
    // was in no test root, so nothing caught it. The assertions below hold for
    // every release: the string parses, carries no prerelease or build
    // metadata, and renders back exactly as written.
    const parsed = try std.SemanticVersion.parse(current);
    try std.testing.expect(parsed.pre == null);
    try std.testing.expect(parsed.build == null);

    var buffer: [64]u8 = undefined;
    const rendered = try std.fmt.bufPrint(&buffer, "{d}.{d}.{d}", .{ parsed.major, parsed.minor, parsed.patch });
    try std.testing.expectEqualStrings(current, rendered);
}
