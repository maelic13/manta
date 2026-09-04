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
        \\build_support/artifact.zig
        \\build_support/zig_version.zig
        \\src/main.zig
        \\src/manta.zig
        \\src/score.zig
        \\src/engine/root.zig
        \\src/engine/runtime.zig
        \\src/engine/time.zig
        \\src/search/baseline.zig
        \\src/search/diagnostics.zig
        \\src/search/ordering.zig
        \\src/search/root.zig
        \\src/search/tt.zig
        \\src/search/types.zig
        \\src/uci/session.zig
        \\src/uci/protocol.zig
        \\src/uci/tests.zig
        \\src/chess/attacks.zig
        \\src/chess/fen.zig
        \\src/chess/generated/magics.zig
        \\src/chess/move.zig
        \\src/chess/movegen.zig
        \\src/chess/notation.zig
        \\src/chess/position.zig
        \\src/chess/queries.zig
        \\src/chess/root.zig
        \\src/chess/state.zig
        \\src/chess/transition.zig
        \\src/chess/types.zig
        \\src/chess/zobrist.zig
        \\src/eval/contract.zig
        \\src/eval/cohorts.zig
        \\src/eval/endgame.zig
        \\src/eval/fit.zig
        \\src/eval/hce.zig
        \\src/eval/hce_params.zig
        \\src/eval/phase.zig
        \\src/eval/root.zig
        \\src/eval/trace.zig
        \\src/eval/winnability.zig
        \\tests/root.zig
        \\tests/eval_reference.zig
        \\tests/eval_invariants.zig
        \\tests/search_baseline.zig
        \\tests/search_substrate.zig
        \\tests/support/seeds.zig
        \\tools/generate_attack_tables.zig
        \\tools/eval_bench.zig
        \\tools/hce_fit.zig
        \\tools/generate_magics.zig
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
