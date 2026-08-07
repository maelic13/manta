const std = @import("std");

const max_file_size = 2 * 1024 * 1024;
const expected_requirement_count = 90;

const required_paths = [_][]const u8{
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
    "build_support/zig_version.zig",
    "docs/DEVELOPMENT.md",
    "src/main.zig",
    "src/manta.zig",
    "tests/root.zig",
    "tools/policy_check.zig",
    "zlint.json",
};

const allowed_reference_files = [_][]const u8{
    "PLAN.md",
    "GUIDE.md",
    "EXPERIMENTS.md",
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

    fn checkRepositoryFiles(self: *Checker) !void {
        var walker = try self.root.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next(self.io)) |entry| {
            if (entry.kind == .directory and shouldSkipDirectory(entry.basename)) {
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

fn shouldSkipDirectory(name: []const u8) bool {
    return std.mem.eql(u8, name, ".git") or
        std.mem.eql(u8, name, ".zig-cache") or
        std.mem.eql(u8, name, "zig-out") or
        std.mem.eql(u8, name, "zig-pkg");
}

fn isPolicyTextFile(path: []const u8) bool {
    const extensions = [_][]const u8{
        ".json", ".md",  ".ps1", ".sh",  ".toml",
        ".yaml", ".yml", ".zig", ".zon",
    };
    for (extensions) |extension| {
        if (std.mem.endsWith(u8, path, extension)) return true;
    }
    return false;
}

fn isAllowedReferenceFile(path: []const u8) bool {
    for (allowed_reference_files) |allowed| {
        if (std.mem.eql(u8, path, allowed)) return true;
    }
    return false;
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
