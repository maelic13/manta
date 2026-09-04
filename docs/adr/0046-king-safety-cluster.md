# ADR-0046: Shelter, attack maps and king safety

## Status

Accepted as `MAN-E03` for Steps 5.3.3 to 5.3.5 on 2026-08-16. The registered
gate accepted H1, so shelter, shared attack maps and king safety are retained
production behaviour, and the Steps 5.3.1 and 5.3.2 work they carried is
retained with them.

## Context

The evaluator had no king-safety model of any kind. Against the pinned
classical reference this was the largest single gap: that evaluator has a
complete model of king ring, attacker weights, safe checks and shelter, where
Manta had nothing. Every middlegame was therefore evaluated as if kings could
not be attacked.

## Decision

- Evaluate shelter and storm per king across its own file and both neighbours,
  by rank distance, since that is what decides how much cover a pawn gives and
  how soon a storming pawn arrives. Score a blocked storm separately from one
  with a clear path, and penalise a file empty of both colours on its own.
- Produce the per-colour attacked-square sets once as shared evidence,
  including a doubly-attacked set that separates a defended square from a
  merely touched one, plus king rings and attacker tallies.
- Accumulate king danger from attacker weight, from ring squares the attacker
  holds and the defender does not hold twice, and from checking squares split
  by whether the defender controls them.
- Ignore a lone attacker entirely: one piece cannot break a defended king, and
  crediting it would make ordinary development look threatening.
- Square accumulated danger before it becomes a score. The chess fact is
  superlinear, two co-ordinated attackers being far worse than twice one, and
  the square law is the shape that fact demands rather than a fitted curve.
- Charge only the middlegame, since a king with few enemy pieces left is an
  asset rather than a liability.
- Keep the whole cluster compile-time ablatable through `king_safety`.

## Consequences

Producers are pawn structure and the shared attack sets, both derived from
authoritative board facts. The consumer is the tapered score. No terminal,
draw or tablebase authority is touched.

This is the first cluster since the search freeze that changes ordinary play,
so every frozen search fingerprint moved. All were re-recorded together with a
stated reason. The parameters are reasoned starting values, not fitted ones;
the gate measures whether the mechanism helps, not whether these numbers are
optimal.

Because it is the first measurable cluster, it also carries the Steps 5.3.1
and 5.3.2 work, whose own effects are too rare to resolve under strength-v1
adjudication. Each remains separately ablatable so a failing gate can be
attributed rather than guessed at.

## Verification

- Colour-mirroring proves every component, including the new term, negates
  under a full board flip. That test had been silently misreading a tapered
  record as a phase after the component count changed; the corrected indices
  now exercise the new term properly.
- Directional tests show a stripped pawn cover scores worse than an intact
  one, and that a lone attacker produces no danger at all.
- An ablation test proves the switch restores an evaluator with no king term.
- Debug, ReleaseSafe and ReleaseFast suites, `zig fmt`, lint, the policy check
  and the portable build all pass.
- The registered gate is prospectively fixed here: candidate `MAN-E03-cand`
  from `0a88627` as A against baseline `MAN-E01-base` from `a6a499b`, one
  thread, `3+0.03`, Hash 64 MiB, concurrency 14 on the designated Ryzen
  9 5950X, normalized `[1, 5]`, alpha/beta 0.05 and at most 16,000 games. The
  harness records the prospective seed. Bounds ask for a modest material gain
  rather than `[3, 10]`, because the term is a first untuned implementation
  and a real but smaller gain should not be discarded.
- Both binaries are clean-tree native builds on the registered host with the
  same toolchain, and their bench fingerprints differ, `744,899` against
  `662,225`, confirming the candidate changes search rather than riding inert.

## Gate outcome

The registered candidate-as-A `[1, 5]` gate accepted H1 at its paired boundary
after 1,592 scored games in 14m19s: 526-332-734, pentanomial
`[29, 146, 304, 236, 81]`, `+60.69 +/- 17.07` nElo, `+42.55 +/- 12.09` Elo,
LLR 2.95 and LOS 100 percent. No timeout, crash, illegal move, disconnect,
forfeit or affinity anomaly occurred. Independent PGN reconstruction
reproduces the win and loss totals exactly; two completed in-flight games
written after the paired boundary are excluded from the statistic, as in
previous runs.

This is by far the largest gain any Manta candidate has produced, and it
resolved in a tenth of the games the parked evaluation gates could not finish.
That is the expected shape when a whole missing evaluation dimension is added
rather than a rare ending corrected, and it retrospectively confirms the
decision to carry the unmeasurable 5.3.1 and 5.3.2 work to a gate that could
actually resolve.

The verdict licenses the cluster, not its individual parameters. These are
reasoned starting values, and the result says the mechanism is worth having;
it says nothing about whether the weights are near optimal.

Artifacts: PGN SHA-256 `F7888C5361E06FE7078996C8F075B3C9BF5BA2F70201431CDAD22F406BACC7A4`; log `DCCFE29C12FDDF5B167F50BE24335D05A43EB5BB799CFFC4CF1283B35F55B5A1`;
manifest `CAA0A06877B9FBCB81AC8D756AB7A3B0EF291C261538E978C73F0E5BA5FCB60E`.

## Traceability

Supports `FUNC-006`, `SCORE-001`, `PERF-006`, `PERF-009`, `QUAL-013` through
`QUAL-016`, and Steps 5.3.3 to 5.3.5 in `PLAN.md`.
