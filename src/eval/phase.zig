//! Promotion-safe tapered-evaluation phase and interpolation.
const std = @import("std");

pub const Phase = struct {
    current: u16,
    total: u16,

    pub fn init(current: u32, total: u16) ?Phase {
        if (total == 0) return null;
        return .{
            .current = @intCast(@min(current, total)),
            .total = total,
        };
    }

    /// Blends from endgame at zero phase to middlegame at full phase.
    /// Truncation toward zero makes blending exactly color-antisymmetric.
    pub fn interpolate(self: Phase, middlegame: i32, endgame: i32) i32 {
        const current = @as(i64, self.current);
        const total = @as(i64, self.total);
        const weighted = @as(i64, middlegame) * current +
            @as(i64, endgame) * (total - current);
        return @intCast(@divTrunc(weighted, total));
    }
};

test "phase endpoints and signed interpolation are exact" {
    // Evaluation phase is a convex blend, not a source of side bias.
    const opening = Phase.init(24, 24).?;
    const ending = Phase.init(0, 24).?;
    const middle = Phase.init(12, 24).?;
    try std.testing.expectEqual(@as(i32, 80), opening.interpolate(80, 20));
    try std.testing.expectEqual(@as(i32, 20), ending.interpolate(80, 20));
    try std.testing.expectEqual(@as(i32, 50), middle.interpolate(80, 20));
    try std.testing.expectEqual(
        -middle.interpolate(81, -20),
        middle.interpolate(-81, 20),
    );
}

test "promotion-heavy material clamps to the opening endpoint" {
    // Legal promotions can exceed the nominal initial material phase.
    const promoted = Phase.init(31, 24).?;
    try std.testing.expectEqual(@as(u16, 24), promoted.current);
    try std.testing.expectEqual(@as(i32, 90), promoted.interpolate(90, -10));
    try std.testing.expect(Phase.init(0, 0) == null);
}
