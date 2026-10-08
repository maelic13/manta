/*
 * Exports the vendored Fathom header's constants and layout facts that the
 * hand-written Zig declarations in syzygy.zig rely on. This translation unit
 * is the independent oracle for those declarations: it is compiled by the C
 * compiler against the real tbprobe.h, and a Zig test compares the values.
 * The order here is the order of the Zig test's expected array.
 */
#include <stddef.h>
#include <stdint.h>

#include "tbprobe.h"

const uint32_t manta_fathom_abi[21] = {
    TB_MAX_MOVES,
    TB_MAX_PLY,
    TB_LOSS,
    TB_BLESSED_LOSS,
    TB_DRAW,
    TB_CURSED_WIN,
    TB_WIN,
    TB_PROMOTES_NONE,
    TB_PROMOTES_QUEEN,
    TB_PROMOTES_ROOK,
    TB_PROMOTES_BISHOP,
    TB_PROMOTES_KNIGHT,
    TB_RESULT_FAILED,
    sizeof(TbMove),
    sizeof(struct TbRootMove),
    offsetof(struct TbRootMove, pv),
    offsetof(struct TbRootMove, pvSize),
    offsetof(struct TbRootMove, tbRank),
    sizeof(struct TbRootMoves),
    offsetof(struct TbRootMoves, moves),
    sizeof(unsigned),
};
