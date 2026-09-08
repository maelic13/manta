# Search coverage against the pinned modern reference

Manta's one-thread search compared mechanism by mechanism with Stockfish
`229f6339` (2026-08-19), checked out locally for this audit, and re-audited
against `edb0d9db` (Stockfish 19) on 2026-09-08 after `MAN-S31` was rejected.
Findings 1 to 3 are from the original audit and Findings 4 to 7 from the
re-audit. PLAN 5.4.0 requires a *current* reference here: the pinned pre-NNUE
snapshots are the right study input for a classical evaluator and the wrong one
for asking whether a modern search is complete.

Same contract as [`HCE_COVERAGE.md`](HCE_COVERAGE.md). This is a **coverage map,
not a parity target**. Manta implements every adopted mechanism as original Zig;
reference code, formulas and constants are not copied. Status values are
`present`, `rejected` with its own `MAN-S` evidence, `parked`, and `missing`.

## The finding this audit exists for

**Manta is missing no mechanism family.** Production enables null move,
ProbCut, dynamic LMR, IIR, check and provenance-checked singular extension,
reverse/quiet futility, late-move and SEE pruning, qsearch SEE/delta pruning,
and continuation history at distances two, four and six. Multi-cut, double
extension, dynamic-null scaling, ProbCut-TT, history pruning and capture
futility exist behind the rejected default-off MAN-S20/MAN-S21 umbrellas; they
are covered implementations, not production consumers.

At the Step-5.4.0 audit, branching over depths four to twelve was `2.412`
against the reference's `1.633`. The gap was therefore in **how hard the
existing mechanisms cut**, not in which mechanisms existed. MAN-S28 then fit
ten active continuous consumers jointly and its MAN-S29 bake accepted H1; that
vector is production. The historical branching measurement is not restated as
MAN-S29 behavior without a new prospective measurement.

## Move ordering is not the constraint

Branching in alpha-beta is a joint product of move-ordering quality and pruning
aggression, so a wide tree does not by itself accuse pruning. If ordering were
weak, cutting harder would be actively harmful — the engine would be discarding
moves it had failed to sort. That had to be measured before any further pruning
work, and Manta already instruments it as `fail_high_by_index`.

Over the `manta-search-observation` corpus, 87,730 cutoffs:

| cutoff on move | share |
|---|---:|
| first | `86.45%` |
| second | `8.96%` |
| third | `2.36%` |
| fourth to eighth | `1.86%` |
| later | `0.37%` |

First three moves account for `97.77%`. The deepest case in the corpus, a
depth-ten opening search carrying 78,187 of those cutoffs, sits at `87.3%`
alone, so the aggregate is not an artifact of shallow cases.

Converting the distribution to expected moves searched per cut node gives
`1.270`. A reference ordering at `90%`, `92%` or `95%` first-move cutoffs would
give `1.216`, `1.173` and `1.108`, so Manta does between `4.5%` and `14.7%` more
work per cut node. **The measured branching gap is `49.7%` per ply.** Ordering
can account for a fraction of it and not the bulk, so it is not the binding
constraint and the pruning and reduction hypothesis survives the test that could
have killed it.

Two limits on this. The reference figures are literature values rather than
measurements, because first-move cutoff rate is internal and cannot be read over
UCI. And the corpus is twelve cases, most at depth four; only one is deep. The
conclusion is robust to the range of plausible reference values but the corpus
deserves widening before ordering is dismissed permanently.

## Finding 1 — the reduction surface saturates

`lateMoveReduction` computes `extra = min(depth_band, move_band)` where
`depth_band = (depth - 3) / 3` and `move_band = log2(move_index + 1) - 2`. The
reference derives its reduction from the **product** of a depth term and a move
term, each logarithmic in its argument, where Manta takes the **minimum** of a
linear depth term and a logarithmic move term. Only the shape is recorded here;
the reference's coefficients are deliberately not transcribed, and the table
below reports observed reduction depth rather than any copied expression.

A minimum is bounded by its smaller argument. `move_band` reaches `3` at sixty
moves and never exceeds it, so `extra` is capped at `3` and the whole reduction
surface saturates at four plies no matter how deep the search goes:

| depth / move | Manta | reference, improving | reference, not improving |
|---|---:|---:|---:|
| d8 m16 | `2` | `3` | `4` |
| d12 m20 | `3` | `3` | `5` |
| d16 m20 | `3` | `4` | `6` |
| d20 m40 | `4` | `5` | `7` |
| d28 m30 | `3` | `5` | `8` |
| **maximum over d4-40, m3-60** | **`4`** | **`7`** | **`10`** |

At depth twenty-eight and move thirty Manta reduces three plies where the
reference reduces five or eight. This is the leading hypothesis for the
branching gap and it is a structural property of the formula, not a constant
that tuning can reach.

## Finding 2 — `improving` is consumed in the opposite direction

The reference increases its reduction by roughly a third when the position is
**not** improving. Deteriorating positions get searched *less*, and the signal
is used to cut harder rather than to protect.

`MAN-S18` gave `improving` a vote in Manta's synchronized LMR and was rejected.
Its own observation records `141` shallower against `2,171` deeper adjustments
and node count rising from `755,581` to `772,203`, so in practice the cluster
mostly *protected* moves from reduction and grew the tree by `2.2%`. `MAN-S20`
did the same: another selectivity cluster that raised nodes, from `744,899` to
`761,703`, and lost.

**Two consecutive selectivity clusters made the tree bigger.** Neither had a
branching measurement to check against, because none existed until 5.4.0. The
direction of travel was toward more careful, more protective search when the
measurement says the tree is already `1.48x` too wide per ply.

`MAN-S18` is therefore **not refuted as a concept**. What was refuted is one
bundle in which the dominant effect ran opposite to the reference's use of the
same signal. Re-registering an `improving`-aware reduction that only *deepens*
is a different hypothesis and needs its own gate.

## Finding 3 — aspiration and reduction scaling are one mechanism

The reference reduces less when the current window is wide relative to the
window the root is currently searching, and that root window is re-established
on every aspiration iteration. Without aspiration windows the root window is
simply the full window, the ratio is constant, and window-proportional reduction
scaling cannot exist at all.

`MAN-S02` parked root aspiration as inert on a `0.82%` node reduction. That
verdict was correct *for aspiration alone*, and it is the clearest case in this
ledger of a mechanism judged in isolation whose value is mostly as an input to a
consumer Manta had not built. Aspiration and delta-proportional reduction are
one dependency-complete cluster and should be registered together or not at all.

## Finding 4 — checking moves are an ordinary move class in the reference

This is the finding that explains `MAN-S31`. In the reference's whole main
search, the "this move gives check" fact appears in exactly three places: where
it is computed, where it selects which shallow-pruning branch a move takes, and
where it is handed to the move-making routine. It never touches depth and never
touches the reduction. In-check status likewise never gates the reduction. The
only extension sources in the entire node are singular extension and a negative
extension for a non-singular transposition move.

Manta grants checking moves three compounding privileges instead:

| privilege | Manta | reference |
|---|---|---|
| Check extension | one ply, unconditional, at every checked node | none |
| Late move reduction on checking moves and evasions | excluded by `lateMoveEligible` | reduced like any other move |
| Shallow pruning of checking moves | **every** cause waived | futility waived; static-exchange pruning still applies |

`MAN-S31` withdrew the first and kept the other two. Forcing lines therefore
became shallower without becoming cheaper per node, which is why a `35%` to
`56%` smaller tree produced no strength. The concept is not refuted; the
isolated formulation is. Step 6.5.4 owns the retry because making checking moves
reducible and prunable requires the reduction surface that step builds.

## Finding 5 — pruning consumes the prospective reduced depth, and ordering is why

The reference derives a move's reduction **before** its shallow-pruning tests
and then expresses every one of those tests against the resulting prospective
reduced depth rather than the nominal depth. Late move count, futility margin
and static-exchange margin all read the same reduced quantity, and history
adjusts that quantity rather than adjusting each threshold separately.

Manta computes its shallow-pruning decisions from nominal depth and derives its
reduction afterwards, independently. The two selectivity families therefore
cannot trade against each other: a move is either discarded or searched at full
depth, with no graded middle. Step 6.5.2 measured the consequence directly —
`57%` of legal main candidates discarded outright at depth ten, while only
`3.3%` of the moves that survive are reduced at all.

This ordering is a contract, not an implementation detail, and PLAN 6.5.4
records it as part of that candidate's scope.

## Finding 6 — null-move reduction and verification are one mechanism

Manta reduces the null probe by two plies, three from depth eight, and then
verifies **every** fail-high with a search at that same reduced depth. Step
6.5.2 measured `99.91%` of `37,085` depth-ten verifications confirming their
fail-high, at about `1.1%` of the tree. A shallow probe re-checked by an equally
shallow search cannot disagree with itself.

The reference reduces far more deeply — its base reduction is several times
Manta's and grows with depth — skips verification entirely below a high depth
threshold, and implements the surviving verification as a search with null move
disabled for the following plies rather than a repeat of the same window. The
deep probe is what makes verification meaningful, and the verification is what
makes the deep probe safe.

Deepening the reduction alone removes the safety the present verification
nominally provides; removing the verification alone leaves the expensive
shallow probe in place. PLAN 6.5.5 therefore registers them as one candidate
with two switches.

## Finding 7 — two proof mechanisms Manta simply does not have

**Mate distance pruning.** The reference clamps alpha against the
mated-in-this-ply bound and beta against the mate-in-next-ply bound at every
node, and returns immediately when they cross. Manta clamps neither, which is
why Step 6.5.2 found two proven-mate positions consuming `47.5%` of the
depth-ten corpus. Note that the reference's root-level early exit on a found
mate lives in its time-management block and does not apply to a fixed-depth
search, so the node collapse observed at fixed depth is attributable to the
node-level clamp alone.

**A shallow singular exclusion horizon.** The reference searches its exclusion
probe at roughly half the new depth. Manta searches it two plies below the
launching node, which is why Step 6.5.2 measured `3,009` exclusion searches
converting `9.5%` of attempts into extensions while costing `5.1%` of the tree.

## Mechanism inventory

| Mechanism | Manta |
|---|---|
| Iterative deepening, PVS, TT with bounds and provenance | present |
| Null move, verified, dynamic reduction | present |
| ProbCut, with TT-informed probe | present |
| LMR, dynamic | present — but see Finding 1 |
| Singular extension, TT provenance, multi-cut, double extension | present |
| Internal iterative reduction, cut-expectation aware | present |
| Check extension, depth authority | present |
| Reverse futility, quiet futility, late move pruning, SEE pruning | present |
| History pruning, capture futility | present, default-off under rejected `MAN-S20` |
| Continuation history at distances 2, 4, 6; contextual history | present |
| Qsearch SEE and delta pruning | present |
| Syzygy | present |
| Root aspiration | **parked** `MAN-S02` — reopen only with Finding 3's consumer |
| `improving`-aware reduction | **rejected** `MAN-S18` — see Finding 2 |
| Capture history | rejected `MAN-S16` |
| LMR reply feedback | rejected `MAN-S14` |
| Balanced history gravity | rejected `MAN-S06` |
| Main selectivity synchronization | rejected `MAN-S20` |
| Depth-authority synchronization | parked `MAN-S21`, unresolved budget stop |
| Razoring | parked — changed the WAC.001 forcing line |
| Correction history | **missing** — owned by 5.4.1 |
| Multi-threaded search | missing — owned by Phase 6 |

## How to read the rejections

A large share of this list is rejected **with evidence**, which is maturity
rather than a gap, and reopening a settled question needs a reason beyond the
reference having the mechanism. But `MAN-E05` and `MAN-E07` were reopened by the
5.3 fit on exactly such a reason: the original refutation had tested one
formulation, not the concept.

The same applies here. `MAN-S18` and `MAN-S20` were tested without any branching
instrument, in a direction the instrument now says was wrong. `MAN-S02` was
tested without its consumer. Those are arguments about the *experiment*, not
verdicts overturned by preference, and each still needs its own registered gate
before anything changes.
