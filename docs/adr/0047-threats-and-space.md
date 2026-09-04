# ADR-0047: Piece threats and space

## Status

Accepted as `MAN-E04` for Step 5.3.6 on 2026-08-17. The registered gate
accepted H1, so piece threats and space are retained production behaviour.

## Context

Manta scored only pawn threats. Pressure from pieces, undefended material and
space control were invisible to the evaluator, so a position where the
opponent had a loose rook under fire looked identical to one where the same
rook was safe.

## Decision

- Read every threat from the shared Step-5.3.4 attack maps rather than
  recomputing, which is what that split existed for.
- Charge a piece the opponent attacks and does not adequately defend by the
  value under fire and by the cheapness of the attacker: such a piece must
  move, be defended or be lost, and each costs more the more valuable it is.
- Charge an undefended piece separately. It is a standing liability rather
  than a contested one, because the opponent chooses the moment.
- Let a king threaten only what the defender does not cover, weighted toward
  the endgame where touching an enemy piece usually wins it.
- Count space as controlled squares in our own half the opponent does not
  contest, and switch the term off below a material floor: in a bare ending
  extra squares are not an asset and counting them would be noise.
- Keep the cluster compile-time ablatable through `threats_and_space`.

## Consequences

Producers are the shared attack sets and piece placement. The consumer is the
tapered score. No terminal, draw or tablebase authority is touched.

Every frozen search fingerprint moved and all were re-recorded together. Two
population assertions needed deeper searches once the tree shifted; neither
was weakened, each was given a depth where its mechanism still fires.

## Gate outcome

The registered candidate-as-A `[1, 5]` gate accepted H1 at its paired boundary
after 4,426 scored games in 40m24s: 1,187-992-2,247, pentanomial
`[84, 490, 916, 593, 130]`, `+23.23 +/- 10.24` nElo, `+15.32 +/- 6.76` Elo,
LLR 2.96 and LOS 100 percent. No engine, clock, protocol or placement anomaly
occurred and the binaries matched their registered hashes.

The gate ran against accepted MAN-E03 rather than the older baseline, so the
result isolates this cluster instead of re-measuring the king-safety gain. It
took nearly three times the games of MAN-E03 for a third of the Elo, which is
the expected shape: king safety filled a structural hole, while threats refine
a dimension that already partly existed through pawn threats and mobility.

The verdict licenses the cluster, not its individual weights, which remain
reasoned starting values.

Artifacts: PGN SHA-256 `AA555643657455D234147FFD4F5B040D84A8BE8B9C2B8F4C89D54BDDEB70EDB7`; log `2BA6ED8A6F43602B3FFA2187189E931ED9957AE7FCC7C1512756E9A462C0DCB3`.

## Traceability

Supports `FUNC-006`, `SCORE-001`, `PERF-006`, `PERF-009`, `QUAL-013` through
`QUAL-016`, and Step 5.3.6 in `PLAN.md`.
