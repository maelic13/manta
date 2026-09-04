# ADR-0036: Monotone dynamic base-LMR candidate

## Status

Accepted as MAN-S15 on 2026-08-14. The registered maintainer-owned `[3,10]`
SPRT accepted H1 after 5,902 scored games, so Step 5.1.5.2 is complete and the
dynamic surface is production.

## Context

Accepted MAN-S04 reduces every eligible late quiet by exactly one ply. That
policy preserves tactical and score authority well, but treats the fourth move
at depth four like a much later move in a substantially deeper tree. The
5.1.5 convergence plan gives dynamic base magnitude an independent gate before
node expectation and history are allowed to modify reductions, so a later
synchronization bundle can start from an attributable base.

A foreign logarithmic expression or tuned constant surface would import
assumptions about another engine's move order, evaluation and depth scale.
Manta instead needs an integer mechanism derived from its own nominal-depth
and searched-legal-move vocabulary. Reduced evidence must remain speculative:
a smaller tree or reference-like trace cannot replace full-depth authority or
playing evidence.

## Decision

- Keep every accepted eligibility rule: non-root fourth-or-later searched
  legal move, nominal depth at least four, quiet non-promotion/non-capture,
  not moving from check, not giving check and not the singular move.
- Compute a base reduction from nominal depth and searched legal-move ordinal
  only. Depth advances in three-ply bands; move lateness advances when the
  already-searched legal prefix doubles. One extra reduction ply requires both
  bands to advance, preventing either a deep early move or shallow very-late
  move from authorizing an aggressive reduction alone.
- Clamp the reduction so at least one child main-search ply remains. Use only
  integer operations in the allocation-free, statically dispatched node path.
- Preserve the existing reduced zero-window probe, explicit reduced
  provenance, reduction-matched reusable TT authority and mandatory nominal-depth
  alpha-rise verification. Only that full-depth result may affect PV, cutoff,
  exact score or outcome history.
- Give node expectation, TT/PV confidence, improving trend and history no
  magnitude authority in this candidate. Those coupled consumers remain owned
  by Step 5.1.5.5.
- Add `Features.dynamic_lmr`. Disabling it keeps LMR eligibility intact but
  restores the accepted fixed one-ply MAN-S13 behavior exactly.

## Evidence and registered gate

Independent properties cover monotonicity in both inputs, positive bounded
reductions, retained child horizon and exact fixed-one-ply switch-off. Existing
legal-PV, restored-state, tactical/check/singular eligibility, reduced-depth
TT authority, mate/draw/cancellation and UCI gates remain mandatory.

The optimized candidate fingerprint is `750,869`; switch-off is exact MAN-S13
`842,040`. Two `manta-search-observation-v10` reports match at SHA-256
`FFE1C3D2E33C9004F9DB3DB44C539C416B4C3DA7D64127E1B3D6B0701EC7BA1B`.
Across 124,188 nodes the candidate performs 3,520 LMR probes totaling 3,928
reduction plies: 403 are multi-ply, the maximum is three, 62 rise above alpha
and receive full-depth re-search, and 3,458 remain reduced fail-lows.

The prospective promotion gate uses the Ryzen 9 5950X host, candidate as A,
one search thread per engine, `3+0.03`, Hash 64 MiB, concurrency 14, the pinned
opening/adjudication/affinity harness, seed `515152`, normalized SPRT
`[3,10]`, and a 12,000-game cap. Historical pair rate implies roughly 110
minutes at the cap; ordinary H0/H1 resolution is expected materially earlier.
The maintainer-owned run accepted H1 after 5,902 scored games/2,951 pairs in
53m39s: 1,560 wins, 1,387 losses, 2,955 draws, pentanomial
`[132,678,1203,761,177]`, `+15.16 +/- 8.86` nElo and LLR 2.96. The log records
no anomaly. Three completed in-flight PGN games were excluded from the paired
statistic. The complete surface is accepted; no node count or subcomponent is
promoted alone.

## Consequences

Move generation/order, legal and special-move handling, terminal/draw policy,
static evaluation, TT score types and history producers are unchanged. The
candidate can reduce allocation, branch and cache pressure by searching
low-priority quiets at a horizon proportional to both depth and lateness, at
the risk of more tactical false positives or missed refutations. Mandatory
full-depth re-search bounds the first risk; only games can decide the second.

Later Step 5.1.5.5 may modify an accepted base using synchronized context. It
must retain separate switches and receives its own dependency-complete gate;
this ADR does not license such modifiers.

## Traceability

Supports `FUNC-004` through `FUNC-006`, `SCORE-001`, `SCORE-010`, `SCORE-016`,
`PERF-006`, `PERF-009`, `PERF-010`, `QUAL-013` through `QUAL-017`, and Step
5.1.5.2 in `PLAN.md`.
