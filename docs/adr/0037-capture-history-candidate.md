# ADR-0037: Bounded capture-history ordering candidate

## Status

Rejected as MAN-S16 on 2026-08-14. The registered `[1,5]` SPRT accepted H0;
the mechanism is retained behind a default-off diagnostic switch and MAN-S15
remains production.

## Context

MAN-S15 orders captures by TT precedence and an authoritative SEE good/bad
partition, but equal-stage captures retain generation order. Search outcomes
already distinguish completed exact/cutoff evidence from fail-low, reduced,
pruned and aborted work. A small worker-local history can therefore learn which
tactical relations tend to resolve nodes without changing which captures are
legal, tactically admissible or reusable as score evidence.

The relation must represent Manta's chess facts rather than copy a foreign
table shape or tuning constants. It must also remain independently testable
before later continuation, LMR and selectivity clusters consume richer history.

## Decision

- Key each capture by resulting mover type, destination normalized to the side
  to move, and actual victim type. En-passant names the pawn removed off the
  destination; promotion captures name the promoted mover, preserving all four
  promotion alternatives.
- Store signed bounded `i16` evidence in one fixed 6 x 64 x 6 table inside each
  worker's ordering state. Use the existing depth-squared bounded-gravity
  update law; perform no allocation, I/O, locking or shared atomic operation.
- Train only completed non-root, non-exclusion main-search exact/cutoff nodes
  whose best move is a capture. Reward that winner and penalize only distinct
  capture relations which survived pruning and were actually searched.
  Fail-low, reduced-only, pruned, aborted, unsearched, root, null and exclusion
  evidence cannot train.
- Consume the value only as the stable history tie-breaker inside the existing
  SEE-defined good- or bad-tactical stage in main search, quiescence and
  ProbCut. SEE membership, move legality, score/bound/provenance, PV/TT,
  terminal/draw, pruning and reduction policy remain unchanged.
- Add `Features.capture_history`; disabling it restores MAN-S15 exactly.

## Evidence and registered gate

Independent properties cover color symmetry, en-passant, promotion identity,
bounded gravity, stage isolation and feature-off generation order. Existing
legal-PV/state, draw/mate, cancellation, TT authority and UCI gates remain
mandatory. The candidate fingerprint is `719,564`; feature-off is exact MAN-S15
`750,869`. Two `manta-search-observation-v11` reports match at SHA-256
`BAB955D764C55A6E06CCE94D638DCEFFB808FCE7F69CA8A7EC6990A1DF5FA3BE`.
Across 122,976 nodes they record 38,755 selections (10,560 main, 28,184
quiescence, 11 ProbCut), 17,091 nonzero selections, 45 exact and 4,700 cutoff
rewards, and 319 searched-alternative penalties.

The gate used the designated Ryzen 9 5950X, candidate as A, one
search thread per engine, `3+0.03`, Hash 64 MiB, concurrency 14, pinned opening,
adjudication and physical-core placement, seed `515163`, normalized `[1,5]`,
and a 20,000-game cap. It accepted H0 after 3,868 scored games/1,934 pairs in
35m12s: 829 wins, 977 losses, 2,062 draws, pentanomial
`[117,504,796,444,73]`, `-20.07 +/- 10.95` nElo and LLR -2.95. The log contains
no infrastructure anomaly; 14 completed in-flight games were excluded from
the paired statistic. Production defaults the switch off. Two
`manta-search-observation-v12` reports match at SHA-256
`67A74760E21D614AC3F5A2EDFDD07F758718AF042266C0F772D972BB8DF0915D`,
restore MAN-S15's 124,188-node population and record zero capture-history
producer or consumer activity.

## Consequences

The table adds 9 KiB to every worker and one bounded lookup to tactical ranking.
It reduced the diagnostic tree but lost decisively in registered games, so the
smaller tree was harmful rather than strength evidence. The likely mechanism
class is reinforcement of shallow/context-poor tactical outcomes, but the gate
licenses rejection rather than a causal claim about one update component.

Later continuation and LMR/selectivity clusters must start from MAN-S15 and may
not silently read this rejected evidence. This ADR does not license capture
pruning, qsearch delta/futility, shared history, retuning or a bundled retry.

## Traceability

Supports `FUNC-004` through `FUNC-006`, `SCORE-001`, `SCORE-010`, `SCORE-012`,
`SCORE-017`, `PERF-006`, `PERF-009`, `PERF-010`, `QUAL-013` through `QUAL-017`,
and Step 5.1.5.3 in `PLAN.md`.
