//! Owned adapter over the vendored Fathom Syzygy probe library.
//!
//! This is the only Manta code that touches the third-party probe layer or its
//! files. It translates Manta's board into Fathom's bitboard call convention
//! and translates Fathom's packed result back into the inward `search`
//! tablebase contract; it makes no chess-policy decision of its own.
//!
//! Ownership follows the resource-generation rule: the handle is initialized
//! before workers are published and freed only after they join. `tb_init` is
//! not thread safe, so it must never run while a search is live. WDL probing
//! is thread safe once initialization completes.
const std = @import("std");
const chess = @import("../chess/root.zig");
const tablebase = @import("../search/tablebase.zig");

/// Zig declarations for the vendored `tbprobe.h` API that Manta calls.
///
/// They are written by hand rather than translated so that the build carries no
/// C-translation dependency. `syzygy_abi.c` compiles against the real header
/// and exports its constants and layout; a test below compares them with these
/// declarations, so an upstream renumbering or layout change cannot pass
/// silently.
const c = struct {
    const TbMove = u16;

    const TB_MAX_MOVES = 192 + 1;
    const TB_MAX_PLY = 256;

    const TB_LOSS = 0;
    const TB_BLESSED_LOSS = 1;
    const TB_DRAW = 2;
    const TB_CURSED_WIN = 3;
    const TB_WIN = 4;

    const TB_PROMOTES_NONE = 0;
    const TB_PROMOTES_QUEEN = 1;
    const TB_PROMOTES_ROOK = 2;
    const TB_PROMOTES_BISHOP = 3;
    const TB_PROMOTES_KNIGHT = 4;

    const TB_RESULT_FAILED: c_uint = 0xFFFFFFFF;

    const TbRootMove = extern struct {
        move: TbMove,
        pv: [TB_MAX_PLY]TbMove,
        pv_size: c_uint,
        tb_score: i32,
        tb_rank: i32,
    };

    const TbRootMoves = extern struct {
        size: c_uint,
        moves: [TB_MAX_MOVES]TbRootMove,
    };

    extern var TB_LARGEST: c_uint;
    extern fn tb_init(path: [*:0]const u8) bool;
    extern fn tb_free() void;
    extern fn tb_probe_wdl_impl(
        white: u64,
        black: u64,
        kings: u64,
        queens: u64,
        rooks: u64,
        bishops: u64,
        knights: u64,
        pawns: u64,
        ep: c_uint,
        turn: bool,
    ) c_uint;
    extern fn tb_probe_root_dtz(
        white: u64,
        black: u64,
        kings: u64,
        queens: u64,
        rooks: u64,
        bishops: u64,
        knights: u64,
        pawns: u64,
        rule50: c_uint,
        castling: c_uint,
        ep: c_uint,
        turn: bool,
        has_repeated: bool,
        use_rule50: bool,
        results: *TbRootMoves,
    ) c_int;
    extern fn tb_probe_root_wdl(
        white: u64,
        black: u64,
        kings: u64,
        queens: u64,
        rooks: u64,
        bishops: u64,
        knights: u64,
        pawns: u64,
        rule50: c_uint,
        castling: c_uint,
        ep: c_uint,
        turn: bool,
        use_rule50: bool,
        results: *TbRootMoves,
    ) c_int;

    /// The header's `static inline` entry point: Syzygy WDL tables index only
    /// positions without castling rights and with a reset halfmove clock.
    fn tb_probe_wdl(
        white: u64,
        black: u64,
        kings: u64,
        queens: u64,
        rooks: u64,
        bishops: u64,
        knights: u64,
        pawns: u64,
        rule50: c_uint,
        castling: c_uint,
        ep: c_uint,
        turn: bool,
    ) c_uint {
        if (castling != 0) return TB_RESULT_FAILED;
        if (rule50 != 0) return TB_RESULT_FAILED;
        return tb_probe_wdl_impl(white, black, kings, queens, rooks, bishops, knights, pawns, ep, turn);
    }
};

/// Constants and layout facts exported by `syzygy_abi.c` from the real header.
extern const manta_fathom_abi: [manta_fathom_abi_len]u32;
const manta_fathom_abi_len = 21;

/// Reasons initialization refused a path. Missing files are not an error:
/// Fathom reports success with zero tables, which degrades to ordinary search.
pub const InitError = error{
    /// Fathom rejected the path string outright.
    ProbeInitFailed,
    /// The path contained an interior zero byte and cannot cross the C ABI.
    InvalidPath,
    /// The path exceeded the adapter's fixed path buffer.
    PathTooLong,
};

pub const max_path_len = 4095;

/// A loaded (or deliberately empty) tablebase generation.
///
/// `largest` is zero whenever no tables are usable, which is the single flag
/// every consumer checks. That keeps "no tablebases configured", "path empty"
/// and "path had no readable tables" on one safe degradation path.
pub const Handle = struct {
    largest: u8 = 0,
    initialized: bool = false,

    /// Loads tables from a Syzygy path list. An empty path unloads and is not
    /// an error. A path naming no readable tables also succeeds with
    /// `largest == 0`, because a missing tablebase must degrade rather than
    /// fail the engine.
    pub fn init(path: []const u8) InitError!Handle {
        if (path.len > max_path_len) return error.PathTooLong;
        if (std.mem.findScalar(u8, path, 0) != null) return error.InvalidPath;

        var buffer: [max_path_len + 1]u8 = undefined;
        @memcpy(buffer[0..path.len], path);
        buffer[path.len] = 0;

        if (!c.tb_init(buffer[0..path.len :0])) return error.ProbeInitFailed;
        const largest = c.TB_LARGEST;
        return .{
            .largest = if (largest > std.math.maxInt(u8)) std.math.maxInt(u8) else @intCast(largest),
            .initialized = true,
        };
    }

    /// Releases probe resources. Safe to call on an unloaded handle, and
    /// required before the process replaces or drops a generation.
    pub fn deinit(self: *Handle) void {
        if (self.initialized) c.tb_free();
        self.* = .{};
    }

    pub fn isLoaded(self: Handle) bool {
        return self.initialized and self.largest != 0;
    }

    /// Probes win/draw/loss for the side to move.
    ///
    /// The inward contract owns every precondition, so this function only
    /// performs the translation and reports whatever the tables answered.
    pub fn probeWdl(
        self: Handle,
        position: *const chess.position.Position,
    ) tablebase.ProbeResult {
        const piece_count: u8 = @intCast(@popCount(position.physical.occupied()));
        if (tablebase.wdlPrecondition(
            piece_count,
            self.largest,
            position.current.castling_rights != .none,
            position.current.rule50,
        )) |reason| return .{ .unavailable = reason };

        const physical = &position.physical;
        const white = physical.by_color[chess.types.Color.white.index()];
        const black = physical.by_color[chess.types.Color.black.index()];
        const result = c.tb_probe_wdl(
            white,
            black,
            physical.by_type[chess.types.PieceType.king.index()],
            physical.by_type[chess.types.PieceType.queen.index()],
            physical.by_type[chess.types.PieceType.rook.index()],
            physical.by_type[chess.types.PieceType.bishop.index()],
            physical.by_type[chess.types.PieceType.knight.index()],
            physical.by_type[chess.types.PieceType.pawn.index()],
            0,
            0,
            enPassantSquare(position),
            position.side_to_move == .white,
        );
        if (result == c.TB_RESULT_FAILED) return .{ .unavailable = .probe_failed };
        return .{ .available = decodeWdl(result) };
    }

    /// Ranks the legal root moves with the DTZ tables, falling back to WDL.
    ///
    /// Returns the number of ranked moves written, or null whenever the tables
    /// cannot rank this root. Every failure path is an ordinary degradation: the
    /// caller simply searches the unrestricted root.
    ///
    /// Fathom's move encoding is never turned into a Manta move directly. Each
    /// returned move is matched against the caller's own legal move list by
    /// origin, destination and promotion piece, so the board layer remains the
    /// only authority on move identity and a foreign encoding cannot inject an
    /// illegal or misinterpreted move. An unmatched move abandons filtering
    /// entirely rather than silently dropping a legal option.
    pub fn probeRootMoves(
        self: Handle,
        position: *const chess.position.Position,
        legal_moves: []const chess.move.Move,
        out: *[chess.types.move_capacity]tablebase.RankedRootMove,
    ) ?usize {
        if (!self.isLoaded()) return null;
        if (legal_moves.len == 0) return null;
        const piece_count: u8 = @intCast(@popCount(position.physical.occupied()));
        if (piece_count > self.largest) return null;
        // Syzygy does not index positions that still have castling rights. The
        // halfmove clock is allowed here, unlike a WDL probe, because the DTZ
        // ranking consumes it directly.
        if (position.current.castling_rights != .none) return null;

        const physical = &position.physical;
        var results: c.TbRootMoves = undefined;
        const white = physical.by_color[chess.types.Color.white.index()];
        const black = physical.by_color[chess.types.Color.black.index()];
        const kings = physical.by_type[chess.types.PieceType.king.index()];
        const queens = physical.by_type[chess.types.PieceType.queen.index()];
        const rooks = physical.by_type[chess.types.PieceType.rook.index()];
        const bishops = physical.by_type[chess.types.PieceType.bishop.index()];
        const knights = physical.by_type[chess.types.PieceType.knight.index()];
        const pawns = physical.by_type[chess.types.PieceType.pawn.index()];
        const rule50: c_uint = position.current.rule50;
        const ep = enPassantSquare(position);
        const turn = position.side_to_move == .white;
        // A repetition already available to the side to move makes a distance-to-
        // zero plan unreliable, and Fathom accounts for that when ranking.
        const has_repeated = position.current.repetition != 0;

        var ok = c.tb_probe_root_dtz(
            white,
            black,
            kings,
            queens,
            rooks,
            bishops,
            knights,
            pawns,
            rule50,
            0,
            ep,
            turn,
            has_repeated,
            true,
            &results,
        );
        if (ok == 0) {
            // Missing DTZ files are common; WDL alone still ranks outcomes.
            ok = c.tb_probe_root_wdl(
                white,
                black,
                kings,
                queens,
                rooks,
                bishops,
                knights,
                pawns,
                rule50,
                0,
                ep,
                turn,
                true,
                &results,
            );
        }
        if (ok == 0 or results.size == 0) return null;

        var count: usize = 0;
        for (results.moves[0..results.size]) |ranked| {
            const matched = matchLegalMove(legal_moves, ranked.move) orelse return null;
            out[count] = .{ .move = matched, .rank = ranked.tb_rank };
            count += 1;
        }
        return count;
    }
};

/// Finds the caller's legal move matching Fathom's encoded origin,
/// destination and promotion piece. Castling and en passant need no special
/// case: they are identified by their squares, and the caller's own generator
/// already produced the correctly typed move.
fn matchLegalMove(
    legal_moves: []const chess.move.Move,
    encoded: c.TbMove,
) ?chess.move.Move {
    const from_index = (encoded >> 6) & 0x3F;
    const to_index = encoded & 0x3F;
    const promotes = (encoded >> 12) & 0x7;
    for (legal_moves) |candidate| {
        if (candidate.from().index() != from_index) continue;
        if (candidate.to().index() != to_index) continue;
        const wants_promotion = promotes != c.TB_PROMOTES_NONE;
        if (wants_promotion != (candidate.kind() == .promotion)) continue;
        if (!wants_promotion) return candidate;
        const expected: chess.types.PieceType = switch (promotes) {
            c.TB_PROMOTES_QUEEN => .queen,
            c.TB_PROMOTES_ROOK => .rook,
            c.TB_PROMOTES_BISHOP => .bishop,
            c.TB_PROMOTES_KNIGHT => .knight,
            else => return null,
        };
        if (candidate.promotionPiece() == expected) return candidate;
    }
    return null;
}

/// Fathom expects zero when no en-passant capture is available.
fn enPassantSquare(position: *const chess.position.Position) c_uint {
    const target = position.current.ep_square;
    if (target == .none) return 0;
    return @intCast(target.index());
}

fn decodeWdl(raw: c_uint) tablebase.Wdl {
    return switch (raw) {
        c.TB_LOSS => .loss,
        c.TB_BLESSED_LOSS => .blessed_loss,
        c.TB_DRAW => .draw,
        c.TB_CURSED_WIN => .cursed_win,
        c.TB_WIN => .win,
        // Fathom documents exactly these five values for a successful probe.
        else => unreachable,
    };
}

comptime {
    // The inward contract mirrors Fathom's encoding. If the vendored revision
    // ever renumbers these, the pinned-hash update procedure must catch it, so
    // assert the agreement here instead of trusting two independent constants.
    std.debug.assert(@backingInt(tablebase.Wdl.loss) == c.TB_LOSS);
    std.debug.assert(@backingInt(tablebase.Wdl.blessed_loss) == c.TB_BLESSED_LOSS);
    std.debug.assert(@backingInt(tablebase.Wdl.draw) == c.TB_DRAW);
    std.debug.assert(@backingInt(tablebase.Wdl.cursed_win) == c.TB_CURSED_WIN);
    std.debug.assert(@backingInt(tablebase.Wdl.win) == c.TB_WIN);
}

test "hand-written Fathom declarations match the compiled header" {
    // The C compiler reads tbprobe.h independently of these declarations, so
    // agreement here is the guard that ABI-relevant upstream changes fail.
    const expected = [manta_fathom_abi_len]u32{
        c.TB_MAX_MOVES,
        c.TB_MAX_PLY,
        c.TB_LOSS,
        c.TB_BLESSED_LOSS,
        c.TB_DRAW,
        c.TB_CURSED_WIN,
        c.TB_WIN,
        c.TB_PROMOTES_NONE,
        c.TB_PROMOTES_QUEEN,
        c.TB_PROMOTES_ROOK,
        c.TB_PROMOTES_BISHOP,
        c.TB_PROMOTES_KNIGHT,
        c.TB_RESULT_FAILED,
        @sizeOf(c.TbMove),
        @sizeOf(c.TbRootMove),
        @offsetOf(c.TbRootMove, "pv"),
        @offsetOf(c.TbRootMove, "pv_size"),
        @offsetOf(c.TbRootMove, "tb_rank"),
        @sizeOf(c.TbRootMoves),
        @offsetOf(c.TbRootMoves, "moves"),
        @sizeOf(c_uint),
    };
    try std.testing.expectEqualSlices(u32, &expected, &manta_fathom_abi);
}

test "an empty path yields a safe unloaded handle rather than an error" {
    // A missing or unconfigured tablebase must degrade to ordinary search.
    var handle = try Handle.init("");
    defer handle.deinit();
    try std.testing.expect(!handle.isLoaded());
    try std.testing.expectEqual(@as(u8, 0), handle.largest);
}

test "a nonexistent path loads no tables and still degrades safely" {
    // Fathom reports success with zero tables when nothing is readable. The
    // adapter must preserve that contract so a bad path cannot abort a search.
    var handle = try Handle.init("D:/manta-nonexistent-syzygy-path-for-tests");
    defer handle.deinit();
    try std.testing.expect(!handle.isLoaded());
}

test "paths that cannot cross the C ABI are rejected before probing" {
    // An interior zero byte would silently truncate the path inside C.
    try std.testing.expectError(error.InvalidPath, Handle.init("a\x00b"));
    const long_path: [max_path_len + 1]u8 = @splat('x');
    try std.testing.expectError(error.PathTooLong, Handle.init(&long_path));
}

test "an unloaded handle reports not_loaded instead of probing" {
    // Probing an unloaded generation must be a normal, allocation-free answer.
    var root: chess.position.PositionState = .{};
    const position = try chess.fen.parse("4k3/8/8/8/8/8/8/4K2R w K - 0 1", &root);
    var handle = Handle{};
    const result = handle.probeWdl(&position);
    try std.testing.expectEqual(
        tablebase.ProbeResult{ .unavailable = .not_loaded },
        result,
    );
}
