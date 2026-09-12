# Search coverage against the pinned modern reference

Current interpretation: 2026-09-09, superseding the earlier causal claims and
open-step assignments. Modern Stockfish search at
`edb0d9db6731067ec50ce619ff372b463bc4dd5d` is the structural reference
(inspected local `src/search.cpp`); earlier audits used `229f6339`.
Do not silently change that pin. Classical evaluator coverage continues to use
its separate pre-NNUE pin.

Manta may reimplement modern search structure, features and their relationships
as original Zig. Coverage maturity is a design objective; copied constants,
NNUE-dependent confidence scales and trace convergence are not objectives.
Every changed producer and consumer must have a Manta-native chess rationale.
Reference presence suggests a hypothesis, not a promotion verdict.

## Current production and missing consumers

Production is MAN-E19 HCE, MAN-S29 fitted search, MAN-T05 clock, MAN-S30
live-history staging and accepted MAN-S34 exact qsearch generation,
deterministic depth-six fingerprint `775,451`.
A disabled implementation is not an active feature. A rejected formulation is
not a proof that its entire concept can never help, nor permission to retry.

| Mechanism | Current Manta status | Reworked owner / interaction |
|---|---|---|
| Iterative deepening, PVS, completed root authority | Present | Preserve through 6.5.8–6.5.10; root time/UCI consumes only final completed iterations |
| Adaptive aspiration with a window-aware search consumer | Missing in production; isolated MAN-R02 ended at cap | 6.5.10 only with explicit root/current window evidence and retry authority |
| Mate-distance window pruning | `SCORE-033` default-off complete non-root window clip; MAN-S32's crossing-only arm removed | Implemented in 6.5.10.1 and awaiting its own registered 1T SPRT; the corpus saving is concentrated in the two mate positions and is not ordinary-position strength |
| Upcoming-repetition bound pruning | Missing; current draw handling recognizes an already reached repetition | 6.5.11 derives a legal move/history witness for main/qsearch; possible draw is not an exact universal TT score |
| TT authenticated score/depth/bound and raw-eval reuse | Present; richer confidence consumption is partial | 6.5.8–6.5.10 own provenance/depth consumers; 6.5.13 owns measured storage/cache cost |
| Internal iterative reduction | Present; contextual extension of its policy is partial/off | Shared depth contract in 6.5.10 and proof review in 6.5.11 |
| Live staged TT/tactical/quiet ordering | MAN-S30 accepted | Retain delayed live ranking; board/qsearch work in 6.5.5–6.5.7, shared evidence in 6.5.9–6.5.10 |
| Main, reply and continuation history | Present, including distances 2/4/6 | Reliable outcome learning and common ordering/reduction scales in 6.5.9–6.5.10 |
| Capture history | MAN-S16 rejected/off | Reopen only for a distinct populated relation and coupled consumers, not the archived table alone |
| Low-ply/countermove/static-eval ordering feedback | Missing or unproven beyond existing evidence | Conditional 6.5.9 review; add only non-redundant information with bounded memory |
| Contextual LMR across node/move classes | Narrow production eligibility; MAN-S18 contextual vote layer rejected/off | 6.5.10 replaces one shared depth policy, not independent aggressive switches |
| LMP, reverse/quiet futility and SEE pruning | Present; prospective-depth and richer evidence coupling partial | 6.5.10 consumes the same move-depth decision as LMR and extensions |
| History pruning / capture futility / ProbCut-TT | Implemented under rejected MAN-S20, off | Derive distinct consumers in 6.5.10–6.5.11 only after changed evidence; no umbrella activation |
| Null move with mandatory verification | Present, fixed two-ply reduction | 6.5.11 derives reduction and verification together, respecting zugzwang and real-move verification |
| ProbCut | Present | 6.5.11 coordinates tactical ordering, qsearch and typed TT proof reuse |
| Check extension and singular extension | Present | 6.5.10 shared forcing-depth budget; 6.5.11 singular proof review on accepted context |
| Richer singular/multi-cut/depth authority | MAN-S21 unresolved at cap, off | No blanket revival; individual relations require 6.5.8 contract and new evidence |
| Half-depth singular exclusion | MAN-S33 stopped inconclusive, off | No same-head retry; changed-context review only in 6.5.11 |
| Verified razoring | Parked implementation | 6.5.11 conditional qsearch-verified shallow proof, with tactical/draw safeguards |
| Qsearch SEE/delta and complete evasions | Present; MAN-S34 accepted exact tactical-only non-check generation plus complete terminal witness | 6.5.7 closed; later consumers preserve its ordering, legality and stand-pat authority |
| Correction history | MAN-S25 rejected/off, not an unimplemented Phase-5 task | 6.5.12 conditional reliable HCE-error producer and coherent search consumers |
| Syzygy, SMP, time/UCI | Present and qualified in prior phases | Preserve authority; no new SMP/NNUE/clock optimization inferred from this phase |

This is not a claim that every listed absent family should be enabled. The
deliverable is a compatible, efficient search that meets PLAN's elapsed and
strength gates, not a count of enabled features.

## Verified implementation differences and implications

### Step 6.5.8 design closure

[ADR-0070](adr/0070-shared-search-evidence-and-depth.md) freezes Manta's fact
interfaces, shared depth pipeline, eligibility/authority matrix, edge cases
and candidate membership. Step 6.5.9 is behavior-neutral; changing consumers
starts only in separately approved 6.5.10 tickets. Complete mate windows are
independent; the initial depth core couples existing pruning and reduction
without new ranking/feedback. Window-aware aspiration is a later paired
producer/consumer candidate, not a repeat of isolated MAN-R02.

The modern reference was rechecked at the pin above; `src/search.cpp` SHA-256
is `A934524DD2F386EC38CDF95B7B2E41CECDC85C9B17E12C0668621E6AE16BE28A`.
The following are source relationships, not copied policy or numerical targets:

| Pinned source area | Relationship adopted or deliberately constrained |
|---|---|
| Main search, lines 737–810 | Upcoming repetition is distinct from reached draw; mate windows precede ordinary continuation. Manta requires explicit history-local authority. |
| Main search, lines 974–1119 | Static facts, null verification, IIR and ProbCut have ordered dependencies. Manta keeps separate producer/horizon certificates and packages. |
| Move loop, lines 1140–1426 | Prospective reduction participates in shallow pruning; singular and checking depth affect subsequent dispatch. Manta uses one finalized plan and mandatory fixed planned verification, not the reference's adaptive verification horizon. |
| Outcome/store and qsearch, lines 1554–1874 | Feedback follows searched outcomes; qsearch has distinct terminal/static/tactical authority. Preserve accepted MAN-S34 generation rather than port a picker. |

Current Manta source audit adds three implementation cautions: the move-loop
`searched_move_count` includes moves later omitted; TT records have no independent
PV-origin bit; and continuation distances 2/4/6 share one table. Therefore 9 must
not silently change the legacy ordinal, invent PV confidence from exact bounds,
or interpret three lookups as independent support. Paired outcome/support stays
disabled until a distinct consumer is qualified. Neither this design nor the
positive MAN-S34 strength result closes the board or depth-13 performance target.

### Step 6.5.9 implementation map — accepted

The behavior-neutral substrate is implemented, reviewed and closed. Its
default and observation-enabled builds reproduce fingerprint `775451`; neither
configuration changes a search consumer. Actual ownership is:

| Interface | Producer / storage | Current consumer |
|---|---|---|
| `StaticFacts` | `baseline.zig:shallowEvidence` plus uninterrupted stack context | Enabled diagnostic snapshot/count only; existing pruning still reads `ShallowEvidence` |
| `TtFacts` | `baseline.zig:probeTable`, retaining stored producer, generation/freshness and unknown PV origin | Enabled diagnostic snapshot/count only; existing TT predicates are unchanged |
| `WindowFacts` | Every main/qsearch invocation; root reference width is frozen from the first finite aspiration attempt | Enabled diagnostic snapshot/count only; MAN-R02 remains off |
| `MoveFacts` | Made legal main/qsearch candidate, including EP victim, promoted result, check/evasion and both ordinals | Enabled diagnostic snapshot/count only |
| `HistoryFacts` | Live worker-local main/reply/shared-continuation values and exact keys, captured at an explicit `ranking` point when a quiet stage is ranked and again at each selected move's `depth` decision, with optional paired shadows | Enabled diagnostic snapshot/count only; no ranking consumer |
| `NodeDepthPlan` / `MoveDepthPlan` | Existing check/IIR and current shallow/LMR/PVS/qsearch dispatch decisions | Enabled diagnostic snapshot/count only; no shared-depth consumer yet |
| `SearchOutcome` | Completed main/qsearch return with route, restrictive scope, actually searched horizon, verification, established producer, omitted-sibling and probe-only-sibling facts. The returned bound selects the winner's certificate for exact/cutoff results and the aggregate for fail-lows; scope and omission stay aggregated | Enabled diagnostic snapshot/count only; ordinary publication remains unchanged |
| `OutcomeSupportCell` | Completed non-root ordinary quiet exact/cutoff update packet under existing main/reply/shared-continuation keys; winner and alternatives each require an ordinary main entry route and a non-reduced, unrestricted, fully searched certificate | Bounded shadow table only; no ordering, pruning, LMR, TT or feedback consumer |

The selector `-Dsearch-evidence-observation=true` compiles bounded worker-local
observation storage; false is the default and leaves a zero-byte state. Hash
collisions are reported as dropped samples after bounded probing and never
merged. Value/support clear together at the start of their owning search run;
support is lifetime admitted-update count for that run, not confidence or
recency. The first GPT-6 Astra High review found scope, horizon, admission and
missing-adapter defects. The second review found five remaining ones: shadow
admission still accepted unchecked and reduced-probe evidence, restrictive
scope and `history_local` draw scope were lost on return, reduced-only and
null-verification results reported nominal rather than actual horizon, qsearch
outcomes hid SEE/delta omissions and the stored TT producer, and ranking-time
history was never observed. The third review accepted the authority and
lifetime boundaries with no evidence leak and blocked closure on certificate
labeling plus one implicit decision, now recorded in ADR-0070 together with its
measured admission profile: an exact or cutoff result is certified by its
winning move, a fail-low by the conservative aggregate, and a probe-only sibling
is reported as its own fact rather than by shortening the winner's horizon. That
correction does not make the paired relation depth-stratified; the accepted
producer rule is the dominant admission gate, so 6.5.10 must not expect a
depth-balanced sample. All three bounded repairs pass their functional and
deterministic parity gates, and the fourth Astra review accepted the authority
and lifetime boundaries, so 6.5.9 is closed. A 6.5.10 consumer still needs its
own approval, and inherits the frozen contract and this admission profile
rather than any permission from 6.5.9.

### Reduction and pruning are a coordinated depth decision

Manta `src/search/baseline.zig:lateMoveEligible` currently limits ordinary LMR
to depth >= 4, move index >= 3, quiet moves, non-check nodes and non-checking
moves. The base derives `min(depth_band, move_band)`, then applies the accepted
MAN-S29 extra scale (116), rounding and a remaining-depth cap. Its behavior
must be derived with active parameters, not an old unscaled table.
A move-band cap at a fixed ordinal is not a universal four-ply maximum.

The pinned reference derives prospective reduction before shallow move pruning
and later adjusts/selects actual probe and re-search depth using move/node
evidence. Manta should adopt a coherent evidence/depth structure, not its
numerical reduction surface or NNUE-calibrated margins. Checking moves and
evasions require distinct legality and forcing safeguards: broader reduction
eligibility is not permission to prune all evasions.

The observed 3.3% reduced-move share and 0.71% re-search rate identify a narrow
active population. They do not measure false-negative tactical omissions or
prove a safe amount of extra reduction. Sampling is conditional on previous
pruning, depth, node and move eligibility; report those denominators.

### Ordering is not exonerated by first-move cutoffs

The earlier observation reported 86.45% first-move cutoffs; the later depth-ten
attribution reported 92.5% in its population. These are useful conditional
cut-node statistics, not a complete ordering-quality measure. They omit
fail-low nodes, PV competition, unsearched/pruned moves, generation cost and
the quality of shared history evidence. Preserve the successful MAN-S30
staging while assessing how ordering supports the new depth consumers.

### Null verification is not a repeated null search

Production `main_selectivity_sync=false` selects fixed reduction two.
The probe searches after a null move at `depth - 1 - reduction`; verification
searches the restored original position at `depth - reduction` with null
disabled at that node. These are different searches. A future null-disabled
region requires an explicit lifetime/recursion contract.

The 37,085 verifications and 34 disagreements do not prove useless checking;
rare cases may prevent zugzwang errors. The reported 1.1% inclusive node cost
is workload-specific and is not measured CPU time. A new deeper reduction and
verification policy must be judged together, with real-move/zugzwang oracles.

### Extension horizon changes alter chess coverage

MAN-S31's removal of non-root check extensions changed nominal-depth coverage;
it did not demonstrate an exact optimization. Its judgment rejection at
`-3.08 +/- 7.63` nElo neither proves a loss nor establishes a cause.
The former explanation that removing all checking privileges would fix it is
withdrawn. A new forcing-line policy must be derived and tested.

MAN-S33 changed which alternatives were searched to establish singularity.
Its 9.13% depth-ten saving and similar extension conversion do not establish
the same useful singular decisions. The maintainer stopped it inconclusive
at a supplied `+1.24 +/- 8.36` nElo snapshot. No automatic retry.

### Cost measurements are not counterfactual savings

Inclusive attribution categories overlap; their percentages cannot be summed
into a unique-work share. Extension frequency does not bound descendant work
removed by an ablation. The 16/64/256-MiB sweep weakens the capacity-pressure
hypothesis on that workload, not all TT layout/replacement or game-history
hypotheses. The two mate-heavy positions must be reported separately as well
as retained in the whole corpus.

## Implementation use

Follow PLAN 6.5.4–6.5.15 and ADR-0068. Freeze Manta's node/move evidence pipeline
before implementing consumers. Every smaller-model ticket names its inputs,
outputs, legal exceptions, score/bound authority, expected cost and refutation
gate. Added mechanisms must consume and improve the shared accepted model,
not duplicate a second ordering, evaluation or depth policy.

Do not relabel archived experiments as the new step numbers. Their original
registrations remain historical evidence; new hypotheses require prospective
registration after implementation and correctness freeze, without harness pilots.
