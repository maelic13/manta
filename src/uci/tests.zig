//! UCI adapter unit-test root with the inward facade supplied by the build.
const protocol = @import("protocol.zig");
const session = @import("session.zig");

test {
    _ = protocol;
    _ = session;
}
