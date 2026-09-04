//! Compile-time evaluation trace sinks with a zero-cost disabled path.
const std = @import("std");

pub const Disabled = struct {
    pub inline fn emit(_: *Disabled, comptime _: []const u8, _: anytype) void {}
};

pub fn Buffer(comptime EntryType: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        pub const Entry = EntryType;
        pub const Record = struct {
            label: []const u8,
            value: Entry,
        };

        records: [capacity]Record,
        count: usize = 0,
        truncated: bool = false,

        pub fn init() Self {
            // SAFETY: `count` starts at zero, and access is restricted to the
            // initialized prefix written by `emit`.
            return .{ .records = undefined };
        }

        pub fn emit(self: *Self, comptime label: []const u8, value: Entry) void {
            if (self.count == capacity) {
                self.truncated = true;
                return;
            }
            self.records[self.count] = .{ .label = label, .value = value };
            self.count += 1;
        }

        pub fn slice(self: *const Self) []const Record {
            return self.records[0..self.count];
        }
    };
}

pub fn isSink(comptime Sink: type, comptime Entry: type) bool {
    if (Sink == Disabled) return true;
    if (!@hasDecl(Sink, "Entry") or !@hasDecl(Sink, "emit")) return false;
    return Sink.Entry == Entry;
}

pub fn requireSink(comptime Sink: type, comptime Entry: type) void {
    if (!isSink(Sink, Entry)) {
        @compileError("evaluation trace sink must be Disabled or expose the evaluator's Entry and emit contract");
    }
}

comptime {
    std.debug.assert(@sizeOf(Disabled) == 0);
}

test "bounded trace records labels without allocation and reports truncation" {
    // Diagnostics are bounded and never alter the evaluator's failure surface.
    const TestBuffer = Buffer(i32, 2);
    var buffer = TestBuffer.init();
    buffer.emit("first", 1);
    buffer.emit("second", 2);
    buffer.emit("third", 3);
    try std.testing.expectEqual(@as(usize, 2), buffer.slice().len);
    try std.testing.expectEqualStrings("first", buffer.slice()[0].label);
    try std.testing.expect(buffer.truncated);
    try std.testing.expect(isSink(TestBuffer, i32));
    try std.testing.expect(!isSink(TestBuffer, u32));
}
