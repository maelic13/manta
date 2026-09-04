//! Selected physical-position and caller-owned reversible-state layouts.
const std = @import("std");
const move = @import("move.zig");
const types = @import("types.zig");

pub const PieceChange = struct {
    piece: types.Piece = .none,
    from: types.Square = .none,
    to: types.Square = .none,
};

/// Every orthodox move changes at most three piece facts: promotion capture is
/// remove pawn + remove victim + add promoted piece. This factual delta has no
/// evaluator or network semantics.
pub const MoveDelta = struct {
    changes: [3]PieceChange = @splat(.{}),
    count: u2 = 0,

    pub fn append(self: *MoveDelta, change: PieceChange) void {
        std.debug.assert(self.count < self.changes.len);
        self.changes[self.count] = change;
        self.count += 1;
    }

    pub fn slice(self: *const MoveDelta) []const PieceChange {
        return self.changes[0..self.count];
    }
};

pub const PositionState = struct {
    key: types.Key = 0,
    pawn_key: types.Key = 0,
    minor_key: types.Key = 0,
    non_pawn_key: [2]types.Key = @splat(0),
    checkers: types.Bitboard = 0,
    previous: ?*PositionState = null,
    delta: MoveDelta = .{},
    ep_square: types.Square = .none,
    captured_piece: types.Piece = .none,
    castling_rights: types.CastlingRights = .none,
    rule50: u16 = 0,
    plies_from_null: u16 = 0,
    /// Ply distance back to the nearest earlier state holding this position
    /// key, or zero when the reversible post-null window holds none.
    ///
    /// The sign carries the second fact a repetition consumer needs: it is
    /// negative when that earlier occurrence was itself a repetition, so the
    /// current position is at least the third occurrence of the key. Both
    /// facts are established once, while the state chain is being extended,
    /// because a consumer that rediscovers them walks the same chain again at
    /// every visit for an answer that cannot have changed.
    repetition: i16 = 0,
};

/// Type/color bitboards plus a mailbox minimize mutable bitboards while
/// preserving constant-time piece lookup. Index zero of `by_type` is the
/// combined occupancy; indices one through six match `PieceType`.
pub const PhysicalPosition = struct {
    board: [64]types.Piece = @splat(.none),
    by_type: [7]types.Bitboard = @splat(0),
    by_color: [2]types.Bitboard = @splat(0),
    piece_count: [15]u8 = @splat(0),
    king_square: [2]types.Square = @splat(.none),

    pub fn occupied(self: *const PhysicalPosition) types.Bitboard {
        return self.by_type[types.PieceType.none.index()];
    }

    pub fn pieces(self: *const PhysicalPosition, color: types.Color, piece_type: types.PieceType) types.Bitboard {
        std.debug.assert(piece_type.isPiece());
        return self.by_color[color.index()] & self.by_type[piece_type.index()];
    }

    pub fn pieceOn(self: *const PhysicalPosition, square: types.Square) types.Piece {
        return self.board[square.index()];
    }
};

/// A position borrows its current state. Search workers provide stable-address
/// state arrays; root/worker cloning must explicitly rebind this pointer.
pub const Position = struct {
    physical: PhysicalPosition = .{},
    current: *PositionState,
    game_ply: u64 = 0,
    side_to_move: types.Color = .white,

    pub fn initEmpty(root_state: *PositionState) Position {
        root_state.* = .{};
        return .{ .current = root_state };
    }

    pub fn currentState(self: *const Position) *const PositionState {
        return self.current;
    }

    pub fn rebind(self: *Position, state: *PositionState) void {
        self.current = state;
    }
};

pub const MoveList = struct {
    moves: [types.move_capacity]move.Move,
    count: usize = 0,

    pub fn init() MoveList {
        // SAFETY: `count` starts at zero, and access is restricted to the
        // initialized prefix written by `append`.
        return .{ .moves = undefined };
    }

    pub fn append(self: *MoveList, value: move.Move) void {
        std.debug.assert(self.count < self.moves.len);
        self.moves[self.count] = value;
        self.count += 1;
    }

    pub fn slice(self: *const MoveList) []const move.Move {
        return self.moves[0..self.count];
    }
};

comptime {
    // These budgets protect per-worker cache/stack shape without freezing
    // incidental field offsets. Supported targets are 64-bit.
    std.debug.assert(@sizeOf(PhysicalPosition) <= 160);
    std.debug.assert(@sizeOf(PositionState) <= 96);
    std.debug.assert(@sizeOf(MoveList) == 520);
    std.debug.assert(@alignOf(PhysicalPosition) <= 8);
    std.debug.assert(@alignOf(PositionState) <= 8);
}

test "position state is caller-owned and explicitly rebound" {
    // A copied physical position must never retain an accidental state owner.
    var root_state: PositionState = .{ .key = 17 };
    var position = Position.initEmpty(&root_state);
    try std.testing.expect(position.currentState() == &root_state);

    var worker_state: PositionState = .{ .key = 29 };
    position.rebind(&worker_state);
    try std.testing.expect(position.currentState() == &worker_state);
    try std.testing.expectEqual(@as(types.Key, 29), position.currentState().key);
}

test "factual move delta covers every standard special-move shape" {
    // A promotion capture is the maximum: remove pawn, remove victim, add piece.
    var delta: MoveDelta = .{};
    delta.append(.{ .piece = .white_pawn, .from = .a7 });
    delta.append(.{ .piece = .black_rook, .from = .a8 });
    delta.append(.{ .piece = .white_queen, .to = .a8 });
    try std.testing.expectEqual(@as(usize, 3), delta.slice().len);
}

test "move list bound is a node capacity rather than game history" {
    // RES-004 fixes generated moves at 256; controller game history is separate.
    var list = MoveList.init();
    list.append(move.Move.normal(.g1, .f3));
    try std.testing.expectEqual(@as(usize, 1), list.slice().len);
}
