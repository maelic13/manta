//! Statically bound evaluator/update/trace contract consumed by future search.
const std = @import("std");
const position = @import("../chess/position.zig");
const move = @import("../chess/move.zig");
const see = @import("../chess/see.zig");
const types = @import("../chess/types.zig");
const score = @import("../score.zig");
const trace = @import("trace.zig");

pub const Backend = enum {
    scalar,
    optimized,
};

pub const UpdateDirection = enum {
    forward,
    backward,
};

/// `position` at an update call is always the post-transition position. The
/// delta belongs to the child state: forward applies it, backward reverses it.
pub const Update = struct {
    delta: *const position.MoveDelta,
    direction: UpdateDirection,
};

pub fn isEvaluator(comptime Evaluator: type) bool {
    if (!@hasDecl(Evaluator, "State") or
        !@hasDecl(Evaluator, "TraceEntry") or
        !@hasDecl(Evaluator, "see_values") or
        !@hasDecl(Evaluator, "backend") or
        !@hasDecl(Evaluator, "refresh") or
        !@hasDecl(Evaluator, "update") or
        !@hasDecl(Evaluator, "evaluate")) return false;
    if (@TypeOf(Evaluator.State) != type or @TypeOf(Evaluator.TraceEntry) != type) return false;
    if (@TypeOf(Evaluator.backend) != Backend) return false;
    if (@TypeOf(Evaluator.see_values) != see.PieceValues) return false;
    if (@TypeOf(Evaluator.refresh) != fn (
        *const Evaluator,
        *Evaluator.State,
        *const position.Position,
    ) void) return false;
    if (@TypeOf(Evaluator.update) != fn (
        *const Evaluator,
        *Evaluator.State,
        *const position.Position,
        Update,
    ) void) return false;
    return true;
}

pub fn requireEvaluator(comptime Evaluator: type) void {
    if (!isEvaluator(Evaluator)) {
        @compileError("evaluator must expose State, TraceEntry, see_values, backend, refresh, update, and evaluate");
    }
    // SAFETY: these values occur only inside `@TypeOf`; no pointer is evaluated
    // or dereferenced while the generic return type is inspected.
    const result = @TypeOf(Evaluator.evaluate(
        trace.Disabled,
        @as(*const Evaluator, undefined),
        @as(*Evaluator.State, undefined),
        @as(*const position.Position, undefined),
        @as(*trace.Disabled, undefined),
    ));
    if (result != score.Score) {
        @compileError("evaluator evaluate must return score.Score");
    }
}

/// Search specializes on this concrete evaluator/sink pair. Runtime evaluator
/// selection belongs outside recursive search and constructs one such binding.
pub fn Binding(comptime Evaluator: type, comptime Sink: type) type {
    comptime requireEvaluator(Evaluator);
    comptime trace.requireSink(Sink, Evaluator.TraceEntry);

    return struct {
        const Self = @This();

        pub const backend = Evaluator.backend;

        evaluator: *const Evaluator,
        state: *Evaluator.State,
        sink: *Sink,

        pub inline fn refresh(self: Self, value: *const position.Position) void {
            Evaluator.refresh(self.evaluator, self.state, value);
        }

        pub inline fn update(self: Self, value: *const position.Position, change: Update) void {
            Evaluator.update(self.evaluator, self.state, value, change);
        }

        pub inline fn evaluate(self: Self, value: *const position.Position) score.Score {
            return Evaluator.evaluate(Sink, self.evaluator, self.state, value, self.sink);
        }

        pub inline fn seeAtLeast(
            _: Self,
            value: *const position.Position,
            chess_move: move.Move,
            threshold: i32,
        ) bool {
            return see.atLeast(value, chess_move, threshold, Evaluator.see_values);
        }
    };
}

const ProbeEvaluator = struct {
    const Self = @This();

    pub const State = struct {
        white_value: i32 = 0,
        updates: i32 = 0,
    };
    pub const TraceEntry = i32;
    pub const see_values: see.PieceValues = .{
        .pawn = 100,
        .knight = 300,
        .bishop = 300,
        .rook = 500,
        .queen = 900,
        .king = 0,
    };
    pub const backend: Backend = .scalar;

    pub fn refresh(_: *const Self, state: *State, value: *const position.Position) void {
        state.white_value = @intCast(value.physical.piece_count[types.Piece.white_pawn.index()]);
    }

    pub fn update(_: *const Self, state: *State, _: *const position.Position, change: Update) void {
        const changed_pieces: i32 = @intCast(change.delta.slice().len);
        state.updates += if (change.direction == .forward) changed_pieces else -changed_pieces;
    }

    pub fn evaluate(
        comptime Sink: type,
        _: *const Self,
        state: *State,
        value: *const position.Position,
        sink: *Sink,
    ) score.Score {
        sink.emit("probe", state.white_value);
        const relative = if (value.side_to_move == .white)
            state.white_value
        else
            -state.white_value;
        return score.Score.fromOrdinary(relative).?;
    }
};

const MissingUpdate = struct {
    pub const State = struct {};
    pub const TraceEntry = void;
    pub const backend: Backend = .scalar;

    pub fn refresh(_: *const @This(), _: *State, _: *const position.Position) void {}

    pub fn evaluate(
        comptime Sink: type,
        _: *const @This(),
        _: *State,
        _: *const position.Position,
        _: *Sink,
    ) score.Score {
        return .zero;
    }
};

test "evaluator structural contract accepts complete and rejects incomplete types" {
    // The search boundary depends on behavior, not a runtime interface object.
    try std.testing.expect(isEvaluator(ProbeEvaluator));
    try std.testing.expect(!isEvaluator(MissingUpdate));
    comptime requireEvaluator(ProbeEvaluator);
}

test "static binding preserves perspective, update direction, and trace equivalence" {
    // Static evaluation is side-to-move evidence; make/unmake updates are exact.
    var root_state: position.PositionState = .{};
    var value = position.Position.initEmpty(&root_state);
    value.physical.piece_count[types.Piece.white_pawn.index()] = 3;

    const evaluator = ProbeEvaluator{};
    var evaluator_state: ProbeEvaluator.State = .{};
    var disabled: trace.Disabled = .{};
    const Plain = Binding(ProbeEvaluator, trace.Disabled);
    const plain = Plain{
        .evaluator = &evaluator,
        .state = &evaluator_state,
        .sink = &disabled,
    };
    plain.refresh(&value);
    try std.testing.expectEqual(@as(i32, 3), plain.evaluate(&value).raw());

    var delta: position.MoveDelta = .{};
    delta.append(.{ .piece = .white_pawn, .from = .a7 });
    delta.append(.{ .piece = .black_rook, .from = .a8 });
    delta.append(.{ .piece = .white_queen, .to = .a8 });
    const forward = Update{ .delta = &delta, .direction = .forward };
    const backward = Update{ .delta = &delta, .direction = .backward };
    plain.update(&value, forward);
    plain.update(&value, backward);
    try std.testing.expectEqual(@as(i32, 0), evaluator_state.updates);

    value.side_to_move = .black;
    try std.testing.expectEqual(@as(i32, -3), plain.evaluate(&value).raw());

    const TestTrace = trace.Buffer(i32, 1);
    var buffer = TestTrace.init();
    const Traced = Binding(ProbeEvaluator, TestTrace);
    const traced = Traced{
        .evaluator = &evaluator,
        .state = &evaluator_state,
        .sink = &buffer,
    };
    try std.testing.expectEqual(plain.evaluate(&value), traced.evaluate(&value));
    try std.testing.expectEqual(@as(usize, 1), buffer.slice().len);
    try std.testing.expectEqual(@as(i32, 3), buffer.slice()[0].value);
}
