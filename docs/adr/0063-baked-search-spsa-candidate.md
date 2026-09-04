# ADR-0063: Baked complete-search SPSA candidate

## Status

Accepted H1 and promoted on 2026-08-26. MAN-S29 is the production one-thread
classical search policy on MAN-E19; the temporary bake selector is retired.

## Context

MAN-S28 completed its prospectively fixed 2,000-iteration/64,000-game horizon
without anomaly. Its ten coordinates jointly control tactical pre-verification,
static pruning, LMR magnitude, late-move allowances, SEE/delta selectivity and
contextual quiet ordering. Selecting or ablating individual coordinates after
observing one joint estimator would create unsupported post-hoc experiments.
Step 5.4.6 therefore permits one rounded, cohesive bake and one net playing
gate.

The directional changes are not uniformly more or less selective. Lower
reverse-futility margin and larger LMR extra scale can cut more aggressively;
larger late-move allowances and qsearch delta cushion protect more moves. The
history weights change ordering only. Their interaction changes branch shape
and search time, so node count and NPS are diagnostics, not promotion evidence.

## Decision

Register `MAN-S29` as the nearest-integer rounding of the complete MAN-S28
theta:

| Option | MAN-S19 | MAN-S29 |
|---|---:|---:|
| `ProbCutMargin` | 100 | 103 |
| `ReverseFutilityMargin` | 100 | 68 |
| `LmrExtraScale` | 100 | 116 |
| `LateMoveBase` | 3 | 4 |
| `LateMoveDepthScale` | 2 | 3 |
| `LateMoveImprovingBonus` | 2 | 4 |
| `QuietFutilityUnit` | 100 | 100 |
| `SeePruningUnit` | 100 | 107 |
| `QsearchDeltaCushion` | 100 | 122 |
| `ReplyHistoryWeight` | 100 | 116 |
| `ContinuationHistoryWeight` | 100 | 118 |

The registered candidate used the compile-time `search-spsa-bake` build option.
After H1, the rounded vector becomes the sole ordinary default and production
fingerprint `799,610`; the temporary selector is removed. Frozen MAN-S19 values
remain available only to reconstruct archived diagnostic fingerprints and are
not a selectable production policy. No UCI option, runtime branch, mutable
state, allocation, cache layout or thread relation is added.

The authoritative gate is candidate-as-A `MAN-S29-spsa-bake` against baseline
`MAN-S19`, 1T `3+0.03`, Hash 64 MiB, paired UHO openings, concurrency 14 and
normalized SPRT `[1,5]`, alpha/beta 0.05, with a 16,000-game cap and harness
seed `651364430`. The designated Ryzen 9 5950X shall be otherwise idle. The
checked launcher owns placement, resume, anomaly records and binary/book/tool
hashes.

H1 promotes the complete vector as one bundle. H0 or exhaustion of the cap
restores the accepted defaults and closes SPSA without coordinate rescue,
restart or a narrower post-hoc test. A genuine infrastructure anomaly permits
only a recorded same-registration recovery.

## Evidence gate

`SCORE-026`'s fixed-vector contract, parameter ranges, search invariants,
selected-arm fingerprints, serialized Debug, ReleaseSafe and ReleaseFast
suites, formatting, policy checks, clean candidate/baseline builds and a
launcher dry-run passed. The candidate gains no legality, move-
generation, terminal, mate, draw/history, tablebase, score/bound/provenance,
TT/PV, cache, allocation or thread authority. Legal bestmove/PV, state
restoration and the existing full-depth verification rules remain unchanged.

The SPRT refutes the only strength hypothesis that matters: at the registered
clock, the fitted interaction is at least +1 nElo and can reach +5 nElo net of
its changed node and time behavior. A deterministic tree change alone neither
supports nor refutes that claim.

## Result

The registered candidate-as-A match accepted H1 after 4,596 scored games and
2,298 complete pairs in 41m38s: 1,272 wins, 1,069 losses and 2,255 draws,
2,399.5 points (`52.21%`), pentanomial `[104,524,876,653,141]`,
`+15.36 +/- 6.87` Elo (`+22.49 +/- 10.04` nElo), LOS `100.00%`, draw ratio
`38.12%`, PairsRatio `1.26` and LLR `2.95`. Independent PGN reconstruction by
complete round reproduces all totals. The PGN contains one later incomplete
round whose candidate win is correctly excluded; the scored games contain
2,401 adjudications and 2,195 normal endings, with no timeout, forfeit, illegal
move, crash, disconnect, option or placement anomaly.

Evidence SHA-256s: PGN
`0255F19898197A7B56807E9B3EFFFA968648E9283718FC5E13AED5E81A4BB918`,
log `71F63D45FEF4A90D398B6CCB33397C3ED2B17F749AA8E49D36B6985ACDFC93FD`
and bridge manifest
`85CC22E807A5AEE9D4FD815AAA315BEAFE51212AF101B7C2CCF596AFC5D874BF`.
The bound source revision is `76b7b0805989a54e3ec9b479eca1fca488f5e987`.

## Consequences

MAN-S29 is licensed only as the complete fitted vector; no coordinate-level
strength claim follows. No additional SPSA, coordinate ablation or speed-only
veto is authorized. Step 5.4.7 freezes this accepted head and performs the
separately owned cumulative Phase-5 comparison before closing the phase.
