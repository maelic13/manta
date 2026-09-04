const std = @import("std");
const builtin = @import("builtin");
const artifact = @import("build_support/artifact.zig");
const project_version = @import("build_support/version.zig");
const zig_version = @import("build_support/zig_version.zig");

pub fn build(b: *std.Build) void {
    zig_version.requireExact(builtin.zig_version_string);

    const native = b.option(bool, "native", "Optimize for this host (the default)") orelse false;
    const portable = b.option(bool, "portable", "Use the supported platform baseline") orelse false;
    const profile = b.option([]const u8, "profile", "Select a curated Manta build profile") orelse "auto";
    const pgo = b.option(bool, "pgo", "Use the measured PGO pipeline when available") orelse false;
    const contextual_space = b.option(
        bool,
        "contextual-space",
        "Enable the Step-5.4.3 MAN-E20 context-weighted-space candidate in this build",
    ) orelse false;
    const shelter_danger_coupling = b.option(
        bool,
        "shelter-danger-coupling",
        "Enable the Step-5.4.3 MAN-E21 shelter-moderated king-danger candidate in this build",
    ) orelse false;
    const correction_history = b.option(
        bool,
        "correction-history",
        "Enable the Step-5.4.1 MAN-S25 correction-history candidate in this build",
    ) orelse false;
    const tune = b.option(
        bool,
        "tune",
        "Expose Step-5.4.5 tune-only search parameters through UCI",
    ) orelse false;
    const root_confidence_time = b.option(
        bool,
        "root-confidence-time",
        "Enable the Step-6.0.2 confidence-driven soft-time candidate in this build",
    ) orelse false;
    const integrated_time = b.option(
        bool,
        "integrated-time",
        "Enable the accepted Step-6.3 integrated time-management policy",
    ) orelse true;
    const stability_aspiration = b.option(
        bool,
        "stability-aspiration",
        "Enable the Step-6.0.3 stability-gated aspiration candidate in this build",
    ) orelse false;
    if (b.option([]const u8, "target", "Cross-compilation is not supported") != null or
        b.option([]const u8, "cpu", "Use -Dprofile instead of raw CPU features") != null)
    {
        buildFatal("cross-target and raw CPU overrides are unsupported; build natively and use -Dprofile", .{});
    }
    if (root_confidence_time and integrated_time)
        buildFatal("the rejected MAN-R01 consumer and Step-6.3 integrated policy are mutually exclusive", .{});

    const mode: artifact.Mode = if (portable) .portable else .native;
    const target = b.resolveTargetQuery(if (mode == .native) .{ .cpu_model = .native } else .{});
    const configuration = artifact.resolve(.{
        .native = native,
        .portable = portable,
        .profile = profile,
        .pgo = pgo,
    }, target.result.cpu.arch) catch |err| buildConfigurationError(b, err, profile);
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Prioritize performance, safety, or binary size (default: ReleaseFast)",
    ) orelse .ReleaseFast;
    const version = b.option([]const u8, "version", "Set the Manta version") orelse project_version.current;
    _ = std.SemanticVersion.parse(version) catch
        buildFatal("Manta versions must use MAJOR.MINOR.PATCH semantic version syntax; found '{s}'", .{version});
    const artifact_name = artifact.artifactName(
        b.allocator,
        version,
        target.result.os.tag,
        configuration,
        optimize,
    ) catch |err| buildFatal("cannot name build artifact: {s}", .{@errorName(err)});
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version);
    build_options.addOption(bool, "transcript_hooks", false);
    const hce_build_options = b.addOptions();
    hce_build_options.addOption(bool, "contextual_space", contextual_space);
    hce_build_options.addOption(bool, "shelter_danger_coupling", shelter_danger_coupling);
    const hce_build_options_module = hce_build_options.createModule();
    const search_build_options = b.addOptions();
    search_build_options.addOption(bool, "correction_history", correction_history);
    search_build_options.addOption(bool, "tune", tune);
    search_build_options.addOption(bool, "root_confidence_time", root_confidence_time);
    search_build_options.addOption(bool, "integrated_time", integrated_time);
    search_build_options.addOption(bool, "stability_aspiration", stability_aspiration);
    const search_build_options_module = search_build_options.createModule();
    const omit_frame_pointer: ?bool = if (optimize == .ReleaseFast and
        target.result.cpu.arch == .x86_64) true else null;

    const manta = b.addModule("manta", .{
        .root_source_file = b.path("src/manta.zig"),
        .target = target,
        .optimize = optimize,
        .omit_frame_pointer = omit_frame_pointer,
        .imports = &.{
            .{ .name = "hce_build_options", .module = hce_build_options_module },
            .{ .name = "search_build_options", .module = search_build_options_module },
        },
    });

    attachFathom(b, manta);

    const executable = b.addExecutable(.{
        .name = "manta",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .omit_frame_pointer = omit_frame_pointer,
            .imports = &.{
                .{ .name = "manta", .module = manta },
                .{ .name = "build_options", .module = build_options.createModule() },
            },
        }),
    });
    b.installArtifact(executable);
    const install_dist = b.addInstallFile(
        executable.getEmittedBin(),
        b.fmt("dist/{s}", .{artifact_name}),
    );
    b.getInstallStep().dependOn(&install_dist.step);

    const dist_step = b.step("dist", "Build the canonically named Manta artifact");
    dist_step.dependOn(&install_dist.step);

    const run_command = b.addRunArtifact(executable);
    run_command.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_command.addArgs(args);

    const run_step = b.step("run", "Run Manta");
    run_step.dependOn(&run_command.step);

    // Syzygy tables are a large external asset kept out of the repository by
    // FILE-001, so the integration probes are opt-in. Without a path the tests
    // report skipped, which keeps CI and fresh clones green.
    const syzygy_path = b.option(
        []const u8,
        "syzygy-path",
        "Directory of Syzygy tablebase files; enables the opt-in probe tests",
    ) orelse "";
    const test_options = b.addOptions();
    test_options.addOption([]const u8, "syzygy_path", syzygy_path);

    const repository_tests = b.addTest(.{
        .name = "manta-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "manta", .module = manta },
                .{ .name = "test_options", .module = test_options.createModule() },
            },
        }),
    });
    const fuzz_tests = b.addTest(.{
        .name = "manta-chess-fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/chess_fuzz.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "manta", .module = manta },
            },
        }),
    });
    const run_fuzz_tests = b.addRunArtifact(fuzz_tests);

    const chess_tests = b.addTest(.{
        .name = "chess-domain-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/chess/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // Tests embedded in the library module are not collected when `manta` is
    // imported as a dependency by tests/root.zig. Give the source facade its
    // own test root so search/type/score invariants execute in every mode.
    const library_test_module = b.createModule(.{
        .root_source_file = b.path("src/manta.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "hce_build_options", .module = hce_build_options_module },
            .{ .name = "search_build_options", .module = search_build_options_module },
        },
    });
    // This root re-parses the library facade instead of importing the `manta`
    // module, so it needs the probe layer attached independently.
    attachFathom(b, library_test_module);
    const library_tests = b.addTest(.{
        .name = "manta-domain-tests",
        .root_module = library_test_module,
    });
    const run_library_tests = b.addRunArtifact(library_tests);

    const uci_tests = b.addTest(.{
        .name = "uci-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/uci/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "manta", .module = manta }},
        }),
    });
    const run_uci_tests = b.addRunArtifact(uci_tests);

    const transcript_tests = b.addTest(.{
        .name = "uci-transcript-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/uci/transcript.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_transcript_tests = b.addRunArtifact(transcript_tests);

    const uci_runner = b.addExecutable(.{
        .name = "manta-uci-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/uci_runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "build_options", .module = build_options.createModule() },
            },
        }),
    });
    const transcript_build_options = b.addOptions();
    transcript_build_options.addOption([]const u8, "version", version);
    transcript_build_options.addOption(bool, "transcript_hooks", true);
    const transcript_search_build_options = b.addOptions();
    transcript_search_build_options.addOption(bool, "correction_history", correction_history);
    transcript_search_build_options.addOption(bool, "tune", false);
    transcript_search_build_options.addOption(bool, "root_confidence_time", root_confidence_time);
    transcript_search_build_options.addOption(bool, "integrated_time", integrated_time);
    transcript_search_build_options.addOption(bool, "stability_aspiration", stability_aspiration);
    const transcript_manta = b.addModule("manta-transcript", .{
        .root_source_file = b.path("src/manta.zig"),
        .target = target,
        .optimize = optimize,
        .omit_frame_pointer = omit_frame_pointer,
        .imports = &.{
            .{ .name = "hce_build_options", .module = hce_build_options_module },
            .{ .name = "search_build_options", .module = transcript_search_build_options.createModule() },
        },
    });
    attachFathom(b, transcript_manta);
    const transcript_engine = b.addExecutable(.{
        .name = "manta-transcript-fixture",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "manta", .module = transcript_manta },
                .{ .name = "build_options", .module = transcript_build_options.createModule() },
            },
        }),
    });
    const run_uci_runner = b.addRunArtifact(uci_runner);
    run_uci_runner.addArtifactArg(transcript_engine);
    run_uci_runner.setCwd(b.path("."));

    const uci_test_step = b.step("test-uci", "Run focused UCI unit and process transcript tests");
    uci_test_step.dependOn(&run_uci_tests.step);
    uci_test_step.dependOn(&run_transcript_tests.step);
    uci_test_step.dependOn(&run_uci_runner.step);

    const version_tests = b.addTest(.{
        .name = "build-version-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build_support/zig_version.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_version_tests = b.addRunArtifact(version_tests);

    const artifact_tests = b.addTest(.{
        .name = "build-artifact-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build_support/artifact.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_artifact_tests = b.addRunArtifact(artifact_tests);

    const policy_checker = b.addExecutable(.{
        .name = "manta-policy-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/policy_check.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
    const run_policy_checker = b.addRunArtifact(policy_checker);
    run_policy_checker.setCwd(b.path("."));

    const policy_tests = b.addTest(.{
        .name = "policy-check-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/policy_check.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    const manta_host = b.createModule(.{
        .root_source_file = b.path("src/manta.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
        .imports = &.{
            .{ .name = "hce_build_options", .module = hce_build_options_module },
            .{ .name = "search_build_options", .module = search_build_options_module },
        },
    });
    const differential_perft = b.addExecutable(.{
        .name = "manta-differential-perft",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/differential_perft.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
            .imports = &.{.{ .name = "manta", .module = manta_host }},
        }),
    });
    const run_differential_perft = b.addRunArtifact(differential_perft);
    if (b.args) |args| run_differential_perft.addArgs(args);
    const differential_step = b.step(
        "differential-perft",
        "Compare deterministic Manta divide maps with an external UCI oracle",
    );
    differential_step.dependOn(&run_differential_perft.step);

    const differential_tests = b.addTest(.{
        .name = "differential-perft-tool-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/differential_perft.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{.{ .name = "manta", .module = manta_host }},
        }),
    });
    const board_bench = b.addExecutable(.{
        .name = "manta-board-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/board_bench.zig"),
            .target = target,
            .optimize = optimize,
            .omit_frame_pointer = omit_frame_pointer,
            .imports = &.{.{ .name = "manta", .module = manta }},
        }),
    });
    const run_board_bench = b.addRunArtifact(board_bench);
    if (b.args) |args| run_board_bench.addArgs(args);
    const board_bench_step = b.step(
        "board-bench",
        "Run the versioned board-operation benchmark",
    );
    board_bench_step.dependOn(&run_board_bench.step);

    const board_bench_tests = b.addTest(.{
        .name = "board-benchmark-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/board_bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "manta", .module = manta }},
        }),
    });
    const eval_bench = b.addExecutable(.{
        .name = "manta-hce-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/eval_bench.zig"),
            .target = target,
            .optimize = optimize,
            .omit_frame_pointer = omit_frame_pointer,
            .imports = &.{.{ .name = "manta", .module = manta }},
        }),
    });
    const run_eval_bench = b.addRunArtifact(eval_bench);
    if (b.args) |args| run_eval_bench.addArgs(args);
    const eval_bench_step = b.step(
        "eval-bench",
        "Run the versioned scalar HCE benchmark",
    );
    eval_bench_step.dependOn(&run_eval_bench.step);

    const eval_bench_tests = b.addTest(.{
        .name = "HCE-benchmark-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/eval_bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "manta", .module = manta }},
        }),
    });
    const search_observe = b.addExecutable(.{
        .name = "manta-search-observe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/search_observe.zig"),
            .target = target,
            .optimize = optimize,
            .omit_frame_pointer = omit_frame_pointer,
            .imports = &.{
                .{ .name = "manta", .module = manta },
                .{ .name = "search_build_options", .module = search_build_options_module },
            },
        }),
    });
    const run_search_observe = b.addRunArtifact(search_observe);
    const search_observe_step = b.step(
        "search-observe",
        "Run the versioned deterministic search-observation suite",
    );
    search_observe_step.dependOn(&run_search_observe.step);

    const search_observe_tests = b.addTest(.{
        .name = "search-observation-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/search_observe.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "manta", .module = manta },
                .{ .name = "search_build_options", .module = search_build_options_module },
            },
        }),
    });
    // Step-5.3.0 residual harness. Reference evaluations are frozen in the
    // cohort table rather than read at runtime, so the report stays
    // deterministic and reviewable without an external binary.
    const eval_residual = b.addExecutable(.{
        .name = "manta-eval-residual",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/eval_residual.zig"),
            .target = target,
            .optimize = optimize,
            .omit_frame_pointer = omit_frame_pointer,
            .imports = &.{
                .{ .name = "manta", .module = manta },
            },
        }),
    });
    const run_eval_residual = b.addRunArtifact(eval_residual);
    const eval_residual_step = b.step(
        "eval-residual",
        "Run the versioned deterministic evaluation residual harness",
    );
    eval_residual_step.dependOn(&run_eval_residual.step);

    const eval_residual_tests = b.addTest(.{
        .name = "evaluation-residual-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/eval_residual.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "manta", .module = manta },
            },
        }),
    });
    const hce_fit_options = b.addOptions();
    hce_fit_options.addOption([]const u8, "parameter_source", @embedFile("src/eval/hce_params.zig"));
    const hce_fit = b.addExecutable(.{
        .name = "manta-hce-fit",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/hce_fit.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "manta", .module = manta },
                .{ .name = "hce_fit_options", .module = hce_fit_options.createModule() },
            },
        }),
    });
    const run_hce_fit = b.addRunArtifact(hce_fit);
    if (b.args) |args| run_hce_fit.addArgs(args);
    const hce_fit_step = b.step("hce-fit-schema", "Verify and report the versioned HCE fitting schema");
    hce_fit_step.dependOn(&run_hce_fit.step);

    const hce_fit_tests = b.addTest(.{
        .name = "hce-fitting-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/hce_fit.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "manta", .module = manta },
                .{ .name = "hce_fit_options", .module = hce_fit_options.createModule() },
            },
        }),
    });
    const run_hce_fit_tests = b.addRunArtifact(hce_fit_tests);
    const hce_fit_test_step = b.step("hce-fit-test", "Run HCE fitting schema and feature conformance tests");
    hce_fit_test_step.dependOn(&run_hce_fit_tests.step);

    // Short edit-loop gate: executable unit/domain contracts and repository
    // policy, without the long qualification, fuzz, subprocess-transcript or
    // historical-tool suites owned by `test`.
    const test_fast_step = b.step("test-fast", "Run the fast developer test subset");
    test_fast_step.dependOn(&run_library_tests.step);
    test_fast_step.dependOn(&run_uci_tests.step);
    test_fast_step.dependOn(&run_version_tests.step);
    test_fast_step.dependOn(&run_artifact_tests.step);
    test_fast_step.dependOn(&run_policy_checker.step);

    const check_step = b.step("check", "Compile Manta and all test roots");
    check_step.dependOn(&executable.step);
    check_step.dependOn(&repository_tests.step);
    check_step.dependOn(&fuzz_tests.step);
    check_step.dependOn(&chess_tests.step);
    check_step.dependOn(&library_tests.step);
    check_step.dependOn(&uci_tests.step);
    check_step.dependOn(&transcript_tests.step);
    check_step.dependOn(&uci_runner.step);
    check_step.dependOn(&version_tests.step);
    check_step.dependOn(&artifact_tests.step);
    check_step.dependOn(&policy_checker.step);
    check_step.dependOn(&policy_tests.step);
    check_step.dependOn(&differential_perft.step);
    check_step.dependOn(&differential_tests.step);
    check_step.dependOn(&board_bench.step);
    check_step.dependOn(&board_bench_tests.step);
    check_step.dependOn(&eval_bench.step);
    check_step.dependOn(&eval_bench_tests.step);
    check_step.dependOn(&search_observe.step);
    check_step.dependOn(&search_observe_tests.step);
    check_step.dependOn(&eval_residual.step);
    check_step.dependOn(&eval_residual_tests.step);
    check_step.dependOn(&hce_fit.step);
    check_step.dependOn(&hce_fit_tests.step);
    check_step.dependOn(&transcript_engine.step);

    // Zig's test-runner protocol expects every child to respond within roughly
    // one minute. Launching all CPU-heavy qualification roots concurrently can
    // starve a healthy child past that bound. Compile through `check` in
    // parallel, then run the full-gate artifacts one at a time. Focused steps
    // keep their independent run artifacts and remain parallel-capable.
    const serial_test_artifacts = [_]*std.Build.Step.Compile{
        repository_tests,
        fuzz_tests,
        chess_tests,
        library_tests,
        uci_tests,
        transcript_tests,
        version_tests,
        artifact_tests,
        policy_tests,
        differential_tests,
        board_bench_tests,
        eval_bench_tests,
        search_observe_tests,
        eval_residual_tests,
        hce_fit_tests,
    };
    var prior_test_step: *std.Build.Step = check_step;
    for (serial_test_artifacts) |test_artifact| {
        const run_serial_test = b.addRunArtifact(test_artifact);
        run_serial_test.step.dependOn(prior_test_step);
        prior_test_step = &run_serial_test.step;
    }
    const run_serial_uci = b.addRunArtifact(uci_runner);
    run_serial_uci.addArtifactArg(transcript_engine);
    run_serial_uci.setCwd(b.path("."));
    run_serial_uci.step.dependOn(prior_test_step);

    const test_step = b.step("test", "Compile in parallel, then run all tests serially");
    test_step.dependOn(&run_serial_uci.step);

    const fuzz_step = b.step(
        "fuzz",
        "Run native chess fuzz entry points (use --fuzz=<iterations>)",
    );
    fuzz_step.dependOn(&run_fuzz_tests.step);

    const fmt_command = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "fmt",
        "--check",
        "--ast-check",
        "--exclude",
        "zig-pkg",
        "--exclude",
        "tools/zlint/zig-pkg",
        ".",
    });
    fmt_command.setCwd(b.path("."));
    const fmt_step = b.step("fmt", "Check formatting and parse all Zig sources");
    fmt_step.dependOn(&fmt_command.step);

    const policy_step = b.step("policy", "Check repository documentation and policies");
    policy_step.dependOn(&run_policy_checker.step);

    const lint_step = b.step("lint", "Run formatting, policy and Zig lint checks");
    lint_step.dependOn(fmt_step);
    lint_step.dependOn(policy_step);
    const run_zlint = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build",
        "--build-file",
        "tools/zlint/build.zig",
        "run",
    });
    run_zlint.setCwd(b.path("."));
    lint_step.dependOn(&run_zlint.step);

    const magic_module = b.createModule(.{
        .root_source_file = b.path("src/chess/generated/magics.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });
    const attack_generator = b.addExecutable(.{
        .name = "manta-generate-attacks",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/generate_attack_tables.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
            .imports = &.{.{ .name = "magics", .module = magic_module }},
        }),
    });
    const run_attack_generator = b.addRunArtifact(attack_generator);
    run_attack_generator.setCwd(b.path("."));
    const generate_attacks_step = b.step(
        "generate-attacks",
        "Regenerate checked embedded sliding-attack tables",
    );
    generate_attacks_step.dependOn(&run_attack_generator.step);

    const kpk_generator = b.addExecutable(.{
        .name = "manta-generate-kpk",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/generate_kpk.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });
    const run_kpk_generator = b.addRunArtifact(kpk_generator);
    run_kpk_generator.setCwd(b.path("."));
    const generate_kpk_step = b.step(
        "generate-kpk",
        "Regenerate the checked exact KPK win/draw bitbase",
    );
    generate_kpk_step.dependOn(&run_kpk_generator.step);
}

fn buildConfigurationError(_: *std.Build, err: artifact.ResolveError, profile: []const u8) noreturn {
    switch (err) {
        error.ConflictingModes => buildFatal("-Dnative and -Dportable cannot be combined", .{}),
        error.UnknownProfile => buildFatal(
            "unknown profile '{s}'; use auto, x86-64, arm64, avx2, pext or avx512",
            .{profile},
        ),
        error.UnsupportedArchitecture => buildFatal("Manta currently supports only x86-64 and ARM64", .{}),
        error.ProfileTargetMismatch => buildFatal("profile '{s}' does not match this host architecture", .{profile}),
        error.ProfileNotAvailable => buildFatal(
            "profile '{s}' is reserved but not implemented; optimized ISA profiles arrive in Phase 10",
            .{profile},
        ),
        error.PgoNotAvailable => buildFatal(
            "-Dpgo is not available until Manta has the representative Phase 4.3 bench and measured PGO pipeline",
            .{},
        ),
    }
}

fn buildFatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    std.process.exit(1);
}

/// Attaches the vendored Fathom Syzygy probe layer to one module.
///
/// Fathom (MIT) supplies only the probe and file-format layer; its exact
/// upstream revision and per-file SHA-256 values are pinned in
/// `config/fathom-vendor.json` and never move silently. The typed WDL/DTZ
/// contract, score conversion, rule-50 policy, root filtering and interior
/// search policy remain original Manta Zig.
///
/// This is the single authorized third-party source exception, and therefore
/// the only reason Manta links libc. A libc-free Linux artifact is no longer
/// a packaging candidate.
///
/// Upstream compiles exactly one translation unit: `tbprobe.c` textually
/// includes `tbchess.c`, so listing the latter here would compile it a second
/// time standalone and fail on its missing prelude.
fn attachFathom(b: *std.Build, module: *std.Build.Module) void {
    module.link_libc = true;
    module.addIncludePath(b.path("third_party/fathom"));
    module.addCSourceFiles(.{
        .root = b.path("third_party/fathom"),
        .files = &.{"tbprobe.c"},
        .flags = &.{"-std=c11"},
    });
}
