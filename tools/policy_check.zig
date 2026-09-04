const std = @import("std");

const max_file_size = 2 * 1024 * 1024;
// Includes the Markdown header row plus every stable requirement-ID row.
const expected_requirement_count = 112;

const required_paths = [_][]const u8{
    ".github/workflows/ci.yml",
    ".github/workflows/release.yml",
    ".github/actions/setup-zig/action.yml",
    "AGENTS.md",
    "ARCHITECTURE.md",
    "CHANGELOG.md",
    "EXPERIMENTS.md",
    "GUIDE.md",
    "LICENSE",
    "PLAN.md",
    "README.md",
    "REQUIREMENTS.md",
    "build.zig",
    "build.zig.zon",
    "build_support/artifact.zig",
    "build_support/version.zig",
    "build_support/zig_version.zig",
    "docs/DEVELOPMENT.md",
    "docs/RELEASING.md",
    "docs/UCI.md",
    "docs/adr/0013-board-representation.md",
    "src/main.zig",
    "src/manta.zig",
    "src/chess/attacks.zig",
    "src/chess/fen.zig",
    "src/chess/generated/bishop_attacks.bin",
    "src/chess/generated/magics.zig",
    "src/chess/generated/rook_attacks.bin",
    "src/chess/move.zig",
    "src/chess/movegen.zig",
    "src/chess/notation.zig",
    "src/chess/position.zig",
    "src/chess/queries.zig",
    "src/chess/root.zig",
    "src/chess/state.zig",
    "src/chess/transition.zig",
    "src/chess/types.zig",
    "src/chess/zobrist.zig",
    "src/uci/protocol.zig",
    "src/uci/session.zig",
    "tests/root.zig",
    "tests/support/seeds.zig",
    "tests/uci/transcript.zig",
    "tests/uci_runner.zig",
    "tests/uci/README.md",
    "tests/uci/01-startup-handshake.transcript",
    "tests/uci/02-unknown-debug.transcript",
    "tests/uci/03-readiness-barriers.transcript",
    "tests/uci/04-options.transcript",
    "tests/uci/05-position-transaction.transcript",
    "tests/uci/06-search-lifecycle.transcript",
    "tests/uci/07-ponder-lifecycle.transcript",
    "tests/uci/08-perft.transcript",
    "tests/uci/09-terminal-position.transcript",
    "tests/uci/10-shutdown.transcript",
    "tests/uci/11-bench.transcript",
    "tests/uci/12-output-backpressure.transcript",
    "tests/uci/13-smp.transcript",
    "tests/uci/14-time-management.transcript",
    "tools/policy_check.zig",
    "tools/generate_attack_tables.zig",
    "tools/generate_magics.zig",
    "tools/ci/install-zig.ps1",
    "tools/ci/install-zig.sh",
    "tools/ci/release_smoke.py",
    "tools/datagen.ps1",
    "tools/texel/score.py",
    "tools/zlint/build.zig",
    "tools/zlint/build.zig.zon",
    "zlint.json",
};

const allowed_reference_files = [_][]const u8{
    "README.md",
    "AGENTS.md",
    "PLAN.md",
    "GUIDE.md",
    "EXPERIMENTS.md",
    "docs/HCE_COVERAGE.md",
    "docs/SEARCH_COVERAGE.md",
    "docs/HCE_DATAGEN.md",
    "docs/adr/0056-hce-selfplay-data-and-fit.md",
    "docs/adr/0050-primary-reference-switch-and-phase-5-3-resequence.md",
    "config/phase-5.1.1-reference.json",
    "config/eval-reference.json",
    "docs/adr/0020-uci-search-and-clock-baseline.md",
    "docs/adr/0023-late-move-reduction-candidate.md",
    "docs/adr/0024-search-reference-observation.md",
    "docs/adr/0033-lmr-reply-feedback-candidate.md",
    "docs/adr/0034-pre-nnue-classical-convergence.md",
    "docs/adr/0036-dynamic-base-lmr-candidate.md",
    "docs/adr/0037-capture-history-candidate.md",
    "docs/adr/0040-static-eval-tt-qsearch-candidate.md",
    "docs/adr/0041-main-selectivity-candidate.md",
    "docs/adr/0042-extension-depth-authority-candidate.md",
    "docs/FASTCHESS_BRIDGE.md",
    "docs/SEARCH_REFERENCE.md",
    "tools/build_test.ps1",
    "tools/datagen.ps1",
    "tools/harness_common.ps1",
    "tools/setup_tools.ps1",
    "tools/sprt.ps1",
    "tools/spsa.ps1",
    "tools/spsa_configs/README.md",
    "tools/step_5_1_fastchess.ps1",
    "tools/watch.ps1",
};

const restricted_names = [_][]const u8{
    "stock" ++ "fish",
    "basi" ++ "lisk",
    "ra" ++ "rog",
};

const Checker = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
    failures: usize = 0,

    fn fail(self: *Checker, comptime format: []const u8, args: anytype) void {
        self.failures += 1;
        std.debug.print("policy: " ++ format ++ "\n", args);
    }

    fn read(self: *Checker, path: []const u8) ![]u8 {
        return self.root.readFileAlloc(
            self.io,
            path,
            self.allocator,
            .limited(max_file_size),
        );
    }

    fn checkRequiredPaths(self: *Checker) void {
        for (required_paths) |path| {
            self.root.access(self.io, path, .{}) catch {
                self.fail("required path is missing: {s}", .{path});
            };
        }
    }

    fn checkPlanGuideSync(self: *Checker) !void {
        const plan = try self.read("PLAN.md");
        defer self.allocator.free(plan);
        const guide = try self.read("GUIDE.md");
        defer self.allocator.free(guide);

        var plan_units = std.StringHashMap(void).init(self.allocator);
        defer plan_units.deinit();
        var guide_units = std.StringHashMap(void).init(self.allocator);
        defer guide_units.deinit();

        try collectNumberedUnits(plan, .plan, &plan_units);
        try collectNumberedUnits(guide, .guide, &guide_units);

        var plan_iterator = plan_units.keyIterator();
        while (plan_iterator.next()) |unit| {
            if (!guide_units.contains(unit.*)) {
                self.fail("GUIDE.md is missing numbered PLAN.md unit {s}", .{unit.*});
            }
        }

        var guide_iterator = guide_units.keyIterator();
        while (guide_iterator.next()) |unit| {
            if (!plan_units.contains(unit.*)) {
                self.fail("GUIDE.md contains unknown numbered unit {s}", .{unit.*});
            }
        }
    }

    fn checkRequirements(self: *Checker) !void {
        const requirements = try self.read("REQUIREMENTS.md");
        defer self.allocator.free(requirements);

        var ids = std.StringHashMap(void).init(self.allocator);
        defer ids.deinit();
        var count: usize = 0;
        var lines = std.mem.splitScalar(u8, requirements, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trimEnd(u8, raw_line, "\r");
            const id = requirementId(line) orelse continue;
            count += 1;
            if (!isRequirementId(id)) {
                self.fail("invalid requirement ID: {s}", .{id});
                continue;
            }
            const result = try ids.getOrPut(id);
            if (result.found_existing) {
                self.fail("duplicate requirement ID: {s}", .{id});
            }
        }

        if (count != expected_requirement_count) {
            self.fail(
                "REQUIREMENTS.md has {d} requirement rows; expected {d}",
                .{ count, expected_requirement_count },
            );
        }
    }

    fn checkCiWorkflow(self: *Checker) !void {
        const workflow = try self.read(".github/workflows/ci.yml");
        defer self.allocator.free(workflow);

        const required_fragments = [_][]const u8{
            "name: CI",
            "pull_request:",
            "push:",
            "workflow_dispatch:",
            "contents: read",
            "persist-credentials: false",
            "actions/checkout@v7",
            "uses: ./.github/actions/setup-zig",
            "timeout-minutes: 6",
            "cancel-in-progress: ${{ github.ref != 'refs/heads/master' }}",
            "zig build lint",
            "zig build test -Doptimize=Debug",
            "zig build test -Doptimize=ReleaseSafe",
            "zig build test -Doptimize=ReleaseFast",
            "zig build dist -Dportable",
            "ubuntu-24.04-arm",
            "macos-26-intel",
            "macos-26",
            "label: linux-x86-64",
            "label: linux-arm64",
            "label: windows-x86-64",
            "label: macos-x86-64",
            "label: macos-arm64",
            "name: gate",
            "if: ${{ always() }}",
            "needs: [quality, native]",
        };
        for (required_fragments) |fragment| {
            if (std.mem.indexOf(u8, workflow, fragment) == null) {
                self.fail("CI workflow is missing required contract: {s}", .{fragment});
            }
        }

        if (std.mem.count(u8, workflow, "branches: [master]") != 2) {
            self.fail("CI workflow must gate both pull requests and pushes to master", .{});
        }
        if (std.mem.count(u8, workflow, "timeout-minutes: 6") != 2) {
            self.fail("every Zig setup step must have the six-minute bound", .{});
        }

        const forbidden_fragments = [_][]const u8{
            "pull_request_target:",
            "continue-on-error:",
            "actions/upload-artifact",
            "mlugg/setup-zig",
            "\n  cross-build:",
            "-Dtarget=",
            "\n  release:",
        };
        for (forbidden_fragments) |fragment| {
            if (std.mem.indexOf(u8, workflow, fragment) != null) {
                self.fail("CI workflow contains forbidden contract: {s}", .{fragment});
            }
        }

        const build_file = try self.read("build.zig");
        defer self.allocator.free(build_file);
        const build_contracts = [_][]const u8{
            "-Dnative and -Dportable cannot be combined",
            "-Dpgo is not available until Manta has the representative Phase 4.3 bench",
            "cross-target and raw CPU overrides are unsupported",
            "dist/{s}",
            "orelse .ReleaseFast",
            "chess-domain-tests",
            "generate-attacks",
        };
        for (build_contracts) |contract| {
            if (std.mem.indexOf(u8, build_file, contract) == null) {
                self.fail("build file is missing required artifact contract: {s}", .{contract});
            }
        }

        const setup_action = try self.read(".github/actions/setup-zig/action.yml");
        defer self.allocator.free(setup_action);
        const setup_contracts = [_][]const u8{
            "actions/cache@v5",
            "using: composite",
            "zig-0.16.0-${{ runner.os }}-${{ runner.arch }}",
            "tools/ci/install-zig.ps1",
            "tools/ci/install-zig.sh",
            "bash \"${{ github.workspace }}/tools/ci/install-zig.sh\"",
        };
        for (setup_contracts) |contract| {
            if (std.mem.indexOf(u8, setup_action, contract) == null) {
                self.fail("Zig setup action is missing required contract: {s}", .{contract});
            }
        }

        const windows_installer = try self.read("tools/ci/install-zig.ps1");
        defer self.allocator.free(windows_installer);
        const unix_installer = try self.read("tools/ci/install-zig.sh");
        defer self.allocator.free(unix_installer);
        const installer_contracts = [_]struct {
            content: []const u8,
            fragment: []const u8,
        }{
            .{ .content = windows_installer, .fragment = "https://ziglang.org/download/$version/" },
            .{ .content = windows_installer, .fragment = "68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e" },
            .{ .content = unix_installer, .fragment = "https://ziglang.org/download/$version/" },
            .{ .content = unix_installer, .fragment = "70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00" },
            .{ .content = unix_installer, .fragment = "ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17" },
            .{ .content = unix_installer, .fragment = "0387557ed1877bc6a2e1802c8391953baddba76081876301c522f52977b52ba7" },
            .{ .content = unix_installer, .fragment = "b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489" },
        };
        for (installer_contracts) |contract| {
            if (std.mem.indexOf(u8, contract.content, contract.fragment) == null) {
                self.fail("Zig installer is missing required contract: {s}", .{contract.fragment});
            }
        }
    }

    fn checkRepositoryFiles(self: *Checker) !void {
        var walker = try self.root.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next(self.io)) |entry| {
            if (entry.kind == .directory and shouldSkipDirectory(entry.path)) {
                walker.leave(self.io);
                continue;
            }
            if (entry.kind != .file or !isPolicyTextFile(entry.path)) continue;

            const content = self.read(entry.path) catch |err| {
                self.fail("cannot read {s}: {s}", .{ entry.path, @errorName(err) });
                continue;
            };
            defer self.allocator.free(content);

            self.checkReferenceNames(entry.path, content);
            self.checkArchitectureImports(entry.path, content);
            if (std.mem.endsWith(u8, entry.path, ".md")) {
                try self.checkMarkdownLinks(entry.path, content);
            }
        }
    }

    fn checkReferenceNames(self: *Checker, path: []const u8, content: []const u8) void {
        if (isAllowedReferenceFile(path)) return;
        for (restricted_names) |name| {
            if (std.ascii.indexOfIgnoreCase(content, name) != null) {
                self.fail("restricted outside-engine reference in {s}", .{path});
            }
        }
    }

    fn checkMarkdownLinks(self: *Checker, source_path: []const u8, content: []const u8) !void {
        var cursor: usize = 0;
        while (std.mem.indexOfPos(u8, content, cursor, "](")) |open| {
            const target_start = open + 2;
            const close = std.mem.indexOfPos(u8, content, target_start, ")") orelse break;
            cursor = close + 1;

            var target = std.mem.trim(u8, content[target_start..close], " \t");
            if (target.len >= 2 and target[0] == '<' and target[target.len - 1] == '>') {
                target = target[1 .. target.len - 1];
            }
            if (target.len == 0 or isExternalLink(target)) continue;

            const hash = std.mem.indexOfScalar(u8, target, '#');
            const relative_path = if (hash) |index| target[0..index] else target;
            const anchor = if (hash) |index| target[index + 1 ..] else "";
            const source_directory = std.fs.path.dirname(source_path) orelse ".";
            const resolved = if (relative_path.len == 0)
                try self.allocator.dupe(u8, source_path)
            else
                try std.fs.path.join(self.allocator, &.{ source_directory, relative_path });
            defer self.allocator.free(resolved);

            self.root.access(self.io, resolved, .{}) catch {
                self.fail("broken relative link in {s}: {s}", .{ source_path, target });
                continue;
            };

            if (anchor.len != 0 and std.mem.endsWith(u8, resolved, ".md")) {
                const target_content = if (std.mem.eql(u8, resolved, source_path))
                    content
                else
                    try self.read(resolved);
                defer if (target_content.ptr != content.ptr) self.allocator.free(target_content);
                if (!hasHeadingAnchor(target_content, anchor)) {
                    self.fail("broken heading anchor in {s}: {s}", .{ source_path, target });
                }
            }
        }
    }

    fn checkArchitectureImports(self: *Checker, path: []const u8, content: []const u8) void {
        const is_inward = hasPathPrefix(path, "src/chess/") or
            hasPathPrefix(path, "src/engine/") or
            hasPathPrefix(path, "src/eval/") or
            hasPathPrefix(path, "src/search/");
        if (is_inward) {
            const forbidden = [_][]const u8{
                "@import(\"../uci/",
                "std.Io.File",
                ".stdout()",
                ".stderr()",
            };
            for (forbidden) |fragment| {
                if (std.mem.indexOf(u8, content, fragment) != null) {
                    self.fail("inward layer imports an outer adapter in {s}: {s}", .{ path, fragment });
                }
            }
        }

        if (hasPathPrefix(path, "src/uci/")) {
            const forbidden = [_][]const u8{
                "@import(\"../chess/",
                "@import(\"../eval/",
                "@import(\"../search/",
            };
            for (forbidden) |fragment| {
                if (std.mem.indexOf(u8, content, fragment) != null) {
                    self.fail("UCI adapter bypasses the engine boundary in {s}: {s}", .{ path, fragment });
                }
            }
        }

        if (pathEquals(path, "src/manta.zig") and std.mem.indexOf(u8, content, "uci/") != null) {
            self.fail("non-UCI library facade imports the UCI adapter", .{});
        }
    }
};

const UnitSource = enum { plan, guide };

fn collectNumberedUnits(
    content: []const u8,
    source: UnitSource,
    units: *std.StringHashMap(void),
) !void {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const id = numberedUnit(line, source) orelse continue;
        if (!isNumberedUnit(id)) continue;
        try units.put(id, {});
    }
}

fn numberedUnit(line: []const u8, source: UnitSource) ?[]const u8 {
    const start = switch (source) {
        .plan => blk: {
            if (!std.mem.startsWith(u8, line, "#### ") and
                !std.mem.startsWith(u8, line, "##### ")) return null;
            break :blk std.mem.indexOfScalar(u8, line, ' ').? + 1;
        },
        .guide => blk: {
            const marker = std.mem.indexOf(u8, line, "**") orelse return null;
            break :blk marker + 2;
        },
    };
    const end = std.mem.indexOfScalarPos(u8, line, start, ' ') orelse return null;
    return line[start..end];
}

fn isNumberedUnit(id: []const u8) bool {
    var parts = std.mem.splitScalar(u8, id, '.');
    var count: usize = 0;
    while (parts.next()) |part| {
        if (part.len == 0) return false;
        for (part) |character| if (!std.ascii.isDigit(character)) return false;
        count += 1;
    }
    return count == 2 or count == 3;
}

fn requirementId(line: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, "| `")) return null;
    const end = std.mem.indexOfPos(u8, line, 3, "`") orelse return null;
    const id = line[3..end];
    if (std.mem.lastIndexOfScalar(u8, id, '-') == null) return null;
    return id;
}

fn isRequirementId(id: []const u8) bool {
    const dash = std.mem.lastIndexOfScalar(u8, id, '-') orelse return false;
    if (dash == 0 or id.len - dash - 1 != 3) return false;
    for (id[0..dash]) |character| if (!std.ascii.isUpper(character)) return false;
    for (id[dash + 1 ..]) |character| if (!std.ascii.isDigit(character)) return false;
    return true;
}

fn shouldSkipDirectory(path: []const u8) bool {
    const basename = std.fs.path.basename(path);
    if (std.mem.eql(u8, basename, ".git") or
        std.mem.eql(u8, basename, ".venv") or
        std.mem.eql(u8, basename, ".zig-cache") or
        std.mem.eql(u8, basename, "__pycache__") or
        std.mem.eql(u8, basename, "venv") or
        std.mem.eql(u8, basename, "zig-out") or
        std.mem.eql(u8, basename, "zig-pkg")) return true;

    const generated_roots = [_][]const u8{
        "artifacts",
        "books",
        "datasets",
        "networks",
        "tablebases",
        "tools/bin",
        "tools/results",
        "tools/test_engines",
        "tools/texel/data",
        "tools/texel/out",
        "tools/weather-factory",
    };
    for (generated_roots) |generated_root| {
        if (pathEquals(path, generated_root)) return true;
    }
    return false;
}

fn isPolicyTextFile(path: []const u8) bool {
    const extensions = [_][]const u8{
        ".json",       ".md",   ".ps1", ".sh",  ".toml",
        ".transcript", ".yaml", ".yml", ".zig", ".zon",
    };
    for (extensions) |extension| {
        if (std.mem.endsWith(u8, path, extension)) return true;
    }
    return false;
}

fn isAllowedReferenceFile(path: []const u8) bool {
    for (allowed_reference_files) |allowed| {
        if (pathEquals(path, allowed)) return true;
    }
    return false;
}

fn hasPathPrefix(path: []const u8, forward_prefix: []const u8) bool {
    if (std.mem.startsWith(u8, path, forward_prefix)) return true;
    var buffer: [128]u8 = undefined;
    if (forward_prefix.len > buffer.len) return false;
    @memcpy(buffer[0..forward_prefix.len], forward_prefix);
    for (buffer[0..forward_prefix.len]) |*byte| {
        if (byte.* == '/') byte.* = '\\';
    }
    return std.mem.startsWith(u8, path, buffer[0..forward_prefix.len]);
}

fn pathEquals(path: []const u8, forward_path: []const u8) bool {
    return path.len == forward_path.len and hasPathPrefix(path, forward_path);
}

fn isExternalLink(target: []const u8) bool {
    return std.mem.startsWith(u8, target, "https://") or
        std.mem.startsWith(u8, target, "http://") or
        std.mem.startsWith(u8, target, "mailto:");
}

fn hasHeadingAnchor(content: []const u8, wanted: []const u8) bool {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len < 2 or line[0] != '#') continue;
        const heading_start = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
        var buffer: [512]u8 = undefined;
        const anchor = headingAnchor(line[heading_start + 1 ..], &buffer) orelse continue;
        if (std.mem.eql(u8, anchor, wanted)) return true;
    }
    return false;
}

fn headingAnchor(heading: []const u8, buffer: []u8) ?[]const u8 {
    var length: usize = 0;
    for (std.mem.trim(u8, heading, " \t\r#")) |character| {
        const output = if (std.ascii.isAlphanumeric(character))
            std.ascii.toLower(character)
        else if (character == ' ' or character == '-')
            '-'
        else
            continue;
        if (length == buffer.len) return null;
        buffer[length] = output;
        length += 1;
    }
    return buffer[0..length];
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = std.heap.smp_allocator;
    var root = try std.Io.Dir.cwd().openDir(init.io, ".", .{ .iterate = true });
    defer root.close(init.io);

    var checker = Checker{
        .allocator = allocator,
        .io = init.io,
        .root = root,
    };
    checker.checkRequiredPaths();
    try checker.checkPlanGuideSync();
    try checker.checkRequirements();
    try checker.checkCiWorkflow();
    try checker.checkRepositoryFiles();

    if (checker.failures != 0) {
        std.debug.print("policy check: FAIL ({d} issue(s))\n", .{checker.failures});
        return 1;
    }
    std.debug.print("policy check: PASS\n", .{});
    return 0;
}

test "numbered units require two or three numeric components" {
    try std.testing.expect(isNumberedUnit("1.0"));
    try std.testing.expect(isNumberedUnit("1.0.2"));
    try std.testing.expect(!isNumberedUnit("Phase-1"));
    try std.testing.expect(!isNumberedUnit("1.0.2.1"));
}

test "requirement IDs have a strict family and three-digit sequence" {
    try std.testing.expect(isRequirementId("UCI-001"));
    try std.testing.expect(!isRequirementId("uci-001"));
    try std.testing.expect(!isRequirementId("UCI-1"));
}

test "heading anchors follow the repository's Markdown convention" {
    var buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        "21--board-state-and-correctness",
        headingAnchor("2.1 — Board state and correctness", &buffer).?,
    );
    try std.testing.expect(hasHeadingAnchor(
        "## 2.1 — Board state and correctness\n",
        "21--board-state-and-correctness",
    ));
}

test "architecture paths accept repository separators" {
    try std.testing.expect(hasPathPrefix("src/uci/session.zig", "src/uci/"));
    try std.testing.expect(hasPathPrefix("src\\uci\\session.zig", "src/uci/"));
    try std.testing.expect(pathEquals("src\\manta.zig", "src/manta.zig"));
    try std.testing.expect(!hasPathPrefix("tests/uci/session.zig", "src/uci/"));
}

test "policy walk excludes generated data but not source data directories" {
    try std.testing.expect(shouldSkipDirectory("tools/texel/data"));
    try std.testing.expect(shouldSkipDirectory("tools\\texel\\data"));
    try std.testing.expect(shouldSkipDirectory("tools/texel/out"));
    try std.testing.expect(shouldSkipDirectory(".venv"));
    try std.testing.expect(!shouldSkipDirectory("src/data"));
}
