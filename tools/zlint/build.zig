const std = @import("std");

pub fn build(b: *std.Build) void {
    const zlint = b.dependency("zlint", .{
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    const run_zlint = b.addRunArtifact(dependencyExecutable(zlint, "zlint"));
    run_zlint.setCwd(b.path("../.."));
    run_zlint.addArg("--stdin");
    run_zlint.setStdIn(.{ .bytes =
        \\build.zig
        \\build_support/zig_version.zig
        \\src/main.zig
        \\src/manta.zig
        \\tests/root.zig
        \\tools/policy_check.zig
        \\tools/zlint/build.zig
        \\
    });

    const run_step = b.step("run", "Run ZLint against the repository");
    run_step.dependOn(&run_zlint.step);
}

fn dependencyExecutable(
    dependency: *std.Build.Dependency,
    name: []const u8,
) *std.Build.Step.Compile {
    for (dependency.builder.install_tls.step.dependencies.items) |step| {
        const install = step.cast(std.Build.Step.InstallArtifact) orelse continue;
        const artifact = install.artifact;
        if (artifact.kind == .exe and std.mem.eql(u8, artifact.name, name)) {
            return artifact;
        }
    }
    std.debug.panic("dependency does not expose executable '{s}'", .{name});
}
