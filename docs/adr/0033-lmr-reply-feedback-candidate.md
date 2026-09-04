# ADR-0033: Full-depth LMR false-positive reply feedback

## Status

Rejected as `MAN-S14` on 2026-08-14. Deterministic qualification passed, but
the registered run stopped on the H0 side at LLR `-2.55` before the formal
`-2.94` boundary and the maintainer directed rejection. The feature remains
independently ablatable but defaults off, restoring accepted MAN-S13 exactly.
Step 5.1.4 is closed; ADR-0034 owns the broader search-convergence work.

## Context

Accepted MAN-S13 freezes contextual reply indexing, bounded updates and quiet-
ordering consumption. Accepted MAN-S04 LMR reduces eligible late quiets by one
ply and requires a full-depth zero-window re-search whenever the reduced probe
rises above alpha. MAN-S13 learns from exact/cutoff quiet winners and searched
alternatives, but it discards the narrower event where a reduced probe appears
to improve alpha and its mandatory full-depth re-search then proves otherwise.

The initial pre-5.2 audit selected no other work inside the then-current scope.
ADR-0034 later corrected that scope: dynamic reduction, richer histories and
their dependent search clusters remain pre-NNUE work. Aspiration and root
confidence still belong to 6.0, correction history to 5.4, SMP to 6.2, and
razoring remains parked by its tactical refutation. Stockfish's
classical search demonstrates the broad concept of post-reduction history
feedback, but Manta does not adopt its tables, formulas, constants or history-
controlled reductions. The bounded local question is whether one authoritative
false-positive outcome can improve Manta's already accepted reply ordering.

## Decision

- Add independently ablatable `Features.lmr_reply_feedback`. It was default on
  only for the MAN-S14 candidate; the rejected production disposition defaults
  it off and restores accepted MAN-S13 exactly.
- A reduced LMR probe has no training authority. It must first rise above the
  parent's current alpha and trigger the already-required full-depth re-search.
- Train only when the full-depth result is an upper bound at or below that same
  alpha. This specifically refutes the reduced probe's apparent improvement.
- Require an eligible quiet move, a real previous-move reply context, ordinary
  non-exclusion search and caller-owned heuristics. Root, null, exclusion,
  capture, promotion, pruned, aborted and unsearched paths cannot train.
- Unmake before updating so the accepted reply key reads the current move's
  piece from its restored origin. Apply one existing bounded depth-squared
  negative update.
- Remove the already-searched quiet from the node's later loser set after the
  update. A subsequent exact/cutoff winner therefore cannot penalize the same
  relation twice at that node.
- Keep reply history as quiet-ordering evidence only. It cannot alter LMR
  eligibility or depth, pruning, score/bound, TT, PV, evaluation,
  terminal/draw or qsearch authority.

## Consequences

Legal generation and make/unmake remain authoritative. Promotions and captures
are excluded as current moves; prior special moves retain MAN-S13's resulting-
piece context semantics. Cancellation returns before any update, and terminal,
draw, TT, null, ProbCut and exclusion paths cannot manufacture feedback.

The ordinary hot path adds one boolean and an occasional worker-local bounded
integer update after an LMR re-search. It adds no allocation, formatting, I/O,
lock, atomic or shared state. The 288-KiB per-worker reply table is unchanged.
The candidate may improve ordering by demoting context-specific replies that
repeatedly trigger wasted re-searches. Node count cannot establish that claim;
the registered time-based games decide it.

## Verification

- A focused legal-position test proves the producer is non-vacuous, is bounded
  by the LMR re-search population, disappears with the feature disabled and
  restores both root positions with sequentially legal PVs.
- Observation accounting requires false-positive penalties not to exceed LMR
  re-searches or total contextual penalties. Exact/cutoff reward attribution
  remains unchanged and generic node fail-low attribution remains zero.
- Feature-off depth-six bench is exact MAN-S13 at `842,040`. MAN-S14 is
  `842,143` (+0.012%); this is a diagnostic tree-shape snapshot, not strength
  or speed evidence.
- Two ReleaseSafe `manta-search-observation-v7` reports are byte-identical at
  SHA-256
  `6F0CF7D11F97D5BE95F0D12C9485F92DE4E0F73A32B25BFBEBDA1B3062F076E9`.
  Across 12 legal roots they record 3,978 LMR probes, 98 mandatory full-depth
  re-searches and 63 false-positive penalties, plus 213,833 contextual lookups,
  266 exact updates, 10,722 cutoff updates and 6,301 total penalties.
- Debug, ReleaseSafe and ReleaseFast suites pass, including all 16 UCI
  transcripts; format, policy/lint and portable-build gates also pass. The
  clean Zig-0.16 native candidate is
  `ff7b4f1`/`3626F557E125350149181F85BCCAEEE56F81C0AD2A00B3F765E17612152CC605`;
  accepted MAN-S13 is
  `1755dc8`/`F707FA7817C09C2580457561A965843300F918FAD21228680FF0379741FE4E48`.
  Both manifests are clean, native, non-PGO and compiler-equal.
- The registered gate is candidate A versus accepted MAN-S13 B, 1T `3+0.03`,
  Hash 64 MiB, concurrency 14 on the Ryzen 9 5950X, explicit physical CPUs
  `0,2,...,26`, UHO book, strength-v1 adjudication, seed `514146`, normalized
  `[3,10]`, alpha/beta 0.05 and at most 12,000 games. Recent gates measured
  about 55 pairs/minute: expect roughly 10–30 minutes for a material boundary
  and about 110 minutes at the cap; stop manually at three hours. Budget
  storage is under 40 MiB. The temporary fastchess bridge has no reliable
  pair-atomic resume, so an interrupted run is restarted rather than combined.
- The last complete report covered 3,558 games: 845 wins, 885 losses and 1,828
  draws, pentanomial `[94,445,727,433,80]`, `-5.87 +/- 11.42` nElo and LLR
  `-2.55`. No engine/runner anomaly appears in the log. The run did not cross
  the formal H0 boundary, so the record says maintainer-directed rejection on
  the H0 side rather than H0 acceptance. Manifest, PGN and log SHA-256 values
  are `A0E57B23AA3E30BE8D4D02E0840BB05AFDE228C5D1CA2BA97537699322BC9CED`,
  `BFE44AD3B0DA8FFC443D3F8819353F95E7D7A9592F13D65B95DA5EEC7C9E8644`
  and `CC634C465457F985E32DAE1A7AEA75E37CE4F8B64F71BCBC294C941D507229B2`.

## Traceability

Supports `FUNC-004`, `FUNC-005`, `FUNC-006`, `SCORE-010`, `SCORE-013`,
`SCORE-014`, `PERF-006`, `PERF-009`, `PERF-010`, `QUAL-005`, `QUAL-013`,
`QUAL-014`, `QUAL-015` and `QUAL-016`.
