const std = @import("std");
const builtin = @import("builtin");
const zig_version = @import("build_support/zig_version.zig");

pub fn build(b: *std.Build) void {
    zig_version.requireExact(builtin.zig_version_string);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const manta = b.addModule("manta", .{
        .root_source_file = b.path("src/manta.zig"),
        .target = target,
        .optimize = optimize,
    });

    const executable = b.addExecutable(.{
        .name = "manta",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "manta", .module = manta },
            },
        }),
    });
    b.installArtifact(executable);

    const run_command = b.addRunArtifact(executable);
    run_command.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_command.addArgs(args);

    const run_step = b.step("run", "Run Manta");
    run_step.dependOn(&run_command.step);

    const repository_tests = b.addTest(.{
        .name = "manta-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "manta", .module = manta },
            },
        }),
    });
    const run_repository_tests = b.addRunArtifact(repository_tests);

    const version_tests = b.addTest(.{
        .name = "build-version-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build_support/zig_version.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_version_tests = b.addRunArtifact(version_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_repository_tests.step);
    test_step.dependOn(&run_version_tests.step);

    const check_step = b.step("check", "Compile Manta and all test roots");
    check_step.dependOn(&executable.step);
    check_step.dependOn(&repository_tests.step);
    check_step.dependOn(&version_tests.step);
}
