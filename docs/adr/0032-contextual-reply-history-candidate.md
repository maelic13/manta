# ADR-0032: Contextual quiet reply-history candidate

## Status

Accepted as `MAN-S13` on 2026-08-14. Deterministic qualification passed and the
maintainer-owned registered SPRT accepted H1. The complete mechanism is
retained. ADR-0033 prepares one separate final synchronization candidate on
this accepted baseline before Step 5.1 closes.

## Context

Accepted MAN-S12 freezes ordinary cutoff, exact/fail-low attribution, move
context, LMR, shallow pruning and ProbCut. Step 5.1.4.5 permits at most one
materially richer history hypothesis and explicitly forbids retuning rejected
MAN-S06. MAN-S06 attached signed outcomes only to side/from/to and used their
sign to exempt a quiet from LMR; its registered gate accepted H0.

The pinned final pre-NNUE reference demonstrates a useful concept: history can
describe a relation between a preceding moved piece/destination and a current
piece/destination rather than treating a move as context-free. It also mixes
several history distances and consumes them in reductions. Manta adopts
neither that structure nor its formulas/constants. The bounded question here
is narrower: can an original one-ply relation improve Manta's quiet ordering
without changing reduction or pruning authority?

## Decision

- Add independently ablatable `Features.contextual_history`, default on for
  MAN-S13. Disabling it restores accepted MAN-S12 exactly.
- Derive a reply context only when the current node arrived through a real
  move. Read the preceding move's resulting piece from its destination in the
  current board: promotion therefore names the promoted piece, castling names
  the king and en passant names the moved pawn. Root and null arrivals have no
  context.
- Key a fixed signed table by previous piece type/destination and current piece
  type/destination. Exclude `.none`. Normalize both squares by flipping ranks
  when black is to move, so color-mirrored relations share an entry while move
  direction remains meaningful. The table occupies 288 KiB and remains
  worker-local.
- At a non-exclusion main-search node, remember only quiet moves that
  passed shallow pruning and were actually searched. If the node completes
  with an exact quiet winner, or a quiet move proves beta cutoff, reward that
  reply relation and penalize the searched quiet non-winners. Do not penalize a
  move that aliases the winner's piece/to key. Fail-low, root, null, exclusion,
  tactical, pruned and unsearched moves do not train the table.
- Use the existing bounded depth-squared gravity transformation for the new
  table. This reuses an arithmetic safety mechanism, not MAN-S06's context-free
  evidence or LMR consumer.
- Add the reply value to accepted main quiet history only inside the quiet
  ordering stage. TT, good/bad tactical SEE stages and killers retain their
  stage priority. Reply history has no score, bound, PV, TT, evaluation,
  pruning, LMR, terminal, draw or qsearch authority.

## Consequences

Legal move generation and make/unmake remain the authority for every special
move. Training happens after unmake, so cancellation and ordinary recursion do
not expose a child board to the table. Terminal/draw/TT/null/ProbCut returns
that bypass ordinary move completion cannot update it. Exclusion probes are
explicitly barred even when they search legal alternatives.

The hot path adds one random table lookup per contextual main-search quiet and
bounded updates only at exact/cutoff outcomes. It adds no allocation,
formatting, I/O, lock or shared atomic. Per-worker locality avoids contention;
the 288 KiB footprint is a declared Phase-6 SMP cost rather than an assumed
shared-history design. Candidate node reduction diagnoses ordering only and
cannot establish Elo.

## Verification

- Unit properties prove bounded reversible updates, context specificity,
  color-mirrored key equivalence, promoted-piece derivation, quiet-stage
  reordering and clearing. A compile-time budget keeps full ordering state
  below 320 KiB per worker.
- Search accounting admits only exact/cutoff updates, counts only searched
  quiet alternatives and proves fail-low updates remain zero. Existing legal
  PV, mate/material, draw/history, cancellation, TT/provenance, board-state and
  16 UCI transcript gates remain active.
- `manta-search-observation-v6` produces two byte-identical ReleaseSafe reports
  at SHA-256
  `2C45CB0A7970C14629E423B2579D28B096CD780B6FA8ACB3D331A637B022C57B`.
  Across 12 legal roots it records 220,828 contextual quiet lookups, 126,551
  nonzero consumers, 250 exact updates, 11,156 cutoff updates and 6,040
  searched-alternative penalties; fail-low updates are zero.
- Feature-off depth-six bench is exact MAN-S12 at `919,299`. MAN-S13 is
  `842,040`, 8.40% fewer nodes; this is a diagnostic tree-shape snapshot, not a
  speed or Elo claim.
- Debug, ReleaseSafe and ReleaseFast suites, including all 16 UCI transcripts,
  pass. Format, policy/lint and the portable build pass. The clean Zig-0.16
  native candidate is source
  `1755dc88190eb20762c9dce2de4d9d10ab64a271`, SHA-256
  `F707FA7817C09C2580457561A965843300F918FAD21228680FF0379741FE4E48`,
  bench `842,040`. The frozen accepted MAN-S12 baseline is source
  `7892717a7e032f5b113a88b4af79ba15857be221`, SHA-256
  `AF091EF481EA42EC559FEEC1FB019975C9E6DED05A33A10D695148B68352C86C`,
  bench `919,299`. Both manifests are clean, native, non-PGO and compiler-equal.
- The registered gate is candidate A versus accepted MAN-S12 B, 1T
  `3+0.03`, Hash 64 MiB, concurrency 14 on the Ryzen 9 5950X, explicit physical
  CPUs `0,2,...,26`, UHO book, strength-v1 adjudication, seed `514135`,
  normalized `[3,10]`, alpha/beta 0.05 and at most 12,000 games. Recent gates
  measured about 55 pairs/minute: expect roughly 10–30 minutes for a material
  boundary and about 110 minutes at the cap; stop manually at three hours.
  Budget storage is under 40 MiB. The temporary fastchess bridge has no
  reliable pair-atomic resume, so an interrupted run is restarted rather than
  combined.
- Only an H1 boundary with zero engine/runner anomaly promotes MAN-S13. H0
  rejects it; reaching the cap without H1 parks/reverts it. No fixed-node,
  alternate-TC or reference-convergence result substitutes for this verdict.
- The registered gate accepted H1 after 2,470 scored games/1,235 complete
  pairs in 22m27s: 697 wins, 567 losses and 1,206 draws, pentanomial
  `[47,270,515,312,91]`, `+27.15 +/- 13.70` nElo and LLR 2.95. The log has zero
  engine or runner anomaly. Independent PGN reconstruction matches the scored
  result exactly; one completed in-flight candidate loss is unpaired and
  correctly excluded.
- The archived manifest, PGN and log SHA-256 values are respectively
  `1FC7B2E368774B6538FDF6B312122348C22F6B8B8AF8ACB2B153E39892569153`,
  `BAD9D0051D39CB07D11131C6E354E586C4000C3D588CBA86BAFDFAC41231E311`
  and `534F9601BE10E3B5789CE40CFD5C53C80588A9D14CC6B7FDA92F2E76CB77475F`.

## Traceability

Supports `FUNC-004`, `FUNC-005`, `FUNC-006`, `SCORE-001`, `SCORE-002`,
`SCORE-010`, `SCORE-011`, `SCORE-012`, `SCORE-013`, `PERF-006`, `PERF-009`,
`PERF-010`, `QUAL-005`, `QUAL-013`, `QUAL-014`, `QUAL-015` and `QUAL-016`.
