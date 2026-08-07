# Manta experiment ledger

This is the indexed maintainer record of Manta measurements and the conditional
lessons they support. It is not a roadmap: [`PLAN.md`](PLAN.md) owns sequencing
and gates; [`GUIDE.md`](GUIDE.md) is the short operational view. Future
`CHANGELOG.md` remains user-facing.

Manta currently has no implementation and therefore no native experiment
results. The imported Basilisk/Rarog rows below are priors that shape test
design. They never accept a Manta change or establish Manta Elo.

## Contents

- [1. How to use this ledger](#1-how-to-use-this-ledger)
  - [Evidence vocabulary](#evidence-vocabulary)
  - [Recording contract](#recording-contract)
  - [Artifact contract](#artifact-contract)
- [2. Measurement, harness and tuning](#2-measurement-harness-and-tuning)
- [3. Board, state and correctness](#3-board-state-and-correctness)
- [4. UCI, root, time management and SMP](#4-uci-root-time-management-and-smp)
- [5. Search and selectivity](#5-search-and-selectivity)
- [6. Evaluation, NNUE and data](#6-evaluation-nnue-and-data)
- [7. Throughput, build and platforms](#7-throughput-build-and-platforms)
- [8. Imported Basilisk/Rarog priors](#8-imported-basiliskrarog-priors)
- [9. Open retry and adoption map](#9-open-retry-and-adoption-map)
- [10. New experiment template](#10-new-experiment-template)

## 1. How to use this ledger

Search by subsystem and stable ID before proposing a mechanism, tune, tool
change or retry. Cite IDs in commit messages and `PLAN.md` when evidence changes
a future decision. Do not copy ledger tables into the roadmap.

Every result is conditional on one source state, Zig/compiler, build pipeline,
machine population, time control, book, adjudication and engine interaction.
Use cautious language: “under these conditions this suggests …”, never
“feature X is universally good/bad.”

### Evidence vocabulary

| Term | Meaning |
|---|---|
| **Accepted** | Passed its prospectively registered gate and entered the accepted Manta baseline. |
| **Retained** | Kept for correctness, infrastructure or structural value; strength may be unresolved. |
| **Rejected** | Failed its registered gate or had clear adverse evidence and was reverted/disabled. |
| **Neutral/inconclusive** | The registered evidence did not distinguish a useful effect at its resolution. |
| **Observation** | Diagnostic or benchmark evidence; not an acceptance verdict. |
| **Imported prior** | Evidence from Basilisk/Rarog or elsewhere. It may shape Manta experiment order/design but never bypasses Manta gates. |
| **Parked** | Not accepted; preserved inert or on a branch until an objective retry trigger occurs. |

### Recording contract

Every experiment that reaches a verdict updates this file in the same commit
that accepts, reverts or closes it. Record:

1. stable ID, date, owner, baseline and candidate source SHAs;
2. dirty-diff hash if either source was dirty;
3. hypothesis and interacting producers/consumers expected to change;
4. prospectively registered gate, hypotheses, budget and stop rule;
5. exact Zig/LLVM, target/features, build options and PGO manifest;
6. binary, book, configuration, dependency and network/data hashes;
7. TC, threads, Hash, concurrency, physical-core affinity/topology and
   adjudication profile;
8. games, W-D-L, estimate/CI and LLR where applicable;
9. diagnostics separately from the verdict: fingerprint, nodes, depth, EBF,
   NPS, recall, contradictions, counters, static loss and suites;
10. disposition, conditional lesson, objective retry trigger and artifact paths.

Do not add accepted-arm Elo values together as a rating forecast. Fast-TC
results may compress or reverse at longer time controls. A successful SPSA
trajectory is a proposal, not proof; its baked production binary requires the
registered SPRT.

### Artifact contract

- Store large PGNs, binaries, books, networks, datasets and profiles outside
  Git under a versioned manifest; commit only compact durable metadata.
- Record source and artifact hashes before a long job starts.
- A dirty binary may diagnose but cannot become an accepted/release baseline.
- Never time builds/benchmarks/games while another load is active. Record any
  contamination and discard timing evidence rather than rationalize it.
- Harness/runner changes use identical-binary calibration before engine
  candidates resume.
- When Colosseum becomes the default runner, preserve bridge manifests and the
  last calibrated legacy adapter so old evidence remains interpretable.

## 2. Measurement, harness and tuning

No native Manta experiments yet.

Future IDs use `MAN-Mnn`.

| ID | Experiment and conditions | Result / disposition | Conditional lesson and retry trigger | Source |
|---|---|---|---|---|
| — | — | — | — | — |

## 3. Board, state and correctness

No native Manta experiments yet.

Future IDs use `MAN-Bnn`.

The Phase-2 board benchmark must name its exact profile:

| Profile | Purpose | Direct comparison rule |
|---|---|---|
| `basilisk-board-v1` | Reproduce Basilisk's current corpus/workload/statistics for historical comparison. | Compare only runs using this exact profile and manifest. |
| `rarog-board-v1` | Reproduce Rarog's current corpus/workload/statistics for historical comparison. | Compare only runs using this exact profile and manifest. |
| `cross-engine-board-v1` | Reconciled five-position, six-workload, median/MAD contract for future three-engine comparisons. | All engines must execute identical manifest/work counts on the same idle host. |

Required `cross-engine-board-v1` workloads are legal moves, legal captures,
make/unmake, pin-aware threshold SEE over captures, startpos perft(4), and
two-ply game simulation. The finalized manifest and hashes are recorded as the
first `MAN-Bnn` observation before any performance optimization.

| ID | Experiment and conditions | Result / disposition | Conditional lesson and retry trigger | Source |
|---|---|---|---|---|
| — | — | — | — | — |

## 4. UCI, root, time management and SMP

No native Manta experiments yet. Future IDs use `MAN-Unn` for protocol and
`MAN-Rnn` for root/time/SMP.

UCI transcript tests are specifications, not experiments. A deliberate change
from the Phase-1 contract receives an ADR and regression; only performance or
strength claims receive an experiment verdict.

| ID | Experiment and conditions | Result / disposition | Conditional lesson and retry trigger | Source |
|---|---|---|---|---|
| — | — | — | — | — |

## 5. Search and selectivity

No native Manta experiments yet.

Future IDs use `MAN-Snn`.

| ID | Experiment and conditions | Result / disposition | Conditional lesson and retry trigger | Source |
|---|---|---|---|---|
| — | — | — | — | — |

## 6. Evaluation, NNUE and data

No native Manta experiments yet.

Future IDs use `MAN-Enn` for HCE/evaluation, `MAN-Nnn` for NNUE and `MAN-Dnn`
for datasets/training.

The Phase-3 Basilisk HCE reference corpus is a conformance record, not proof of
strength. Intentional differences from Basilisk receive native Manta IDs and
must separate correctness/design rationale from later game evidence.

| ID | Experiment and conditions | Result / disposition | Conditional lesson and retry trigger | Source |
|---|---|---|---|---|
| — | — | — | — | — |

## 7. Throughput, build and platforms

No native Manta experiments yet.

Future IDs use `MAN-Pnn`.

| ID | Experiment and conditions | Result / disposition | Conditional lesson and retry trigger | Source |
|---|---|---|---|---|
| — | — | — | — | — |

## 8. Imported Basilisk/Rarog priors

These rows are explicitly **not Manta results**. They capture lessons worth
designing around and the Manta phase that must verify them locally.

| ID | Imported evidence | Manta implication | PLAN coverage |
|---|---|---|---|
| MAN-X01 | Basilisk/Rarog found scheduler placement and concurrent compilation/timing capable of moving small game and NPS readings materially. | Discover physical cores, pin explicitly, reserve capacity, forbid concurrent timed work, and calibrate identical binaries before candidate tests. | §3.1–3.2, 4.4 |
| MAN-X02 | Both engines encountered tuners fitted around defects or incomplete mechanisms; a correct standalone repair could look strongly negative until consumers were jointly refit. | Freeze architecture before SPSA, keep related mechanisms ablatable, diagnose interactions and use post-fit ablations. | §3.3, 5.1–5.3 |
| MAN-X03 | Exact bench node identity survived behaviour-neutral speed work, but single-build/single-run NPS comparisons produced misleading conclusions. | Treat fingerprint as behaviour evidence only; use identical-binary calibration plus pooled/interleaved independent production builds for speed. | §3.2, 4.2, 10.2 |
| MAN-X04 | KBNK/KQK, mate-distance, WAC, perft and rule-50 tests caught semantic failures but did not predict Elo reliably. | Keep canaries mandatory while reserving strength verdicts for registered games. | §3.2, 4.3 |
| MAN-X05 | Multi-thread fixes and strength gains differed radically from 1T behavior; private helper clocks, node budgets and result ownership caused real failures. | Design SMP ownership before implementation and gate clock safety/strength independently at 1T and 4T. | 0.2, 6.0–6.2 |
| MAN-X06 | Repeated HCE work in Basilisk stopped transferring reliably, while both engines identified NNUE as the main evaluation path. | Use Basilisk HCE as bootstrap/oracle/fallback, keep it maintained, but direct normal evaluation investment to NNUE. | 3, 7–9, 11 |
| MAN-X07 | Cross-compiled ARM/x86 assets could handshake and agree on nodes while still lacking proven ISA behavior or native speed. | Inspect emitted instructions and dependencies; require target-native correctness and performance before release. | 10.0–10.1 |
| MAN-X08 | Robust process tests exposed ordering, EOF, stale stop, ponder, spent-clock, threaded PV and malformed-input defects not covered by parser unit tests. | Freeze UCI transcripts in Phase 1 and complete process parity before tournament use. | 1.1–1.2, 4.2, 6.1 |
| MAN-X09 | Current Basilisk and Rarog board benchmarks use similar names but differ in one FEN, one hot operation and sample/estimator choices. | Maintain historical profiles and publish an identical versioned cross-engine manifest before direct comparison. | §4.1, 2.3 |
| MAN-X10 | Search bounds from static eval, stand pat, qsearch, ProbCut, null, reduced and full searches were not interchangeable; provenance leaks caused unsafe consumers. | Introduce typed result evidence with the initial search rather than retrofit it after tuning. | 4.0–4.1, 5.1 |
| MAN-X11 | Root aspiration, timing, legal fallback and helper-result selection became inconsistent when driven by separate confidence signals. | Define one completed-root evidence model and use it across root consumers. | 5.1, 6.0–6.2 |
| MAN-X12 | SPSA schedule/unit/default drift and tune-only option mismatches invalidated assumptions even when runs appeared to converge. | Generate defaults/options/clamps from one source, assert every emitted perturbation and register schedule/horizon before launch. | §3.3, 4.4 |
| MAN-X13 | Fast-TC accepted gains compressed materially at longer time controls and external opponents. | Use STC for iteration but require LTC, 4T and external cohorts at phase/release boundaries. | §3.2, 6.2, 10.3 |
| MAN-X14 | NNUE static loss, teacher transfer and training trajectories did not consistently predict playing strength. | Require untouched sets, multiple seeds, integer conformance, NPS and SPRT; do not promote on loss alone. | 7–9 |
| MAN-X15 | PEXT availability did not imply equal performance across x86 microarchitectures; ISA labels, build flags and runtime checks could drift. | Model AVX2/BMI2 as sibling capabilities, include measured microarchitecture suitability and make artifact/runtime contracts executable. | 10.0 |

## 9. Open retry and adoption map

This table contains repository-wide tool or hypothesis triggers that are not
yet Manta experiments.

| Item | Current state | Objective trigger | Destination |
|---|---|---|---|
| Third-party Zig linter | ZLint 0.8.1 targets Zig 0.15.2 and is incompatible with Manta's latest-stable 0.16.0 policy. | A pinned linter release explicitly supports the then-current stable Zig, passes its own tests, and produces a reviewed zero-warning Manta baseline. | Phase 1 quality pipeline |
| Colosseum runner | Desired future default; required CLI surface is not yet complete. | CLI supports Manta's SPRT/SPSA/gauntlet/manifests/affinity/adjudication needs; identical-binary calibration and legacy bridge pass. | Phase 4.5 |
| HCE tuning | Closed during the normal NNUE path. | Serious NNUE retries fail and the user explicitly enters Phase 11 after written review. | Phase 11 |
| Additional pre/post-NNUE SPSA | Not authorized. | Evidence demonstrates that the registered consolidated fit could not identify the necessary parameter class. | Explicit PLAN amendment |

An imported prior or parked item becomes a new Manta experiment with a new
native ID. It never overwrites historical evidence.

## 10. New experiment template

```markdown
### MAN-<area><number> — <short name>

- Date / owner:
- Baseline SHA / candidate SHA / dirty-diff hash:
- Hypothesis and interacting producers/consumers:
- Registered gate, hypotheses, budget and stop rule:
- Build: Zig/LLVM, optimize mode, target/features, PGO manifest:
- Artifacts: binary/book/config/network/data/dependency hashes:
- Games: TC, threads, Hash, concurrency, physical cores/affinity, adjudication:
- Result: games, W-D-L, Elo/nElo and CI, LLR:
- Deterministic evidence: tests, perft, fingerprint, conformance:
- Diagnostics: nodes, EBF, NPS, depth, recall, contradictions, counters, loss:
- Disposition: accepted / retained / rejected / neutral / observation / parked:
- Conditional lesson:
- Objective retry trigger or `closed`:
- Artifact/manifests / commits:
```
