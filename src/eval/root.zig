//! Evaluator-facing score, phase, update, and diagnostic composition boundary.
pub const cohorts = @import("cohorts.zig");
pub const contract = @import("contract.zig");
pub const endgame = @import("endgame.zig");
pub const fit = @import("fit.zig");
pub const hce = @import("hce.zig");
pub const phase = @import("phase.zig");
pub const trace = @import("trace.zig");
pub const winnability = @import("winnability.zig");

test {
    _ = cohorts;
    _ = contract;
    _ = endgame;
    _ = fit;
    _ = hce;
    _ = phase;
    _ = trace;
    _ = winnability;
}
