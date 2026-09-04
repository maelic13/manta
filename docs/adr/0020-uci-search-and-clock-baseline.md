# ADR-0020: UCI search and conservative clock baseline

## Status

Accepted for Step 4.2 on 2026-08-10; amended after MAN-S03 clock evidence on
2026-08-11 and after Step 6.1 ponder activation on 2026-08-29.

## Context

The deterministic search substrate must become a forfeit-safe one-thread UCI
engine without putting text, formatting or process I/O into chess, evaluation
or search. Search jobs need an immutable legal root and enough reversible game
history for draw semantics. Replacement, stop and shutdown must not duplicate
or lose a required result, and elapsed time must include queue/dispatch delay.

## Decision

- Keep input, UCI syntax and the sole stdout presenter in the outer adapter.
  The engine runtime owns game/history, replaceable resources, immutable jobs,
  epochs, the persistent CPU worker and typed completion values.
- Allocate one stable worker state outside search. Its persistent `std.Thread`
  waits for jobs and posts a controller semaphore immediately after writing its
  typed completion; ordinary node, move, evaluate and TT work allocates and
  formats nothing. The controller never polls completion with a timer.
- Clone only the current reversible repetition context into each job and
  rebuild its `previous` links. Position commands construct and validate a
  complete candidate before replacing the active game.
- Treat `searchmoves` as a root-only domain restriction. Suppress root TT probe
  and store for a restricted job so full-root evidence cannot bypass an
  excluded move; deeper TT evidence remains valid.
- Timestamp the complete `go` line at input. For ordinary game clocks, reserve
  `Move Overhead` independently for engine work and for scheduling/publication;
  fixed `movetime` retains its single-overhead contract. Allocate a conservative
  equal horizon share plus half increment, cap hard time at twice soft time and
  never beyond spendable clock, and use saturating absolute deadlines.
- Poll cancellation at every node and the monotonic hard deadline every 1,024
  nodes. Check the soft deadline only after a complete root iteration. On an
  early hard stop, publish the first legal permitted root move when no complete
  iteration exists.
- Use the controller epoch for urgent stop/quit/EOF, worker observation and
  exactly-once completion. Replacement and resource mutation finish the old
  job before committing the new state.
- Step 6.1 adds opt-in clock-based pondering and bounded live progress without
  changing legal-move, score, TT, fallback or stopping authority. Completed
  ponder work is retained until hit/stop; hit uses the original receipt time.

## Consequences

- One-thread results remain deterministic apart from elapsed-time fields and
  time-bounded completed depth. Clock reads and atomics are amortized or narrow;
  ordinary chess/search hot paths remain allocation- and I/O-free.
- The allocation model is intentionally conservative. Phase 6 may improve
  root-confidence allocation and add SMP/ponder behavior without changing
  receipt accounting, legal fallback or epoch ownership.
- Passing deterministic and process tests proves protocol/correctness
  properties, not tournament time safety. The zero-forfeit smoke remains a
  separate acceptance condition.
- A fastchess success exit does not prove that condition: the checked wrapper
  rejects any nonzero timeout/crash/protocol count before considering a
  statistical boundary.

## Verification

- Fake-clock tests cover zero/spent time, overhead, increments, moves-to-go,
  saturating arithmetic, soft/hard ordering, stale epochs and exact poll
  distance.
- Search tests cover legal restricted roots, warm-TT isolation, typed time
  termination, board/evaluator restoration and legal fallback/PV behavior.
- Thirteen cumulative process cases cover malformed input, readiness during
  search, transactional positions/options, replacement, repeated stop,
  movetime, zero clocks, perft, terminal roots, quit and active EOF.
- Debug, ReleaseSafe and ReleaseFast tests plus native/portable build and policy
  gates pass. The separately recorded `MAN-U01` maintainer smoke completed ten
  `3+0.03` games with zero engine faults, time losses, infrastructure faults or
  anomalies; all games ended by natural checkmate.
- MAN-S03's first 1,176-game strength run reached H1 but recorded two baseline
  timeouts. PGN timing showed Windows-tick-sized inter-search gaps from the old
  controller poll, so that result could not promote the candidate. The amended
  path then passed a zero-anomaly 100-game pilot and a zero-anomaly 1,070-game
  H1 strength run; tick-aligned move times remained at the background rate.

## Reference concepts

The amendment follows current Stockfish's infrastructure concepts: persistent
workers park on condition variables and notify completion (`src/thread.cpp`),
UCI captures the search start time before later command processing
(`src/uci.cpp`), and clock policy explicitly accounts for move overhead while
keeping maximum time below the remaining clock (`src/timeman.cpp`). Manta keeps
its typed controller/presenter ownership and simple Phase-4 allocation; no
Stockfish fitted constant or playing formula is copied.
