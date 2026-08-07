# Manta development workflow guide

This is the concise operational roadmap. Detailed rationale, contracts, gates
and phase exit criteria live in [`PLAN.md`](PLAN.md). Normative acceptance
criteria live in [`REQUIREMENTS.md`](REQUIREMENTS.md). The accepted design is
in [`ARCHITECTURE.md`](ARCHITECTURE.md) and its [ADRs](docs/adr/README.md).
Conditional experiment evidence lives in [`EXPERIMENTS.md`](EXPERIMENTS.md).

## Current checkpoint

| Item | State |
|---|---|
| Repository | Phase 0 is complete; no engine source or build files exist yet. |
| Current phase | **Phase 1.0 — Latest-stable toolchain and build spine**, authorized but not started. |
| Implementation permission | **Open for Phase 1 only.** Board, evaluation and search work remain closed until their owning phases. |
| License | **GPL-3.0-or-later**, copyright (C) 2026 Miloslav Macůrek. |
| Branches | Develop on `dev`. One Phase-0 foundation squash commit establishes `master`; after that `master` takes one required-CI squash merge per release. |
| Required Zig | Latest official stable only: **0.16.0**, verified 2026-08-07. No master/dev/nightly builds. |
| UCI | Basilisk-level parity is specified in Phase 1 and completed before tournament release. |
| Evaluation | Original Zig-native Manta HCE first, informed once by Basilisk's proven features/values; no copied engine code or synchronization. NNUE is strategic; HCE stays tested as a fallback. |
| Performance shape | Portable scalar oracle plus sibling runtime-selected x86-64/ARM64 backends; native local builds prioritize speed. WSL2 is the normal local Linux x86-64 test environment. |
| Long jobs | None in Phase 1. Later game/tuning jobs run serially on the single Ryzen 9 5950X through a calibrated Colosseum host profile and a bounded wall-time budget; other long workloads follow their owning phase. |
| Shared tools | Colosseum owns engine-agnostic game/tuning infrastructure; `net_trainer` owns engine-agnostic NNUE data/training/export contracts. Manta pins them and keeps only original Zig integration plus checked configurations. |

## Non-negotiable rules

| Rule | Operational meaning |
|---|---|
| Latest stable Zig | Check <https://ziglang.org/download/> at every phase start and release. A newer stable release blocks feature work until migration. Pin and require the exact version; never use nightly. |
| Zig-native code | Use explicit allocators/errors/optionals/tagged unions, precise types, `comptime`, static dispatch and measured `@Vector` kernels. Do not translate C++ or Rust structures mechanically. |
| Zero-cost Clean Architecture | Dependencies and external adapters stay clean, but the hot path gets no heap interfaces, virtual dispatch or speculative indirection. |
| Portable semantics | The scalar implementation is the oracle. Every ISA backend is bit-exact and must have a safe fallback. |
| Quality | Canonical format, AST checks, lint, strict typing, all required test modes and architecture-fitness checks gate every change. |
| Domain-meaningful tests | Tests and coding agents must reason from chess rules, search evidence and engine goals, use independent oracles/properties, and never preserve incidental current numbers as truth. |
| Evidence | Perft/bench/WAC/telemetry explain; registered games decide strength. Phase 4 supplies a conservative 1T clock before games begin, then each candidate gets one representative time-based SPRT. Fixed-node games are diagnostic only. |
| Candidate scope | Prefer one independently meaningful idea. Bundle only inseparable, invalid-in-isolation or below-affordable-resolution components behind switches; one passing gate accepts the bundle, not every part. |
| Thread goals | 1T is the deterministic baseline. 4T correctness, time safety, strength and scaling are independent gates; higher-thread behavior is measured, not assumed. |
| Machine isolation | Never compile or run another timed workload during any game test, tuner, PGO pass or performance benchmark. Colosseum measures physical-core placement/concurrency on the real 5950X; do not infer capacity from logical-thread count. |
| Reference checkpoints | At Phases 4–5, 6, 7–9 and 10, refresh exact pinned Basilisk and Stockfish source/material audits for hypotheses and failure modes. Implement original Zig designs; copy no engine code, constants or formulas. |
| HCE scope | Implement and preserve the initial evaluator, but do not spend the primary development budget tuning it before NNUE. |
| Original engine | Engine code, Zig tests, build files and architecture checks are original Manta work. Only established tooling may be adapted; vendored Fathom is the anticipated source exception. |
| Public documentation | README, changelog and release notes remain simple and Manta-focused. Named engine comparisons and priors belong only in PLAN, GUIDE and EXPERIMENTS. |

## Tooling policy

The initial mandatory quality surface, once Phase 1 creates the build spine,
is:

```powershell
zig version
zig fmt --check --ast-check .
zig build lint
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
```

- Zig's formatter defines code style; no competing formatter is permitted.
- The compiler, `ast-check`, project lint rules and tests are authoritative.
- ZLS is recommended and must match the required stable Zig release.
- ZLint 0.9.1 declares Zig 0.16.0 compatibility. Phase 1 pins and evaluates it;
  it becomes part of `zig build lint` only after a reviewed zero-warning
  baseline and reproducible CI pass.
- Treat warnings, forbidden dependencies and unannotated unsafe operations as
  failures. Prefer domain-specific enums and integer types over loosely typed
  primitives and flags.
- Repository `AGENTS.md` is mandatory for coding agents, especially its
  producer/consumer, chess-domain and intentional-exact-value test rules.

## Branch, CI and release workflow

| Stage | Contract |
|---|---|
| Development | Commit numbered steps to `dev` after the applicable local gates. CI can be manually dispatched on `dev` using the complete gate. |
| Release merge | Open `dev` → `master`; required CI runs on the pull request. Squash merge only, with direct `master` pushes prohibited. |
| Master backstop | The same CI runs on every `master` push so the exact release commit is independently recorded as green. |
| CI jobs | Exact Zig guard; docs/link/policy checks; format/AST/lint; Debug, ReleaseSafe and ReleaseFast tests; supported native target builds; later perft/UCI/bench agreement. |
| Local Linux | Use WSL2 for normal Linux x86-64 builds, tests and artifact smoke checks. Retained results record distribution/kernel/WSL versions. |
| Release build | From the exact tagged `master` commit, build and smoke-test native Windows/Linux/macOS x86-64 and ARM64 assets where runners are available; compare deterministic fingerprints and generate hashes/manifests. |
| Publication | Attach verified binaries to a draft GitHub Release, derive its notes from the matching `CHANGELOG.md` section, then publish only after the entire asset matrix succeeds. |

`master` starts with one Phase-0 foundation squash commit so the public default
branch carries the license and accepted contracts; every later `master` commit
is a release.

Portable binaries are mandatory. Measured x86-64 ISA tiers become additional
release assets later and never replace the portable fallback. WSL is not the
sole release proof, an ARM64 validator or final native performance evidence.
Linux libc-free, GNU-linked and static-musl candidates are measured rather
than assuming musl is fastest.

## Phase roadmap

### Phase 0 — Clean Architecture and project contracts

- [x] **0.0 Scope/origin/license:** GPL-3.0-or-later; original Manta engine,
      tests and build code; tooling-only reuse plus licensed Fathom; standard
      chess portable-scalar 1T first-playable scope; advanced features deferred.
- [x] **0.1 Requirements/quality:** `REQUIREMENTS.md` freezes traceable
      functional, performance, safety and portability contracts, score/units,
      resource/failure policy, exact toolchain guard and test/CI/platform
      matrices.
- [x] **0.2 Architecture:** `ARCHITECTURE.md` plus twelve ADRs freeze Zig-native
      Clean Architecture boundaries, explicit lifetimes, caller-owned position
      state, static evaluator/search composition, responsive control, TT/time/
      ISA/format contracts, future-feature seams and zero-cost fitness checks.
- [x] **0.3 Gate:** all 90 requirements and twelve ADRs passed ownership,
      verification-seam, concurrency, shutdown, dependency and hot-path-cost
      review. A re-audit on the same date re-verified the toolchain facts,
      corrected the UCI/perft and dependency contracts, moved SEE to its
      Phase-2 board owner, required a conservative Phase-4 clock before games,
      selected one representative SPRT per candidate and made SPSA conditional.
      Phase 1 is explicitly authorized; later phases remain closed.

No production engine code is written in Phase 0.

### Phase 1 — Repository foundation and UCI behavioural specification

- [ ] Recheck/migrate to the newest official stable Zig.
- [ ] Add version-guarded build/test/lint/CI infrastructure.
- [ ] Implement identical manual and `master`-PR CI plus the post-merge
      `master` backstop, branch-protection check names and the native platform
      matrix. Keep release upload dormant until release gates exist.
- [ ] Freeze primary-reference UCI command/state/output transcripts, with
      Stockfish as the secondary cross-check, before board or search
      implementation.
- [ ] Cover command ordering, stop/quit/EOF, isready/options, position errors,
      all search-form `go` limits, ponder semantics, clock start, serialized
      output, legal PV/fallback and exactly one bestmove; freeze diagnostic
      `go perft` separately with no search bestmove.
- [ ] Build the asynchronous process-test harness and architecture-fitness
      checks. Later capabilities activate already-specified transcripts rather
      than redefining them.

### Phase 2 — Board, state, move generation and direct board benchmark

- [ ] Select the board/state/move representation through an ADR and measured
      criteria; assert layout and invariants at compile time.
- [ ] Implement FEN, attacks, legality, special moves, make/unmake/null,
      repetition/rule-50, Zobrist and NNUE-ready dirty-piece state.
- [ ] Implement pin-aware threshold SEE as a board-level query; the benchmark
      needs it here, and Phase 4.1 adds only its search integration.
- [ ] Run canonical/differential perft, randomized round trips, recomputation
      checks and fuzz/property tests.
- [ ] Freeze `cross-engine-board-v1`: identical FENs, operations, work counts,
      warmups, 11 samples, median/MAD, DCE barrier and manifests.
- [ ] Retain historical Basilisk/Rarog compatibility profiles because their
      current board benchmarks differ in one FEN, one workload and statistics.

Required common workloads: legal moves, legal captures, make/unmake, pin-aware
threshold SEE, startpos perft(4), and two-ply game simulation.

### Phase 3 — Initial Manta HCE and evaluator-ready state

- [ ] Define evaluator/score/trace composition with static hot-path dispatch.
- [ ] Implement original Zig-native evaluator composition informed by the
      accepted reference concepts and values, without copied engine code or an
      ongoing synchronization contract.
- [ ] Build a reference corpus with component and total parity; document every
      intentional deviation.
- [ ] Test symmetry, endgames, score scale, determinism and throughput.
- [ ] Stop at a solid initial/fallback evaluator: no broad HCE feature or
      tuning cycle.

### Phase 4 — Deterministic 1T search, UCI baseline and tooling

- [ ] Add iterative PVS/qsearch with typed result provenance, legal completed
      fallback and safe interruption.
- [ ] Add TT, staged ordering, histories, the SEE search integration and
      diagnostics with deterministic tests.
- [ ] Activate Phase-1 1T UCI transcripts.
- [ ] Implement the shared 40-position
      `bench [depth] [repeats] [threads]` contract. Default 1T fingerprint is
      deterministic; multi-thread nodes are speed data only.
- [ ] Add tactical/WAC, mate/endgame canaries, repeated short-search
      reproducibility CI and short Debug/ReleaseSafe self-play smoke games.
- [ ] Implement and fake-clock/process-test conservative 1T handling for
      `movetime`, clocks/increments/moves-to-go, overhead and hard deadlines;
      pass a zero-forfeit smoke match before strength testing opens.
- [ ] Qualify a pinned Colosseum CLI revision through self-test, capability
      discovery and dry runs; keep only Manta configs/option mapping, not a
      runner adapter or duplicated match/statistics code.
- [ ] On the real 5950X, calibrate physical-core placement, reserved capacity,
      concurrency and identical-binary null bias at the representative
      Phase-5 TC. Size calibration from required precision and measured wall
      time, and record the host profile. Fix generic gaps upstream.

### Phase 5 — Evidence-coherent single-thread search

- [ ] Freeze the first tournament-capable functional baseline after the
      conservative Phase-4 clock and harness gates pass.
- [ ] Add coherent aspiration/root, NMP, selectivity/LMR, IIR/ProbCut/singular,
      history/correction and result-provenance families with ablations.
- [ ] Prefer one mechanism per candidate. Use a reversible cohesive bundle only
      where the single-host rule permits it; do not claim each part of a passing
      bundle helped or run low-value exhaustive ablations.
- [ ] Integrate Syzygy under strict I/O, WDL/DTZ and rule-50 contracts.
- [ ] Freeze architecture and normally defer SPSA until the retained NNUE/search
      system is stable. An exceptional pre-NNUE run needs a written necessity
      review, explicit PLAN amendment and approval; its baked result gets one
      representative time-based final-build SPRT.
- [ ] Investigate contempt only after the baseline freezes; add no UCI option
      unless analysis/play semantics, draw-rule interactions and native games
      provide positive evidence.

### Phase 6 — Time management, robust UCI parity and SMP

- [ ] Preserve the Phase-4 monotonic receipt-based clock and hard deadline while
      improving soft allocation with one completed-root confidence model for
      timing, aspiration and fallback.
- [ ] Activate every Phase-1 UCI transcript, including stale signals, barriers,
      ponder-after-spent-time, malformed input and legal threaded PVs.
- [ ] Add SMP under explicit pool/result/cancellation ownership.
- [ ] Preserve inert 1T semantics; validate 1/2/4/8T scaling and zero forfeits.
      Gate an SMP candidate once, normally at 4T `10+0.1`; do not duplicate it
      automatically at 1T and several time controls.

### Phase 7 — NNUE runway and data contract

- [ ] Audit dirty state and accumulator refresh/push/pop completeness.
- [ ] Freeze scalar features, perspectives, buckets, quantization and versioned
      endian-defined network format.
- [ ] Qualify and pin `net_trainer` as the shared owner of data tooling,
      training recipes, export/file contracts and conformance vectors. Put
      reusable fixes upstream; do not vendor it.
- [ ] Define dataset generation, deduplication, splits, labels, seeds,
      manifests and resume through that contract. Manta owns the original Zig
      loader, inference, accumulator and optimized backends.
- [ ] Land no-op scaffolding only when NNUE-off is bench-identical.

### Phase 8 — Baseline NNUE

- [ ] Train reproducible pilots with multiple seeds.
- [ ] Prove trainer export, scalar full refresh and incremental parity across
      randomized games and special moves.
- [ ] Add exact portable, x86-64 and ARM64 inference backends.
- [ ] Funnel HCE-versus-NNUE candidates with multiple seeds, validation,
      conformance, NPS and fixed-node diagnostics, then give the clean survivor
      one representative 1T time-based SPRT. Continue testing HCE after NNUE
      becomes default.

### Phase 9 — NNUE frontier and final search fit

- [ ] Use untouched residuals, search disagreements and games to drive data and
      architecture changes.
- [ ] Test feature/threat/king/material/bucket/width axes one at a time with
      multiple seeds, integer parity and throughput as the funnel; give only
      surviving promotion candidates their one representative game gate.
- [ ] Reopen Phase-5 search assumptions under the retained NNUE: rerun
      decision-useful ablations and permit structural changes to histories,
      pruning/static-eval consumers, threat evidence and result provenance.
- [ ] Freeze the co-adapted system and perform the SPSA necessity review plus a
      small sensitivity pilot. If justified, run at most one checkpointed fit,
      normally over 4–8 coordinates; more than 12 needs explicit evidence and
      approval. Bake once and run one representative SPRT; otherwise skip.

### Phase 10 — ISA dispatch, platforms, scaling and release maturity

- [ ] Build a portable semantic core with sibling x86-64 baseline, AVX2,
      BMI2/PEXT and ARM64 NEON backends where measurements support them.
- [ ] Keep AVX2 and BMI2 as independent capabilities; CPU feature presence is
      not proof that PEXT is fastest.
- [ ] Validate binaries natively across the supported Windows/Linux/macOS and
      x86-64/ARM64 matrix; inspect emitted instructions and dependencies.
- [ ] Profile before PGO/LTO, cache/layout, TT, vector or NUMA optimization.
- [ ] Add demanded product features through planned seams and release with
      reproducible manifests and external cohort evidence.
- [ ] Activate draft-release publication: notes from `CHANGELOG.md`, exact-tag
      native builds, artifact smoke tests, cross-backend fingerprints,
      checksums and manifests before publishing.

### Phase 11 — Optional HCE fallback

Enter only after serious NNUE retries fail and the user explicitly chooses it.

- [ ] Document NNUE failure evidence and approve a narrow HCE scope.
- [ ] Select a residual-driven HCE program rather than a broad feature list.
- [ ] Apply the SPSA necessity review before one possible HCE fit, then use one
      representative time-based promotion gate; add platform/ISA and cumulative
      release evidence only if an HCE release is proposed.

## Decision rules

| Situation | Action |
|---|---|
| New stable Zig release | Stop feature work, migrate syntax/APIs/tooling, reproduce all gates, then continue. |
| Dependency/linter lacks latest-stable support | Omit, replace or track it; never downgrade Zig. |
| Behaviour-neutral change | Exact 1T bench plus format/AST/lint/tests and performance evidence when hot. |
| Correctness change affects legal play | Regression and correctness suites, then registered games unless unreachable. |
| Coherent strength candidate | Final production binaries; one prospectively chosen representative time-based SPRT, default `[3,10]` nElo at 1T `3+0.03`, 12k cap; only H1 promotes. |
| Small idea or knob | Test independently when its likely signal justifies the host cost; otherwise keep it inert, include it in one reversible mechanism-level bundle or defer it. |
| Cohesive bundle | Only inseparable, invalid-in-isolation or below-resolution parts; preserve switches, exclude unrelated work and use one gate. A pass accepts only the bundle. |
| SPSA | Never automatic. Normally defer until NNUE/search/score-scale freeze; require a necessity review, sensitivity pilot, explicit authorization, normally 4–8 coordinates, checkpoints and a measured 5950X wall-time budget. |
| Bench node change | Explain, regression-test and record old/new fingerprint in `EXPERIMENTS.md`. |
| Speed claim | Bench identity plus identical-binary calibration and pooled/interleaved A/B. |
| UCI difference from Basilisk | Decide explicitly in an ADR and transcript; never drift accidentally. |
| NNUE baseline loses | Diagnose data, labels, integration and architecture; keep HCE fallback, but do not abandon NNUE casually. |
| Colosseum capability gap | Contribute the generic fix upstream. Use a narrow temporary legacy bridge only for a demonstrated blocker and remove it after qualification. |
| Shared NNUE tooling gap | Improve `net_trainer` upstream; keep only Manta-specific original Zig integration in this repository. |

## What happens next

Phase 1 is authorized but no Phase-1 implementation has started. Begin with
step 1.0: recheck the latest official stable Zig, decide the minimal build
module/test layout and freeze the CI check names before creating the build
spine. Then specify UCI behaviour and its process harness as Phase 1 requires.

Do not implement board representation, move generation, evaluation, search or
later features. Do not run any long or timed jobs.

## Working rhythm

```text
You   -> Ask for the next numbered step or return requested long-job artifacts.
Model -> Implements one step, verifies, updates PLAN + GUIDE (+ ledger), commits.
You   -> Runs only an explicitly requested SPSA/SPRT/gauntlet/datagen job.
```

## Planned common commands

These become available in their owning phases:

```powershell
zig version
zig fmt --check --ast-check .
zig build lint
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
zig build board-bench -Doptimize=ReleaseFast
zig build run -Doptimize=ReleaseFast -- bench 13 1 1
colosseum-cli capabilities
colosseum-cli self-test
colosseum-cli --run-file .\testing\strength.toml --dry-run --json
colosseum-cli --run-file .\testing\strength.toml
colosseum-cli status <run-directory> --json
```
