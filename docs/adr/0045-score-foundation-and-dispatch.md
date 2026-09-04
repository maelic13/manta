# ADR-0045: Score foundation and unwinnable-material dispatch

## Status

Proposed as `MAN-E01` for Step 5.3.1 on 2026-08-16. Deterministic qualification
is complete; the registered cluster playing gate is pending.

## Context

Step 5.3.0's residual harness compared Manta's evaluator against the pinned
classical reference across six cohorts and exposed two defects that are chess
rules rather than tuning gaps.

The first is decisive. A king and two knights cannot force mate, yet Manta
evaluated that ending at `+562` and a depth-eight search made it worse at
`+724`. The engine believed it was winning a position it cannot possibly win.
The reference scores the same position `0`. The same blindness covers a lone
minor piece, and it also mis-scores a side that leads on material while holding
only a knight.

The second is shared with the reference. Neither evaluator reads the halfmove
clock, so the harness recorded an identical score for one position at clock 0
and clock 98. A side five halfmoves from a draw claim was told it was a queen
ahead.

Both defects are statements about which outcomes are reachable under the rules,
so they belong in the score foundation rather than in any later positional
cluster.

## Decision

- Add `Config` to the evaluator and expose it as `HceWith(config)`, with
  `Hce = HceWith(.{})` as production. Each rule is independently ablatable, so
  a later audit can attribute playing evidence to one rule rather than to the
  pair.
- Clamp an advantage its holder cannot force mate with to exactly zero. A side
  lacks mating material when it has no pawn, rook or queen, and either no
  bishop at all or at most one minor piece in total. A pawn can promote, and a
  rook or queen mates alone, so either leaves mating material. Two minors
  including a bishop can mate; knights alone cannot however many there are.
- Examine only the leading side. The trailing side's material says nothing
  about whether the position can be won, and the clamp answers exactly one
  question: can the side that is ahead convert.
- Return exactly zero rather than a scaled remainder. This is a claim about
  reachable outcomes, not a confidence discount, so a fraction would assert a
  winning chance that does not exist.
- Scale an ordinary score by the share of the fifty-move allowance that
  remains, once the clock passes sixty halfmoves. Below that threshold a
  capture or pawn move is overwhelmingly likely, so scaling would distort
  ordinary play instead of describing the rule. Above it the score falls
  linearly to zero at the hundred-halfmove draw.

## Consequences

Producers are piece counts and the halfmove clock, both authoritative board
facts. The consumer is the final ordinary score. Neither rule manufactures a
terminal, repetition or tablebase result: the evaluator still returns an
ordinary score, and search remains the only authority that can declare a draw
or a mate. A defender who walks into mate in an unwinnable ending is still
found by search, whose mate score dominates the clamped zero.

`SCORE-001` forbids static evaluation from manufacturing terminal, repetition
or rule-draw *evidence*. It does not forbid reading the halfmove clock, and
`PLAN.md` schedules rule-50 scaling inside this step. Two tests previously
asserted the stronger reading that the clock is never an evaluator input; they
are rewritten to assert the corrected contract, and the castling and
en-passant halves of that invariant are kept intact and separate.

The accepted whole-search fingerprint is unchanged at `744,899`, because every
position in the frozen bench corpus has mating material and a fresh clock. One
archived ablation moved by a single node, from `919,299` to `919,298`, and the
evaluator corpus checksum moved from `354` to `100`. Both are recorded here as
intentional.

Evaluation cost is unchanged in the hot path: the clamp reads existing piece
bitboards and the scale is one comparison plus one multiply and divide, all
after the tapered interpolation that already ran.

## Verification

- Focused tests cover each mating-material class: king and two knights, a lone
  knight, a lone bishop and a knight-versus-pawn lead all score zero, while
  bishop and knight, queen and rook keep their advantage.
- A halfmove-clock test proves the score is unchanged below the threshold and
  shrinks monotonically toward zero above it, while remaining an ordinary
  score.
- An ablation test proves both switches off reproduce the earlier evaluator,
  and that enabling only the clamp leaves the clock inert.
- The residual harness records the change directly: king and two knights moves
  from `+562` to `0` at every reported depth, a queen ending at clock 95 falls
  from `+1201` to `+150`, and bishop and knight at clock 98 falls from `+831`
  to `+41`, while the same bishop and knight ending at clock 0 is untouched.
- Debug, ReleaseSafe and ReleaseFast suites, `zig fmt`, lint and the policy
  check pass.
- The first registered gate was abandoned before completion once the audit
  found defects in the candidate, and its partial result is not evidence. The
  gate is re-registered prospectively as `MAN-E02`, covering the score
  foundation together with the Step-5.3.2 correctness repairs: candidate
  `MAN-E02-cand` from `aecb323` as A against baseline
  `MAN-E01-base` from `a6a499b`, one thread, `3+0.03`, Hash 64 MiB,
  concurrency 14 on the designated Ryzen 9 5950X, `simplify` bounds
  `[-5, 0]`, alpha/beta 0.05 and at most 16,000 games. The harness generates
  and records the prospective seed.
- Non-regression bounds are the honest instrument for this cluster. Both rules
  correct a rule-level error rather than add a heuristic, and both are provably
  inert on the frozen bench corpus, so the trigger is rare and the true effect
  is expected to be small. Demanding a `[3, 10]` gain would reject a correct
  change for lack of measurable benefit, while `[-5, 0]` asks the question that
  actually matters: does fixing the evaluator cost anything. H1 keeps the
  cluster; H0 indicates the fifty-move threshold or linear shape is wrong and
  that rule is ablated before any retry.
- Both binaries were built on the registered host from clean trees with the
  same Zig 0.16.0 toolchain, report the identical `744,899` bench fingerprint,
  and differ exactly where intended: king and two knights reports `+724` from
  the baseline and `0` from the candidate.

## Gate outcome

`MAN-E02` was stopped at 4,922 scored games with LLR 0.13 against a 2.94
boundary, roughly four percent of the way. At the observed rate H1 would have
needed about 111,000 games against a 16,000 cap, so the gate could only ever
have exhausted its budget unresolved. The partial result is parked and is not
evidence.

The cause is measurability, not the change. Across those games the fifty-move
rule decided 3 of 4,922 (0.06%), while 49% ended in threefold repetition and
48% by adjudication. The `resign=600/3` rule ends games long before endgames
materialise and `draw=10/8 from move 40` ends shuffles before the halfmove
clock can climb, so strength-v1 adjudication removes exactly the positions
this cluster corrects. The Step-5.3.2 repairs are inert in a gate by
construction, because no `SyzygyPath` is configured during games.

`PLAN.md` anticipates this case and permits a prospectively registered
no-adjudication or recalibrated gate when evaluator semantics fall outside
what strength-v1 can see. Rather than recalibrate the host for a change whose
measurable effect is near zero by construction, the cluster is carried forward
and gated together with the first evaluation term that changes play in
ordinary positions. Its own evidence stays deterministic: rule-level proofs,
focused tests, harness deltas and an unchanged bench fingerprint.

## Traceability

Supports `FUNC-006`, `SCORE-001`, `PERF-006`, `PERF-009`, `QUAL-013` through
`QUAL-016`, and Step 5.3.1 in `PLAN.md`.
