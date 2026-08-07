# Manta development plan

This is the maintainer-facing source of truth for what Manta will build, in
what order, and with which evidence. [`GUIDE.md`](GUIDE.md) is the short
operational mirror. [`EXPERIMENTS.md`](EXPERIMENTS.md) is the indexed,
conditional evidence ledger. Future `README.md` and `CHANGELOG.md` files are
user-facing and must not become experiment notebooks.

Manta is a new UCI chess engine written in Zig. Basilisk and Rarog are design,
behavioural, test and measurement references; Manta is not a line-by-line port.
Its architecture and implementation must exploit Zig's own strengths.

## 1. Current state

| Item | State |
|---|---|
| Repository | Planning-only repository at `D:/code/manta`; no engine source exists. |
| Current phase | **Phase 0 — architecture and contracts**. No engine implementation may begin before its exit gate. |
| Zig | **0.16.0**, verified as the latest official stable release on 2026-08-07. Development/nightly builds are forbidden. |
| Initial evaluator | A Zig-idiomatic reimplementation of Basilisk's HCE, used as a bootstrap, reference and durable fallback. No significant HCE tuning campaign is planned. |
| Strategic evaluator | NNUE. HCE remains buildable and tested after NNUE lands so an explicit fallback remains possible. |
| Protocol | UCI. Basilisk-level robustness and behaviour parity are a Phase-1 specification and a release requirement. |
| Platforms | Portable scalar semantics first; production intent includes x86-64 and ARM64 with runtime-selected optimized backends. Phase 0 must finalize the supported matrix. |
| Long jobs | None authorized. SPRT, SPSA, gauntlet, datagen and timed performance work begin only when a later phase explicitly requests them. |

## 2. Non-negotiable engineering requirements

### 2.1 Latest stable Zig only

1. “Latest Zig” means the newest **official released stable** version listed at
   <https://ziglang.org/download/>. Master, development and nightly builds are
   never accepted in development, CI or releases.
2. At the start of every numbered phase and before every release, check the
   official download page. If a newer stable version exists, toolchain and
   syntax migration blocks new feature work until it is complete.
3. Pin and record the exact stable version in repository tooling, CI and every
   build/experiment/release manifest. The build must reject a different Zig
   version rather than silently accepting old syntax or a nightly compiler.
4. Do not add compatibility branches, deprecated syntax or standard-library
   shims for older Zig releases. Dependencies that lag behind the current
   stable release must be upgraded, replaced, isolated or omitted.
5. Every toolchain upgrade reads the official release notes, runs the complete
   correctness and UCI matrix in all required optimization modes, reproduces
   the deterministic `bench` fingerprint, and re-establishes performance
   anchors before claims are made.

Current authoritative references are the [Zig 0.16.0 language
documentation](https://ziglang.org/documentation/0.16.0/) and [0.16.0 release
notes](https://ziglang.org/download/0.16.0/release-notes.html). Replace these
references when the next stable migration is accepted; never use master
documentation to justify code in a stable-version repository.

### 2.2 Zig-native implementation

Manta must use Zig as Zig, not imitate C++, Rust or Java:

- use explicit allocators and ownership, error unions, optionals, tagged
  unions, exhaustive `switch`, slices, precise integer types and compile-time
  validation;
- use `comptime`, generics and static dispatch where they remove duplication or
  runtime cost without obscuring the chess semantics;
- use `@Vector` and target-aware code generation for measured SIMD kernels;
- make integer overflow, casts, alignment, endianness and serialization
  deliberate and tested;
- keep unsafe operations, unchecked indexing, raw pointer manipulation,
  `undefined` state and disabled runtime safety narrowly scoped, documented and
  justified by invariant tests plus measurement;
- perform no avoidable allocation, formatting, I/O or dynamic dispatch in the
  search hot path; and
- prefer clear domain types over primitive obsession or untyped flag fields.

The portable implementation is the semantic oracle. Architecture-specific
implementations must be exact backends, not divergent engine variants.

### 2.3 Clean Architecture without hot-path tax

Phase 0 must design the architecture before implementation. Clean Architecture
means dependency direction, testable policies and replaceable external
adapters; it does **not** mean heap-allocated interfaces, virtual dispatch,
indirection or ownership ambiguity in performance-critical code.

The design must decide and document:

- module boundaries and the allowed dependency graph;
- where chess rules, engine policies, UCI, clocks, files, threads, tablebases,
  evaluators, hardware detection and tooling belong;
- value ownership, allocator lifetime, state-stack and make/unmake contracts;
- concurrency ownership, cancellation, publication and output serialization;
- compile-time/static polymorphism versus the few justified runtime dispatch
  points;
- error handling at every process and library boundary;
- data layout, cache and alignment constraints in hot structures;
- test seams and architecture-fitness checks that prevent dependency erosion;
- extension seams for NNUE, HCE, SMP/NUMA, Syzygy, Chess960, MultiPV,
  datagen, tuning, diagnostics and additional instruction sets; and
- which decisions require an Architecture Decision Record (ADR).

No final module map or abstraction is predetermined here. Phase 0 produces and
reviews it. The exit gate rejects a design that cannot demonstrate zero-cost
hot-path composition in generated code or focused microbenchmarks.

### 2.4 Code quality, style and typing

The Zig compiler and formatter are the primary quality tools:

| Check | Policy |
|---|---|
| `zig fmt --check --ast-check .` | Mandatory locally and in CI; canonical Zig formatting is not configurable. |
| `zig build test -Doptimize=Debug` | Mandatory correctness and leak/invariant development gate. |
| `zig build test -Doptimize=ReleaseSafe` | Mandatory optimized-with-safety gate. |
| `zig build test -Doptimize=ReleaseFast` | Mandatory production-semantics gate at phase/release boundaries. |
| `zig build lint` | Mandatory build step once Phase 1 creates it; initially composes formatting, AST checks and project-specific architecture/style checks. |
| ZLS | Recommended editor diagnostics; its release must match the exact stable Zig version. It is not a substitute for CI. |
| Third-party linter | Adopt only a pinned release explicitly compatible with the required stable Zig. The current ZLint 0.8.1 targets Zig 0.15.2 and therefore cannot gate Zig 0.16.0 Manta. Track it and enable it when compatibility is proven. |

Project-specific lint/fitness checks must cover forbidden dependency edges,
accidental hot-path allocation, stale tune-option defaults, unversioned binary
formats and unsafe-operation annotations. Treat warnings as failures. Comments
explain invariants and reasons, not line-by-line mechanics. Public APIs and
non-obvious bit layouts document their contracts.

## 3. Development and evidence process

### 3.1 Responsibilities and commits

```text
Model  -> inspect, design/implement one plan step, locally verify, update docs, commit.
User   -> run requested long SPSA/SPRT/gauntlet/datagen jobs and return artifacts.
Model  -> apply the registered verdict, update PLAN + GUIDE + EXPERIMENTS, commit.
```

- Complete phases in order unless this plan explicitly permits parallel work.
- Commit each completed step with an imperative subject and useful body. Never
  push, tag or publish unless explicitly asked.
- Keep `PLAN.md` and `GUIDE.md` synchronized in the same commit.
- Consult `EXPERIMENTS.md` before proposing or retrying a mechanism. Close an
  experiment by recording its verdict, conditions, lesson and retry trigger in
  the same commit that accepts, reverts or parks it.
- Preserve unrelated user changes. Dirty binaries record a diff hash and can
  diagnose, but can never become baselines or release artifacts.
- Never compile or run another timed workload while an SPRT, SPSA, gauntlet,
  NPS A/B, PGO training or board benchmark is running. Deterministic outputs
  may survive contention; timing evidence does not.

### 3.2 Required gates

Early functional phases use correctness gates, not premature self-play. Once
Manta is tournament-capable, the following default evidence policy applies:

| Change | Required evidence |
|---|---|
| Documentation/architecture only | Internal-link check, PLAN/GUIDE consistency, requirement traceability and no engine-source change. |
| Toolchain/dependency upgrade | Official release-note review, format/AST/lint, all required test modes, exact 1T bench fingerprint and affected native target matrix. |
| Behaviour-neutral refactor/test/tooling | Format/AST/lint, relevant tests in required modes, sanitizing/safety tools when available, exact 1T bench fingerprint. |
| Correctness repair changing legal play | Deterministic regression, perft/invariants, tactical/mate/endgame/UCI suites, then strength gate unless unreachable in legal play. |
| Coherent strength candidate | Final production-build candidate versus the accepted final production baseline; default `[3,10]` nElo at `3+0.03`, maximum 12,000 games; only H1 promotes. |
| Broad/risky architecture bundle | Prospectively register `[0,10]` or `[3,12]`; preserve ablation switches and use one final-binary gate. |
| Non-inferiority/simplification | `[-3,0]`; H1 supports non-regression. |
| Speed-only | Exact bench identity plus identical-binary calibration and pooled/interleaved independent production-build NPS A/B. |
| UCI/time/root/SMP | Process regressions, 1T STC, 1T `10+0.1`, 4T `10+0.1`, zero forfeits; record topology, Hash and clock policy. |
| Harness change | Fixed-N identical-binary calibration: 30k games at 1T and 10k at 4T where applicable; complete 95% nElo CI inside ±5. |
| ISA/backend change | Exact scalar/backend conformance, cross-backend fingerprint, disassembly, unsupported-hardware behavior and target-native same-tier performance evidence. |
| Phase/release boundary | Clean reproducible artifacts, complete correctness/UCI/platform matrix, prior-baseline cumulative match and external cohort where applicable. |

Use the paired UHO book and `strength-v1` adjudication inherited from the
calibrated Basilisk/Rarog harness until Colosseum replaces them through the
bridge procedure in Phase 4. Record source SHA, dirty diff, Zig/LLVM version,
target/features, build options, binary/book/network hashes, PGO manifest, TC,
threads, Hash, concurrency, affinity, adjudication and CPU topology.

SPRT decides strength. Perft, deterministic node counts, WAC, static loss,
depth, EBF, NPS and telemetry explain results but do not replace games.

### 3.3 SPSA budget

1. Do not tune before the relevant architecture and parameter consumers freeze.
2. Reimplement Basilisk HCE values as the bootstrap; do not spend a normal HCE
   tuning campaign on a strategically temporary evaluator.
3. Permit one consolidated pre-NNUE search SPSA after Phase 5 freezes the
   single-thread search architecture. Diagnostics select no more than about 24
   non-redundant coordinates.
4. Permit one consolidated post-NNUE search SPSA after Phase 9 freezes the
   retained NNUE architecture and score scale.
5. A further run requires explicit evidence that the previous fit could not
   identify the needed parameter class. HCE coordinates are allowed only if
   Phase 11 is explicitly entered.
6. Discrete mechanisms use A/B switches or small registered grids. SPSA
   proposes; the clean final production build passes a separate registered
   SPRT. Estimator, schedule, bounds, horizon and stop rule are registered
   before launch—no post-hoc tail selection.

## 4. Benchmark and reproducibility contracts

### 4.1 Cross-engine board benchmark

Phase 2 must create a versioned benchmark specification before optimizing the
board. “Same benchmark” means identical inputs and operations, not similar
labels. The contract freezes:

- FEN text and parser mode;
- exact definition and count of every operation;
- whether state is copied, allocated, cached or recomputed inside timing;
- warm-up count, sample count, estimator and dispersion measure;
- dead-code-elimination barrier and correctness preflight;
- build mode, target CPU/features and runtime dispatch selection;
- output schema and units; and
- CPU/OS/power/topology/Zig manifest.

Required workloads are legal move generation, legal captures, make/unmake,
pin-aware threshold SEE over captures, start-position perft(4), and two-ply game
simulation over the agreed five-position corpus. Report median operations per
second, median absolute deviation and operations per iteration over 11 measured
samples; never allocate or copy the working set in the timed region.

The existing Basilisk and Rarog tests currently differ in one corpus position,
one hot workload and sampling statistics. Phase 2 must preserve compatibility
profiles for historical comparison and publish one reconciled
`cross-engine-board-v1` manifest before claiming direct three-engine results.
Absolute cross-language throughput is descriptive; controlled same-machine
runs and profiles explain it.

Performance thresholds are set only after correct Debug and ReleaseFast
baselines exist on known machines. CI thresholds remain generous correctness
alarms; stable native hardware provides regression evidence.

### 4.2 Built-in `bench` command

Manta must implement the Basilisk/Rarog information contract:

```text
bench [depth] [repeats] [threads]
```

- Default depth is established when the baseline search stabilizes; default
  repeats and threads are `1`.
- The default ignores the current `Threads` option, clears TT and histories,
  uses the fixed shared 40-position suite, and yields a deterministic 1T total
  node fingerprint across supported platforms and scalar/optimized backends.
- The third argument deliberately enables multi-thread speed measurement. Its
  node total is not a deterministic fingerprint.
- A single repeat prints per-position nodes, elapsed time, NPS and EBF plus
  aggregate nodes, time, NPS, geometric-mean EBF, median nodes and top-position
  node share. Multiple repeats print compact per-run data and a clearly named
  best/median statistic; fingerprint diagnostics come from run one.
- Invalid arguments produce a clear diagnostic without corrupting engine state.
- Fingerprint changes require an intentional update with the causal change,
  correctness evidence and old/new values recorded in `EXPERIMENTS.md`.

Bench node identity proves deterministic search behaviour, not strength or
speed. Speed claims require the A/B procedure in §3.2.

### 4.3 Determinism and manifests

- Zobrist keys and deterministic test RNGs use fixed, versioned seeds.
- Tie-breaking, TT/history reset and test corpus order are specified.
- Persisted files (NNUE, datasets, manifests, optional TT state) are versioned,
  endian-defined and reject incompatible inputs.
- Reproducible release manifests include source, exact Zig version, build
  options, target/features, dependencies, binary hash, runtime backend, bench
  fingerprint and all embedded data/network hashes.

## 5. Phases

### Phase 0 — Clean Architecture and project contracts

**No engine implementation is permitted in this phase.**

#### 0.0 — Product scope, provenance and licensing

- Decide Manta's license before source or constants are copied.
- Define what may be reimplemented from Basilisk and Rarog and record provenance
  for algorithms, evaluation features/values, test positions, books, networks
  and third-party dependencies.
- Freeze the first playable scope: standard chess, portable scalar, 1T UCI,
  deterministic search and bootstrap HCE. List deferred features explicitly.
- Define success and exit criteria for every following phase; no Elo promise is
  attached to early functional milestones.

#### 0.1 — Requirements and quality model

- Convert this plan into traceable functional, performance, portability and
  safety requirements.
- Define terminology, score/mate conventions, units, supported files, resource
  limits and failure policy.
- Define the format/AST/lint/test/benchmark/CI matrix and the exact Zig version
  guard. Review Zig 0.16.0 release notes and current APIs before design examples
  are accepted.

#### 0.2 — Architecture design

- Produce context, module/dependency, runtime, state-lifetime and concurrency
  diagrams without implementing them.
- Write ADRs for board/state representation selection process, make/unmake
  ownership, evaluator selection, search composition, UCI control plane, clock,
  TT concurrency, runtime ISA dispatch and persisted formats.
- Define architecture-fitness tests and zero-cost acceptance checks.
- Walk future features—NNUE, SMP/NUMA, Syzygy, Chess960, MultiPV, datagen,
  diagnostics and additional ISAs—through the proposed design and record
  pressure points without implementing speculative abstractions.

#### 0.3 — Architecture proof and exit gate

- Review each boundary for dependency direction, error flow, allocator
  lifetime, testability and hot-path cost.
- Prototype only disposable design spikes outside the production tree if
  generated-code or layout evidence is required. No spike becomes engine code.
- Exit only with approved diagrams/ADRs, requirement traceability, license and
  provenance policy, quality/toolchain policy, supported-target intent and an
  explicit statement that engine implementation may begin.

### Phase 1 — Repository foundation and UCI behavioural specification

UCI parity is defined here, before board or search details can distort it.

#### 1.0 — Latest-stable toolchain and build spine

- Recheck the latest official stable Zig and migrate before any feature work.
- Add version-guarded `build.zig`/`build.zig.zon`, library/executable/test
  modules and standard build steps without chess behaviour.
- Add `fmt`, `ast-check`, `lint`, Debug/ReleaseSafe/ReleaseFast tests and initial
  cross-platform CI. Pin only current-stable-compatible dependencies.
- Add ZLS guidance and evaluate the current third-party linter. If no release
  supports the required Zig, retain project lint checks and a tracked adoption
  item rather than downgrading Zig.

#### 1.1 — UCI behavioural specification

Create a normative command/state/output matrix and process transcript corpus
using Basilisk as the primary compatibility oracle and Rarog as a second
reference. Resolve differences deliberately. Specify at minimum:

- `uci`, `debug`, `isready`, `setoption`, `ucinewgame`, `position`, `go`,
  `stop`, `ponderhit`, `quit`, EOF and unknown/malformed input;
- command ordering when search is active, repeated `go`, stale stop signals,
  option barriers and exactly-once `bestmove` publication;
- `go` limits: clocks/increments, `movestogo`, `movetime`, `depth`, `nodes`,
  `mate`, `infinite`, `ponder`, `searchmoves` and `perft`;
- clock start at receipt of `go`, not delayed worker execution;
- completed ponder waiting for `ponderhit` or `stop`, without restarting a
  spent clock;
- serialized complete output lines, legal PVs, legal fallback/bestmove and
  terminal/no-legal-move representation;
- FEN/illegal-move rejection and whether the last valid position is retained;
- option ranges/defaults as a single source of truth; and
- diagnostics, exit codes and resource bounds for hostile input.

Each transcript test may name the later phase that supplies its engine
capability, but its expected behaviour cannot silently change later.

#### 1.2 — Test harness and repository policy

- Build a process-test harness that can drive asynchronous stdin/stdout with
  bounded waits and distinguish eventual-output assertions from timing tests.
- Add documentation/link checks, architecture-fitness checks, deterministic
  seeds and artifact directory conventions.
- Exit with a clean quality pipeline, frozen UCI specification and no chess
  behaviour beyond what the approved architecture requires for the shell.

### Phase 2 — Board, state, move generation and direct board benchmark

#### 2.0 — Domain types and representation decision

- Evaluate candidate board/state and move encodings against the Phase-0
  criteria; record the ADR and memory/layout compile-time assertions.
- Define colors, pieces, squares, moves, bitboards, castling/EP/rule-50/fullmove
  state and Zobrist identity with precise types and illegal-state policy.
- Generate suitable attack/Zobrist tables at compile time where this improves
  correctness/startup without making builds unreasonable.

#### 2.1 — State transitions and legality

- Implement FEN, attack queries, pseudo/legal generation, captures/evasions,
  make/unmake/null moves and check/pin state under one invariant contract.
- Support promotion, castling, en passant, repetition and rule-50 semantics.
- Prepare per-ply state and complete dirty-piece records suitable for a future
  incremental NNUE accumulator; do not add NNUE inference yet.

#### 2.2 — Correctness campaign

- Canonical perft with divide, randomized differential perft against at least
  one independent oracle, and long random make/unmake round trips.
- Recompute and compare occupancy, piece lists/bitboards, king state, checks,
  hashes, rule counters and FEN at every sampled ply.
- Add malformed-input/property/fuzz coverage and minimize every found failure
  into a deterministic regression.

#### 2.3 — Board benchmark

- Reconcile and version the Basilisk/Rarog benchmark contract from §4.1.
- Implement historical compatibility profiles plus
  `cross-engine-board-v1`; verify identical work counts before timing.
- Capture Debug and ReleaseFast baselines on the same idle host for Manta,
  Basilisk and Rarog, with complete manifests. Do not optimize from noisy
  single samples.

### Phase 3 — Bootstrap HCE and evaluator-ready state

#### 3.0 — Evaluation boundary

- Implement the Phase-0 evaluator composition using compile-time/static
  selection in the hot path.
- Define score, mate/TB, phase/interpolation and trace contracts. Preserve a
  scalar reference path and an evaluator-independent search-facing API.

#### 3.1 — Basilisk HCE reimplementation

- Reimplement Basilisk's accepted HCE concepts and values idiomatically in Zig;
  do not mechanically translate C++ structure or copy defects.
- Freeze a reference position corpus with component traces and expected totals.
  Exact parity is the default; every intentional semantic deviation is an ADR,
  regression and experiment-ledger entry.
- Make incremental state optional only where measurement justifies it. Keep
  evaluation deterministic, allocation-free and traceable.

#### 3.2 — Strategic HCE limit

- Add evaluation invariants, symmetry/color-flip tests, endgame/mate-scale
  tests and throughput measurements.
- Do not start broad new feature work or Texel/SPSA tuning. HCE exists to make
  Manta playable, bootstrap search/data, provide a debug oracle and remain a
  maintained fallback.
- Exit with HCE parity/known deviations documented and the NNUE state contract
  unobstructed.

### Phase 4 — Deterministic 1T search, UCI baseline and tooling

#### 4.0 — Search correctness baseline

- Implement iterative deepening, alpha-beta/PVS, quiescence, legal PVs,
  terminal/draw/mate semantics and interruption-safe result publication.
- Add a typed result-evidence model from the beginning so static evaluation,
  stand pat, qsearch moves, reduced/full search, null and speculative cutoffs
  cannot accidentally gain equal authority later.

#### 4.1 — TT, ordering and diagnostics substrate

- Add TT key/bound/depth/mate conversion/replacement contracts, staged move
  ordering, killers/history and SEE with deterministic tests.
- Establish diagnostics for tree shape, pruning overlap, best-move recall,
  TT producer/consumer provenance, root stability and stop latency. Diagnostics
  off must preserve the bench fingerprint.

#### 4.2 — UCI baseline completion

- Connect the Phase-1 protocol/control-plane contract to real position and
  search capabilities without moving parsing or I/O into the domain/search
  layers.
- Activate 1T process transcripts for malformed input, go/stop/quit/EOF,
  `searchmoves`, perft, nodes/depth/movetime/infinite and legal PV/bestmove.

#### 4.3 — Built-in bench and test suites

- Implement the versioned 40-position `bench` contract from §4.2 and establish
  Manta's first accepted fingerprint only after correctness freezes.
- Add tactical/WAC diagnostics, mate-distance and KBNK/KQK/endgame canaries.
  These detect semantics and explain changes; they do not decide strength.

#### 4.4 — Experiment tooling foundation

- Port/adapt the synchronized Basilisk/Rarog PowerShell workflow for tool
  setup, final production builds, SPRT, SPSA, gauntlets, NPS A/B, scaling,
  watching and artifact capture.
- Use one harness-neutral, versioned experiment manifest/config schema so the
  engine and evidence ledger are not coupled to a single runner.
- Calibrate identical binaries, physical-core selection, reserved cores,
  affinity, concurrency, book and adjudication before any Manta strength claim.

#### 4.5 — Colosseum migration seam

- Treat current scripts as adapters. When Colosseum CLI implements the needed
  features, add a Colosseum adapter without changing the registered experiment
  schema.
- Require identical-binary 1T/4T calibration, command/option/adjudication audit,
  paired-opening verification and bridge tests against the prior harness.
- Switch the default only when equivalent semantics and acceptable null bias
  are demonstrated. Archive the old adapter until the first Colosseum-gated
  release is reproducible.

### Phase 5 — Evidence-coherent single-thread search

#### 5.0 — Freeze functional baseline

Reproduce the complete correctness/UCI/fingerprint matrix and capture a clean
production manifest. From here, playing changes require the registered gates.

#### 5.1 — Search architecture

Add and diagnose coherent families rather than isolated copied formulas:

- aspiration and root result ownership;
- null-move pruning and verification;
- futility/razoring/LMP/SEE pruning and LMR around one prospective-depth and
  pre-move evidence model;
- IIR, ProbCut, extensions and singular search with explicit provenance;
- history/correction update attribution and saturation; and
- legal completed fallback on every abort path.

Reference contemporary engines for hypotheses, never constants or verdicts.
Each mechanism remains ablatable. A smaller tree or higher depth is not proof
of stronger move selection.

#### 5.2 — Syzygy and endgame integration

- Add replaceable Syzygy probing with strict path/error handling, WDL/DTZ,
  rule-50 semantics, root filtering and score conversion tests.
- Keep tablebase I/O outside the pure board/search policy boundary and ensure
  missing/corrupt files degrade safely.

#### 5.3 — Consolidated pre-NNUE fit

- Freeze architecture, use diagnostics to select no more than about 24 search,
  history and time-independent coordinates, and run the one pre-NNUE SPSA.
- Bake a clean production candidate, run post-fit ablations and accept only
  through the registered final-binary SPRT.
- Do not tune HCE weights. Exit with a stable 1T baseline suitable for NNUE
  comparison and data generation.

### Phase 6 — Time management, robust UCI parity and SMP

#### 6.0 — Clock and root confidence

- Use a monotonic clock and account from `go` receipt through dispatch.
- Derive aspiration, time allocation, fallback and later SMP publication from
  one completed-iteration root-confidence model.
- Test clock/increment/movestogo/movetime/ponder overhead, stop latency, minimum
  completed depth and adverse scheduling.

#### 6.1 — Full Phase-1 UCI parity

Activate the complete transcript matrix, including repeated commands, stale
signals, `isready` barriers, option changes, completed ponder waiting,
ponderhit after spent time, malformed positions, threaded legal PVs and exactly
one bestmove. Differential transcript comparison against Basilisk is a gate;
intentional differences require an ADR and regression.

#### 6.2 — SMP

- Add a thread pool and shared structures under the Phase-0 ownership model.
- Preserve inert 1T semantics and fingerprint. Define aggregate node limits,
  helper clocks, TT sharing, result ownership, cancellation and publication.
- Measure 1/2/4/8T scaling and run independent 1T STC/LTC plus 4T LTC strength
  gates with zero forfeits. Multi-thread strength is not inferred from 1T.

### Phase 7 — NNUE runway and data contract

#### 7.0 — State and accumulator contract

- Audit every move/null/unmake path for complete dirty-piece records and
  accumulator push/pop/refresh needs.
- Freeze scalar feature-index, perspective, bucket and quantization references;
  encode architecture/version/endianness metadata from the first network file.

#### 7.1 — Trainer and dataset preflight

- Define self-play/teacher data schema, sampling, deduplication, train/valid/
  untouched-test splits, label blend, manifests, seeds, resume and integrity.
- Pin the trainer source/toolchain and require export/inference conformance.
- Preserve HCE and search-disagreement corpora as diagnostics, not automatic
  training truth.

#### 7.2 — Runway gate

Land no-op/scalar scaffolding only if it is bench-identical when NNUE is off,
complete on all board transitions and portable across the supported matrix.

### Phase 8 — Baseline NNUE

#### 8.0 — Controlled pilot networks

Train small, reproducible pilot networks with at least two seeds. Validate file
loading, quantization, scalar inference and untouched-set metrics before scale.

#### 8.1 — Scalar and incremental integration

- Integrate the network behind the same search-facing evaluator contract.
- Prove scalar full-refresh, incremental accumulator and trainer-export parity
  over randomized long games and every special move.
- Add strict loader failures and embedded/external network hash reporting.

#### 8.2 — Portable and vector backends

Implement exact portable, x86-64 and ARM64 kernels using Zig-native vectors or
target intrinsics selected by measured suitability. Every optimized path must
match the scalar integer reference bit-for-bit.

#### 8.3 — Baseline acceptance

Compare HCE and NNUE at fixed nodes, NPS, STC, LTC and 4T; test more than one
network seed. Static validation loss alone cannot promote a network. Keep HCE
buildable and continuously tested after NNUE becomes the default.

### Phase 9 — NNUE frontier and final search fit

#### 9.0 — Residual and disagreement analysis

Use untouched teacher residuals, search disagreements, natural finishes and
game evidence to identify data/architecture gaps. Do not select only by one
loss metric.

#### 9.1 — Architecture ladder

Test evidence-led feature, king/perspective, threat, material/output bucket,
width, activation and refresh changes one axis at a time with multiple seeds,
integer conformance, throughput and games.

#### 9.2 — Consolidated post-NNUE fit

After network architecture and score scale freeze, select no more than about 24
non-redundant search/history/time coordinates for the single post-NNUE SPSA.
Bake, ablate and SPRT the clean production result.

### Phase 10 — ISA dispatch, platforms, scaling and release maturity

#### 10.0 — Runtime backend dispatch

The intended shape is a portable semantic core with sibling optimized
backends—for example x86-64 baseline, AVX2, BMI2/PEXT and ARM64 NEON—selected
once at startup where practical. AVX2 and BMI2 are independent capabilities;
PEXT presence does not prove it is fast on that microarchitecture.

- Make compile flags, artifact names, runtime checks and user guidance one
  executable ISA contract.
- Refuse unsupported forced backends safely and always provide a portable
  fallback.
- Inspect emitted instructions and dynamic dependencies. Cross-compilation and
  a UCI handshake are necessary but not sufficient.

#### 10.1 — Native platform validation

Build and execute the supported Windows/Linux/macOS and x86-64/ARM64 matrix.
Require native tests, UCI/perft/bench agreement, lock-free atomic assertions
where relied upon, target-native performance evidence and backend conformance.

#### 10.2 — Performance and scaling

Profile before optimizing. Measure board, evaluator, search, TT/cache pressure,
allocation, branch behaviour, 1/2/4/8T scaling and high-thread/NUMA cases.
Evaluate PGO/LTO only through the current stable Zig's supported pipeline and
controlled A/B evidence. No implementation technique is required merely
because it helped another language or engine.

#### 10.3 — Product completion and releases

Add demanded features such as MultiPV or Chess960 only through their planned
seams and dedicated correctness/UCI gates. Produce reproducible target assets,
manifests and a cumulative external cohort before a strength release.

### Phase 11 — Optional HCE fallback

Enter only after serious NNUE data, training, integration and architecture
retries fail and the user explicitly chooses to redirect effort.

#### 11.0 — Failure review and scope decision

Document which NNUE hypotheses failed, under what evidence, and why more NNUE
work has lower expected value. Confirm that HCE remains correct and performant.

#### 11.1 — HCE residual program

Use evaluation traces, untouched residuals and search disagreement to select a
small HCE feature program. Avoid recreating broad historical feature lists.

#### 11.2 — HCE fit and release

Permit one HCE fit, then require fixed-node diagnostics, SPRT, LTC/4T and the
complete platform/ISA release matrix. NNUE code and evidence remain preserved
unless removal is separately justified.

## 6. Durable lessons carried into Manta

1. Copy experiment design and behavioural contracts, never another engine's
   verdict or Elo arithmetic.
2. Tune consumers only after architecture freezes; a tune can conceal a defect
   and make its later repair appear harmful.
3. Canaries catch semantics. Games decide strength.
4. Bench fingerprint identity proves deterministic behaviour, not speed.
5. A smaller or deeper tree can choose worse moves; measure recall,
   contradiction and fixed-node quality.
6. Search results need provenance. Static eval, stand pat, qsearch, ProbCut,
   null, reduced, full and incomplete results do not have equal authority.
7. Root aspiration, timing, fallback and SMP must share coherent completed
   evidence.
8. Multi-thread correctness, time safety and strength are independent release
   conditions.
9. Machine time is a budget. Do not spend full gates resolving immaterial
   isolated knobs when a coherent architecture fit is planned.
10. Cross-compilation is not platform validation; production assets run on
    their target hardware.
11. HCE is a bootstrap and fallback, not the strategic optimization sink.
12. The newest stable Zig is a requirement, while exact pinning and manifests
    preserve reproducibility inside that requirement.

## 7. Release checklist

1. Recheck and migrate to the latest official stable Zig; no nightly compiler.
2. Phase gate and cumulative prior-release match passed.
3. Clean tree; version, license and provenance current.
4. Format/AST/lint plus Debug, ReleaseSafe and ReleaseFast matrices pass.
5. Perft/invariants/fuzz regressions, tactical/mate/endgame/Syzygy and complete
   UCI process tests pass.
6. Deterministic 1T bench fingerprint agrees across every production backend
   and native target; deliberate changes are recorded.
7. Fresh revision-matched production/PGO/ISA assets are smoke-tested natively;
   manifests, hashes, dependencies and disassembly audits are archived.
8. NNUE releases record network/architecture/trainer/data hashes and exact
   scalar/incremental/backend parity. HCE fallback tests still pass.
9. Update user-facing documentation only for visible changes; keep experiment
   bookkeeping in `EXPERIMENTS.md`.
10. Commit locally. Do not tag, push or publish unless explicitly requested.

## 8. Planned command surface

These commands become valid only as their owning phases implement them:

```powershell
zig version
zig fmt --check --ast-check .
zig build lint
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
zig build board-bench -Doptimize=ReleaseFast
zig build run -Doptimize=ReleaseFast -- bench 13 1 1
.\tools\build_test.ps1 -Suffix <name>
.\tools\sprt.ps1 -EngineA <candidate> -EngineB <baseline> `
  -NameA Candidate -NameB Baseline -Elo0 3 -Elo1 10 -MaxGames 12000
.\tools\nps_ab.ps1 -EngineA <candidate> -EngineB <baseline> -Rounds 12
.\tools\spsa.ps1 -ConfigGroup search_final -EngineSuffix <base>
.\tools\gauntlet.ps1 -Engine <candidate> -Opponents <list> -TC "10+0.1"
```
