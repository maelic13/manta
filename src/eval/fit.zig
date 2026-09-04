//! Offline HCE fitting feature events.
//!
//! Production sinks do not implement `coefficient`, so every call below is
//! removed at comptime. The fitting sink records a sparse list outside search.
const std = @import("std");

pub const schema_version = "manta-hce-fit-v3";

pub const Component = enum {
    material_pst,
    pawns,
    activity,
    passed,
    king_safety,
    pawn_threats,
    threats_space,
    winnability,
    final,
};

pub const Lane = enum { scalar, middlegame, endgame };

pub const Entry = struct {
    group: []const u8,
    element: u16,
    component: Component,
    lane: Lane,
    count: i32,
};

pub const max_sparse_entries = 512;

pub const Recorder = struct {
    entries: [max_sparse_entries]Entry,
    len: usize = 0,
    overflowed: bool = false,
    phase: ?u8 = null,
    total: ?i32 = null,

    pub fn init() Recorder {
        // SAFETY: `len` starts at zero and every entry is initialized before
        // it joins the observable prefix returned by `slice`.
        return .{ .entries = undefined };
    }

    pub fn emit(self: *Recorder, label: []const u8, value: anytype) void {
        if (std.mem.eql(u8, label, "phase")) self.phase = value.phase;
        if (std.mem.eql(u8, label, "total")) self.total = value.total;
    }

    pub fn coefficient(
        self: *Recorder,
        group: []const u8,
        element: usize,
        component: Component,
        lane: Lane,
        count: i32,
    ) void {
        if (count == 0) return;
        for (self.entries[0..self.len]) |*entry| {
            if (entry.element == element and entry.component == component and
                entry.lane == lane and std.mem.eql(u8, entry.group, group))
            {
                entry.count += count;
                return;
            }
        }
        if (self.len == self.entries.len) {
            self.overflowed = true;
            return;
        }
        self.entries[self.len] = .{
            .group = group,
            .element = @intCast(element),
            .component = component,
            .lane = lane,
            .count = count,
        };
        self.len += 1;
    }

    pub fn slice(self: *const Recorder) []const Entry {
        return self.entries[0..self.len];
    }
};

pub inline fn record(
    comptime Sink: type,
    sink: *Sink,
    comptime group: []const u8,
    element: usize,
    component: Component,
    lane: Lane,
    count: i32,
) void {
    if (comptime @hasDecl(Sink, "coefficient"))
        sink.coefficient(group, element, component, lane, count);
}

pub inline fn tapered(
    comptime Sink: type,
    sink: *Sink,
    comptime group: []const u8,
    element: usize,
    component: Component,
    count: i32,
) void {
    record(Sink, sink, group, element * 2, component, .middlegame, count);
    record(Sink, sink, group, element * 2 + 1, component, .endgame, count);
}

test "sparse recorder merges identical coefficient applications" {
    var recorder = Recorder.init();
    recorder.coefficient("doubled", 0, .pawns, .middlegame, 2);
    recorder.coefficient("doubled", 0, .pawns, .middlegame, -1);
    recorder.coefficient("doubled", 1, .pawns, .endgame, 3);
    try std.testing.expectEqual(@as(usize, 2), recorder.len);
    try std.testing.expectEqual(@as(i32, 1), recorder.entries[0].count);
    try std.testing.expect(!recorder.overflowed);
}
