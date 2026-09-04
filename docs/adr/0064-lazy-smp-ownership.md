# ADR-0064: Main-authoritative lazy SMP ownership

## Status

Accepted for Step 6.2 on 2026-08-30. Playing strength and host scaling remain
evidence gates; this record freezes the correctness contract they will test.

## Context

Manta's one-thread search is the deterministic semantic baseline. Parallel
search may reuse its legal-move, draw/history, score/bound and completed-depth
authority, but it must not make mutable positions, histories or partial root
results concurrently owned. The transposition table already has validated
atomic probe/store semantics, so it is the narrowest useful collaboration
boundary.

Root splitting would add shared move scheduling and partial-score publication
before Manta has native SMP evidence. Identical independent searches, however,
would reproduce the same tree. Step 6.2 therefore needs explicit but bounded
diversification and a single unambiguous result owner.

## Decision

Manta uses main-authoritative lazy SMP:

- worker 0 runs the accepted iterative search and is the only owner of the
  completed score, PV, best move, soft-time decision and UCI progress;
- helpers start at deterministic staggered depths and search independently to
  contribute validated TT moves and bounds; helper results, including fully
  completed ones, never replace the main result;
- every worker owns its mutable position/repetition chain, evaluator state,
  search stack, ordering/correction/history tables and local counters;
- workers share only the atomic TT, immutable limits/parameters/tablebase
  handle, absolute time/cancellation facts and bounded aggregate counters;
- the controller advances the TT generation once per root job, before workers
  start. Concurrent reads may miss races but never trust torn evidence under
  ADR-0009;
- a user node limit is one aggregate budget. Its SMP-only counter is exact;
  ordinary searches without a node limit retain local counters and avoid a
  per-node shared atomic. Time limits are common absolute deadlines and are
  never multiplied by worker count;
- worker 0 finishing latches helper cancellation. Interrupted and partially
  searched helpers carry TT evidence only when the ordinary store contract was
  already satisfied; they have no root publication authority;
- reported final nodes and tablebase hits aggregate all workers. Live UCI
  progress remains worker-0 lower-bound evidence until final aggregation;
- perft and deterministic bench stay single-worker. With `Threads = 1`, the
  existing search specialization, histories and fingerprint remain exact;
- `Threads` is a transactional idle-barrier resource. A replacement pool is
  fully allocated and started before it becomes active; failure retains the
  previous pool and public value. Shutdown joins every owned worker;
- Step 6.2 sets no affinity or NUMA policy. The OS scheduler is authoritative
  until 1/2/4/8-thread measurements justify a topology policy. The public range
  is `1...1024`, but useful higher counts are evidence, not an assumption.

The algorithm changes neither legal-position handling, terminal/draw rules,
special-move semantics nor score/bound provenance. Each worker receives the
same complete reversible root history, so repetition remains locally exact.

## Evidence gate

Before any playing claim, focused and process tests must establish transactional
resize, joined stop/quit/EOF, legal main-owned bestmove, aggregate node limits,
one-thread inertness and a real four-worker search. The deterministic production
bench must remain `799,610`.

Then the maintainer-owned host measures zero-forfeit 1/2/4/8-thread scaling and
runs one prospective 4T `3+0.03` SPRT for the playing candidate. Failure to
scale, any time multiplication, race/forfeit, illegal result, 1T fingerprint
change or H0 closes or revises the candidate; throughput alone cannot promote
playing strength.

TT prefetch, hashfull, parallel clear, large pages and topology-aware placement
remain Phase-10 refinements.
