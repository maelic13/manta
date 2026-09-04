# ADR-0048: Material imbalance and evaluation cost

## Status

Partly accepted, partly rejected, on 2026-08-17. The cost work is **accepted**
as behaviour-neutral implementation work and recorded as `MAN-P01`; it is
production. The imbalance term was **rejected as `MAN-E07`** at `-7.00` Elo
against that accepted head and is archived default-off. The combined `MAN-E06` gate this
ADR originally proposed was withdrawn before any verdict — see
[ADR-0049](0049-separating-behaviour-neutral-cost-from-chess-terms.md) for why
the bundle could not have answered the question it was asked.

## Context

Two problems belong to this step, and they are opposite in kind.

The evaluator valued each piece at a constant, so it held that a knight is
worth the same on a blocked board as on an empty one and that two rooks are
worth exactly twice one. Neither is true, and the error only shows when the
two sides hold different material, which is precisely the position type an
engine has to judge when it decides whether to take an exchange.

At the same time the evaluator had become expensive. Steps 5.3.3 to 5.3.6 took
throughput from 6,313,094 to 3,602,798 evaluations per second on the
development host. A semantically attractive evaluator that loses time-based
games is rejected, so the cost had to be brought back before more chess
meaning was added to it.

## Decision

### Cost, with no change of meaning

- Establish the repetition facts once, when the state is created, instead of
  walking the state chain at every visited node. The transition already
  recorded the distance back to the nearest earlier occurrence of the key;
  that field now also carries, in its sign, whether a further occurrence
  stands behind it. No irreversible move can fall inside the reversible
  post-null window, so the matched ancestor's window is exactly this one
  shortened by the distance travelled: an occurrence it recorded lies inside
  this window too, and any occurrence before the match lies inside its own.
  The two encodings are therefore equivalent, and the search-cycle test
  becomes a constant-time read. The official threefold claim keeps its walk,
  which makes it an in-repository oracle for the encoded form.
- Produce piece activity and the shared attack maps in one pass. The squares a
  piece reaches under the current occupancy answer both "how much can this
  piece do" and "which squares does this side hold"; two passes paid the
  sliding lookup twice for every slider on the board.
- Compute the pawn terms as sets rather than pawn by pawn. Doubled, isolated,
  connected and passed pawns are all statements about a set, so they come from
  file fills and spans; only the passed bonus keeps a loop, because it is
  indexed by advancement, and it visits passed pawns alone. Shelter takes the
  nearest own pawn ahead of the king from the first set bit in the king's
  direction of play. Pawn attack spans are two masked shifts, and the passed
  regions are a compile-time table.

### Nonlinear material imbalance

Three relations, each a product of piece counts rather than a sum:

- A knight profits from a crowded board and a rook suffers on one. The knight
  wants support points and short lines; the rook wants open files. Both are
  measured against every pawn on the board, because the whole pawn mass closes
  a position rather than one side's share of it.
- Rooks duplicate each other. They want the same open files and the same
  seventh rank, so a second rook adds less than the first. The bishop pair is
  the opposite case, two bishops covering complementary square colours, and is
  already credited by its own term.
- A queen duplicates a rook for the same reason.

Every one of these cancels exactly between equal armies, so the term is silent
whenever the two sides hold the same pieces and speaks only across a material
difference. That is what makes it an imbalance rather than a second material
table, and it is the property that distinguishes it from rejected MAN-E05,
which scaled the whole endgame half of every position it touched.

The switch is `material_imbalance`. **It defaults off**: the relations were
rejected as `MAN-E07`, so production evaluates a purely additive material
value and enabling the switch restores the archived mechanism for study.

### Deliberately not done

- **Lazy evaluation is rejected for now.** It would require the window to
  reach the evaluator, which makes the result a property of the search state
  rather than of the position. MAN-S19 caches exact raw evaluation in spare
  transposition bits, and a window-dependent value is not cacheable there. The
  search head is frozen, so this cannot be resolved inside an evaluator step.
  Reconsider at 5.4.2, which owns measured search/evaluator compatibility.
- **A pawn-structure cache is not built.** It was the obvious answer while the
  pawn terms cost about a third of the evaluator, but making that work
  constant removed the reason for it. A cache would have added evaluator
  state, per-worker lifetime and a collision contract in exchange for a saving
  the set-wise form already took. Reconsider only if a later pawn term
  reintroduces work that genuinely grows with the position.
- **No new activation guard is added.** The guards that matter already exist:
  a king with no king square, fewer than two attackers or no accumulated
  danger returns before the four check-ray computations, and space is charged
  only above its material floor. Measured over the forty-position bench corpus,
  king safety holds 21.7 percent of evaluator time, threats and space 2.7
  percent, and imbalance is free within noise. The king-safety remainder is
  shelter, which is deliberately unguarded: a broken shelter is a weakness
  whether or not a piece is currently attacking it, so skipping it when no
  attacker is present would change the evaluation rather than only its cost.
  The next reduction there must be a cheaper shelter computation.

## Consequences

Producers are piece counts, the pawn board, the occupancy and the state chain.
Consumers are the tapered score and the search-cycle draw test. No terminal,
draw, tablebase, bound or provenance authority changes: the repetition rewrite
answers the identical question, and the imbalance term is an ordinary score
component that the Step-5.3.1 clamp still overrides where material cannot
force mate.

The pruning bounds that consume static evaluation were re-measured against
accepted MAN-E04 over the deterministic observation suite, since a smaller tree
could starve a consumer. None was starved: late-move pruning goes `360,720` to
`321,277`, reverse futility `21,017` to `18,878`, futility `14,759` to
`13,305`, SEE `16,846` to `15,352`, qsearch delta `5,306` to `4,339` and null
move `370` to `359`, all falling roughly with the node reduction. Every bound
reading zero was already zero at MAN-E04 because its mechanism is archived off.
ProbCut cutoffs go `18` to `8` on a population too small to read as a trend.

The cost work left every frozen fingerprint untouched, which is the evidence
that separates it from the chess change. The imbalance term moved all eighteen
to a distinct recorded set, production reaching `619,197` nodes, and all
eighteen returned to their cost-head values when the rejected switch was
defaulted off. Production is `668,643` again, identical to accepted MAN-E04's
tree, since the cost work changes no evaluation. The archived-on set is
retained as refutation history in the same way MAN-E05's is.

Throughput is recorded under "Gate outcome" below, from the controlled
`MAN-P01` measurement. The figures originally written here were unbalanced and
taken without an idle check; they are withdrawn rather than corrected in place,
because the method and not only the numbers was wrong. All throughput here is
descriptive; no part of it is a strength claim, and `MAN-E07` alone decides
whether the imbalance term is retained.

## Gate outcome

Cost work: accepted on fingerprint evidence under the behaviour-neutral rule,
with `MAN-P01` throughput. Measured order-balanced on an idle host at an
unchanged fingerprint `668,643`, so nodes are identical and the NPS ratio is
the time ratio. Two independently built instances of the same commit give
`+8.0%` and `+8.9%` median bench NPS and `-7.4%` and `-8.2%` depth-six wall
time, so the claim is `+8` to `+9%`; the spread is codegen, not noise, because
`MAN-P02` found the build is not byte-reproducible. Evaluator throughput
`3,642,567` to `5,410,463` eval/s, `+48.5%`. The `+14.7%` bench figure this ADR previously carried was
unbalanced and taken without an idle check; it overstated the gain at both ends
and is withdrawn.

Imbalance term: **rejected** as `MAN-E07`, H0 accepted after 6,606 games at
`-7.00 +/- 5.54` Elo, LOS 0.66 percent, LLR `-2.97`, zero anomaly. The switch
defaults off and production is exactly the cost head. Its measured cost had
been `-4.6%` evaluator throughput against a `-7.4%` node reduction, but the
verdict is about chess and not cost: the relations are harmful, not merely
expensive. They are refuted rather than unfitted, so ADR-0049's
rescue-by-fitting clause does not reach them.

## Traceability

- `PLAN.md` 5.3.8, `GUIDE.md` current checkpoint.
- `EXPERIMENTS.md` `MAN-E06`.
- `src/eval/hce.zig`, `src/eval/hce_params.zig`, `src/chess/draw.zig`,
  `src/chess/transition.zig`, `src/chess/position.zig`.
- `tests/eval_invariants.zig`, `tests/eval_reference.zig`,
  `tests/state_invariants.zig`, `tests/bench_qualification.zig`.
