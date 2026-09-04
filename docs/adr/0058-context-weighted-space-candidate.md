# ADR-0058: Context-weighted space candidate

## Status

Prospectively registered on 2026-08-24 as `MAN-E20`; statically refuted on the
same date. The candidate code and schema-v3 migration qualified
deterministically, but the candidate-only fit selected a negative space
coefficient and missed the registered validation-improvement floor. No
candidate vector, binary or game gate exists. Schema v3 remains as
behavior-neutral cleanup and the candidate switch remains off.

## Context

Manta already prices safe central space, with a second count for squares its
pawns support. One positive `space_bonus` multiplies that count only above a
binary material floor, after which normal middlegame interpolation supplies the
only further context. The constrained Phase-5.3 fit pinned `space_bonus` at its
positive semantic bound while the unconstrained fit wanted it negative. A flat
coefficient is therefore averaging positions where space has different value.

Space is useful while pieces remain to exploit maneuvering room, and locked
central pawns make that room harder to create with a pawn break. This motivates
an original Manta relation using the existing material phase and locked central
pawn pairs. It is not a transcription of the reference's squared weight.

## Decision

`MAN-E20` changes only the magnitude of the existing space term. For each side:

- `raw_space = popCount(safe_space) + popCount(pawn_supported_safe_space)`;
- `central_locks` is the global count of white pawns immediately behind black
  pawns on files c through f, capped at four;
- `context = phase * (4 + central_locks)`, where phase is already clamped to
  `0...24`; and
- `weighted_space = floor(raw_space * context / 96)` is computed before the
  white-minus-black difference.

The maximum multiplier is two, it is one at full phase with no central lock,
and it falls monotonically to zero with material phase. Per-side division before
subtraction preserves colour symmetry. The existing central/safe/supported
square definitions remain unchanged; replacing the supported lane and coupling
shelter into king danger are separate later hypotheses.

One compile-time `contextual_space` switch selects the candidate. Switch-off is
exact MAN-E19 evaluator behavior on the accepted MAN-S19 search head. The sole
consumer is the middlegame HCE space score and its sparse `space_bonus` feature.
It gains no legality, terminal, draw, tablebase, history, TT, bound, PV, pruning,
reduction, correction, cache or thread authority. It allocates nothing and adds
only bounded bitboard, popcount and integer arithmetic to evaluation.

The same implementation step owns schema v3. It deletes the rejected MAN-E18
mechanism and its nine coefficients, the two unreachable `knight_outpost`
coefficients, and the superseded `space_material_floor` row. The legacy
switch-off arm retains its frozen value 12 as an internal baseline constant.
Schema v3 therefore contains 1,229 coefficients in 125 groups. These deletions
must first reproduce production fingerprint `724,563`; they carry no strength
claim and are not part of the candidate's causal mechanism.

## Prospective refutation gates

The existing labelled train and validation CSVs may be recompiled under schema
v3; no self-play regeneration is authorized. The old frozen-test split has
already been opened and shall not be reused as new selection or promotion
evidence. Validation is a pre-game filter only.

The migrated switch-off arm must pass schema/source round-trip, exact sparse
component reconstruction, legal-position colour mirroring and exact production
fingerprint. Candidate properties must show zero space at phase zero, monotonic
non-decrease with phase and added central locks for unchanged raw space, the
two-times bound, ordinary-band safety and incremental/full-evaluation agreement.
ReleaseFast evaluator throughput is recorded under the existing controlled
benchmark so the final time-controlled strength verdict can be interpreted.

Only `space_bonus` is fitted for this candidate; every other accepted
coefficient stays frozen. The unconstrained float optimum must be at least
`0.5`, so integer rounding remains a positive bonus without semantic clipping.
The rounded candidate must improve aggregate validation loss by at least
`0.000200` against the migrated accepted-vector baseline, and no material-phase
validation loss may regress by more than 0.1 percent. Failure of any condition
refutes `MAN-E20` before binaries or games. Static loss can only refute.

The `0.000200` floor is larger than the `0.000151` best validation-selected
alternative from the closed post-fit sweep and about one tenth of the original
accepted validation gain. It therefore refuses another optimizer-scale wiggle;
it is not presented as a universal loss-to-Elo conversion.

Passing the filter opens one candidate-as-A 1T `3+0.03`, Hash-64,
concurrency-14 paired-UHO normalized `[1,5]` SPRT against the accepted fitted
MAN-E19 evaluator on MAN-S19 search, alpha/beta 0.05, a 16,000-game cap and a
fresh harness-recorded seed fixed before launch. H1 promotes the formulation
and its one fitted coefficient together. H0/cap leaves the switch off and
closes it without a formula or coefficient retry. Any anomaly voids the run.

## Performance verdict

The idle-host preflight reported 2.7%, 4.0% and 2.8% total CPU. Benchmark
preflight passed for both arms with checksum `-260`, so the planned checksum
plumbing was unnecessary. Two order-balanced ReleaseFast pairs measured
switch-off medians of 3,340,415 and 3,349,299 eval/s and candidate medians of
3,281,808 and 3,161,950 eval/s. The geometric means fixed before measurement
are 3,344,854 and 3,221,322 eval/s respectively: MAN-E20 retains 96.307%, a
3.693% regression.

The second candidate run had 1.96% MAD, but it is retained rather than rerun
after the aggregate result was known.

**Maintainer amendment, 2026-08-24:** the original 2% hard veto had no
derivation from Elo, integrated search NPS or an operational feasibility
limit. MAN-E20 is a chess-strength candidate, so better decisions may offset
its cost in time-controlled play. The threshold is withdrawn and the measured
cost remains visible. This transparent post-measurement governance correction
did not erase or repeat evidence: candidate-only fitting and validation still
had to decide whether the conditional SPRT branch could open. The result below
closed that branch.

## Fit verdict

The existing train and validation CSVs compiled under schema v3 with
3,000,000/166,667 samples, 214,622,496/11,911,358 sparse events and zero
rejected rows. The old frozen test was neither compiled nor opened. At fixed
`K = 1.62679234682616`, `space_bonus` had 1,662,778 training and 92,387
validation events. Training selected an unconstrained optimum of
`-3.403923499`, below the registered `0.5` positive-meaning gate. Rounding to
`-3` changed validation loss from `0.103648340983299` to
`0.103634579079070`, an improvement of only `0.000013761904229` against the
`0.000200` floor. The report SHA-256 is
`AF1EC32006AC19559A6AB48AC4DB06A4D286376FF9957FC073CA73A8CF02ABA1`.

Both independent static gates therefore refute MAN-E20. No candidate vector
was emitted, and the conditional binary/SPRT branch never opens. The result
does not say that space is intrinsically harmful; it says this phase-and-lock
transformation does not support the intended positive space meaning in Manta's
frozen linear model strongly enough to justify games.

## Consequences

Schema v3 remains as behavior-neutral cleanup and production remains the
switch-off MAN-E19 evaluator. MAN-E20 is closed without a coefficient retry.
This decision does not license the shelter/king-danger or sheltered-depth space
formulations, SPSA, new data generation, or a correction/selectivity retry.

## Traceability

- `REQUIREMENTS.md` `SCORE-024`; `PLAN.md` 5.4.3.
- `EXPERIMENTS.md` `MAN-E20`; `docs/HCE_COVERAGE.md`.
- ADR-0050, ADR-0054 and ADR-0056.
