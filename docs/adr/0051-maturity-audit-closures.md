# ADR-0051: Endgame recogniser authority, the fitting substrate, and the fit gate's failure branch

## Status

Accepted 2026-08-18. Amends `PLAN.md` 5.3.12, 5.3.13, 5.3.15 and 5.3.16, and
narrows [ADR-0050](0050-primary-reference-switch-and-phase-5-3-resequence.md)'s
gate policy by giving it a defined failure branch. No step numbers change.

## Context

An external maturity audit reviewed the re-sequenced Phase 5 and found three
gaps. All three were verified against the repository before being accepted; a
fourth suggestion was checked and placed differently.

1. **Pawnless flank was scheduled nowhere.** The coverage map recorded it as
   missing and no step owned it, so Phase 5 as written did not close its own
   audited coverage map.
2. **Endgame completion was underspecified.** Step 5.3.13 named eight
   recognisers and then said "and the rest", which is not a criterion anyone
   can check a claim of maturity against.
3. **The fit had no substrate and no defined failure branch.** The evaluator
   trace reports aggregated cluster scores, which cannot drive a coefficient
   fit, and 5.3.16 did not say which evaluator becomes the Phase-5 head if its
   gate returns H0.

## Decision

### The pawnless flank is a king-safety term, and belongs to 5.3.12

The audit proposed adding it to 5.3.10 with the pawn work. The reference
charges it inside its king evaluation, not its pawn evaluation, and the concept
is meaningless without the king flank that 5.3.12's flank-attack term
introduces. It is therefore owned by 5.3.12.

The process lesson is the larger one: a coverage map is only useful if every
row is either scheduled or explicitly rejected. That reconciliation is now the
responsibility of the step that reads the table, rather than of whoever
happens to remember.

### Endgame recognisers bind to an exact list, split by authority

Step 5.3.13 binds to the seventeen recognisers named in the coverage map, in
two classes that are implemented differently because they carry different
authority. Ten return a value: `KXK`, `KBNK`, `KNNK`, `KNNKP`, `KPK`, `KQKP`,
`KQKR`, `KRKB`, `KRKN`, `KRKP`. Seven return a scale factor: `KBPKB`, `KBPKN`,
`KBPPKB`, `KPKP`, `KRPKB`, `KRPKR`, `KRPPKRP`. The reference splits them the
same way, which is evidence the distinction is real rather than convenient.

**Manta does not follow the reference across the authority boundary.** The
reference's value recognisers return scores built on a known-win constant
clamped just below its tablebase band, so its static evaluation manufactures
near-terminal authority. `SCORE-001` forbids that here, and `src/score.zig`
reserves everything above `ordinary_max_raw` for mate and tablebase evidence.
Every Manta recogniser returns an ordinary-band score or a scale factor: a won
ending is a large ordinary advantage, and search finds the mate. The evaluator
only says the ending is winnable.

Each recogniser carries counterexample tests for its drawn cases as well as its
won ones, on both colours, including the boundary positions where the
classification flips. A recogniser that misfires is worse than its absence,
because it speaks with confidence where the general evaluator would have
judged cautiously.

### The fitting substrate is built at the structure freeze

A coefficient list is only enumerable once the structure stops moving, so
5.3.15 owns the substrate: a versioned parameter schema, per-coefficient
feature and count extraction, round-trip generation from a fitted vector back
to committed source, and confirmation that no binary switch is in the free set.

The extraction is checked by exact reproduction — features dotted with the
current parameter vector must equal the production score on the conformance
corpus and on randomised legal positions. A fitting representation that
disagrees with the evaluator optimises something the engine does not play, and
that disagreement would be invisible in the loss curve.

### The fit gate's failure branch is registered before the run

ADR-0050 deliberately left clusters 5.3.10 to 5.3.14 without individual gates.
That buys one promoting run instead of five, and it creates a hole: an H0 at
5.3.16 cannot distinguish a fit that spoiled a good structure from a structure
that was never worth having. Choosing the disposition after seeing the result
would be choosing the answer, so it is fixed now.

H1 promotes the fitted structural head. H0 or the cap triggers exactly one
attribution run — the unfitted structural head against the same baseline, on
identical conditions, registered as part of this gate. If that passes, Phase
5.3 closes on the unfitted structural head and the fit is parked as a failed
calibration. If it also fails, Phase 5.3 closes on the last accepted head, the
Step-5.3.9 evaluator, and the structural work is archived behind its cluster
switches as refutation history in the same way `MAN-E05` and `MAN-E07` are. No
third run follows either branch.

## Consequences

Phase 5.3 now closes its own coverage map or records an explicit rejection for
every row, and its terminal state is defined for all three outcomes of the fit
gate rather than only the successful one.

The endgame authority constraint is the most likely place for a subtle defect
in the remaining work, because the natural implementation — the one the
reference uses — is the forbidden one. It is called out here so that a reviewer
checks the score band rather than the chess.

## Traceability

- `PLAN.md` 5.3.12, 5.3.13, 5.3.15, 5.3.16; `GUIDE.md` Phase-5 checklist.
- [`docs/HCE_COVERAGE.md`](../HCE_COVERAGE.md); `src/score.zig` band contract.
- `REQUIREMENTS.md` `SCORE-001`.
- [ADR-0050](0050-primary-reference-switch-and-phase-5-3-resequence.md).
