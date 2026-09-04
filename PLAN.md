# Manta Engineering Plan

This document tells coding agents how to sequence Manta work and what evidence
closes a step. `GUIDE.md` is the maintainer checklist, `REQUIREMENTS.md` is
normative, ADRs own durable design decisions, and `EXPERIMENTS.md` records
measurement verdicts.

## Current state

Manta 1.0.0 is the release candidate. Phases 0–6 are closed and Phase 7 has not
started. The production engine combines MAN-E19 classical evaluation, MAN-S29
search parameters and MAN-T05 integrated clock parameters. One-thread depth-6
bench is `799,610` nodes. The release configuration supports portable 64-bit
Windows x86-64, Linux x86-64/ARM64 and macOS x86-64/ARM64 artifacts.

No coding agent may start Phase 7, a game match, SPSA, data generation or other
long run without explicit maintainer approval.

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
- Once tournament-capable, one prospectively registered representative SPRT
  decides a playing candidate. H1 promotes; H0 or an unresolved cap rejects.
- A cohesive bundle may be gated only when its parts are inseparable or below
  affordable independent resolution. Its result licenses only the bundle.
- SPSA begins only after consumers freeze and a sensitivity pilot justifies the
  interacting coordinates. The complete rounded vector receives one game gate.

### Tooling and host policy

- Use exactly Zig 0.16.0 until a separately approved stable-toolchain migration.
- Use Manta's checked fastchess bridge for matches and its pinned local Weather
  Factory wrapper for SPSA. Colosseum is parked until explicitly re-enabled.
- The game/tuning host is one Ryzen 9 5950X. Agents prepare bounded resumable
  commands and estimates; the maintainer starts long jobs.
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
work; behavior changes require games.

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
