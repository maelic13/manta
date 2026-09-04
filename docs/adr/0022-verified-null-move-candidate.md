# ADR-0022: Verified null-move pruning

## Status

Accepted for Step 5.1 on 2026-08-11 by `MAN-S03`.

## Context

Manta's exact one-thread baseline searches every legal main-tree move at full
nominal depth apart from PVS probes. In many non-PV positions, evidence that a
side could pass and still exceed beta can reject the subtree cheaply. Passing
is not a legal chess move, however, and is specifically unreliable in
zugzwang. Null results therefore cannot acquire terminal, exact or full-search
authority merely because they produce a numeric score.

## Decision

- Keep null pruning compile-time ablatable. The production candidate enables
  it without adding a runtime policy interface to recursive search.
- Consider only zero-window non-PV nodes of depth at least four. Exclude check,
  an immediate prior null, non-ordinary beta values, positions without
  side-to-move non-pawn material, and static evaluations below beta.
- Apply the existing search-only reversible null transition. Send its empty
  factual delta through the evaluator's forward/backward update seam because
  side-to-move perspective still changes.
- Search the null child with a two-ply reduction. A supported fail-high starts
  a null-disabled verification search of the legal position at depth minus
  two; every fail-high is verified rather than trusting a depth threshold.
- On successful verification, return fail-hard beta as a lower bound with
  `null_move` provenance and no fabricated chess move. Mate/tablebase values
  never originate from this cutoff because eligibility requires ordinary beta.
- Abort from the null child or verification search unwinds evaluator and board
  state before retaining the prior completed root iteration or legal fallback.

The two-ply reduction represents one complete move by both sides and was a
reasoned candidate value, not an imported engine constant or fitted result.
The registered time-based game gate accepted the complete mechanism.

## Consequences

- Null pruning changes the deterministic search tree and may change move
  selection; smaller node count or greater depth does not establish strength.
- Pawn-only endings are conservatively excluded. Verification reduces, but
  cannot mathematically eliminate, zugzwang risk in positions with pieces.
- TT consumers retain the existing bound/provenance checks. A stored null
  cutoff has no move and cannot become exact root evidence.
- The accepted depth-6 diagnostic fingerprint is `6,715,524` with the
  mechanism enabled. This remains diagnostic evidence rather than the reason
  for promotion.

## Verification and promotion

- Feature-focused tests cover pawn-only zugzwang exclusion, mate/material
  canaries, legal PVs, exact completed-root publication and null-side evaluator
  restoration during forced abort.
- Existing repetition/null fencing, transition reconstruction, TT validation,
  deterministic reset, self-play smoke, UCI/process and all optimization-mode
  gates remain mandatory.
- After repairing timer-polled UCI completion symmetrically in candidate and
  baseline, the 100-game pilot completed without anomaly and reduced
  Windows-tick-aligned move times from 82.98% to 19.82%.
- The only promotion gate used candidate-as-A, one thread, `3+0.03`, Hash 64
  MiB, concurrency 14, normalized `[3,10]` nElo, alpha/beta 0.05 and a
  16,000-game cap. Seed `417776518` accepted H1 after 1,070 scored games:
  407 wins, 281 losses, 382 draws, `+56.04 +/- 20.82` nElo and LLR 2.96.
  There were zero timeouts, crashes, illegal moves, protocol or affinity
  anomalies. The result licenses the complete verified-null mechanism, not
  either reduction or guard independently.

## Traceability

Supports `FUNC-003`–`FUNC-006`, `SCORE-001`, `PERF-006`, `PERF-009`,
`PERF-010`, `QUAL-013`, `QUAL-014` and `QUAL-016`.
