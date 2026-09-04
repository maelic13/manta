# ADR-0053: Bounded endgame-only winnability and initiative

## Status

Accepted for Step 5.3.14 on 2026-08-21. Playing promotion remains owned by the
joint Step-5.3.16 fit and gate.

## Context

The completed evaluator priced individual assets and liabilities but did not
price whether an endgame offered several independent conversion routes. The
coverage audit named five facts that distinguish a technically narrow edge
from a complex one: passed-pawn count, king outflanking, pawns on both flanks,
king infiltration and almost-unwinnable material.

This term is deliberately last in the structural sequence because it consumes
facts produced by earlier clusters and modifies their combined endgame score.
It must remain ordinary evidence: terminal, rule-draw and Syzygy authority is
unchanged, and Step 5.3.13's exact recognizers are more specific.

## Decision

- Derive the passed-pawn count from the existing cached pawn sets rather than
  reclassifying pawns.
- Define outflanking as the amount by which the kings' file separation exceeds
  their rank separation. Direct opposition contributes zero.
- Treat pawns on both `a`-through-`d` and `e`-through-`h` as two-flank play,
  count each king on the opposing half as infiltration, and flag a pawnless,
  queenless low-force army when it leads the endgame score.
- Combine those counts using reasoned starting coefficients into one signed
  endgame-only adjustment. Cap a positive bonus at 80 cp and cap a negative
  adjustment at the score's magnitude, so it cannot reverse the leader.
- Apply the term after all tapered components and before interpolation. Exact
  value recognizers may replace the interpolated result and exact scale
  recognizers may scale it. Tempo, insufficient-material and rule-50 handling
  remain later consumers.
- Keep `winnability` independently ablatable. Step 5.3.15 enumerates its
  coefficients but excludes them from the linear fit because both caps make
  the response piecewise; the structure still rides the joint playing gate.

## Consequences

The producers are authoritative piece placement, king squares, the cached
passed-pawn sets and the combined endgame score. Consumers are phase
interpolation, exact endgame recognition, the final static score and MAN-S19's
raw-evaluation cache. There is no new allocation, I/O, lock, shared state or
thread interaction.

Feature and counterexample properties protect all five facts. The signed term
preserves colour/rank symmetry and cannot cross zero; full evaluation remains
ordinary and switch-off restores Step 5.3.13. Aggregate absolute residual
improves on the whole frozen Step-5.3.0 reference cohort.

Benchmark v2 reports `3,581,285` eval/s with 1.97% MAD, `-33.8%` from the
Step-5.3.9 baseline and inside the structural block's 40-percent allowance.
The checksum changes from `-85` to `-82`; production's depth-six fingerprint
changes from `736,492` to `697,962`, with all eighteen trees re-recorded.

## Traceability

- `PLAN.md` 5.3.14; `GUIDE.md`; `docs/HCE_COVERAGE.md`.
- `src/eval/winnability.zig`, `src/eval/hce.zig`,
  `src/eval/hce_params.zig`, `tests/eval_invariants.zig`.
- `SCORE-001`, `SCORE-005`, `PERF-002`, `PERF-006`, `PERF-009`, `QUAL-015`.
