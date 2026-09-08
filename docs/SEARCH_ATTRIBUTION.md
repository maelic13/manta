# Whole-tree search attribution

Interpretation corrected on 2026-09-08 under ADR-0068. Measurements below
remain historical observations; PLAN's reworked Phase 6.5 owns current
priorities. Inclusive cost, conversion rates and extension frequency are not
counterfactual savings or strength evidence.

Step-6.5.2 rebaseline of the production search after `MAN-S30`. It answers one
question: **where does Manta's tree actually go, and which mechanism owns the
gap against the sibling engines.** Nothing here is a strength verdict. Node
totals, shares and branching ratios informed the historical priority list.
The reworked PLAN owns current tickets; retained candidates still need a game
gate.

The Step-6.5.0 audit measured the gap in aggregate. This step measures it per
depth, per position and per mechanism, because the aggregate turned out to be
misleading in a way that changes the priorities.

## Conditions

Corpus is the frozen forty-position `tools/bench_positions.epd`, identical to
`engine.bench.positions`. One search thread everywhere. Native ReleaseFast
Manta at production fingerprint `775,451`.

| Role | Binary | Reported id | SHA-256 |
|---|---|---|---|
| Subject | `zig-out/bin/manta.exe` | `Manta 1.0.0` | `73367CDC…47FACBE7` |
| Sibling | `D:\code\rarog\target\release\rarog.exe` | `Rarog 2.3.2` | `C5744AC9…D7EE8FA2` |
| Sibling | `D:\code\basilisk\build\dist\basilisk-v1.10.0-dev-windows-x86_64-pext-pgo.exe` | `Basilisk 1.9.3` | `1034DE95…82072906` |
| Shape reference | `D:\code\stockfish\src\stockfish.exe` | `Stockfish dev-20260707-db91fd16` | `F7C3D427…9181F2B2` |

The Basilisk file name says `v1.10.0-dev` while the binary reports `1.9.3`; the
engine's own `id name` is what is recorded. Stockfish is a search-shape
reference under the same corpus, never an implementation target, and its NNUE
evaluator makes its per-node cost incomparable with the others.

Two independent instruments, because they answer different questions:

- **Cross-engine depth curve** — `tools/branching_profile.ps1` drives each
  engine over plain UCI with a fresh process per depth and `ucinewgame` per
  position. It measures node totals and wall time for a real production binary
  with no observer attached.
- **Internal attribution** — `zig build search-attribution` runs the same corpus
  in process with the diagnostic observer enabled, clearing the table and
  ordering state before every position. Its node counts match the depth curve
  exactly; its wall times do not, because counting costs time. Never quote its
  timings as throughput.

Commands, for reproduction:

```bash
zig build search-attribution -- --min-depth 4 --max-depth 10 --hash 64 --json out.json
```

```powershell
pwsh -NoProfile -File .\tools\branching_profile.ps1 -Engine .\zig-out\bin\manta.exe -MinDepth 4 -MaxDepth 10 -Hash 64
```

## The depth curve

Total nodes over the forty positions at 64 MiB, fresh process per depth.

| depth | Manta | Rarog | Basilisk | Stockfish |
|---:|---:|---:|---:|---:|
| 4 | 149,063 | 62,966 | 56,078 | 15,516 |
| 6 | 782,298 | 273,633 | 240,840 | 37,205 |
| 8 | 4,424,221 | 848,798 | 1,014,712 | 123,348 |
| 10 | 26,778,901 | 2,183,568 | 4,072,440 | 342,460 |
| 11 | 79,180,184 | 3,438,589 | 5,886,488 | 647,184 |
| 12 | 170,853,905 | 5,544,413 | 8,506,949 | 1,211,684 |
| geometric branching, 4→12 | **2.412** | 1.750 | 1.873 | 1.724 |

Depths eleven and twelve ran inside a recorded local cap: all four engines
completed in `3m19s` wall time together, well under the fifteen minutes
budgeted, so no truncation was needed.

Branching is the durable statement. Manta needs about `2.41` times the tree per
extra ply where the siblings need `1.75` to `1.87`; that compounds, and it is
why the absolute gap widens from `2.4x` at depth four to `31x` at depth twelve
against Rarog. Absolute node counts are not comparable across engines because
each counts nodes differently; the ratio between consecutive depths of the same
engine is.

## The aggregate was misleading

Per-position node shares at depth ten expose an extreme concentration.

| position | FEN | Manta | Rarog | Basilisk | Stockfish |
|---|---|---:|---:|---:|---:|
| 6 | `r1bq1r2/pp2n3/4N2k/3pPppP/1b1n2Q1/2N5/PP3PP1/R1B1K2R w KQ g6 0 20` | 8,382,516 | 36 | 119 | 469 |
| 30 | `1Q4bk/3R2pp/p7/3p3P/1p6/1B6/P2q1PP1/6K1 w - - 2 17` | 4,333,385 | 34,552 | 31,904 | 1,957 |
| 27 | `1k2r3/1pp1bpKp/p7/8/2PNr3/1P2P1P1/P4P1P/3R3R b - - 2 9` | 1,516,947 | 132,112 | 76,185 | 21,115 |

Positions 6 and 30 alone are `47.5%` of Manta's entire depth-ten corpus. The
top five are `59.5%`; the bottom twenty together are `13.0%`.

**Both dominating positions are proven mates.** Manta reports `mate 1` on
position 6 and `mate 6` on position 30, and reaches those verdicts early — the
mate-in-one appears in the first iteration — yet keeps searching. Removing just
those two positions changes the corpus ratio against Rarog from `12.3x` to
`6.5x` and against Basilisk from `6.6x` to `3.5x`. The per-position **median**
ratio is `5.4x` against Rarog and `5.2x` against Basilisk, with an interquartile
range of `4.4x`–`11.0x`.

So the Step-6.5.0 aggregate figure of `9–14x` more depth-ten nodes was
substantially a report about two mate positions. The real ordinary-position gap
is closer to `5x`, and it is still large.

## Ranked findings

### 1. Mate distance pruning is missing

Manta clamps no window against the mate band. There is no
`alpha = max(matedIn(ply), alpha)` / `beta = min(mateIn(ply + 1), beta)` pair at
node entry, so a proven mate at the root does not stop the search from proving
worse mates below it, and iterative deepening does not stop when the remaining
depth cannot improve a found mate. Position 6 spends `8.2M` nodes on the
thirty-nine root moves that cannot beat a mate in one; Rarog answers the same
question in `36` nodes.

This is a concentrated mate-tree sink. Ply-dependent mate bounds can exclude
branches unable to improve the incumbent. Finding some mate alone is not proof
that no shorter mate exists; root early completion needs its own proven bound.
The score band is frozen by `SCORE-004` and `SCORE-005`.
It is nevertheless a search change — the tree, the fingerprint and possibly the
reported mate line all move — so it is a playing candidate needing its own 1T
SPRT, not a cleanup. The complete contract now belongs to the reworked
Step 6.5.10, after its design in 6.5.8.

### 2. Late move reduction reaches a narrow population

| depth | main moves searched | LMR probes | probe share | re-search rate |
|---:|---:|---:|---:|---:|
| 6 | 435,844 | 13,520 | 3.10% | 1.90% |
| 8 | 2,667,963 | 97,361 | 3.65% | 1.11% |
| 10 | 16,420,591 | 546,443 | 3.33% | **0.71%** |

Reduction is restricted to quiet, non-checking, non-check-evasion moves from
move index three at depth four or more. Its depth/move-band minimum is scaled
by the accepted extra factor 116, rounded and capped by remaining depth.
`96.7%` of searched main moves do not take this LMR path; of those that do,
`99.3%` do not trigger a full-depth verification. Other depth mechanisms still
exist, so absence of an LMR probe is not proof of unreduced nominal coverage.

A low re-search rate is not a measure of safety or information loss. A missed
refutation can fail low without triggering verification. Depth, move and
prior-pruning eligibility condition this population. Reworked 6.5.10 derives a
shared selective-depth policy and tests its chess outcomes; it must not tune
aggression to an arbitrary target re-search rate.

The complementary fact is that Manta is not gentle overall: `57%` of legal main
candidates at depth ten are pruned outright, `15.8M` of them by late-move count
alone, plus `3.4M` quiet-futility and `2.7M` SEE prunes. Manta makes a binary
decision — discard the move or search it at full depth — where the siblings
have a graded middle.

### 3. Whole-tree charge

Every visited node is charged to the innermost speculative context on its path,
which partitions the tree exactly, and to every enclosing context, which says
what would disappear if a mechanism stopped opening subtrees. Depth ten, 64 MiB:

| charge | exclusive | inclusive | inclusive, mate positions removed |
|---|---:|---:|---:|
| ordinary | 28.4% | 28.4% | 8.7% |
| LMR probe | 50.3% | 54.8% | 60.0% |
| LMR re-search | 4.5% | 9.8% | 17.7% |
| PV re-search | 6.4% | 15.6% | 29.6% |
| null probe | 6.4% | 8.3% | 15.9% |
| null verification | 1.0% | 1.1% | 2.2% |
| singular exclusion | 2.4% | 5.1% | 9.3% |
| ProbCut | 0.6% | 0.9% | 1.8% |

Read the inclusive column as overlapping: a node inside an LMR probe inside a
PV re-search is counted under both. The mate positions inflate `ordinary`
because their cost is full-width root work, which is why the third column
matters.

Nothing here says a mechanism is wasteful by itself — a probe that produces a
cutoff has earned its subtree. The ordinary-position inclusive LMR and PV re-search shares are 17.7% and
29.6%. They overlap, so their sum is not a 47% unique-work share. Use exclusive
charges or an explicitly measured union to quantify distinct work.

### 4. Null verification rarely changes the probe answer

| depth | attempts | fail-highs verified | verifications confirmed |
|---:|---:|---:|---:|
| 8 | 10,444 | 5,431 | 99.89% |
| 9 | 25,479 | 14,114 | 99.88% |
| 10 | 63,875 | 37,085 | **99.91%** |

Mandatory verification costs about `1.1%` of the tree and changes the answer
`34` times out of `37,085` at depth ten. This does not establish redundancy: rare zugzwang-sensitive disagreements may
matter. The real-move verification is distinct from the null probe. Reworked
Step 6.5.11 must derive both probe depth and verification safety; the counter
measures nodes, not CPU time or the value of avoided errors.

Null move itself is healthy: it cuts on `58%` of attempts at depth ten, rising
monotonically from `22.5%` at depth five.

### 5. Transposition pressure is not the constraint

Depth-ten total nodes across the hash sweep:

| engine | 16 MiB | 64 MiB | 256 MiB | change |
|---|---:|---:|---:|---:|
| Manta | 26,949,444 | 26,778,901 | 26,762,725 | **0.70%** |
| Rarog | 2,183,568 | 2,183,568 | 2,183,568 | 0.00% |
| Basilisk | 4,344,961 | 4,072,440 | 4,089,247 | 6.27% |
| Stockfish | 342,460 | 342,460 | 342,460 | 0.00% |

Sixteen times the table changes Manta's tree by well under one percent. The
store outcomes explain why: current-generation evictions at depth ten fall from
`4,007,158` to `9,594` across the sweep while the tree does not move. The gap is search
policy is not explained by capacity pressure on this fresh-position workload.
This does not settle layout/probe CPU cost or replacement behavior with warm
game history. The earlier eight-percent observation used a shared table across
positions; do not extrapolate either reset policy to every future comparison.

Table yield at depth ten, 64 MiB, `26.8M` lookups: `75.6%` miss, `9.1%`
rejected for insufficient depth, `1.5%` rejected on bound, `13.9%` usable. No
lookup was ever rejected for an illegal stored move. Of `14.6M` stores, `80.3%`
filled an empty way, `14.6%` refreshed the same position, `1.0%` were declined
and `4.1%` evicted a current-generation entry.

### 6. Move ordering is not the constraint either

First-move cutoff share rises with depth and reaches `92.5%` at depth ten, up
from the `86.45%` recorded at Step 5.4.0. The transposition move, when
available, is the best move `83.5%` of the time. This weakens a gross cut-node
misordering explanation. It does not evaluate fail-low/PV nodes, omitted moves,
generation cost or the usefulness of ordering evidence to new depth consumers.

### 7. Generation waste persists

Depth ten generates `18.5` moves for every move it searches, and `57%` of
candidates are discarded by shallow pruning after they were generated. The
Step-6.5.1b staged picker removed the abandoned quiet tail at nodes that cut
early; the remaining waste is dominated by nodes that do generate their quiets
and then prune most of them by count. This is a reworked 6.5.5–6.5.7 cost question,
not a tree-size question — the pruned moves cost generation and ranking, not
subtrees.

### 8. Forcing lines are bounded

In-check nodes are `8.9%` of the depth-ten tree and extended nodes `6.4%`;
essentially every extension is the blanket check extension (`1,714,018` of
`1,714,250`). Consecutive in-check runs and consecutive extension runs both cap
at five plies across the corpus, with the overwhelming majority of length one.

These frequencies do not bound the descendant work caused by extensions.
The later S31 ablation changed much more of the tree, but also changed tactical
coverage; neither extension frequency nor short chains prove dispensable work.

### 9. Singular exclusion cost and extension conversion

At depth ten, `3,009` exclusion searches produce `285` extensions — a `9.5%`
conversion — and cost `5.1%` of the tree inclusively. The exclusion search runs
at `depth - 2`, only two plies shallower than the node that launched it, which
is why so few searches cost so much. Similar aggregate extension counts do not establish identical singular
choices or useful tactical coverage. MAN-S33 later changed this horizon and
was stopped inconclusive; only a distinct accepted-context proposal may reopen it.

## What this step decides

The measurements identify questions, not a guaranteed optimization order.
Mate-distance work explains a concentrated tail; LMR eligibility and depth
deserve review; proof searches need cost-versus-decision-quality assessment;
generation and per-node cost remain an independent delivery objective.

Low re-search frequency is not a defect by itself. A node's extension flag
does not bound all descendant work attributable to that extension. The hash
sweep does not retire TT layout/replacement cost, and first-move cutoffs do not
retire ordering quality. PLAN 6.5.4–6.5.15 and ADR-0068 replace the former
priority list with board-backbone work followed by a shared search-depth policy.

## Artifacts

`zig-out/attribution/` holds the raw JSON and text for every run above:
`manta-d4-10-h{16,64,256}.{json,txt}` for the internal sweep and
`branching-{manta,rarog,basilisk,stockfish}-h64{,-deep,-d10}.json` plus the
16 and 256 MiB depth-ten points for the cross-engine curve. These are local
diagnostic assets and are not committed.
