# ADR-0005: Statically specialized, replaceable evaluators

- Status: Accepted
- Date: 2026-08-07

## Context

Manta starts with an original HCE and later adds NNUE while keeping HCE tested
as a fallback. A runtime evaluator interface at every node would add indirect
calls; embedding evaluator state in the position would make either evaluator
difficult to replace.

## Decision

- Define the evaluator as a compile-time structural Zig contract with concrete
  evaluator and worker-state types.
- Select the active evaluator once before root search using a tagged runtime
  choice, then enter a monomorphized HCE or NNUE root/search specialization.
- Persistent workers hold a tagged union of concrete evaluator states. The
  outer switch activates one member and passes a concrete pointer inward.
- Evaluation, update and refresh calls inside recursive search are statically
  dispatched.
- Position state exposes only factual chess state and dirty-piece changes.
  HCE incremental caches and NNUE accumulator/refresh state remain evaluator
  local.
- User-facing cp conversion and mate/tablebase score bands are owned by the
  score/search presentation contracts, not evaluator-specific constants.
- Diagnostics use a compile-time sink. The production no-op implementation
  must compile out.
- Loading a replacement network is transactional and only occurs while workers
  are joined.

## Consequences

- Both evaluators can coexist in one executable with limited root-level code
  duplication and no per-node vtable.
- Additional ISA specializations may multiply code; Phase 10 measures and
  controls code size versus indirect-kernel cost.
- A replacement HCE can be written without changing position/make/unmake.
- The contract is checked by `comptime` diagnostics rather than a nominal
  language interface.

## Verification

- Compile-time contract tests intentionally instantiate valid/invalid test
  evaluators.
- HCE and NNUE state transitions compare incremental results with full refresh.
- Production disassembly rejects evaluator vtable/tag switches in recursive
  hot paths.
- Scalar/backend and trace/no-trace configurations produce exact scores.

## Traceability

Supports `SCORE-008`, `PERF-001`, `PERF-004`, `PERF-005` and the Phase-3/8
evaluator gates.
