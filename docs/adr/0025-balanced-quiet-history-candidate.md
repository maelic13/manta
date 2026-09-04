# ADR-0025: Balanced quiet-history and conservative reduction confidence candidate

## Status

Rejected for Step 5.1.2 through `MAN-S06` on 2026-08-12. The registered
playing gate accepted H0; both features default off and MAN-S04 remains the
accepted production behavior.

## Context

Accepted MAN-S04 orders quiet moves with a single from/to history table, but
only quiet beta cutoffs update it. Repeated success can therefore saturate an
entry without contrary searched outcomes aging it, and LMR cannot distinguish
the first reducible quiet move that has positive local evidence. Richer
contextual tables would add producers and consumers that Manta has not yet
shown it needs.

History is fallible worker-local ordering evidence. It is not a chess fact,
static evaluation, score bound, terminal/draw result or TT provenance. Any
consumer must preserve the accepted rule, special-move and full-depth
publication contracts.

## Tested decision

- Keep the existing `[side][from][to]` table and two killers. Do not add a new
  allocation, context table or shared state.
- On a full-authority quiet beta cutoff, apply a positive depth-squared update
  and retain the existing killer rotation. Apply an equal negative update only
  to earlier quiet non-promotion moves already searched at the same node.
  Captures, promotions and unsearched later moves are not failures.
- Use bounded gravity with limit `16 * 1024`; every touched entry ages in
  proportion to the new update instead of irreversibly accumulating. Cap the
  depth input before squaring so arithmetic remains bounded.
- Let a positive history score protect only the fourth ordered quiet from the
  accepted MAN-S04 one-ply LMR probe. It is the first otherwise-eligible move;
  fifth and later quiets remain reducible. Check, evasion, tactical and
  checking-move exclusions remain unchanged.
- Keep balanced outcome learning and history-informed LMR as independent
  compile-time switches. Disabling both restores the exact MAN-S04 search
  mechanism and deterministic fingerprint.
- Extend the policy-inert observer with penalty and LMR-protection counts.
  Diagnostics remain caller-owned and cannot return a decision to search.

## Consequences

- The producer is a verified quiet cutoff after full-depth/PVS authority. The
  transformations are signed bounded history updates; consumers are quiet
  ordering and the narrow first-reducible-move LMR guard.
- A reduced alpha rise still receives mandatory full-depth re-search. A
  reduced-only fail-low cannot cut off, update history or publish a PV/bound
  with full-search authority.
- Legal generation, make/unmake, castling and en-passant treatment,
  check/evasion search, terminal and repetition/rule-50 results, TT semantics
  and root publication are unchanged.
- Ordinary nodes add bounded integer work and reuse the already ordered move
  prefix. They allocate nothing and add no I/O, lock, shared atomic or
  cross-thread state. One-thread determinism remains the current scope.
- The proposal was rejected when the registered final-binary SPRT accepted H0.
  Node reduction and trace populations were diagnostic only. The isolated
  switches and tests remain as refutation history; production does not consume
  either feature.

## Verification

- Unit tests cover positive/negative saturation, aging and success-only killer
  rotation. Focused legal-position tests exercise rewards, searched-failure
  penalties, LMR protection, feature-off behavior, legal PVs and restored
  position state.
- Debug, ReleaseSafe and ReleaseFast suites pass, including all 16 UCI process
  transcripts. Formatting, lint and architecture policy pass.
- The final candidate fingerprint is `2,885,300` nodes versus MAN-S04
  `2,910,189` (0.86% fewer). With both switches disabled it is exactly
  `2,910,189`.
- Two ReleaseSafe `manta-search-observation-v1` reports are byte-identical at
  SHA-256
  `C554798E0CC3B4DC988E6F4945A250C6C94C4D0766EE45C39327071D6D6EF658`.
  Across the 12 roots they observe 1,239 rewards, 587 searched-failure
  penalties, 254 LMR probes and one narrow history protection.
- An initially broad exemption for every positive-history late quiet was
  rejected before games: it produced `3,189,838` nodes (9.61% above MAN-S04),
  while that broad LMR consumer over legacy history alone produced `4,503,780`
  (54.76% above). Balanced outcomes without the LMR consumer produced
  `2,781,748` (4.41% below). These ablations selected scope; none proves
  strength or independently licenses a component.
- The exact archive SHA-256 is
  `F85134A6D4056165F94A00984125FAFF8F4190A3838E890F25B87FD4F381549E`.
  Clean Ryzen-native Zig 0.16.0 artifacts were candidate
  `18929fb4c1b16b35c913761873c530faf095c4df` /
  `D41B267729654EA5F316AE282CD2F4E17427C5D80635E81E8A646BEB9AC54659`
  and MAN-S04 baseline `d43b6762dcaa61181d50b6250cb3fc8ff40ee893` /
  `89258DCDF9AE79F408AC1FA08AE8BEFEC754188FDD50E2EEAEAC1CCB3F58E6B6`.
- On the registered Ryzen 9 5950X, candidate-as-A 1T `3+0.03`, Hash 64 MiB,
  concurrency 14, seed `512061` and normalized `[3,10]`, H0 was accepted after
  2,448 scored games/1,224 complete pairs in 21m39s: 620 wins, 690 losses,
  1,138 draws, pentanomial `[78,321,490,263,72]`, `-14.31 +/- 13.76` nElo and
  LLR -2.95. Independent PGN reconstruction matches every scored total.
  Fastchess stopped one candidate process after the H0 boundary; its
  disconnected game and two completed unpaired in-flight games were unscored.
  No scored timeout, crash, illegal move, protocol, clock or affinity anomaly
  occurred. PGN SHA-256 is
  `40037499C7105FE1483D92AD77452ACE68E962BF732A71535462D1CBCF3FD878`.

## Traceability

Supports `FUNC-004`, `FUNC-005`, `FUNC-006`, `PERF-006`, `PERF-009`,
`PERF-010`, `QUAL-005`, `QUAL-013`, `QUAL-014`, `QUAL-015` and `QUAL-016`.
