# Manta Development Guide

This is the maintainer's concise roadmap. Normative behavior lives in
`REQUIREMENTS.md`, design decisions in `ARCHITECTURE.md` and the ADRs, execution
rules in `PLAN.md`, and game/tuning evidence in `EXPERIMENTS.md`.

## Current checkpoint

- Manta 1.0.0 is the release baseline: a complete UCI engine with classical
  evaluation, deterministic one-thread search, Syzygy, mature clock control and
  main-authoritative lazy SMP.
- Phases 0–6 and the Manta 1.0 release baseline are complete. Targeted
  pre-NNUE performance Phase 6.5 is current; Phase 7 remains blocked until the
  whole Phase 6.5 candidate and evidence sequence is complete.
- Production is the MAN-E19 HCE, MAN-S29 search fit, MAN-T05 clock fit,
  MAN-S30 live-history move ordering, MAN-S34 tactical-only non-check qsearch
  generation and MAN-S35 complete mate windows. The deterministic one-thread
  depth-6 fingerprint is `642,336` nodes.
- Step 6.5.4 is complete. On the designated 5950X the six-cell board ratio is
  `0.638`; depth 13 hit the frozen mate-position timeout, and routine bench 13
  exceeded 30 seconds. These are open deficits, not accepted targets.
- Step 6.5.5 is complete with no retained candidate. Common-path, cached-attack
  and inline-slider formulations failed matched board/search timing, were
  removed, and production remains unchanged.
- Step 6.5.6 is complete with no retained candidate. Known-piece transition
  updates helped only the isolated cell and slowed composite/search work; SEE
  capture reuse crossed parity. Both were removed, so the board target remains
  open and production stays at fingerprint `775,451`.
- Step 6.5.7 is complete. `MAN-S34` removes unused quiet generation/ranking
  from non-check qsearch while retaining a complete legal stalemate witness.
  Its registered final 1T SPRT accepted H1 after 1,614 games without anomaly,
  so the mechanism is production and the full-generation arm reconstructs
  MAN-S30.
- Step 6.5.8's shared search design is complete in ADR-0070. Step 6.5.9 is
  complete: four Astra authority reviews, three bounded repairs and an accepted
  authority and lifetime boundary with no evidence leak. ADR-0070 now records
  the decision the reviews found implicit -- the returned bound chooses whether
  a node is certified by its winning move or by the conservative aggregate --
  together with the measured admission profile, which shows the paired relation
  is trained mostly at shallow remaining depth by construction. Default and
  observation-enabled builds keep exact fingerprint parity at `775,451`.
  The repository policy gate passes again after the separate bench-document
  repair of 2026-09-12.
- Step 6.5.10 is open and 6.5.10.1 is complete. `MAN-S35` is production: every
  non-root node searches its window clipped to the mate distances the rules
  still allow, `SCORE-033` owns the mechanism, and MAN-S32's crossing-only
  switch is removed. Its registered `[1,5]` gate was neutral -- maintainer
  stopped at 1,998 games, `+4.00 +/- 9.32` Elo, LLR `0.23`, no anomaly -- and
  the mechanism was retained by an explicit documented maintainer exception,
  not by an H1 verdict. That exception is recorded in `EXPERIMENTS.md` and is
  not precedent for any other candidate. The corpus saving is concentrated in
  the two mate positions (`-88.5%` at depth 10); the ordinary 38-position
  subset moved `+0.21%` and ordinary elapsed time was noise-dominated, so no
  ordinary-position strength is claimed.
- Phase 6.5 was redirected on 2026-09-12. The measured gap is tree shape:
  geometric branching `2.225` against `1.88` for the pinned classical
  Stockfish on the same forty positions, `82.2 M` nodes against `2.6 M` at
  depth 12. Step 6.5.10 is now one coordinated selective-search core,
  `MAN-S36`, designed in ADR-0071 and contracted by `SCORE-034`. 6.5.10.2
  implementation is approved and is next: Opus implements from the ADR, Fable
  reviews, then one registered 1T SPRT decides. After that verdict the
  maintainer decides between finishing Phase 6.5 and releasing 1.1.0.
  Progress: tickets A to D are committed and E is implemented; the first
  review found the core blind to a quiet-move mate threat that the classical
  reference sees through first-ply quiescence checks, so ADR-0071 gained
  component F `core_qs_checks` and ticket E2 precedes F and G.
- No Phase-6.5 implementation step, Phase-7 implementation, games, tuning or
  data generation begins without separate approval.

## Completed phases

### Phase 0 — Clean architecture and project contracts

- [x] **0.0 — Product scope, origin and licensing:** Established Manta as an
  original Zig UCI chess engine under GPL-3.0-or-later.
- [x] **0.1 — Requirements and quality model:** Defined stable requirement IDs,
  correctness invariants and evidence standards.
- [x] **0.2 — Architecture design:** Established inward dependencies, explicit
  ownership and replaceable protocol, search, evaluation and tablebase seams.
- [x] **0.3 — Architecture proof and exit gate:** Verified the repository and
  its policy checks before implementation advanced.

### Phase 1 — Repository foundation and UCI specification

- [x] **1.0 — Toolchain and build spine:** Pinned Zig 0.16.0 and reproducible
  build, format, lint and test entry points.
- [x] **1.1 — UCI behavioral specification:** Defined the complete protocol,
  lifecycle, timing and error contracts.
- [x] **1.2 — Test harness and repository policy:** Added bounded process tests,
  transcript coverage and repository-policy enforcement.
- [x] **1.3 — Artifact build orchestration:** Added native and portable named
  artifacts with explicit platform/profile metadata.

### Phase 2 — Board, state and move generation

- [x] **2.0 — Domain types and representation:** Selected the board/state model
  and documented its invariants.
- [x] **2.1 — State transitions and legality:** Implemented legal move
  generation, make/unmake, hashing, repetition and special moves.
- [x] **2.2 — Correctness campaign:** Passed independent perft, randomized state
  recomputation and terminal/draw validation.
- [x] **2.3 — Board benchmark:** Froze the direct board/SEE diagnostic corpus
  and measurement contract.

### Phase 3 — Classical evaluation foundation

- [x] **3.0 — Evaluation boundary:** Defined score, evaluator and trace
  contracts without leaking infrastructure into the hot path.
- [x] **3.1 — Initial Manta HCE:** Implemented a complete tapered classical
  evaluator with independently tested feature semantics.
- [x] **3.2 — Strategic HCE limit:** Froze a sound fallback before search-led
  development and later evidence-based fitting.

### Phase 4 — Deterministic search, UCI and tooling

- [x] **4.0 — Search correctness baseline:** Added deterministic iterative
  deepening, PVS/alpha-beta, quiescence and legal result publication.
- [x] **4.1 — TT, ordering and diagnostics:** Added transposition storage,
  move-order evidence and bounded search instrumentation.
- [x] **4.2 — UCI baseline completion:** Connected real search, cancellation,
  limits and result handling to the protocol session.
- [x] **4.3 — Bench and test suites:** Froze deterministic bench and full
  correctness, safety and UCI gates; presentation and arguments match Rarog
  while Manta retains its depth-six default.
- [x] **4.4 — Experiment tooling:** Added checked match, SPRT, SPSA and artifact
  workflows; Colosseum remains parked until explicitly re-enabled.
- [x] **4.5 — Test-host qualification:** Qualified the Ryzen 9 5950X harness
  profile and the boundary around shared third-party tooling.

### Phase 5 — Classical search and evaluation convergence

- [x] **5.0 — Functional baseline:** Froze the first tournament-capable
  one-thread engine and representative game gate.
- [x] **5.1 — Search architecture:** Built and measured the final classical
  search head; rejected candidates remain disabled.
- [x] **5.2 — Syzygy and endgames:** Added correct WDL/DTZ probing, root use and
  replacement-safe tablebase ownership.
- [x] **5.3 — Evaluator convergence:** Completed classical feature coverage and
  promoted the fitted MAN-E19 HCE.
- [x] **5.4 — Search/evaluation synchronization:** Closed residual compatibility
  work and promoted the MAN-S29 joint search fit. The cumulative Phase-5 gate
  accepted H1; its short sample proves a material gain, not a precise rating.

### Phase 6 — Time management, robust UCI and SMP

- [x] **6.0 — Clock and root confidence:** Added hard-safe receipt-based timing,
  root evidence and exact once-counted ponder credit.
- [x] **6.1 — Full UCI parity:** Completed option ownership, queued control,
  pondering, live reporting and the full process matrix.
- [x] **6.2 — SMP:** Added main-authoritative lazy SMP and qualified the 4T pool;
  one-thread behavior remains deterministic.
- [x] **6.3 — Integrated time management:** Added telemetry, fitted the complete
  clock surface and promoted MAN-T05. The cumulative MAN-C02 4T-versus-Phase-5
  gate accepted H1; it proves the integrated release configuration materially
  stronger, not a precise rating or component attribution.

## Open roadmap

### Phase 6.5 — Board backbone and integrated search maturity

Two separate goals: rival Basilisk across the six board benchmark cells, and
bring the search tree's branching factor to that of the pinned classical
Stockfish with a mature, coordinated search. PLAN owns the exact targets,
implementation tickets, model assignments and gates. Fewer nodes and higher NPS
are separate diagnostics; registered games still decide promotion. Search
structure and relationships are reimplemented as original Zig with Manta's own
values for Manta's contracts.

- [x] **6.5.0 — Comparable performance audit:** Board and search deficits measured.
- [x] **6.5.1a — Exact staged move picker:** Exact formulation rejected.
- [x] **6.5.1b — Live-history staged picker:** MAN-S30 accepted; production
  fingerprint `775,451`.
- [x] **6.5.2 — Whole-tree attribution:** Work measured; causal overclaims
  corrected. Low re-search frequency alone does not prove safe pruning headroom.
- [x] **6.5.3 — Forcing-line selectivity:** MAN-S31 rejected by judgment, not
  formal H0. Historical MAN-S32 was superseded by 6.5.10.1 and its switch
  removed; MAN-S33 stopped inconclusive and unpromoted. No automatic retries.
- [x] **6.5.4 — Freeze the two targets and implementation contracts:** Bound
  source/build identities, setup semantics, target limits and designated-host
  baselines. Board and search targets currently fail.
- [x] **6.5.5 — Legal generation and attack/check backbone:** Bounded exact
  specializations were refuted by matched timing and removed; the generation
  deficit remains visible for later residual-cost work.
- [x] **6.5.6 — State transitions, SEE and board parity checkpoint:** Narrow
  exact duplicate-work forms were refuted and removed. The `0.638` board
  baseline remains open; residual attribution is explicitly owned by 6.5.14.
- [x] **6.5.7 — Qsearch work proportional to tactical search:** MAN-S34 avoids
  discarded quiet work while preserving stalemate, evasions and exact search
  behavior; its final 1T SPRT accepted H1 and the mechanism is production.
- [x] **6.5.8 — Modern search design and one evidence/depth contract:** ADR-0070
  freezes the shared pipeline, authority and independently gated packages.
- [x] **6.5.9 — Shared ordering and outcome-evidence substrate:** One reliable
  history/TT/move-evidence model for ordering and selective search, behavior-
  neutral and default-off. Three authority repairs closed; the fourth Astra
  High review accepted the authority and lifetime boundaries.
- [ ] **6.5.10 — Coordinated selective-search core:** One package, `MAN-S36`,
  per ADR-0071: informative history, full-coverage log reductions, prospective-
  depth pruning, node-level proofs and root aspiration, gated once.
  - [x] **6.5.10.1 — Complete mate windows:** `MAN-S35` non-root window clip;
    production by maintainer exception on a neutral gate.
  - [ ] **6.5.10.2 — Implement the core:** Opus tickets A to G from the ADR,
    ending in branching, attribution and a local diagnostic match.
  - [ ] **6.5.10.3 — Review loop:** Fable authority and legality review with
    bounded repairs until acceptance is recorded.
  - [ ] **6.5.10.4 — Registered gate and decision:** One 1T SPRT on the
    designated host; then continue or release 1.1.0.
- [ ] **6.5.11 — Fit of the accepted core:** Conditional SPSA of the live
  coordinates and one rounded bake, `MAN-S37`.
  - [ ] **6.5.11.1 — Coordinate set:** Fable freezes the live coordinates and
    ranges; Opus exposes them through the tune-only registry.
  - [ ] **6.5.11.2 — Fit and bake:** Maintainer-run Weather Factory fit on the
    designated host, one rounded vector, one 1T SPRT.
- [ ] **6.5.12 — Evaluator calibration:** The king-danger block was never
  fitted and disagrees with the classical reference by hundreds of centipawns
  in attacking positions; SPSA is necessary but not the whole answer.
  - [ ] **6.5.12.1 — King-danger game fit:** Tune-only exposure of the
    nonlinear king-danger scalars, one Weather Factory fit, one bake, one 1T
    SPRT, `MAN-E22`; residual harness before and after.
  - [ ] **6.5.12.2 — Structural king-attack review:** Only if the attacking
    residual stays above 150 centipawns; one derived candidate, one SPRT.
  - [ ] **6.5.12.3 — Deeper-label linear refit:** Only if the nonlinear block
    changed what the linear terms consume; new corpus at a node budget that
    resolves attacks, refit with the nonlinear block fixed, one gate.
  - [ ] **6.5.12.4 — Correction history as pruning input:** Producer and
    consumers together, re-derived on the core.
- [ ] **6.5.13 — Second-order search relationships:** Conditional follow-on
  packages on the accepted core, each gated alone.
  - [ ] **6.5.13.1 — Capture history and capture-aware SEE and futility.**
  - [ ] **6.5.13.2 — Singular review on the new reduction surface.**
  - [ ] **6.5.13.3 — ProbCut move cap and typed TT proof reuse.**
  - [ ] **6.5.13.4 — Quiet SEE pruning and upcoming-repetition bound.**
  - [ ] **6.5.13.5 — TT replacement and aging review.**
- [ ] **6.5.14 — Residual full-search cost and board target:** Profile-owned
  exact work after the tree freezes; PGO optional.
  - [ ] **6.5.14.1 — Profile and fix the largest residual owner.**
  - [ ] **6.5.14.2 — HCE traversal and pawn-cache inspection.**
  - [ ] **6.5.14.3 — TT cache-line versus capacity and replacement.**
  - [ ] **6.5.14.4 — Six-cell board target on the designated host.**
- [ ] **6.5.15 — Targets, cumulative gate and release decision:** Depth curve
  against classical Stockfish, board cells, `MAN-C03` against 1.0.0, then
  continue or release 1.1.0 and freeze.
  - [ ] **6.5.15.1 — Freeze and final gates.**
  - [ ] **6.5.15.2 — Depth curve and board cells on the designated host.**
  - [ ] **6.5.15.3 — Search and board targets recorded, met or open.**
  - [ ] **6.5.15.4 — Cumulative `MAN-C03` against Manta 1.0.0.**
  - [ ] **6.5.15.5 — Continue or release 1.1.0 and freeze.**

### Phase 7 — NNUE runway and data contract

- [ ] **7.0 — State and accumulator contract:** Freeze feature, perspective,
  bucket, dirty-state and versioned network-format semantics.
- [ ] **7.1 — Trainer and dataset preflight:** Qualify `net_trainer` and define
  reproducible data, training, export and conformance contracts.
- [ ] **7.2 — Runway gate:** Admit only complete, portable NNUE scaffolding that
  is behaviorally inert while disabled.

### Phase 8 — Baseline NNUE

- [ ] **8.0 — Controlled pilot networks:** Train reproducible multi-seed pilots
  and validate files, quantization and untouched metrics.
- [ ] **8.1 — Scalar and incremental integration:** Prove original Zig scalar,
  accumulator and trainer-export parity over realistic games.
- [ ] **8.2 — Portable and vector backends:** Add bit-exact portable, x86-64
  and ARM64 inference implementations.
- [ ] **8.3 — Baseline acceptance:** Funnel candidates through conformance,
  loss and speed, then give the survivor one representative SPRT.

### Phase 9 — NNUE frontier and final search fit

- [ ] **9.0 — Residual and disagreement analysis:** Use untouched errors,
  search disagreements and games to identify real evaluator gaps.
- [ ] **9.1 — Architecture ladder:** Test evidence-led NNUE axes with multi-seed
  conformance, loss, throughput and one promotion gate per survivor.
- [ ] **9.2 — Search/evaluator co-adaptation:** Reopen search assumptions under
  the retained NNUE and permit evidence-led structural changes.
- [ ] **9.3 — Consolidated post-NNUE fit:** Tune only if the necessity review
  and sensitivity pilot justify one bounded checkpointed SPSA run.

### Phase 10 — ISA dispatch, platforms, scaling and release maturity

- [ ] **10.0 — Runtime backend dispatch:** Build one executable capability
  contract around a portable core and measured sibling ISA backends.
- [ ] **10.1 — Native platform validation:** Run and inspect production assets
  on every supported native OS/architecture target.
- [ ] **10.2 — Performance and scaling:** Profile and optimize build, layout,
  cache, TT, vector, topology and scaling behavior.
- [ ] **10.3 — Product completion and releases:** Complete demanded features,
  reproducible artifacts, cumulative evidence and guarded publication.

### Phase 11 — Optional HCE fallback

Enter only after serious NNUE retries fail and the maintainer explicitly
chooses it.

- [ ] **11.0 — Failure review and scope decision:** Document NNUE failure and
  explicitly authorize a narrow fallback program.
- [ ] **11.1 — HCE residual program:** Select only evidence-led HCE work not
  already answered by the NNUE path.
- [ ] **11.2 — HCE fit and release:** Tune only if justified, then gate one
  clean candidate and add release evidence only if it will ship.

## Decision rules

- Correctness and deterministic tests establish validity; registered games
  decide playing-strength changes.
- Keep one independently meaningful mechanism per candidate unless a documented
  dependency makes a bundle indivisible.
- Build and smoke-test all supported release targets natively. Do not claim an
  ISA tier or platform that is not implemented and measured.
- After Step 6.5.10's registered gate the maintainer decides between finishing
  Phase 6.5 and releasing Manta 1.1.0. Phase 7, defining NNUE state, feature and
  accumulator contracts, requires explicit approval in either case.
