# ADR-0003: Position/state separation and evidence-led representation selection

- Status: Accepted
- Date: 2026-08-07

## Context

A chess position combines physical piece placement, reversible rule state,
derived king geometry, pre-search game history and evaluator-specific
incremental state. Treating them as one copyable heap-owning board makes
make/unmake, repetition, NNUE and worker cloning difficult. Selecting exact
bitboard/mailbox layouts without Zig measurements would nevertheless be
premature.

## Decision

Separate:

- `PhysicalPosition`: selected piece placement/occupancy representation;
- `PositionState`: one caller-owned record per ply containing reversible rule
  state, keys, cached factual geometry, capture/repetition/null information and
  factual dirty-piece deltas;
- `GameHistory`: controller-owned pre-search keys/state needed for draws; and
- evaluator-local state: HCE or NNUE stacks owned by each worker.

Phase 2 chooses the physical representation and current-state link through an
ADR backed by correctness and measurement. Required candidates/criteria cover:

- piece bitboards, occupancy, mailbox and deliberately redundant forms;
- legal generation, captures, SEE, make/unmake and full search workloads;
- `@sizeOf`, alignment, cache footprint and copy behavior;
- Debug/ReleaseSafe safety and ReleaseFast generated code;
- current-state pointer versus checked index/cursor;
- x86-64 and ARM64 suitability; and
- future dirty-piece/NNUE and centralized castling needs.

The architecture does not require a generic runtime variant interface. Standard
chess is the only implementation. Castling and other rule facts stay
centralized so a future variant need not invade search/evaluation.

## Consequences

- Factual cached geometry may be maintained incrementally when full-search
  evidence supports it.
- Evaluator constants/caches cannot leak into the general position.
- Exact representation, attack generation and byte budgets remain open until
  Phase 2.
- Position copies require an explicit root/worker cloning contract rather than
  accidental copying of borrowed state.

## Verification

- Candidate representations pass identical perft, state recomputation and
  randomized round-trip suites before timing.
- Layout and clone/rebind invariants are compile-time and runtime tested.
- Board benchmarks state the exact representation/work contract and full
  search validates the selected winner.
- Architecture lint forbids evaluation-specific fields in chess state.

## Traceability

Supports `FUNC-001`, `FUNC-002`, `SCORE-003`, `PERF-001` and the Phase-2 board
selection contract.
