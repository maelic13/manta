# ADR-0050: Stockfish as primary reference, coverage parity as a Phase-5 goal, and the 5.3 re-sequence

## Status

Accepted 2026-08-17 by maintainer decision. Amends `AGENTS.md`, `PLAN.md` 1 and
5.3, and the reference roles set in `PLAN.md`. Supersedes the 5.3.9/5.3.10
sequence introduced by [ADR-0049](0049-separating-behaviour-neutral-cost-from-chess-terms.md),
whose gate and fit decisions otherwise stand.

## Context

Three facts arrived together.

A term-by-term audit against the pinned final pre-NNUE Stockfish snapshot
(`9587eeeb`, checked out locally for the audit) found roughly twenty-five
priced chess concepts that Manta does not price, or prices only partly. They
concentrate in passed pawns — where Manta scores only how far a passer has
advanced and nothing about whether it can move — in piece detail, in threats,
and in endgame knowledge, where Manta has no specialised recognisers at all.
The full table is [`docs/HCE_COVERAGE.md`](../HCE_COVERAGE.md).

Second, the last two evaluation gates failed. `MAN-E05` graded endgame
conversion and lost 16.32 Elo; `MAN-E07` added nonlinear material imbalance and
lost 7.00. Both are reference-family concepts. Both were implemented with
hand-reasoned coefficients.

Third, the maintainer decided that a non-fitted HCE is not an acceptable
Phase-5 output, and that the classical evaluator should reach reference-level
maturity before Phase 5 closes.

## Decision

### Stockfish becomes the primary reference

Basilisk moves to secondary cross-check. The reference is the pinned final
pre-NNUE classical snapshot, which is the strongest classical evaluator
available to compare against; modern Stockfish has no classical evaluator at
all, so no moving target exists.

### Coverage parity is a goal; implementation parity is not

This is the one goal that changed, and the boundary is exact.

**A goal:** the set of chess concepts the Phase-5 evaluator prices should reach
the reference's maturity. An evaluator blind to a quarter of the concepts its
reference prices is not a finished classical evaluator, and discovering that at
the freeze would be worse than discovering it now.

**Still forbidden:** copied code, copied constants, formula matching, trace
convergence, feature-name matching as evidence. Every adopted concept is
derived independently, designed against Manta's own producers and consumers,
written as original Zig, and given Manta's own values.

Coverage is a candidate list, never evidence. A row in the coverage table
licenses an investigation, not an implementation, and certainly not an
acceptance — `MAN-E05` and `MAN-E07` are the standing proof that a
reference-family concept can lose games in this engine.

### Structural completion is not gated by individual SPRTs

Steps 5.3.10 to 5.3.14 are gated on deterministic evidence: property and
counterexample tests against an independent oracle, colour and phase symmetry,
special-move and endgame cases, an independently ablatable switch, held-out
residual improvement through the 5.3.0 harness, and a stated throughput budget.
None receives its own strength gate on hand-set coefficients.

The justification is measured rather than theoretical. Two consecutive
hand-scaled terms lost games, and the reference's own values are the product of
a long automated fit — so adopting its concepts with reasoned constants
reproduces its structure without its calibration. Spending an hour of host time
per cluster to rediscover that is paying for a result already in evidence
twice. `AGENTS.md` has always said static loss may select but never promotes;
this applies that rule properly for the first time.

The block is calibrated at 5.3.16 and promoted by that step's single SPRT. Each
cluster stays independently ablatable, so a failing joint gate is attributed by
targeted post-fit ablation rather than by an exhaustive matrix. This is not a
return to `MAN-E06` bundling: that bundle mixed a *measured* speed gain with an
unmeasured chess term in one Elo number, whereas here every component is the
same kind of thing, calibrated together because they interact.

### The 5.3.7 retry is absorbed, not scheduled separately

Endgame recognisers and convertibility grading are one subsystem. `MAN-E05`
graded conversion while having no recogniser able to say whether an ending was
winnable, which is why a pawnless minor edge could be damped to an eighth.
Recognisers first, grading on top, is the structurally different model its
retry trigger demands. Retuning the archived factors alone remains forbidden.

### The rejected imbalance term gets exactly one post-fit ablation

`MAN-E07` enters the 5.3.16 fit as a free coefficient block and is decided by
one ablation of the fitted binary. This is a narrow, prospectively stated
exception, justified by the specific failure mode: the suspected cause was
double counting against `rook_open`, `rook_semi_open`, `knight_outpost` and
mobility, which is a claim about *joint* scale that only a joint fit can
settle. If the fitted evaluator is no better with the block than without, the
term is deleted rather than archived again. No other rejected mechanism enters
the fit.

This narrows ADR-0049, which held that a term showing negative signal untuned
is refuted outright. That rule was too crude for the double-counting case,
where a directionally correct relation can still be net harmful because the
evaluator already carries part of the same signal. The rule now reads: a term
is refuted when its *relations* are wrong, and is a fit candidate when its
relations duplicate signal already priced elsewhere. Hand-retuning a failed
gate stays forbidden in both cases.

## Consequences

Remaining Phase 5.3 is 5.3.9 audit (done), 5.3.10 to 5.3.14 structural
completion, 5.3.15 structure freeze, 5.3.16 parameter fit and promoting gate,
5.3.17 cumulative checkpoint and close. Completed steps keep their numbers,
because ADRs, ledger rows and commit messages cite them; only the remaining
plan was re-sequenced.

Phase 5 grows by roughly five implementation steps. That is the cost of
reaching a mature classical evaluator, and it is paid once. The alternative —
freezing a structure known to miss a quarter of its reference's concepts and
then fitting it — would produce a well-calibrated incomplete evaluator, which
is worse than an uncalibrated complete one because the fit would have to be
redone after every later addition.

Host cost falls rather than rises despite the extra steps: five clusters that
would each have taken an hour-long SPRT now share one promoting gate.

## Traceability

- `AGENTS.md` reference roles and coverage goal.
- `PLAN.md` 1 reference roles, 5.3.7 retry disposition, 5.3.9 to 5.3.17.
- `GUIDE.md` current checkpoint and Phase-5 checklist.
- [`docs/HCE_COVERAGE.md`](../HCE_COVERAGE.md); `config/eval-reference.json`.
- [ADR-0048](0048-imbalance-and-evaluation-cost.md),
  [ADR-0049](0049-separating-behaviour-neutral-cost-from-chess-terms.md).
