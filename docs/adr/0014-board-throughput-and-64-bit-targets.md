# ADR-0014: Board throughput specialization and 64-bit target boundary

- Status: Accepted
- Date: 2026-08-10
- Supersedes: ADR-0013's initial cache and x86 sliding-backend choices

## Context

The accepted Phase-2 board was correct but a controlled
`cross-engine-board-v1` comparison on the designated Ryzen 9 5950X showed a
large throughput deficit to the reference implementation. Profiling was
unavailable without an elevated Windows sampling session, so emitted-code
inspection, isolated primitive probes and interleaved native ReleaseFast A/B
runs were used. The maintainer also fixed Manta's product boundary at 64-bit
x86-64 and ARM64;
supporting 32-bit layouts would add constraints with no product value.

## Decision

Manta supports only x86-64 and ARM64. All 32-bit targets fail build
configuration. Process-local hot structures may rely on 64-bit pointers and
`usize`; protocols, persisted formats and externally visible counters retain
their explicitly sized contracts.

Keep ADR-0013's hybrid mailbox, piece-type bitboards, color occupancy, compact
moves and caller-owned state. Refine its initial performance choices as follows:

- cache each king square in the physical position and maintain it with every
  rebuild, put, remove and move;
- use pointer-width `usize` for `MoveList.count` on the supported 64-bit
  targets;
- expose aligned typed sliding-attack tables rather than byte-wise embedded
  reads;
- in native BMI2 x86-64 builds, transform the checked magic-order asset to PEXT
  order at compile time and use the hardware instruction; retain magic lookup
  for portable x86-64 and hyperbola quintessence for ARM64;
- specialize legal generation by compile-time color and exact generation mode,
  generate ordinary pawns setwise, use static empty-board rays for pinner
  discovery and use short-circuit boolean king-safety queries where only a
  boolean is consumed; and
- retain full legal-capture semantics in threshold SEE while carrying attacker
  sets and revealed slider rays incrementally.
- omit the frame pointer explicitly in ReleaseFast x86-64 engine modules after
  controlled evidence showed lower register pressure; keep the default on
  ARM64 and in safety/debug modes until target-native evidence says otherwise.

The factual move delta, all reversible rule state, legal move partition,
checked overflow behavior and scalar/exact-backend conformance remain part of
the operation. Benchmarks may not omit required state simply because no later
evaluator consumes it yet.

## Consequences

- The hot board representation has one supported native pointer shape, so no
  32-bit count, packing or alignment variants are maintained.
- BMI2 selection is a compile-time native-build specialization with no startup
  table construction or per-lookup runtime dispatch.
- Physical position and move-list layout budgets deliberately change to include
  cached king squares and a 64-bit count; independent state reconstruction must
  verify both caches.
- Compile-time table transformation increases optimized build work but not
  process startup work or runtime mutable state.
- Direct board throughput improves materially, but the benchmark remains
  diagnostic: it neither proves playing strength nor licenses a comparative
  throughput claim until every registered workload actually does.

## Verification

- Exhaustive slider subsets agree with the coordinate-ray oracle in Debug,
  ReleaseSafe and ReleaseFast, including portable magic and native BMI2 paths.
- Random legal make/unmake walks compare mailbox, bitboards, counts, king
  squares, keys, state and unwind results with full reconstruction.
- External reference-engine divide maps refute legal generation or transition
  drift.
- `cross-engine-board-v1` preflight freezes the work quanta and controlled
  interleaved 5950X A/B runs decide each performance arm.
- Native supported-target gates and explicit unsupported-architecture build
  errors enforce the 64-bit boundary.

## Traceability

Refines ADR-0013 and supports `FUNC-001`, `FUNC-002`, `RES-004`, `PERF-001`–
`PERF-005`, `PORT-003`, `PORT-006` and Phase 2 Steps 2.0–2.3.
