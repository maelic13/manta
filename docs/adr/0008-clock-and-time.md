# ADR-0008: Injected monotonic clock and receipt-based time accounting

- Status: Accepted
- Date: 2026-08-07
- Amended: 2026-08-11 and 2026-08-29

## Context

Time management must include command dispatch delay, support ponder transition
and remain deterministically testable. Reading wall time directly throughout
search couples policy to the OS and makes edge cases flaky.

## Decision

- A narrow inward `time` module owns monotonic instant/duration values and the
  clock port shared by input, controller and search. Production adapts Zig 0.16
  `std.Io` monotonic time; tests provide a deterministic fake.
- The UCI input adapter captures the timestamp when the complete `go` command
  is received, before queueing.
- Internal timestamps/durations use opaque monotonic nanoseconds with checked
  or saturating difference/addition. UCI milliseconds are boundary units.
- A pure time-policy function creates immutable soft/hard budgets and absolute
  deadlines from the job snapshot.
- Search polls time/cancellation at an adjustable node interval rather than on
  every node. The poll interval is part of stop-latency evidence.
- Ponderhit updates the active time state without restarting elapsed time.
- Until the matching epoch is hit, ponder ignores soft/hard clock deadlines but
  may finish an explicit depth/node limit. A hit activates the original
  receipt-derived deadlines, so already-spent time is never reset or credited
  twice.
- Step 6.0.4 records the hit's monotonic input-receipt timestamp before its
  epoch release and latches the saturating receipt-to-hit interval exactly once
  on the matching worker transition. It remains observational until the
  integrated time policy consumes it.
- Move overhead and scheduling reserve are explicit inputs, not hidden global
  constants.
- Worker completion wakes the controller directly. Timed polling is forbidden
  between completed engine work and publication because Windows timer
  quantization is part of clock spend and leaves the assigned CPU idle.
- Phase 4 implements a conservative deterministic 1T policy for `movetime` and
  ordinary clocks/increments/moves-to-go before strength testing begins. Phase
  6 refines soft allocation, root-confidence use, ponder behavior and SMP
  coordination without changing receipt-based accounting or hard-deadline
  safety.

## Consequences

- Time-policy arithmetic can be exhaustively unit-tested without sleeping.
- Process tests still verify real scheduling and output behavior.
- One indirect clock call at an amortized poll boundary is acceptable and must
  be measured; it is not present on every node.
- SMP workers share the job's time contract, while one owner decides final
  root stopping/publication.

## Verification

- Fake-clock boundary/property tests for zero, overflow, increments,
  moves-to-go, movetime, ponder and spent dispatch time.
- Matching/stale epoch, single-latch and reversed-timestamp properties for
  ponder credit.
- Real process tests bound stop/quit and adverse scheduling.
- Scope-matched 1T or 4T time-strength gate plus independent forfeit, process
  and scaling tests for the other dimensions.
- Profiling verifies clock polling is amortized.

## Traceability

Supports `UCI-004`, `UCI-005`, `UCI-008`, `RES-009`, `RES-010`, `PERF-010`
and the Phase-4 baseline/Phase-6 advanced clock contracts.
