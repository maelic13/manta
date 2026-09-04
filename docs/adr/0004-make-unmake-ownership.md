# ADR-0004: Caller-owned make/unmake state and history

- Status: Accepted
- Date: 2026-08-07

## Context

Search performs make/unmake at node frequency. Hidden history vectors, board
copies, allocations and broad error handling are costly and make ownership
unclear. External move application, by contrast, must reject malformed or
illegal input transactionally.

## Decision

- A search worker supplies bounded per-ply state storage.
- Hot `makeMove` receives the next state slot, records all information needed
  for restoration, updates physical placement/keys/factual caches, and emits a
  dirty-piece delta.
- `unmakeMove` reverses physical placement and restores the prior state without
  allocation, full-position copying or unrelated recomputation.
- Null move has a distinct internal API and state contract; it is never an
  externally supplied chess move.
- Played game ply advances only for real moves. Reversible rule counters use
  saturating arithmetic in the child state, while unmake restores the exact
  parent values through the stable state chain.
- En-passant contributes to repetition identity only when the opponent has a
  legal capture; every transition maintains full, pawn, minor and per-color
  non-pawn keys incrementally.
- Hot APIs have narrow documented preconditions established by move generation
  and assert them in safety builds.
- External/FEN/UCI application uses a checked transactional layer. On failure,
  the current valid position and history remain unchanged.
- Pre-search game history is controller-owned. A search job receives the
  bounded repetition context needed by worker-local search.
- No method silently owns or grows a history container inside the position.

## Consequences

- Search state is bounded by `MAX_PLY` plus explicit padding.
- The state slot may be addressed by pointer or index; ADR-0003 defers that
  measured choice.
- Legal/pseudo-legal generation contracts must be named precisely so a hot
  precondition cannot be misused by protocol code.
- NNUE updates can consume the same factual delta without coupling make/unmake
  to a network architecture.

## Verification

- Random legal games make/unmake to byte-equivalent initial state and recompute
  all hashes, geometry and rule counters independently.
- Special-move, null, repetition and rule-50 histories receive deterministic
  regressions plus property/fuzz coverage.
- Allocation instrumentation proves zero allocation.
- Maximum-ply and padding tests prove every state access is in bounds.

## Traceability

Supports `UCI-006`, `SAFE-003`, `SAFE-009`, `RES-005`, `RES-012` and
`FILE-004`.
