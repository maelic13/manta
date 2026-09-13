# ADR-0069: Exact tactical-only non-check qsearch generation candidate

## Status

Accepted for Step 6.5.7 as production `MAN-S34`. Deterministic and local
performance gates passed; the registered one-thread game gate accepted H1.

## Context

Production qsearch generates and ranks every legal move before skipping every
ordinary quiet. That preserves stalemate, but spends most of the frontier on
moves qsearch cannot consume. Manta already owns an exact, order-preserving
partition between tacticals (captures plus every promotion) and non-tactical
quiets through the accepted MAN-S30 generator/picker contracts.

## Decision

- In check, continue to generate, rank and search the complete legal evasion
  set.
- Outside check, generate only the exact tactical partition. A non-empty
  partition is itself a legal-move witness. If it is empty, generate the
  disjoint non-tactical-quiet partition into the same bounded move list solely
  to establish whether the node is stalemate, record its generated work, then
  reset the list before ordering.
- Preserve tactical generator order, TT ranking within that list, SEE/delta
  eligibility, checking exemptions, make/unmake, negamax bounds, PV and
  depth-zero TT storage. Quiet TT moves remain unsearched exactly as before.
- Keep the mechanism compile-time ablatable. Ordinary builds default on;
  disabling it reconstructs MAN-S30's full-qsearch-generation behavior.

## Consequences

Move generation remains the sole legality producer. The terminal consumer sees
a complete witness before stand pat; a tactical move proves non-stalemate even
if SEE or delta later rejects its recursive search. Checkmate, draw/history,
mate distance, promotions and en passant are unchanged. No score, bound,
provenance, pruning, depth, history, cache, allocation or thread authority is
added.

Across the twelve frozen observation cohorts, candidate and production agree
on every best move, score, bound, provenance, node count and main/qsearch split.
Generated moves fall from `6,974,800` to `3,023,797`, a `56.65%` reduction.
The depth-six fingerprint remains `775,451`; matched native ReleaseFast runs show
about `1.34x` NPS. These are qualification diagnostics, not playing evidence.

## Verification

The independent full legal list checks stalemate, quiet-only mobility, a legal
capture and checked quiet evasions against the candidate partition/witness.
Existing tactical/quiet partition, SEE, terminal/draw, legal-PV, restoration,
observer-disabled equivalence, ReleaseSafe and UCI process suites remain
mandatory. `MAN-S34` is candidate A in the unchanged trusted 1T `3+0.03`,
64-MiB, UHO normalized `[1,5]` gate with a 16,000-game cap.

The registered gate accepted H1 at the official 1,614-game decision snapshot:
W/L/D `505/320/789`, pentanomial `[23,150,321,245,68]`,
`+59.77 +/- 16.95` nElo (`+40.00 +/- 11.45` Elo), LLR `2.95`, LOS `100%`.
No completed time forfeit or engine, protocol or affinity anomaly occurred.
Two in-flight games completed after the boundary, leaving 1,616 games in the
final PGN/log without changing the prospective verdict.

## Traceability

Supports `FUNC-004` through `FUNC-006`, `SCORE-032`, `PERF-006`, `PERF-009`,
`PERF-010` and `QUAL-013` through `QUAL-017`.
