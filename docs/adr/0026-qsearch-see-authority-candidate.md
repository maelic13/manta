# ADR-0026: Quiescence SEE eligibility and evidence-authority candidate

## Status

Accepted for Step 5.1.3 through `MAN-S07` on 2026-08-12. The registered Ryzen
playing gate accepted H1; the complete mechanism is retained.

## Context

Accepted MAN-S04 quiescence searches every legal evasion while in check and,
otherwise, establishes a static stand-pat score before recursively searching
every capture and promotion. That is correct but spends branches on captures
whose evaluator-valued static exchange sequence loses material. It also tagged
the final result as `qsearch_move` whenever any tactical move existed, even
when no searched move beat stand pat.

Static evaluation, threshold SEE and searched child scores have different
authority. SEE is a fallible local exchange predicate, not an evaluation,
bound, terminal result or TT score producer. A candidate may use it to decide
which captures receive recursive search, but cannot publish SEE as score
evidence.

## Proposed decision

- Preserve every legal check evasion. Outside check, preserve all promotions
  and every non-losing capture under the evaluator's existing `SEE >= 0`
  predicate.
- A negative-SEE non-promotion capture is made before rejection so discovered
  checking status comes from the resulting legal position. Search it normally
  if it gives check; otherwise unmake it and omit its recursive child.
- Treat en passant as a capture under the board's existing pin-aware SEE and
  normal make/unmake contracts. Do not add a special search score or shortcut.
- Keep the static score as the best source until a searched continuation
  strictly improves it. A final result with no improving move stores no move
  and carries `stand_pat` provenance, even if losing tactical moves were
  searched. A tactical winner carries `qsearch_move` provenance.
- Retain qsearch TT depth zero and typed bound/provenance. Positive-depth main
  search cannot consume a depth-zero qsearch record as sufficiently deep.
- Do not add delta pruning: Manta has not established a safe evaluator-scale
  margin contract for it.
- Keep the policy compile-time ablatable. Disabling `qsearch_see` restores the
  exact accepted MAN-S04 node fingerprint.

## Consequences

- Producers are full HCE static evaluation, evaluator-valued board SEE and the
  resulting position's checker set after make. Transformations are the guarded
  capture eligibility decision and ordinary negation/bound propagation.
  Consumers are qsearch recursion, PV construction and depth-zero TT records.
- Terminal and history-draw tests still precede expansion. Checkmate,
  stalemate, repetition/rule draws, mate distance, castling legality and all
  check evasions are unchanged. Promotions and negative-SEE checking captures
  cannot be pruned by this mechanism.
- Every tentative move is unmade on rejection, completion and abort. Focused
  tests independently replay legal PVs and recompute position consistency.
- Ordinary nodes add one existing SEE query for eligible captures. A rejected
  capture still pays make/unmake to classify check, then saves its recursive
  branch, TT traffic and descendant work. There is no allocation, formatting,
  I/O, lock or shared atomic; one-thread determinism remains the baseline.
- A smaller tree admitted but did not promote this candidate. The registered
  final-binary SPRT accepted H1, so the complete bundle is retained without
  claiming that every guard helped independently.

## Verification

- Debug, ReleaseSafe and ReleaseFast suites cover feature-on/off search, legal
  best move/PV, state restoration, nonzero rejection population and preserved
  negative-SEE checking captures. The observer verifies candidate accounting
  and has no policy return channel.
- The candidate fingerprint is `2,288,471` nodes versus MAN-S04 `2,910,189`,
  a 21.36% reduction in this diagnostic workload. Feature-off is exactly
  `2,910,189`; the rejected MAN-S06 archive remains exactly `2,885,300` with
  this candidate disabled.
- Two ReleaseSafe `manta-search-observation-v1` reports are byte-identical at
  SHA-256
  `2A86F0A614184716982DAA85F5FA65018369816CF2603701BC85993D78F15287`.
  Across 12 roots they record 8,983 negative-SEE candidates, 7,679 prunes and
  1,304 checking exemptions. Stand-pat nodes/cutoffs/final results are
  36,702/25,357/2,935.
- The sole promotion gate is the unchanged candidate-as-A, one-thread,
  `3+0.03`, Hash 64 MiB, concurrency-14 normalized `[3,10]` SPRT on the
  designated Ryzen 9 5950X. It accepted H1 after 1,202 games/601 pairs in
  10m43s: 382 wins, 265 losses, 555 draws, pentanomial
  `[21,117,240,170,53]`, `+49.54 +/- 19.64` nElo and LLR 2.95. The maintainer
  returned the completed summary; the run archive and binary hashes were not
  available in this worktree at closeout and remain release-manifest inputs.

## Traceability

Supports `FUNC-004`, `FUNC-005`, `FUNC-006`, `SCORE-001`, `SCORE-004`,
`PERF-006`, `PERF-009`, `PERF-010`, `QUAL-005`, `QUAL-013`, `QUAL-014`,
`QUAL-015` and `QUAL-016`.
