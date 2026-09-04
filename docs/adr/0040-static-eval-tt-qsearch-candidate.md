# ADR-0040: Static-evaluation, TT and quiescence candidate

## Status

Accepted as MAN-S19 on 2026-08-15. The registered maintainer-owned cluster
SPRT accepted H1.

## Context

MAN-S17 keeps one raw HCE value per searched ply for improving and shallow
selectivity, while TT entries store only searched score/bound evidence.
Quiescence evaluates the same position again and prunes only negative-SEE
nonchecking captures. These boundaries are correct but leave two related
opportunities: an authenticated same-position TT hit can avoid repeated HCE,
and a compatible searched bound can improve the estimate used by pruning
without changing the raw evaluator fact. Quiescence can also omit a
nonnegative exchange that still cannot bridge alpha by a conservative margin.

The rejected MAN-S16 capture history adds no proven information to this
boundary and is not revived. Stockfish's classical design supplies the
producer/consumer questions, not Manta's representation, constants or policy.

## Decision

- Use nine previously unused bits in the existing atomic TT payload to cache
  exact raw HCE in `[-255,255]`; zero means absent and outliers are not clipped.
  Preserve the 16-byte entry, four-way 64-byte cluster, generation width and
  every old payload bit when the producer switch is off.
- Authenticate cached evaluation with the same full position key and repeated
  guard reads as the searched record. A same-key replacement without a fresh
  evaluation preserves an older cached raw value.
- Keep raw HCE, pruning evaluation and TT searched value distinct. Improving
  uses raw HCE only. A searched ordinary exact value may replace pruning
  evaluation; a lower bound may only raise it and an upper bound may only lower
  it. Terminal, stand-pat, fallback, null, speculative, exclusion and tablebase
  provenance cannot refine it.
- In quiescence, name the actual baseline producer: raw HCE is `stand_pat`,
  while a refined exact/bound result remains `tt_exact`/`tt_bound`. A searched
  move remains `qsearch_move`.
- Add delta eligibility only for non-PV, non-checking, non-promotion captures
  with nonnegative SEE. When SEE cannot bridge alpha beyond one pawn from the
  pruning evaluation, make the move and prune only if it does not give check.
  Evasions, promotions, decisive bands, losing-capture SEE and rule draws keep
  their existing authority.
- Keep one umbrella plus TT raw-cache, TT refinement and qsearch-delta
  compile-time switches. The umbrella-off fingerprint must be exact MAN-S17.

## Consequences

The ordinary node path remains allocation-free and lock-free. TT footprint and
cache-line layout do not change; exact static caching is deliberately limited
to the common near-balanced band. Qsearch may search fewer captures, but node
reduction and reference resemblance are diagnostic only. The existing
TT/SEE/good-bad tactical ordering remains production; MAN-S16 is reconsidered
at 5.1.5.6R only if an accepted MAN-S19 verdict exposes a new populated,
non-redundant contextual capture relation.

Umbrella-off is exact MAN-S17 `755,581`; MAN-S19 is `744,899`. Debug and
ReleaseSafe gates, UCI transcripts, legal PV/state, mate/draw and focused
packing/bound/special-move tests pass. Two normalized
`manta-search-observation-v16` reports match at SHA-256
`D4186FCB7675D5213716F648B5A8143825BE7849A475BCFA38DD946540965118`.
Across 192,340 nodes they record 20,538 raw-eval TT hits, 4,156 directional
refinements and 5,403 delta candidates, of which 5,042 prune and 361 remain
because the move gives check.

One candidate-as-A 1T `3+0.03`, Hash-64, concurrency-14, normalized `[1,5]`,
20,000-game-cap SPRT accepted H1 after 8,922 scored games/4,461 pairs in
1h20m58s: 2,246 wins, 2,026 losses, 4,650 draws, pentanomial
`[184,1034,1861,1142,240]`, `+13.02 +/- 7.21` nElo and LLR 2.96. The log has
zero anomaly; two completed in-flight PGN draws were correctly excluded. The
result promotes the complete cluster, not its individual components. MAN-S19
creates no new contextual capture relation independent of SEE and MAN-S17, so
5.1.5.6R closes skipped and MAN-S16 remains off.

## Traceability

Supports `FUNC-004` through `FUNC-006`, `SCORE-001`, `SCORE-004`, `SCORE-010`,
`SCORE-012`, `SCORE-015`, `SCORE-020`, `PERF-006`, `PERF-009`, `PERF-010`,
`QUAL-013` through `QUAL-017`, and Step 5.1.5.6 in `PLAN.md`.
