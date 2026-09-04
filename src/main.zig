//! Process composition root for the bounded UCI shell.
const std = @import("std");
const build_options = @import("build_options");
const session = @import("uci/session.zig");

pub fn main(init: std.process.Init) !u8 {
    return session.run(init.gpa, init.io, build_options.version, build_options.transcript_hooks);
}
