//! Engine policy facade independent of text adapters.
pub const bench = @import("bench.zig");
pub const options = @import("options.zig");
pub const runtime = @import("runtime.zig");
pub const syzygy = @import("syzygy.zig");
pub const time = @import("time.zig");

test {
    _ = bench;
    _ = runtime;
    _ = syzygy;
    _ = time;
}
