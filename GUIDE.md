# Manta development workflow guide

This is the concise operational roadmap. Detailed rationale, contracts, gates
and phase exit criteria live in [`PLAN.md`](PLAN.md). Normative acceptance
criteria live in [`REQUIREMENTS.md`](REQUIREMENTS.md). The accepted design is
in [`ARCHITECTURE.md`](ARCHITECTURE.md) and its [ADRs](docs/adr/README.md).
Conditional experiment evidence lives in [`EXPERIMENTS.md`](EXPERIMENTS.md).

## Current checkpoint

| Item | State |
|---|---|
| Repository | Phase 0 and steps 1.0.1–1.0.2 are complete. Step 1.0.3 is implemented locally and awaits its first remote CI run. No UCI or chess behaviour exists. |
| Current phase | **Step 1.0.3 — CI and branch gate**, awaiting remote validation. |
| Implementation permission | **Open for Phase 1 only.** Board, evaluation and search work remain closed until their owning phases. |
| License | **GPL-3.0-or-later**, copyright (C) 2026 Miloslav Macůrek. |
| Branches | Develop on `dev`; `master` takes one required-CI squash merge per release. The sole publisher enforces the gate and resets `dev` only after the release and post-merge checks are final. |
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

The initial mandatory quality surface, now provided by the Phase-1 build spine,
is:

```powershell
zig version
zig build fmt
zig build lint
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
```

- Zig's formatter defines code style; no competing formatter is permitted.
- The compiler, `ast-check`, project lint rules and tests are authoritative.
- ZLS is recommended and must match the required stable Zig release.
- ZLint 0.9.1 is source-pinned in an isolated host-tool package and remains part
  of `zig build lint`; normal builds do not resolve its dependencies.
- Treat warnings, forbidden dependencies and unannotated unsafe operations as
  failures. Prefer domain-specific enums and integer types over loosely typed
  primitives and flags.
- Repository `AGENTS.md` is mandatory for coding agents, especially its
  producer/consumer, chess-domain and intentional-exact-value test rules.

## Branch, CI and release workflow

| Stage | Contract |
|---|---|
| Development | Commit numbered steps to `dev` after local gates. Once the workflow exists on default `master`, it can be manually dispatched on `dev`; bootstrap it first with an unmerged draft PR. |
| Release merge | Open `dev` → `master`; required CI runs on the pull request. The sole publisher enforces squash-only acceptance without repository branch protection. |
| Master backstop | The same CI runs on every `master` push. Verify it, the finalized release and a clean worktree before resetting `dev` to `master`. |
| CI jobs | Checksum-verified official Zig with bounded cached setup; docs/link/policy checks; format/AST/lint; Debug, ReleaseSafe and ReleaseFast tests; five supported native target builds; later perft/UCI/bench agreement. |
| Local Linux | Use WSL2 for normal Linux x86-64 builds, tests and artifact smoke checks. Retained results record distribution/kernel/WSL versions. |
| Release build | From the exact tagged `master` commit, build and smoke-test Windows x86-64 plus Linux/macOS x86-64 and ARM64 assets where runners are available; compare deterministic fingerprints and generate hashes/manifests. |
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

Each `N.x` item is one discuss → implement → verify → document → commit step.
A phase closes only after all of its steps pass. If a step is later divided,
its indented children use `N.x.y`; unnumbered explanatory bullets are not
separate implementation units.

### Phase 0 — Clean Architecture and project contracts

- [x] **0.0 — Product scope, origin and licensing:** Define Manta's identity,
      standard-chess scope, originality policy and GPL license.
- [x] **0.1 — Requirements and quality model:** Freeze normative behavior,
      measurements, platforms, CI and release expectations.
- [x] **0.2 — Architecture design:** Define Zig-native Clean Architecture,
      ownership, concurrency, hot-path and future-feature boundaries.
- [x] **0.3 — Architecture proof and exit gate:** Audit all contracts and
      authorize Phase 1 without writing production engine code.

### Phase 1 — Repository foundation and UCI behavioural specification

- [ ] **1.0 — Latest-stable toolchain and build spine:** Pin current stable Zig
      and create the minimal build, test, lint and CI foundation.
  - [x] **1.0.1 — Toolchain and build spine:** Add the exact Zig guard, package,
        executable, library facade and three-mode test foundation.
  - [x] **1.0.2 — Quality and development tooling:** Add formatting, AST,
        project-policy, ZLint and ZLS guidance gates.
  - [ ] **1.0.3 — CI and branch gate:** Add the identical manual/PR/master
        workflow, native/cross-target matrix and stable aggregate check.
- [ ] **1.1 — UCI behavioural specification:** Freeze command, state, timing,
      output and diagnostic transcript behavior before chess implementation.
- [ ] **1.2 — Test harness and repository policy:** Build the asynchronous
      process harness, architecture checks and repository quality gates.

### Phase 2 — Board, state, move generation and direct board benchmark

- [ ] **2.0 — Domain types and representation decision:** Select and document
      move, board, state and layout contracts from measured criteria.
- [ ] **2.1 — State transitions and legality:** Implement legal chess state,
      moves, hashing, history and NNUE-ready dirty records.
- [ ] **2.2 — Correctness campaign:** Prove rules and reversible state through
      perft, independent recomputation, properties and fuzzing.
- [ ] **2.3 — Board benchmark:** Freeze and measure the comparable board/SEE
      workload contract before optimizing it.

### Phase 3 — Initial Manta HCE and evaluator-ready state

- [ ] **3.0 — Evaluation boundary:** Define score, evaluator and trace contracts
      with static hot-path composition.
- [ ] **3.1 — Initial Manta HCE:** Implement and verify the original Zig-native
      bootstrap evaluator against the reference corpus.
- [ ] **3.2 — Strategic HCE limit:** Freeze a solid fallback without starting a
      broad HCE feature or tuning program.

### Phase 4 — Deterministic 1T search, UCI baseline and tooling

- [ ] **4.0 — Search correctness baseline:** Add deterministic iterative
      search, qsearch, typed result provenance and safe interruption.
- [ ] **4.1 — TT, ordering and diagnostics substrate:** Add transposition,
      ordering, history, SEE integration and search observability.
- [ ] **4.2 — UCI baseline completion:** Connect real search to the Phase-1 UCI
      contract and deliver a conservative, forfeit-safe 1T clock.
- [ ] **4.3 — Built-in bench and test suites:** Freeze the bench fingerprint,
      search reproducibility CI and tactical/endgame canaries.
- [ ] **4.4 — Experiment tooling foundation:** Qualify pinned Colosseum
      workflows and retain only Manta configuration and option mapping.
- [ ] **4.5 — 5950X host qualification and shared-tool boundary:** Calibrate
      placement, concurrency, null bias and bounded job budgets on the real host.

### Phase 5 — Evidence-coherent single-thread search

- [ ] **5.0 — Freeze functional baseline:** Capture the first clean,
      tournament-capable deterministic production baseline.
- [ ] **5.1 — Search architecture:** Add evidence-led 1T search mechanisms as
      independent candidates or justified reversible bundles.
- [ ] **5.2 — Syzygy and endgame integration:** Add replaceable WDL/DTZ probing
      under strict rule-50, score and I/O contracts.
- [ ] **5.3 — Pre-NNUE freeze and conditional fit:** Freeze search, investigate
      contempt and defer tuning unless its necessity is explicitly proven.

### Phase 6 — Time management, robust UCI parity and SMP

- [ ] **6.0 — Clock and root confidence:** Improve allocation around one
      completed-root confidence model while preserving hard-deadline safety.
- [ ] **6.1 — Full Phase-1 UCI parity:** Activate the complete robust protocol
      transcript matrix against real engine capabilities.
- [ ] **6.2 — SMP:** Add explicit worker/result/cancellation ownership and gate
      1T inertness, 4T strength and wider scaling separately.

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

Enter only after serious NNUE retries fail and the user explicitly chooses it.

- [ ] **11.0 — Failure review and scope decision:** Document NNUE failure and
      explicitly authorize a narrow fallback program.
- [ ] **11.1 — HCE residual program:** Select only evidence-led HCE work not
      already answered by the NNUE path.
- [ ] **11.2 — HCE fit and release:** Tune only if justified, then gate one
      clean candidate and add release evidence only if it will ship.

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

Step 1.0.3's draft-PR probes exposed CI setup defects and an unstable Zig 0.16.0
Windows ARM64 toolchain. Windows ARM64 has been removed from current support;
the simplified five-platform repair now needs a clean rerun on the existing
unmerged draft pull request. Phase 1.1 remains closed until that matrix and the
stable `CI / gate` pass. Manual dispatch becomes available only after the
workflow exists on default `master`.

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
zig build fmt
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
