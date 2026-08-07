# Manta development workflow guide

This is the concise operational roadmap. Detailed rationale, contracts, gates
and phase exit criteria live in [`PLAN.md`](PLAN.md). Conditional experiment
evidence lives in [`EXPERIMENTS.md`](EXPERIMENTS.md).

## Current checkpoint

| Item | State |
|---|---|
| Repository | Planning only; no engine source or build files exist. |
| Current phase | **Phase 0 — Clean Architecture and project contracts** |
| Implementation permission | **Not open.** Finish and approve Phase 0 first. |
| Required Zig | Latest official stable only: **0.16.0**, verified 2026-08-07. No master/dev/nightly builds. |
| UCI | Basilisk-level parity is specified in Phase 1 and completed before tournament release. |
| Evaluation | Zig-idiomatic Basilisk HCE reimplementation first; NNUE is strategic; HCE stays tested as a fallback. |
| Performance shape | Portable scalar oracle plus sibling runtime-selected x86-64/ARM64 backends; final design belongs to Phase 0. |
| Long jobs | None. Do not start SPRT, SPSA, gauntlet, datagen, PGO or timed performance work. |

## Non-negotiable rules

| Rule | Operational meaning |
|---|---|
| Latest stable Zig | Check <https://ziglang.org/download/> at every phase start and release. A newer stable release blocks feature work until migration. Pin and require the exact version; never use nightly. |
| Zig-native code | Use explicit allocators/errors/optionals/tagged unions, precise types, `comptime`, static dispatch and measured `@Vector` kernels. Do not translate C++ or Rust structures mechanically. |
| Zero-cost Clean Architecture | Dependencies and external adapters stay clean, but the hot path gets no heap interfaces, virtual dispatch or speculative indirection. |
| Portable semantics | The scalar implementation is the oracle. Every ISA backend is bit-exact and must have a safe fallback. |
| Quality | Canonical format, AST checks, lint, strict typing, all required test modes and architecture-fitness checks gate every change. |
| Evidence | Perft/bench/WAC/telemetry explain; registered games decide strength. |
| Machine isolation | Never compile or run another timed workload during any game test, tuner, PGO pass or performance benchmark. |
| HCE scope | Reimplement and preserve it, but do not spend the primary development budget tuning it before NNUE. |

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
- A third-party Zig linter becomes mandatory only after a pinned release is
  proven compatible with the required stable Zig. ZLint 0.8.1 currently
  targets Zig 0.15.2, so it cannot be used to justify downgrading from 0.16.0.
- Treat warnings, forbidden dependencies and unannotated unsafe operations as
  failures. Prefer domain-specific enums and integer types over loosely typed
  primitives and flags.

## Phase roadmap

### Phase 0 — Clean Architecture and project contracts

- [ ] **0.0 Scope/provenance/license:** choose the license, define permitted
      Basilisk/Rarog reuse, freeze the first playable scope and list deferred
      features.
- [ ] **0.1 Requirements/quality:** trace functional, performance, safety and
      portability requirements; define units, failure policy, exact toolchain
      guard and the test/CI matrix.
- [ ] **0.2 Architecture:** produce dependency, state-lifetime, runtime and
      concurrency designs plus ADRs for board/state, evaluator, search, UCI,
      clocks, TT, ISA dispatch and file formats.
- [ ] **0.3 Gate:** prove allocator/error/concurrency ownership, test seams and
      zero-cost hot-path composition. Approve implementation explicitly.

No production engine code is written in Phase 0.

### Phase 1 — Repository foundation and UCI behavioural specification

- [ ] Recheck/migrate to the newest official stable Zig.
- [ ] Add version-guarded build/test/lint/CI infrastructure.
- [ ] Freeze Basilisk-parity UCI command/state/output transcripts before board
      or search implementation.
- [ ] Cover command ordering, stop/quit/EOF, isready/options, position errors,
      all `go` limits, ponder semantics, clock start, serialized output, legal
      PV/fallback and exactly one bestmove.
- [ ] Build the asynchronous process-test harness and architecture-fitness
      checks. Later capabilities activate already-specified transcripts rather
      than redefining them.

### Phase 2 — Board, state, move generation and direct board benchmark

- [ ] Select the board/state/move representation through an ADR and measured
      criteria; assert layout and invariants at compile time.
- [ ] Implement FEN, attacks, legality, special moves, make/unmake/null,
      repetition/rule-50, Zobrist and NNUE-ready dirty-piece state.
- [ ] Run canonical/differential perft, randomized round trips, recomputation
      checks and fuzz/property tests.
- [ ] Freeze `cross-engine-board-v1`: identical FENs, operations, work counts,
      warmups, 11 samples, median/MAD, DCE barrier and manifests.
- [ ] Retain historical Basilisk/Rarog compatibility profiles because their
      current board benchmarks differ in one FEN, one workload and statistics.

Required common workloads: legal moves, legal captures, make/unmake, pin-aware
threshold SEE, startpos perft(4), and two-ply game simulation.

### Phase 3 — Bootstrap HCE and evaluator-ready state

- [ ] Define evaluator/score/trace composition with static hot-path dispatch.
- [ ] Reimplement Basilisk's accepted HCE concepts and values idiomatically.
- [ ] Build a reference corpus with component and total parity; document every
      intentional deviation.
- [ ] Test symmetry, endgames, score scale, determinism and throughput.
- [ ] Stop at a solid bootstrap/fallback: no broad HCE feature or tuning cycle.

### Phase 4 — Deterministic 1T search, UCI baseline and tooling

- [ ] Add iterative PVS/qsearch with typed result provenance, legal completed
      fallback and safe interruption.
- [ ] Add TT, SEE, staged ordering, histories and diagnostics with deterministic
      tests.
- [ ] Activate Phase-1 1T UCI transcripts.
- [ ] Implement the shared 40-position
      `bench [depth] [repeats] [threads]` contract. Default 1T fingerprint is
      deterministic; multi-thread nodes are speed data only.
- [ ] Add tactical/WAC, mate/endgame canaries and experiment tooling.
- [ ] Calibrate current Basilisk/Rarog SPRT/SPSA/NPS/gauntlet adapters with a
      harness-neutral manifest.
- [ ] Add Colosseum as an adapter when its CLI is ready; switch only after
      identical-binary calibration and bridge tests.

### Phase 5 — Evidence-coherent single-thread search

- [ ] Freeze the first tournament-capable functional baseline.
- [ ] Add coherent aspiration/root, NMP, selectivity/LMR, IIR/ProbCut/singular,
      history/correction and result-provenance families with ablations.
- [ ] Integrate Syzygy under strict I/O, WDL/DTZ and rule-50 contracts.
- [ ] Freeze architecture, select at most about 24 coordinates, run the one
      pre-NNUE search SPSA, bake, ablate and final-build SPRT it.

### Phase 6 — Time management, robust UCI parity and SMP

- [ ] Use a monotonic clock starting at `go` receipt and one completed-root
      confidence model for timing, aspiration and fallback.
- [ ] Activate every Phase-1 UCI transcript, including stale signals, barriers,
      ponder-after-spent-time, malformed input and legal threaded PVs.
- [ ] Add SMP under explicit pool/result/cancellation ownership.
- [ ] Preserve inert 1T semantics; validate 1/2/4/8T scaling, 1T STC/LTC and 4T
      LTC strength separately with zero forfeits.

### Phase 7 — NNUE runway and data contract

- [ ] Audit dirty state and accumulator refresh/push/pop completeness.
- [ ] Freeze scalar features, perspectives, buckets, quantization and versioned
      endian-defined network format.
- [ ] Define dataset generation, deduplication, splits, labels, seeds,
      manifests, resume and trainer/export conformance.
- [ ] Land no-op scaffolding only when NNUE-off is bench-identical.

### Phase 8 — Baseline NNUE

- [ ] Train reproducible pilots with multiple seeds.
- [ ] Prove trainer export, scalar full refresh and incremental parity across
      randomized games and special moves.
- [ ] Add exact portable, x86-64 and ARM64 inference backends.
- [ ] Gate HCE versus NNUE at fixed nodes, NPS, STC, LTC and 4T. Validation loss
      alone cannot promote. Continue testing HCE after NNUE becomes default.

### Phase 9 — NNUE frontier and final search fit

- [ ] Use untouched residuals, search disagreements and games to drive data and
      architecture changes.
- [ ] Test feature/threat/king/material/bucket/width axes one at a time with
      multiple seeds, integer parity, throughput and games.
- [ ] Freeze network architecture/scale, then run the one post-NNUE search SPSA
      plus clean bake, ablations and SPRT.

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

### Phase 11 — Optional HCE fallback

Enter only after serious NNUE retries fail and the user explicitly chooses it.

- [ ] Document NNUE failure evidence and approve a narrow HCE scope.
- [ ] Select a residual-driven HCE program rather than a broad feature list.
- [ ] Permit one HCE fit, then run full STC/LTC/4T and platform/ISA gates.

## Decision rules

| Situation | Action |
|---|---|
| New stable Zig release | Stop feature work, migrate syntax/APIs/tooling, reproduce all gates, then continue. |
| Dependency/linter lacks latest-stable support | Omit, replace or track it; never downgrade Zig. |
| Behaviour-neutral change | Exact 1T bench plus format/AST/lint/tests and performance evidence when hot. |
| Correctness change affects legal play | Regression and correctness suites, then registered games unless unreachable. |
| Coherent strength candidate | Final production binaries, default `[3,10]` nElo, 12k cap; only H1 promotes. |
| Small knob | Keep inert, bundle coherently or defer to the consolidated fit. Do not spend a full gate casually. |
| SPSA | Once pre-NNUE and once post-NNUE after architecture freeze; HCE only in explicit fallback. |
| Bench node change | Explain, regression-test and record old/new fingerprint in `EXPERIMENTS.md`. |
| Speed claim | Bench identity plus identical-binary calibration and pooled/interleaved A/B. |
| UCI difference from Basilisk | Decide explicitly in an ADR and transcript; never drift accidentally. |
| NNUE baseline loses | Diagnose data, labels, integration and architecture; keep HCE fallback, but do not abandon NNUE casually. |
| Colosseum CLI ready | Add adapter, calibrate and bridge; switch only after equivalent semantics are demonstrated. |

## What happens next

Complete only Phase 0:

1. choose the license and provenance boundary;
2. freeze first-playable/deferred product scope;
3. write requirements and architecture ADRs/diagrams;
4. define the exact quality, CI and platform matrix; and
5. review the zero-cost architecture gate and explicitly authorize Phase 1.

Do not create `src/`, `build.zig`, chess types, UCI code or benchmarks until
Phase 0 is approved. Do not run any long or timed jobs.

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
.\tools\sprt.ps1 -EngineA <candidate> -EngineB <baseline> `
  -NameA Candidate -NameB Baseline -Elo0 3 -Elo1 10 -MaxGames 12000
.\tools\nps_ab.ps1 -EngineA <candidate> -EngineB <baseline> -Rounds 12
```
