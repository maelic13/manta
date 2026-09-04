# ADR-0043: Search-only cumulative freeze candidate

## Status

Accepted as MAN-S22 on 2026-08-15. The registered cumulative SPRT accepted H1,
so exact MAN-S19 is the frozen Step-5.1.5 one-thread search head.

## Context

MAN-S15 dynamic LMR, MAN-S17 continuation evidence and MAN-S19 static-eval/TT/
qsearch synchronization each passed their prospective game gate after MAN-S13.
MAN-S16 capture history, MAN-S18 LMR synchronization and MAN-S20 main
selectivity were rejected; MAN-S21 depth authority reached its cap without H1.
The individual verdicts establish their registered candidate comparisons, but
do not yet freeze one explicit production switch configuration or show that the
accepted search head retains cumulative value against the immutable MAN-S13
entry baseline.

## Decision

- Define default `Features{}` as the production MAN-S19 policy. A focused test
  asserts every accepted umbrella/component on and every rejected, parked or
  later-phase umbrella off. Diagnostic component switches below a disabled
  umbrella remain available but have no production authority.
- Make no chess/search behavior change. The producers remain legal position,
  history, raw HCE, authenticated TT and searched-result evidence; their only
  consumers remain the accepted ordering, reduction, pruning, extension and
  qsearch paths. Legality, terminal, draw/history, castling, en-passant,
  promotion, mate-score, bound and provenance handling remain exact MAN-S19.
- Compare clean native MAN-S22 directly with the frozen clean MAN-S13 binary in
  one candidate-as-A 1T `3+0.03`, Hash-64, concurrency-14, normalized `[3,10]`
  SPRT with seed `515229` and a 12,000-game cap.
- H1 freezes MAN-S19 as the Step-5.1.5 one-thread search head. H0 or a cap
  without H1 pauses progression for an evidence audit; it does not
  retrospectively revoke independently accepted candidates without a new
  prospective decision.

## Consequences

The ledger adds no hot-path branch, allocation, cache traffic, I/O, lock,
atomic or thread interaction. It protects configuration identity rather than
an incidental score, tuning constant or node count. Existing legal-PV,
make/unmake, mate/draw, cancellation, UCI and feature-off tests remain the
mechanism oracles; the accepted production depth-six fingerprint is `744,899`
and the repeated `manta-search-observation-v20` SHA-256 is
`0C488A2413038DC1EFF1DFA88152C28BBCF0C84C34F5EA6E00E42018B7098144`.
Only the registered games can establish the cumulative playing claim.

## Outcome

The registered candidate-as-A seed-`515229` gate accepted H1 at its paired
boundary after 7,564 scored games/3,782 pairs in 1h08m39s: 1,937-1,745-3,882,
pentanomial `[164, 869, 1567, 975, 207]`, `+13.32 +/- 7.83` nElo
(`+8.82 +/- 5.19` Elo), LLR 2.98 against the `(-2.94, 2.94)` bounds and LOS
99.96%. The stop was the H1 boundary, not the 12,000-game cap, so the result
resolves rather than parks. Independent PGN reconstruction reproduces the
totals exactly, every one of the 7,564 games carries a legal chess or
adjudication termination, and the log contains zero timeout, crash, illegal
move, disconnect, forfeit or affinity anomaly. Manifest binaries matched the
registered candidate `52584FE9...` and MAN-S13 baseline `F707FA78...`, with
the pinned book and fastchess hashes unchanged.

The accepted head therefore retains roughly `+9` Elo cumulatively over the
immutable MAN-S13 entry baseline at this time control. That is a modest
aggregate for six intervening candidate cycles, and it is the honest measure
of the 5.1.5 sequence: three accepted mechanisms net of three rejections and
one parked family. It licenses freezing this configuration, not a claim that
any individual switch is independently optimal.

## Traceability

Supports `FUNC-004` through `FUNC-006`, `SCORE-010`, `SCORE-013`, `SCORE-015`,
`SCORE-016`, `SCORE-018`, `SCORE-019`, `PERF-006`, `PERF-009`, `PERF-010`,
`QUAL-013` through `QUAL-017`, and Step 5.1.5.9 in `PLAN.md`.
