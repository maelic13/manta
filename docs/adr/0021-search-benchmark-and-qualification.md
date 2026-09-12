# ADR-0021: Search benchmark and qualification boundary

## Status

Accepted 2026-08-10; presentation amended 2026-09-09.

## Context

Manta needs deterministic whole-search evidence that detects accidental search,
ordering, cache and reset changes without misrepresenting node count or shallow
tactical tests as playing strength. The workload must be independent of prior
UCI game state and configurable engine resources, bounded in ordinary CI, and
cancellable through the existing controller/worker ownership model.

## Decision

- `manta-search-bench-v1` owns an ordered 40-position legal corpus, default
  depth 6, repeat/thread defaults of one, and a repeat cap of 16.
- A bench job allocates a private 16 MiB TT at the controller boundary. Each
  repeat clears it and quiet-ordering history once; positions within the repeat
  deliberately share those caches. The resource is freed at completion.
- Bench ignores current Hash, Threads and game position. Phase 4 accepts only
  one thread; Phase 6 owns any multi-thread diagnostic semantics.
- The fingerprint is cumulative main-search plus quiescence node visits from
  iterative searches of all positions. The first accepted depth-6 total is
  `9,135,205`; the bounded depth-one reset signature is `38,164`.
- Typed completion records cross the worker boundary. Only the UCI presenter
  formats ordered position/run/summary or cancellation lines, and bench never
  publishes `bestmove`. The public form is `bench [depth] [repeats]`, matching
  Rarog's argument order while retaining Manta's depth-six default. Single-run
  position lines and the final aggregate block use the Rarog layout and fields,
  including completed score/depth and the maximum-node position behind top
  share.
- Repeated fresh-reset/node-limit searches, duplicate short fixed-node self-play
  and tactical/mate/KQK/KBNK canaries are correctness diagnostics. Registered
  games remain the only playing-strength verdict.

## Consequences

Any fingerprint change requires a causal ledger entry, the old and new totals,
and complete correctness evidence. Timing, NPS, EBF and concentration fields
remain descriptive; speed claims require the separate controlled A/B method.
The private table adds memory only while bench runs, and ordinary search hot
paths gain no allocation, I/O, lock or runtime indirection.

The presentation amendment changes no bench input or search behavior. The
accepted MAN-S34 depth-six total was `775,451`, with geomean EBF `4.821`,
upper median `12,447` nodes and maximum-position share `16.9%` (`130,895`
nodes). Step 6.5.10.1's accepted MAN-S35 mate windows later moved the
production total to `642,336`, geomean EBF `4.703`, upper median `12,201` and
share `16.1%` (`103,615`). Wall time and NPS remain run-specific diagnostics.

## Verification

Supports `UCI-001`, `UCI-002`, `PERF-006`, `QUAL-011`, `QUAL-015` and `REL-004`
through `tests/bench_qualification.zig`, `tests/search_qualification.zig`, the
Phase-4.3 process transcript and the required optimization/target matrix.
