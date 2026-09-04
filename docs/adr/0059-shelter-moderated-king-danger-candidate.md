# ADR-0059: Shelter-moderated king-danger candidate

## Status

Rejected on 2026-08-24 as `MAN-E21`. The default-off implementation and
deterministic qualification passed, but the registered `[1,5]` SPRT accepted
H0. Production remains switch-off.

## Context

Manta's king-safety evaluator already computes two relevant facts for each
king. `kingShelter` returns signed comfort from nearby own pawns, enemy pawn
storms and open or semi-open king files. Separately, attack maps accumulate
piece and pawn attackers, weak ring squares, possible checks, pinned blockers,
queen availability and flank pressure into `danger`; positive danger is then
squared into a middlegame penalty.

Shelter currently enters the final king score only as a linear bonus or
penalty. It does not change the nonlinear danger transformation. Consequently,
two otherwise equally attacked kings pay the same square-law penalty even when
one has intact cover and the other faces an advanced pawn storm or open file;
the shelter score merely offsets that penalty afterward. Chess says the pawn
structure changes how readily existing pressure becomes a forcing attack, so
the dependency belongs before the square.

This is a candidate, not an implementation-parity exercise. The pinned
reference establishes that the dependency is mature enough to test, but Manta
derives its own relation from its existing signed shelter score and danger
scale. MAN-E20's static refutation also warns against adding an independently
tuned context formula without native evidence.

## Decision

Add one compile-time `shelter_danger_coupling` candidate switch, default off.
For one king:

1. compute the existing signed `shelter` score unchanged and retain it in the
   ordinary tapered king-safety result;
2. preserve the existing rule that fewer than two attackers creates no danger
   penalty;
3. accumulate every existing raw-danger producer unchanged; and
4. with the candidate on, replace raw danger `D` by
   `effective_danger = max(0, D - shelter.middlegame)` immediately before the
   existing square-law conversion.

Positive shelter therefore reduces the nonlinear penalty; negative shelter
from missing cover, open files or pawn storms increases it. Zero shelter is
inert. The formula introduces no new coefficient, scale or cap and freezes all
accepted parameter values. Shelter remains a standing linear score when no
attack is active, while its second consumer exists only after the accepted
two-attacker threshold. Endgame shelter remains linear because the danger
penalty is middlegame-only.

The producer is the existing `kingShelter` result. The transformation consumes
only its signed middlegame lane and the already accumulated raw danger. The sole
new consumer is the existing squared middlegame king-danger penalty. Total HCE
then follows the unchanged taper, winnability, raw-evaluation, TT and search
paths. The candidate gains no legality, terminal, mate, draw, tablebase,
rule-fifty, score-bound/provenance, TT/PV, pruning/reduction, correction,
history, cache or thread authority.

Castling changes the king square and therefore shelter through the ordinary
position transition. En passant, captures and promotions may alter pawn cover,
storms or attacks only through the resulting legal board. Missing kings retain
the existing zero return. The calculation is stack-local, allocation-free and
adds one subtraction and non-negative clamp only on the already-active danger
path; no shared or worker-local state changes.

## Evidence gate

Implementation is authorized only behind the default-off switch. Deterministic
qualification must establish:

- exact switch-off MAN-E19/MAN-S19 fingerprint `724,563` and unchanged PV;
- pure-transform properties: zero-shelter identity, positive-shelter monotonic
  relief, negative-shelter monotonic amplification, non-negative effective
  danger and preserved two-attacker threshold;
- legal-position colour mirroring and paired positions where better cover
  reduces the penalty under the same raw-danger cohort;
- no change to terminal, mate, draw, tablebase, decisive-score, rule-fifty or
  ordinary score-band authority;
- safety-build overflow coverage and incremental/full-evaluation agreement;
- populated observation counts for positive relief, negative amplification,
  zero-shelter identity and effective-danger-to-zero transitions; and
- controlled ReleaseFast evaluator throughput as a cost diagnostic, with no
  invented Elo-equivalent veto.

Static reference residuals and fixed-node search may explain the candidate but
cannot promote it. The existing coefficients freeze, so there is no corpus
compilation or static fit. If deterministic qualification passes, prepare one
candidate-as-A 1T `3+0.03`, Hash-64, concurrency-14 paired-UHO normalized
`[1,5]` SPRT against exact MAN-E19/MAN-S19, alpha/beta 0.05, a 16,000-game cap
and a fresh harness-recorded seed. H1 promotes the coupling; H0 or the cap
rejects it without a formula or coefficient retry. Any infrastructure anomaly
voids the run.

If H1 promotes the nonlinear consumer, the production fitting schema must be
reviewed before any later fit: coefficients contributing to signed shelter can
no longer be treated as purely linear merely because their direct score remains
linear. That conditional schema work is not part of this candidate's initial
implementation or game gate.

## Qualification result

The compile-time implementation preserves every producer and coefficient and
adds only the registered subtraction/clamp before the candidate square-law
path. Candidate-only bounded trace records expose raw danger, signed shelter
and effective danger; the production disabled sink removes them. The build and
test roots compile in Debug, ReleaseSafe and ReleaseFast with the candidate on,
and the full Debug suite passes.

Transform properties, legal colour mirroring, 48-ply reused/fresh evaluator
state, ordinary-score and safety-build overflow checks pass. A four-position
legal observation cohort records two positive-relief transitions, one negative
amplification, one zero-shelter identity and one positive-danger-to-zero
transition. Its controlled storm-pawn pair holds raw danger equal while the
better shelter reduces effective danger. The two-attacker threshold remains
outside the transformation and is unchanged.

Switch-off reproduces the accepted depth-6 fingerprint `724,563`; the candidate
fingerprint is `763,658`. Both evaluator-benchmark arms retain checksum `-260`.
On the idle 5950X, the predeclared switch-off/candidate/candidate/switch-off
ReleaseFast order produced geometric means of 3,355,551 and 3,404,592 eval/s:
the candidate measured 101.461% of switch-off throughput, a 1.461% diagnostic
increase. This is code-layout-sensitive cost evidence, not a strength claim.
No corpus, fit or coefficient change occurred. Deterministic qualification
therefore opened exactly the registered maintainer-run SPRT.

The candidate-as-A 1T `3+0.03`, Hash-64, concurrency-14 paired-UHO run used
seed `675534226` and accepted H0 after 7,284 scored games/3,642 complete pairs
in 1h05m42s. MAN-E21 scored 1,838 wins, 1,973 losses and 3,473 draws, 3,574.5
points (49.07%), pentanomial `[228,929,1434,852,199]`, `-6.44 +/- 5.52` Elo,
`-9.31 +/- 7.98` nElo, LOS 1.11% and LLR `-2.97`. Independent PGN
reconstruction matches every scored total. One later completed game belongs to
an incomplete pair and is excluded. The scored terminations are 3,897
adjudications and 3,387 normal chess endings; the logs contain no timeout,
crash, illegal-move, disconnect, forfeit or affinity anomaly.

Evidence is under `zig-out/fastchess/MAN-E21-sprt-20260824_200408`. PGN
SHA-256 is `5DAB86FF82D1079232F7E5B7FB355170073089830B34CDD0DA637A4660C13760`,
fastchess-log SHA-256 is
`114494D690718FC17E8BCF63E3CDAADADE9AA480494BC8A27A3DD26866AE2C5B`,
and bridge-manifest SHA-256 is
`9724E4EE3ABECB33528BEC1F8C5B3096B40599D40DDA094D1CF84AE1EF02622B`.

## Consequences

MAN-E21 remains archived default-off without a formula or coefficient retry.
MAN-E20 is also refuted and off, so Step 5.4.3 closes with no promoted
formulation. Schema v3 remains the current production fitting interface. The
separate sheltered-maneuvering-space formulation remains unregistered.
Production remains MAN-E19 on MAN-S19.

## Traceability

- `REQUIREMENTS.md` `SCORE-025`; `PLAN.md` 5.4.3.
- `EXPERIMENTS.md` `MAN-E21`; `docs/HCE_COVERAGE.md`.
- ADR-0050, ADR-0055, ADR-0056 and ADR-0058.
