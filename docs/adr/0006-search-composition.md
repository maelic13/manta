# ADR-0006: Concrete evidence-coherent search composition

- Status: Accepted
- Date: 2026-08-07

## Context

Chess search needs aggressive specialization and tightly coupled evidence, but
a single unstructured search object makes root ownership, thread-local state,
TT bounds and pruning provenance easy to confuse. Object-per-heuristic designs
would add abstraction without matching Zig or the hot-path needs.

## Decision

Compose search from concrete value/state types and cohesive functions:

- immutable `SearchJob`;
- root-owned iterative deepening and completed iterations;
- per-worker `ThreadState` and per-ply `SearchStack`;
- narrowly defined `SharedSearch` for cancellation, TT and batched SMP data;
- typed `CompletedIteration` and `SearchResult`; and
- compile-time root/PV/non-PV modes where specialization improves generated
  code.

Search and pruning evidence is not represented as an unqualified integer at
consumer boundaries. Terminal, tablebase, static, lower-bound, upper-bound and
exact results remain distinguishable through compact types, compile-time node
context or proven local invariants.

One-thread search is the deterministic semantic baseline. With
`Threads = 1`, helper voting, jitter and SMP-only accounting are absent or
provably inert. Local counters are batched when shared. Four-thread time safety,
correctness, strength and scaling are independent gates.

The architecture optimizes for playing strength: heuristics may be changed
when chess semantics remain correct and registered game evidence accepts them.
Exact node counts diagnose behavior; they do not define an ideal search tree.

## Consequences

- Root publication has one owner and only completed legal iterations can become
  final results.
- Heuristics remain ablatable without strategy interfaces.
- Typed evidence prevents consumers from treating a shallow/static/TT bound as
  a proven exact result.
- The SMP algorithm and helper policy remain deferred until Phase 6.

## Verification

- Legal PV/fallback and exactly-once result process tests.
- Mate, draw, TT-bound and abort-path result tests.
- One-thread fingerprint agreement with SMP support compiled in.
- Fixed-node diagnostics plus one scope-representative registered 1T or 4T
  time-based gate for a playing change.
- Disassembly and allocation checks for recursive search.

## Traceability

Supports `FUNC-003`–`FUNC-005`, `SCORE-004`, `PERF-002`, `PERF-006`,
`PERF-010` and the Phase-4/5/6 search gates.
