# ADR-0071: Coordinated selective-search core

## Status

Accepted for implementation by maintainer decision on 2026-09-12, against
production head `596159e` (MAN-S35, fingerprint `642,336`). It redirects the
remainder of Phase 6.5 toward one measurable outcome: a large registered
strength gain from the search tree, delivered as one coordinated package
rather than a sequence of isolated mechanisms.

It supersedes ADR-0070's candidate boundaries for 10.2 to 10.4 and its
per-consumer eligibility envelope (quiet-only LMR, nonnegative one-ply-floored
reductions, always-verified null move, shallow ceiling of three plies), and
ADR-0068's step sequence for 6.5.10 to 6.5.15. It keeps ADR-0070's fact
interfaces, authority and certificate rules, scope propagation and legal edge
cases: they describe how evidence is labelled, not how much of the tree is
searched. It withdraws the "do not revive rejected umbrellas" rule for the
components named below. Those umbrellas were rejected as isolated changes on a
head that lacked the rest of the system; that is not evidence against the
system. Their archived switches stay off; the concepts are re-derived here.

## Why one package

The search-shape reference is the final pre-NNUE Stockfish pinned in
`config/eval-reference.json` (commit `9587eeeb`, built with the recorded
`zig c++` command, identity `Stockfish 160826 64 POPCNT`). It is the strongest
engine with a classical evaluator, so it is the right yardstick for a search
that will keep a classical evaluator until Phase 7. The maintainer's own
engines are secondary data points only. Measured on this workstation at head
`596159e`, forty-position corpus, 64 MiB, one thread, fresh process per depth
(`tools/branching_profile.ps1`):

| Quantity | Manta `596159e` | Classical Stockfish `9587eeeb` |
|---|---:|---:|
| Geometric branching factor, depths 4 to 12 | `2.225` | `1.88` |
| Nodes at depth 12 | `82,249,155` | `2,598,338` |
| Elapsed at depth 12, this host | `57.5 s` | `1.3 s` |

Nominal depths are not equal chess coverage across engines, so the node and
time ratios at one depth overstate the gap. The branching factor is the
durable statement: Manta needs `2.2` times the tree per extra ply where the
reference needs `1.9`, and that compounds into several plies at equal time,
which is the order of the strength gap the maintainer wants closed.

Every previous attempt at this lever in Manta was one mechanism gated alone:
MAN-S18 LMR votes, MAN-S20 history pruning and capture futility, MAN-S21 depth
authority, MAN-S31 check extension, MAN-S33 singular horizon. Each lost or was
inconclusive, and the plan then froze rules that keep the tree wide: quiet-only
LMR from the fourth move at depth four, shallow pruning to depth three only,
fixed two-ply always-verified null move, positive-saturating main history
with no penalties. Modern selectivity works as a system: reductions must be
large and history-aware, pruning must use the depth a move will actually be
searched at, forward proofs must trust their own margins, and history must be
informative enough to carry those decisions. Testing the parts one at a time
on a head that lacks the others measures the wrong thing.

## Decision

Implement candidate `MAN-S36`, the coordinated selective-search core, behind
one compile-time umbrella `-Dselective-core` (`features.selective_core`),
default off until its registered gate accepts H1. Six component switches
exist only for ablation diagnosis and are never gated separately:
`core_history`, `core_lmr`, `core_move_pruning`, `core_node_pruning`,
`core_aspiration` and `core_qs_checks` (added by the 2026-09-12 review
resolution below). With the umbrella off, every component is off and the tree
reproduces `642,336` exactly, in default and observation-enabled builds.

All constants below are Manta's seeds in Manta's units. They are order-of-
magnitude choices with a stated rationale, to be fitted in Step 6.5.11 once the
mechanisms freeze. None is copied from another engine.

### Units and facts

Depth is plies in `u16` with saturating arithmetic; scores are centipawns at
`score.units_per_pawn = 100`; history is `i16` in `[-16384, 16384]`
(`ordering.State.history_limit`); reduction arithmetic is `i32` in 1024ths of
a ply and is converted to plies once at dispatch with floor division and a
clamp. Facts come from existing producers:

| Fact | Producer |
|---|---|
| `depth` | active node depth after check extension and IIR |
| `pv_node`, `cut_node` | `expectation.isPrincipal()`, `expectation == .cut` |
| `improving`, `pruning_eval`, `static known` | `ShallowEvidence` (raw eval versus ply minus two; false when unknown or in check) |
| TT move present | `table_evidence.chess_move != null` |
| `search_index`, `actually_searched_count` | move loop ordinals, selected and actually recursed |
| move class | quiet, promotion, capture with picker source `good_tactical` (SEE at least zero) or `bad_tactical` |
| `gives_check` | child check state after `make`; unknown before make |
| `stat` | the quiet-history value the picker ranks with, `main + weighted reply + weighted continuation`, clamped to `[-16384, 16384]`; captured at selection for delayed quiets and computed on demand for TT or killer sourced quiets |
| `singular` | the node's singular move and its admitted plies |

### A. Informative history (`core_history`)

`historyBonus(depth) = min(2048, 150 * depth - 60)`, so a depth-one outcome
moves an entry by about 90 and a depth-fourteen outcome saturates at 2048.
The malus has the same magnitude. Rationale: the accepted `depth^2` bonus
never approaches the 16384 range, so relative history is uninformative for
any consumer other than coarse ranking.

- Main history uses the bounded gravity update for both directions: bonus to
  the exact or cutoff winner, malus to every quiet actually searched before it
  at that node. The legacy positive-saturating add is retired under the core.
  The searched-quiet list is collected at every node, not only when a reply
  context exists.
- Reply and continuation tables keep their producers and admission; they read
  the new bonus through the shared function.
- Killers, ranking composition and weights (`116`/`118`) are unchanged.
  Capture history stays off.

### B. Full-coverage reduction surface (`core_lmr`)

Eligible: `depth >= 2`, `search_index >= 2`, node not in check, move does not
give check, move is not the singular move, and the move is a non-promotion
quiet or a `bad_tactical` capture. Promotions, good captures and the first two
selected moves are never reduced. Root moves are eligible with relief.

Reduction in 1024ths, `r`:

```
T[d][m] = 1024 * (0.625 + ln(d) * ln(m) / 2.4)     d, m in 1..63, clamped
r  = T[min(depth,63)][min(search_index,63)]
r += pv_node ? -1024 : +1024
r -= improving ? 1024 : 0
r += cut_node ? 768 : 0
r += (tt move present and search_index >= 4) ? 512 : 0
r -= stat * 1024 / 8192                           (about +/- 2 plies)
r -= ply == 0 ? 1024 : 0
reduction = clamp(floor(r / 1024), 0, new_depth - 1)     (no reduction when new_depth == 0)
```

`new_depth = depth - 1 + singular plies`. The table is generated at compile
time with `@log` on `f64`. A reduced probe keeps at least one main-search ply
(amended 2026-09-12, third review): a zero-depth probe hands the opponent a
quiescence in which our own quiet mate threats are invisible, because F
generates checks only for the side to move at the first quiescence ply.
Rationale per term: later moves at deeper nodes are less likely to matter
(log-log table); PV nodes carry the answer and cut nodes are expected to be
refuted by one move; a present TT move that already failed means late
alternatives are weaker; history is the only per-move evidence about quiet
quality; the root chooses the played move.

Dispatch is unchanged in shape: a reduced null-window probe; if it scores above
alpha and `reduction > 0`, a null-window re-search at `new_depth`; at a PV node
a result inside the window then gets the full-window re-search. A zero
reduction is the ordinary scout and never triggers a verification. Reduced
fail-lows keep `reduced_search` provenance and the existing reduced TT depth.
The archived `dynamic_lmr` band surface, `lmr_desaturation`,
`lmr_synchronization` votes and `history_lmr` guard are not consulted under
the core.

### C. Prospective-depth move pruning (`core_move_pruning`)

Prospective depth `pd = max(0, new_depth - reduction_estimate)`, where the
estimate evaluates the surface in B before `make` with `gives_check = false`.
The estimate and the applied reduction differ only for checking moves, which
are exempt from pruning after `make`.

Gate for every rule: `!pv_node`, node not in check, `actually_searched_count
>= 1`, static evaluation known, ordinary alpha and beta, side to move has
non-pawn material. Tests run before `make`; omission commits after `make`
only if the move does not give check, exactly as today.

Quiet non-promotion moves:

1. **Late-move count.** `pd <= 8` and `search_index >= lmp_count` with
   `lmp_count = max(2, late_move_base + late_move_depth_scale * pd * pd / 4 +
   (improving ? late_move_improving_bonus : 0))`, MAN-S29 parameters
   `4 / 3 / 4`, giving about `7, 10, 16, 22, 31, 40, 52` for `pd = 2..8`.
   When it first triggers at a node, the picker skips the remaining quiets
   without making them, **except direct quiet checks** (amended 2026-09-12,
   third review): the node computes its direct-check squares once, per piece
   type from the enemy king with the mover's origin removed, exactly as F's
   generator does, and a quiet whose destination is in that set is still made
   and searched. Discovered checks are not recognised and may be skipped. Bad
   captures are still emitted.
2. **Futility.** `pd <= 8` and
   `pruning_eval + quiet_futility_unit * (pd + 1) + shallowConfidenceBonus(improving) <= alpha`.
3. **History.** `pd <= 6` and `stat < -4000 * pd`.

Captures (non-promotion): `pd <= 8` and SEE below `max(-1000, -see_pruning_unit * pd)`.

Every omission sets the node's omitted-siblings fact. **TT authority under the
core:** a fail-low with omitted siblings is stored as an ordinary upper bound
at nominal depth. Alpha-beta exactness is defined within the engine's
selective policy, and downgrading such entries to reduced provenance made the
table refuse most non-PV upper bounds. ADR-0070's certificate still records
the omission for diagnostics; it no longer changes storage.

### D. Node-level forward proofs (`core_node_pruning`)

Gate: `!pv_node`, node not in check, not an exclusion node, static evaluation
known, ordinary beta, non-pawn material.

1. **Reverse futility.** `depth <= 8` and
   `pruning_eval - (150 + (improving ? 0 : 60)) * depth >= beta` returns the
   existing speculative lower bound at beta. Amended 2026-09-12, third review:
   the first seed reused the depth-one fitted margin of 68 plus 50 per ply,
   and Manta's HCE swings by more than 500 for an attacked queen, so that
   margin let a static claim override a mate in one at depth 3.
3. **Razoring.** `depth == 1`, ordinary alpha, and `pruning_eval + 300 <= alpha`
   returns the quiescence result through the existing parked razoring path.
   Amended 2026-09-12, third review: razoring at depth 2 and 3 replaces a
   main-search ply in which the razored side's own quiet mate threats would
   be visible with a quiescence in which they are not.
2. **Null move.** `depth >= 3`, not directly after a null move,
   `pruning_eval >= beta`; `R = 3 + depth / 4 + min(3, (pruning_eval - beta) / 200)`;
   probe the child at `depth - 1 - R` (saturating to a quiescence probe). A
   fail-high at `depth < 10` is a cutoff at beta with `null_move` provenance.
   At `depth >= 10` the existing same-node verification at `depth - R` with
   null disabled decides. Mate-range null scores are clamped to beta.
4. **Internal iterative reduction.** `depth >= 4` and no legal TT move, at
   every node type, reduces the active depth by one ply. The PV-only rule is
   retired under the core.

ProbCut (`depth >= 5`, margin `103`, reduction three), singular extension,
check extension and quiescence are unchanged in this package.

### E. Root aspiration (`core_aspiration`)

From iteration depth 4 onward, when the previous completed iteration returned
an exact ordinary score `s`: `delta = 20 + |s| / 32`, window
`[s - delta, s + delta]` clamped to the full band. A fail-low lowers alpha by
`delta`; a fail-high raises beta by `delta`; after each failure
`delta = delta + delta / 2 + 5`; after four failures on one side that side
opens to the full bound. Only an exact attempt commits the iteration, root
evidence is reset per attempt, and no partial attempt reaches time or UCI
publication. Mate or tablebase previous scores use the full window. The
archived MAN-R02 `features.aspiration` stays off and `SCORE-029` describes it
unchanged.

### F. Quiet checks in the first quiescence ply (`core_qs_checks`)

Added by the review resolution below. At a non-check quiescence node entered
directly from the main search (quiescence ply zero: the depth-zero dispatch,
razoring and ProbCut verification entries), after the tactical partition is
generated and only when stand-pat did not already cut, generate the legal
**direct** quiet checks: non-capture, non-promotion moves whose destination
attacks the enemy king with the mover's origin removed from the occupancy.
Knights, bishops, rooks and queens use the corresponding attack set from the
king square; pawn single and double pushes use the squares from which a pawn
of the side to move attacks the king; king moves, castling and discovered
checks are not generated. This is a subset, not a partition: the MAN-S34
terminal witness keeps its own rule, except that a non-empty check set is
itself a legal-move witness.

Search each generated check only if its destination is not a losing square,
meaning the static exchange on the destination with zero initial gain and the
mover as first occupant is at least zero. Manta's `see.atLeast` returned
`threshold <= 0` for every quiet move without reading the board, so the
review of 2026-09-12 extends it: a non-capture, non-promotion, non-castling
move runs the existing exchange sequence from its destination with the mover's
origin removed from the occupancy. Capture and promotion paths are unchanged
by construction, no umbrella-off consumer prices a quiet move, and the board
benchmark's threshold-SEE cell prices captures only, so the accepted tree and
the frozen board workload are untouched. Checks are searched without delta
pruning, in the picker's ordinary quiet position (after the TT move, good
tacticals and killers, before bad tacticals). The checked child is an in-check quiescence node at ply one, which
already generates complete evasions and has no stand-pat; checks are never
generated below quiescence ply zero, so the extension is bounded by one ply.
Storage, provenance, stand-pat, SEE and delta rules for tactical moves are
unchanged, and the umbrella-off quiescence is exactly MAN-S34.

Rationale: the core's count-based quiet skip, its unverified null-move cutoffs
below depth 10 and its zero-depth probes all assume that a mate threat by a
quiet move remains visible one ply later. In a tactical-only quiescence it is
invisible, and the review found the whole core blind to WAC.001's mate in two
at every depth through nine while the classical reference finds it at depth
five with exactly this relation in place.

### Excluded from the package

Capture history, correction history, singular and check-extension policy,
ProbCut changes, upcoming-repetition bounds, quiet SEE pruning, TT format or
replacement, quiescence, SMP, time management and build optimization. They are
Step 6.5.12 follow-ons on the accepted core.

## Invariants and tests

- Legal PV and best move, terminal and draw precedence, mate-distance
  semantics, tablebase authority and cancellation restoration are unchanged.
- Nothing is reduced in check, when giving check, for promotions or for the
  first two selected moves, and a reduced probe keeps at least one main-search
  ply. No per-move omission test (futility, history, SEE) omits a move that
  gives check, the late-move-count skip keeps direct quiet checks, and
  nothing is omitted at the root, before one move is actually searched, or
  under decisive windows. Component F keeps a mate threat by the side to move
  visible at the first quiescence ply; it does not cover the side not to move,
  which is why the probe floor and the skip exemption exist.
- Null verification subtrees cannot null-prune at their root; exclusion
  searches keep today's behavior.
- Off arm: `642,336`, identical PV and results, both build arms. Each
  component switch compiles in both states.
- Canaries: mate in one at depth one, the hanging-queen capture, KQK and
  KBNK positive, WAC.001 `g3g6` at depth 5 in the full core arm. Depth 5 is
  anchored to the classical reference, which finds the move exactly there;
  the off arm's depth-3 expectation is a property of the unpruned tree and is
  not required of the core. A changed canary is recorded with its cause, never
  silently re-blessed or deleted.
- Focused properties for the new formulas: table monotonicity in both
  arguments, clamp bounds, sign of each adjustment, `lmp_count` monotonicity,
  prospective depth never exceeding `new_depth`, aspiration termination.

## Diagnostics before games and refutation

On this workstation, forty positions, 64 MiB, fresh process per depth, core on
versus core off:

| Diagnostic | Baseline | Required before review |
|---|---:|---|
| Geometric branching, depths 4 to 12 | `2.225` (reference `1.88`) | at most `1.95` |
| Nodes at depth 12 | `82.2 M` | at most `25 M` |
| NPS relative to baseline | `1.00` | at least `0.85` |
| Ordinary and mate cohorts | | reported separately, both improving |
| Local diagnostic match, 1T `3+0.03`, 500 fixed games | | at least `+80` Elo |

The local match is a design diagnostic run by the implementing agent on this
workstation; it authorizes nothing and is not the registered gate. Below
`+30` Elo the package is not registered: ablate by component switch, in the
order history, node pruning, move pruning, reduction surface, for at most one
diagnostic cycle before re-planning. Between `+30` and `+80` the review
decides. The registered gate is one 1T SPRT on the designated host under the
unchanged trusted harness. H0 or a cap refutes the package as a whole; the
ablation order above then applies once before any re-plan.

Node savings, branching factor and local matches are diagnostics. Only the
registered SPRT promotes.

## Review resolution after ticket E, 2026-09-12

Opus stopped at ticket E because the core arm answered WAC.001 with `f6h5` at
depth 5 and localised the failure to `core_move_pruning` and
`core_node_pruning` independently. The review measured the position on the
workspace host, Hash 64 MiB, one thread:

| Engine and arm | First depth answering `g3g6` |
|---|---|
| Classical Stockfish `9587eeeb` | 5 (`mate 3`; `f6e8` at 3, `f6h5` at 4) |
| Manta `596159e`, umbrella off | 3 (`mate 2`) |
| Manta core arm with tickets A to E | never through depth 9 (`cp 26`, `f6h5`) |

A mate in two that stays invisible at depth nine is a missing relation, not a
strict canary. The position is `1.Qg6` with `Qh7#` and `Nxg6#` behind it, and
both mating moves are quiet or checking moves whose refutation the core never
reaches: after `1.Qg6 <defence>` the count-based skip drops the late quiet
`Qh7#` unmade, and at the defender's node the unverified null probe descends
straight into a quiescence that generates no quiet checks, so "pass" looks
safe and the sacrifice fails low. The off arm survives only because it prunes
almost nothing; the classical reference survives because its first quiescence
ply generates quiet checks. Decisions:

1. **Component F is added** as above. Neither the SEE floor, the reverse
   futility depth nor the null policy is changed: Opus's capture hypothesis
   does not apply (the sacrifice is a quiet move), and ADR-0027's "refutation"
   of wider reverse futility was this same canary with no games, caused by the
   same missing relation.
2. **Late-move-count skip may drop quiet checks** by construction; the
   invariant list is amended and F is the safety net. Per-move tests keep the
   post-make check exemption.
3. **IIR** keeps the root, in-check and exclusion exclusions; "every node type"
   means every expectation.
4. Opus's recorded decisions stand: component accessors on `Features`, the
   bonus formula over its prose, a dedicated searched-quiet list for main
   history, the one-sided null mate clamp and the `history` prune cause.
5. **WAC.001 `g3g6` at depth 5** is required of the full core arm and is
   re-anchored to the classical reference; the off arm keeps depth 3.

Ticket E is accepted for commit as implemented; the canary moves to the new
ticket E2, which implements F and must restore the depth-5 answer in the
complete core arm before tickets F and G run.

**Second stop, quiet-move SEE.** Opus found and demonstrated that
`see.atLeast` ignores the board for quiet moves, so F's filter was a no-op as
written. Decision: the faithful reading, a real quiet-move exchange path in
`src/chess/see.zig`, which the classical reference also applies to its
quiescence checks. The cheaper pawn-attack predicate would be a different rule
and dropping the filter spends nodes on spite checks. `src/chess/see.zig` is
added to the ticket's files for this one change; the differential SEE
properties extend to quiet moves (bounds, monotonicity in the threshold and
the floor of minus the mover's value), and the off-arm fingerprint proves the
accepted tree is untouched.

## Third review, 2026-09-12: the traced failure

With F in place the core arm still answered `f6h5`, and F alone was correct, so
the review traced a scratch build of two component arms on
`go depth 5 searchmoves f6h5 g3g6`, printing every decision at plies one and
two. The first root move scores `-206`, so the black node after `Qg6` runs in
the window `[205, 206]` and must return at least `206` for the sacrifice to
fail.

- **Move-pruning arm.** After `1.Qg6 Nxe5` the white node at depth 3 has
  static eval `-838`. It searched `dxe5`, futility-pruned three king moves,
  and on the fourth quiet (`a2a3`) the late-move count triggered and the
  picker skipped every remaining quiet unmade, including `Qh7#`. Only the bad
  captures `Qxh6+` and `Qxg7+` were then searched. White returned `-206`,
  black's `Nxe5` scored `206`, and the node failed high on its first move.
  The per-move check exemption never ran because the move was never made.
- **Node-pruning arm.** The black node after `Qg6` has static eval `+570`,
  the HCE pricing the queen attacked by a pawn. Internal iterative reduction
  took it from depth 4 to 3 because its table entries came from cutoffs with
  no move, and reverse futility then cut with `570 - (68 + 50) * 3 = 216 >=
  206`. A static claim overrode a mate in one.

Both are design defects of the seeds, not properties of the canary. The three
amendments above follow: the count skip keeps direct quiet checks, reverse
futility margins scale with Manta's own evaluation swings and razoring returns
to depth one, and reduced probes keep one main-search ply so the side not to
move cannot lose its quiet mate threats in a quiescence that generates no
checks for it. The classical reference has the last two properties; the first
is Manta's answer to an exemption the reference does not need because its
killers and countermoves usually surface the check first. The traces are kept
in the session scratchpad and summarised in PLAN.
