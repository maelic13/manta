//! Authoritative public UCI option definitions.

pub const Id = enum {
    hash,
    threads,
    clear_hash,
    ponder,
    move_overhead,
    syzygy_path,
    syzygy_probe_depth,
    syzygy_probe_limit,
    syzygy_fifty_move_rule,
};

pub const Kind = union(enum) {
    spin: struct { default: u64, min: u64, max: u64 },
    check: bool,
    button,
    string: []const u8,
};

pub const Spec = struct {
    id: Id,
    name: []const u8,
    normalized_name: []const u8,
    kind: Kind,
};

/// Canonical declaration order. Every advertised option has an active typed
/// consumer; the Threads range is the accepted RES-006 public contract.
pub const public = [_]Spec{
    .{ .id = .threads, .name = "Threads", .normalized_name = "threads", .kind = .{ .spin = .{ .default = 1, .min = 1, .max = 1024 } } },
    .{ .id = .hash, .name = "Hash", .normalized_name = "hash", .kind = .{ .spin = .{ .default = 64, .min = 1, .max = 1_048_576 } } },
    .{ .id = .clear_hash, .name = "Clear Hash", .normalized_name = "clear hash", .kind = .button },
    .{ .id = .ponder, .name = "Ponder", .normalized_name = "ponder", .kind = .{ .check = false } },
    .{ .id = .move_overhead, .name = "Move Overhead", .normalized_name = "move overhead", .kind = .{ .spin = .{ .default = 10, .min = 0, .max = 5_000 } } },
    .{ .id = .syzygy_path, .name = "SyzygyPath", .normalized_name = "syzygypath", .kind = .{ .string = "<empty>" } },
    .{ .id = .syzygy_probe_depth, .name = "SyzygyProbeDepth", .normalized_name = "syzygyprobedepth", .kind = .{ .spin = .{ .default = 1, .min = 1, .max = 100 } } },
    .{ .id = .syzygy_probe_limit, .name = "SyzygyProbeLimit", .normalized_name = "syzygyprobelimit", .kind = .{ .spin = .{ .default = 7, .min = 0, .max = 7 } } },
    .{ .id = .syzygy_fifty_move_rule, .name = "Syzygy50MoveRule", .normalized_name = "syzygy50moverule", .kind = .{ .check = true } },
};

pub fn find(normalized_name: []const u8) ?Spec {
    for (public) |spec| {
        if (std.mem.eql(u8, normalized_name, spec.normalized_name)) return spec;
    }
    return null;
}

pub fn get(comptime id: Id) Spec {
    inline for (public) |spec| if (spec.id == id) return spec;
    unreachable;
}

const std = @import("std");

test "public registry names and defaults are unique and in range" {
    for (public, 0..) |spec, index| {
        for (public[0..index]) |prior| {
            try std.testing.expect(spec.id != prior.id);
            try std.testing.expect(!std.ascii.eqlIgnoreCase(spec.name, prior.name));
            try std.testing.expect(!std.mem.eql(u8, spec.normalized_name, prior.normalized_name));
        }
        switch (spec.kind) {
            .spin => |spin| try std.testing.expect(spin.min <= spin.default and spin.default <= spin.max),
            .check, .button, .string => {},
        }
    }
}
