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
  MAN-S30 live-history move ordering and MAN-S34 tactical-only non-check
  qsearch generation. The deterministic one-thread depth-6 fingerprint remains
  `775,451` nodes.
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
- Step 6.5.8's shared search design is complete in ADR-0070. Step 6.5.9's first
  Astra review found authority, lifetime and missing-history-adapter defects,
  and the second found five remaining ones in shadow admission, recursive scope,
  reported horizon, qsearch outcome metadata and ranking-time history. Both
  bounded repairs and their idle-PC verification are complete with exact
  default/enabled fingerprint parity at `775,451`; the repeated Astra High
  review is next. Step 6.5.10 remains blocked. Three pre-existing bench-document
  policy violations remain; PLAN records the separate repair.
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
reach depth 13 in comparable time with a mature, coordinated search. PLAN owns
the exact targets, implementation tickets, model assignments and gates.
Fewer nodes and higher NPS are separate diagnostics; registered games still
decide promotion. Modern Stockfish supplies search structure and feature
relationships, reimplemented in original Zig for Manta's contracts.

- [x] **6.5.0 — Comparable performance audit:** Board and search deficits measured.
- [x] **6.5.1a — Exact staged move picker:** Exact formulation rejected.
- [x] **6.5.1b — Live-history staged picker:** MAN-S30 accepted; production
  fingerprint `775,451`.
- [x] **6.5.2 — Whole-tree attribution:** Work measured; causal overclaims
  corrected. Low re-search frequency alone does not prove safe pruning headroom.
- [x] **6.5.3 — Forcing-line selectivity:** MAN-S31 rejected by judgment, not
  formal H0. Historical MAN-S32 remains parked; MAN-S33 stopped inconclusive
  and unpromoted. No automatic retries.
- [x] **6.5.4 — Freeze the two targets and implementation contracts:** Bound
  source/build identities, setup semantics, target limits and designated-host
  baselines. Board and search targets currently fail.
- [x] **6.5.5 — Legal generation and attack/check backbone:** Bounded exact
  specializations were refuted by matched timing and removed; the generation
  deficit remains visible for later residual-cost work.
- [x] **6.5.6 — State transitions, SEE and board parity checkpoint:** Narrow
  exact duplicate-work forms were refuted and removed. The `0.638` board
  baseline remains open; residual attribution is explicitly owned by 6.5.13.
- [x] **6.5.7 — Qsearch work proportional to tactical search:** MAN-S34 avoids
  discarded quiet work while preserving stalemate, evasions and exact search
  behavior; its final 1T SPRT accepted H1 and the mechanism is production.
- [x] **6.5.8 — Modern search design and one evidence/depth contract:** ADR-0070
  freezes the shared pipeline, authority and independently gated packages.
- [ ] **6.5.9 — Shared ordering and outcome-evidence substrate:** One reliable
  history/TT/move-evidence model for ordering and selective search.
  **Implemented and twice repaired; next:** repeated GPT-6 Astra High authority
  review.
- [ ] **6.5.10 — Integrated ordering, aspiration and selective depth:** Connect
  mate bounds, root windows, contextual LMR, shallow pruning and forcing depth.
- [ ] **6.5.11 — Forward proofs matched to the accepted depth policy:** Derive
  repetition bounds, null/verification, ProbCut and singular/razoring policies
  on the accepted head.
- [ ] **6.5.12 — Evaluation reliability feeding search, only where justified:**
  Corrected/static evidence and its consumers; no automatic rejected-feature retry.
- [ ] **6.5.13 — Residual full-search cost and build optimization:** Address
  measured remaining HCE/TT/hot-path cost; PGO is optional, not a mandatory project.
- [ ] **6.5.14 — Conditional fit of the interacting accepted search:** Tune only
  frozen, live consumers when justified and separately approved; otherwise defer.
- [ ] **6.5.15 — Separate board/search targets and integrated closeout:** Pass
  board target, comparable depth-13/routine-bench time and cumulative strength
  separately. Missed targets keep the deficit open; Phase 7 needs approval.

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
- The next development step after the Manta 1.0.0 release is **7.0**, defining
  NNUE state, feature and accumulator contracts. It requires explicit approval.
