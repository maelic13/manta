# Manta Engineering Plan

This document tells coding agents how to sequence Manta work and what evidence
closes a step. `GUIDE.md` is the maintainer checklist, `REQUIREMENTS.md` is
normative, ADRs own durable design decisions, and `EXPERIMENTS.md` records
measurement verdicts.

## Current state

Manta 1.0.0 is the release baseline. Phases 0–6 are closed, targeted pre-NNUE
performance Phase 6.5 is current and Phase 7 has not started. The production
engine combines MAN-E19 classical evaluation, MAN-S29 search parameters and
MAN-T05 integrated clock parameters, MAN-S30 live-history move ordering.
One-thread depth-6 bench is `775,451` nodes. The release configuration supports portable 64-bit Windows x86-64,
Linux x86-64/ARM64 and macOS x86-64/ARM64 artifacts.

No coding agent may start a Phase-6.5 implementation step, Phase 7, a game
match, SPSA, data generation or other long run without explicit maintainer
approval.

## Engineering and evidence contracts

### Product and architecture

- Build the strongest correct chess-playing engine practical in Zig while
  preserving deterministic one-thread behavior as the first-class baseline.
- Follow the inward dependency graph in `ARCHITECTURE.md`; keep allocation,
  I/O, locks and avoidable shared atomics out of ordinary hot paths.
- The scalar implementation is authoritative. Optimized backends must be exact
  and selected through an explicit capability contract.
- Study mature engines for candidate concepts, dependencies and test methods,
  never for implementation parity or copied constants.
- Preserve legal-position, terminal, draw/history, special-move, score/bound,
  provenance and thread-ownership semantics for every chess/search change.

### Change workflow

1. Read the current GUIDE checkpoint, owning requirement and relevant ADR.
2. State the bounded outcome, affected files and verification gate before the
   first edit. Obtain approval for meaningful scope changes.
3. Freeze the mechanism with focused correctness/property tests.
4. Run cheap gates during editing and each required complete gate once after
   behavior freezes.
5. Measure only the quantities needed for the current decision. Register a
   playing or tuning experiment prospectively before spending games.
6. Record a completed step in GUIDE and PLAN, and evidence in EXPERIMENTS/ADRs.

### Evidence hierarchy

- Independent rules, properties, perft, make/unmake recomputation and protocol
  tests decide correctness.
- A bench fingerprint identifies deterministic behavior; it is not a speed or
  strength measurement.
- Fixed-work and throughput measurements diagnose cost, scaling and quality per
  node but do not promote playing changes.
- A candidate claiming exact behavior must reproduce the accepted fingerprint,
  PV and results. A mismatch requires a causal record and reclassifies a legal,
  deterministic candidate as playing behavior; it does not reject it for
  strength.
- Once tournament-capable, every retained production-executable candidate,
  including exact speed work, receives one prospectively registered,
  representative SPRT. H1 promotes; H0 rejects and an unresolved cap does not
  promote. Documentation, tests and disabled diagnostics require no games.
- A cohesive bundle may be gated only when its parts are inseparable or below
  affordable independent resolution. Its result licenses only the bundle.
- SPSA begins only after consumers freeze and a sensitivity pilot justifies the
  interacting coordinates. The complete rounded vector receives one game gate.

### Tooling and host policy

- Use exactly Zig 0.16.0 until a separately approved stable-toolchain migration.
- Use Manta's checked fastchess bridge for matches and its pinned local Weather
  Factory wrapper for SPSA. Colosseum is parked until explicitly re-enabled.
- Development, implementation and local diagnostics occur on the current
  workspace computer. Authoritative games, tuning and final cross-engine
  timings run on the separate designated Ryzen 9 5950X.
- Agents prepare candidate and baseline from exact source identities with the
  same Zig version, target and build options. A remote handoff records source
  revision/tree or archive hash, binary SHA-256, feature switches, benchmark
  fingerprint, runner/book hashes and the complete setup-only command.
- The maintainer runs setup validation and the registered resumable job on the
  designated host, then returns the manifest, log, PGN and checkpoint for
  verification. Require a fresh bounded pilot only when a changed engine/
  protocol, clock, runner, host, placement, book or adjudication boundary needs
  qualification. Agents do not start long jobs on either host.
- Do not overlap games, tuning or data generation on that host.

### Release policy

Manta uses semantic versions and `vMAJOR.MINOR.PATCH` Git tags. Major versions
represent major engine generations or incompatible public contracts, minor
versions meaningful compatible features/strength releases, and patch versions
correctness, portability, build, documentation or deliberately small changes.
The display name may shorten `1.0.0` to “Manta 1”.

A release is valid only from a clean tagged commit whose two version sources and
changelog agree, after required CI passes. The release workflow builds and
natively smoke-tests every supported portable artifact, requires deterministic
bench agreement, creates SHA-256 checksums and uploads assets to the existing
GitHub Release. Tags, pushes and publication remain maintainer-owned.

## Completed phases

### Phase 0 — Clean architecture and contracts

#### 0.0 — Product scope, origin and licensing

Closed with original-project identity, GPL licensing and explicit provenance.

#### 0.1 — Requirements and quality model

Closed with stable requirement IDs, correctness priorities and verification
classes.

#### 0.2 — Architecture design

Closed with explicit boundaries, dependency direction, ownership and replaceable
outer adapters.

#### 0.3 — Architecture proof and exit gate

Closed after repository-policy and architectural conformance review.

### Phase 1 — Repository and UCI foundation

#### 1.0 — Toolchain and build spine

Closed on pinned Zig 0.16.0, canonical formatting, lint, tests and artifacts.

#### 1.1 — UCI behavioral specification

Closed with command, state, timing, ordering and failure behavior specified.

#### 1.2 — Test harness and repository policy

Closed with bounded child-process transcripts and repository contract checks.

#### 1.3 — Artifact build orchestration

Closed with truthful native/portable versioned artifact naming.

### Phase 2 — Board, state and move generation

#### 2.0 — Domain types and representation

Closed with the selected board model and documented invariants.

#### 2.1 — State transitions and legality

Closed with legal chess, reversible state, repetition, hashing and special moves.

#### 2.2 — Correctness campaign

Closed through independent perft, randomized full-state recomputation and
terminal/draw coverage.

#### 2.3 — Board benchmark

Closed with a versioned workload for board, attack and SEE diagnostics.

### Phase 3 — Classical evaluation foundation

#### 3.0 — Evaluation boundary

Closed with score, trace and evaluator contracts.

#### 3.1 — Initial Manta HCE

Closed with a complete original tapered classical evaluator and focused tests.

#### 3.2 — Strategic HCE limit

Closed with a sound fallback and an explicit evidence threshold for further
evaluation work.

### Phase 4 — Deterministic search, UCI and tooling

#### 4.0 — Search correctness baseline

Closed with deterministic iterative deepening, alpha-beta/PVS, quiescence and
legal result handling.

#### 4.1 — TT, ordering and diagnostics

Closed with transposition, ordering/history and bounded instrumentation.

#### 4.2 — UCI baseline completion

Closed with real search limits, cancellation and publication wired to UCI.

#### 4.3 — Bench and test suites

Closed with deterministic bench and full correctness/safety/process gates.

#### 4.4 — Experiment tooling

Closed with checked build, match, SPRT, SPSA and evidence workflows. Colosseum
is retained but parked.

#### 4.5 — Test-host qualification

Closed with the 5950X host profile and calibrated harness boundary.

### Phase 5 — Classical convergence

#### 5.0 — Functional baseline

Closed with a tournament-capable one-thread baseline and representative gate.

#### 5.1 — Search architecture

Closed after deterministic and game-tested search development. Rejected
mechanisms remain disabled; exact MAN-S19 became the pre-fit search head.

#### 5.2 — Syzygy and endgames

Closed with correct WDL/DTZ probing, root integration and rule-50 semantics.

#### 5.3 — Evaluator convergence

Closed after coverage completion and constrained fit. MAN-E19 accepted H1 and
is the released classical evaluator.

#### 5.4 — Search/evaluation synchronization and final fit

Closed after residual compatibility review and a complete ten-coordinate
search fit. MAN-S29 accepted H1 and is production. The cumulative MAN-C01 gate
accepted H1 against Phase 5.0; its small sample establishes a material
cumulative improvement, not a precise Elo value or component attribution.

### Phase 6 — Time management, robust UCI and SMP

#### 6.0 — Clock and root confidence

Closed with hard-safe receipt-based deadlines, root telemetry and exact
once-counted ponder credit. Rejected confidence consumers remain disabled.

#### 6.1 — Full UCI parity

Closed with authoritative options, ordered asynchronous control, pondering,
reporting and the full process matrix.

#### 6.2 — SMP

Closed with main-authoritative lazy SMP. Fixed-work scaling reached
`1.00x/2.16x/4.17x/7.68x` at 1/2/4/8T, and MAN-R03 qualified the 4T pool. This
does not establish strength at every thread count.

#### 6.3 — Integrated time-management maturity

Closed with typed telemetry, an integrated optimum/maximum policy and the
complete fitted MAN-T05 clock surface. MAN-T05 was accepted by explicit
maintainer judgment after an H1 result whose wrapper rejected six completed
time forfeits under its original zero-timeout contract; the candidate had one
and the baseline five. The final MAN-C02 4T-versus-Phase-5 1T gate accepted H1
without anomaly. It establishes a material integrated release gain, not a
precise rating or attribution to time, UCI or SMP individually.

## Open roadmap

### Phase 6.5 — Pre-NNUE search and hot-path performance

This phase repairs two separately measured deficits before the board and
evaluation contracts become inputs to NNUE work: Manta processes each node too
slowly and searches far too many nodes to reach the same nominal depth. The
post-MAN-S29 audit measured `9–14x` more depth-ten nodes and `2.6–3.2x` more
time per node than the sibling engines. Small hot-path or PGO gains cannot close
that combined gap, so tree efficiency is the first-class objective.

Behavior-neutral work must preserve legal move membership and order,
terminal/draw/history semantics, score/bound/provenance, TT/PV results and the
exact one-thread search tree. If an implementation instead changes a history
snapshot, move order, score, bound or searched subtree, diagnose and record the
cause, then treat the legal deterministic result as a playing candidate. A
fingerprint change never rejects such a candidate for strength. Node reduction,
depth, NPS, fixed-node quality and static tests remain diagnostics.

Every retained production-executable candidate in this phase, including an
exact speed optimization, must pass its own prospectively registered 1T
time-based SPRT on the separate designated game-testing computer. Correctness,
operational and throughput gates admit a candidate to games and may show that
it does not solve this phase's performance objective; only clean H1 promotes
it. Do not combine independent mechanisms to save game budget.

Track the whole depth curve rather than minimizing the depth-six fingerprint.
Deep selectivity may leave shallow totals nearly unchanged. The final
operational gate requires the common corpus through depth thirteen and a
routinely runnable `bench 13 1 1` under a prospective wall-time limit frozen by
the maintainer before the run. Equal-depth comparisons use identical positions,
1T, Hash, toolchain class and fresh processes; fixed-node quality and SPRT guard
against obtaining a smaller tree by discarding valuable chess work.

#### 6.5.0 — Comparable performance audit

Complete. All engines used the same `cross-engine-board-v1` workload and the
same forty search FENs. Native ReleaseFast Manta measured `1.12M` NPS and
`28,858,278` nodes at depth ten, versus Rarog at `2.96M`/`2,055,303` and
Basilisk at `3.58M`/`3,215,963`. Manta therefore searched `14.0x`/`9.0x` more
nodes and processed a node `2.6x`/`3.2x` more slowly. Its depth-eight-to-ten
tree grew `6.28x`, versus `2.61x` and `3.29x`.

The board benchmark localized a smaller but real deficit. Manta reached
`392M` legal moves/s, `93M` captures/s, `36M` make-unmakes/s, `239M` perft
nodes/s and `323M` two-ply simulations/s. That is generally `7–17%` behind
Rarog and `22–39%` behind Basilisk. Rarog's SEE uses different piece values,
so only the Manta/Basilisk `31.6M`/`54.4M` SEE comparison is exact.

The production observation supplied the mechanism evidence: about twenty-one
moves were generated per searched move, roughly `85–86%` of cutoffs occurred
on the first searched move, and the depth-ten opening case accepted `16,328`
of `16,901` LMR probes without re-search. Its `573` re-searches are `3.4%` and
its mean reduction is about `1.12` plies. Null move cut on `354` of `1,472`
attempts, while `354` of `355` fail-highs survived mandatory verification.
ProbCut converted `39` of the `44` moves that passed its qsearch filter. HCE
measured `3.39M` evaluations/s; its call frequency and standalone cost make it
a secondary per-node cost rather than an explanation for the search-tree gap.

The audit creates priorities, not Elo claims. The repository remained
unchanged while it was measured.

#### 6.5.1a — Exact staged move picker

Complete — rejected only as an exact optimization. The allocation-free
prototype split ordinary non-check interior generation into validated TT, good
tactical, lazy quiet and bad tactical stages. Its random legal-position
differential covered equal membership, order and uniqueness, including
castling, en passant and every promotion shape, and the full Debug gate passed.

Lazy quiet generation and ranking produced `775,451` depth-six nodes instead
of production `799,610`. The eager control retained `799,610`, and forcing the
prototype to generate and rank quiets before searching its first child also
restored `799,610`. Descendant searches update worker-local main, reply and
continuation histories; the accepted picker snapshots every sibling rank at
parent entry, while the lazy stage consumed later history. Preserving that
snapshot required the eager quiet work and removed the intended saving. The
prototype was removed and the production picker remains unchanged.

This result rejects only the behavior-neutral formulation. It does not decide
whether live-history ordering is stronger or whether its combined tree and
per-node change improves time-controlled play.

#### 6.5.1b — Live-history staged picker

Complete — accepted and promoted. Registered `MAN-S30` crossed its `[1,5]` H1
boundary after 8,752 games at `+13.19 +/- 7.28` nElo (`+8.93 +/- 4.93` Elo,
LLR `2.95`, LOS `99.98%`). Live-history staging is now the production default,
production fingerprint is `775,451`, and `-Dlive-history-staging=false`
reconstructs the superseded MAN-S29 eager picker for archived diagnostics.
Four completed time forfeits (three baseline, one candidate, no other fault)
tripped the bridge's zero-timeout rule; the maintainer accepted the result by
explicit judgment and `EXPERIMENTS.md` records both the waiver and the PGN
reconstruction showing host scheduling pressure rather than a clock defect.

The original step definition follows.

Rebuild the lazy generator as an explicitly behavior-changing candidate. The
producer is authoritative worker-local history updated by completed descendant
searches; tactical and quiet generation transform it at the time each stage is
entered; ordering is the sole consumer. It gains no legality, terminal/draw,
score, bound, provenance, TT, PV, pruning, reduction, allocation or thread
authority.

Prove deterministic 1T execution, equal legal membership, uniqueness and state
restoration across castling, en passant, all promotions, checks, evasions,
terminal positions, repetitions and rule-50 cases. Record complete depth curves,
per-stage generated/searched counts, NPS and wall time. The fingerprint and PV
may change and receive a causal ledger entry. Prepare exact candidate/baseline
artifacts and a setup-only manifest; the maintainer runs one prospectively
registered 1T SPRT directly on the separate game host. No fresh pilot is needed
because this candidate changes only internal search ordering and retains the
qualified engine/protocol, clock, runner, host, placement, book and adjudication
boundaries. Only clean H1 may promote it.

Recommended model: GPT-6 Astra High; GPT-5.6 Sol XHigh fallback.

Implementation record — the mechanism is complete and now default-on.
`-Dlive-history-staging` selects it for the engine, built-in bench and
search-observation executable. Direct legal generation now exposes exact
tactical and non-tactical-quiet subsets whose filtered order and union match
the complete generator across castling, en passant, checks and every promotion
shape. Ordinary root, checked and singular-exclusion nodes retain eager
generation. One caller-owned `MoveList` holds the tactical prefix, a validated
quiet TT move if present, delayed quiets and retained bad tacticals without
allocation or duplicate emission.

The candidate repeats deterministically with legal PV and restored state. Its
depth-six bench is `775,451` nodes versus production `799,610`, exactly matching
the earlier diagnosed prototype and causally confirming live quiet-rank timing.
The candidate observation passes all twelve fixed cohorts and reports tactical
generation, quiet-stage entry, delayed quiet generation and existing searched-
source counts. Across that completed cohort, `79,446` eligible staged nodes
generated `88,027` tacticals; only `56,539` opened their quiet stage, so
`22,907` completed nodes avoided quiet generation. Opened stages generated
`1,579,505` non-tactical quiets. These are diagnostic results, not a strength
verdict. A sequential five-repeat development-host depth-six check measured
baseline/candidate median wall time `791/766 ms` and median NPS
`1,010,884/1,012,338`: the `3.02%` smaller tree produced about `3.16%` lower
wall time without resolved per-node regression. This was neither idle-host nor
game evidence; registered `MAN-S30` on the separate 5950X supplied the
promotion verdict recorded above.

#### 6.5.2 — Whole-tree attribution

Rebaseline production MAN-S29 before selecting more search candidates. Use the
same forty positions, 1T, native ReleaseFast, identical Hash and a fresh process
per depth for Manta, Rarog and Basilisk. Measure depths four through ten first;
extend to eleven and twelve only inside a recorded local time cap. Use a
16/64/256 MiB Hash sweep to separate search policy from TT pressure. Stockfish
is a search-shape reference under the same corpus, not an implementation target.

Extend observation only where needed to partition main and qsearch nodes; PVS
and aspiration retries; LMR probes and full-depth verification; null probes and
verification; ProbCut; singular/exclusion work; check entries and extension
chains; generated and searched moves; and TT probe, hit, usable-cutoff, depth
rejection, collision and replacement yield. Report per-depth and per-position
distributions so one opening or ending cannot decide the diagnosis.

This step changes no production mechanism and runs no games. Its output ranks
the following candidate questions and freezes the operational depth-curve
baseline. Recommended model: GPT-5.6 Terra High.

#### 6.5.3 — Forcing-line selectivity

Measure the compound cost of unconditional extension at every checked node,
full-depth treatment of every evasion and checking move, and checking-move
exemption from shallow pruning. Nominal root depth, legal check evasion,
existing terminal/draw precedence, mate distance and special-move legality
remain fixed; only the amount of search allocated to non-root forcing lines
may change.

First test removing blanket check extension as one independently switched
candidate. If evidence then justifies it, test late checking-move or evasion LMR
as a separate candidate using move ordinal, SEE/history and node expectation;
do not prune legal evasions. Record check-chain length, in-check nodes,
extensions, reduced checks/evasions, verification re-searches, tactical/mate
results and the complete depth curve. Each production candidate receives its
own remote-host 1T SPRT and requires clean H1.

Recommended model: GPT-6 Astra High; GPT-5.6 Sol XHigh fallback.

#### 6.5.4 — Aspiration-aware contextual LMR

Replace the saturating minimum-shaped reduction only through one
dependency-complete candidate. Root aspiration supplies the current window
width; a non-saturating depth/move surface combines that width with typed node
expectation, improving direction, TT quality, singular context, move class and
accepted history. The prospective reduced depth may then consistently inform
LMP, futility and SEE eligibility. Losing captures and any check/evasion scope
must be justified by 6.5.3 evidence; promotions and the singular move retain
explicit protection.

The candidate must retain at least one ordinary child ply where required.
Every reduced alpha rise returns to an authoritative horizon before publishing
score, bound, PV, TT or history evidence. Aspiration retries reset partial root
evidence and only a final exact iteration commits. Per-depth and per-position
node/re-search distributions diagnose the mechanism but cannot reject it for
strength solely because the fingerprint moves. One remote-host 1T SPRT decides
promotion; H1 licenses only the complete dependency cluster.

Recommended model: GPT-6 Astra XHigh; GPT-5.6 Sol Max fallback.

#### 6.5.5 — Forward proof and pruning efficiency

After the LMR head freezes, attribute and test proof mechanisms separately.
The first null-move question is whether the present same-node verification is
needed in safe ordinary material: `354` of `355` observed fail-highs survived
it. Checks, PV, consecutive nulls, pawn-only and zugzwang-prone material,
decisive scores and shallow horizons retain exclusions or verification unless a
new contract proves otherwise. Null evidence remains a typed lower-bound proof.

Then measure ProbCut TT reuse, tactical move cap and qsearch-to-main conversion,
and whether LMP, futility and SEE consume the final prospective depth from
6.5.4 consistently. Do not reopen the complete rejected MAN-S20 bundle. Each
new producer/consumer relation is independently switched, tested for legal PV,
mate/draw, zugzwang, bound/provenance, TT and restoration semantics, and given
its own remote-host 1T SPRT before promotion.

Recommended model: GPT-6 Astra High; GPT-5.6 Sol XHigh fallback.

#### 6.5.6 — TT and qsearch efficiency

Measure TT density, replacement, generation aging, prefetch value and usable
main/qsearch cutoff yield before changing layout or policy. Hash sweeps must
distinguish a weak replacement policy from ordinary capacity pressure. Any
layout-only candidate preserves exact encoded semantics; any changed
replacement or cutoff behavior is a playing candidate with a new fingerprint.

At non-check qsearch nodes, generate only legal captures and promotions instead
of generating and ranking every legal quiet that will be discarded. In-check
qsearch still generates and searches every legal evasion. Preserve tactical
generation order, SEE/delta decisions, checks, underpromotions, en passant,
terminal results, TT stores and score provenance. An exact implementation must
retain the fingerprint; a deterministic mismatch is diagnosed and moved to the
playing track. Every retained production candidate receives its own remote-host
1T SPRT after correctness and controlled throughput qualification.

Recommended model: GPT-6 Astra High; GPT-5.6 Sol XHigh fallback.

#### 6.5.7 — Exact board, SEE and HCE hot paths

Reprofile only after the accepted search head freezes, because tree changes
alter hot-path frequency. Candidate board areas are a no-pinned legal-generation
path, reused pin/check facts, single move classification/SEE, and measured
transition, checker or repetition work. PEXT already exists in native BMI2
builds. Preserve every mailbox/bitboard/count/king/key/rule-50/repetition/checker
and factual move-delta invariant through recomputation, randomized make/unmake,
perft and special-move tests.

For MAN-E19, compare occupied-piece traversal with the current 64-square
material/PST/phase scan and instrument pawn-cache hit, collision and footprint
before changing it. Preserve exact score, trace and symmetry. Do not add
incremental HCE or a whole-eval cache without a new concentrated profile and
ownership decision.

Each candidate needs exact fingerprint/PV/results, repeated native board or HCE
and complete-search throughput, and—under the Phase-6.5 production policy—one
remote-host 1T SPRT. A mismatch is reclassified rather than hidden. Group only
mechanically inseparable edits.

Recommended model: GPT-5.6 Terra High.

#### 6.5.8 — Build optimization

After source behavior freezes, define a representative PGO training workload
from the deterministic corpus, including opening, tactical, quiet, check-evasion
and endgame positions. Implement generate/merge/use as a checked build pipeline
with compiler/version, workload and profile integrity recorded. Portable and
non-PGO fallbacks remain available and accurately named.

Repeated clean builds must reproduce fingerprint, PV/results and profile-use
metadata. Compare candidate and non-PGO binaries on fresh-process board, HCE and
complete-search workloads. A retained PGO production artifact also requires its
own remote-host 1T SPRT; no resolved end-to-end gain closes the step without
adding product complexity.

Recommended model: GPT-5.6 Terra High.

#### 6.5.9 — Qualification and close

Run the full correctness, ReleaseSafe, ReleaseFast, UCI/process, policy and
platform gates after the final implementation freezes. On the separate
designated host, verify source/archive identities, Zig/build options, candidate
and baseline SHA-256, feature ledger, runner/book hashes and setup-only output
before any SPRT. Run a fresh pilot only when one of those operational boundaries
changed and needs requalification. The maintainer starts the jobs and returns
manifest, log, PGN and checkpoint evidence; no result is recorded until
independent pair and anomaly reconstruction agrees.

Repeat the common 1T/Hash depth curve through depth thirteen on the same host for
Manta, Rarog and Basilisk, with Stockfish retained as a search-shape reference.
Record nodes, NPS, elapsed time, effective growth and per-position tails against
immutable Manta 1.0.0. Run `bench 13 1 1` under the prospectively frozen routine
wall-time limit. These are operational exit gates, not Elo claims.

Every retained production change must already hold its own clean H1. Then run
one prospectively registered cumulative 1T SPRT against immutable Manta 1.0.0
to establish the integrated result, not component attribution or a precise
rating. Close Phase 6.5 only with accepted implementations, rejected/parked or
unresolved dispositions, complete remote artifacts and no unowned selector.
Phase 7 requires separate approval.

Recommended model: GPT-5.6 Sol High.

### Phase 7 — NNUE runway and data contract

#### 7.0 — State and accumulator contract

- Audit every move, null-move and unmake path for complete dirty-piece records
  and accumulator push/pop/refresh needs.
- Freeze scalar feature indexing, perspectives, buckets and quantization.
- Define architecture, version, endianness and integrity metadata in the first
  network format.
- Require disabled scaffolding to preserve exact production behavior.

#### 7.1 — Trainer and dataset preflight

- Qualify and pin the shared `net_trainer` revision for data, training,
  checkpoints, export and conformance vectors.
- Define sampling, deduplication, splits, label blend, seeds, resume and
  integrity before generating a large dataset.
- Keep Manta responsible for its original Zig loader, scalar inference,
  incremental accumulators and optimized backends.
- Preserve HCE/search disagreement corpora as diagnostics, not automatic truth.

#### 7.2 — Runway gate

Land no-op/scalar scaffolding only when disabled behavior is bench-identical,
every board transition is covered and the format is portable across the
supported matrix.

### Phase 8 — Baseline NNUE

#### 8.0 — Controlled pilot networks

Train small reproducible pilots with multiple seeds. Validate file loading,
quantization, scalar inference and untouched metrics before scaling data or
architecture.

#### 8.1 — Scalar and incremental integration

Integrate through the existing evaluator contract. Prove full-refresh,
incremental and trainer-export parity over randomized games and every special
move, with strict loader failures and reported network identity.

#### 8.2 — Portable and vector backends

Implement exact portable, x86-64 and ARM64 kernels. Every optimized path must
match the scalar integer reference bit-for-bit.

#### 8.3 — Baseline acceptance

Use multiple seeds, untouched loss, integer conformance, throughput and
fixed-node quality as the funnel. Give the sole surviving NNUE candidate one
representative one-thread time-based SPRT against HCE. Keep HCE buildable and
tested after NNUE becomes the default.

### Phase 9 — NNUE frontier and final search fit

#### 9.0 — Residual and disagreement analysis

Use untouched teacher residuals, search disagreements, natural finishes and
games to locate real data or architecture gaps.

#### 9.1 — Architecture ladder

Test evidence-led feature, bucket, width, activation and refresh changes one
axis at a time. Reject weak candidates through multi-seed loss, conformance and
throughput before the single playing gate.

#### 9.2 — Search/evaluator co-adaptation

Reopen pruning margins, histories, corrections, static-eval consumers and
provenance assumptions under the retained NNUE. Permit original structural
changes; do not assume HCE-era mechanisms or constants remain optimal.

#### 9.3 — Consolidated post-NNUE fit

After architecture, score scale and consumers freeze, conduct a necessity
review and sensitivity pilot. If justified, run one bounded checkpointed SPSA
over non-redundant interacting coordinates, bake the complete result and submit
one representative SPRT. Otherwise close the step without tuning.

### Phase 10 — ISA dispatch, platforms, scaling and release maturity

#### 10.0 — Runtime backend dispatch

Create one explicit capability contract around a portable semantic core and
measured sibling ISA backends. AVX2 and BMI2/PEXT are independent capabilities;
forced unsupported backends must fail safely.

#### 10.1 — Native platform validation

Build and execute every production asset on its native target. Require
correctness, UCI/perft/bench agreement, backend conformance, atomic assumptions
and target-native performance evidence.

#### 10.2 — Performance and scaling

Profile before optimizing. Measure board, evaluator, search, TT/cache pressure,
allocation, branches, 1/2/4/8T scaling and high-thread/NUMA behavior. The Phase-5
evaluator deliberately traded throughput for strength, so behavior-neutral
evaluation speed remains useful when a current profile identifies a concentrated
cost. Fingerprint identity plus controlled throughput can accept exact speed
work; behavior changes require games. This later step owns post-NNUE runtime ISA
dispatch, vector inference, topology, NUMA and final scaling. It consumes rather
than repeats the pre-NNUE scalar/search work closed in Phase 6.5.

#### 10.3 — Product completion and releases

Add requested features such as MultiPV or Chess960 only through dedicated
contracts and correctness/UCI gates. For each release, produce reproducible
native assets, checksums, smoke results and matching user-facing notes.

### Phase 11 — Optional HCE fallback

Enter only after serious NNUE retries fail and the maintainer explicitly
chooses to redirect development.

#### 11.0 — Failure review and scope decision

Document which NNUE hypotheses failed, their evidence and why further NNUE work
has lower expected value. Confirm the HCE remains correct and performant.

#### 11.1 — HCE residual program

Use evaluation traces, untouched residuals and search disagreements to select a
small HCE feature program without recreating historical feature lists.

#### 11.2 — HCE fit and release

Require a tuning-necessity review before one HCE fit, then one representative
SPRT and complete platform/release evidence only if the result will ship.

## Manta 1 release gate

1. Version sources, UCI identity, changelog and tag must agree on `1.0.0` /
   `v1.0.0`.
2. The worktree is reviewed for accidental/generated content and licensing.
3. Format, policy, lint and required Debug/ReleaseSafe/ReleaseFast gates pass.
4. Pull-request CI passes all five native targets and portable smoke tests.
5. The annotated tag points at the reviewed release commit.
6. The published release workflow natively builds all five artifacts, verifies
   their UCI identities and shared depth-6 fingerprint, and attaches checksums.
7. A clean download of at least one published artifact is launched in a UCI
   interface before announcing the release.

The exact maintainer procedure is in `docs/RELEASING.md`.
