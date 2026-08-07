# ADR-0009: Lock-free shared TT semantics without undefined races

- Status: Accepted
- Date: 2026-08-07

## Context

The transposition table is probed at node frequency and later shared by search
threads. Locks are unsuitable, while non-atomic shared reads/writes would be a
language-level data race. Multiword entries can tear unless their validation
protocol makes an incomplete observation a safe miss.

## Decision

- TT is a concrete internal search structure with one encoding/replacement
  semantics for 1T and SMP.
- Clusters are fixed-size, aligned and allocated as a complete generation
  outside search.
- Shared words use Zig atomic integer operations with explicitly justified
  memory ordering. No plain concurrent access is permitted.
- The encoding/validation protocol may return a miss during a race but shall
  not return an internally inconsistent hit.
- Retrieved moves are validated against the current position before they can
  influence make/unmake.
- The design uses target-supported lock-free atomic word sizes and does not
  require 128-bit lock-free atomics.
- Score-to/from-TT mate normalization and bound decoding are centralized.
- Clear, age and replacement behavior is deterministic at 1T.
- Resize occurs only while workers are joined; failed allocation retains the
  old table.
- TT is process-local and never persisted.

A non-atomic 1T storage policy is a later optional specialization, not the
baseline architecture. It must reuse the encoding/replacement algorithm,
preserve deterministic behavior and demonstrate a native speed benefit.

## Consequences

- Phase 4 must choose cluster size, atomic word layout, tag validation and
  replacement constants with layout/performance evidence.
- False misses are an accepted concurrency outcome; corrupted trusted hits are
  not.
- Atomic capability is asserted for every supported target before release.
- TT access remains direct/static in search rather than behind a runtime port.

## Verification

- Atomic/encoding model and stress tests including forced interleavings.
- TSAN-equivalent tooling when available plus long multi-thread probes/stores.
- Mate/bound round trips, move validation and deterministic 1T replacement.
- Native x86-64/ARM64 lock-free assertions and 1T/4T benchmarks.

## Traceability

Supports `SCORE-004`, `SAFE-009`, `PERF-002`, `PORT-006` and the Phase-4/6 TT
contracts.
