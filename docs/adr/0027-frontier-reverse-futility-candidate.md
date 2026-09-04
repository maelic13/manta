# ADR-0027: Frontier reverse-futility candidate

## Status

Parked component checkpoint from `MAN-S08` on 2026-08-12. Deterministic
qualification passes, but the mechanism defaults off and has no isolated
playing gate. It may be reconsidered only in the dependency-complete Step
5.1.4.3 shallow-selectivity family after depth authority freezes.

## Context

Accepted MAN-S07 distinguishes raw HCE, stand pat, searched qsearch scores and
TT bounds. At a shallow non-PV zero-window node, an ordinary static score far
above beta can indicate that expanding every quiet continuation is unlikely to
change the fail-high result. Static evaluation is nevertheless not proof: it
cannot manufacture terminal, draw, mate, PV or reusable TT authority.

The first implementation admitted depths one through three and immediately
failed the WAC.001 forcing-move canary at root depth three. That was treated as
a mechanism-level refutation: a depth-two child left too much unresolved
tactical space. The final candidate is categorically restricted to the
depth-one main-search frontier rather than tuning a larger margin around the
failure.

## Decision

- At depth exactly one, permit reverse-futility pruning only at non-PV,
  zero-window nodes where the side to move is not in check, beta is an ordinary
  score and the side to move has non-pawn material.
- Evaluate the unchanged legal position. Cut off only when static evaluation
  is at least beta plus one pawn. The margin derives from Manta's normative
  100-search-unit pawn scale; it is not an imported coefficient or fit.
- Return fail-hard beta as typed lower-bound `speculative_cutoff` evidence.
  Store no TT entry and produce no move or PV at the pruned node.
- Keep terminal and history-draw checks before the heuristic. Check evasions,
  decisive-score windows and pawn-only zugzwang-sensitive positions retain
  ordinary search.
- Keep the mechanism compile-time ablatable. Disabling `reverse_futility`
  restores accepted MAN-S07 exactly.

## Consequences

- The producer is raw HCE of the current position. Transformations are the
  depth/window/rule guards and the one-pawn comparison. The immediate consumer
  is only the parent alpha-beta search; TT, root publication and PV construction
  receive no direct speculative record.
- Legal generation, make/unmake, castling, en passant, promotion, terminal,
  repetition/rule-50, mate-distance and accepted qsearch semantics are
  unchanged. Pawn-only nodes are excluded to avoid treating zugzwang as a
  pass-like static advantage.
- A cutoff avoids legal move generation, child branches and their cache/TT
  traffic. Eligible non-cutoffs pay one HCE call. There is no allocation,
  formatting, I/O, lock or shared atomic; one-thread determinism remains the
  baseline.
- This would be selective playing policy when enabled. Exact tests and a
  smaller tree qualify only the component implementation. Because shared depth
  authority and neighboring shallow consumers are not yet frozen, the feature
  defaults off and production remains accepted MAN-S07.

## Verification

- Pure eligibility tests exclude PV, check, non-zero-window, pawn-only,
  decisive-score, disabled and non-frontier nodes and freeze the one-pawn
  scale-derived margin.
- Focused legal-position tests prove a nonzero candidate/cutoff population,
  feature-off behavior, exact legal root publication, legal PV replay, full
  state restoration, zero speculative TT stores and zero pawn-only candidates.
- The initial depth-one-through-three scope changed WAC.001 from forcing
  `Qg6`; narrowing to depth one restores that canary plus every mate/material,
  draw/history and UCI test.
- The candidate fingerprint is `2,002,938` nodes versus accepted MAN-S07
  `2,288,471`, a 12.48% reduction in this diagnostic workload. Feature-off is
  exactly `2,288,471`.
- Two ReleaseSafe `manta-search-observation-v1` reports are byte-identical at
  SHA-256
  `88F64FE27866C4770C56299ACDF5B4DF8D44D2B703F7002BD182D3F8B4E7B9FF`.
  Across 12 roots they record 2,534 candidates and 1,050 cutoffs. Both
  pawn-only zugzwang roots record zero candidates, and speculative TT stores
  remain zero.
- No MAN-S08 SPRT is authorized. Step 5.1.4.3 may reuse the implementation and
  diagnostics only after 5.1.4.2 freezes check-extension, IIR and
  singular/exclusion depth authority; it must re-evaluate the current guards,
  margin and consumers within the complete shallow-selectivity family.

## Traceability

Supports `FUNC-004`, `FUNC-005`, `FUNC-006`, `SCORE-001`, `SCORE-004`,
`PERF-006`, `PERF-009`, `PERF-010`, `QUAL-005`, `QUAL-013`, `QUAL-014`,
`QUAL-015` and `QUAL-016`.
