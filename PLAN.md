# Manta Engineering Plan

This document tells coding agents how to sequence Manta work and what evidence
closes a step. `GUIDE.md` is the maintainer checklist, `REQUIREMENTS.md` is
normative, ADRs own durable design decisions, and `EXPERIMENTS.md` records
measurement verdicts.

## Current state

Manta 1.0.0 is the release baseline. Phases 0–6 are closed, targeted pre-NNUE
performance Phase 6.5 is current and Phase 7 has not started. Phase 7 remains
blocked until all of Phase 6.5, including every retained candidate and evidence
closeout below, is complete. The production
engine combines MAN-E19 classical evaluation, MAN-S29 search parameters,
MAN-T05 integrated clock parameters, MAN-S30 live-history move ordering,
MAN-S34 tactical-only non-check qsearch generation and MAN-S35 complete mate
windows.
One-thread depth-6 bench is `642,336` nodes. The release configuration supports portable 64-bit Windows x86-64,
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
- The checked fastchess SPRT harness is trusted from battle-tested Rarog and
  Basilisk use. An ordinary Manta search candidate with unchanged operational
  boundaries proceeds directly from setup-only validation to its final SPRT;
  do not insert a candidate-specific pilot.
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

Closed with deterministic bench and full correctness/safety/process gates. The
2026-09-09 presentation alignment uses Rarog's `bench [depth] [repeats]`
argument order, per-position fields and aggregate layout over the already
identical forty-position corpus. Manta retains its depth-six default and exact
`775,451` production fingerprint; only the diagnostic interface changed.

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

### Phase 6.5 — Board backbone and integrated search maturity

Replanned on 2026-09-08 by maintainer request after MAN-S31 and the stopped
MAN-S33 attempt. ADR-0068 supersedes the old open-step sequence; completed
6.5.0–6.5.3 keep their historical numbers. Production remains MAN-S30 at
`775,451`. This is implementation guidance, not permission to start engines,
jobs, tuning or Phase 7.

There are two independent delivery objectives. Neither may hide failure of the
other, and neither is a substitute for playing strength:

| Objective | Frozen comparison and exit target |
|---|---|
| Board backbone | On the idle designated 5950X, native optimized builds, identical `cross-engine-board-v1` inputs/work counts and SEE semantics: geometric mean of Manta/Basilisk throughput ratios across all six cells at least `1.00`, with no cell below `0.95`. Report every cell, not just the aggregate. These are maintainer-request-derived planning targets, not achieved measurements. |
| Mature search | Revised 2026-09-12 by maintainer direction: the reference is the pinned final pre-NNUE Stockfish (`9587eeeb`), not the maintainer's own engines. Same immutable forty positions, 1T, Hash 64 MiB, fresh-process/reset policy: geometric branching over depths 4 to 12 at most `1.98` against the reference's host-measured value, depth-12 total elapsed at most `4x` the reference, ordinary and mate cohorts reported separately and both retained. Separately require routine `bench 13 1` (Hash 1 MiB) within 30 seconds. Historical Basilisk depth-13 figures remain recorded under 6.5.4 as diagnostics. |
| Strength and safety | Legal results, correct terminal/draw/bound authority, unchanged hard time safety, each retained candidate's registered 1T H1, then cumulative H1 against immutable Manta 1.0.0. No inferred 4T strength improvement. |

Step 6.5.4 binds reference revisions, tolerances, timing protocol and the
absolute routine-bench limit before implementation measurements. Do not move a
target after seeing a result. A failed target means an open deficit or explicit
maintainer scope revision, not a completed phase because all ideas were tried.
Native compiler/ISA capability must be comparable, not identical compiler brands.
Board moves/s, perft nodes/s, full-search NPS, searched nodes and elapsed time
are separate quantities. Fewer cheap nodes can lower NPS while saving time;
removing useful search can shrink nodes without saving strength. Nominal depth
is an operational comparison, not equal chess coverage across engines.

**Reference and implementation rule.** Use modern Stockfish search structure,
feature relationships and evidence flow, currently pinned at
`edb0d9db6731067ec50ce619ff372b463bc4dd5d`, as the structural design reference.
The final pre-NNUE Stockfish pinned in `config/eval-reference.json` is the
search-shape and strength yardstick for a classical-evaluation engine and the
HCE study reference; Basilisk remains the board-throughput comparison and the
maintainer's engines are otherwise secondary data points.
Reimplement selected structure and features as original Zig, with Manta-owned
score units, history scales, depth semantics, safety predicates and tests.
Do not import NNUE-dependent confidence assumptions or tuned constants. An
absent/default-off family is a coverage question, not proof it will win here.

**Delivery order and compatibility.** Board facts feed efficient generation and
SEE; those feed qsearch and ordering; authoritative search outcomes train
history; the same bounded evidence informs prospective depth, pruning,
extensions and verification. Later candidates start from the accepted earlier
head. A rejected dependency stays off and its dependent proposal must be
re-derived; never quietly activate a rejected umbrella. The sequence is:

`4 contracts -> 5 legal generation -> 6 transitions/SEE -> 7 qsearch ->
8 search design -> 9 evidence substrate -> 10 coordinated core ->
11 core fit -> 12 second-order relationships -> 13 residual cost ->
14 targets, cumulative gate and release decision` (resequenced 2026-09-12).

**Common implementation ticket (applies to every open step).**

- Read the named code/contract; state the changed producer, transformations,
  all consumers and the excluded scope before editing. Work on one numbered
  ticket, not the next step as well.
- Freeze feature-off reconstruction, typed ordinary/mate/tablebase/draw scores,
  TT depth/bound/provenance, complete-root publication, cancellation restoration
  and worker-local ownership. No hot-path allocation, I/O, locks or avoidable
  shared atomics. Preserve portable scalar authority and Zig 0.16.0.
- While editing use compile/focused invariant tests. Once frozen run the
  applicable complete correctness/safety/process gates once. Exact claims
  require fingerprint, PV and result identity; explain legal mismatches rather
  than blessing a changed expected value.
- Use existing board, observation, attribution and branching tools. Add only a
  missing counter needed for the ticket's decision, behind disabled diagnostics.
  Inspect release-build cost, never observer timings. Use matched A/B order and
  repeated samples; unresolved noise is not a speed claim.
- Each independently meaningful retained production change gets one final
  registered 1T SPRT. An inseparable producer/consumer package or demonstrated
  below-resolution cohesive package gets one gate for the package, not games
  after each partial implementation ticket. Register package membership and
  switches before games; agreement with a reference is not bundling evidence.
- Use the trusted existing fastchess harness: setup-only validation, then the
  final command. No candidate-specific pilots, no automatic second time control,
  no extending or splicing an inconclusive run. Freeze source/binaries, host
  placement, budget, anomaly rule and stop rule; maintainer runs games.
- H0, cap and maintainer-stopped inconclusive runs do not promote. Do not infer
  equivalence from an interval containing zero, or a settled verdict from an
  LLR trend. Store concise evidence in EXPERIMENTS; raw artifacts stay ignored.

**Model assignments (revised 2026-09-12).** Claude Fable owns search design,
interacting selective-search semantics, authority review and every chess
question an implementer cannot settle from the written contract. Claude Opus
implements frozen tickets from ADR and PLAN text, runs the named diagnostics
and stops at an unresolved chess assumption rather than guessing. The
historical GPT assignments in completed steps are records, not guidance.

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

Complete. `docs/SEARCH_ATTRIBUTION.md` holds the rebaselined depth curve,
per-position distribution and mechanism attribution; no production mechanism
changed and no games ran. The observer gained an exact whole-tree charge
partition, an inclusive per-mechanism subtree cost, transposition lookup and
store outcome partitions and check/extension chain histograms, and
`zig build search-attribution` sweeps the forty-position corpus across depths
and table sizes.

Four historical results inform the reworked phase, without settling causality:

- Two proven-mate positions are `47.5%` of the depth-ten corpus because Manta
  has no mate-distance pruning. Removing them moves the corpus ratio against
  Rarog from `12.3x` to `6.5x`, so the Step-6.5.0 aggregate overstated the
  ordinary-position gap; the per-position median is `5.4x`.
- Branching over depths four to twelve is `2.412` against `1.750` and `1.873`
  for the siblings, so tree efficiency remains a substantial separate deficit.
- Late move reduction reaches `3.3%` of searched main moves and re-searches
  `0.71%` of those, while shallow pruning discards `57%` of candidates outright.
  These conditional rates do not measure missed refutations or safe headroom.
- A 16/64/256 MiB sweep changes Manta's depth-ten tree by `0.70%`, and first
  move cutoffs reach `92.5%`. This weakens capacity-pressure and gross cut-node
  misordering explanations on this workload, not all TT/ordering hypotheses.

Mate-distance pruning was originally assigned to historical Step 6.5.5. The
reworked shared-depth design in 6.5.8–6.5.10 now owns its complete contract.
It remains a playing change, not an automatic cleanup or ordinary-tree solution.

The original step definition follows.

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

The subject is now production MAN-S30 rather than MAN-S29, because MAN-S30 was
promoted before this measurement ran.

#### 6.5.3 — Forcing-line selectivity

Closed by maintainer judgment, not formal H0. MAN-S31 removed only non-root
blanket check increments and retained checked-root extension. Qualification
passed; depth-ten nodes fell 56.53%, or 35.34% excluding the two mate-heavy
positions. At 7,958 games the result was `-3.08 +/- 7.63` nElo, LLR `-1.60`,
without anomaly. Production remains unchanged.

This does not prove a loss, equivalence, or why the change failed to establish
a gain. Removing extensions changes tactical coverage at the same nominal
depth. The old explanation that removing all checking-move protections would
necessarily repair the result is withdrawn. A differently derived forcing-line
policy may be considered only inside 6.5.10's shared depth contract; no isolated
retry or automatic removal of all protections is authorized.

MAN-S32 and MAN-S33 retain their experiment IDs and original registration under
historical Step 6.5.5 / ADR-0067; open step numbers below are new:
MAN-S32 mate-distance pruning remains default-off, with concentrated mate-tree
savings rather than demonstrated ordinary-position strength. The maintainer
stopped MAN-S33; the supplied 6,640-game snapshot is `+1.24 +/- 8.36` nElo,
LLR `-0.39`. It is inconclusive and unpromoted, not H0. Do not restart it or
treat its similar aggregate extension conversion as decision-quality proof.
Final artifact reconciliation remains evidence housekeeping, not a new game job.

#### 6.5.4 — Freeze the two targets and implementation contracts

**Model:** GPT-6 Astra High. **Dependency:** completed evidence above.
**Files:** PLAN, GUIDE, SEARCH_COVERAGE, existing benchmark manifests/tools;
REQUIREMENTS and a relevant ADR only if their authority changes.

1. Reuse the existing audit; do not repeat a broad profiling campaign. Bind the
   exact production Manta, Basilisk and modern search-reference source/binary
   identities. Verify the board profile's six denominators, reset behavior,
   SEE values, native backend and no hidden legality/evaluator work differences.
2. Freeze the two target protocols above, baseline timings and an absolute
   `bench 13 1` limit on the designated host. Reuse comparable retained
   measurements; request only missing baseline measurements from the maintainer.
   Depth-13 jobs have a predeclared timeout and incomplete is not a fast result.
3. Rank board cells by gap and representative search cost, using existing
   profiles first. Explicitly separate generation, transition, SEE, evaluator,
   ordering and TT costs. Inspect relevant emitted code before proposing an
   unchecked fast path, table expansion or layout change.
4. Freeze a legal regression population covering checks/evasions, forced mates,
   quiet tactics, sacrifices, pawn/zugzwang endings, repetitions/rule-50 and
   castling/EP/underpromotions. Reuse existing cases and independent oracles.
   Keep timing inputs separate from correctness stress; no benchmark-specific
   branches or tuned corpus recognition.

**Gate/output:** one concise target/identity/cost table and bounded tickets for
5–7; documentation/policy and missing setup checks only. No candidate or SPRT.
Uncertain cost attribution must be marked, not filled with guessed percentages.

**2026-09-08 execution checkpoint — complete.** The preparation pass froze the
contracts below without engine or game work. The subsequent designated-host run
bound fresh artifacts and followed the fixed stop rules. It establishes open
performance deficits; it does not satisfy either Phase-6.5 exit target.

Frozen identities (SHA-256 is over retained bytes, not a filename/version guess):

| Input | Identity | Qualification status |
|---|---|---|
| Manta production source | `a500d6b3c37696b304c65a94d69bb1cf3b05d169`, tree `232593be935860e98fa5ab9a5df63eaac7db6f99` | Clean checkout; roadmap/tool changes leave the production search mechanism unchanged |
| Production reconstruction | `tools/test_engines/manta-phase65-baseline.exe`, SHA `7727BB4FCB50BE1972E8A45BDE3EFEFC05DAFB3E2C507D5FDEE248DC9632CBB8` | Fresh schema-9 sidecar records clean source, Zig 0.16.0, native integrated-time/live-history/check-extension on, other candidates off, bench `775451` |
| Historical Basilisk search binary | `D:/code/basilisk/build/dist/basilisk-v1.10.0-dev-windows-x86_64-pext-pgo.exe`, SHA `1034DE95AE556B972878F91FF265FED2F4F5CD13F10AAC721D12B62282072906` | Matches attribution record; exact source/compiler/PGO binding is missing. Do not bind it to current checkout by assumption |
| Basilisk production baseline | `tools/test_engines/basilisk-phase65-baseline-pext-pgo.exe`, SHA `A8A574B57C3D700958847C87067D14893E83891D62C7928E9C8E6BDEF04CB0C4` | Clean `d0f262765a198c61dc8fe9fdf09db6a733b61fec`; Clang 22.1.8, native PEXT, PGO-use, bench `12568898` |
| Modern search reference | `edb0d9db6731067ec50ce619ff372b463bc4dd5d`; `src/search.cpp` SHA `A934524DD2F386EC38CDF95B7B2E41CECDC85C9B17E12C0668621E6AE16BE28A` | Source reference, no reference binary needed for either performance target |
| Forty-position timing corpus | `tools/bench_positions.epd`, SHA `F7451A4E7750C6DE5A9AC37AA6E3631782A6932B784B89EEB714BE533E6E1862` | Freeze order and all forty positions; ordinary subset excludes zero-based indices 6 and 30 only |
| Manta board workload | `tools/board_bench.zig`, SHA `F98BF51D355A193FDE42BC0C324CC1E823A60C191D45846FFD0E997281DA38B0` | Work/SEE setup contract inspected; future code edits preserve the input/denominator contract rather than this implementation hash |
| Basilisk board workload | `tests/board_performance.cpp`, SHA `95E2B546FF0BE6F825DC3D3A9B0B0C53C4E28D0C0551C0D23941B5493C68D7E3`, commit `d0f262765a198c61dc8fe9fdf09db6a733b61fec` | Source work counts, schedule and SEE setup endpoint agree; designated-host artifact binding pending |

The old Basilisk binary reports version 1.9.3 despite its filename. Its current
source checkout is not evidence of which code built it. A newly bound baseline
may replace this unqualified historical binary only before candidate timings;
record the replacement and do not combine old/new timing samples. No change
to the target tolerances is implied.

**Board work and cost contract.** Both sources use the same five-position
`cross-engine-board-v1` corpus, reused move lists, threshold zero, no HCE
evaluation callback, 150 ms warm-up and 11 x 150 ms samples, median/MAD.
State is restored between iterations. Native BMI2/PEXT capability must match;
record actual compiler/optimization/PGO and benchmark anti-elision support.
Use optimized source-bound board artifacts, not a PGO-labelled search binary
as proof of the board test's build settings.

| Cell | Operations per corpus iteration | Historical Manta rate | Initial owner and limitation |
|---|---:|---:|---|
| Legal generation | 128 legal moves | 392M moves/s | 5: common unpinned/check-mask path; CPU share not measured |
| Legal captures | 10 captures | 93M moves/s | 5: tactical subset; includes legality, not pseudo-legal output |
| Make/unmake | 128 move pairs | 36M pairs/s | 6: includes generating the move list; not isolated transition cost |
| Threshold SEE | 10 capture decisions | 31.6M decisions/s | 6: includes capture generation; historical Basilisk 54.4M is a diagnostic, not yet qualified equal-semantic work |
| Start-position perft(4) | 197281 leaves | 239M nodes/s | 5+6: composite generation/transition cost, not search NPS |
| Two-ply simulation | 4597 child legal moves | 323M moves/s | 5+6: composite generation/transition cost |

Both SEE implementations use pawn/knight/bishop/rook/queen/king values
`100/300/300/500/900/20000`. That alone does not prove equal semantics:
Manta selects a legal recapturer using `recaptureIsLegal`; the inspected
Basilisk threshold path uses cached pin filtering and its own swap loop.
Before certifying this cell, compare decisions on the ten frozen captures and
review king/pin/x-ray exceptions against Manta's independent exchange oracle.
Never weaken Manta legality to match a faster approximation. If the existing
benchmark exposes no decision signature, propose only a setup-only signature
check, not a new search experiment. The six-cell target stays unqualified
until this comparison contract is settled.

The historical board record says a general 22–39% gap, but retained exact
per-cell Basilisk medians/MADs and source-bound host metadata were not located.
Do not manufacture a per-cell ranking from that range. Generation is first
because it contributes to five of the six measured cells; transition and SEE
follow after their cost is separated. HCE's historical 3.39M evaluations/s,
18.5 generated moves per searched move and TT/node counts are not CPU shares.
Qsearch visibly generates/ranks quiets it discards; its marginal speed benefit
still requires measurement. No emitted-code speed claim has been made.

**Prospective timing/acceptance protocol.** Freeze routine `bench 13 1` at
30 seconds on the idle designated 5950X: a usability budget, not a prediction
from the old curve. All forty cases and completed depth must be accounted for.
Keep the 64-MiB relative target and six-cell limits above unchanged.

- Pin one physical core, identical affinity/power conditions for each engine;
  record OS, CPU, clocks/power mode, source, compiler, ISA, PGO and binary SHA.
- Board final comparison: three alternating matched process pairs in A/B,
  B/A, A/B order, each using the existing 11-sample protocol. For each cell use
  the median of pairwise throughput ratios, then their geometric mean. Retain
  individual medians/MADs. If pair ratios straddle a target, report unresolved;
  no extra repeats or relaxed threshold chosen after inspecting results.
- Search final comparison: same three-pair order; fresh process per depth,
  `ucinewgame` and `isready` per position, 1T/64 MiB, no ponder/tablebases or
  competing timed work. Each position's wall interval includes reset/readiness
  through `bestmove`, excluding process startup/shutdown. Sum these intervals
  for full and ordinary cohorts; retain nodes and reported UCI time separately.
  Use median pairwise elapsed ratios for the two <=1.10 acceptance tests.
- Freeze 60 seconds per position, 300 seconds per depth and 900 seconds per
  engine's depth-4–13 sweep. Timeout/incomplete depth is not a fast result;
  stop and retain the diagnostic. A final routine bench over 30 seconds fails
  its separate operational target. The maintainer starts all timing jobs.
- Retained depth-12 JSON shows Manta 170853905 nodes / 129045 ms and Basilisk
  8506949 / 2524 ms. These are historical aggregate diagnostics: reports have
  `engine:null`, no bound host metadata, no depth 13 and no per-position times.
  They cannot substitute for the missing qualified target baseline.

**Frozen regression selection.** Reuse `src/search/observation.zig` v23
(current SHA `64C50D5CE20D08645B9AF3D3527D5EC1DA6A8F85B24188097A7129A42BBA27B4`):
opening-start/castling-pressure, quiet-piece-tension/closed-center,
tactical-wac001/hanging-queen, both file-check evasions, zugzwang-opposition/
locked-wings and both endgames. Retain timing cases 6 and 30 as mate regressions.
Use existing movegen checks/pins/castling/EP/promotion properties, transition
ordinary/special/null/nested restoration tests, SEE legal-exchange/king/pin
oracles, draw repetition/null-boundary/rule-50/checkmate tests and qsearch
stalemate/quiet-only/evasion tests. Freeze legal expectations, not selective
search scores or node counts. Extend only a missing edge case in its owning
implementation ticket; never tailor a fast path to this population.

**Bounded handoff tickets (not implementation authorization).**

- **5-A, Terra High:** inspect `generateFor`, `pinnedPieces`, `generatePieces`
  and native emitted code; identify duplicated king/pin/check work. Propose
  one exact ordinary-path specialization with unchanged legal order. Keep
  king/EP/castling exceptions intact. Gate: independent every-encoding legality,
  partition/order, special-position perft and exact search fingerprint/PV.
  No unchecked operation, new table or layout without a measured/proven need.
- **6-A, Terra High / Astra legality review:** use the accepted generation head;
  inspect `makeNormal` and state/key/checker updates, then one exact duplicated
  work elimination. Gate: independent complete state/delta and nested unmake
  restoration, ReleaseSafe, all six board cells and exact search identity.
  SEE is a separate 6-B ticket after the comparability question above is closed;
  do not bundle unrelated transition and exchange algorithms.
- **7-A, Terra High:** reuse accepted tactical generation in non-check qsearch;
  establish a legal-move witness before stand-pat can mask stalemate, retaining
  every evasion and tactical tie order. Gate: quiet-only/stalemate, checks,
  EP/underpromotion, typed TT/stand-pat authority and exact fingerprint/PV.
  No new pruning margins or history semantics. Performance and final H1 remain
  required by each ticket's parent step; tests are not strength evidence.

**Tool completion and remaining blocker (2026-09-08).** The approved measurement
repairs are implemented. `branching_profile.ps1` schema v2 binds executable,
corpus and optional manifest hashes; records monotonic reset-through-bestmove
time per position, full/ordinary depth summaries and UCI-reported time; enforces
position/depth/run deadlines; and writes an explicit incomplete report before
failing. A one-position depth-one smoke produced a complete bound report; a
one-millisecond depth-13 canary produced an incomplete timeout report.

`board_bench.zig` and Basilisk's source-bound board benchmark now emit the same
opt-in `SEE-CONTRACT-V1` rows outside all timed regions. The new
`compare_board_see.ps1` runs both preflights, requires exactly ten unique
position/UCI-move rows, normalizes generation order, binds binary hashes and
fails on any membership/result difference. The local ReleaseSafe Manta artifact
`C27CAA08...94F5CD` and Basilisk release-pext artifact
`BA8D8B5A...860DBD5` agreed on all 10 threshold-zero decisions. This closes
the frozen-corpus semantic question, not general cross-engine SEE equivalence;
Manta's legal exchange oracle remains authoritative. The Basilisk diagnostic
endpoint is committed at `d0f262765a198c61dc8fe9fdf09db6a733b61fec`.

Reproduction, setup only (no timed samples, search or games):

```powershell
zig build board-bench-bin -Dnative -Doptimize=ReleaseFast
cmake --build D:/code/basilisk/build/release-pext --target board_performance_test
./tools/compare_board_see.ps1 -MantaBench ./zig-out/bin/manta-board-bench.exe -BasiliskBench D:/code/basilisk/build/release-pext/board_performance_test.exe -OutFile ./zig-out/phase65-see-setup.json
```

**Designated-host baseline.** The idle Ryzen 9 5950X ran Windows 11 build 26200
under the recorded Ultimate power plan, with each timed parent/process pinned to
affinity mask `1`. Manta's native ReleaseFast board artifact is SHA
`8ECE9988...C2FAFB`; Basilisk's Clang-22 release-pext board artifact is
`BA8D8B5A...860DBD5`. The setup-only SEE comparison again passed 10/10.

| Board cell | Manta median/s | Basilisk median/s | median pair ratio | target |
|---|---:|---:|---:|---|
| Legal generation | 393,644,600 | 615,801,720 | 0.636 | fail |
| Legal captures | 93,144,489 | 114,560,960 | 0.814 | fail |
| Make/unmake | 35,358,543 | 55,426,787 | 0.640 | fail |
| Threshold SEE | 30,198,468 | 56,923,160 | 0.531 | fail |
| Start-position perft(4) | 245,255,949 | 392,588,067 | 0.625 | fail |
| Two-ply simulation | 322,450,289 | 524,301,686 | 0.615 | fail |

The median-ratio geometric mean is `0.638`; all six cells miss the `0.95`
individual floor. Pair ratios were wholly below the targets, so this is a
resolved baseline deficit rather than timing noise. Generation feeds five
cells, while threshold SEE is the largest isolated ratio gap; Steps 5 and 6
retain that dependency order rather than optimizing SEE first in isolation.

The first Manta profiler-v2 sweep completed depths 4–12. Depth 12 was
`170,853,905` nodes / `133,704 ms` full and `69,374 ms` ordinary. At depth 13,
positions 0–5 completed before mate-heavy position 6 exceeded the fixed 60 s
position deadline; the report is explicitly incomplete. Per protocol, the
remaining alternating sweeps were not run, so neither the full nor ordinary
depth-13 ratio is claimed. The separate pinned `bench 13 1` check timed out at
`30,034 ms` without a completed total. Both search targets therefore remain
open failures; incomplete work is not credited as speed.

Ignored raw evidence lives under `zig-out/phase65-baseline/`: board comparison
SHA `1E28BD94...B2539`, incomplete search report SHA `D240B8E1...F0F26`, routine
bench report SHA `6EC39CA9...1FF94`, and SEE setup SHA `E83F0389...B7F59`.
Step 6.5.4 is complete because identities, targets, contracts and the baseline
outcomes are now frozen. Step 6.5.5 is next; no candidate or SPRT was created.

#### 6.5.5 — Legal generation and attack/check backbone

**Model:** GPT-5.6 Terra High; Astra High for any legality proof change.
**Dependency:** 4. **Files:** `src/chess/movegen.zig`, `queries.zig`,
`attacks.zig`, relevant board tests; transition/state only for shared facts
explicitly approved in the ticket.

1. Follow `generateFor`, `pinnedPieces`, king safety and evasion masks.
   Specialize the common unpinned/non-check path; compute position-wide
   king/check/pin facts once per valid position, not once per candidate move.
   A reused fact has an explicit invalidation boundary at every real/null move.
2. Keep legal tactical and quiet subsets exhaustive, disjoint and in the
   accepted filtered generation order. Do not replace legal generation with
   speculative pseudo-legal counts to improve the board score.
3. Preserve exact double-check king-only evasions, pin-ray mobility, king
   destination attacks with changed occupancy, castling transit/final safety,
   EP's two removed pawns and all promotion choices. Never infer king safety
   solely from attack maps computed with stale king occupancy.
4. Inspect native attack lookup/inlining and repeated bounds/classification
   work; PEXT already exists. Adopt an ISA-specific change only with exact
   scalar fallback and measured emitted-code benefit, not a language-based
   expectation that Zig must be faster.

**Gate:** legal-set/order oracle, perft, randomized state recomputation and
special-move safety; exact full-search fingerprint/PV/results. Measure all
board cells plus fixed-tree full-search throughput. Retain only a resolved
cost improvement and final 1T H1 under the common package rule.
**Handoff to 6:** documented reusable facts and ownership, not a new search
policy or a broad representation rewrite.

**2026-09-08 execution checkpoint — complete, no retained candidate.** Four
bounded forms of the same generation/attack-path hypothesis were measured in
three pinned A/B, B/A, A/B pairs and removed after refutation:

- A compile-time unpinned/non-check specialization removed redundant masks and
  the pinned-pawn loop. Legal-generation ratios `1.002/0.965/1.015` crossed
  parity. Although capture generation and perft medians were `1.048` and
  `1.038`, make/unmake and two-ply simulation were `0.991` and `0.981`.
  Fixed-tree depth-eight search kept exactly `4,565,886` nodes but elapsed
  ratios were `1.012/1.011/1.026`; isolated cells did not translate to search.
- Forcing that pawn specialization inline made legal generation `0.958` and
  make/unmake `0.935`; it was immediately rejected as code-growth harm.
- Reusing one immutable enemy piece-class set across king-destination queries
  put every six-cell median below parity (`0.942` perft, `0.958` generation).
- Directly inlining the native slider lookup into legal generation remained
  unresolved/negative: generation `0.985`, perft `0.996`, simulation `0.992`,
  with individual pairs crossing parity. No emitted-code assumption overruled
  the measurements.

Both feature-off and candidate builds passed `test-fast`; candidate search
retained fingerprint `775451`, and the temporary direct-slider path also passed
the exhaustive independent occupancy oracle. All experimental source/build
switches were then removed, leaving production source unchanged. No candidate
qualified for registration, so no SPRT was prepared or run. The result closes
this bounded ticket without claiming the board target: generation remains a
measured deficit, and Step 6.5.6 starts from unchanged production rather than
from a locally attractive isolated benchmark result.

#### 6.5.6 — State transitions, SEE and board parity checkpoint

**Model:** GPT-5.6 Terra High; Astra High for SEE legality semantics.
**Dependency:** 5's accepted facts, or unchanged production if 5 was rejected.
**Files:** `src/chess/transition.zig`, `state.zig`, `position.zig`,
`queries.zig`, `see.zig`, board tests.

1. Profile ordinary relocation/make-unmake and state-copy/update cost. Remove
   demonstrably duplicated occupancy, key, checker or material work while
   preserving the factual move delta used by HCE and the later NNUE runway.
   Keep quiet/capture/promotion/castling/EP/null paths independently accountable.
2. Reuse move class, victim, attack and pin facts in threshold SEE where valid.
   Preserve legal least-attacker selection, pinned recaptures, king captures,
   x-ray discovery, promotion value and EP occupancy. A threshold early return
   needs an inequality proof, not equality to the current implementation.
3. Validate exact undo of mailbox, bitboards, occupancies, side, kings, castling,
   EP, material, Zobrist, checker, rule-50 and repetition state. Preserve
   evaluator callback order, root/null history boundaries and cancellation.
4. Re-run the frozen six-cell comparison once implementation freezes. Report
   geometric mean and every cell against Basilisk, plus full-search throughput.
   If the board target is missed, identify the remaining measured owner and
   propose a bounded follow-up here; do not hide it behind search gains.

**Gate:** independent make/unmake recomputation and SEE exchange oracle,
ReleaseSafe, exact fingerprint/PV/results, controlled native A/B, final 1T H1.
Exact changes sharing one derived-state invariant may form one preregistered
package with 5; independent primitives are not bundled by default.

**2026-09-09 execution checkpoint — complete, no retained candidate.** The
bounded transition and SEE duplicate-work hypotheses were tested independently
and removed after their end-to-end evidence failed:

- Passing the already-known mover/victim into physical make/unmake updates
  avoided mailbox rediscovery and improved the isolated make/unmake cell in all
  three alternations (`1.018/1.089/1.084`). It did not transfer coherently:
  perft's median ratio was `0.956`, other composite cells crossed parity, and an
  exact-tree depth-six search alternation was about `1.021x` slower by elapsed
  time. The node fingerprint remained `775451`.
- Reusing the initial capture classification in threshold SEE preserved the
  legal exchange oracle, but its paired threshold-cell ratios were
  `0.964/1.028`. That unresolved interval provides no speed claim and did not
  justify a whole-search candidate.

ReleaseSafe `test-fast` passed while evaluating both exact forms. Final
`transition.zig` and `see.zig` are byte-identical to the accepted production
source; therefore the frozen designated-host board result remains authoritative:
geometric mean `0.638`, with all six cells below the `0.95` floor. No candidate
qualified for registration and no SPRT was prepared or run.

The remaining deficit is not assigned to another speculative state rewrite.
Generation still contributes to five composite cells, while threshold SEE is
the largest isolated ratio gap; this benchmark also folds generation into both
named cells and exercises SEE only at threshold zero. Step 6.5.13 must refresh
the profile on the accepted search head, add transition-only and representative
search-threshold attribution only if still needed, and select the single largest
measured owner. This is the bounded board follow-up; the now-complete Step 6.5.7
does not conceal the open board target behind reduced qsearch work.

#### 6.5.7 — Qsearch work proportional to tactical search

**Model:** GPT-5.6 Terra High. **Dependency:** accepted board head.
**Files:** `src/search/baseline.zig` qsearch, `ordering.zig`,
`src/chess/movegen.zig` only for a necessary legality-existence interface.

1. Replace non-check qsearch's full legal generation and quiet ranking with
   tactical-only generation/selection. Reuse the accepted board facts and
   tactical/quiet partition instead of implementing a second move generator.
2. Preserve stalemate: no tactical moves does not mean no legal moves.
   Before stand-pat can mask stalemate, establish a legal-move witness through
   a bounded existence query or equivalent proven contract. Checkmate still
   requires complete legal evasions; all evasions are eligible for search.
3. Preserve TT move eligibility, tactical tie order, SEE/delta decisions,
   stand-pat and searched-bound provenance, draw precedence, promotions/EP and
   exact terminal stores. Do not add qsearch pruning or change margins here.
4. Avoid duplicate legality scans and eager ranking at stand-pat cutoffs while
   retaining the terminal witness. Measure saved generation/ranking work and
   whole-search elapsed/NPS, not just generated/searched move ratios.

**Gate:** stalemate with/without pseudo-legal captures, quiet-only legal moves,
checks, promotions and EP; exact fingerprint/PV/results; controlled full-search
speed gain and final 1T H1. Legal behavioral mismatches require diagnosis and
a playing classification, not silent relaxation of this exact ticket.

**2026-09-09 completion checkpoint — accepted and promoted.** `MAN-S34`
implements the exact tactical-only non-check
qsearch path specified by ADR-0069. It reuses the accepted `.tacticals` and
`.non_tactical_quiets` partition in one `MoveList`: a tactical is immediately a
legal witness; only an empty tactical list triggers quiet generation, whose
count proves mobility before the list is reset without ranking. Checked nodes
retain the complete `.all` evasion list. No pruning, score, bound, provenance,
depth, history, allocation or thread authority changed.

The independent full-legal-list test covers actual stalemate, quiet-only
mobility, a legal capture and checked quiet evasions. Candidate-on and off
ReleaseSafe gates pass, including the full suite and all 24 UCI process cases.
Across the twelve frozen observation cohorts, both arms have identical best
moves, scores, bounds, provenance, main/qsearch node split and total nodes.
Generated moves fell from `6,974,800` to `3,023,797` (`-56.65%`). Three-order
native ReleaseFast comparisons retained fingerprint `775451`; representative
median NPS was about `1.34x` production (`1,572,922` versus `1,173,148` in the
final recorded pair). This is exact-cost qualification, not strength evidence.

Frozen setup identities:

| Arm/input | Identity |
|---|---|
| Candidate A | `tools/test_engines/manta-MAN-S34-candidate.exe`, SHA-256 `7707EF8832650603C145A05C2CAB1DDC2C669BA4F3BDDE9A007938881F598B78`; native ReleaseFast Zig 0.16.0; qsearch tactical generation on; bench `775451` |
| Baseline B | `tools/test_engines/manta-MAN-S34-baseline.exe`, SHA-256 `D73FA1D181BDDB8DB7E9AC16FCB053E9866D96707DB6C12D2FBFA36DAA1A03BC`; identical settings with qsearch tactical generation off; bench `775451` |
| Source state | HEAD `a500d6b3c37696b304c65a94d69bb1cf3b05d169`, tree `232593be935860e98fa5ab9a5df63eaac7db6f99`, executable-source/tool diff identity `1a88898fdc26e737eee39ba3a3c9cf5d25f7f153`; both sidecars explicitly record the dirty state |
| Harness/book | `sprt.ps1` SHA `487836C5068B1C3652A66D9D72EB886808F9F66451BE1F97AE629C9C45898BF1`; fastchess SHA `8444E73965AE44E716CDE1BB546A7D7C8C9FC7A442A44194A0C71A3BFFA7DD0D`; UHO book SHA `7A7F6470615A69C6CF23D565417701D38732876F480AF90D67B42ABADE35644A` |

The unchanged trusted 5950X/fastchess boundary required no pilot. The final
registered 1T `3+0.03`, 64-MiB, concurrency-14, normalized `[1,5]` SPRT with
seed `751289825` accepted H1 at the official 1,614-game decision snapshot:
W/L/D `505/320/789`, pentanomial `[23,150,321,245,68]`,
`+59.77 +/- 16.95` nElo (`+40.00 +/- 11.45` Elo), LLR `2.95`, LOS `100%`.
No completed time forfeit or engine, protocol or affinity anomaly occurred.
Two already-running games completed after the boundary, so the retained PGN
and full log contain 1,616 games; they are completion evidence, not a change
to the 1,614-game SPRT verdict. The artifacts are
`tools/results/sprt_MAN-S34_vs_MAN-S30_20260909_082719.{log,pgn}` with their
candidate, baseline and run manifests.

MAN-S34 is production by default. Explicit
`-Dqsearch-tactical-generation=false` reconstructs MAN-S30's full qsearch
generation for archived diagnostics. Both arms retain fingerprint `775451`.
Step 6.5.7 is closed; Step 6.5.8's subsequent design closure is recorded below.

#### 6.5.8 — Modern search design and one evidence/depth contract

**Model:** GPT-6 Astra XHigh. **Dependency:** accepted 7 head.
**Files:** SEARCH_COVERAGE, owning ADR/requirements, PLAN; read
`baseline.zig`, `types.zig`, `ordering.zig`, `tt.zig`, `params.zig`.
**Complete, 2026-09-09. This is a design ticket, not a game candidate.**

[ADR-0070](docs/adr/0070-shared-search-evidence-and-depth.md) is the frozen
implementation contract: concrete fact interfaces and lifetimes, ordered
node/move pipeline, signed horizon arithmetic, consumer eligibility/authority,
feedback admission, package boundaries and independent legal edge-case gates.
SEARCH_COVERAGE records the source-bound reference check and current gaps.
The approved design leaves production MAN-S34 and fingerprint `775451`
unchanged. Step 6.5.9 is next, not a playing candidate or SPRT preparation.

Verification: `git diff --check` passes. `zig build policy` reports no issue in
this step's documents, but repository-wide success is blocked by three unchanged
bench-contract reference-name violations in `docs/adr/0021-search-benchmark-and-qualification.md`,
`docs/UCI.md` and `tests/uci/README.md`. These are already present at the source
head above; no policy repair is bundled. The design is complete. The separate
repair landed on 2026-09-12: the two format documents now cite ADR-0021
instead of naming the outside engine, that ADR is allowlisted as the design
record, and `zig build policy` passes repository-wide.

Write a Manta-native node/move pipeline from the pinned modern reference:
terminal/draw and mate bounds -> authenticated TT/static evidence -> safe
node-level pruning -> ordered legal candidates -> prospective move depth ->
shallow pruning -> extension/reduced probe -> required re-search -> one
authoritative outcome update/store. Specify the exact ordering where a producer
depends on a searched result; never create a circular depth/extension decision.

For each fact, name its producer, lifetime and consumers: raw HCE, ordinary
compatible TT refinement, improving/opponent trend, expected PV/cut/all node,
TT move/depth/bound/PV provenance, root/current window widths, move class,
history strength and sample support, check/evasion state and singular result.
Distinguish nominal depth, extension, reduction, probe depth and verification
depth with signed intermediates and checked/clamped conversion to legal plies.

Cover mature families explicitly: PVS/aspiration, mate-distance window bounds,
TT/IIR, quiet/tactical ordering and outcome feedback, LMR, LMP/futility/SEE,
null/verification, ProbCut, singular/forcing extensions, verified razoring,
upcoming-repetition bounds, qsearch and optional correction history. Existing,
rejected and missing
consumers are different statuses; code behind a disabled umbrella is not
production maturity.

**Gate/output:** frozen interfaces, eligibility/authority table, legal edge-case
matrix and numbered implementation sub-tickets for 9–12. For each candidate
package state why parts interact, what stays off and what refutes the claim.
No copied reference constants, NNUE assumptions, automatic revived switches or
target re-search percentage. Design review must precede smaller-model coding.

#### 6.5.9 — Shared ordering and outcome-evidence substrate

**Model:** GPT-5.6 Terra High for frozen interfaces/tests; Astra High review.
**Dependency:** 8. **Files:** `types.zig`, `ordering.zig`, `baseline.zig`,
`params.zig`, `build.zig` for the default-off diagnostic selector, disabled
observation counters and focused `tests/search_substrate.zig` properties.

Implement these bounded sub-tickets in order, as one behavior-neutral step.
Names, fields and admission rules are in ADR-0070; no coefficient fitting or
new production consumer is part of this work.

**Step 6.5.9 is complete.** Three Astra High authority reviews each rejected a
defect class and each was repaired inside the step; the fourth accepted the
result. The first Astra review rejected the initial
substrate: shadow feedback inherited legacy admission, restrictive scopes did
not survive descendant routes, several shortcuts overstated searched horizon,
move plans did not exactly describe legacy depth use, and `HistoryFacts` was
absent. The second Astra review rejected that repair on five remaining
authority defects: shadow history still admitted alternatives and winners whose
outcome source and scope were unchecked and could not distinguish an entry made
as a reduced probe; restrictive scope was lost on return and draw results never
carried `history_local`; reduced-only and null-verification results reported
nominal rather than actual searched horizon; qsearch outcomes reported
`omitted_siblings = false` despite SEE/delta omissions and lost the stored
producer on a TT cutoff; and only the per-move snapshot existed where ADR-0070
also requires a ranking-time history fact. The third Astra review accepted the
authority and lifetime boundaries and found no evidence leak on any repaired
path, but blocked closure on four certificate-labeling defects and one implicit
design decision: an aggregate that certified exact results with a sibling's
reduced verification and producer; a `reduced_probe` route relabelled
`completed` by the internal null-move or ProbCut verification it returned
through; stored `speculative_cutoff` records labelled exclusion evidence; a
qsearch cutoff inheriting every searched child's omission instead of its
winner's; and no written rule for which certificate describes a completed node.
All were diagnostic-substrate defects, not evidence that production playing
strength regressed. The repeated review confirmed every third-repair fix,
reproduced ADR-0070's admission profile from the substrate's own per-search
counters, and accepted the authority and lifetime boundaries. Its one
documentation correction is applied: the pre-repair admission figures were
produced by module-level probes that accumulated across a whole test binary,
so ADR-0070 publishes only the exact per-search profile and no before/after
comparison. Step 6.5.9 closes; Step 6.5.10 is unblocked.

1. **6.5.9.1 — Exact fact adapters (`types`, `baseline`).** Add `StaticFacts`,
   `TtFacts`, `WindowFacts` and `MoveFacts` views at existing producers. Preserve
   raw/refined separation, original TT producer and unknown PV-origin. Trend
   validity records root/null/exclusion boundaries without changing legacy
   pruning. Keep selected ordinal and actually-searched count distinct; legacy
   policy continues using its existing ordinal. Test absent/stale/decisive TT,
   move-class EP/promotion and perspective/chain-boundary cases.
2. **6.5.9.2 — Depth/outcome observations (`types`, `baseline`).** Record
   `NodeDepthPlan`, `MoveDepthPlan` and `SearchOutcome` at existing dispatch and
   completion boundaries. Observe current check/IIR/singular/probe/verification
   depth; do not move the check wrapper or replace any formula yet. Preserve
   same-ply scratch restoration, origin and scope. Test signed boundary
   arithmetic, reduced-alpha-rise orchestration, exclusion/null re-entry and
   interrupted outcomes. Observation cannot alter PV, TT storage or feedback.
3. **6.5.9.3 — Paired shadow outcomes (`ordering`, `types`, `baseline`).**
   Define ADR-0070's signed value/saturating-support cell and once-only eligible
   update packet. Add `-Dsearch-evidence-observation=false` as the default,
   with no public UCI option. Compile-time-disabled shadows may use existing
   main/reply/continuation keys only; keep current live staging and production updates
   exact. Pair values/counts from identical admitted outcomes. Test searched
   sibling filtering, reset/saturation, root/null boundaries and shared-key
   aliasing. No capture-history revival, new table family or periodic aging.
4. **6.5.9.4 — Integration closure.** Compare default and observation-enabled
   results, PV, node fingerprint and restoration; prove default removes shadow
   allocations/updates, bound diagnostic worker storage and run the owning
   safety gate once after freeze. Update the interface map with actual symbols.
   Astra High reviews the authority boundary before closing the step.

**Gate:** feature-off and observation-on exactness at `775451`, legal PV/result
equivalence, synthetic outcome/reset/chain-boundary tests, allocation and lifetime
checks. Disabled substrate needs no games. Stop and diagnose any mismatch;
do not conceal a playing change in this step. Richer support is not calibrated
confidence and has no initial production consumer in 10.2.

Implementation evidence before review:

- `types.zig` now owns optional static/TT/window/move facts, explicit node/move
  depth plans, scoped outcomes and a bounded signed value/support cell. The TT
  adapter keeps the original producer, generation/freshness and unknown PV
  origin. Static trends require uninterrupted real-move chains.
- `baseline.zig` observes the accepted check/IIR, shallow omission, LMR/PVS,
  null/exclusion and qsearch routes without replacing their formulas. Selected
  ordinal and actually searched count are separate. Final source/scope and
  verification facts are retained; no result, PV, TT or root publication reads
  the observation.
- The `search-evidence-observation` build selector defaults false and maps only
  to a compile-time search feature. The default `SearchEvidenceObservation` is
  zero bytes. Its enabled bounded worker-local storage is at most 128 KiB and
  adds no UCI option. Shadow values/support use exact existing relation keys,
  admit only completed ordinary exact/cutoff quiet outcomes, ignore unsearched
  siblings and avoid double-counting identical shared continuation contexts.
- The repair adds the missing per-move `HistoryFacts` view with separate live
  main/reply/continuation values, exact production keys and optional paired
  shadows. It propagates restricted-root/null/exclusion/ProbCut scope through
  descendants, preserves original TT/search producers across negation, records
  shortcut and verified horizons separately, restores same-ply static facts,
  and admits one deduplicated shadow packet only after a completed non-root
  ordinary exact/cutoff result whose winning child has searched authority.
- `MoveDepthPlan` now records the legacy parent-depth pruning input separately
  from nominal/probe child depth, grants singular depth only to the singular
  move, and names the child wrapper's check grant without moving or consuming it.
- The second repair carries one observation-only completion certificate through
  negation and every recursive return: established producer, actual searched
  horizon, restrictive scope, verification state and inherited omission. A
  parent horizon is derived from that child certificate instead of its own
  active depth, so a reduced-only winner, a null verification and a ProbCut
  cutoff each report the horizon actually searched. Draw and empty-exclusion
  returns take `history_local` and `exclusion` scope, and a stored-producer TT
  cutoff takes the scope its producer implies, so a restriction cannot be
  discarded by returning through an ordinary parent.
- Shadow admission requires that certificate for the winner and for every
  alternative, plus an ordinary main entry route. A reduced probe, restricted
  scope, non-searched producer or short horizon is refused, so unverified or
  speculative evidence cannot train the paired relation.
- Qsearch completion records its own restrictive scope, original producer and
  omitted-sibling fact. SEE/delta omissions and TT cutoffs no longer report a
  complete result under generic returned provenance.
- `HistoryFacts` carries an explicit `ranking`/`depth` observation point.
  Ranking facts are captured when the picker is constructed and when the
  delayed quiet stage is ranked, before any descendant can mutate worker-local
  history; depth facts remain per selected move at its depth decision.
- The third repair makes the returned bound choose the certificate. A fail-high
  and an exact result take producer, horizon and verification from the winning
  move; a fail-low keeps the conservative aggregate; restrictive scope and
  omitted siblings stay aggregated in every case. A probe-only sibling is
  reported through the new `reduced_siblings` fact instead of shortening the
  winner's horizon. The entry route now dominates the verification label, so a
  `reduced_probe` stays `reduced_only` through an internal null-move or ProbCut
  verification. A stored `speculative_cutoff` keeps its producer under ordinary
  scope rather than claiming exclusion evidence, because reverse futility and
  singular multi-cut share that provenance and a record cannot separate them.
  Qsearch cutoffs inherit the winning child's omission, matching the main
  search. ADR-0070 records the rule and its measured admission profile.
Verification used a clean isolated Zig 0.16.0 installed by the repository's
SHA-256-pinned `tools/ci/install-zig.ps1`. The earlier report of a truncated
standard-library file was a host I/O artifact: the named files read intact on
direct inspection, the failure moves between unrelated files, and it recurs at
`-j1`. No toolchain file was modified. Retrying the same command clears it.

The second repair ran the full Debug `zig build test` in both arms, including
all 24 UCI process cases. By maintainer direction of 2026-09-12, full suites are
no longer a routine per-step gate during rapid development; they run before a
release. The third repair therefore ran the gates that verify it: default and
observation-enabled compile checks of every test root, the enabled focused
executable tests covering the new certificate/route/omission properties, and the
deterministic behavior gate. Default and enabled ReleaseFast `bench 6 1` each
produced 40 identical depth/score/node/EBF records and the accepted aggregate
fingerprint `775451`, geomean EBF `4.821`, median `12447` and top share `16.9%`
(`130895`). Single-run time/NPS differ as expected for enabled observation and
make no throughput claim. The three unchanged bench-reference policy violations
listed under 6.5.8 still fail their policy dependency. `zig build fmt` and
`git diff --check` pass. No games, pilot or experiment registration applies.

The accepting review independently reran the gates on the third-repair commit:
default `test-fast` `227/232` with the five enabled-only tests skipped, enabled
`232/232`, only the three known bench-reference policy failures, ReleaseFast
`bench 6 1` at `775451` with all 40 records identical across arms, and clean
formatting and whitespace. Because full suites are no longer a routine per-step
gate, the pre-release run still owes 6.5.9 one full `zig build test` in both
arms; the second repair's full-suite pass plus these focused gates are the
evidence of record until then.

The Astra review owns 6.5.9.4 closure. It must verify that table collisions are
diagnostic drops rather than merged samples; support is lifetime count rather
than probability/recency; shadow reset matches its per-search owner; qsearch,
null, exclusion and restricted-root scope cannot acquire ordinary feedback/TT
authority; and the default-off code is genuinely erased. The repeated review
additionally owns the earlier repaired paths: no reduced, restricted or
non-searched result reaches shadow admission by any entry route; every
restriction, including `history_local` draws, survives recursive return and
negation; every reported horizon is the horizon actually searched; qsearch
reports its own omission and stored producer; and ranking-time history is
observed before descendants can mutate it. It also re-confirms the third
repair: the bound chooses the certificate, a reduced probe keeps that label
through an internal verification, a stored speculative cutoff is not exclusion
evidence, qsearch cutoffs follow their winner, and ADR-0070's recorded
admission profile matches the substrate's own counters. That review is
complete and accepted, so 6.5.9.4 is closed. Step 6.5.10 may begin; it is a
separately approved package and inherits no permission from this step beyond
the frozen contract and the recorded admission profile.

#### 6.5.10 — Coordinated selective-search core

**Redefined on 2026-09-12 by maintainer direction.** The remaining Phase-6.5
search work is one package, `MAN-S36`, designed in
[ADR-0071](docs/adr/0071-coordinated-selective-search-core.md) and contracted
by `SCORE-034`. The maintainer wants a large registered strength gain from this
step; the step is not complete until that gate has run and the continue-or-
release decision of 6.5.14 is recorded. **Model:** Claude Fable owns design,
review and every chess or authority question; Claude Opus implements each
ticket below from the ADR text and reports; Fable reviews before the local
diagnostic match and again before the SPRT is prepared. **Dependency:**
production head `596159e` (MAN-S35, fingerprint `642,336`). **Files:**
`src/search/baseline.zig`, `ordering.zig`, `types.zig`, `params.zig`,
`build.zig`, `tests/search_substrate.zig`, `tests/search_qualification.zig`,
`tests/bench_qualification.zig`; `tt.zig` only if the storage-authority change
needs it. No board, evaluation, UCI, clock or SMP files.

**Search-shape reference.** By maintainer direction the comparison engine for
tree shape is the final pre-NNUE Stockfish pinned in `config/eval-reference.json`
(commit `9587eeeb`), built with the recorded `zig c++` command; the maintainer's
own engines are secondary data points. Baselines measured on the workspace host
on 2026-09-12, forty positions, 64 MiB, 1T, fresh process per depth:

| Quantity | Manta `596159e` | Classical Stockfish `9587eeeb` |
|---|---:|---:|
| Geometric branching, depths 4 to 12 | `2.225` | `1.88` |
| Nodes at depth 12 | `82,249,155` | `2,598,338` |
| Elapsed at depth 12 | `57,494 ms` | `1,321 ms` |
| Depth-12 ordinary-subset elapsed | `55,875 ms` | `1,300 ms` |

Nominal depths are not equal coverage across engines; the branching factor is
the durable comparison. The package's pre-game targets are branching at most
`1.95`, depth-12 nodes at most `25 M`, NPS at least `0.85` of baseline, both
cohorts improving, and a local diagnostic match of at least `+80` Elo.

**Current-mechanism inventory at `596159e`.** Symbols are in
`src/search/baseline.zig` unless noted. Every row changes under the core; the
ADR gives the replacement formulas.

| Mechanism | Present implementation | Under the core |
|---|---|---|
| Quiet history | `recordLegacyQuietCutoff` adds `depth` to a positive-saturating `i16` main table with no malus; reply/continuation use signed gravity with `historyBonus = depth^2`; `balanced_history` bonus/malus path exists but is off | One linear bonus `min(2048, 150*depth - 60)` and equal malus through `updateBounded` for main, reply and continuation; malus only to quiets actually searched before the winner |
| Late-move reduction | `lateMoveEligible`: depth >= 4, `search_index >= 3`, quiet, not in check, not giving check, not singular; `min((depth-3)/3, log2(index+1)-2)` scaled by `116`, plus one, capped at `depth-2`; probe `reduced(depth-1, r)`, alpha rise re-searched at `full_child_depth` | Compile-time log-log table in 1024ths with PV/improving/cut/TT/history/root adjustments, from the third selected move at depth >= 2, quiets and losing captures, clamped to `[0, new_depth]` so a probe may run in quiescence; dispatch shape unchanged |
| Shallow move omission | `shallowMovePruneEligible`: non-PV zero window, `search_index != 0`, parent `depth <= 3`, non-pawn material; LMP/futility/SEE read parent depth | One prospective depth `pd = max(0, new_depth - estimated reduction)`; LMP, futility and losing-capture SEE to `pd <= 8`, history pruning to `pd <= 6`; guard is one move actually searched; LMP trigger skips the node's remaining quiets |
| Omission fail-low storage | `speculativeStoreValue` relabels a pruned fail-low as `reduced_search` and `tableDepth` stores it one ply shallower | Ordinary upper bound at nominal depth; the omission stays a diagnostic fact |
| Reverse futility, razoring | RFP at `depth == 1` only with margin `68`; razoring parked at depth 1 | RFP to depth 8 with `68*depth + 50*depth*(not improving)`; razoring to depth 3 with `200*depth` through quiescence |
| Null move | Fixed `R = 2`, minimum depth 4, verification at every fail-high at `depth - R` with null disabled | `R = 3 + depth/4 + min(3, (eval-beta)/200)` from depth 3; fail-high below depth 10 cuts without verification; from depth 10 the existing verification decides |
| IIR | PV node, depth >= 5, no TT move | Every node type, depth >= 4, no legal TT move |
| Aspiration | `features.aspiration = false` (MAN-R02 stability gate, symmetric doubling) | `core_aspiration`: `delta = 20 + |s|/32`, failed-side widening, geometric growth, one side opens fully after four failures; only exact attempts commit |
| Unchanged | ProbCut (`depth >= 5`, margin `103`, reduction 3), singular extension, check extension, quiescence, TT format, publication, clock, SMP | Same |

Sub-tickets, in order. 6.5.10.1 is complete; 6.5.10.2 is approved for
implementation by this redefinition; 6.5.10.3 and 6.5.10.4 follow without a
further approval step but each records its outcome here before the next begins.

**6.5.10.1 frozen contract.**

1. Placement is the existing MAN-S32 slot: non-root, after `isSearchDraw`
   and the max-ply exit, before `probeTable`. Compute `lower = matedIn(ply)`
   and `upper = mateIn(ply+1)`, then `alpha' = max(alpha, lower)` and
   `beta' = min(beta, upper)`. When `alpha' >= beta'` return the existing
   proof; otherwise the node continues with `alpha'/beta'` as its window, so
   the TT probe, null/ProbCut/static windows, the move loop, the PVS test and
   the final bound classification all read the narrowed window. Root never
   narrows; completed-root, aspiration and root-confidence logic are untouched.
2. Bound authority: a result at or below `alpha'` is `.upper`, at or above
   `beta'` is `.lower`, between them exact. These remain valid against the
   caller's wider window because no score reachable from this ply lies in the
   clipped ranges; that is a SCORE-004 arithmetic property, tested from the
   rules rather than from the implementation. TT storage keeps the existing
   `scoreToTable` normalization and format. A checkmated or stalemated node
   inside a narrowed window still returns within the clipped bounds.
3. Zero windows are unchanged from MAN-S32 by the existing equivalence
   property; the new behavior is confined to PV windows: the first ply below
   root, `pv_research` children and full-window aspiration retries. The
   default `-Dsearch-evidence-observation=false` arm records nothing; the
   enabled arm records the narrowed window as the invocation's current width.
4. Proposed selector, to confirm at ticket start: replace
   `features.mate_distance_pruning` and `-Dmate-distance-pruning` with
   `features.mate_windows` and `-Dmate-windows`, default off. The crossing-only
   arm is removed rather than kept as a third configuration, because ADR-0070
   states it is not the contract and two default-off mate switches would create
   an untested combination. MAN-S32 keeps its historical registration. The off
   arm must reproduce `775,451`, identical PV and results.
5. Tests, each with an independent oracle: forced mates for both sides at
   several plies giving identical mate distance and legal PV in both arms;
   the window property in item 2 over crossing and non-crossing windows,
   including a PV window that narrows without crossing; a scripted child that
   confirms the returned bound is valid against the unnarrowed window; mate
   bounds stored under a narrowed window and read back through the TT; root
   mate positions (corpus indices 6 and 30) completing with the same best move
   and score in both arms; terminal nodes inside a narrowed window.
6. Evidence before games: `zig build search-attribution` and
   `tools/branching_profile.ps1` over the forty positions in both arms,
   reporting the full corpus, the ordinary subset and the two mate cases
   separately, with nodes, elapsed and NPS as separate columns. A mate-cohort
   saving is expected and is not ordinary-position strength.
7. Gate: focused tests, off-arm fingerprint, then one registered 1T SPRT of
   the on arm against this head under the unchanged trusted harness. The
   candidate takes the next free `MAN-S` identifier when it is frozen; nothing
   is registered now. 10.2 rebases on the accepted arm either way.

**6.5.10.1 implementation record (2026-09-12).** Implemented as frozen, with
one clarification the contract did not state and the code now documents. The
clip drops *both* band edges from the searched window, because a window is an
open interval: `alpha' = matedIn(ply)` excludes being mated on this ply and
`beta' = mateIn(ply + 1)` excludes mating on the next. Neither exclusion loses
a searchable outcome. A node that still has a legal move cannot score
`matedIn(ply)` -- that value requires no legal move at all, and the terminal
rule decides it above the window -- and a result that reaches `mateIn(ply + 1)`
is the fastest mate the ply can hold, so the fail-high lower bound it returns
is already the whole truth rather than a window artifact. Every score strictly
inside the band keeps the same membership in the clipped and requested windows,
which is what keeps a bound proven against the clipped edges valid for a caller
holding a wider one.

`features.mate_distance_pruning` and `-Dmate-distance-pruning` are replaced by
`features.mate_windows` and `-Dmate-windows`, default off; `mateDistanceBound`
becomes `mateWindow`, returning either the two unchanged crossing proofs or the
clipped window. `negamaxNode` now searches that window, and the invocation
reports it back so enabled observation records the width its own consumers
read rather than the width requested. `MAN-S32`'s crossing-only arm is gone,
ADR-0067's retention decision is marked superseded, and `SCORE-033` owns the
mechanism.

Gates that ran on the designated 5950X. Focused and full `zig build test` pass,
including the rewritten band/clip properties, zero-window equivalence, both-side
mate distance, terminal precedence, clipped-window table round trip and corpus
mate-position identity. Native ReleaseFast `bench 6 1` reproduces `775,451` in
the off arm and records `642,336` in the on arm, replacing `MAN-S32`'s frozen
`642,394`: the complete clip narrows open principal windows that the crossing
test could not touch. `zig build fmt`, `zig build policy` and `git diff --check`
pass. No games have been run.

Evidence before games, from `zig build search-attribution` (depths 4-10, 64 MiB,
40 positions) and `tools/branching_profile.ps1` (same range, fresh process per
depth, engines `manta-6510-baseline` / `manta-6510-candidate`). Both harnesses
report identical node counts, so the cohorts below are one measurement seen
twice. Nodes, elapsed and NPS are separate columns on purpose.

| Cohort | Depth | Nodes off | Nodes on | Change |
|---|---:|---:|---:|---:|
| Ordinary 38 | 6 | 639,198 | 638,250 | `-0.15%` |
| Ordinary 38 | 8 | 3,280,907 | 3,266,629 | `-0.44%` |
| Ordinary 38 | 9 | 6,491,409 | 6,373,812 | `-1.81%` |
| Ordinary 38 | 10 | 14,063,000 | 14,091,873 | `+0.21%` |
| Mate 6 and 30 | 8 | 1,143,314 | 38,321 | `-96.65%` |
| Mate 6 and 30 | 10 | 12,715,901 | 1,459,111 | `-88.53%` |
| Full corpus 40 | 10 | 26,778,901 | 15,550,984 | `-41.93%` |

The full-corpus total is the attribution error this ticket was told to avoid:
`-41.9%` at depth 10 is almost entirely the two mate positions. On the ordinary
subset the effect is within half a percent at every depth, positive at depth 10,
and only 13 of 38 ordinary positions change at all -- those whose trees contain
a mate score somewhere. Two of them move substantially in opposite directions
(position 33 `-25.2%`, position 38 `+33.2%`), which is legal window-dependent
behavior, not a saving. Ordinary elapsed time is noise-dominated: the
in-process sweep read `-2.95%` at depth 10 while the first cross-engine run read
`+7.11%`, and repeated depth-10 runs gave baseline `11,709 / 12,787 / 12,156` ms
against candidate `12,541 / 12,360 / 12,389` ms, so the candidate's spread lies
inside the baseline's own. No ordinary throughput change is claimed in either
direction, and none of this is strength evidence.

**6.5.10.1 gate and closure (2026-09-12).** The registered 1T SPRT ran on the
designated 5950X from the prepared arms: candidate SHA-256
`82CA7B3396B0C84948838E3358F01937497BDA5A7DE521C0BF217DA606B0D125`
(`-Dmate-windows=true`, bench `642,336`) against the same-source baseline
`04C0F60117D6B6A54AFDEB8BF76195DC75C09F6ACEF9CC18D942B1ADE577FFE4`
(bench `775,451`), 1T `3+0.03`, Hash 64 MiB, concurrency 14, paired randomized
UHO, normalized `[1,5]` at alpha/beta `0.05`, seed `1079633543`. The maintainer
stopped it at 1,998 games: W/L/D `484/461/1053`, `+4.00 +/- 9.32` Elo
(`+6.54 +/- 15.23` nElo), LLR `0.23`, no anomaly of any kind. The interval
straddles zero. That is neither H0 nor H1; it is a neutral result.

**The mechanism is production by an explicit maintainer exception, not by the
gate.** The recorded reasons are that the result is neutral to slightly
positive and that the change completes a previously functional feature rather
than introducing a speculative one. The gate itself was misdesigned: gainer
bounds were registered for a mechanism whose own pre-game evidence already
predicted no ordinary-position gain, and a non-regression design should have
been chosen prospectively, before any games ran. That error is recorded here so
it is not repeated. **The exception is not precedent.** Only H1 promotes; a
neutral or H0 candidate is not retained on judgment again without the
maintainer making that same call explicitly.

Promotion changes the deterministic identity. `features.mate_windows` and
`-Dmate-windows` default on, production `bench 6 1` is `642,336` with geomean
EBF `4.703`, upper median `12,201` and top share `16.1%` (`103,615`), and the
switch-off arm reconstructs the superseded `775,451` tree exactly. Every
archived reconstruction in `tests/bench_qualification.zig` pins the switch off
through `runArchived`, so each historical fingerprint still names the head it
was measured on; MAN-S33 and MAN-R02 pin it off for the same reason. Focused
and full `zig build test`, `zig build fmt`, `zig build policy`, `zig build lint`
and `git diff --check` pass.

**6.5.10.2 — Implement the core (Opus, from ADR-0071).** Work the tickets in
this order. Every ticket ends with: both arms compile (`zig build check` with
`-Dselective-core=false` and `true`), the off arm reproduces `642,336` in
native ReleaseFast `bench 6 1` with identical PV and results, the ticket's
focused tests pass, and one commit. Do not tune the ADR's seed constants by
hand; a changed seed needs a demonstrated defect and a recorded reason. Do not
read other engines' sources; the ADR is the contract.

- **A. Switches.** Add `-Dselective-core` and `features.selective_core` plus
  the five component flags `core_history`, `core_lmr`, `core_move_pruning`,
  `core_node_pruning`, `core_aspiration`, each effective only when the umbrella
  is on. Extend the feature-ledger test, `build.zig` option plumbing and
  `tests/bench_qualification.zig`'s `runArchived` so every archived fingerprint
  pins the umbrella off. The core requires `live_history_staging`; make the
  incompatible combination a compile error.
- **B. `core_history`.** `historyBonus` per ADR A; main history moves to the
  bounded gravity update with bonus to the exact or cutoff quiet winner and
  malus to every quiet actually searched before it, collected at every node
  regardless of reply context; reply and continuation keep their producers.
  Killers and ranking weights unchanged. Tests: bonus bounds and monotonicity,
  gravity stays within `history_limit`, only searched quiets are penalised,
  winners at exact PV nodes are rewarded, killers rotate as before.
- **C. `core_lmr`.** Comptime log-log table, one `coreReduction` returning
  1024ths from a named-input struct, eligibility per ADR B, the `stat` input
  from the picker's ranking value, root relief, and the clamp to
  `[0, new_depth]` at dispatch (a zero probe depth enters quiescence through the
  existing depth-zero dispatch). Reduced fail-lows keep `reduced_search`
  provenance and the reduced TT depth. Under the core the archived
  `dynamic_lmr`, `lmr_desaturation`, `lmr_synchronization` and `history_lmr`
  paths are not consulted. Tests: table monotonic in both arguments, sign of
  each adjustment, clamp bounds, first two selected moves never reduced, checks,
  promotions, good captures and the singular move never reduced, every reduced
  alpha rise verified before PV, cutoff or feedback authority, and a zero
  reduction behaving as the ordinary scout.
- **D. `core_move_pruning`.** Pre-make estimate with `gives_check = false`,
  `pd`, the four omission rules per ADR C, `skipQuiets` on the live picker
  after the first late-move-count trigger (bad captures still emitted), and the
  storage change: a fail-low with omitted siblings stores as an ordinary upper
  bound at nominal depth under the core. Tests: `pd <= new_depth`, no omission
  before one move actually searched, no omission of a checking move after
  make, no omission at PV nodes, in check, under decisive windows or without
  non-pawn material, skipped quiets counted as omitted, remaining bad captures
  still searched, and the nominal-depth upper-bound store.
- **E. `core_node_pruning`.** RFP to depth 8, razoring to depth 3 through the
  existing parked path, null move per ADR D with no verification below depth
  10 and the existing same-node verification from depth 10, mate-range null
  scores clamped to beta, and all-node IIR at depth >= 4 without a legal TT
  move. Tests: no null move without non-pawn material, in check, at PV nodes or
  directly after a null; verification subtree cannot null-prune at its root;
  RFP and razoring refuse PV, check, exclusion and decisive windows; IIR never
  fires at exclusion nodes; the existing zugzwang, fortress and tactical
  canaries; WAC.001 `g3g6` at depth 5.
- **F. `core_aspiration`.** A new root window per ADR E, separate from the
  archived MAN-R02 path: only exact attempts commit, root evidence resets per
  attempt, the retained completed result survives cancellation mid-retry, and
  a mate or tablebase previous score uses the full window. Tests: bounded
  attempt count, scripted fail-low and fail-high sequences, cancellation.
- **G. Integration diagnostics.** With the mechanisms frozen, run once and
  report as one table in this section: both-arm `bench 6 1`;
  `tools/branching_profile.ps1` depths 4 to 12 at 64 MiB in both arms
  (branching, depth-12 nodes, elapsed, NPS, ordinary and mate cohorts);
  `zig build search-attribution -- --min-depth 4 --max-depth 10 --hash 64` on
  the core arm (LMR probe share, re-search rate, each omission rule's share
  with its eligibility denominator, null attempts, cutoffs and verifications,
  aspiration retries); the tactical canaries; one full `zig build test` per
  arm. Then the local diagnostic match on this workstation, authorized by this
  plan as a design diagnostic and not as a gate:

  ```bash
  pwsh -NoProfile -File .\tools\sprt.ps1 -EngineA .\zig-out\manta-core.exe -EngineB .\zig-out\manta-base.exe -NameA MAN-S36-core -NameB MAN-S35-base -Mode fixed -Games 500 -Concurrency 8 -TC 3+0.03 -Hash 64
  ```

  Report W/L/D and the Elo estimate. Below `+30` Elo, stop and run the ADR's
  ablation order once; between `+30` and `+80`, stop for review; at or above
  `+80`, proceed to review. Do not run anything on the designated host.

Stop rules for Opus: any legality, PV, terminal or restoration failure stops
the ticket; a changed canary is recorded with its cause, never re-blessed or
deleted silently; a fingerprint change in the off arm is a defect; questions
about authority or chess semantics stop for Fable rather than being resolved
by guess.

**6.5.10.3 — Review loop (Fable).** Review the implementation against ADR-0071
and `SCORE-034`: verification before PV, cutoff, TT or feedback authority;
provenance and scope through negation; null-verification scope; exclusion-node
behavior; the omission storage change; every legality exemption; arithmetic
at saturation and negative 1024ths; plausibility of the G diagnostics with
their denominators; and test independence. Each finding returns to Opus as a
bounded repair that re-runs its ticket gate and the affected G rows. The loop
ends when Fable records acceptance here with the final diagnostic table.

**6.5.10.4 — Registered gate and decision.** Prepare `MAN-S36` per the
EXPERIMENTS template: candidate `-Dselective-core=true` against the same-source
baseline, both native ReleaseFast with recorded SHA-256, bench fingerprints
and manifests; 1T `3+0.03`, Hash 64 MiB, concurrency 14, paired randomized
UHO, normalized `[1,5]` at alpha/beta `0.05`, 16,000-game cap, setup-only
preflight, every fault fatal, no pilot. The maintainer runs it on the
designated host. H1 promotes: the umbrella defaults on, the new fingerprint is
recorded, the off arm keeps reconstructing `642,336`, the archived fingerprints
stay pinned, and `SCORE-034`, EXPERIMENTS, GUIDE and this section are
reconciled. H0 or the cap does not promote: one ablation cycle in the ADR's
order is permitted, then a re-plan. After the verdict the maintainer records
in 6.5.14 whether Phase 6.5 continues through 6.5.11 to 6.5.13 or Manta
releases 1.1.0 on the accepted head and freezes.

#### 6.5.11 — Fit of the accepted core (conditional, expected)

**Model:** Fable designs the coordinate set; Opus wires the tune-only registry.
**Dependency:** accepted 6.5.10 and a maintainer decision to continue.

The core's seeds are order-of-magnitude values, so a joint fit is expected to
be worth its budget once the mechanisms are frozen. Expose only live
coordinates through the existing tune-only `params.zig` registry: table base
and divisor, history divisor, PV/improving/cut/TT adjustments, late-move base,
scale and improving bonus, futility unit, history-prune unit, SEE unit, RFP
margins, razoring unit, null-move base, depth and margin divisors, aspiration
delta and growth, history bonus slope and cap. Exclude categorical switches,
safety and terminal predicates. Use the existing Weather Factory bridge on the
designated host with prospective ranges, iteration horizon and stop rule; the
maintainer runs it. Bake one rounded vector and gate it once as `MAN-S37`.

**Gate:** complete valid checkpoints, bounded active theta, no infrastructure-
contaminated gradients, one final production 1T H1. An inconclusive or rejected
fit leaves the accepted seeds in place.

#### 6.5.12 — Second-order relationships on the accepted core (conditional)

**Model:** Fable derives each package; Opus implements. **Dependency:** the
accepted and, if run, fitted core; a maintainer decision to continue.

Candidates in this order, each its own package with its own diagnostics and one
1T SPRT, each derived on the actual accepted head; deferral or rejection is a
valid closure and nothing is retried automatically:

1. Correction history as a live pruning and reduction input: producer and
   consumers together, re-derived rather than re-enabling MAN-S25.
2. Capture history with a capture-aware SEE pruning threshold and capture
   futility.
3. Singular review: threshold scale, half-depth exclusion horizon, non-PV
   double extension and multi-cut, on the new reduction surface.
4. ProbCut move cap and typed TT proof reuse.
5. Quiet SEE pruning and the upcoming-repetition lower bound.
6. TT replacement and aging review under the new tree.

#### 6.5.13 — Residual full-search cost and board target

**Model:** Opus for profile-owned exact work; Fable for any TT semantic change.
**Dependency:** search head frozen through 6.5.12 or the decision to skip it.

1. Refresh the profile on the frozen tree and rank time in HCE, SEE, picker,
   TT and transition. Fix the largest evidenced residual owner, not every
   listed mechanism.
2. Compare occupied-piece traversal with the 64-square HCE scan and inspect
   the pawn cache before any cache redesign; incremental HCE only on a
   concentrated profile with an exact refresh contract.
3. TT work separates cache-line and prefetch cost from capacity and
   replacement; a changed replacement decision is playing behavior.
4. Measure the six-cell board target against Basilisk on the designated host;
   PGO and LTO are optional and need a reproducible pipeline first.

**Gate:** exact scalar, fingerprint, PV and result identity for exact work,
repeated release-build whole-search timing, applicable concurrency tests, and
one 1T H1 per retained playing change.

#### 6.5.14 — Targets, cumulative gate and release decision

**Model:** Opus collects evidence; Fable performs the final review.
**Dependency:** every prior disposition explicit.

1. Freeze source, binaries, toolchain, feature ledger and fingerprints. Run the
   final correctness, ReleaseSafe and ReleaseFast, UCI, time, SMP lifecycle and
   platform gates once each.
2. On the idle designated host, measure the forty-position depth curve 4 to
   13 for Manta and the pinned classical Stockfish under the identical fresh-
   process protocol, and the six board cells against Basilisk. Record nodes,
   NPS, elapsed, branching, ordinary and mate cohorts and per-position tails.
3. Search target, revised on 2026-09-12: geometric branching over depths 4 to
   12 at most `1.98` against the reference's host-measured value, depth-12
   total elapsed at most `4x` the reference, and routine `bench 13 1` at most
   30 seconds. Board target unchanged from 6.5.4. These are planning targets;
   a miss is an open deficit, never a moved target.
4. Run the cumulative registered 1T SPRT of the final head against immutable
   Manta 1.0.0 as `MAN-C03` on the trusted harness.
5. The maintainer decides: continue Phase 6.5 on the recorded deficits, or
   release Manta 1.1.0 on the accepted head and freeze development. GUIDE
   records the board target, the search target and the strength gate
   separately. Phase 7 still needs its own approval.

**Superseded on 2026-09-12:** the former 6.5.11 forward-proof packages, 6.5.12
evaluation reliability, 6.5.13 residual cost, 6.5.14 conditional fit and
6.5.15 closeout. Their surviving content is owned by the steps above; their
mechanisms that entered the core are governed by ADR-0071.

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
