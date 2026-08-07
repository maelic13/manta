# Manta development plan

This is the maintainer-facing source of truth for what Manta will build, in
what order, and with which evidence. [`REQUIREMENTS.md`](REQUIREMENTS.md) is
the normative, traceable acceptance contract. [`ARCHITECTURE.md`](ARCHITECTURE.md)
and its [ADRs](docs/adr/README.md) own the accepted design. [`GUIDE.md`](GUIDE.md)
is the short operational mirror. [`EXPERIMENTS.md`](EXPERIMENTS.md) is the
indexed, conditional evidence ledger. [`README.md`](README.md) and
[`CHANGELOG.md`](CHANGELOG.md) are user-facing and must not become experiment
notebooks.

Manta is a new UCI chess engine written in Zig. Basilisk is the primary design
and behavioural reference; Stockfish is the secondary gold-standard
cross-check. Basilisk and Rarog are also tooling and prior-evidence references.
Manta's engine, tests and build implementation are original Zig work rather
than a line-by-line port, and must exploit Zig's own strengths.

## 1. Current state

| Item | State |
|---|---|
| Repository | Phase 0 and steps 1.0.1–1.0.2 are complete. Step 1.0.3 is implemented locally; successive remote probes repaired CI bootstrap and excluded the unstable Windows ARM64 toolchain, with a clean five-platform rerun pending. No UCI or chess behaviour exists. |
| Current phase | **Step 1.0.3 — CI and branch gate**, awaiting a clean remote rerun. Later Phase-1 steps and all later phases remain closed. |
| Implementation permission | Open only for the work explicitly owned by Phase 1. No board, evaluation or search implementation may be pulled forward. |
| License | **GPL-3.0-or-later**, copyright (C) 2026 Miloslav Macůrek. |
| Branch workflow | Development occurs on `dev`. Every later `master` commit is a release squash-merged through a required-CI pull request. The sole publisher enforces the gate procedurally and resets `dev` only after the release and post-merge checks are final. |
| Zig | **0.16.0**, verified as the latest official stable release on 2026-08-07. Development/nightly builds are forbidden. |
| Initial evaluator | An original, replaceable Zig-native Manta HCE informed by Basilisk's proven feature set and accepted parameter values at the initial snapshot. It is not copied, linked or kept synchronized. No significant initial HCE tuning campaign is planned. |
| Strategic evaluator | NNUE. HCE remains buildable and tested after NNUE lands so an explicit fallback remains possible. |
| Protocol | UCI. Basilisk-level robustness and behaviour parity are a Phase-1 specification and a release requirement. |
| Platforms | The Phase-0 matrix is frozen in `REQUIREMENTS.md`: Windows x86-64 plus Linux/macOS x86-64 and ARM64, target-native execution before publishing an asset, and WSL2 as the normal local Linux x86-64 test environment. Windows ARM64 is deferred until stable Zig tooling passes the ordinary gates. |
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

The accepted Phase-0.2 module map, ownership/runtime diagrams and zero-cost
contracts now live in [`ARCHITECTURE.md`](ARCHITECTURE.md) and its ADRs. Phase
0.3 audits them. The exit gate rejects a design that cannot demonstrate
zero-cost hot-path composition in generated code or focused microbenchmarks.

### 2.4 Code quality, style and typing

The Zig compiler and formatter are the primary quality tools:

| Check | Policy |
|---|---|
| `zig build fmt` | Mandatory locally and in CI; runs canonical format and AST checks over repository Zig sources while excluding ignored package sources. |
| `zig build test -Doptimize=Debug` | Mandatory correctness and leak/invariant development gate. |
| `zig build test -Doptimize=ReleaseSafe` | Mandatory optimized-with-safety gate. |
| `zig build test -Doptimize=ReleaseFast` | Mandatory production-semantics gate at phase/release boundaries. |
| `zig build lint` | Mandatory build step once Phase 1 creates it; initially composes formatting, AST checks and project-specific architecture/style checks. |
| ZLS | Recommended editor diagnostics; its release must match the exact stable Zig version. It is not a substitute for CI. |
| Third-party linter | Source-pinned host-only ZLint 0.9.1 has a reviewed zero-warning baseline and is part of `zig build lint`; step 1.0.3 adds its reproducible CI pass. |

Project-specific lint/fitness checks must cover forbidden dependency edges,
accidental hot-path allocation, stale tune-option defaults, unversioned binary
formats and unsafe-operation annotations. Treat warnings as failures. Comments
explain invariants and reasons, not line-by-line mechanics. Public APIs and
non-obvious bit layouts document their contracts.

### 2.5 Chess-domain evidence and strength objective

Manta's objective is playing strength under correct chess and UCI semantics,
not implementation similarity or preservation of incidental output. Every
non-trivial test must identify the chess rule, search invariant,
protocol/ownership contract or performance risk it protects. Prefer an
independent rule oracle, recomputation, property/metamorphic relation,
differential comparison or instrumentation; do not duplicate production logic
and call it an oracle.

Exact evaluations, node totals, sizes, constants and tuning values are tests
only when they are deliberate contracts, conformance snapshots or diagnostic
fingerprints with a stated purpose and update procedure. Coding work traces
state/evidence producers and consumers and considers legal chess,
terminal/draw/special-move semantics, bounds, cache/allocation/thread behavior
and plausible strength impact. One-thread behavior is the deterministic
baseline; four-thread correctness, time safety, strength and scaling are
independent gates, and higher-thread claims require measurement. Repository
[`AGENTS.md`](AGENTS.md) makes this mandatory for coding agents.

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
- Coding agents must follow [`AGENTS.md`](AGENTS.md), including its
  domain-meaningful test and producer/consumer reasoning rules.
- Never compile or run another timed workload while an SPRT, SPSA, gauntlet,
  NPS A/B, PGO training or board benchmark is running. Deterministic outputs
  may survive contention; timing evidence does not.
- The only designated long game-testing/tuning host is the user's Ryzen 9 5950X. Its
  usable concurrency is a measured Colosseum host-profile result, not `32`
  logical threads assumed as game slots. Colosseum jobs are serialized and retain
  physical-core placement, reserved capacity, pilot pair rate, bounded
  expected/worst wall time, storage, checkpoint/resume and stop-rule evidence.

### 3.2 Branch, CI and release workflow

1. `dev` is the development branch. Normal step commits remain there and pass
   the applicable local gates before they are committed.
2. `master` is release-only. A release moves from `dev` through a pull request
   after required CI and is squash-merged into one release commit. The sole
   publisher enforces this procedure; repository branch protection is not
   required. Unverified direct pushes to `master` remain forbidden by project
   policy.
   One accepted exception precedes that rule: at the end of Phase 0 the
   accepted project foundation is squash-merged from `dev` into `master` as a
   single foundation commit, so the public default branch carries the license,
   README and accepted contracts instead of appearing unlicensed until the
   first release. After that commit `master` receives releases only.
3. Phase 1 creates one authoritative CI workflow with identical jobs for pull
   requests targeting `master`, pushes to `master` as a backstop, and manual
   dispatch on any branch. Once the workflow exists on default `master`, a
   manual run from `dev` is the exact preview of the release-merge gate, not a
   reduced substitute. Its initial remote validation uses an unmerged draft
   `dev` to `master` pull request because manual dispatch is unavailable until
   the workflow reaches the default branch.
4. The CI gate pins the exact stable Zig, checks documentation and internal
   links, formatting/AST/lint, Debug/ReleaseSafe/ReleaseFast tests, supported
   target builds and, once available, deterministic cross-platform bench
   agreement. The sole publisher requires it before squash merge, then verifies
   the post-merge `master` run and a clean worktree before resetting `dev`.
5. The release workflow operates on the exact tagged `master` revision. It
   creates or uses a draft GitHub Release, builds every supported native asset,
   smoke-tests the artifact that will be uploaded, compares deterministic
   fingerprints, produces hashes and a reproducibility manifest, attaches all
   assets, and publishes only after the complete matrix succeeds.
6. `CHANGELOG.md` is the authoritative source of user-facing release notes.
   The release workflow extracts the matching version section; GitHub's
   pull-request-generated notes are not the primary release text.

The initial supported release intent is native portable binaries for Windows
x86-64 plus Linux and macOS across x86-64 and ARM64 where GitHub-hosted native
runners are available. Windows ARM64 is deferred until a stable Zig compiler
passes the ordinary native gates. Accepted x86-64 ISA tiers become sibling
assets in Phase 10; absence of an optimized tier never removes the portable
fallback.
WSL2 is the primary local Linux x86-64 build, test and artifact-smoke
environment. Hosted/native Linux CI remains required for releases, and WSL2
does not validate ARM64 or final target-native performance. GNU-linked,
libc-free and static-musl Linux packaging are implementation candidates rather
than preselected winners; deterministic parity, dependency inspection and
controlled speed/deployment evidence decide the released form.

### 3.3 Required gates

Early functional phases use correctness gates, not premature self-play. Once
Manta is tournament-capable, the following default evidence policy applies:

| Change | Required evidence |
|---|---|
| Documentation/architecture only | Internal-link check, PLAN/GUIDE consistency, requirement traceability and no engine-source change. |
| Toolchain/dependency upgrade | Official release-note review, format/AST/lint, all required test modes, exact 1T bench fingerprint and affected native target matrix. |
| Behaviour-neutral refactor/test/tooling | Format/AST/lint, relevant tests in required modes, sanitizing/safety tools when available, exact 1T bench fingerprint. |
| Correctness repair changing legal play | Deterministic regression, perft/invariants, tactical/mate/endgame/UCI suites, then strength gate unless unreachable in legal play. |
| Coherent strength candidate | Final production-build candidate versus the accepted final production baseline; one prospectively chosen representative time-based SPRT, default `[3,10]` nElo at 1T `3+0.03`, maximum 12,000 games; only H1 promotes. |
| Coherent resource-aware bundle | Allowed only when components are inseparable, invalid/misleading in isolation or individually below affordable resolution. Register one mechanism-level hypothesis, no unrelated changes, component switches and `[0,10]` or `[3,12]`; use one final-binary gate. A pass accepts the bundle, not every component. |
| Non-inferiority/simplification | `[-3,0]`; H1 supports non-regression. |
| Speed-only | Exact bench identity plus identical-binary calibration and pooled/interleaved independent production-build NPS A/B. |
| UCI/time/root/SMP | Process and fake-clock regressions plus one strength gate chosen for the claimed scope: normally 1T `3+0.03`, 1T `10+0.1` for a specifically long-time allocation claim, or 4T `10+0.1` for an SMP claim; require zero forfeits and record topology, Hash and clock policy. |
| Harness/clock/placement change | Identical-binary calibration at the exact production TC, threads, Hash, book, adjudication and placement. Size fixed-N prospectively for the requested null-bias precision and available 5950X wall time; recalibrate only after a relevant runner, clock, OS/hardware or topology/placement change. |
| ISA/backend change | Exact scalar/backend conformance, cross-backend fingerprint, disassembly, unsupported-hardware behavior and target-native same-tier performance evidence. |
| Phase/release boundary | Clean reproducible artifacts, complete correctness/UCI/platform matrix and one cumulative match or external cohort chosen for the phase/release claim; this validates the integrated baseline and does not retroactively duplicate every accepted candidate gate. |

No playing-strength gate runs until Phase 4 implements and validates the
conservative 1T clock policy in §4.2. From then onward, final production speed
is part of the result: each candidate gets exactly one prospectively registered
time control and thread scope representative of its claim. Fixed-node games
remain useful observations of quality per node, but they cannot accept a
change. NPS, nodes, depth and telemetry explain the time-based verdict rather
than creating a second promotion path. Do not repeat the same candidate at STC,
LTC and several thread counts by default; additional game evidence is justified
only by a distinct claimed scope or a cumulative phase/release decision.

Prefer one independently meaningful idea per candidate. Cheap correctness,
fingerprint, NPS, telemetry and tactical diagnostics reject weak work before
games but do not promote it. Small compatible changes may accumulate behind
switches as one staging bundle only under the bundle rule above. If that bundle
passes, retain no claim about the isolated value of each part. If it fails or
is inconclusive, run only the ablations whose expected decision value justifies
their 5950X time; do not spend an exhaustive test matrix by default.

| Phase | Playing-evidence activation |
|---|---|
| 0–3 | None. Contracts, board correctness/performance and HCE semantics are not playing-strength claims. |
| 4 | Build and verify the conservative 1T clock, then calibrate the harness and run a zero-forfeit smoke match; do not spend a candidate SPRT before the Phase-5 baseline freezes. |
| 5 | One 1T representative time-based SPRT per coherent playing candidate. Diagnostics and ablations funnel candidates before that long gate. |
| 6 | One time-based SPRT matched to the changed scope: 1T for allocation/root work or 4T for SMP. Deterministic inertness, process races, scaling and forfeit tests cover the other dimensions without duplicate SPRTs. |
| 7 | No routine strength gate for data-contract/scaffolding work while NNUE-off is exact; any behavior-changing work follows the Phase-5 rule. |
| 8–9 | Loss, conformance, seed and throughput evidence funnel networks/fits; each clean promotion candidate receives one representative time-based SPRT. SPSA remains conditional under §3.4. |
| 10 | Platform/ISA work uses exact conformance and native speed evidence. A release candidate receives one cumulative match/external cohort for the release claim, not a replay of every development gate. |
| 11 | If explicitly entered, diagnostics funnel one HCE candidate to one representative time-based SPRT; release evidence is added only if that candidate will ship. |

Colosseum is the strategic owner of engine-agnostic matches, SPRT, SPSA,
calibration, placement, watching and run records. Phase 4 qualifies a pinned
release or source revision; because it launches ordinary UCI executables,
Manta needs checked configurations and option mapping, not a runner adapter.
Any temporary legacy bridge is allowed only if qualification finds a real
blocker and is removed after the upstream fix. Record runner source/version,
source SHA, dirty diff, Zig/LLVM version, target/features, build options,
binary/book/network hashes, PGO manifest, TC, threads, Hash, concurrency,
affinity, adjudication and CPU topology. Record any fixed-node diagnostic
separately from the authoritative gate.

SPRT decides strength. Perft, deterministic node counts, WAC, static loss,
depth, EBF, NPS and telemetry explain results but do not replace games.

### 3.4 SPSA budget

1. Do not tune before the relevant architecture, score scale and parameter
   consumers freeze. Reaching a phase never authorizes SPSA by itself.
2. Seed the original Manta HCE with the proven reference feature/value baseline;
   do not spend a normal HCE tuning campaign on a strategically temporary
   evaluator.
3. Before proposing SPSA, write a short necessity review and run a small fixed
   sensitivity pilot. Show that several interacting continuous coordinates are
   sensitive and uncertain, that diagnostics or smaller experiments cannot
   answer the question efficiently, and that running now has higher expected
   value than deferring it.
4. The normal plan has no pre-NNUE SPSA. Phase 5 may request one consolidated
   exception only if a frozen search parameter set materially blocks playing
   strength, data quality or progress before NNUE; it requires an explicit PLAN
   amendment and user approval.
5. After Phase 9 freezes the retained NNUE architecture and score scale, one
   consolidated search/history/time SPSA may be authorized if the necessity
   review and pilot pass. Normally select 4–8 non-redundant interacting
   coordinates; more than 12 requires explicit evidence and user approval.
   Skipping the run is a valid outcome, not an incomplete phase.
6. A further run requires explicit evidence that the previous fit could not
   identify the needed parameter class. HCE coordinates are allowed only if
   Phase 11 is explicitly entered.
7. Before launch, use Colosseum's deterministic schedule and resume contract to
   estimate calendar time from a measured 5950X pilot rate. Register bounded
   checkpoints and stop early when movement is noise-dominated, insensitive or
   no longer worth the remaining machine time. Do not schedule automatic reruns.
8. Discrete mechanisms use A/B switches or small registered grids. SPSA
   proposes; the clean final production build passes one time-based registered
   SPRT. Estimator, schedule, bounds, horizon and stop rule are registered
   before launch—no post-hoc tail selection.

### 3.5 Contemporary reference checkpoints

Basilisk remains Manta's primary design reference and Stockfish the secondary
gold-standard cross-check, but neither is a source of copied engine code. At
the start of each high-leverage phase below, inspect exact pinned source
revisions and official development/testing material, extract hypotheses and
failure modes, and record only the implications relevant to original Zig code.
Do not import formulas, constants or architecture by prestige, and do not keep
Manta synchronized afterward.

| Phase | Required checkpoint |
|---|---|
| 4–5 | Search testing discipline, deterministic signatures/reproducibility, short debug self-play, result provenance, pruning/history interactions and complexity cost. |
| 6 | Time allocation, stop/publication safety, shared-memory ownership and scaling methodology. |
| 7–9 | Reproducible data/training recipes, evaluator/search co-adaptation, accumulator/inference contracts and realistic data scale. |
| 10 | ISA dispatch, topology/NUMA behavior, thread placement and target-native validation. |

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
speed. Speed claims require the A/B procedure in §3.3.

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

#### 0.0 — Product scope, origin and licensing

**Completed 2026-08-07.** The accepted product and origin contract is:

- Manta is GPL-3.0-or-later, copyright (C) 2026 Miloslav Macůrek. Source files
  use the matching copyright notice and SPDX identifier.
- Basilisk is the primary behavioural/design reference and Stockfish is the
  secondary cross-check. Names and detailed comparison evidence may appear in
  the maintainer-facing `PLAN.md`, `GUIDE.md` and `EXPERIMENTS.md`; user-facing
  README, changelog and release notes remain concise and Manta-focused.
- All engine code, Zig tests, build files and architecture checks are original
  Manta work. Existing Basilisk/Rarog experiment and build-orchestration
  tooling may be adapted deliberately. No engine implementation is copied.
- The initial HCE uses the feature lessons and accepted parameter values that
  worked in Basilisk as a one-time design/value baseline, but its types,
  composition, state, tracing and algorithms are independently written in Zig.
  Manta neither links to nor remains synchronized with Basilisk. The evaluator
  seam permits later NNUE and a clean-sheet replacement HCE.
- Tests are original Zig implementations. They may cover logically identical
  rules, positions, regressions and expected behaviour without per-case origin
  bookkeeping.
- Fathom is the anticipated third-party source exception for Syzygy. If it is
  vendored, its MIT license and source notices are preserved. Any other
  third-party source requires an explicit plan amendment and license review.
- Opening books, tablebases, PGNs, datasets, training outputs and development
  networks remain external, local and gitignored. Reproducibility manifests
  record their content hashes and roles without committing the assets.
- Contributor/CLA policy is deferred while Manta is a single-author project;
  it will be defined before accepting an outside contribution.

The first-playable milestone is the end of Phase 4: standard chess only, a
portable scalar single-thread UCI executable, full legal state and move
handling, deterministic search, an original Manta HCE, basic depth/node/
movetime/infinite/stop control, conservative 1T clocks suitable for later game
gates, exactly one legal `bestmove`, correctness suites and a deterministic
bench fingerprint. It carries no Elo promise.

Deferred beyond first-playable are NNUE, SMP/NUMA, Syzygy, Chess960 and other
variants, MultiPV, mature ponder/time management, optimized ISA backends,
datagen/training, strength tuning and games, PGO/LTO, GUI integration and
non-UCI protocols. Architecture must leave deliberate seams for likely future
features without implementing speculative abstractions.

The success and exit criteria for subsequent phases are their explicit gates
in this plan. Early functional milestones are judged by contracts,
correctness, determinism and reproducibility rather than Elo.

#### 0.1 — Requirements and quality model

**Completed 2026-08-07.** [`REQUIREMENTS.md`](REQUIREMENTS.md) now freezes:

- stable functional, UCI, score, resource, safety, file, performance,
  portability, quality and release requirement IDs with phase owners and
  verification methods;
- `MATE = 32000`, `INFINITY = 32001`, `NONE = 32002`, `MAX_PLY = 256`, one
  authoritative depth ceiling and move-count UCI mate reporting;
- neutral draw scoring initially, with contempt parked for a Phase-5
  investigation and no premature public option;
- bounded, checked input and transactional position/resource/file failure;
- exact Zig 0.16.0 build and CI guards, Zig 0.16 API constraints, the mandatory
  format/AST/lint/test/benchmark matrix and ZLint 0.9.1 evaluation;
- the supported build/native-release matrix, WSL2's local Linux role,
  native-artifact release evidence and benchmark-driven libc/musl packaging;
  and
- the maintainer-gated `dev` to `master` squash workflow, stable aggregate CI gate and
  changelog-derived draft-release contract.

#### 0.2 — Architecture design

**Completed 2026-08-07.** [`ARCHITECTURE.md`](ARCHITECTURE.md), twelve
[ADRs](docs/adr/README.md) and [`AGENTS.md`](AGENTS.md) now freeze:

- a Zig-native Clean Architecture dependency graph: chess/score domain,
  statically composed evaluation/search policy, engine application controller,
  outer UCI/platform adapters and one composition root;
- explicit allocator/resource/job/worker/ply lifetimes, stable-address
  preallocated worker storage and no allocation/I/O/dynamic dispatch in normal
  node paths;
- controller-owned root/resources, caller-owned per-ply make/unmake state,
  evaluator-local HCE/NNUE state and an evidence-led Phase-2 board/current-state
  selection rather than a premature layout;
- typed commands/events and output port, bounded/epoch-aware responsive control,
  explicit `std.Io` adapters and a project-owned persistent CPU worker pool;
- monomorphized evaluator/search composition, evidence-aware search results,
  canonical 1T semantics and separately gated 4T behavior;
- lock-free atomic TT safety semantics, injected monotonic time, scalar-oracle
  ISA dispatch and versioned little-endian persisted formats;
- narrow typed error flow across adapters/controller/workers, transactional
  recovery, outer-only presentation and fatal internal-invariant handling;
- future pressure seams for NNUE, SMP/NUMA, tablebases, Chess960, MultiPV,
  datagen, diagnostics, new HCEs and additional ISAs without speculative
  implementations; and
- executable architecture-fitness/zero-cost checks plus mandatory
  chess-domain reasoning for tests and coding agents.

#### 0.3 — Architecture proof and exit gate

**Completed 2026-08-07 — PASS.** The exit audit found no issue requiring a
product decision and authorizes Phase 1. Its concise verdict is:

| Check | Verdict |
|---|---|
| Requirements and test seams | All 90 requirements have an owning phase/activation and feasible unit, property, process, static, benchmark, game, native-target or release evidence. Resource, failure, game-gate and tuning-budget rows state their owners and checks explicitly. |
| Dependencies | The accepted graph is inward, acyclic by design and keeps UCI, files, OS services and presentation outside chess/evaluation/search policy. Ports are owned by their inward consumer. |
| Ownership and errors | Process, controller, resource generation, job, worker and ply lifetimes each have one owner. Recoverable boundary failures are typed/transactional; corrupt internal invariants fail fast. |
| Concurrency and shutdown | Epoch control, bounded/coalescible traffic, one controller, one presenter, per-job worker completion and interruptible shutdown provide testable stop/quit/EOF and exactly-once publication semantics without unbounded queues. |
| Hot-path cost | Move generation, make/unmake, evaluation, recursive search and TT access use concrete/static composition with no allocator or I/O. Runtime clock, event and optional probe calls are coarse, amortized or dominated by the external operation and have explicit measurement gates. |
| Deferred choices | Board/state layout, attacks, TT packing, HCE internals, SMP, ISA packaging and Linux ABI remain deliberately assigned to evidence-owning later phases; none requires a speculative Phase-0 abstraction. |
| Governance | License/origin, latest-stable Zig, quality, CI/branch and supported-target contracts are complete and mutually consistent. No disposable code spike was needed. |

The audit corrected three implementation-significant gaps: session termination
is exempt from impossible output guarantees after EOF/quit/fatal stdout;
resource replacement joins active workers and retains the prior generation
before potentially blocking construction; and worker completion now has an
explicit bounded return path independent of UCI presentation.

An independent re-audit on 2026-08-07 re-verified the external toolchain facts
(Zig 0.16.0, released 2026-04-13, is still the newest official stable release;
ZLint 0.9.1 is current and its 0.9.0 release added Zig 0.16.0 support) and
corrected further documentation defects without reopening the gate:

- `UCI-001` forbade all non-protocol stdout while §4.2 mandates a `bench`
  command; `UCI-005` omitted diagnostic `go perft`; and `UCI-003` incorrectly
  required that diagnostic mode to publish `bestmove`. The requirements now
  separate search completion from frozen diagnostic output.
- `FUNC-004` attributed a no-legal-move token to the UCI specification, which
  defines none; the spelling is now an explicit Phase-1 compatibility decision.
- `RES-012` was added because no requirement bounded the applied `position`
  move list or the pre-search game history, and `RES-004`'s 256-move generated
  capacity could have been mistaken for a game-length limit.
- The accepted dependency graph omitted `uci` edges into `chess`/`score`, the
  tablebase adapter's inward `chess` edge and `manta.zig` entirely. It now
  grants only those dependencies: typed WDL/DTZ remains a search-owned contract
  and score conversion remains search policy rather than adapter policy.
- The runtime sequence diagram published the ordered command before the urgent
  control signal, contradicting the ordering that the responsiveness argument
  depends on.
- Search-epoch ownership was ambiguous between the input adapter and the
  controller; the controller mints it and the adapter observes it.
- `ARCHITECTURE.md` §17 did not list move encoding among the deferred Phase-2
  choices, and `ADR-0007` did not trace the mailbox requirements it decides.

The re-audits also raised sequencing and evidence conflicts, now resolved.
Phase 2.1
implements pin-aware threshold SEE as a board-level query because 2.3's
benchmark contract requires it, leaving Phase 4.1 only its search integration.
Phase 4 now delivers a conservative 1T clock policy before tournament testing;
thereafter each candidate receives one representative time-based promotion
gate, so throughput is reflected without duplicate node/time SPRTs. `PERF-011`
makes SPSA conditional on a necessity review and normally defers the first
consolidated fit until the NNUE/search system freezes. Finally, `master` takes
one Phase-0 foundation squash commit so the public default branch is not an
unlicensed stale snapshot until the first release.

**Authorization:** Phase 1 may now begin. This authorization covers only the
repository foundation, build/quality/CI spine, UCI behavioural specification
and its test harness described below. It does not authorize work from Phase 2
or later.

### Phase 1 — Repository foundation and UCI behavioural specification

UCI parity is defined here, before board or search details can distort it.

#### 1.0 — Latest-stable toolchain and build spine

##### 1.0.1 — Toolchain and build spine

**Completed 2026-08-07.** Zig 0.16.0 remained the latest official stable and
matched the local compiler. The `0.0.0-dev` package now has an exact compile-time
version guard with negative tests, a silent executable composition root, an
independently importable library facade, a repository test root and standard
build/run/check/test steps. Native `ReleaseFast` plus `cpu=native`, all three
test modes and an ARM64 Linux cross-target compile check passed. No UCI or chess
behaviour was introduced.

- Recheck the latest official stable Zig and migrate before any feature work.
- Add exact-version-guarded `build.zig`/`build.zig.zon`, a minimal executable,
  library facade, repository test root and build-support tests without UCI or
  chess behaviour.
- Provide standard native build, run, compile-check and
  Debug/ReleaseSafe/ReleaseFast test steps. Keep local peak builds explicit as
  `ReleaseFast` plus `cpu=native`; portable targets remain explicit.

##### 1.0.2 — Quality and development tooling

**Completed 2026-08-07.** The build now exposes independent format/AST and
repository-policy gates plus a single `zig build lint` umbrella. The original
Zig policy checker validates required layout, local Markdown links and anchors,
PLAN/GUIDE numbering, the 90 unique requirement contracts and public-reference
policy, with its parsing rules covered by unit tests. Source-pinned ZLint 0.9.1
runs as host-only development tooling against a reviewed zero-warning baseline
covering all six repository Zig files. Concise exact-version, ZLS and local
command guidance lives in `docs/DEVELOPMENT.md`. All three test modes passed;
no UCI or chess behaviour was introduced.

- Add `fmt`, `ast-check`, `lint`, documentation/policy checks and concise
  development/ZLS guidance.
- Pin ZLint 0.9.1 as host-only development tooling and evaluate it against a
  reviewed zero-warning baseline. If it proves unsuitable, retain project lint
  checks, record the reason and never downgrade Zig to keep it.

##### 1.0.3 — CI and branch gate

**Implemented locally 2026-08-07; clean remote rerun pending.** One read-only
workflow now gives `master` pull requests, `master` pushes and manual dispatches
the identical job graph. It pins Zig 0.16.0 and current major action versions,
runs the complete local quality and three-mode test gate, executes ReleaseSafe
tests plus a ReleaseFast smoke build on five native hosted targets, and reduces
the quality and native results to stable `CI / gate`. The policy checker locks
the workflow's essential trigger, security, toolchain and matrix contracts. No
artifact publication or release automation was activated.
The first draft-PR probe showed that the prior Zig setup action could stall on
a randomly selected mirror and still used a deprecated Node runtime. CI now
downloads official platform archives directly, verifies their published SHA-256
checksums, caches only the verified exact compiler through the current Node-24
major action, and bounds setup to six minutes. It also keeps source-pinned ZLint
in a separate host-tool package, so normal native and cross-target builds neither
resolve nor fetch lint dependencies. The second probe exposed a missing Unix
execute bit and confirmed that the official native Windows ARM64 compiler exits
silently from `zig build` on the hosted ARM runner. The composite action now
invokes the Unix installer through Bash. A third probe bypassed the build runner
and proved the compiler itself could pass one test before crashing with a Windows
access violation on the next independent test. Windows ARM64 is therefore
removed from current support, along with its special-case gate. The redundant
cross-build job was then removed so every supported platform gate now compiles
and executes natively. Reconsider Windows ARM64 at a stable Zig upgrade and
restore it only through the ordinary path. The step closes only after the
simplified five-target repair passes on the unmerged draft `dev` to `master`
pull request. Manual
dispatch becomes available after the workflow later reaches default `master`.

- Implement the §3.2 branch gate: identical manual and `master`-PR CI,
  post-merge `master` backstop, stable aggregate maintainer gate, exact
  Zig pin, complete quality/test modes and supported platform build matrix.
- Pin only current-stable-compatible dependencies and action revisions. Release
  asset publication remains inert until its later correctness gates exist.

#### 1.1 — UCI behavioural specification

Create a normative command/state/output matrix and process transcript corpus
using Basilisk as the primary compatibility oracle and Stockfish as the
secondary gold-standard cross-check. Resolve differences deliberately. Specify
at minimum:

- `uci`, `debug`, `isready`, `setoption`, `ucinewgame`, `position`, `go`,
  `stop`, `ponderhit`, `quit`, EOF and unknown/malformed input;
- command ordering when search is active, repeated `go`, stale stop signals,
  option barriers and exactly-once `bestmove` publication;
- search-form `go` limits: clocks/increments, `movestogo`, `movetime`, `depth`,
  `nodes`, `mate`, `infinite`, `ponder` and `searchmoves`;
- mutually exclusive diagnostic `go perft`, including exact completion/output
  and the absence of a search `bestmove`;
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
- Implement pin-aware threshold static exchange evaluation as a board-level
  query over attacks, occupancy and pin state. The primitive belongs here
  because `cross-engine-board-v1` requires it in 2.3; Phase 4.1 adds only its
  search integration and ordering use.
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

### Phase 3 — Initial Manta HCE and evaluator-ready state

#### 3.0 — Evaluation boundary

- Implement the Phase-0 evaluator composition using compile-time/static
  selection in the hot path.
- Define score, mate/TB, phase/interpolation and trace contracts. Preserve a
  scalar reference path and an evaluator-independent search-facing API.

#### 3.1 — Initial Manta HCE

- Implement an original Manta HCE informed by Basilisk's accepted concepts and
  values; do not mechanically translate its structure, copy engine code or
  preserve defects.
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

**Representative strength regime.** No game can promote a change until Phase
4.2 delivers the conservative 1T clock policy below. Once its fake-clock,
process and forfeit gates pass, ordinary 1T candidates use one representative
time-based SPRT under §3.3. Fixed-node games are optional diagnostics, not a
second acceptance gate. Phase 6 owns advanced allocation, root confidence,
ponder behavior and SMP timing rather than the first usable clock.

#### 4.0 — Search correctness baseline

- Implement iterative deepening, alpha-beta/PVS, quiescence, legal PVs,
  terminal/draw/mate semantics and interruption-safe result publication.
- Add a typed result-evidence model from the beginning so static evaluation,
  stand pat, qsearch moves, reduced/full search, null and speculative cutoffs
  cannot accidentally gain equal authority later.

#### 4.1 — TT, ordering and diagnostics substrate

- Add TT key/bound/depth/mate conversion/replacement contracts, staged move
  ordering, killers/history and the search integration of the Phase-2 SEE
  primitive, all with deterministic tests.
- Establish diagnostics for tree shape, pruning overlap, best-move recall,
  TT producer/consumer provenance, root stability and stop latency. Diagnostics
  off must preserve the bench fingerprint.

#### 4.2 — UCI baseline completion

- Connect the Phase-1 protocol/control-plane contract to real position and
  search capabilities without moving parsing or I/O into the domain/search
  layers.
- Activate 1T process transcripts for malformed input, go/stop/quit/EOF,
  `searchmoves`, nodes/depth/movetime/infinite, legal PV/bestmove and the
  separate diagnostic `go perft` completion.
- Implement the conservative deterministic 1T clock policy needed for games:
  `movetime`, clocks/increments/moves-to-go, receipt-based accounting, explicit
  move overhead, checked soft/hard budgets, amortized polling and a legal
  completed fallback at the hard deadline. Keep the allocation deliberately
  simple; Phase 6 improves it.
- Pass exhaustive fake-clock boundaries, adverse-scheduling process tests and
  a zero-forfeit smoke match before any result may call Manta
  tournament-capable.

#### 4.3 — Built-in bench and test suites

- Implement the versioned 40-position `bench` contract from §4.2 and establish
  Manta's first accepted fingerprint only after correctness freezes.
- Add a repeated short-search reproducibility job across fresh-game resets and
  varied node limits, plus short Debug/ReleaseSafe self-play smoke games. Treat
  crashes, illegal moves, signature drift and sanitizer/safety failures as CI
  defects rather than Elo questions.
- Add tactical/WAC diagnostics, mate-distance and KBNK/KQK/endgame canaries.
  These detect semantics and explain changes; they do not decide strength.

#### 4.4 — Experiment tooling foundation

- Qualify an exact pinned Colosseum CLI release or source candidate with its
  self-test, capability report and dry runs. Verify Manta UCI options, paired
  openings, adjudication, final production binaries, bounded SPRT/SPSA,
  checkpoints, artifacts and resume behavior.
- Keep only versioned Manta configurations and expected option mappings here.
  Colosseum launches ordinary UCI executables, so do not create a Manta runner
  or duplicate its match/statistics/placement code.

#### 4.5 — 5950X host qualification and shared-tool boundary

- On the actual Ryzen 9 5950X, let Colosseum discover physical/SMT topology and
  reserve capacity. Pilot the representative Phase-5 time control, choose the
  physical-core placement/concurrency profile from measured throughput and
  stability, then run a prospectively sized identical-binary calibration.
- Store exact tool SHA/version, host profile, pair rate, precision target and
  expected/worst wall time. Repeat only after a relevant runner, clock,
  hardware/OS or placement change.
- Contribute any reusable defect or missing capability upstream to Colosseum.
  Use a narrow temporary legacy bridge only for a demonstrated blocker; do not
  fork Colosseum, and remove the bridge after the upstream path qualifies.

### Phase 5 — Evidence-coherent single-thread search

#### 5.0 — Freeze functional baseline

Reproduce the complete correctness/UCI/fingerprint matrix and capture a clean
production manifest. From here, playing changes require the registered gates.
Tournament-capable means the Phase-4 conservative clock policy, harness
calibration and zero-forfeit smoke evidence have passed.

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
of stronger move selection. Prefer one mechanism per candidate. Stage a
coherent reversible bundle only when §3.3 permits it, and spend targeted
ablations only when their expected information exceeds their host cost.

#### 5.2 — Syzygy and endgame integration

- Add replaceable Syzygy probing with strict path/error handling, WDL/DTZ,
  rule-50 semantics, root filtering and score conversion tests.
- Keep tablebase I/O outside the pure board/search policy boundary and ensure
  missing/corrupt files degrade safely.

#### 5.3 — Pre-NNUE freeze and conditional fit

- Freeze the search architecture and parameter consumers. Do not schedule SPSA
  by default: first perform the §3.4 necessity review. Normally retain reasoned
  defaults and defer the consolidated fit until NNUE and its score scale are
  stable. An exceptional pre-NNUE run requires an explicit PLAN amendment and
  user approval.
- Before exposing any contempt option, register a separate investigation of
  static/dynamic contempt, analysis/play semantics, root perspective,
  repetition/rule-50/tablebase interactions and opponent diversity. Adopt only
  with positive native evidence; otherwise record a parked or closed verdict.
- If a fit is exceptionally authorized, bake a clean production candidate, run
  post-fit ablations and accept it only through one representative time-based
  final-binary SPRT.
- Do not tune HCE weights. Exit with a stable 1T baseline suitable for NNUE
  comparison and data generation.

### Phase 6 — Time management, robust UCI parity and SMP

#### 6.0 — Clock and root confidence

- Preserve the Phase-4 monotonic receipt-based clock and hard-deadline safety
  while improving its soft allocation for realistic controls.
- Derive aspiration, time allocation, fallback and later SMP publication from
  one completed-iteration root-confidence model.
- Test clock/increment/movestogo/movetime/ponder overhead, stop latency, minimum
  completed depth and adverse scheduling.
- A playing change to allocation/root policy receives one prospectively chosen
  1T time-based gate representative of its claim; it is not automatically run
  at both STC and LTC.

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
- Measure 1/2/4/8T scaling and require zero forfeits. An SMP playing candidate's
  one authoritative gate is normally 4T `10+0.1`; 1T inertness is established
  by deterministic/process evidence rather than a duplicate SPRT. Higher-thread
  strength is not inferred from scaling data.

### Phase 7 — NNUE runway and data contract

#### 7.0 — State and accumulator contract

- Audit every move/null/unmake path for complete dirty-piece records and
  accumulator push/pop/refresh needs.
- Freeze scalar feature-index, perspective, bucket and quantization references;
  encode architecture/version/endianness metadata from the first network file.

#### 7.1 — Trainer and dataset preflight

- Qualify and pin the shared `net_trainer` revision. It owns engine-agnostic
  game/data tooling, training recipes, quantization/file contract, export,
  checkpoints and reference conformance vectors; reusable improvements land
  upstream there rather than in Manta.
- Define self-play/teacher data schema, sampling, deduplication, train/valid/
  untouched-test splits, label blend, manifests, seeds, resume and integrity
  through that shared contract.
- Manta owns an original Zig loader, scalar inference, dirty-state/accumulator
  integration and optimized backends. Do not copy its C++/Rust examples or
  make the trainer a vendored/runtime dependency.
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

Use multiple network seeds, untouched loss, integer conformance, NPS and
fixed-node quality as the funnel. The clean NNUE candidate that survives it
receives one representative 1T time-based SPRT against HCE; it is not repeated
automatically at fixed nodes, LTC and 4T. Static validation loss alone cannot
promote a network. Keep HCE buildable and continuously tested after NNUE
becomes the default.

### Phase 9 — NNUE frontier and final search fit

#### 9.0 — Residual and disagreement analysis

Use untouched teacher residuals, search disagreements, natural finishes and
game evidence to identify data/architecture gaps. Do not select only by one
loss metric.

#### 9.1 — Architecture ladder

Test evidence-led feature, king/perspective, threat, material/output bucket,
width, activation and refresh changes one axis at a time. Use multiple seeds,
untouched loss, integer conformance and throughput to reject weak candidates
before games; each surviving promotion candidate receives only its one
representative time-based gate.

#### 9.2 — Search/evaluator co-adaptation

- Reopen the Phase-5 search architecture under the retained NNUE. Re-run
  mechanism ablations and inspect histories/correction, pruning margins,
  static-eval consumers, threat inputs and result provenance because a sound
  HCE-era structure or constant need not remain sound with the new evaluator.
- Permit evidence-led structural changes; do not limit this step to retuning
  old numbers. Keep changes original, reversible and independently gated under
  §3.3, with cohesive bundles only where the single-host rule justifies them.
- Freeze the retained search/evaluator consumers only after this pass.

#### 9.3 — Consolidated post-NNUE fit

After network architecture, score scale and parameter consumers freeze, perform
the §3.4 SPSA necessity review and sensitivity pilot. If both pass, authorize
at most one checkpointed consolidated run, normally over 4–8 non-redundant
search/history/time coordinates; more than 12 requires explicit evidence and
approval. Bake the result and submit the clean production candidate to one
representative time-based SPRT. Run only decision-useful ablations. If the
review or pilot does not pass, record the skip and close the phase without
spending the tuning budget.

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
- Inspect emitted instructions and dynamic dependencies on target hardware. A
  successful build and UCI handshake are necessary but not sufficient.

#### 10.1 — Native platform validation

Build and execute Windows x86-64 plus Linux/macOS x86-64 and ARM64.
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
manifests and a cumulative external cohort before a strength release. Activate
the §3.2 draft-release workflow: derive notes from the matching changelog
section, build and natively smoke-test every supported asset from the tag,
verify cross-backend fingerprints, attach hashes/manifests/binaries, and only
then publish the release.

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

Apply the §3.4 necessity review before permitting one HCE fit. Use fixed-node
and throughput measurements as diagnostics, one representative time-based SPRT
for promotion, and the complete platform/ISA plus cumulative release gate only
if an HCE release is actually proposed. NNUE code and evidence remain preserved
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
10. Platform validation is native: production assets compile and run on their
    target hardware.
11. HCE is a bootstrap and fallback, not the strategic optimization sink.
12. The newest stable Zig is a requirement, while exact pinning and manifests
    preserve reproducibility inside that requirement.
13. Prefer small, independently reviewable playing ideas. When single-host
    resolution makes a cohesive bundle rational, a passing gate licenses only
    the bundle and targeted ablations must justify their machine cost.
14. Search and evaluation co-adapt. Re-open HCE-era search assumptions after
    NNUE instead of treating the final stage as parameter tuning alone.
15. Shared infrastructure belongs upstream in Colosseum or `net_trainer`;
    Manta retains original Zig integration and reproducible pinned contracts.

## 7. Release checklist

1. Recheck and migrate to the latest official stable Zig; no nightly compiler.
2. Phase gate and cumulative prior-release match passed.
3. Clean tree; version, license, origin policy and changelog current.
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
10. Required CI passes on the `dev` → `master` pull request; squash merge leaves
    one release commit on `master`. Do not tag, push or publish unless
    explicitly requested.

## 8. Planned command surface

These commands become valid only as their owning phases implement them:

```powershell
zig version
zig build fmt
zig build lint
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
zig build board-bench -Doptimize=ReleaseFast
zig build run -Doptimize=ReleaseFast -- bench 13 1 1
.\tools\build_test.ps1 -Suffix <name>
colosseum-cli capabilities
colosseum-cli self-test
colosseum-cli --run-file .\testing\strength.toml --dry-run --json
colosseum-cli --run-file .\testing\strength.toml
colosseum-cli status <run-directory> --json
colosseum-cli nps <engine> --nodes <registered-node-count>
```
