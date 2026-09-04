# ADR-0041: Main-selectivity candidate

## Status

Rejected as MAN-S20 on 2026-08-15. Deterministic qualification passed, but
the registered maintainer-owned cluster SPRT accepted H0.

## Context

MAN-S19 freezes raw/pruning evaluation and TT provenance, MAN-S15 freezes the
depth/move-index LMR surface, and MAN-S17 freezes accepted quiet context. Main
selectivity still consumes those facts independently: verified null move has a
fixed reduction, ProbCut treats non-cutting TT records as ordering hints, and
shallow quiet/capture pruning does not use accepted contextual history or the
TT-refined pruning estimate. The rejected MAN-S16 capture table and MAN-S18
LMR vote policy supply no accepted authority and remain off.

The pinned final pre-NNUE Stockfish source demonstrates the dependency concepts
of depth/eval-sensitive null probes, reduced-horizon TT/ProbCut interaction and
history/eval-aware move pruning. Manta does not copy its formulas, constants,
tables or behavior; each policy below is derived from Manta's typed evidence,
pawn scale and existing verified paths.

## Decision

- Preserve MAN-S03's always-verified null proof and pawn-only guard. Starting
  from reduction two, nominal depth at least eight and a two-pawn pruning-eval
  margin may each add one probe ply; retain at least one ordinary probe ply and
  two same-node verification plies, using the identical reduction for both.
- At an otherwise eligible ProbCut node, accept a TT decision only when its
  ordinary searched provenance owns at least ProbCut's reduced parent horizon.
  Lower/exact evidence at or above raised beta returns fail-hard ProbCut beta;
  upper/exact evidence below it suppresses only the redundant speculative
  probe. Shallower, reduced-fail-low, null, terminal, stand-pat, fallback,
  exclusion, speculative and tablebase producers remain unusable.
- Derive positive/negative/neutral confidence by majority direction across
  accepted main, reply and continuation quiet histories. Positive/negative
  confidence moves the late-move count threshold by one; positive confidence
  also protects a quiet-futility candidate. The first searched move, PV,
  zero-window, ordinary-score, pawn-only and post-move-check guards remain.
- Capture futility can only tighten MAN-S11's depth-only SEE threshold. It asks
  whether tactical gain bridges alpha from MAN-S19 pruning evaluation after a
  one-pawn cushion per remaining ply. It never relaxes SEE; promotions remain
  excluded and every rejected candidate is made before a checking move is
  exempted.
- Keep one umbrella plus dynamic-null, ProbCut-TT, history-pruning and capture-
  futility compile-time switches. The umbrella-off fingerprint must be exact
  MAN-S19. No component changes storage, trains evidence or gains score, PV,
  terminal/draw, full-depth TT or legality authority.

## Consequences

Ordinary nodes remain allocation-free, lock-free and concretely specialized.
All new state is stack-local; histories remain worker-local and TT layout is
unchanged. The cluster may search more or fewer nodes because positive history
protects plausible quiet moves while the other arms remove redundant probes.
That tree shape is diagnostic, not a strength claim.

Cluster-off is exact MAN-S19 `744,899`; MAN-S20 is `761,703`. Debug and
ReleaseSafe gates, UCI transcripts, legal PV/state, mate/draw/zugzwang and
focused reduction/threshold/provenance tests pass. Two normalized
`manta-search-observation-v17` reports match at SHA-256
`8A7D57EC50FAC61662FFE15CB4DDA274A0FC9B83C56C2CA2F9C190F8C7F57023`.
Across 334,249 nodes every component is populated; both pawn-only cases record
zero selectivity activity.

The candidate-as-A 1T `3+0.03`, Hash-64, concurrency-14, normalized `[1,5]`
SPRT accepted H0 after 2,798 scored games: 597-750-1,451, pentanomial
`[77,389,598,280,55]`, `-29.25 +/- 12.87` nElo and LLR -2.96. The log has no
infrastructure anomaly; one completed in-flight PGN draw was excluded from the
paired verdict. The umbrella therefore defaults off and exact MAN-S19 remains
production. No immediate retune or component ablation is justified. A future
design may be proposed only at Step 5.4.2 if frozen HCE/correction/depth
evidence demonstrates a measured compatibility gap and supplies a structurally
new consumer relation. Repeated production `manta-search-observation-v18`
reports match at SHA-256
`A03E462F7B48AB61C3205C4EA85B17C731480BEFD9648D044B010FA2EB30EC43`
and prove zero activity from every rejected arm.

## Traceability

Supports `FUNC-004` through `FUNC-006`, `SCORE-001`, `SCORE-004`, `SCORE-010`,
`SCORE-012`, `SCORE-013`, `SCORE-016`, `SCORE-018`, `SCORE-020`, `SCORE-021`,
`PERF-006`, `PERF-009`, `PERF-010`, `QUAL-013` through `QUAL-017`, and Step
5.1.5.7 in `PLAN.md`.
