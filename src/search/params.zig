//! Immutable search-policy values and their tune-only UCI registry.
const std = @import("std");
const search_build_options = @import("search_build_options");

pub const tune_enabled = search_build_options.tune;

pub const Id = enum {
    probcut_margin,
    reverse_futility_margin,
    lmr_extra_scale,
    late_move_base,
    late_move_depth_scale,
    late_move_improving_bonus,
    quiet_futility_unit,
    see_pruning_unit,
    qsearch_delta_cushion,
    reply_history_weight,
    continuation_history_weight,
};

pub const Spec = struct {
    id: Id,
    name: []const u8,
    default: i32,
    min: i32,
    max: i32,
};

const probcut_margin_default = 103;
const reverse_futility_margin_default = 68;
const lmr_extra_scale_default = 116;
const late_move_base_default = 4;
const late_move_depth_scale_default = 3;
const late_move_improving_bonus_default = 4;
const quiet_futility_unit_default = 100;
const see_pruning_unit_default = 107;
const qsearch_delta_cushion_default = 122;
const reply_history_weight_default = 116;
const continuation_history_weight_default = 118;

/// Defaults reproduce the accepted MAN-S29 search exactly. The ranges are
/// prospective sensitivity bounds, not claims that either edge is sound.
pub const specs = [_]Spec{
    .{ .id = .probcut_margin, .name = "ProbCutMargin", .default = probcut_margin_default, .min = 25, .max = 300 },
    .{ .id = .reverse_futility_margin, .name = "ReverseFutilityMargin", .default = reverse_futility_margin_default, .min = 25, .max = 300 },
    .{ .id = .lmr_extra_scale, .name = "LmrExtraScale", .default = lmr_extra_scale_default, .min = 50, .max = 200 },
    .{ .id = .late_move_base, .name = "LateMoveBase", .default = late_move_base_default, .min = 1, .max = 8 },
    .{ .id = .late_move_depth_scale, .name = "LateMoveDepthScale", .default = late_move_depth_scale_default, .min = 0, .max = 6 },
    .{ .id = .late_move_improving_bonus, .name = "LateMoveImprovingBonus", .default = late_move_improving_bonus_default, .min = 0, .max = 6 },
    .{ .id = .quiet_futility_unit, .name = "QuietFutilityUnit", .default = quiet_futility_unit_default, .min = 25, .max = 300 },
    .{ .id = .see_pruning_unit, .name = "SeePruningUnit", .default = see_pruning_unit_default, .min = 25, .max = 300 },
    .{ .id = .qsearch_delta_cushion, .name = "QsearchDeltaCushion", .default = qsearch_delta_cushion_default, .min = 25, .max = 300 },
    .{ .id = .reply_history_weight, .name = "ReplyHistoryWeight", .default = reply_history_weight_default, .min = 0, .max = 200 },
    .{ .id = .continuation_history_weight, .name = "ContinuationHistoryWeight", .default = continuation_history_weight_default, .min = 0, .max = 200 },
};

pub const Values = struct {
    probcut_margin: i32 = probcut_margin_default,
    reverse_futility_margin: i32 = reverse_futility_margin_default,
    lmr_extra_scale: i32 = lmr_extra_scale_default,
    late_move_base: i32 = late_move_base_default,
    late_move_depth_scale: i32 = late_move_depth_scale_default,
    late_move_improving_bonus: i32 = late_move_improving_bonus_default,
    quiet_futility_unit: i32 = quiet_futility_unit_default,
    see_pruning_unit: i32 = see_pruning_unit_default,
    qsearch_delta_cushion: i32 = qsearch_delta_cushion_default,
    reply_history_weight: i32 = reply_history_weight_default,
    continuation_history_weight: i32 = continuation_history_weight_default,

    pub fn get(self: Values, id: Id) i32 {
        return switch (id) {
            inline else => |tag| @field(self, @tagName(tag)),
        };
    }

    pub fn set(self: *Values, id: Id, value: i32) void {
        const spec = specFor(id);
        switch (id) {
            inline else => |tag| @field(self, @tagName(tag)) = std.math.clamp(value, spec.min, spec.max),
        }
    }
};

/// Frozen pre-SPSA values used only to reproduce archived MAN-S19-relative
/// diagnostic fingerprints. They are not a selectable production policy.
pub const man_s19: Values = .{
    .probcut_margin = 100,
    .reverse_futility_margin = 100,
    .lmr_extra_scale = 100,
    .late_move_base = 3,
    .late_move_depth_scale = 2,
    .late_move_improving_bonus = 2,
    .quiet_futility_unit = 100,
    .see_pruning_unit = 100,
    .qsearch_delta_cushion = 100,
    .reply_history_weight = 100,
    .continuation_history_weight = 100,
};

pub fn find(name: []const u8) ?Spec {
    for (specs) |spec|
        if (std.ascii.eqlIgnoreCase(name, spec.name)) return spec;
    return null;
}

fn specFor(id: Id) Spec {
    for (specs) |spec|
        if (spec.id == id) return spec;
    unreachable;
}

test "search parameter defaults and ranges share one registry" {
    const values: Values = .{};
    inline for (specs) |spec| {
        try std.testing.expectEqual(spec.default, values.get(spec.id));
        try std.testing.expect(spec.min < spec.default and spec.default < spec.max);
        try std.testing.expectEqual(spec, find(spec.name).?);
    }
}

test "search parameter writes clamp at the declared boundary" {
    var values: Values = .{};
    inline for (specs) |spec| {
        values.set(spec.id, spec.min - 1);
        try std.testing.expectEqual(spec.min, values.get(spec.id));
        values.set(spec.id, spec.max + 1);
        try std.testing.expectEqual(spec.max, values.get(spec.id));
    }
}

test "production defaults are the accepted MAN-S29 vector" {
    // SCORE-026/QUAL-015/PERF-010: these exact integers are the prospectively
    // frozen rounding of MAN-S28's complete theta and won MAN-S29's registered
    // production SPRT as one cohesive vector.
    const expected: Values = .{
        .probcut_margin = 103,
        .reverse_futility_margin = 68,
        .lmr_extra_scale = 116,
        .late_move_base = 4,
        .late_move_depth_scale = 3,
        .late_move_improving_bonus = 4,
        .see_pruning_unit = 107,
        .qsearch_delta_cushion = 122,
        .reply_history_weight = 116,
        .continuation_history_weight = 118,
    };
    try std.testing.expectEqual(expected, Values{});
    try std.testing.expectEqual(@as(i32, 100), (Values{}).quiet_futility_unit);
    try std.testing.expectEqual(@as(i32, 100), man_s19.probcut_margin);
    try std.testing.expectEqual(@as(i32, 100), man_s19.continuation_history_weight);
}
