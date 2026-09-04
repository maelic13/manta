//! Deterministic scalar bootstrap handcrafted evaluation.
const std = @import("std");
const hce_build_options = @import("hce_build_options");
const attacks = @import("../chess/attacks.zig");
const position = @import("../chess/position.zig");
const see = @import("../chess/see.zig");
const types = @import("../chess/types.zig");
const score = @import("../score.zig");
const contract = @import("contract.zig");
const endgame = @import("endgame.zig");
const fit = @import("fit.zig");
const params = @import("hce_params.zig");
const phase = @import("phase.zig");
const winnability = @import("winnability.zig");

const Bitboard = types.Bitboard;

pub const Tapered = struct {
    middlegame: i32 = 0,
    endgame: i32 = 0,

    fn add(self: *Tapered, other: Tapered) void {
        self.middlegame += other.middlegame;
        self.endgame += other.endgame;
    }

    fn scaled(value: [2]i16, count: i32) Tapered {
        return .{
            .middlegame = @as(i32, value[0]) * count,
            .endgame = @as(i32, value[1]) * count,
        };
    }
};

pub const TraceValue = union(enum) {
    tapered: Tapered,
    phase: u8,
    total: i32,
};

/// Step-5.3.1 score-foundation switches. Each mechanism is an independently
/// ablatable chess-rule correction rather than a tuned term, so disabling the
/// whole set reproduces the pre-5.3.1 evaluator exactly.
pub const Config = struct {
    /// Clamp an advantage held by a side that cannot force mate.
    insufficient_material: bool = true,
    /// Scale the score toward a draw as the fifty-move allowance runs out.
    rule_fifty_scaling: bool = true,
    /// Step-5.3.5 king shelter, storm and attack danger. Disabling this alone
    /// restores the pre-5.3.3 evaluator, which had no king-safety term at all.
    king_safety: bool = true,
    /// Step-5.3.6 piece threats and space, read from the shared attack maps.
    threats_and_space: bool = true,
    /// Step-5.3.12 threat and king-safety completion: threats by safe pawn and
    /// by pawn push, slider and knight pressure on the enemy queen, restricted
    /// pieces, weak queen protection, king blockers, king-flank attack and the
    /// pawnless flank. Disabling it restores the Step-5.3.11 evaluator.
    threat_completion: bool = true,
    /// Step-5.3.11 piece detail: outposts for both minors with bad and
    /// reachable variants, minor behind pawn, king protector, the bishop
    /// colour-complex and x-ray terms, long-diagonal and king-ring pressure,
    /// rook on the queen file and the king ring, trapped rook, weak queen and
    /// queen infiltration. Disabling it removes this detail set; schema v3 no
    /// longer preserves the superseded bootstrap knight-outpost ablation.
    piece_detail: bool = true,
    /// Step-5.3.10 pawn completion: backward, weak-unopposed, weak-lever and
    /// blocked pawns, rank-weighted connected pawns, and the passed-pawn model
    /// that asks whether a passer can actually advance. Disabling it restores
    /// the Step-5.3.8 evaluator, which counted connected pawns flat and scored
    /// a passer by its rank alone.
    pawn_completion: bool = true,
    /// Behaviour-neutral worker-local pawn cache. Step 5.3.10 reintroduced
    /// position-growing pawn work and fired ADR-0048's retry trigger. Full-key
    /// validation makes collisions misses rather than evaluation changes.
    pawn_cache: bool = true,
    /// Step-5.3.13 exact-signature endgame values and scale factors. These
    /// remain ordinary static evidence; search owns terminal and tablebase
    /// authority. Disabling the switch restores the Step-5.3.12 evaluator.
    endgame_knowledge: bool = true,
    /// Step-5.3.14 endgame winnability and initiative. This grades conversion
    /// routes without changing terminal, tablebase or draw authority.
    /// Disabling it restores the Step-5.3.13 evaluator.
    winnability: bool = true,
    /// Step-5.4.3 MAN-E20 candidate: continuously weight the existing space
    /// count by material phase and immediately opposed central pawn pairs.
    /// Disabling it preserves exact MAN-E19 behavior, including floor 12.
    contextual_space: bool = false,
    /// Step-5.4.3 MAN-E21 candidate: let signed middlegame shelter moderate
    /// active king danger before the existing square-law penalty.
    shelter_danger_coupling: bool = false,
    /// Rejected MAN-E05 graded endgame scaling, archived default-off. Its
    /// registered gate accepted H0 at `-16.32` Elo. The mechanism and its
    /// tests are retained as refutation history, not as accepted policy. The
    /// unwinnable clamp above is unrelated and remains production: it states a
    /// binary fact, while this attempted to express degrees.
    endgame_scaling: bool = false,
};

/// Halfmove clock at which the remaining allowance starts to bound
/// conversion. Before this, a capture or pawn move is overwhelmingly likely,
/// so scaling would distort ordinary play rather than describe the rules.
pub const rule_fifty_scale_start: u16 = 60;
/// The clock value at which the game is drawn on claim.
pub const rule_fifty_limit: u16 = 100;

/// Production evaluator plus the one explicitly registered compile-time
/// Step-5.4.3 candidate switch. Ordinary builds preserve exact MAN-E19
/// behavior; no runtime branch or UCI surface is introduced.
pub const production_config: Config = .{
    .contextual_space = hce_build_options.contextual_space,
    .shelter_danger_coupling = hce_build_options.shelter_danger_coupling,
};
pub const Hce = HceWith(production_config);

/// Full refresh remains authoritative. The small worker-local pawn cache is a
/// memoization of exact pawn-key evidence, not incremental evaluation state.
pub fn HceWith(comptime config: Config) type {
    return struct {
        const Self = @This();

        pub const State = struct {
            pawn_cache: PawnCache = .{},
        };
        pub const TraceEntry = TraceValue;
        pub const see_values: see.PieceValues = .{
            .pawn = params.mg_val[types.PieceType.pawn.index()],
            .knight = params.mg_val[types.PieceType.knight.index()],
            .bishop = params.mg_val[types.PieceType.bishop.index()],
            .rook = params.mg_val[types.PieceType.rook.index()],
            .queen = params.mg_val[types.PieceType.queen.index()],
            .king = 0,
        };
        pub const backend: contract.Backend = .scalar;

        pub fn refresh(_: *const Self, _: *State, _: *const position.Position) void {}

        pub fn update(
            _: *const Self,
            _: *State,
            _: *const position.Position,
            _: contract.Update,
        ) void {}

        pub fn evaluate(
            comptime Sink: type,
            _: *const Self,
            evaluator_state: *State,
            value: *const position.Position,
            sink: *Sink,
        ) score.Score {
            var total: Tapered = .{};

            const placement = placementAndPhase(Sink, sink, value);
            total.add(placement.value);
            sink.emit("material_pst", TraceValue{ .tapered = placement.value });

            // The pawn sets are produced once and read twice: structure is a
            // pawn-only fact and is scored here, while the passed-pawn model
            // needs the attack maps and is scored after they exist.
            // SAFETY: the only branch that takes this address assigns the
            // complete value immediately before the pointer escapes the block.
            var uncached_pawn_evidence: PawnEvidence = undefined;
            const pawn_evidence: *const PawnEvidence = if (comptime config.pawn_cache)
                evaluator_state.pawn_cache.get(config.pawn_completion, value)
            else blk: {
                uncached_pawn_evidence = PawnEvidence.compute(config.pawn_completion, value);
                break :blk &uncached_pawn_evidence;
            };
            const pawns = pawn_evidence.structure;
            recordPawnFeatures(Sink, sink, config.pawn_completion, &pawn_evidence.sets, value);
            total.add(pawns);
            sink.emit("pawns", TraceValue{ .tapered = pawns });

            // Activity and the shared attack maps are produced together
            // because they read the same fact; see `pieceActivityAndAttacks`.
            const activity = pieceActivityAndAttacks(Sink, sink, config.piece_detail, value);
            const attack_info = activity.info;
            total.add(activity.value);
            sink.emit("activity", TraceValue{ .tapered = activity.value });

            const passers = passedPawns(Sink, sink, config.pawn_completion, &pawn_evidence.sets, value, attack_info);
            total.add(passers);
            sink.emit("passed", TraceValue{ .tapered = passers });

            const king = if (comptime config.king_safety)
                kingSafety(
                    Sink,
                    sink,
                    config.threat_completion,
                    config.shelter_danger_coupling,
                    value,
                    attack_info,
                )
            else
                Tapered{};
            total.add(king);
            sink.emit("king_safety", TraceValue{ .tapered = king });

            const threats = pawnThreats(Sink, sink, value, attack_info);
            total.add(threats);
            sink.emit("pawn_threats", TraceValue{ .tapered = threats });

            const piece_threats = if (comptime config.threats_and_space)
                threatsAndSpace(
                    Sink,
                    sink,
                    config.threat_completion,
                    config.contextual_space,
                    value,
                    attack_info,
                    placement.phase_value,
                )
            else
                Tapered{};
            total.add(piece_threats);
            sink.emit("threats_space", TraceValue{ .tapered = piece_threats });

            const initiative = if (comptime config.winnability)
                winnability.evaluate(
                    value,
                    pawn_evidence.sets[0].passed | pawn_evidence.sets[1].passed,
                    total.endgame,
                ).adjustment
            else
                0;
            total.endgame += initiative;
            sink.emit("winnability", TraceValue{ .tapered = .{ .endgame = initiative } });

            // Scale the endgame component by how convertible the leading
            // side's edge actually is, before tapering mixes the two halves.
            // The leader is decided from the untapered endgame score, since
            // that is the half being scaled.
            if (comptime config.endgame_scaling) {
                const leader: types.Color = if (total.endgame >= 0) .white else .black;
                const factor = endgameScale(value, leader);
                if (factor != params.scale_normal)
                    total.endgame = @divTrunc(total.endgame * factor, params.scale_normal);
            }

            sink.emit("phase", TraceValue{ .phase = placement.phase_value });
            var white_value = (phase.Phase{
                .current = placement.phase_value,
                .total = params.phase_total,
            }).interpolate(total.middlegame, total.endgame);
            if (comptime config.endgame_knowledge) {
                if (endgame.recognize(value)) |recognized| switch (recognized) {
                    .value => |known| white_value = known.white_value,
                    .scale => |known| {
                        const leader_matches = white_value != 0 and (known.strong_side == null or
                            ((white_value > 0) == (known.strong_side.? == .white)));
                        if (leader_matches)
                            white_value = @divTrunc(white_value * known.factor, endgame.scale_normal);
                    },
                };
            }
            const ordinary = (if (value.side_to_move == .white) white_value else -white_value) + params.tempo;
            fit.record(Sink, sink, "tempo", 0, .final, .scalar, 1);

            // A side that cannot force mate cannot convert an advantage, so the
            // position is worth a draw no matter how much material it counts. This
            // is a rule about what is reachable, not a tuned discount, so the
            // result is exactly zero rather than a scaled remainder. It stays a
            // static judgement: search may still return a mate score when the
            // defender actually walks into one, and that dominates this value.
            const clamped = if (comptime config.insufficient_material)
                clampUnwinnable(value, ordinary)
            else
                ordinary;

            // The fifty-move allowance bounds how long the stronger side has to
            // force a capture or pawn move. As the remaining allowance shrinks,
            // an advantage becomes progressively less convertible.
            const scaled = if (comptime config.rule_fifty_scaling)
                scaleByRuleFifty(clamped, value.current.rule50)
            else
                clamped;

            sink.emit("total", TraceValue{ .total = scaled });

            // Legal material limits keep this far inside the ordinary score band.
            return score.Score.fromOrdinary(scaled) orelse unreachable;
        }
    };
}

/// How convertible the leading side's endgame advantage actually is,
/// expressed as a factor out of `scale_normal`.
///
/// Step 5.3.7 replaces the binary unwinnable clamp with a graded factor. The
/// clamp remains correct for material that cannot force mate, which genuinely
/// is a yes-or-no fact, but most drawish endings are not binary: opposite
/// bishops, a wrong rook pawn or a bare minor edge are all degrees of
/// difficulty rather than certainties. A factor damps the endgame component
/// instead of cliff-edging the final score.
///
/// Only the endgame term is scaled, because every one of these is a statement
/// about conversion rather than about the middlegame position.
fn endgameScale(value: *const position.Position, leader: types.Color) i32 {
    const physical = &value.physical;
    const them = leader.opposite();
    const own_pawns = @popCount(physical.pieces(leader, .pawn));
    const own_bishops = physical.pieces(leader, .bishop);
    const enemy_bishops = physical.pieces(them, .bishop);

    // A wrong rook pawn: the bishop cannot control the promotion square, so
    // the defending king simply sits in the corner.
    if (own_pawns == 1 and @popCount(own_bishops) == 1 and
        physical.pieces(leader, .knight) == 0 and
        physical.pieces(leader, .rook) == 0 and
        physical.pieces(leader, .queen) == 0)
    {
        const pawns = physical.pieces(leader, .pawn);
        const on_rook_file = pawns & (fileMask(0) | fileMask(7)) != 0;
        if (on_rook_file and wrongCornerBishop(leader, pawns, own_bishops))
            return params.scale_wrong_rook_pawn;
    }

    // A material edge with no pawns at all is hard to convert even when mate
    // is theoretically forceable.
    if (own_pawns == 0 and physical.pieces(leader, .rook) == 0 and
        physical.pieces(leader, .queen) == 0)
        return params.scale_no_pawns_minor;

    // Opposite-coloured bishops cannot contest each other's squares.
    if (@popCount(own_bishops) == 1 and @popCount(enemy_bishops) == 1 and
        oppositeColoured(own_bishops, enemy_bishops))
    {
        const heavy = physical.by_type[types.PieceType.rook.index()] |
            physical.by_type[types.PieceType.queen.index()] |
            physical.by_type[types.PieceType.knight.index()];
        return if (heavy == 0)
            params.scale_opposite_bishops
        else
            params.scale_opposite_bishops_pieces;
    }

    // Otherwise conversion gets easier with every pawn that remains.
    const pawnful = params.scale_pawnful_base + params.scale_per_pawn * @as(i32, own_pawns);
    return @min(pawnful, params.scale_normal);
}

/// True when the two bishop boards stand on different square colours.
fn oppositeColoured(a: Bitboard, b: Bitboard) bool {
    const a_light = a & light_squares != 0;
    const b_light = b & light_squares != 0;
    return a_light != b_light;
}

/// True when the bishop does not control the queening square of a rook pawn.
fn wrongCornerBishop(side: types.Color, pawns: Bitboard, bishops: Bitboard) bool {
    const file: types.File = if (pawns & fileMask(0) != 0) .a else .h;
    const promotion_rank: types.Rank = if (side == .white) .eight else .one;
    const promotion = types.Square.make(file, promotion_rank);
    const promotion_light = squareBit(promotion) & light_squares != 0;
    const bishop_light = bishops & light_squares != 0;
    return promotion_light != bishop_light;
}

/// True when `side` has no combination of material that can force mate.
///
/// A pawn can promote, and a rook or queen mates on its own, so any of those
/// leaves mating material. Otherwise only the minor pieces decide it:
///
///   - a lone minor cannot mate at all;
///   - one or two knights cannot force mate, but three can, which is reachable
///     through promotion;
///   - a bishop pair confined to one square colour cannot mate however many
///     bishops there are, since the bare king simply stays on the other colour;
///   - any other combination of two or more minors can mate.
fn lacksMatingMaterial(value: *const position.Position, side: types.Color) bool {
    const physical = &value.physical;
    if (physical.pieces(side, .pawn) != 0) return false;
    if (physical.pieces(side, .rook) != 0) return false;
    if (physical.pieces(side, .queen) != 0) return false;
    const bishop_board = physical.pieces(side, .bishop);
    const bishops = @popCount(bishop_board);
    const knights = @popCount(physical.pieces(side, .knight));
    if (bishops + knights <= 1) return true;
    if (bishops == 0) return knights <= 2;
    // Bishops on a single square colour never cover the other colour, so a
    // bare king is safe there no matter how many bishops or knights assist.
    if (knights == 0 and (bishop_board & light_squares == 0 or bishop_board & dark_squares == 0))
        return true;
    return false;
}

const light_squares: Bitboard = 0x55AA_55AA_55AA_55AA;
const dark_squares: Bitboard = ~light_squares;

/// Zeroes an advantage its holder cannot convert. Only the leading side is
/// examined: the trailing side's material says nothing about whether the
/// position can be won.
fn clampUnwinnable(value: *const position.Position, ordinary: i32) i32 {
    if (ordinary == 0) return 0;
    const leader: types.Color = if ((ordinary > 0) == (value.side_to_move == .white))
        .white
    else
        .black;
    return if (lacksMatingMaterial(value, leader)) 0 else ordinary;
}

/// Scales an ordinary score by the share of the fifty-move allowance that
/// remains, once the allowance is short enough to matter.
fn scaleByRuleFifty(ordinary: i32, rule50: u16) i32 {
    if (rule50 <= rule_fifty_scale_start) return ordinary;
    const clamped_clock = @min(rule50, rule_fifty_limit);
    const remaining: i32 = @intCast(rule_fifty_limit - clamped_clock);
    const window: i32 = @intCast(rule_fifty_limit - rule_fifty_scale_start);
    return @divTrunc(ordinary * remaining, window);
}

const Placement = struct {
    value: Tapered,
    phase_value: u8,
};

fn placementAndPhase(comptime Sink: type, sink: *Sink, value: *const position.Position) Placement {
    var result: Tapered = .{};
    var phase_value: u16 = 0;
    for (value.physical.board, 0..) |piece, square_index| {
        if (piece == .none) continue;
        const piece_type = piece.pieceType();
        const side = piece.color();
        const sign: i32 = if (side == .white) 1 else -1;
        const square = types.Square.fromIndex(@intCast(square_index));
        const relative_square = if (side == .white) square else square.flipRank();
        const type_index = piece_type.index();
        const pst_index = type_index - 1;
        result.middlegame += sign * (@as(i32, params.mg_val[type_index]) +
            params.pst_mg[pst_index][relative_square.index()]);
        result.endgame += sign * (@as(i32, params.eg_val[type_index]) +
            params.pst_eg[pst_index][relative_square.index()]);
        fit.record(Sink, sink, "mg_val", type_index, .material_pst, .middlegame, sign);
        fit.record(Sink, sink, "eg_val", type_index, .material_pst, .endgame, sign);
        fit.record(
            Sink,
            sink,
            "pst_mg",
            pst_index * 64 + relative_square.index(),
            .material_pst,
            .middlegame,
            sign,
        );
        fit.record(
            Sink,
            sink,
            "pst_eg",
            pst_index * 64 + relative_square.index(),
            .material_pst,
            .endgame,
            sign,
        );
        phase_value += params.phase_weight[type_index];
    }
    return .{
        .value = result,
        .phase_value = @intCast(@min(phase_value, params.phase_total)),
    };
}

/// Doubled, isolated, connected, candidate and passed pawns.
///
/// Every one of these is a statement about a *set* of pawns rather than about
/// one pawn at a time. A doubled penalty belongs only to a rear pawn; isolated
/// and backward ownership then excludes it and each other, so the fit is not
/// asked to split one weakness among three coefficients. Connected pawns are
/// those the same side's pawns already defend. Passer loops remain bounded by
/// the number of pawns and reuse the cached classification.
fn pawnStructure(comptime complete: bool, sets: [2]PawnSets, value: *const position.Position) Tapered {
    var result: Tapered = .{};
    inline for (.{ types.Color.white, types.Color.black }) |side| {
        const sign: i32 = if (side == .white) 1 else -1;
        const set = sets[side.index()];
        const enemy = value.physical.pieces(side.opposite(), .pawn);

        result.add(Tapered.scaled(params.doubled, sign * @as(i32, @popCount(set.doubled))));
        result.add(Tapered.scaled(params.isolated, sign * @as(i32, @popCount(set.isolated))));

        if (comptime !complete) {
            result.add(Tapered.scaled(params.connected, sign * @as(i32, @popCount(set.connected))));
            continue;
        }

        // Step 5.3.10. A backward pawn is a lasting weakness; the file being
        // free of enemy pawns makes it a reachable one as well.
        const open_files = ~fileFill(enemy);
        result.add(Tapered.scaled(params.backward, sign * @as(i32, @popCount(set.backward))));
        result.add(Tapered.scaled(
            params.backward_open,
            sign * @as(i32, @popCount(set.backward & open_files)),
        ));
        // Charged to isolated pawns only. Backward pawns already pay the
        // open-file case above, and one signal must not be split in two.
        result.add(Tapered.scaled(
            params.weak_unopposed,
            sign * @as(i32, @popCount(set.isolated & open_files)),
        ));
        result.add(Tapered.scaled(params.weak_lever, sign * @as(i32, @popCount(set.weak_lever))));

        var blocked = set.blocked;
        while (popSquare(&blocked)) |square| {
            const relative_rank = types.relativeRank(side, square.rank()).index();
            if (relative_rank < 4 or relative_rank > 5) continue;
            result.add(Tapered.scaled(params.blocked_pawn[relative_rank - 4], sign));
        }

        // A chain is worth more the further it has advanced, more again when
        // the pawns stand side by side, and less when the file ahead is shut.
        var connected = set.connected | set.phalanx;
        while (popSquare(&connected)) |square| {
            const bit = squareBit(square);
            const relative_rank = types.relativeRank(side, square.rank()).index();
            const phalanx: i32 = if (set.phalanx & bit != 0) 1 else 0;
            const opposed: i32 = if (set.opposed & bit != 0) 1 else 0;
            const weight = 2 + phalanx - opposed;
            result.middlegame += sign * @divTrunc(@as(i32, params.connected_mg[relative_rank]) * weight, 2);
            result.endgame += sign * @divTrunc(@as(i32, params.connected_eg[relative_rank]) * weight, 2);
            const defenders = attacks.pawn[side.opposite().index()][square.index()] & set.own;
            const supports: i32 = @intCast(@popCount(defenders));
            result.add(Tapered.scaled(params.connected_support, sign * supports));
        }
    }
    return result;
}

/// Sparse fitting counts mirror the pawn facts consumed above, but do not
/// recompute the cached score. Component conformance tests compare their dot
/// product with `pawnStructure`; the half-weight connected-rank tables remain
/// excluded because each application truncates independently.
fn recordPawnFeatures(
    comptime Sink: type,
    sink: *Sink,
    comptime complete: bool,
    sets: *const [2]PawnSets,
    value: *const position.Position,
) void {
    inline for (.{ types.Color.white, types.Color.black }) |side| {
        const sign: i32 = if (side == .white) 1 else -1;
        const set = sets[side.index()];
        const enemy = value.physical.pieces(side.opposite(), .pawn);
        fit.tapered(Sink, sink, "doubled", 0, .pawns, sign * @as(i32, @popCount(set.doubled)));
        fit.tapered(Sink, sink, "isolated", 0, .pawns, sign * @as(i32, @popCount(set.isolated)));
        if (comptime !complete) {
            fit.tapered(Sink, sink, "connected", 0, .pawns, sign * @as(i32, @popCount(set.connected)));
            continue;
        }
        const open_files = ~fileFill(enemy);
        fit.tapered(Sink, sink, "backward", 0, .pawns, sign * @as(i32, @popCount(set.backward)));
        fit.tapered(
            Sink,
            sink,
            "backward_open",
            0,
            .pawns,
            sign * @as(i32, @popCount(set.backward & open_files)),
        );
        fit.tapered(
            Sink,
            sink,
            "weak_unopposed",
            0,
            .pawns,
            sign * @as(i32, @popCount(set.isolated & open_files)),
        );
        fit.tapered(Sink, sink, "weak_lever", 0, .pawns, sign * @as(i32, @popCount(set.weak_lever)));
        var blocked = set.blocked;
        while (popSquare(&blocked)) |square| {
            const relative_rank = types.relativeRank(side, square.rank()).index();
            if (relative_rank >= 4 and relative_rank <= 5)
                fit.tapered(Sink, sink, "blocked_pawn", relative_rank - 4, .pawns, sign);
        }
        var connected = set.connected | set.phalanx;
        while (popSquare(&connected)) |square| {
            const defenders = attacks.pawn[side.opposite().index()][square.index()] & set.own;
            fit.tapered(
                Sink,
                sink,
                "connected_support",
                0,
                .pawns,
                sign * @as(i32, @popCount(defenders)),
            );
        }
    }
}

/// Candidate and passed pawns, scored after the shared attack maps exist.
///
/// The rank tables say how far a passer has come. Everything here says whether
/// it can actually go anywhere, which is the question Step 5.3.10 was opened
/// to answer: before it, a passer on the sixth rank blockaded by a knight and
/// hunted by the enemy king scored exactly the same as a free one.
///
/// The stop-square and path terms are charged only from the fourth relative
/// rank, because a passer still on its third has too many intervening moves
/// for the current occupancy to say much, and skipping them keeps the common
/// case cheap.
fn passedPawns(
    comptime Sink: type,
    sink: *Sink,
    comptime complete: bool,
    sets: *const [2]PawnSets,
    value: *const position.Position,
    info: AttackInfo,
) Tapered {
    var result: Tapered = .{};
    inline for (.{ types.Color.white, types.Color.black }) |side| {
        const sign: i32 = if (side == .white) 1 else -1;
        const us = side.index();
        const them = side.opposite().index();
        const occupied = value.physical.occupied();

        if (comptime complete) {
            var candidates = sets[us].candidate;
            while (popSquare(&candidates)) |square| {
                const relative_rank = types.relativeRank(side, square.rank()).index();
                result.middlegame += sign * params.candidate_mg[relative_rank];
                result.endgame += sign * params.candidate_eg[relative_rank];
                fit.record(Sink, sink, "candidate_mg", relative_rank, .passed, .middlegame, sign);
                fit.record(Sink, sink, "candidate_eg", relative_rank, .passed, .endgame, sign);
            }
        }

        var passed = sets[us].passed;
        while (popSquare(&passed)) |square| {
            const relative_rank = types.relativeRank(side, square.rank()).index();
            result.middlegame += sign * params.passed_mg[relative_rank];
            result.endgame += sign * params.passed_eg[relative_rank];
            fit.record(Sink, sink, "passed_mg", relative_rank, .passed, .middlegame, sign);
            fit.record(Sink, sink, "passed_eg", relative_rank, .passed, .endgame, sign);
            if (comptime !complete) continue;

            const file_index = square.file().index();
            const edge_distance = @min(file_index, 7 - file_index);
            result.add(Tapered.scaled(params.passed_file[edge_distance], sign));
            fit.tapered(Sink, sink, "passed_file", edge_distance, .passed, sign);

            if (relative_rank < 3) continue;

            const stop = pawnPush(side, squareBit(square));
            if (stop == 0) continue;
            const stop_square = types.Square.fromIndex(@intCast(@ctz(stop)));

            if (stop & occupied != 0) {
                result.add(Tapered.scaled(params.passed_blocked, sign));
                fit.tapered(Sink, sink, "passed_blocked", 0, .passed, sign);
            }
            if (stop & info.all[them] != 0 and stop & info.all[us] == 0) {
                result.add(Tapered.scaled(params.passed_stop_attacked, sign));
                fit.tapered(Sink, sink, "passed_stop_attacked", 0, .passed, sign);
            }
            if (stop & info.all[us] != 0) {
                result.add(Tapered.scaled(params.passed_stop_defended, sign));
                fit.tapered(Sink, sink, "passed_stop_defended", 0, .passed, sign);
            }

            // Everything between the pawn and promotion. Each square is
            // evidence of its own: one unsafe square does not erase friendly
            // control elsewhere, and several unsafe squares are worse than
            // one. The stop-square terms above remain the immediate-move
            // specialization; these counts describe the complete route.
            const path = if (side == .white)
                northFill(stop)
            else
                southFill(stop);
            const attacked_count: i32 = @intCast(@popCount(path & info.all[them]));
            const defended_count: i32 = @intCast(@popCount(path & info.all[us]));
            result.add(Tapered.scaled(params.passed_path_attacked, sign * attacked_count));
            result.add(Tapered.scaled(params.passed_path_defended, sign * defended_count));
            fit.tapered(Sink, sink, "passed_path_attacked", 0, .passed, sign * attacked_count);
            fit.tapered(Sink, sink, "passed_path_defended", 0, .passed, sign * defended_count);

            // Whose king reaches the stop square first decides a pawn race,
            // and matters more the further the pawn has come. This is an
            // endgame fact: with pieces on, neither king is walking there.
            const advance: i32 = @intCast(relative_rank - 2);
            const our_king = value.physical.king_square[us];
            const their_king = value.physical.king_square[them];
            if (our_king != .none) {
                const count = sign * kingDistance(our_king, stop_square) * advance;
                result.endgame += params.passed_king_own * count;
                fit.record(Sink, sink, "passed_king_own", 0, .passed, .endgame, count);
            }
            if (their_king != .none) {
                const count = sign * kingDistance(their_king, stop_square) * advance;
                result.endgame += params.passed_king_their * count;
                fit.record(Sink, sink, "passed_king_their", 0, .passed, .endgame, count);
            }
        }
    }
    return result;
}

const PawnSets = struct {
    doubled: Bitboard = 0,
    isolated: Bitboard = 0,
    connected: Bitboard = 0,
    passed: Bitboard = 0,
    /// Not passed and not opposed. Every remaining adjacent-file stopper is
    /// attacked now, with at least one distinct friendly pawn per stopper.
    /// This is a leverable majority, not a promise that the exchange wins.
    candidate: Bitboard = 0,
    /// Step 5.3.10. No own pawn on a neighbouring file stands level with this
    /// one or behind it, and an enemy pawn controls the square it must move
    /// to. It cannot advance and no pawn can come to defend it.
    backward: Bitboard = 0,
    /// Attacked by two enemy pawns and defended by none, so the defender
    /// chooses which way to lose it.
    weak_lever: Bitboard = 0,
    /// Standing directly behind an enemy pawn on its own file.
    blocked: Bitboard = 0,
    /// This side's pawns, so a consumer can count defenders of one square
    /// without needing the position again.
    own: Bitboard = 0,
    /// An own pawn stands beside it on the same rank.
    phalanx: Bitboard = 0,
    /// An enemy pawn stands somewhere ahead on its own file.
    opposed: Bitboard = 0,
};

const PawnEvidence = struct {
    sets: [2]PawnSets,
    structure: Tapered,

    fn compute(comptime complete: bool, value: *const position.Position) PawnEvidence {
        const sets = [2]PawnSets{
            pawnSets(
                .white,
                value.physical.pieces(.white, .pawn),
                value.physical.pieces(.black, .pawn),
            ),
            pawnSets(
                .black,
                value.physical.pieces(.black, .pawn),
                value.physical.pieces(.white, .pawn),
            ),
        };
        return .{ .sets = sets, .structure = pawnStructure(complete, sets, value) };
    }
};

/// A full 64-bit pawn key is retained beside every direct-mapped entry, so a
/// collision can only evict evidence; it can never return another position's
/// score. State is concrete and worker-local through the evaluator binding.
const PawnCache = struct {
    const entry_count = 16;
    const Entry = struct {
        valid: bool = false,
        key: types.Key = 0,
        evidence: PawnEvidence = .{ .sets = @splat(.{}), .structure = .{} },
    };

    entries: [entry_count]Entry = @splat(.{}),

    fn get(self: *PawnCache, comptime complete: bool, value: *const position.Position) *const PawnEvidence {
        const key = value.current.pawn_key;
        const index: usize = @intCast(key & (entry_count - 1));
        const entry = &self.entries[index];
        if (!entry.valid or entry.key != key) {
            entry.* = .{
                .valid = true,
                .key = key,
                .evidence = PawnEvidence.compute(complete, value),
            };
        }
        return &entry.evidence;
    }
};

/// Squares one file to either side of the given set, without wrapping.
fn widen(bits: Bitboard) Bitboard {
    return ((bits & ~file_h) << 1) | ((bits & ~file_a) >> 1);
}

/// Every square on a file that holds at least one of the given pieces.
fn fileFill(bits: Bitboard) Bitboard {
    return northFill(bits) | southFill(bits);
}

/// One diagonal pawn step, kept separate so the two can be intersected into
/// the doubly-attacked set a lever test needs.
fn pawnAttackEast(side: types.Color, pawns: Bitboard) Bitboard {
    return if (side == .white) (pawns & ~file_h) << 9 else (pawns & ~file_h) >> 7;
}

fn pawnAttackWest(side: types.Color, pawns: Bitboard) Bitboard {
    return if (side == .white) (pawns & ~file_a) << 7 else (pawns & ~file_a) >> 9;
}

/// One square forward for the given colour.
fn pawnPush(side: types.Color, pawns: Bitboard) Bitboard {
    return if (side == .white) pawns << 8 else pawns >> 8;
}

/// Chebyshev distance, which is how many king moves separate two squares.
fn kingDistance(a: types.Square, b: types.Square) i32 {
    const file_delta = @abs(@as(i32, a.file().index()) - @as(i32, b.file().index()));
    const rank_delta = @abs(@as(i32, a.rank().index()) - @as(i32, b.rank().index()));
    return @intCast(@max(file_delta, rank_delta));
}

/// The pawn-structure sets for one side, from whole-board operations.
fn pawnSets(side: types.Color, own: Bitboard, enemy: Bitboard) PawnSets {
    // Only a rear pawn owns the doubled penalty. The leading pawn retains its
    // normal structural identity and the same file is never charged once per
    // member merely because it contains more than one pawn.
    const doubled = own & (if (side == .white)
        southFill(own >> 8)
    else
        northFill(own << 8));

    // A pawn is isolated when neither neighbouring file holds one of ours at
    // any rank, so the test is against our files smeared sideways by one.
    const own_files = fileFill(own);
    const neighbour_files = widen(own_files);

    // Everything an enemy pawn still commands on the way to promotion: the
    // squares behind it on its own file, widened to both neighbours.
    const enemy_front = if (side == .white) southFill(enemy >> 8) else northFill(enemy << 8);
    const contested = enemy_front |
        ((enemy_front & ~file_h) << 1) | ((enemy_front & ~file_a) >> 1);

    // Step 5.3.10. A pawn is backward when no own pawn on a neighbouring file
    // stands level with it or behind it, so none can ever come up to defend
    // it, and an enemy pawn already controls the square it must move to. The
    // "level or behind" test is our own pawns filled forward and then smeared
    // sideways: a square is covered exactly when a neighbouring-file pawn sits
    // on its rank or a lower one.
    const forward_fill = if (side == .white) northFill(own) else southFill(own);
    const reachable_support = widen(forward_fill);
    const enemy_attacks = pawnAttackSpan(side.opposite(), enemy);
    const stop_denied = if (side == .white) enemy_attacks >> 8 else enemy_attacks << 8;
    const isolated_all = own & ~neighbour_files;
    const backward = own & ~doubled & ~isolated_all & ~reachable_support & stop_denied;

    // Attacked twice by enemy pawns and defended by none of ours.
    const doubly_attacked = pawnAttackEast(side.opposite(), enemy) &
        pawnAttackWest(side.opposite(), enemy);
    const own_attacks = pawnAttackSpan(side, own);
    const weak_lever = own & doubly_attacked & ~own_attacks;

    // Directly behind an enemy pawn on its own file.
    const blocked = own & (if (side == .white) enemy >> 8 else enemy << 8);

    // An enemy pawn stands somewhere ahead on the same file. `enemy_front`
    // already holds exactly those squares before it is widened.
    const opposed = own & enemy_front;
    const passed = own & ~contested;

    // A candidate has no same-file pawn ahead and is held only by adjacent
    // pawns that can be exchanged immediately. Requiring at least as many
    // distinct attackers as stoppers rejects the false two-stoppers/one-pawn
    // case. This bounded per-pawn proof is cached with the other pawn facts.
    var candidate: Bitboard = 0;
    var possible = own & ~passed & ~opposed;
    while (popSquare(&possible)) |square| {
        const stoppers = enemy & passed_mask[side.index()][square.index()] &
            adjacentFiles(square.file().index());
        if (stoppers == 0 or stoppers & ~own_attacks != 0) continue;
        const attackers = own & pawnAttackSpan(side.opposite(), stoppers);
        if (@popCount(attackers) >= @popCount(stoppers)) candidate |= squareBit(square);
    }

    return .{
        .doubled = doubled,
        .isolated = isolated_all & ~doubled,
        .connected = own & own_attacks,
        .passed = passed,
        .candidate = candidate,
        .backward = backward,
        .weak_lever = weak_lever,
        .blocked = blocked,
        .own = own,
        .phalanx = own & widen(own),
        .opposed = opposed,
    };
}

/// Every square on or north of a set bit, along its own file.
fn northFill(initial: Bitboard) Bitboard {
    var bits = initial;
    bits |= bits << 8;
    bits |= bits << 16;
    bits |= bits << 32;
    return bits;
}

/// Every square on or south of a set bit, along its own file.
fn southFill(initial: Bitboard) Bitboard {
    var bits = initial;
    bits |= bits >> 8;
    bits |= bits >> 16;
    bits |= bits >> 32;
    return bits;
}

/// Per-colour attacked-square sets, produced once and consumed by activity,
/// king safety and threats alike.
///
/// Step 5.3.4 exists because these sets are shared evidence: recomputing them
/// inside each consumer would both cost more and let the consumers silently
/// disagree about which squares are attacked. `by_two` records squares a side
/// attacks more than once, which is what distinguishes a defended square from
/// a merely touched one.
pub const AttackInfo = struct {
    all: [2]Bitboard = @splat(0),
    two: [2]Bitboard = @splat(0),
    by_type: [2][7]Bitboard = @splat(@splat(0)),
    king_ring: [2]Bitboard = @splat(0),
    attackers: [2]u8 = @splat(0),
    attack_weight: [2]i32 = @splat(0),

    fn note(
        self: *AttackInfo,
        side: types.Color,
        piece_type: types.PieceType,
        squares: Bitboard,
    ) void {
        const index = side.index();
        self.two[index] |= self.all[index] & squares;
        self.all[index] |= squares;
        self.by_type[index][piece_type.index()] |= squares;
    }
};

/// The squares immediately around a king, which is where an attack has to
/// arrive. The ring is pulled back from the board edge so a cornered king is
/// not credited with safety it does not have.
fn kingRing(square: types.Square) Bitboard {
    var ring = attacks.king[square.index()] | squareBit(square);
    const file = square.file().index();
    if (file == 0) ring |= ring << 1 else if (file == 7) ring |= ring >> 1;
    return ring;
}

fn squareBit(square: types.Square) Bitboard {
    return @as(Bitboard, 1) << @intCast(square.index());
}

/// Restrict geometric reach to moves that do not expose the moving side's
/// king. A pinned knight has no legal destination; a pinned slider or pawn may
/// retain only squares on the king/piece line. Raw x-ray relations are derived
/// separately by their owning features and never masquerade as legal control.
fn legalReach(
    piece_type: types.PieceType,
    square: types.Square,
    reach: Bitboard,
    pinned: Bitboard,
    king_square: types.Square,
) Bitboard {
    if (pinned & squareBit(square) == 0 or king_square == .none) return reach;
    if (piece_type == .knight) return 0;
    return reach & attacks.line[king_square.index()][square.index()];
}

fn legalPawnAttacks(
    side: types.Color,
    pawns: Bitboard,
    pinned: Bitboard,
    king_square: types.Square,
) Bitboard {
    var result = pawnAttackSpan(side, pawns & ~pinned);
    var constrained = pawns & pinned;
    while (popSquare(&constrained)) |square| {
        result |= legalReach(
            .pawn,
            square,
            attacks.pawn[side.index()][square.index()],
            pinned,
            king_square,
        );
    }
    return result;
}

/// The shared attack maps together with the piece-activity score.
const Activity = struct {
    info: AttackInfo = .{},
    value: Tapered = .{},
};

/// Builds the shared attack sets, the king-attack tallies that 5.3.5 reads and
/// the mobility, outpost and rook-file terms, in one pass over the pieces.
///
/// Step 5.3.8 fuses these because they consume the same fact. The squares a
/// piece reaches under the current occupancy answer both "how much can this
/// piece do" and "which squares does this side hold", so computing them in
/// separate passes paid the sliding lookup — the most expensive operation in
/// the evaluator — twice for every slider on the board. Nothing about the
/// chess meaning of either term changes: the score is identical term by term.
fn pieceActivityAndAttacks(
    comptime Sink: type,
    sink: *Sink,
    comptime detail: bool,
    value: *const position.Position,
) Activity {
    var result: Activity = .{};
    const info = &result.info;
    const occupied = value.physical.occupied();

    // Pawn spans and king rings are inputs to the piece loop of the *other*
    // side, so both sides' copies must exist before that loop starts.
    var pawn_span: [2]Bitboard = @splat(0);
    var pinned: [2]Bitboard = @splat(0);
    inline for (.{ types.Color.white, types.Color.black }) |side| {
        const king_square = value.physical.king_square[side.index()];
        if (king_square != .none) {
            info.king_ring[side.index()] = kingRing(king_square);
            pinned[side.index()] = kingBlockers(value, side, king_square);
        }
        const pawns = value.physical.pieces(side, .pawn);
        pawn_span[side.index()] = pawnAttackSpan(side, pawns);

        const legal_pawn_attacks = legalPawnAttacks(side, pawns, pinned[side.index()], king_square);
        info.note(side, .pawn, legal_pawn_attacks);
    }

    inline for (.{ types.Color.white, types.Color.black }) |side| {
        const index = side.index();
        const sign: i32 = if (side == .white) 1 else -1;
        const king_square = value.physical.king_square[index];
        if (king_square != .none) info.note(side, .king, attacks.king[king_square.index()]);
        const enemy_ring = info.king_ring[side.opposite().index()];

        const own = value.physical.by_color[index];
        const own_pawns = value.physical.pieces(side, .pawn);
        const enemy_pawns = value.physical.pieces(side.opposite(), .pawn);
        const enemy_pawn_attacks = pawn_span[side.opposite().index()];
        const all_pawns = value.physical.by_type[types.PieceType.pawn.index()];
        const all_queens = value.physical.by_type[types.PieceType.queen.index()];
        const enemy_span_all = pawnAttackSpanAll(side.opposite(), enemy_pawns);
        const low_pawn_ranks: Bitboard = if (side == .white)
            (@as(Bitboard, 0xff) << 8) | (@as(Bitboard, 0xff) << 16)
        else
            (@as(Bitboard, 0xff) << 40) | (@as(Bitboard, 0xff) << 48);
        const blocked_pawns = own_pawns & pawnPush(side.opposite(), occupied);
        const mobility_area = ~(enemy_pawn_attacks | blocked_pawns |
            (own_pawns & low_pawn_ranks) |
            value.physical.pieces(side, .king) |
            value.physical.pieces(side, .queen));
        // Relative ranks four to six: far enough to be an outpost, near enough
        // that a pawn could still have contested it.
        const outpost_ranks: Bitboard = if (side == .white)
            (@as(Bitboard, 0xff) << 24) | (@as(Bitboard, 0xff) << 32) | (@as(Bitboard, 0xff) << 40)
        else
            (@as(Bitboard, 0xff) << 16) | (@as(Bitboard, 0xff) << 24) | (@as(Bitboard, 0xff) << 32);

        if (@popCount(value.physical.pieces(side, .bishop)) >= 2) {
            result.value.add(Tapered.scaled(params.bishop_pair, sign));
            fit.tapered(Sink, sink, "bishop_pair", 0, .activity, sign);
        }

        inline for (.{ types.PieceType.knight, types.PieceType.bishop, types.PieceType.rook, types.PieceType.queen }) |piece_type| {
            var pieces = value.physical.pieces(side, piece_type);
            while (popSquare(&pieces)) |square| {
                const raw_reach = attacks.forPiece(piece_type, side, square, occupied);
                const reach = legalReach(piece_type, square, raw_reach, pinned[index], king_square);
                info.note(side, piece_type, reach);
                // A piece counts as an attacker once, however many ring
                // squares it covers: pressure comes from distinct attackers.
                if (reach & enemy_ring != 0) {
                    info.attackers[index] += 1;
                    info.attack_weight[index] += params.king_attack_weight[piece_type.index()];
                }

                // Mobility counts squares the piece may actually use: its own
                // men block it and an enemy pawn guards the square against it.
                const destinations = reach & ~own & mobility_area;
                const mobility: usize = @intCast(@popCount(destinations));
                result.value.add(mobilityValue(Sink, sink, piece_type, mobility, sign));

                if (piece_type == .rook) {
                    const file_pawns = all_pawns & fileMask(square.file().index());
                    if (file_pawns == 0) {
                        result.value.add(Tapered.scaled(params.rook_open, sign));
                        fit.tapered(Sink, sink, "rook_open", 0, .activity, sign);
                    } else if (own_pawns & fileMask(square.file().index()) == 0) {
                        result.value.add(Tapered.scaled(params.rook_semi_open, sign));
                        fit.tapered(Sink, sink, "rook_semi_open", 0, .activity, sign);
                    }
                    if (types.relativeRank(side, square.rank()) == .seven) {
                        result.value.add(Tapered.scaled(params.rook_seventh, sign));
                        fit.tapered(Sink, sink, "rook_seventh", 0, .activity, sign);
                    }
                }

                if (comptime detail) {
                    const bit = squareBit(square);
                    const minor: usize = if (piece_type == .bishop) 1 else 0;

                    // A piece that already attacks the ring is counted as an
                    // attacker above; this is the pressure a piece applies
                    // from outside, through pawns it would pass once the
                    // position opens.
                    if (reach & enemy_ring == 0) {
                        if (piece_type == .rook) {
                            if (fileMask(square.file().index()) & enemy_ring != 0) {
                                result.value.add(Tapered.scaled(params.rook_on_king_ring, sign));
                                fit.tapered(Sink, sink, "rook_on_king_ring", 0, .activity, sign);
                            }
                        } else if (piece_type == .bishop) {
                            if (attacks.forPiece(.bishop, side, square, all_pawns) & enemy_ring != 0) {
                                result.value.add(Tapered.scaled(params.bishop_on_king_ring, sign));
                                fit.tapered(Sink, sink, "bishop_on_king_ring", 0, .activity, sign);
                            }
                        }
                    }

                    if (piece_type == .knight or piece_type == .bishop) {
                        // An outpost is a square our pawn defends that no
                        // enemy pawn can ever attack, now or after advancing.
                        const outposts = outpost_ranks & pawn_span[index] & ~enemy_span_all;
                        const targets = value.physical.by_color[side.opposite().index()] & ~all_pawns;
                        const wing: Bitboard = if (bit & queen_side != 0) queen_side else king_side;

                        if (piece_type == .knight and
                            outposts & bit != 0 and
                            bit & centre_files == 0 and
                            reach & targets == 0 and
                            @popCount(targets & wing) <= 1)
                        {
                            // Well placed and with nothing to do, which is not
                            // the same as well placed.
                            result.value.add(Tapered.scaled(params.bad_outpost, sign));
                            fit.tapered(Sink, sink, "bad_outpost", 0, .activity, sign);
                        } else if (outposts & bit != 0) {
                            result.value.add(Tapered.scaled(params.outpost[minor], sign));
                            fit.tapered(Sink, sink, "outpost", minor, .activity, sign);
                        } else if (piece_type == .knight and outposts & reach & ~own != 0) {
                            result.value.add(Tapered.scaled(params.reachable_outpost, sign));
                            fit.tapered(Sink, sink, "reachable_outpost", 0, .activity, sign);
                        }

                        // A pawn of either colour directly in front shields it.
                        if (all_pawns & pawnPush(side, bit) != 0) {
                            result.value.add(Tapered.scaled(params.minor_behind_pawn, sign));
                            fit.tapered(Sink, sink, "minor_behind_pawn", 0, .activity, sign);
                        }

                        if (king_square != .none) {
                            result.value.add(Tapered.scaled(
                                params.king_protector[minor],
                                sign * kingDistance(king_square, square),
                            ));
                            fit.tapered(
                                Sink,
                                sink,
                                "king_protector",
                                minor,
                                .activity,
                                sign * kingDistance(king_square, square),
                            );
                        }

                        if (piece_type == .bishop) {
                            // Our pawns on the bishop's own square colour are
                            // the ones it can never defend or pass. It matters
                            // more when the bishop is outside its own pawn
                            // chain and when the centre is locked.
                            const same_colour: Bitboard =
                                if (bit & light_squares != 0) light_squares else dark_squares;
                            const on_colour: i32 = @intCast(@popCount(own_pawns & same_colour));
                            const blocked = own_pawns & pawnPush(side.opposite(), occupied);
                            const outside_chain: i32 = if (pawn_span[index] & bit != 0) 0 else 1;
                            const weight = outside_chain + @as(i32, @intCast(@popCount(blocked & centre_files)));
                            const bishop_pawn_count = sign * on_colour * weight;
                            result.value.add(Tapered.scaled(params.bishop_pawns, bishop_pawn_count));
                            fit.tapered(Sink, sink, "bishop_pawns", 0, .activity, bishop_pawn_count);

                            // Enemy pawns on its diagonals as if the board were
                            // empty: the ones it will still face once it opens.
                            const open_diagonals = attacks.forPiece(.bishop, side, square, 0);
                            const xray_count = sign * @as(i32, @intCast(@popCount(open_diagonals & enemy_pawns)));
                            result.value.add(Tapered.scaled(params.bishop_xray_pawns, xray_count));
                            fit.tapered(Sink, sink, "bishop_xray_pawns", 0, .activity, xray_count);

                            if (@popCount(attacks.forPiece(.bishop, side, square, all_pawns) & centre_squares) > 1) {
                                result.value.add(Tapered.scaled(params.long_diagonal_bishop, sign));
                                fit.tapered(Sink, sink, "long_diagonal_bishop", 0, .activity, sign);
                            }
                        }
                    }

                    if (piece_type == .rook) {
                        if (fileMask(square.file().index()) & all_queens != 0) {
                            result.value.add(Tapered.scaled(params.rook_on_queen_file, sign));
                            fit.tapered(Sink, sink, "rook_on_queen_file", 0, .activity, sign);
                        }

                        // Only a rook that is not already on a semi-open file
                        // can be trapped: the open file is the escape.
                        if (own_pawns & fileMask(square.file().index()) != 0 and
                            mobility <= params.trapped_rook_mobility and
                            king_square != .none)
                        {
                            const king_file = king_square.file().index();
                            const rook_file = square.file().index();
                            // The rook is shut in on the same side the king
                            // occupies, so the king is what blocks it.
                            if ((king_file < 4) == (rook_file < king_file)) {
                                const raw = value.current.castling_rights.raw();
                                const mask: u4 = if (side == .white) 0b0011 else 0b1100;
                                const factor: i32 = if (raw & mask == 0) 2 else 1;
                                result.value.add(Tapered.scaled(params.trapped_rook, sign * factor));
                                fit.tapered(Sink, sink, "trapped_rook", 0, .activity, sign * factor);
                            }
                        }
                    }

                    if (piece_type == .queen) {
                        // A relative pin or a discovered attack waiting to
                        // happen ties the queen to whatever stands in the way.
                        const enemy_rooks = value.physical.pieces(side.opposite(), .rook);
                        const enemy_bishops = value.physical.pieces(side.opposite(), .bishop);
                        if (xrayedBy(.rook, square, occupied, enemy_rooks) or
                            xrayedBy(.bishop, square, occupied, enemy_bishops))
                        {
                            result.value.add(Tapered.scaled(params.weak_queen, sign));
                            fit.tapered(Sink, sink, "weak_queen", 0, .activity, sign);
                        }

                        if (types.relativeRank(side, square.rank()).index() > 3 and
                            enemy_span_all & bit == 0)
                        {
                            result.value.add(Tapered.scaled(params.queen_infiltration, sign));
                            fit.tapered(Sink, sink, "queen_infiltration", 0, .activity, sign);
                        }
                    }
                }
            }
        }
    }
    return result;
}

/// Shelter and storm for one king, summed over its own file and neighbours.
///
/// The chess fact is that a king is safe behind unmoved pawns and unsafe when
/// enemy pawns advance to prise them open, so both are measured by rank
/// distance from the king. A file with no pawn of either colour is separately
/// penalised, because heavy pieces enter there regardless of pawn structure.
/// This is computed on the pawn side because it is a property of pawn
/// structure; king safety consumes it.
fn kingShelter(
    comptime Sink: type,
    sink: *Sink,
    value: *const position.Position,
    side: types.Color,
    king_square: types.Square,
    perspective_sign: i32,
) Tapered {
    if (king_square == .none) return .{};
    var result: Tapered = .{};
    const own_pawns = value.physical.pieces(side, .pawn);
    const enemy_pawns = value.physical.pieces(side.opposite(), .pawn);
    const king_file: i32 = @intCast(king_square.file().index());
    const centre = @min(@max(king_file, 1), 6);

    var offset: i32 = -1;
    while (offset <= 1) : (offset += 1) {
        const file: u3 = @intCast(centre + offset);
        const mask = fileMask(file);
        const own_on_file = own_pawns & mask;
        const enemy_on_file = enemy_pawns & mask;

        const own_distance = nearestPawnDistance(side, king_square, own_on_file);
        const enemy_distance = nearestPawnDistance(side, king_square, enemy_on_file);
        const file_distance: usize = if (file == king_square.file().index()) 0 else 1;
        result.middlegame += params.shelter_rank[file_distance][own_distance];
        fit.record(
            Sink,
            sink,
            "shelter_rank",
            file_distance * 8 + own_distance,
            .king_safety,
            .middlegame,
            perspective_sign,
        );

        // A storming pawn that has run into ours is blocked and much less
        // dangerous than one with a clear path, so it is scored separately.
        if (enemy_distance != 0 and own_distance != 0 and enemy_distance == own_distance + 1) {
            result.middlegame += params.storm_blocked[enemy_distance];
            fit.record(Sink, sink, "storm_blocked", enemy_distance, .king_safety, .middlegame, perspective_sign);
        } else {
            result.middlegame += params.storm_rank[enemy_distance];
            fit.record(Sink, sink, "storm_rank", enemy_distance, .king_safety, .middlegame, perspective_sign);
        }

        if (own_on_file == 0) {
            if (enemy_on_file == 0) {
                result.add(.{ .middlegame = params.king_open_file[0], .endgame = params.king_open_file[1] });
                fit.tapered(Sink, sink, "king_open_file", 0, .king_safety, perspective_sign);
            } else {
                result.add(.{ .middlegame = params.king_semi_open_file[0], .endgame = params.king_semi_open_file[1] });
                fit.tapered(Sink, sink, "king_semi_open_file", 0, .king_safety, perspective_sign);
            }
        }
    }
    return result;
}

/// Rank distance from the king to the nearest pawn on `file_pawns` standing in
/// front of it. Zero means the file holds no such pawn, which the tables treat
/// as the missing-pawn case rather than as distance zero.
///
/// Pawns on one file are ordered by rank, so the nearest one ahead is the
/// first set bit in the king's own direction of play rather than the smallest
/// of a scanned set.
fn nearestPawnDistance(side: types.Color, king_square: types.Square, file_pawns: Bitboard) u3 {
    const king_rank: u6 = @intCast(king_square.rank().index());
    const ahead = if (side == .white) ranksAbove(king_rank) else ranksBelow(king_rank);
    const candidates = file_pawns & ahead;
    if (candidates == 0) return 0;
    const nearest: u6 = if (side == .white)
        @intCast(@ctz(candidates))
    else
        @intCast(63 - @clz(candidates));
    const pawn_rank = nearest >> 3;
    const distance = if (side == .white) pawn_rank - king_rank else king_rank - pawn_rank;
    return @intCast(distance);
}

/// Every square strictly north of the given rank.
fn ranksAbove(rank: u6) Bitboard {
    if (rank == 7) return 0;
    return ~ranksBelow(rank + 1);
}

/// Every square strictly south of the given rank.
fn ranksBelow(rank: u6) Bitboard {
    if (rank == 0) return 0;
    return (@as(Bitboard, 1) << @intCast(@as(u7, rank) * 8)) - 1;
}

/// The band of files a king on `file` must watch. The centre files count as
/// one flank because a king there is exposed from both sides, and the edge
/// files borrow their neighbour rather than pretend the board continues.
fn kingFlank(file: u3) Bitboard {
    const queen_side_files = file_a | (file_a << 1) | (file_a << 2) | (file_a << 3);
    const king_side_files = (file_a << 4) | (file_a << 5) | (file_a << 6) | (file_a << 7);
    return switch (file) {
        0 => queen_side_files & ~(file_a << 3),
        1, 2 => queen_side_files,
        3, 4 => centre_files,
        5, 6 => king_side_files,
        7 => king_side_files & ~(file_a << 4),
    };
}

/// Our own pieces standing between our king and an enemy slider that would
/// otherwise attack it. They cannot leave without exposing the king, so they
/// are not free to defend it either.
///
/// This is computed here rather than borrowed from move generation, because
/// evaluation must not depend on the generator; it reads the same attack
/// tables and nothing else.
fn kingBlockers(value: *const position.Position, side: types.Color, king_square: types.Square) Bitboard {
    const them = side.opposite();
    const occupied = value.physical.occupied();
    var candidates = (attacks.bishop_rays[king_square.index()] &
        (value.physical.pieces(them, .bishop) | value.physical.pieces(them, .queen))) |
        (attacks.rook_rays[king_square.index()] &
            (value.physical.pieces(them, .rook) | value.physical.pieces(them, .queen)));
    var blockers: Bitboard = 0;
    while (popSquare(&candidates)) |slider| {
        const between = attacks.between[king_square.index()][slider.index()] & occupied;
        if (@popCount(between) == 1 and between & value.physical.by_color[side.index()] != 0)
            blockers |= between;
    }
    return blockers;
}

/// King safety for both sides, from the shared attack maps plus shelter.
///
/// The chess reasoning is that danger is superlinear in the number of distinct
/// attackers: one piece near a king is an inconvenience, three co-ordinated
/// pieces are usually decisive. Accumulated danger is therefore squared before
/// it becomes a score, which is the shape that fact demands. A lone attacker
/// is ignored entirely, because a single piece cannot mate a defended king and
/// crediting it would make every developing move look threatening.
///
/// A check that lands on a square the defender does not control is weighted
/// far above one that can simply be captured, since only the former forces the
/// king to move.
fn kingSafety(
    comptime Sink: type,
    sink: *Sink,
    comptime complete: bool,
    comptime shelter_danger_coupling: bool,
    value: *const position.Position,
    info: AttackInfo,
) Tapered {
    var result: Tapered = .{};
    inline for (.{ types.Color.white, types.Color.black }) |side| {
        const sign: i32 = if (side == .white) 1 else -1;
        const side_value = kingSafetyFor(
            Sink,
            sink,
            complete,
            shelter_danger_coupling,
            value,
            info,
            side,
            sign,
        );
        result.middlegame += sign * side_value.middlegame;
        result.endgame += sign * side_value.endgame;
    }
    return result;
}

/// King safety from one side's point of view, returned unsigned so the caller
/// owns the perspective. A positive result means this king is comfortable.
fn kingSafetyFor(
    comptime Sink: type,
    sink: *Sink,
    comptime complete: bool,
    comptime shelter_danger_coupling: bool,
    value: *const position.Position,
    info: AttackInfo,
    side: types.Color,
    perspective_sign: i32,
) Tapered {
    const defender = side.index();
    const attacker = side.opposite().index();
    const king_square = value.physical.king_square[defender];
    if (king_square == .none) return .{};

    // Shelter is a standing property of the position and applies whether or
    // not pieces are currently attacking.
    const shelter = kingShelter(Sink, sink, value, side, king_square, perspective_sign);
    var result = shelter;

    const non_pawn_non_king = value.physical.occupied() &
        ~value.physical.by_type[types.PieceType.pawn.index()] &
        ~value.physical.by_type[types.PieceType.king.index()];
    if (comptime complete) {
        if (@popCount(non_pawn_non_king) <= 4) {
            var own_pawns = value.physical.pieces(side, .pawn);
            var distance_sum: i32 = 0;
            while (popSquare(&own_pawns)) |pawn| distance_sum += kingDistance(king_square, pawn);
            result.endgame += params.king_pawn_proximity * distance_sum;
            fit.record(
                Sink,
                sink,
                "king_pawn_proximity",
                0,
                .king_safety,
                .endgame,
                perspective_sign * distance_sum,
            );
        }
    }

    // The flank facts do not need an attack in progress. A king whose flank
    // holds no pawn at all has nothing to hide behind, and squares the enemy
    // holds on that flank restrict the defender whether or not they ever
    // become an attack. Both are therefore charged before the attacker test.
    var flank_attack: i32 = 0;
    if (comptime complete) {
        const flank = kingFlank(king_square.file().index());
        const camp: Bitboard = if (side == .white)
            0x0000_00FF_FFFF_FFFF
        else
            0xFFFF_FFFF_FF00_0000;
        const held = info.all[attacker] & flank & camp;
        const held_twice = held & info.two[attacker];
        flank_attack = @intCast(@popCount(held) + @popCount(held_twice));

        result.add(Tapered.scaled(params.flank_attacks, -flank_attack));
        fit.tapered(Sink, sink, "flank_attacks", 0, .king_safety, perspective_sign * -flank_attack);
        if (value.physical.by_type[types.PieceType.pawn.index()] & flank == 0) {
            result.add(Tapered.scaled(params.pawnless_flank, 1));
            fit.tapered(Sink, sink, "pawnless_flank", 0, .king_safety, perspective_sign);
        }
    }

    const attacking_pawns = value.physical.pieces(side.opposite(), .pawn);
    const attacking_king = value.physical.king_square[attacker];
    const pinned_attackers = if (attacking_king == .none)
        0
    else
        kingBlockers(value, side.opposite(), attacking_king);
    const possible_pawn_attackers = attacking_pawns & pawnAttackSpan(side, info.king_ring[defender]);
    var pawn_attackers: i32 = @intCast(@popCount(possible_pawn_attackers & ~pinned_attackers));
    var constrained_pawns = possible_pawn_attackers & pinned_attackers;
    while (popSquare(&constrained_pawns)) |pawn| {
        const pawn_reach = legalReach(
            .pawn,
            pawn,
            attacks.pawn[side.opposite().index()][pawn.index()],
            pinned_attackers,
            attacking_king,
        );
        if (info.king_ring[defender] & pawn_reach != 0)
            pawn_attackers += 1;
    }
    const attacker_count = @as(i32, info.attackers[attacker]) + pawn_attackers;
    // One attacker cannot break a defended king, so danger starts at two.
    if (attacker_count < 2) return result;

    const occupied = value.physical.occupied();
    var danger: i32 = info.attack_weight[attacker];
    danger += params.king_pawn_attack_weight * pawn_attackers;
    if (value.physical.pieces(side.opposite(), .queen) == 0) danger -= params.king_no_queen_relief;
    if (value.physical.pieces(side, .queen) != 0) danger -= params.king_defender_queen_relief;

    // Ring squares the attacker hits and the defender does not hold twice are
    // where an invasion actually lands.
    const ring = info.king_ring[defender];
    const weak = ring & info.all[attacker] & ~info.two[defender];
    danger += @as(i32, params.king_ring_weak) * @popCount(weak);

    // Squares from which each piece type would give check, split by whether
    // the defender controls them.
    const safe = ~value.physical.by_color[attacker] & ~info.all[defender];
    const rook_rays = attacks.forPiece(.rook, side, king_square, occupied);
    const bishop_rays = attacks.forPiece(.bishop, side, king_square, occupied);
    const knight_rays = attacks.forPiece(.knight, side, king_square, occupied);
    danger += checkDanger(.queen, (rook_rays | bishop_rays) & info.by_type[attacker][types.PieceType.queen.index()], safe);
    danger += checkDanger(.rook, rook_rays & info.by_type[attacker][types.PieceType.rook.index()], safe);
    danger += checkDanger(.bishop, bishop_rays & info.by_type[attacker][types.PieceType.bishop.index()], safe);
    danger += checkDanger(.knight, knight_rays & info.by_type[attacker][types.PieceType.knight.index()], safe);

    if (comptime complete) {
        // A piece pinned in front of our own king cannot step aside to defend
        // it, so every such blocker is standing danger.
        const blockers = kingBlockers(value, side, king_square);
        danger += params.king_blocker_danger * @as(i32, @intCast(@popCount(blockers)));
        // Flank pressure grows superlinearly for the same reason the rest of
        // danger does, and the defender's own hold on the flank offsets it.
        const flank = kingFlank(king_square.file().index());
        const camp: Bitboard = if (side == .white)
            0x0000_00FF_FFFF_FFFF
        else
            0xFFFF_FFFF_FF00_0000;
        const defended_flank: i32 = @intCast(@popCount(info.all[defender] & flank & camp));
        danger += @divTrunc(params.king_flank_attack_danger * flank_attack * flank_attack, 8);
        danger -= params.king_flank_defense_danger * defended_flank;
    }

    if (comptime shelter_danger_coupling) {
        const raw_danger = danger;
        danger = shelterModeratedDanger(raw_danger, shelter.middlegame);
        // Candidate-only diagnostics expose the producer, input and result to
        // bounded trace sinks. The production Disabled sink compiles away.
        sink.emit("shelter_danger_raw", TraceValue{ .total = raw_danger });
        sink.emit("shelter_danger_shelter", TraceValue{ .total = shelter.middlegame });
        sink.emit("shelter_danger_effective", TraceValue{ .total = danger });
    }
    if (danger <= 0) return result;
    // The square law is the mechanism: doubling the pressure roughly
    // quadruples the penalty. Only the middlegame is charged, because a king
    // with few enemy pieces left is an asset rather than a liability.
    if (comptime shelter_danger_coupling) {
        const penalty = @divTrunc(
            @as(i64, danger) * @as(i64, danger),
            @as(i64, params.king_danger_divisor),
        );
        result.middlegame -= @intCast(penalty);
    } else {
        result.middlegame -= @divTrunc(danger * danger, params.king_danger_divisor);
    }
    return result;
}

/// MAN-E21's only transformation. Widening makes the subtraction defined for
/// every i32 input; actual evaluator bounds keep the result representable.
fn shelterModeratedDanger(raw_danger: i32, shelter_middlegame: i32) i32 {
    const effective = @max(
        @as(i64, 0),
        @as(i64, raw_danger) - @as(i64, shelter_middlegame),
    );
    return @intCast(effective);
}

/// Weighs the checking squares a piece type can reach, separating those the
/// defender does not control from those it does.
fn checkDanger(comptime piece_type: types.PieceType, checks: Bitboard, safe: Bitboard) i32 {
    if (checks == 0) return 0;
    const safe_checks = @popCount(checks & safe);
    const unsafe_checks = @popCount(checks & ~safe);
    return @as(i32, params.safe_check_weight[piece_type.index()]) * safe_checks +
        @as(i32, params.unsafe_check_weight) * unsafe_checks;
}

/// Piece threats and space, both read from the shared 5.3.4 attack maps.
///
/// A threat is a piece the opponent attacks and we do not adequately defend.
/// The chess content is that such a piece must move, be defended or be lost,
/// and each of those costs something; the cost scales with the value of the
/// piece under fire and with how cheap the attacker is. A piece with no
/// defender at all is worse still, because the opponent chooses the moment.
///
/// Space counts squares in our own half that we control and the opponent does
/// not, which is only meaningful while enough material remains to use them; in
/// a bare endgame extra squares are not an asset, so the term switches off.
fn threatsAndSpace(
    comptime Sink: type,
    sink: *Sink,
    comptime complete: bool,
    comptime contextual_space: bool,
    value: *const position.Position,
    info: AttackInfo,
    phase_value: u8,
) Tapered {
    var result: Tapered = .{};
    const central_locks: u8 = if (comptime contextual_space) centralLocks(value) else 0;
    inline for (.{ types.Color.white, types.Color.black }) |side| {
        const sign: i32 = if (side == .white) 1 else -1;
        const us = side.index();
        const them = side.opposite().index();
        const enemy = value.physical.by_color[them];

        const defended = info.all[them];
        // Pawn protection, or a defence-count surplus, makes a target costly
        // to challenge. Other defended targets remain contestable when the
        // attacker can match their support.
        const strongly_protected = info.by_type[them][types.PieceType.pawn.index()] |
            (info.two[them] & ~info.two[us]);
        const minor_attacks = info.by_type[us][types.PieceType.knight.index()] |
            info.by_type[us][types.PieceType.bishop.index()];
        const rook_attacks = info.by_type[us][types.PieceType.rook.index()];

        inline for (.{ types.PieceType.pawn, types.PieceType.knight, types.PieceType.bishop, types.PieceType.rook, types.PieceType.queen }) |target| {
            const targets = enemy & value.physical.by_type[target.index()] & ~strongly_protected;
            const by_minor = @popCount(targets & minor_attacks);
            const by_rook = @popCount(targets & rook_attacks);
            const minor_count = sign * @as(i32, by_minor);
            const rook_count = sign * @as(i32, by_rook);
            result.add(Tapered.scaled(params.threat_by_minor[target.index()], minor_count));
            result.add(Tapered.scaled(params.threat_by_rook[target.index()], rook_count));
            fit.tapered(Sink, sink, "threat_by_minor", target.index(), .threats_space, minor_count);
            fit.tapered(Sink, sink, "threat_by_rook", target.index(), .threats_space, rook_count);
        }

        // Undefended enemy pieces we attack at all.
        const non_pawn = enemy & ~value.physical.by_type[types.PieceType.pawn.index()];
        const loose = non_pawn & info.all[us] & ~defended;
        const hanging_count = sign * @as(i32, @popCount(loose));
        result.add(Tapered.scaled(params.hanging, hanging_count));
        fit.tapered(Sink, sink, "hanging", 0, .threats_space, hanging_count);

        // The king may only take what the defender does not cover.
        const king_targets = non_pawn & info.by_type[us][types.PieceType.king.index()] & ~defended;
        const king_count = sign * @as(i32, @popCount(king_targets));
        result.add(Tapered.scaled(params.threat_by_king, king_count));
        fit.tapered(Sink, sink, "threat_by_king", 0, .threats_space, king_count);

        const safe_area = ~info.by_type[them][types.PieceType.pawn.index()];

        if (comptime complete) {
            // Squares the enemy holds so firmly that attacking them buys
            // nothing: a pawn defends them, or they are defended twice and we
            // do not contest them twice.
            const weak = enemy & ~strongly_protected & info.all[us];

            // A weak piece whose only defender is the queen is barely defended:
            // the queen cannot accept the trade that defence implies. This is
            // disjoint from the hanging term above, which prices pieces with no
            // defender at all.
            const weak_queen_count = sign * @as(i32, @intCast(@popCount(
                weak & info.by_type[them][types.PieceType.queen.index()],
            )));
            result.add(Tapered.scaled(params.weak_queen_protection, weak_queen_count));
            fit.tapered(Sink, sink, "weak_queen_protection", 0, .threats_space, weak_queen_count);

            // Enemy pieces whose squares we contest without their being
            // strongly held. This prices restriction of movement rather than
            // any capture, so it counts squares and not material.
            const restricted = info.all[them] & ~strongly_protected & info.all[us];
            const restricted_count = sign * @as(i32, @intCast(@popCount(restricted)));
            result.add(Tapered.scaled(params.restricted_piece, restricted_count));
            fit.tapered(Sink, sink, "restricted_piece", 0, .threats_space, restricted_count);

            // A square is safe for us when the enemy does not hold it or we
            // hold it too.
            const safe = ~info.all[them] | info.all[us];

            // A pawn standing safely and attacking a piece: the opponent must
            // answer, and no attacker is cheaper.
            const safe_pawns = value.physical.pieces(side, .pawn) & safe;
            const king_square = value.physical.king_square[us];
            const pinned_pawns = if (king_square == .none) 0 else kingBlockers(value, side, king_square);
            const safe_pawn_count = sign * @as(i32, @intCast(@popCount(
                legalPawnAttacks(side, safe_pawns, pinned_pawns, king_square) & non_pawn,
            )));
            result.add(Tapered.scaled(params.threat_by_safe_pawn, safe_pawn_count));
            fit.tapered(Sink, sink, "threat_by_safe_pawn", 0, .threats_space, safe_pawn_count);

            // The same threat one move away. A pawn may step once, or twice
            // from its home rank, onto an empty square the enemy does not hold.
            const empty = ~value.physical.occupied();
            var pushes = pawnPush(side, value.physical.pieces(side, .pawn) & ~pinned_pawns) & empty;
            const double_rank: Bitboard = if (side == .white)
                @as(Bitboard, 0xff) << 16
            else
                @as(Bitboard, 0xff) << 40;
            pushes |= pawnPush(side, pushes & double_rank) & empty;
            pushes &= ~info.by_type[them][types.PieceType.pawn.index()] & safe;
            const pawn_push_count = sign * @as(i32, @intCast(@popCount(
                pawnAttackSpan(side, pushes) & non_pawn,
            )));
            result.add(Tapered.scaled(params.threat_by_pawn_push, pawn_push_count));
            fit.tapered(Sink, sink, "threat_by_pawn_push", 0, .threats_space, pawn_push_count);

            // Squares from which we could hit the enemy queen next move. The
            // queen must keep watching them whether or not we ever go there,
            // and it counts double when it is the only queen on the board.
            const enemy_queens = value.physical.pieces(side.opposite(), .queen);
            if (@popCount(enemy_queens) == 1) {
                const queen_square = types.Square.fromIndex(@intCast(@ctz(enemy_queens)));
                const only_queen: i32 =
                    if (@popCount(value.physical.by_type[types.PieceType.queen.index()]) == 1) 2 else 1;
                const occupied = value.physical.occupied();
                const queen_safe = safe_area & ~value.physical.pieces(side, .pawn) & ~strongly_protected;

                const knight_forks = info.by_type[us][types.PieceType.knight.index()] &
                    attacks.forPiece(.knight, side, queen_square, occupied);
                const knight_queen_count = sign * only_queen *
                    @as(i32, @intCast(@popCount(knight_forks & queen_safe)));
                result.add(Tapered.scaled(params.knight_on_queen, knight_queen_count));
                fit.tapered(Sink, sink, "knight_on_queen", 0, .threats_space, knight_queen_count);

                const slider_hits = (info.by_type[us][types.PieceType.bishop.index()] &
                    attacks.forPiece(.bishop, side, queen_square, occupied)) |
                    (info.by_type[us][types.PieceType.rook.index()] &
                        attacks.forPiece(.rook, side, queen_square, occupied));
                const slider_queen_count = sign * only_queen *
                    @as(i32, @intCast(@popCount(slider_hits & queen_safe & info.two[us])));
                result.add(Tapered.scaled(params.slider_on_queen, slider_queen_count));
                fit.tapered(Sink, sink, "slider_on_queen", 0, .threats_space, slider_queen_count);
            }
        }

        const score_space = if (comptime contextual_space)
            true
        else
            phase_value >= legacy_space_material_floor;
        if (score_space) {
            const home = if (side == .white) white_home_half else black_home_half;
            const back_rank: Bitboard = if (side == .white) 0xff else @as(Bitboard, 0xff) << 56;
            const central_home = home & centre_files & ~back_rank;
            const safe_space = central_home & ~value.physical.pieces(side, .pawn) &
                info.all[us] & ~info.by_type[them][types.PieceType.pawn.index()];
            const supported = safe_space & info.by_type[us][types.PieceType.pawn.index()];
            const raw_space: i32 = @intCast(@popCount(safe_space) + @popCount(supported));
            const weighted_space = if (comptime contextual_space)
                contextualSpaceCount(raw_space, phase_value, central_locks)
            else
                raw_space;
            const space_count = sign * weighted_space;
            result.middlegame += @as(i32, params.space_bonus) * space_count;
            fit.record(Sink, sink, "space_bonus", 0, .threats_space, .middlegame, space_count);
        }
    }
    return result;
}

const white_home_half: Bitboard = 0x0000_0000_FFFF_FFFF;
const black_home_half: Bitboard = 0xFFFF_FFFF_0000_0000;
const legacy_space_material_floor: u8 = 12;

/// Immediately opposed pawn pairs on the four central files. This is a global
/// board fact: both sides face the same locked centre, so it must be computed
/// once and applied symmetrically before white-minus-black subtraction.
fn centralLocks(value: *const position.Position) u8 {
    const white_pawns = value.physical.pieces(.white, .pawn);
    const black_pawns = value.physical.pieces(.black, .pawn);
    const opposed = pawnPush(.white, white_pawns) & black_pawns & centre_files;
    return @min(@as(u8, @intCast(@popCount(opposed))), 4);
}

/// MAN-E20's bounded per-side space magnitude. Inputs are non-negative chess
/// counts; division therefore implements the registered floor exactly.
fn contextualSpaceCount(raw_space: i32, phase_value: u8, central_locks: u8) i32 {
    std.debug.assert(raw_space >= 0 and raw_space <= 24);
    std.debug.assert(phase_value <= 24);
    std.debug.assert(central_locks <= 4);
    return @divTrunc(
        raw_space * @as(i32, phase_value) * (4 + @as(i32, central_locks)),
        96,
    );
}

test "contextual space is zero monotone and bounded" {
    // SCORE-024: the candidate is a non-negative per-side weighting. More
    // usable material or more central locks cannot reduce an unchanged raw
    // count, phase zero is silent, and the registered maximum is two times.
    for (0..25) |raw_index| {
        const raw_space: i32 = @intCast(raw_index);
        for (0..5) |lock_index| {
            const locks: u8 = @intCast(lock_index);
            try std.testing.expectEqual(@as(i32, 0), contextualSpaceCount(raw_space, 0, locks));

            var previous_phase: i32 = 0;
            for (0..25) |phase_index| {
                const weighted = contextualSpaceCount(raw_space, @intCast(phase_index), locks);
                try std.testing.expect(weighted >= previous_phase);
                try std.testing.expect(weighted <= raw_space * 2);
                previous_phase = weighted;
            }
        }

        var previous_lock: i32 = 0;
        for (0..5) |lock_index| {
            const weighted = contextualSpaceCount(raw_space, 24, @intCast(lock_index));
            try std.testing.expect(weighted >= previous_lock);
            previous_lock = weighted;
        }
        try std.testing.expectEqual(raw_space, contextualSpaceCount(raw_space, 24, 0));
    }
    try std.testing.expectEqual(@as(i32, 48), contextualSpaceCount(24, 24, 4));
}

test "central locks count only immediately opposed c through f pawns" {
    // SCORE-024: pawn opposition is a global structural fact, independent of
    // the side being evaluated; outer-file locks do not enter the context.
    const chess_fen = @import("../chess/fen.zig");
    var root: position.PositionState = .{};
    const all_central = try chess_fen.parse(
        "4k3/8/8/2pppp2/2PPPP2/8/8/4K3 w - - 0 1",
        &root,
    );
    try std.testing.expectEqual(@as(u8, 4), centralLocks(&all_central));

    var outer_root: position.PositionState = .{};
    const outer_only = try chess_fen.parse(
        "4k3/8/8/p6p/P6P/8/8/4K3 w - - 0 1",
        &outer_root,
    );
    try std.testing.expectEqual(@as(u8, 0), centralLocks(&outer_only));
}

fn pawnThreats(comptime Sink: type, sink: *Sink, value: *const position.Position, info: AttackInfo) Tapered {
    var result: Tapered = .{};
    inline for (.{ types.Color.white, types.Color.black }) |side| {
        const sign: i32 = if (side == .white) 1 else -1;
        const attacked = info.by_type[side.index()][types.PieceType.pawn.index()];
        const enemy = side.opposite();
        const targets = value.physical.by_color[enemy.index()] &
            (value.physical.by_type[types.PieceType.knight.index()] |
                value.physical.by_type[types.PieceType.bishop.index()] |
                value.physical.by_type[types.PieceType.rook.index()] |
                value.physical.by_type[types.PieceType.queen.index()]);
        const count = sign * @as(i32, @intCast(@popCount(attacked & targets)));
        result.add(Tapered.scaled(params.pawn_threat, count));
        fit.tapered(Sink, sink, "pawn_threat", 0, .pawn_threats, count);
    }
    return result;
}

fn mobilityValue(comptime Sink: type, sink: *Sink, piece_type: types.PieceType, count: usize, sign: i32) Tapered {
    return switch (piece_type) {
        .knight => recordedTableValue(Sink, sink, "mob_n_mg", "mob_n_eg", params.mob_n_mg[0..], params.mob_n_eg[0..], count, sign),
        .bishop => recordedTableValue(Sink, sink, "mob_b_mg", "mob_b_eg", params.mob_b_mg[0..], params.mob_b_eg[0..], count, sign),
        .rook => recordedTableValue(Sink, sink, "mob_r_mg", "mob_r_eg", params.mob_r_mg[0..], params.mob_r_eg[0..], count, sign),
        .queen => recordedTableValue(Sink, sink, "mob_q_mg", "mob_q_eg", params.mob_q_mg[0..], params.mob_q_eg[0..], count, sign),
        else => unreachable,
    };
}

fn recordedTableValue(
    comptime Sink: type,
    sink: *Sink,
    comptime mg_name: []const u8,
    comptime eg_name: []const u8,
    mg: []const i16,
    eg: []const i16,
    count: usize,
    sign: i32,
) Tapered {
    const index = @min(count, mg.len - 1);
    fit.record(Sink, sink, mg_name, index, .activity, .middlegame, sign);
    fit.record(Sink, sink, eg_name, index, .activity, .endgame, sign);
    return tableValue(mg, eg, count, sign);
}

fn tableValue(mg: []const i16, eg: []const i16, count: usize, sign: i32) Tapered {
    const index = @min(count, mg.len - 1);
    return .{ .middlegame = sign * mg[index], .endgame = sign * eg[index] };
}

/// Every square attacked by at least one pawn of `side`.
///
/// Both diagonal steps are the same displacement for every pawn on the board,
/// so the whole set is two masked shifts. The file masks remove the wrap that a
/// shift would otherwise create across the a- and h-file boundary.
fn pawnAttackSpan(side: types.Color, pawns: Bitboard) Bitboard {
    return if (side == .white)
        ((pawns & ~file_a) << 7) | ((pawns & ~file_h) << 9)
    else
        ((pawns & ~file_h) >> 7) | ((pawns & ~file_a) >> 9);
}

const file_a: Bitboard = 0x0101_0101_0101_0101;
const file_h: Bitboard = file_a << 7;
/// The four central squares, which decide whether a long diagonal is the one
/// that matters.
const centre_squares: Bitboard = (@as(Bitboard, 1) << 27) | (@as(Bitboard, 1) << 28) |
    (@as(Bitboard, 1) << 35) | (@as(Bitboard, 1) << 36);
/// Files c to f. A blocked centre is what makes a wrong-coloured bishop bad,
/// and an outpost outside these files is the one that can be irrelevant.
const centre_files: Bitboard = (file_a << 2) | (file_a << 3) | (file_a << 4) | (file_a << 5);
const queen_side: Bitboard = file_a | (file_a << 1) | (file_a << 2) | (file_a << 3);
const king_side: Bitboard = ~queen_side;

/// Every square a pawn of `side` attacks now or could attack after advancing.
/// An outpost is a square outside this set: no enemy pawn can ever come to it.
fn pawnAttackSpanAll(side: types.Color, pawns: Bitboard) Bitboard {
    const ahead = if (side == .white) northFill(pawns) else southFill(pawns);
    return pawnAttackSpan(side, ahead);
}

/// Whether a slider of `piece_type` belonging to the enemy sees `square`
/// through exactly one blocker, which is a relative pin or a discovered
/// attack waiting to happen. The second lookup removes every square the first
/// one stopped on, so anything it newly reaches lies beyond a single blocker.
fn xrayedBy(
    piece_type: types.PieceType,
    square: types.Square,
    occupied: Bitboard,
    enemy_sliders: Bitboard,
) bool {
    const direct = attacks.forPiece(piece_type, .white, square, occupied);
    const blockers = direct & occupied;
    if (blockers == 0) return false;
    const behind = attacks.forPiece(piece_type, .white, square, occupied ^ blockers);
    return behind & ~direct & enemy_sliders != 0;
}

/// Squares a pawn on the indexed square must find free of enemy pawns to be
/// passed: everything ahead of it on its own file and both neighbours.
///
/// The set depends only on the square and the colour, so it is built once at
/// compile time rather than rebuilt rank by rank for every pawn evaluated.
const passed_mask: [2][64]Bitboard = blk: {
    @setEvalBranchQuota(20_000);
    var table: [2][64]Bitboard = @splat(@splat(0));
    for (0..64) |index| {
        const square = types.Square.fromIndex(@intCast(index));
        const file = square.file().index();
        const files = fileMask(file) | adjacentFiles(file);
        const home: i8 = @intCast(square.rank().index());
        for ([2]types.Color{ .white, .black }) |side| {
            var result: Bitboard = 0;
            var rank = home;
            while (true) {
                rank += if (side == .white) 1 else -1;
                if (rank < 0 or rank > 7) break;
                const rank_shift: u6 = @intCast(rank * 8);
                result |= files & (@as(Bitboard, 0xff) << rank_shift);
            }
            table[side.index()][index] = result;
        }
    }
    break :blk table;
};

fn fileMask(file: u3) Bitboard {
    return @as(Bitboard, 0x0101010101010101) << file;
}

fn adjacentFiles(file: u3) Bitboard {
    var result: Bitboard = 0;
    if (file != 0) result |= fileMask(file - 1);
    if (file != 7) result |= fileMask(file + 1);
    return result;
}

fn popSquare(bits: *Bitboard) ?types.Square {
    if (bits.* == 0) return null;
    const index: u6 = @intCast(@ctz(bits.*));
    bits.* &= bits.* - 1;
    return types.Square.fromIndex(index);
}

comptime {
    contract.requireEvaluator(Hce);
    // The cache remains small enough for one concrete worker-owned state and
    // cannot grow with the search tree or configured hash size.
    std.debug.assert(@sizeOf(Hce.State) <= 4 * 1024);
}

fn pieceActivityForTest(comptime detail: bool, value: *const position.Position) Activity {
    var recorder = fit.Recorder.init();
    return pieceActivityAndAttacks(fit.Recorder, &recorder, detail, value);
}

test "shifted pawn span equals the union of the per-square attack tables" {
    // FUNC-006: the shift form must reproduce exactly which squares pawns
    // attack, including the a- and h-file edges where a shift wraps. The
    // per-square table is the independent oracle, and the boards below cover
    // both edges, both colours and the promotion ranks.
    var rng = std.Random.DefaultPrng.init(0x5A3D_9C11_0E27_44B1);
    const random = rng.random();
    for (0..512) |iteration| {
        const pawns: Bitboard = switch (iteration) {
            0 => 0,
            1 => file_a,
            2 => file_h,
            3 => file_a | file_h,
            4 => ~@as(Bitboard, 0),
            else => random.int(u64),
        };
        inline for (.{ types.Color.white, types.Color.black }) |side| {
            var remaining = pawns;
            var expected: Bitboard = 0;
            while (popSquare(&remaining)) |square|
                expected |= attacks.pawn[side.index()][square.index()];
            try std.testing.expectEqual(expected, pawnAttackSpan(side, pawns));
        }
    }
}

test "shared attacks exclude moves forbidden by an absolute pin" {
    // FUNC-006: a piece shielding its king from a slider may only retain
    // attacks on the pin ray. The attack map is evaluation evidence, not a
    // pseudo-legal geometry map, so downstream mobility, threat and king
    // consumers must never receive impossible knight/pawn captures.
    const chess_fen = @import("../chess/fen.zig");
    const activity = struct {
        fn call(fen_text: []const u8) !Activity {
            var root: position.PositionState = .{};
            const value = try chess_fen.parse(fen_text, &root);
            return pieceActivityForTest(true, &value);
        }
    }.call;

    const pinned_knight = try activity("k3r3/8/8/8/8/8/4N3/4K3 w - - 0 1");
    const free_knight = try activity("k3r3/8/8/8/8/8/4N3/3K4 w - - 0 1");
    try std.testing.expectEqual(
        @as(Bitboard, 0),
        pinned_knight.info.by_type[types.Color.white.index()][types.PieceType.knight.index()],
    );
    try std.testing.expect(
        free_knight.info.by_type[types.Color.white.index()][types.PieceType.knight.index()] != 0,
    );

    const pinned_rook = try activity("k3r3/8/8/8/8/8/4R3/4K3 w - - 0 1");
    const rook_reach = pinned_rook.info.by_type[types.Color.white.index()][types.PieceType.rook.index()];
    try std.testing.expect(rook_reach & types.Square.e3.bit() != 0);
    try std.testing.expect(rook_reach & types.Square.d2.bit() == 0);

    const pinned_pawn = try activity("k3r3/8/8/8/8/8/4P3/4K3 w - - 0 1");
    try std.testing.expectEqual(
        @as(Bitboard, 0),
        pinned_pawn.info.by_type[types.Color.white.index()][types.PieceType.pawn.index()],
    );
}

test "pawn sets match a per-pawn classification" {
    // FUNC-006: doubled, isolated, connected and passed are chess facts about
    // individual pawns. The whole-board form must select exactly the pawns the
    // per-square definitions select, on every legal pawn rank and both edges.
    var rng = std.Random.DefaultPrng.init(0x2F17_88C0_43BE_6A95);
    const random = rng.random();
    const pawn_ranks: Bitboard = 0x00FF_FFFF_FFFF_FF00;
    for (0..2048) |_| {
        const own = random.int(u64) & random.int(u64) & pawn_ranks;
        const enemy = random.int(u64) & random.int(u64) & pawn_ranks & ~own;
        inline for (.{ types.Color.white, types.Color.black }) |side| {
            const forward: i32 = if (side == .white) 1 else -1;
            var expected: PawnSets = .{
                .doubled = 0,
                .isolated = 0,
                .connected = 0,
                .passed = 0,
                .own = own,
            };
            var remaining = own;
            while (popSquare(&remaining)) |square| {
                const bit = squareBit(square);
                const file = square.file().index();
                const rank: i32 = @intCast(square.rank().index());
                var own_ahead = false;
                var file_mates = own & fileMask(file) & ~bit;
                while (popSquare(&file_mates)) |other| {
                    const other_rank: i32 = @intCast(other.rank().index());
                    if ((side == .white and other_rank > rank) or
                        (side == .black and other_rank < rank)) own_ahead = true;
                }
                const doubled = own_ahead;
                const isolated = own & adjacentFiles(file) == 0;
                if (doubled) expected.doubled |= bit;
                if (isolated and !doubled) expected.isolated |= bit;
                if (attacks.pawn[side.opposite().index()][square.index()] & own != 0)
                    expected.connected |= bit;
                if (enemy & passed_mask[side.index()][square.index()] == 0) expected.passed |= bit;

                // Step 5.3.10 sets, each classified square by square from its
                // own definition rather than from the whole-board form.
                const stop_rank = rank + forward;
                const stop: ?types.Square = if (stop_rank >= 0 and stop_rank <= 7)
                    types.Square.fromIndex(@intCast(stop_rank * 8 + @as(i32, file)))
                else
                    null;

                // Backward: no own pawn on a neighbouring file stands level
                // with it or behind it, and an enemy pawn holds its stop
                // square.
                var has_helper = false;
                var neighbours = own & adjacentFiles(file);
                while (popSquare(&neighbours)) |other| {
                    const other_rank: i32 = @intCast(other.rank().index());
                    const level_or_behind = if (side == .white)
                        other_rank <= rank
                    else
                        other_rank >= rank;
                    if (level_or_behind) has_helper = true;
                }
                if (stop) |stop_square| {
                    const denied = attacks.pawn[side.index()][stop_square.index()] & enemy != 0;
                    if (!doubled and !isolated and !has_helper and denied)
                        expected.backward |= bit;
                }

                // Weak lever: both enemy pawn attacks land on it and none of
                // ours defends it.
                const east = pawnAttackEast(side.opposite(), enemy) & bit != 0;
                const west = pawnAttackWest(side.opposite(), enemy) & bit != 0;
                const defended = attacks.pawn[side.opposite().index()][square.index()] & own != 0;
                if (east and west and !defended) expected.weak_lever |= bit;

                // Blocked: an enemy pawn stands on the stop square.
                if (stop) |stop_square| {
                    if (enemy & squareBit(stop_square) != 0) expected.blocked |= bit;
                }

                // Phalanx: an own pawn stands beside it on the same rank.
                if (own & adjacentFiles(file) & (@as(Bitboard, 0xff) << @intCast(rank * 8)) != 0)
                    expected.phalanx |= bit;

                // Opposed: an enemy pawn stands ahead of it on its own file.
                var ahead: Bitboard = 0;
                var walk = rank + forward;
                while (walk >= 0 and walk <= 7) : (walk += forward) {
                    ahead |= @as(Bitboard, 1) << @intCast(walk * 8 + @as(i32, file));
                }
                if (enemy & ahead != 0) expected.opposed |= bit;

                // Candidate: no same-file stopper, not already passed, and
                // every adjacent stopper is attacked by a distinct own pawn.
                const blockers = enemy & passed_mask[side.index()][square.index()];
                const adjacent_stoppers = blockers & adjacentFiles(file);
                if (blockers != 0 and enemy & ahead == 0 and adjacent_stoppers != 0) {
                    var all_levered = true;
                    var stoppers = adjacent_stoppers;
                    while (popSquare(&stoppers)) |stopper| {
                        if (attacks.pawn[side.opposite().index()][stopper.index()] & own == 0)
                            all_levered = false;
                    }
                    var attacker_count: usize = 0;
                    var attackers = own;
                    while (popSquare(&attackers)) |attacker| {
                        if (attacks.pawn[side.index()][attacker.index()] & adjacent_stoppers != 0)
                            attacker_count += 1;
                    }
                    if (all_levered and attacker_count >= @popCount(adjacent_stoppers))
                        expected.candidate |= bit;
                }
            }
            try std.testing.expectEqualDeep(expected, pawnSets(side, own, enemy));
            try std.testing.expectEqual(@as(Bitboard, 0), expected.doubled & expected.isolated);
            try std.testing.expectEqual(@as(Bitboard, 0), expected.doubled & expected.backward);
            try std.testing.expectEqual(@as(Bitboard, 0), expected.isolated & expected.backward);
        }
    }
}

test "candidate passers require enough immediate pawn levers" {
    // FUNC-006: a leverable majority must have no same-file stopper and must
    // be able to challenge every adjacent stopper with distinct pawns. This
    // is classified directly, independently of the score parameters.
    const chess_fen = @import("../chess/fen.zig");
    const whiteSets = struct {
        fn call(fen_text: []const u8) !PawnSets {
            var root: position.PositionState = .{};
            const value = try chess_fen.parse(fen_text, &root);
            return pawnSets(
                .white,
                value.physical.pieces(.white, .pawn),
                value.physical.pieces(.black, .pawn),
            );
        }
    }.call;

    // d4 is stopped by e6 only after a future push. The f5 pawn supplies the
    // immediate lever; without it d4 is neither passed nor a candidate.
    const supported = try whiteSets("4k3/8/4p3/5P2/3P4/8/8/4K3 w - - 0 1");
    const unsupported = try whiteSets("4k3/8/4p3/8/3P4/8/8/4K3 w - - 0 1");
    try std.testing.expect(supported.candidate & squareBit(.d4) != 0);
    try std.testing.expect(unsupported.candidate & squareBit(.d4) == 0);

    // One d-pawn attacks both adjacent stoppers but cannot exchange both.
    const outnumbered = try whiteSets("4k3/8/8/2p1p3/3P4/8/8/4K3 w - - 0 1");
    try std.testing.expect(outnumbered.candidate & squareBit(.d4) == 0);

    // A same-file stopper cannot be removed by a pawn capture and therefore
    // excludes candidate status even if another adjacent pawn is levered.
    const opposed = try whiteSets("4k3/8/8/3pp3/3P4/8/8/4K3 w - - 0 1");
    try std.testing.expect(opposed.candidate & squareBit(.d4) == 0);
}

test "a passer is worth less when it cannot actually advance" {
    // FUNC-006: Step 5.3.10 exists because rank alone does not say whether a
    // passed pawn is going anywhere. These are relations between positions,
    // not recorded numbers: the same pawn on the same square must score worse
    // when something stops it and better when nothing does.
    const chess_fen = @import("../chess/fen.zig");
    const passedOf = struct {
        fn call(fen_text: []const u8) !Tapered {
            var root: position.PositionState = .{};
            const value = try chess_fen.parse(fen_text, &root);
            const sets = [2]PawnSets{
                pawnSets(.white, value.physical.pieces(.white, .pawn), value.physical.pieces(.black, .pawn)),
                pawnSets(.black, value.physical.pieces(.black, .pawn), value.physical.pieces(.white, .pawn)),
            };
            const activity = pieceActivityForTest(true, &value);
            var recorder = fit.Recorder.init();
            return passedPawns(fit.Recorder, &recorder, true, &sets, &value, activity.info);
        }
    }.call;

    // A blockading knight in front of the pawn is the classic answer to a
    // passer, and must cost the pawn something.
    const free = try passedOf("4k3/8/8/3P4/8/8/8/4K3 w - - 0 1");
    const blockaded = try passedOf("4k3/8/3n4/3P4/8/8/8/4K3 w - - 0 1");
    try std.testing.expect(blockaded.endgame < free.endgame);

    // The defending king sitting on the promotion path devalues it; the same
    // king far away does not.
    const king_near = try passedOf("8/8/3k4/3P4/8/8/8/4K3 w - - 0 1");
    const king_far = try passedOf("8/8/8/3P4/8/8/8/k3K3 w - - 0 1");
    try std.testing.expect(king_near.endgame < king_far.endgame);

    // Our own king escorting the pawn is worth more than leaving it alone.
    const escorted = try passedOf("7k/8/3K4/3P4/8/8/8/8 w - - 0 1");
    const abandoned = try passedOf("7k/8/8/3P4/8/8/8/K7 w - - 0 1");
    try std.testing.expect(escorted.endgame > abandoned.endgame);

    // A rook pawn is easier to stop than a central one at the same rank. The
    // pawns are placed on the third rank, below the rank at which the stop
    // square and king-race terms activate, so this compares the file term
    // alone rather than whichever king happens to stand nearer.
    const central = try passedOf("4k3/8/8/8/8/3P4/8/4K3 w - - 0 1");
    const edge = try passedOf("4k3/8/8/8/8/P7/8/4K3 w - - 0 1");
    try std.testing.expect(edge.endgame < central.endgame);
    try std.testing.expect(edge.middlegame < central.middlegame);

    // Colour mirroring must negate the whole component.
    const mirrored = try passedOf("4k3/8/8/8/3p4/8/8/4K3 b - - 0 1");
    const upright = try passedOf("4k3/8/8/3P4/8/8/8/4K3 w - - 0 1");
    try std.testing.expectEqual(-upright.endgame, mirrored.endgame);
    try std.testing.expectEqual(-upright.middlegame, mirrored.middlegame);
}

test "candidate value stays below passed value and path control is graded" {
    // FUNC-006: candidate status is potential conversion, while passed status
    // means every pawn stopper is already gone. Path attack and defence must
    // also accumulate per square instead of collapsing to a clean/dirty bit.
    const chess_fen = @import("../chess/fen.zig");
    const Evidence = struct {
        value: Tapered,
        attacked: i32,
        defended: i32,
    };
    const evidence = struct {
        fn call(fen_text: []const u8) !Evidence {
            var root: position.PositionState = .{};
            const value = try chess_fen.parse(fen_text, &root);
            const sets = [2]PawnSets{
                pawnSets(.white, value.physical.pieces(.white, .pawn), value.physical.pieces(.black, .pawn)),
                pawnSets(.black, value.physical.pieces(.black, .pawn), value.physical.pieces(.white, .pawn)),
            };
            const activity = pieceActivityForTest(true, &value);
            var recorder = fit.Recorder.init();
            const passer_value = passedPawns(fit.Recorder, &recorder, true, &sets, &value, activity.info);
            var attacked: i32 = 0;
            var defended: i32 = 0;
            for (recorder.slice()) |entry| {
                if (entry.lane != .middlegame) continue;
                if (std.mem.eql(u8, entry.group, "passed_path_attacked")) attacked += entry.count;
                if (std.mem.eql(u8, entry.group, "passed_path_defended")) defended += entry.count;
            }
            return .{ .value = passer_value, .attacked = attacked, .defended = defended };
        }
    }.call;

    const candidate = try evidence("4k3/8/4p3/5P2/3P4/8/8/4K3 w - - 0 1");
    const passed = try evidence("4k3/8/8/5P2/3P4/8/8/4K3 w - - 0 1");
    try std.testing.expect(candidate.value.middlegame < passed.value.middlegame);
    try std.testing.expect(candidate.value.endgame < passed.value.endgame);

    const clear = try evidence("7k/8/8/3P4/8/8/8/K7 w - - 0 1");
    const attacked = try evidence("7k/2b5/8/3P4/8/8/8/K7 w - - 0 1");
    const defended = try evidence("7k/8/8/2BP4/8/8/8/K7 w - - 0 1");
    try std.testing.expectEqual(@as(i32, 0), clear.attacked);
    try std.testing.expect(attacked.attacked > clear.attacked);
    try std.testing.expect(defended.defended > clear.defended);
    try std.testing.expect(attacked.value.endgame < clear.value.endgame);
    try std.testing.expect(defended.value.endgame > clear.value.endgame);
}

test "threat and king-safety completion charges what it names" {
    // FUNC-006: compared as the difference the switch makes, so the Step-5.3.6
    // threat terms — which both arms share — cancel exactly and only the new
    // ones remain.
    const chess_fen = @import("../chess/fen.zig");
    const delta = struct {
        fn call(fen_text: []const u8) !Tapered {
            var root: position.PositionState = .{};
            const value = try chess_fen.parse(fen_text, &root);
            const activity = pieceActivityForTest(true, &value);
            var on_recorder = fit.Recorder.init();
            var off_recorder = fit.Recorder.init();
            const on = threatsAndSpace(fit.Recorder, &on_recorder, true, false, &value, activity.info, 24);
            const off = threatsAndSpace(fit.Recorder, &off_recorder, false, false, &value, activity.info, 24);
            return .{
                .middlegame = on.middlegame - off.middlegame,
                .endgame = on.endgame - off.endgame,
            };
        }
    }.call;
    const kingDelta = struct {
        fn call(fen_text: []const u8) !Tapered {
            var root: position.PositionState = .{};
            const value = try chess_fen.parse(fen_text, &root);
            const activity = pieceActivityForTest(true, &value);
            var on_recorder = fit.Recorder.init();
            var off_recorder = fit.Recorder.init();
            const on = kingSafety(fit.Recorder, &on_recorder, true, false, &value, activity.info);
            const off = kingSafety(fit.Recorder, &off_recorder, false, false, &value, activity.info);
            return .{
                .middlegame = on.middlegame - off.middlegame,
                .endgame = on.endgame - off.endgame,
            };
        }
    }.call;

    // A safe pawn attacking a knight is the cheapest possible threat, and the
    // same knight out of the pawn's reach is not threatened at all.
    const pawn_hits = try delta("4k3/8/8/3n4/4P3/8/8/4K3 w - - 0 1");
    const pawn_misses = try delta("4k3/8/8/7n/4P3/8/8/4K3 w - - 0 1");
    try std.testing.expect(pawn_hits.middlegame > pawn_misses.middlegame);

    // A knight one square from forking the enemy queen records that named
    // pressure, while the remote knight does not. Inspect the producer rather
    // than an aggregate delta: after joint fitting, unrelated completion terms
    // in the two legal positions need not cancel numerically.
    const knightQueenCount = struct {
        fn call(fen_text: []const u8) !i32 {
            var root: position.PositionState = .{};
            const value = try chess_fen.parse(fen_text, &root);
            const activity = pieceActivityForTest(true, &value);
            var recorder = fit.Recorder.init();
            _ = threatsAndSpace(fit.Recorder, &recorder, true, false, &value, activity.info, 24);
            var count: i32 = 0;
            for (recorder.slice()) |entry| {
                if (entry.lane == .middlegame and
                    std.mem.eql(u8, entry.group, "knight_on_queen"))
                    count += entry.count;
            }
            return count;
        }
    }.call;
    // Keep the king off the queen's file: an e-file pin would correctly remove
    // the knight's attacks from the legal shared map.
    const eyeing_queen = try knightQueenCount("4q2k/8/8/8/4N3/8/8/K7 w - - 0 1");
    const elsewhere = try knightQueenCount("4q2k/8/8/8/8/8/8/KN6 w - - 0 1");
    try std.testing.expect(eyeing_queen > elsewhere);
    try std.testing.expect(params.knight_on_queen[0] > 0);

    // A king on a flank with no pawn at all has nothing to hide behind.
    const with_pawns = try kingDelta("4k3/8/8/8/8/8/5PPP/6K1 w - - 0 1");
    const pawnless = try kingDelta("4k3/8/8/8/8/8/PPP5/6K1 w - - 0 1");
    try std.testing.expect(pawnless.middlegame < with_pawns.middlegame);

    // A bishop pinning a knight in front of our king is standing danger: the
    // knight cannot step aside to defend. Both positions hold two attackers,
    // so the difference is the blocker rather than the attack itself.
    const pinned = try kingDelta("4k3/8/8/8/1b6/8/3N4/4K2r w - - 0 1");
    const unpinned = try kingDelta("4k3/8/8/8/1b6/8/5N2/4K2r w - - 0 1");
    try std.testing.expect(pinned.middlegame <= unpinned.middlegame);

    // Colour mirroring negates both new components.
    const white_side = try delta("4k3/8/8/3n4/4P3/8/8/4K3 w - - 0 1");
    const black_side = try delta("4k3/8/8/4p3/3N4/8/8/4K3 b - - 0 1");
    try std.testing.expectEqual(-white_side.middlegame, black_side.middlegame);
    try std.testing.expectEqual(-white_side.endgame, black_side.endgame);
}

test "threats respect protection and space is central and pawn supported" {
    // FUNC-006: a pawn-protected target is not a cheap minor-piece threat, and
    // space is useful central territory rather than every controlled square
    // on a broad home half.
    const chess_fen = @import("../chess/fen.zig");
    const minorThreatCount = struct {
        fn call(fen_text: []const u8) !i32 {
            var root: position.PositionState = .{};
            const value = try chess_fen.parse(fen_text, &root);
            const attacks_info = pieceActivityForTest(true, &value).info;
            var recorder = fit.Recorder.init();
            _ = threatsAndSpace(fit.Recorder, &recorder, true, false, &value, attacks_info, 24);
            var count: i32 = 0;
            for (recorder.slice()) |entry| {
                if (entry.lane == .middlegame and
                    std.mem.eql(u8, entry.group, "threat_by_minor") and
                    entry.element == types.PieceType.knight.index() * 2)
                    count += entry.count;
            }
            return count;
        }
    }.call;
    const protected = try minorThreatCount("7k/8/8/5p2/4n3/8/8/KB6 w - - 0 1");
    const loose = try minorThreatCount("7k/8/8/7p/4n3/8/8/KB6 w - - 0 1");
    try std.testing.expectEqual(@as(i32, 0), protected);
    try std.testing.expect(loose > protected);

    const spaceValue = struct {
        fn call(fen_text: []const u8) !Tapered {
            var root: position.PositionState = .{};
            const value = try chess_fen.parse(fen_text, &root);
            const attacks_info = pieceActivityForTest(true, &value).info;
            var recorder = fit.Recorder.init();
            return threatsAndSpace(fit.Recorder, &recorder, true, false, &value, attacks_info, 24);
        }
    }.call;
    const central = try spaceValue("4k3/8/8/8/8/3PP3/8/4K3 w - - 0 1");
    const flanks = try spaceValue("4k3/8/8/8/8/P6P/8/4K3 w - - 0 1");
    try std.testing.expect(central.middlegame > flanks.middlegame);
}

test "piece detail charges the placements it names" {
    // FUNC-006: Step 5.3.11 claims are relations between positions, not
    // recorded numbers. Each pair is compared as the *difference the switch
    // makes*, so mobility, rook files and the bishop pair — which both arms
    // share — cancel exactly and only the new terms remain. Picking positions
    // where those cancel by hand proved unreliable.
    const chess_fen = @import("../chess/fen.zig");
    const detailDelta = struct {
        fn call(fen_text: []const u8) !Tapered {
            var root: position.PositionState = .{};
            const value = try chess_fen.parse(fen_text, &root);
            const with = pieceActivityForTest(true, &value).value;
            const without = pieceActivityForTest(false, &value).value;
            return .{
                .middlegame = with.middlegame - without.middlegame,
                .endgame = with.endgame - without.endgame,
            };
        }
    }.call;

    // The outpost rule changed rather than appeared: Step 5.3.10 asked whether
    // an enemy pawn attacks the square *now*, and this step asks whether one
    // could ever attack it. Both knights below are defended by our pawn and
    // unattacked today; the second has a black pawn two ranks away that can
    // advance and evict it, so only the first is a real outpost. Everything
    // else about the two positions is identical, so the delta isolates exactly
    // that change of definition.
    const permanent = try detailDelta("4k3/7p/8/3N4/2P5/8/8/4K3 w - - 0 1");
    const evictable = try detailDelta("4k3/4p3/8/3N4/2P5/8/8/4K3 w - - 0 1");
    try std.testing.expect(permanent.middlegame > evictable.middlegame);

    // A bishop whose own pawns sit on its square colour is the bad one.
    const clear = try detailDelta("4k3/8/8/8/8/1P3P2/8/2B1K3 w - - 0 1");
    const clogged = try detailDelta("4k3/8/8/8/8/2P2P2/8/2B1K3 w - - 0 1");
    try std.testing.expect(clogged.middlegame < clear.middlegame);

    // A bishop seeing both central squares along a long diagonal.
    const long_diagonal = try detailDelta("4k3/8/8/8/8/8/1B6/4K3 w - - 0 1");
    const short_diagonal = try detailDelta("4k3/8/8/8/8/8/7B/4K3 w - - 0 1");
    try std.testing.expect(long_diagonal.middlegame > short_diagonal.middlegame);

    // A rook sharing a file with the enemy queen is pointed at it.
    const on_queen_file = try detailDelta("3qk3/8/8/8/8/8/8/3RK3 w - - 0 1");
    const off_queen_file = try detailDelta("3qk3/8/8/8/8/8/8/2R1K3 w - - 0 1");
    try std.testing.expect(on_queen_file.middlegame > off_queen_file.middlegame);

    // A queen an enemy rook x-rays through a single blocker is tied to that
    // blocker. The second position blocks the ray twice, which breaks the
    // x-ray while leaving every other piece where it stands.
    const xrayed = try detailDelta("3rk3/8/8/3n4/8/3Q4/8/4K3 w - - 0 1");
    const double_blocked = try detailDelta("3rk3/8/3p4/3n4/8/3Q4/8/4K3 w - - 0 1");
    try std.testing.expect(xrayed.middlegame < double_blocked.middlegame);

    // A minor far from its own king defends less than one beside it.
    const near_king = try detailDelta("4k3/8/8/8/8/8/8/3NK3 w - - 0 1");
    const far_king = try detailDelta("4k3/8/8/8/8/8/8/N3K3 w - - 0 1");
    try std.testing.expect(near_king.middlegame > far_king.middlegame);
}

test "pawn completion charges the weaknesses it names" {
    // FUNC-006: each new structural term must be visible in the position it
    // describes and silent in the one it does not.
    const chess_fen = @import("../chess/fen.zig");
    const structureOf = struct {
        fn call(fen_text: []const u8) !Tapered {
            var root: position.PositionState = .{};
            const value = try chess_fen.parse(fen_text, &root);
            const sets = [2]PawnSets{
                pawnSets(.white, value.physical.pieces(.white, .pawn), value.physical.pieces(.black, .pawn)),
                pawnSets(.black, value.physical.pieces(.black, .pawn), value.physical.pieces(.white, .pawn)),
            };
            return pawnStructure(true, sets, &value);
        }
    }.call;

    // A pawn whose stop square is held by an enemy pawn and which no
    // neighbour can ever defend is backward; moving the neighbour up so it
    // stands behind the pawn removes exactly that fact.
    const backward = try structureOf("4k3/2p5/8/8/1P6/8/8/4K3 w - - 0 1");
    const defended = try structureOf("4k3/2p5/8/8/1P6/P7/8/4K3 w - - 0 1");
    try std.testing.expect(defended.middlegame > backward.middlegame);

    // Pawns side by side are worth more than the same two pawns split apart.
    const phalanx = try structureOf("4k3/8/8/8/8/8/PP6/4K3 w - - 0 1");
    const split = try structureOf("4k3/8/8/8/8/8/P6P/4K3 w - - 0 1");
    try std.testing.expect(phalanx.middlegame > split.middlegame);

    // Colour mirroring negates the component.
    const white_side = try structureOf("4k3/8/8/8/8/8/PP6/4K3 w - - 0 1");
    const black_side = try structureOf("4k3/6pp/8/8/8/8/8/4K3 b - - 0 1");
    try std.testing.expectEqual(-white_side.middlegame, black_side.middlegame);
    try std.testing.expectEqual(-white_side.endgame, black_side.endgame);
}

test "shelter distance finds the nearest pawn ahead of the king" {
    // FUNC-006: shelter is measured to the nearest own pawn still standing in
    // front of the king, and zero means the file has none. Scanning by rank is
    // the independent definition the bit form must reproduce.
    var rng = std.Random.DefaultPrng.init(0x71C4_0D62_9AE3_1F08);
    const random = rng.random();
    for (0..64) |king_index| {
        const king_square = types.Square.fromIndex(@intCast(king_index));
        for (0..64) |_| {
            const file_pawns = random.int(u64) & fileMask(king_square.file().index());
            inline for (.{ types.Color.white, types.Color.black }) |side| {
                var expected: u3 = 0;
                var pawns = file_pawns;
                while (popSquare(&pawns)) |square| {
                    const king_rank: i32 = @intCast(types.relativeRank(side, king_square.rank()).index());
                    const pawn_rank: i32 = @intCast(types.relativeRank(side, square.rank()).index());
                    const ahead = pawn_rank - king_rank;
                    if (ahead <= 0) continue;
                    const distance: u3 = @intCast(@min(ahead, 7));
                    if (expected == 0 or distance < expected) expected = distance;
                }
                try std.testing.expectEqual(
                    expected,
                    nearestPawnDistance(side, king_square, file_pawns),
                );
            }
        }
    }
}

test "king-safety repair records file geometry and endgame pawn distance" {
    // FUNC-006: the king's actual file, rather than the centre of the clamped
    // three-file window, owns the same-file shelter bucket. This specifically
    // protects kings on a/h files, where those two notions differ.
    const chess_fen = @import("../chess/fen.zig");
    var edge_root: position.PositionState = .{};
    const edge = try chess_fen.parse("4k3/8/8/8/8/8/7P/7K w - - 0 1", &edge_root);
    var shelter_trace = fit.Recorder.init();
    _ = kingShelter(fit.Recorder, &shelter_trace, &edge, .white, .h1, 1);
    var same_file_rank_one: i32 = 0;
    var adjacent_rank_one: i32 = 0;
    for (shelter_trace.slice()) |entry| {
        if (!std.mem.eql(u8, entry.group, "shelter_rank")) continue;
        if (entry.element == 1) same_file_rank_one += entry.count;
        if (entry.element == 9) adjacent_rank_one += entry.count;
    }
    try std.testing.expectEqual(@as(i32, 1), same_file_rank_one);
    try std.testing.expectEqual(@as(i32, 0), adjacent_rank_one);

    // In a low-material ending the recorded proximity fact is exactly the
    // Chebyshev king distance summed over that side's pawns. It remains an
    // ordinary evaluation feature and has no terminal authority.
    var ending_root: position.PositionState = .{};
    const ending = try chess_fen.parse("7k/8/8/3P4/8/8/P7/4K3 w - - 0 1", &ending_root);
    const ending_activity = pieceActivityForTest(true, &ending);
    var ending_trace = fit.Recorder.init();
    _ = kingSafetyFor(fit.Recorder, &ending_trace, true, false, &ending, ending_activity.info, .white, 1);
    var recorded_distance: i32 = 0;
    for (ending_trace.slice()) |entry| {
        if (std.mem.eql(u8, entry.group, "king_pawn_proximity")) recorded_distance += entry.count;
    }
    try std.testing.expectEqual(
        kingDistance(.e1, .d5) + kingDistance(.e1, .a2),
        recorded_distance,
    );
}

test "king danger includes pawn attackers and queen availability" {
    // FUNC-006: the e3 pawn attacks f2 in White's king ring and joins the g8
    // rook as a second attacker; on e4 it does not. Both positions keep the
    // shelter files and every piece attacker unchanged.
    const chess_fen = @import("../chess/fen.zig");
    const comfort = struct {
        fn call(fen_text: []const u8) !Tapered {
            var root: position.PositionState = .{};
            const value = try chess_fen.parse(fen_text, &root);
            const activity = pieceActivityForTest(true, &value);
            var sink: fit.Recorder = fit.Recorder.init();
            return kingSafetyFor(fit.Recorder, &sink, true, false, &value, activity.info, .white, 1);
        }
    }.call;
    const pawn_attacks = try comfort("6r1/4k3/8/8/8/4p3/5PPP/6K1 w - - 0 1");
    const pawn_misses = try comfort("6r1/4k3/8/8/4p3/8/5PPP/6K1 w - - 0 1");
    try std.testing.expect(pawn_attacks.middlegame < pawn_misses.middlegame);

    // A remote attacking queen still makes an established attack harder to
    // neutralise, while a remote defending queen is a resource. The chosen
    // squares do not themselves touch the king ring.
    const no_queens = pawn_attacks;
    const attacker_queen = try comfort("2q3r1/4k3/8/8/8/4p3/5PPP/6K1 w - - 0 1");
    const defender_queen = try comfort("6r1/4k3/8/8/8/2Q1p3/5PPP/6K1 w - - 0 1");
    try std.testing.expect(attacker_queen.middlegame < no_queens.middlegame);
    try std.testing.expect(defender_queen.middlegame > no_queens.middlegame);
}

test "shelter-moderated danger has the registered directional properties" {
    // SCORE-025: this is the candidate's complete transformation, tested
    // independently of the shelter and attack producers. The two-attacker
    // boundary remains outside this function and therefore unchanged.
    const raw_values = [_]i32{ -20, 0, 25, 100, 640 };
    for (raw_values) |raw| {
        const baseline = @max(raw, 0);
        try std.testing.expectEqual(baseline, shelterModeratedDanger(raw, 0));
        try std.testing.expect(shelterModeratedDanger(raw, 30) <= baseline);
        try std.testing.expect(shelterModeratedDanger(raw, -30) >= baseline);
        try std.testing.expect(shelterModeratedDanger(raw, 30) >= 0);
        try std.testing.expect(shelterModeratedDanger(raw, -30) >= 0);
    }
    try std.testing.expectEqual(@as(i32, 0), shelterModeratedDanger(25, 25));
    try std.testing.expectEqual(@as(i32, 55), shelterModeratedDanger(25, -30));

    // Widened subtraction covers the evaluator's bounded extrema without an
    // intermediate overflow in safety builds.
    try std.testing.expectEqual(
        @as(i32, 0),
        shelterModeratedDanger(std.math.minInt(i32), std.math.maxInt(i32)),
    );
}

test "passed-pawn masks match a rank-by-rank reconstruction" {
    // FUNC-006: a pawn is passed when no enemy pawn stands ahead of it on its
    // own file or either neighbour. The table must encode exactly that region,
    // so it is compared against a direct reconstruction for every square.
    for (0..64) |index| {
        const square = types.Square.fromIndex(@intCast(index));
        const files = fileMask(square.file().index()) | adjacentFiles(square.file().index());
        inline for (.{ types.Color.white, types.Color.black }) |side| {
            var expected: Bitboard = 0;
            var rank: i8 = @intCast(square.rank().index());
            while (true) {
                rank += if (side == .white) 1 else -1;
                if (rank < 0 or rank > 7) break;
                expected |= files & (@as(Bitboard, 0xff) << @intCast(rank * 8));
            }
            try std.testing.expectEqual(expected, passed_mask[side.index()][index]);
        }
    }
}

test "mating material recognises every forcing and non-forcing combination" {
    // FUNC-006: these are chess facts about which material can force mate.
    // Three knights and a mixed-colour bishop pair can; one or two knights and
    // a single-colour bishop pair cannot, however much material is counted.
    const cases = [_]struct { fen: []const u8, side: types.Color, lacks: bool }{
        .{ .fen = "4k3/8/8/8/8/8/8/K7 w - - 0 1", .side = .white, .lacks = true },
        .{ .fen = "4k3/8/8/8/8/8/8/KN6 w - - 0 1", .side = .white, .lacks = true },
        .{ .fen = "4k3/8/8/8/8/8/8/KB6 w - - 0 1", .side = .white, .lacks = true },
        .{ .fen = "4k3/8/8/8/8/8/8/KNN5 w - - 0 1", .side = .white, .lacks = true },
        // Three knights force mate, and promotion makes that reachable.
        .{ .fen = "4k3/8/8/8/8/8/N7/KNN5 w - - 0 1", .side = .white, .lacks = false },
        // Bishops on one colour leave the other colour permanently safe.
        .{ .fen = "4k3/8/8/8/8/8/8/KB1B4 w - - 0 1", .side = .white, .lacks = true },
        // A mixed-colour bishop pair mates.
        .{ .fen = "4k3/8/8/8/8/8/8/KBB5 w - - 0 1", .side = .white, .lacks = false },
        .{ .fen = "4k3/8/8/8/8/8/8/KBN5 w - - 0 1", .side = .white, .lacks = false },
        .{ .fen = "4k3/8/8/8/8/8/8/KR6 w - - 0 1", .side = .white, .lacks = false },
        .{ .fen = "4k3/8/8/8/8/8/8/KQ6 w - - 0 1", .side = .white, .lacks = false },
        .{ .fen = "4k3/8/8/8/8/8/P7/K7 w - - 0 1", .side = .white, .lacks = false },
    };
    const fen = @import("../chess/fen.zig");
    for (cases) |case| {
        var root: position.PositionState = .{};
        const value = try fen.parse(case.fen, &root);
        try std.testing.expectEqual(case.lacks, lacksMatingMaterial(&value, case.side));
    }
}
