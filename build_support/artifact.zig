const std = @import("std");

pub const Mode = enum {
    native,
    portable,
};

pub const Profile = enum {
    auto,
    x86_64,
    arm64,
    avx2,
    pext,
    avx512,

    pub fn parse(text: []const u8) error{UnknownProfile}!Profile {
        if (std.mem.eql(u8, text, "auto")) return .auto;
        if (std.mem.eql(u8, text, "x86-64")) return .x86_64;
        if (std.mem.eql(u8, text, "arm64")) return .arm64;
        if (std.mem.eql(u8, text, "avx2")) return .avx2;
        if (std.mem.eql(u8, text, "pext")) return .pext;
        if (std.mem.eql(u8, text, "avx512")) return .avx512;
        return error.UnknownProfile;
    }

    pub fn tag(self: Profile) []const u8 {
        return switch (self) {
            .auto => "auto",
            .x86_64 => "x86-64",
            .arm64 => "arm64",
            .avx2 => "avx2",
            .pext => "pext",
            .avx512 => "avx512",
        };
    }
};

pub const Request = struct {
    native: bool = false,
    portable: bool = false,
    profile: []const u8 = "auto",
    pgo: bool = false,
};

pub const Configuration = struct {
    mode: Mode,
    profile: Profile,
    pgo: bool,
};

pub const ResolveError = error{
    ConflictingModes,
    UnknownProfile,
    UnsupportedArchitecture,
    ProfileTargetMismatch,
    ProfileNotAvailable,
    PgoNotAvailable,
};

/// Resolve user-facing build policy independently of compiler target creation.
/// `auto` deliberately selects only a profile with a retained implementation;
/// Phase 10 may add measured microarchitecture preferences here.
pub fn resolve(request: Request, arch: std.Target.Cpu.Arch) ResolveError!Configuration {
    if (request.native and request.portable) return error.ConflictingModes;
    if (request.pgo) return error.PgoNotAvailable;

    const mode: Mode = if (request.portable) .portable else .native;
    const requested_profile = Profile.parse(request.profile) catch return error.UnknownProfile;
    const profile = switch (requested_profile) {
        .auto => baselineProfile(arch) catch return error.UnsupportedArchitecture,
        .x86_64 => if (arch == .x86_64) .x86_64 else return error.ProfileTargetMismatch,
        .arm64 => if (arch == .aarch64) .arm64 else return error.ProfileTargetMismatch,
        .avx2, .pext, .avx512 => return error.ProfileNotAvailable,
    };

    return .{ .mode = mode, .profile = profile, .pgo = false };
}

fn baselineProfile(arch: std.Target.Cpu.Arch) error{UnsupportedArchitecture}!Profile {
    return switch (arch) {
        .x86_64 => .x86_64,
        .aarch64 => .arm64,
        else => error.UnsupportedArchitecture,
    };
}

pub const NameError = error{
    InvalidVersion,
    UnsupportedOperatingSystem,
};

pub fn artifactName(
    allocator: std.mem.Allocator,
    version: []const u8,
    os: std.Target.Os.Tag,
    configuration: Configuration,
    optimize: std.builtin.OptimizeMode,
) (NameError || std.mem.Allocator.Error)![]u8 {
    if (!validVersion(version)) return error.InvalidVersion;

    const os_tag = switch (os) {
        .windows => "windows",
        .linux => "linux",
        .macos => "macos",
        else => return error.UnsupportedOperatingSystem,
    };
    const native_suffix = if (configuration.mode == .native) "-native" else "";
    const optimize_suffix = switch (optimize) {
        .ReleaseFast => "",
        .Debug => "-debug",
        .ReleaseSafe => "-release-safe",
        .ReleaseSmall => "-release-small",
    };
    const pgo_suffix = if (configuration.pgo) "-pgo" else "";
    const extension = if (os == .windows) ".exe" else "";

    return std.fmt.allocPrint(
        allocator,
        "manta-v{s}-{s}-{s}{s}{s}{s}{s}",
        .{
            version,
            os_tag,
            configuration.profile.tag(),
            native_suffix,
            optimize_suffix,
            pgo_suffix,
            extension,
        },
    );
}

fn validVersion(version: []const u8) bool {
    if (version.len == 0) return false;
    for (version) |character| {
        if (std.ascii.isAlphanumeric(character)) continue;
        if (character == '.' or character == '-' or character == '+') continue;
        return false;
    }
    return true;
}

test "native is the default and portable is explicit" {
    const native = try resolve(.{}, .x86_64);
    try std.testing.expectEqual(Mode.native, native.mode);
    try std.testing.expectEqual(Profile.x86_64, native.profile);

    const portable = try resolve(.{ .portable = true }, .aarch64);
    try std.testing.expectEqual(Mode.portable, portable.mode);
    try std.testing.expectEqual(Profile.arm64, portable.profile);
}

test "build policy rejects every 32-bit architecture family" {
    // PORT-006 permits hot layouts to rely on 64-bit pointers and `usize`.
    // Both common 32-bit families must therefore fail before compilation.
    try std.testing.expectError(error.UnsupportedArchitecture, resolve(.{}, .x86));
    try std.testing.expectError(error.UnsupportedArchitecture, resolve(.{}, .arm));
}

test "native and portable are mutually exclusive" {
    try std.testing.expectError(
        error.ConflictingModes,
        resolve(.{ .native = true, .portable = true }, .x86_64),
    );
}

test "profiles are target-aware and unavailable tiers fail closed" {
    try std.testing.expectError(
        error.ProfileTargetMismatch,
        resolve(.{ .profile = "arm64" }, .x86_64),
    );
    try std.testing.expectError(
        error.ProfileNotAvailable,
        resolve(.{ .profile = "pext" }, .x86_64),
    );
    try std.testing.expectError(
        error.UnknownProfile,
        resolve(.{ .profile = "fastest" }, .x86_64),
    );
}

test "PGO cannot be requested before its measured pipeline exists" {
    try std.testing.expectError(
        error.PgoNotAvailable,
        resolve(.{ .pgo = true }, .x86_64),
    );
}

test "artifact names state portability and non-default optimization" {
    const portable = try artifactName(
        std.testing.allocator,
        "1.0.0",
        .windows,
        .{ .mode = .portable, .profile = .x86_64, .pgo = false },
        .ReleaseFast,
    );
    defer std.testing.allocator.free(portable);
    try std.testing.expectEqualStrings("manta-v1.0.0-windows-x86-64.exe", portable);

    const native = try artifactName(
        std.testing.allocator,
        "0.0.0-dev",
        .linux,
        .{ .mode = .native, .profile = .arm64, .pgo = false },
        .ReleaseSafe,
    );
    defer std.testing.allocator.free(native);
    try std.testing.expectEqualStrings(
        "manta-v0.0.0-dev-linux-arm64-native-release-safe",
        native,
    );

    const future_pgo = try artifactName(
        std.testing.allocator,
        "1.0.0",
        .windows,
        .{ .mode = .native, .profile = .pext, .pgo = true },
        .ReleaseFast,
    );
    defer std.testing.allocator.free(future_pgo);
    try std.testing.expectEqualStrings(
        "manta-v1.0.0-windows-pext-native-pgo.exe",
        future_pgo,
    );
}

test "artifact versions reject path syntax" {
    try std.testing.expectError(
        error.InvalidVersion,
        artifactName(
            std.testing.allocator,
            "1.0/escape",
            .linux,
            .{ .mode = .portable, .profile = .x86_64, .pgo = false },
            .ReleaseFast,
        ),
    );
}
