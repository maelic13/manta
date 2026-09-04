//! Deterministic search policy facade.
pub const baseline = @import("baseline.zig");
pub const diagnostics = @import("diagnostics.zig");
pub const observation = @import("observation.zig");
pub const ordering = @import("ordering.zig");
pub const params = @import("params.zig");
pub const tablebase = @import("tablebase.zig");
pub const tt = @import("tt.zig");
pub const types = @import("types.zig");

test {
    _ = baseline;
    _ = diagnostics;
    _ = observation;
    _ = ordering;
    _ = params;
    _ = tablebase;
    _ = tt;
    _ = types;
}
