# ADR-0002: Explicit ownership, lifetimes and allocation

- Status: Accepted
- Date: 2026-08-07

## Context

Search requires large per-thread buffers, aligned TT/network storage and
bounded command payloads. Hidden/global allocation obscures failure behavior;
putting every fixed-capacity structure on an OS thread stack risks overflow.
Zig makes allocators and destruction explicit and its containers expect the
owner to supply allocation policy.

## Decision

- The composition root selects the concrete general allocator and owns final
  teardown.
- Every allocating type has an explicit `init`/`deinit` contract and receives
  an allocator at its owning operation. No global allocator is visible to core
  code.
- The controller owns current position/history and replaceable generations of
  TT, worker pool, network and tablebase resources.
- A search job immutably borrows resource generations that outlive its joined
  workers.
- Each worker owns one aligned, stable-address allocation containing fixed
  per-ply/search/evaluator arrays and histories.
- Large fixed-capacity worker arrays are heap-resident within that object, not
  local recursive variables or thread-stack aggregates.
- Chess, move generation, evaluation and node search accept no allocator and
  allocate nothing during search.
- Command and output scratch is bounded and owned by adapters/controller, then
  released after transfer/consumption.
- Reconfiguration first stops and joins active workers, retains the prior
  generation while constructing and validating a replacement, then swaps and
  destroys the prior generation. Potentially blocking file work stays in an
  outer cancellable adapter operation.

## Consequences

- Worker addresses remain stable for a current-state pointer if Phase 2 selects
  that representation.
- Search startup may allocate/resize only before publication; the timed hot
  path stays allocation-free.
- Network and TT references need no per-node refcount because replacement is
  forbidden until workers join.
- Thread-stack size is still explicit because recursion remains, but frames
  contain no large move/PV arrays.

## Verification

- Allocation-counting tests cover make/unmake, movegen, evaluate, TT and search.
- Debug tests use a leak-detecting allocator; resource failure tests preserve
  the old generation.
- Compile-time layout assertions and maximum-ply runs guard worker size,
  alignment and stack usage.
- Ownership diagrams and every `deinit` path are audited in Phase 0.3.

## Traceability

Supports `RES-004`–`RES-008`, `SAFE-004`, `SAFE-009`, `PERF-002`, `PERF-009`
and `FILE-004`.
