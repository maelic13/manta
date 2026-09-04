# ADR-0039: LMR synchronization candidate

## Status

Rejected as MAN-S18 on 2026-08-14. The registered maintainer-owned `[1,5]`
cluster SPRT accepted H0; production restores exact MAN-S17.

## Context

MAN-S15 accepted an original monotone late-move-reduction surface driven only
by nominal depth and searched legal-move ordinal. MAN-S17 then accepted
worker-local one-/two-/four-/six-ply contextual quiet evidence. Prospective
principal/cut expectation, improving trend, legal TT evidence and verified
singular status are also available, but none yet modifies the base reduction.

The isolated MAN-S14 negative reply update was correct and populated but
centered below zero in games. Reintroducing it alone or retuning a constant
would repeat that rejected hypothesis. Conversely, copying a mature engine's
continuous LMR formula would import parameters fitted to another evaluator,
ordering stack and tree. Step 5.1.5.5 therefore needs one dependency-complete,
Manta-owned consumer with explicit authority and ablation boundaries.

## Decision

- Preserve MAN-S15's depth/move-index surface as the sole base reduction.
- Let improving/non-improving trend, principal/cut expectation, legal TT-move
  presence, verified singular context and accepted-history confidence cast
  typed protect/deepen votes. Legal TT evidence protects because its bound and
  age need not be exact; a verified singular best move makes later alternatives
  eligible for deeper treatment.
- Derive history confidence from the majority direction of populated main,
  reply and continuation relations. Do not add incomparable raw magnitudes or
  let one saturated table dominate the other contexts.
- Require two agreeing independent votes before changing the base. A tie or an
  isolated fact leaves it unchanged. Protect or deepen by at most one child ply,
  retain at least one ordinary child ply and keep all existing eligibility,
  check, tactical, checking-move and singular-move guards.
- Preserve mandatory full-depth verification for every reduced alpha rise.
  Only its final authoritative result may train contextual history: positive
  when it remains above the original alpha, negative otherwise. Update reply
  and every available continuation relation after unmake, and remove the move
  from the later node-outcome population so it is not trained twice.
- Keep one umbrella plus improving, expectation, TT, singular, history,
  positive-feedback and negative-feedback compile-time switches. Record every
  signal direction, applied adjustment and feedback disposition.

## Authority and operational consequences

The bundle changes only reduction magnitude and future quiet ordering. It
creates no legality, terminal, draw, score, bound, provenance, PV or TT-store
authority. Root, null, exclusion, capture, promotion, checking, singular-move,
pruned, aborted and unsearched paths cannot train feedback. Ordinary node paths
remain allocation-free and use only worker-local state; no lock, I/O, shared
atomic or new table is introduced.

The umbrella-off depth-six fingerprint is exact MAN-S17 `755,581`; MAN-S18 is
`772,203`. ReleaseSafe, UCI transcripts, legal PV/state, mate/draw,
cancellation, agreement/bounds and per-signal accounting gates pass. Two
normalized `manta-search-observation-v14` reports match at SHA-256
`D5CD07E177C698ABDEDE60D5AB6507BF19D909F6B0CE186C441BEF2EA14D18BB`.
Across 244,254 nodes they contain 10,330 LMR probes, 142 mandatory re-searches,
141 shallower and 2,171 deeper adjustments, 36 positive and 91 negative
feedback events. Improving, expectation, TT and accepted-history consumers are
live; the rare singular vote is populated by a focused typed-evidence test.

The candidate-as-A 1T `3+0.03`, Hash-64, concurrency-14, seed-`515185`,
normalized `[1,5]`, 20,000-game-cap SPRT accepted H0 after 9,288 games in
1h24m32s: 2,242 wins, 2,361 losses, 4,685 draws, pentanomial
`[255,1174,1877,1111,227]`, `-6.61 +/- 7.07` nElo and LLR -2.96. The PGN
contains exactly the scored sample and the log has no timeout, crash, forfeit,
illegal-move or runner-error marker.

MAN-S18 therefore remains archived behind default-off compile-time switches;
production is exact MAN-S17. Its 2,171 deeper versus 141 shallower adjustments
show that an immediate constant tweak or component lottery would primarily
retune the same rejected policy, so no immediate ablation is authorized. A
conditional Step 5.1.5.8R could formulate a new mechanism only after accepted
static-evaluation, selectivity and depth work supplied a materially different,
populated reduction-confidence relation. That trigger was absent: MAN-S19 did
not add an LMR-confidence producer, MAN-S20 was rejected and MAN-S21 was not
promoted. The repeat therefore closed skipped on 2026-08-15 with no code or
games. No result licenses an isolated MAN-S14 retune or an individual
component claim.

## Traceability

Supports `FUNC-004` through `FUNC-006`, `SCORE-010`, `SCORE-013`, `SCORE-015`,
`SCORE-016`, `SCORE-018`, `SCORE-019`, `PERF-006`, `PERF-009`, `PERF-010`,
`QUAL-013` through `QUAL-017`, and Step 5.1.5.5 in `PLAN.md`.
