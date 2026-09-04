//! Frozen one-time reference value snapshot used by Manta's bootstrap HCE.
// Source files and hashes are recorded in ADR-0016; this is not a synchronized dependency.

pub const mg_val: [7]i16 = .{
    0, 84, 323, 364, 514, 1085, 0,
};

pub const eg_val: [7]i16 = .{
    0, 100, 311, 325, 562, 998, 0,
};

pub const pst_mg: [6][64]i16 = .{
    .{
        0,   0,   0,   0,   0,   0,   0,  0,
        -31, -1,  -17, -23, -14, 34,  42, -28,
        -23, -6,  -9,  -11, 4,   2,   24, -10,
        -24, -3,  -5,  7,   15,  6,   3,  -23,
        -10, 12,  6,   17,  21,  12,  15, -22,
        -5,  7,   26,  31,  65,  56,  25, -20,
        98,  134, 61,  95,  68,  126, 34, -11,
        0,   0,   0,   0,   0,   0,   0,  0,
    },
    .{
        -167, -89, -34, -49, 61,  -97, -15, -107,
        -73,  -41, 68,  33,  25,  62,  7,   -17,
        -47,  58,  37,  65,  84,  110, 73,  44,
        -9,   17,  22,  54,  37,  68,  18,  22,
        -13,  4,   16,  13,  29,  19,  21,  -7,
        -23,  -9,  12,  10,  19,  17,  25,  -16,
        -29,  -53, -12, -3,  -1,  18,  -14, -19,
        -105, -21, -58, -33, -17, -28, -19, -23,
    },
    .{
        -29, 4,  -79, -37, -25, -41, 7,   -8,
        -26, 12, -18, -12, 28,  57,  21,  -47,
        -16, 37, 42,  37,  34,  51,  37,  -1,
        -4,  5,  19,  50,  37,  37,  7,   -2,
        -6,  13, 13,  26,  34,  12,  10,  4,
        0,   15, 15,  15,  14,  27,  18,  10,
        4,   15, 16,  0,   7,   21,  33,  1,
        -33, -3, -14, -21, -13, -12, -39, -21,
    },
    .{
        -16, -12, -2,  12,  14, 12, -34, -25,
        -44, -16, -20, -10, -1, 11, -6,  -71,
        -45, -25, -16, -17, 3,  0,  -5,  -33,
        -36, -26, -12, -1,  9,  -7, 6,   -23,
        -24, -11, 7,   26,  24, 35, -8,  -20,
        -5,  19,  26,  36,  17, 45, 61,  16,
        26,  31,  57,  62,  80, 67, 26,  44,
        32,  42,  32,  51,  63, 9,  31,  43,
    },
    .{
        -28, 0,   26,  11,  48,  41,  43,  45,
        -24, -39, -4,  0,   -16, 53,  28,  54,
        -13, -17, 7,   8,   29,  57,  47,  57,
        -27, -27, -15, -16, -1,  18,  -2,  1,
        -9,  -26, -9,  -10, -2,  -4,  3,   -3,
        -14, 2,   -11, -2,  -5,  2,   14,  5,
        -35, -8,  11,  2,   8,   15,  -3,  1,
        -1,  -18, -9,  10,  -15, -25, -31, -50,
    },
    .{
        -15, 36,  12,  -54, 8,   -29, 22,  8,
        1,   7,   -8,  -64, -43, -16, 11,  8,
        -14, -14, -22, -46, -44, -30, -15, -27,
        -49, -1,  -27, -39, -46, -44, -33, -51,
        -17, -20, -12, -27, -30, -25, -14, -36,
        -9,  24,  2,   -16, -20, 6,   22,  -22,
        29,  -1,  -20, -7,  -8,  -4,  -38, -29,
        -65, 23,  16,  -15, -56, -34, 2,   13,
    },
};

pub const pst_eg: [6][64]i16 = .{
    .{
        0,   0,   0,   0,   0,   0,   0,   0,
        -3,  -3,  10,  0,   14,  7,   -4,  -18,
        -2,  -1,  4,   19,  8,   10,  -6,  -12,
        16,  3,   -11, -6,  -3,  -13, 1,   -4,
        33,  23,  13,  2,   -2,  4,   18,  16,
        56,  37,  41,  22,  26,  51,  56,  24,
        134, 108, 109, 107, 105, 104, 112, 108,
        0,   0,   0,   0,   0,   0,   0,   0,
    },
    .{
        -58, -38, -13, -28, -31, -27, -63, -99,
        -25, -8,  -25, -2,  -9,  -25, -24, -52,
        -24, -20, 10,  9,   -1,  -17, -19, -41,
        -17, 3,   22,  22,  22,  11,  8,   -18,
        -18, -6,  16,  25,  16,  17,  4,   -18,
        -23, -3,  -1,  15,  10,  -3,  -20, -22,
        -42, -20, -10, -5,  -2,  -20, -23, -44,
        -29, -51, -23, -15, -22, -18, -50, -64,
    },
    .{
        -14, -21, -11, -8,  -7, -9,  -17, -24,
        -8,  -5,  7,   -12, -3, -13, -4,  -14,
        2,   -8,  0,   -1,  -2, 6,   0,   4,
        -3,  9,   12,  9,   14, 10,  3,   2,
        -6,  3,   13,  19,  7,  10,  -3,  -9,
        -12, -3,  8,   10,  13, 3,   -7,  -15,
        -14, -18, -7,  -1,  4,  -9,  -15, -27,
        -23, -9,  -23, -5,  -9, -16, -5,  -17,
    },
    .{
        -9, 2,  3,  -1, -5, -10, 4,   -20,
        -6, -6, 0,  2,  -9, -9,  -11, -3,
        -4, 0,  -5, -1, -7, -12, -8,  -16,
        3,  5,  8,  4,  -5, -6,  -8,  -11,
        4,  3,  13, 1,  2,  1,   -1,  2,
        7,  7,  7,  5,  4,  -3,  -5,  -3,
        11, 11, 9,  9,  -3, 3,   8,   3,
        13, 10, 18, 15, 12, 12,  8,   5,
    },
    .{
        -9,  22,  22,  27,  25,  19,  10,  20,
        -17, 20,  32,  41,  58,  25,  30,  0,
        -20, 6,   9,   49,  47,  35,  19,  9,
        3,   22,  24,  45,  57,  40,  57,  36,
        -18, 28,  19,  47,  31,  34,  39,  23,
        -16, -27, 15,  6,   9,   17,  10,  5,
        -22, -23, -30, -16, -16, -23, -36, -32,
        -33, -28, -22, -43, -5,  -32, -20, -41,
    },
    .{
        -74, -35, -18, -18, -11, 14,  -4,  -19,
        -12, 17,  14,  17,  17,  32,  20,  10,
        10,  17,  23,  15,  20,  42,  36,  13,
        -8,  22,  24,  27,  26,  33,  26,  3,
        -18, -4,  21,  24,  27,  23,  9,   -11,
        -19, -3,  11,  21,  23,  16,  7,   -9,
        -27, -11, 4,   13,  14,  4,   -5,  -17,
        -53, -34, -21, -11, -28, -14, -24, -43,
    },
};

pub const passed_mg: [8]i16 = .{
    0, 4, 6, 6, 23, 91, 91, 0,
};

pub const passed_eg: [8]i16 = .{
    0, 6, 8, 52, 84, 111, 121, 0,
};

// A candidate is not yet passed: every adjacent-file stopper must first be
// exchanged by a distinct pawn lever. These remain well below the passed-pawn
// tables after the joint fit prices the conversion chance.
pub const candidate_mg: [8]i16 = .{
    0, 0, 2, 4, 10, 24, 40, 0,
};

pub const candidate_eg: [8]i16 = .{
    0, 0, 3, 8, 18, 38, 64, 0,
};

pub const mob_n_mg: [9]i16 = .{
    0, 5, 9, 15, 20, 24, 31, 36, 40,
};

pub const mob_n_eg: [9]i16 = .{
    0, 5, 10, 16, 21, 26, 30, 35, 37,
};

pub const mob_b_mg: [14]i16 = .{
    0, 4, 8, 13, 22, 27, 32, 36, 40, 45, 50, 55, 60, 65,
};

pub const mob_b_eg: [14]i16 = .{
    0, 7, 14, 22, 30, 38, 45, 51, 56, 63, 69, 76, 84, 91,
};

pub const mob_r_mg: [15]i16 = .{
    -1, 1, 2, 2, 2, 7, 7, 10, 13, 14, 14, 14, 14, 14, 14,
};

pub const mob_r_eg: [15]i16 = .{
    0, 7, 14, 21, 28, 36, 45, 50, 58, 67, 71, 77, 83, 90, 96,
};

pub const mob_q_mg: [28]i16 = .{
    0,  2,  4,  6,  8,  9,  11, 13, 16, 18, 20, 23, 25, 26,
    28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54,
};

pub const mob_q_eg: [28]i16 = .{
    0,   12,  24,  36,  48,  60,  72,  84,  96,  108, 120, 132, 144, 156,
    168, 180, 192, 204, 216, 228, 240, 252, 264, 276, 288, 300, 312, 324,
};

pub const phase_weight: [7]u8 = .{ 0, 0, 1, 1, 2, 4, 0 };
pub const phase_total: u8 = 24;

pub const doubled = [2]i16{ 0, -8 };
pub const isolated = [2]i16{ -1, -10 };
pub const connected = [2]i16{ 14, 0 };
pub const bishop_pair = [2]i16{ 31, 50 };
pub const rook_open = [2]i16{ 31, 6 };
pub const rook_semi_open = [2]i16{ 12, 13 };
pub const rook_seventh = [2]i16{ 5, 22 };
pub const pawn_threat = [2]i16{ 56, 24 };
pub const tempo: i16 = 15;

// Step-5.3.3 pawn refinements. A backward pawn cannot advance without being
// taken and is not defended by a neighbour, so it is a lasting weakness rather
// than a momentary one; the penalty is larger when the file is open, because
// the enemy can then attack it with heavy pieces.
pub const backward = [2]i16{ -7, -13 };
pub const backward_open = [2]i16{ -12, -9 };

// Step-5.3.10 pawn completion. Step 5.3.16 jointly fitted supported free
// coefficients; structurally impossible or low-support entries retain priors.
//
// `backward` and `backward_open` above were declared in Step 5.3.3 and never
// consumed by any evaluator path. This step wires them in for the first time.

// An isolated pawn with no enemy pawn on its file is weak *and* reachable: the
// enemy can double heavy pieces on the file without a pawn trade first. The
// penalty deliberately applies to isolated pawns only, not to backward ones,
// because `backward_open` already charges the open-file case for those. The
// two sets are kept disjoint so the fit is not asked to split one signal
// across two coefficients, which is the failure mode rejected MAN-E07 showed.
pub const weak_unopposed = [2]i16{ -4, -8 };

// A pawn attacked by two enemy pawns and defended by none is lost material or
// a broken structure; the defender chooses which. It is charged mostly in the
// endgame, where the resulting weakness cannot be answered with activity.
pub const weak_lever = [2]i16{ 0, -13 };

// A pawn on the fifth or sixth rank standing directly behind an enemy pawn has
// spent its advance and cannot trade; the file is closed for it. The two
// entries are the fifth and sixth relative ranks, in that order.
pub const blocked_pawn = [2][2]i16{ .{ -11, -3 }, .{ -4, 2 } };

// Connected pawns, by relative rank. A chain is worth more the further it has
// advanced, because the squares it denies are closer to the enemy camp. The
// base is multiplied by `2 + phalanx - opposed` and halved, so a pawn beside
// its neighbour is worth half again as much as one merely defended from
// behind, and a pawn whose file is blocked by an enemy pawn is worth half.
pub const connected_mg = [8]i16{ 0, 4, 6, 9, 16, 30, 54, 0 };
pub const connected_eg = [8]i16{ 0, 0, 2, 4, 10, 24, 48, 0 };
// Each own pawn actually defending it, over and above the chain value.
pub const connected_support = [2]i16{ 7, 8 };

// Step-5.3.10 passed pawns. The rank tables above say how far a passer has
// come; everything here says whether it can actually go anywhere.

// By distance from the nearest edge. A passer on a rook file is easier for a
// lone king to stop, because the king has fewer squares to cover behind it.
pub const passed_file = [4][2]i16{ .{ -5, -3 }, .{ -2, -2 }, .{ 1, 2 }, .{ 2, 3 } };

// The square directly ahead decides whether the pawn moves at all.
pub const passed_blocked = [2]i16{ -8, -18 };
pub const passed_stop_attacked = [2]i16{ -6, -15 };
pub const passed_stop_defended = [2]i16{ 5, 13 };
// Every square between the pawn and promotion contributes independently.
// Defence is useful even when another path square is unsafe, while repeated
// enemy control makes conversion progressively less credible.
pub const passed_path_attacked = [2]i16{ -3, -11 };
pub const passed_path_defended = [2]i16{ 3, 7 };

// King proximity to the square in front of the passer, endgame only, scaled by
// how far the pawn has advanced. A pawn on the seventh is decided by whose
// king reaches it; a pawn on the third is not.
pub const passed_king_own: i16 = -8;
pub const passed_king_their: i16 = 14;

// Step-5.3.11 piece detail. Step 5.3.16 jointly fitted supported free
// coefficients. Indexed `[knight, bishop]` where a term applies to both minors,
// because the same fact is worth different amounts to a piece that jumps and
// one that slides.

// A minor on a square our pawn defends and no enemy pawn can ever attack is
// permanent: it cannot be driven away by a pawn, only traded. The bishop earns
// less than the knight because a bishop already reaches distant squares and
// gains less from a fixed home.
pub const outpost = [2][2]i16{ .{ 31, 15 }, .{ 18, 6 } };
// A knight on an outpost outside the centre files that attacks nothing worth
// attacking is well placed and irrelevant, which is a different thing from
// being well placed.
pub const bad_outpost = [2]i16{ -8, -3 };
// A knight one move away from an outpost it can actually occupy.
pub const reachable_outpost = [2]i16{ 14, 7 };
// A minor directly behind a pawn of either colour is shielded from frontal
// attack while it develops.
pub const minor_behind_pawn = [2]i16{ 11, 4 };
// A minor far from its own king defends nothing when the king is attacked.
// Charged per square of king distance, so it is a gradient rather than a
// cliff, and more for the knight because it needs more moves to come back.
pub const king_protector = [2][2]i16{ .{ -1, -1 }, .{ -1, -1 } };

// Our own pawns standing on the bishop's square colour are the pawns it can
// never defend or pass. The penalty is multiplied by whether the bishop is
// itself outside our pawn chain and by how blocked the centre is, because a
// bad bishop behind a locked centre is the losing kind.
pub const bishop_pawns = [2]i16{ -1, -5 };
// Enemy pawns on the bishop's diagonals as if the board were empty: they are
// the ones it will still be looking at after the position opens.
pub const bishop_xray_pawns = [2]i16{ -5, -4 };
// A bishop seeing both central squares through pawns only.
pub const long_diagonal_bishop = [2]i16{ 21, 6 };
// A bishop whose diagonals reach the enemy king ring once pawns are removed,
// counted only when it is not already a direct attacker.
pub const bishop_on_king_ring = [2]i16{ 24, 0 };

// A rook sharing a file with a queen of either colour is pointed at the most
// valuable target on the board.
pub const rook_on_queen_file = [2]i16{ 6, 11 };
// A rook whose file reaches the enemy king ring, counted only when it is not
// already a direct attacker.
pub const rook_on_king_ring = [2]i16{ 16, 0 };
// A rook with almost no moves, shut in on the same side as its own king. It is
// worse when the king can no longer castle, because castling is the move that
// would have freed it.
pub const trapped_rook = [2]i16{ -54, -13 };
// Rook mobility at or below which the trapped test applies.
pub const trapped_rook_mobility: u32 = 3;

// An enemy rook or bishop x-raying the queen through a single blocker: the
// queen is tied to the blocker whether or not the pin is absolute.
pub const weak_queen = [2]i16{ -54, -15 };
// A queen past the middle of the board on a square no enemy pawn can attack,
// now or after any advance.
pub const queen_infiltration = [2]i16{ 0, 15 };

// Step-5.3.12 threats. Step 5.3.16 jointly fitted supported free coefficients.

// A pawn we can afford to leave where it stands, attacking a piece: the
// opponent must move or lose material, and a pawn is the cheapest attacker
// there is.
pub const threat_by_safe_pawn = [2]i16{ 171, 93 };
// The same threat one move away. Worth much less because it is answerable,
// but it constrains where enemy pieces may stand.
pub const threat_by_pawn_push = [2]i16{ 46, 37 };
// Squares from which we could check or fork the enemy queen next move. The
// queen must keep watching them, which is a standing cost even unrealised.
pub const knight_on_queen = [2]i16{ 15, 10 };
pub const slider_on_queen = [2]i16{ 54, 16 };
// An enemy piece whose moves we contest on a square it is not strongly
// protected on. This prices restriction rather than capture.
pub const restricted_piece = [2]i16{ 0, 0 };
// A weak piece whose only defender is the queen is barely defended at all:
// the queen cannot afford the trade it would have to accept.
pub const weak_queen_protection = [2]i16{ 14, 0 };

// Step-5.3.12 king safety. The first three feed accumulated danger before it
// is squared; the last two are ordinary tapered scores.

// A piece pinned in front of our own king cannot step aside to defend it.
pub const king_blocker_danger: i32 = 98;
// Sustained pressure on the king's flank, counted over the squares the
// attacker holds there and again over those it holds twice. Squared like the
// rest of danger, so it is divided back down before joining the sum.
pub const king_flank_attack_danger: i32 = 3;
pub const king_flank_defense_danger: i32 = 4;
// The same flank pressure also costs an ordinary score, because it restricts
// the defender whether or not it ever becomes an attack.
pub const flank_attacks = [2]i16{ 3, 2 };
// A king on a flank with no pawn of either colour has no cover to lose and no
// cover to rely on.
pub const pawnless_flank = [2]i16{ -17, -95 };

// Shelter and storm, indexed by how far the relevant pawn stands from the
// king's own rank. Index zero means no pawn on that file at all, which is the
// worst case for shelter and the least urgent for a storm.
//
// Shelter rewards an own pawn still standing in front of the king; the closer
// it is, the more cover it gives. Storm penalises an enemy pawn bearing down;
// the closer it is, the more dangerous, except that a pawn already touching
// our own is blocked and far less threatening.
pub const shelter_rank = [2][8]i16{
    .{ -14, 38, 29, 15, 6, 2, 0, 0 },
    .{ -6, 28, 22, 11, 5, 1, 0, 0 },
};
pub const storm_rank = [8]i16{ 0, -6, -30, -18, -7, -3, -2, 0 };
pub const storm_blocked = [8]i16{ 0, 0, 12, 8, 3, 0, 0, 0 };
// A king on a file with no pawn of either colour is exposed to heavy pieces.
pub const king_open_file = [2]i16{ -25, 4 };
pub const king_semi_open_file = [2]i16{ -10, 2 };

// Step-5.3.5 king safety. Attack weight is per attacking piece type and
// reflects how much pressure that piece can generate against a king, not its
// material value: a queen dominates, a lone knight matters little.
pub const king_attack_weight: [7]i16 = .{ 0, 0, 20, 18, 32, 62, 0 };
pub const king_pawn_attack_weight: i32 = 12;
pub const king_no_queen_relief: i32 = 52;
pub const king_defender_queen_relief: i32 = 18;
pub const king_pawn_proximity: i16 = -1;
// A check that lands on a square the defender does not control is far more
// dangerous than one that can simply be captured.
pub const safe_check_weight: [7]i16 = .{ 0, 0, 72, 54, 82, 92, 0 };
pub const unsafe_check_weight: i16 = 12;
// Squares in the ring that we attack but do not defend.
pub const king_ring_weak: i16 = 34;
// Danger converts to a score with a square law: two attackers are far worse
// than twice one attacker, which is the chess fact this shape encodes. The
// divisor sets the scale at which that curve reaches material relevance.
pub const king_danger_divisor: i32 = 640;

// Step-5.3.6 threats. A piece the opponent attacks and we do not adequately
// defend is liable to be lost or to cost a tempo, and the loss is larger the
// more valuable the piece. Minor-on-minor pressure matters less than pressure
// against a rook or queen, which cannot retreat as cheaply.
pub const threat_by_minor: [7][2]i16 = .{
    .{ 0, 0 }, .{ 6, 20 }, .{ 22, 26 }, .{ 24, 28 }, .{ 38, 20 }, .{ 42, 14 }, .{ 0, 0 },
};
pub const threat_by_rook: [7][2]i16 = .{
    .{ 0, 0 }, .{ 2, 20 }, .{ 20, 26 }, .{ 20, 26 }, .{ 0, 0 }, .{ 36, 16 }, .{ 0, 0 },
};
// A piece with no defender at all is a standing liability, not merely a
// piece under pressure.
pub const hanging = [2]i16{ 34, 20 };
// A king that can safely touch an enemy piece wins it outright in most
// endings, which is why this is weighted toward the endgame.
pub const threat_by_king = [2]i16{ 18, 42 };
// Central home-half squares that we control and enemy pawns do not, counted
// twice when pawn-supported. The evaluator owns contextual weighting and the
// frozen legacy material floor; this remains the sole fitted coordinate.
pub const space_bonus: i16 = 1;

// Step-5.3.13 exact-signature endgames. These are enumerated for the fitting
// schema but excluded from the linear fit: recognizer dispatch, min/max caps
// and scale application make them a nonlinear specialized subsystem.
pub const endgame_kxk_base: i32 = 800;
pub const endgame_kxk_material = [4]i32{ 900, 500, 320, 300 };
pub const endgame_conversion = [2]i32{ 8, 12 };
pub const endgame_tempo: i32 = 6;
pub const endgame_king_geometry = [2]i32{ 3, 4 };
pub const endgame_kbnk = [3]i32{ 1450, 22, 8 };
pub const endgame_knnkp = [3]i32{ 90, 18, 5 };
pub const endgame_kpk = [4]i32{ 45, 42, 24, 18 };
pub const endgame_kqkp = [2]i32{ 220, 760 };
pub const endgame_kqkr: i32 = 620;
pub const endgame_krkb: i32 = 150;
pub const endgame_krkn: i32 = 170;
pub const endgame_krkp = [5]i32{ 60, 260, 30, 30, 24 };
pub const endgame_kbpkb = [3]i32{ 2, 18, 42 };
pub const endgame_kbpkn = [3]i32{ 8, 34, 3 };
pub const endgame_kbppkb = [3]i32{ 24, 34, 50 };
pub const endgame_kpkp = [3]i32{ 6, 24, 48 };
pub const endgame_krpkb = [2]i32{ 34, 4 };
pub const endgame_krpkr = [3]i32{ 18, 26, 4 };
pub const endgame_krppkrp = [2]i32{ 38, 52 };

// Step-5.3.14 endgame winnability. These values grade independent conversion
// routes. Step 5.3.15 enumerates but excludes them from its linear fit because
// the maximum and no-sign-flip rules make their response nonlinear.
pub const winnability_base: i32 = -26;
pub const winnability_passed: i32 = 8;
pub const winnability_pawn_count: i32 = 1;
pub const winnability_pawn_ending: i32 = 4;
pub const winnability_outflanking: i32 = 5;
pub const winnability_both_flanks: i32 = 14;
pub const winnability_infiltration: i32 = 9;
pub const winnability_almost_unwinnable: i32 = -24;
pub const winnability_max_bonus: i32 = 80;

// Step-5.3.7 endgame scaling. The endgame component is multiplied by a factor
// out of `scale_normal`, so a partially drawn ending is damped rather than
// cliff-edged to zero. Only the endgame is scaled: these are all statements
// about whether a material edge can actually be converted.
pub const scale_normal: i32 = 64;
pub const scale_draw: i32 = 0;
// Opposite-coloured bishops with no other pieces cannot cover each other's
// squares, so many otherwise winning pawn edges cannot be forced through.
pub const scale_opposite_bishops: i32 = 20;
// With other pieces still on, opposite bishops are far less drawish because
// the extra pieces cover the missing colour.
pub const scale_opposite_bishops_pieces: i32 = 44;
// A lone rook-pawn with a bishop that does not control the promotion square
// is the classic dead draw regardless of how far the pawn has advanced.
pub const scale_wrong_rook_pawn: i32 = 4;
// A bare minor advantage with no pawns converts only rarely.
pub const scale_no_pawns_minor: i32 = 8;
// Each remaining pawn makes a small material edge easier to convert, so the
// scale rises with pawn count rather than sitting at one flat value.
pub const scale_pawnful_base: i32 = 34;
pub const scale_per_pawn: i32 = 6;
