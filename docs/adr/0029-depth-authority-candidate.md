# ADR-0029: Depth-authority candidate

## Status

Accepted as `MAN-S10` on 2026-08-12. Its registered `[3,10]` playing gate
accepted H1; the complete family is retained and Step 5.1.4.3 is open.

## Context

Accepted MAN-S07 has explicit nominal, extension and reduction depth intent,
but only LMR and null move change searched depth. Checks deserve additional
resolution because the checked side has no legal option except an evasion. A
deep PV node without a legal TT move has weaker ordering evidence and can spend
one less ply before its result receives normal authority. Conversely, a deep
ordinary TT lower/exact value may identify a uniquely important move, but only
if a search of every legal alternative fails below a score derived from that
record.

These mechanisms change one another's depth and TT consumers. Testing them as
one family avoids treating an incomplete depth model as a finished playing
candidate. Manta's guards and fixed one-ply transformations are native
reasoning choices; reference engines supplied dependency and failure-mode
ideas, not code, formulas, constants or a convergence target.

## Decision

- Extend an in-check main-search node by one ply before horizon handling. The
  root iteration retains its nominal completed depth and `MAX_PLY` remains the
  hard recursion boundary.
- Apply one-ply internal iterative reduction only at a non-root, non-check PV
  node of searched depth at least five that has no legal TT move. Root and
  exclusion nodes are never reduced.
- Attempt singular verification only at a non-root, non-check ordinary node of
  searched depth at least six. Its legal TT move must come from an ordinary
  lower/exact record no more than one ply shallower than the requested search;
  a depth-sufficient record still performs its normal TT cutoff first.
- Search the unchanged position two plies shallower through a null window while
  excluding exactly the TT move and disabling null move. Only an upper-bound
  result below the TT value minus one Manta pawn makes that TT move singular
  and extends its ordinary child search by one ply.
- Exclusion is not a chess terminal condition. If no alternative remains it
  returns an exclusion fail-low. Exclusion searches do not probe or store the
  TT, build a PV, update quiet history, run null move or expose reusable
  provenance; `exclusion_search` exists only for typed diagnostics.
- Keep the family and check, IIR and singular producers independently
  compile-time ablatable. Disabling `depth_authority` restores accepted
  MAN-S07 exactly.

## Consequences

Check state is produced by authoritative board transition/checker data. TT
probe supplies a legality-validated move plus decoded score, bound, depth and
producer. Depth intent transforms those facts; main search, TT depth, PVS/LMR,
PV publication and diagnostics consume the resulting horizon. Excluded-move
state is fixed per worker ply and is saved/restored around the same-position
probe, so future SMP adds no shared mutable policy.

Legal generation, castling, en-passant and promotion identity remain owned by
the board layer. Repetition/rule-50 and terminal detection run before any
selective mechanism. Mate/tablebase scores cannot seed singular verification,
and exclusion evidence cannot escape into ordinary TT/PV/history consumers.
The hot path adds no allocation, formatting, I/O, lock or shared atomic.

The family may increase nodes in forcing lines: the depth-six benchmark moves
from MAN-S07's `2,288,471` to `3,581,485` nodes (+56.49%). This is diagnostic
cost, not evidence of strength. The versioned 12-root observation records
`105,368` nodes, 3,782 check extensions and three naturally rejected singular
attempts. Focused no-TT and seeded-TT tests separately populate IIR and an
accepted singular extension, prove exact exclusion count, legal PVs, completed
nominal root depth, restored position state and zero exclusion TT stores.

## Verification and promotion

- Debug, ReleaseSafe and ReleaseFast suites, format, lint, supported builds and
  the tactical/mate/endgame/UCI gates must pass.
- Family-off depth-six bench must remain exactly `2,288,471`; each producer has
  a focused ablation and the final candidate fingerprint is `3,581,485`.
- Two `manta-search-observation-v3` ReleaseSafe reports must be byte-identical.
- The sole promotion evidence is registered `MAN-S10`: candidate as A against
  MAN-S07, 1T `3+0.03`, Hash 64 MiB, concurrency 14 on the Ryzen 9 5950X,
  normalized `[3,10]`, alpha/beta 0.05, seed `514102`, maximum 12,000 games.
  It accepted H1 after 1,818 games/909 pairs in 16m09s: 547-424-847,
  pentanomial `[39,182,365,263,60]`, `+34.91 +/- 15.97` nElo and LLR 2.95.
  No infrastructure anomaly was reported. The returned summary did not include
  binary or run-artifact hashes; retain them as release-manifest inputs if they
  become available.

## Traceability

Supports `FUNC-004`, `FUNC-005`, `FUNC-006`, `SCORE-003`, `SCORE-004`,
`SCORE-010`, `SCORE-011`, `PERF-006`, `PERF-009`, `PERF-010`, `QUAL-013`,
`QUAL-014`, `QUAL-015` and `QUAL-016`.
