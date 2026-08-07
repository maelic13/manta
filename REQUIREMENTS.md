# Manta requirements

This document is the normative, maintainer-facing contract for Manta. It
states what the engine and its delivery process shall do in terms that can be
verified by tests, CI, benchmarks, manifests or release evidence.

[`PLAN.md`](PLAN.md) owns sequencing and rationale. [`GUIDE.md`](GUIDE.md) is
the concise operational view. [`EXPERIMENTS.md`](EXPERIMENTS.md) records
conditional evidence. [`ARCHITECTURE.md`](ARCHITECTURE.md) and its
[ADRs](docs/adr/README.md) own implementation-independent design decisions;
requirements deliberately avoid duplicating that design.

## 1. Requirement governance

`Shall` and `must` are release-gating. `Should` is a recommendation that may be
departed from with written rationale. Each normative statement has a stable
identifier:

| Prefix | Area |
|---|---|
| `FUNC` | Product and chess behaviour |
| `UCI` | Protocol behaviour |
| `SCORE` | Evaluation, mate and measurement conventions |
| `RES` | Resource bounds |
| `SAFE` | Failure and recovery behaviour |
| `FILE` | External and persisted data |
| `PERF` | Performance and determinism |
| `PORT` | Targets, builds and portability |
| `QUAL` | Static quality and verification |
| `REL` | CI and release process |

All requirements in this initial revision are **specified**: their wording has
been accepted, while implementation verification belongs to the owning phase.
When a requirement becomes executable, its tests, CI check or evidence
manifest shall cite its ID. A requirement may change only deliberately, with
the roadmap and guide updated in the same change and an ADR when observable
behaviour or architecture is affected.

## 2. Terminology and units

| Term | Contract |
|---|---|
| Root side | The side to move in the position supplied to the current search. |
| Ply | One move by one side. Internal mate distance, search stacks and selective depth use plies. |
| Depth | Nominal completed iterative-search depth in plies. A requested UCI depth is a search limit, not a promise that every branch has that length. |
| Selective depth | Greatest ply reached by the reported search, measured from root ply zero. |
| Node | One invocation of the versioned main-search or quiescence-search node contract. The exact inclusion rules freeze with the first deterministic bench. |
| Centipawn (`cp`) | User-facing evaluation unit where 100 approximates one pawn. Internal evaluator units may differ but shall be converted before UCI output. |
| Millisecond (`ms`) | All UCI clock and elapsed-time values. Search timing uses a monotonic clock. |
| Byte | Eight bits. File sizes and hashes operate on bytes. |
| MiB | 1,048,576 bytes. `Hash` and memory manifests use MiB, never ambiguous `MB`. |
| NPS | Counted nodes divided by monotonic elapsed seconds; descriptive throughput, never a strength verdict. |
| Portable build | A release build whose declared baseline CPU features run on the documented target population. |
| Native build | A build specialized for the executing host with `cpu=native`; it is not assumed portable. |
| Fingerprint | The exact deterministic one-thread node total for a versioned bench input and reset contract. |

### 2.1 Score and mate model

| ID | Requirement | Owner | Verification |
|---|---|---:|---|
| `SCORE-001` | Draw and neutral evaluation shall be `0`. Positive scores favour the side to move at an internal node; root UCI output shall be from the root side's perspective. | 3–4 | Unit and search tests |
| `SCORE-002` | Search calculations shall use a signed 32-bit score domain. `MATE` shall be `32000`, `INFINITY` shall be `32001`, and `NONE` shall be `32002`. `INFINITY` is a search bound; `NONE` is a sentinel and shall never enter arithmetic or UCI output. Any later compact storage representation requires checked, lossless conversion for every representable search score. | 3–4 | Compile-time, range and unit tests |
| `SCORE-003` | `MAX_PLY` shall be `256`. Valid search-ply indices are `0...255`; per-ply storage shall add and document any sentinel or look-ahead padding separately. | 0.2, 2, 4 | Layout and boundary tests |
| `SCORE-004` | A win in `p` plies shall be `MATE - p`; a loss in `p` plies shall be `-MATE + p`. Transposition-table storage shall normalize mate distance to and from the current ply without changing ordering. | 4 | Mate and TT round-trip tests |
| `SCORE-005` | The lowest mate-band magnitude shall be `MATE - MAX_PLY` (`31744`). Future tablebase values shall occupy a distinct reserved band below mate values; ordinary evaluations shall never enter either decisive band. | 3, 5 | Range assertions and conversion tests |
| `SCORE-006` | A requested UCI search depth shall be represented as an optional limit and normalized to at most `MAX_PLY - 1`. Manta shall not introduce a second unrelated maximum-search-depth constant. | 1, 4 | Parser and boundary transcripts |
| `SCORE-007` | UCI mate output shall count moves, not plies: positive internal distance uses `(plies + 1) / 2`; negative distance uses division by two toward zero. A currently checkmated root reports `score mate 0`. | 1, 4 | Exact mate transcript corpus |
| `SCORE-008` | The initial HCE shall use a stable user-facing scale near 100 cp per pawn. A later evaluator may use another internal scale only behind an explicit, tested UCI conversion. | 3, 8 | Evaluation and UCI tests |
| `SCORE-009` | The accepted baseline shall have no contempt adjustment and no public contempt option. After the single-thread baseline freezes, Phase 5 shall investigate static/dynamic contempt, analysis/play behaviour and draw-rule interactions; an option is added only after positive native evidence. | 5 | Registered experiment or parked verdict |

## 3. Product and protocol requirements

| ID | Requirement | Owner | Verification |
|---|---|---:|---|
| `FUNC-001` | Manta shall implement orthodox standard chess correctly. No variant behaviour is part of the initial product contract. | 2–4 | Perft, invariants and game tests |
| `FUNC-002` | Rules, search, evaluation and external adapters shall remain separable enough to add a variant later without embedding variant conditionals throughout the hot path. No speculative variant implementation is required. | 0.2–0.3 | ADR and dependency-fitness review |
| `FUNC-003` | The first-playable engine shall be a portable, scalar, single-thread UCI executable with complete legal move handling, deterministic search, an original HCE, depth/node/movetime/infinite/stop control and a conservative deterministic policy for ordinary clocks/increments/moves-to-go. | 4 | Phase-4 acceptance matrix |
| `FUNC-004` | Every completed search shall return exactly one legal `bestmove`, or, in a terminal position, the no-legal-move token frozen by the Phase-1 transcript contract. UCI itself defines no such token, so the chosen spelling is a deliberate compatibility decision, not an inherited default. Cancellation and failure shall never publish an illegal move. | 1, 4, 6 | Process transcript tests |
| `FUNC-005` | One-thread search from a fixed position, configuration, seed and cleared state shall be deterministic across supported targets and exact backends. | 4, 8, 10 | Fingerprint and backend tests |
| `FUNC-006` | Manta's engineering objective shall be playing strength under correct chess and UCI semantics. Design and implementation work shall consider chess meaning, search quality, throughput and measured 1T/4T behavior rather than similarity to an existing implementation or preservation of incidental numbers. | All | Review, diagnostics and registered games |

Phase 1 shall expand the following protocol requirements into a complete
command/state/output transcript matrix before chess behaviour is implemented:

| ID | Requirement | Owner | Verification |
|---|---|---:|---|
| `UCI-001` | Manta shall implement UCI with complete, serialized stdout lines. While a protocol session is active, stdout shall carry protocol output plus the output of explicitly specified diagnostic commands only. `bench` (§4.2 of `PLAN.md`) and `go perft` are such commands and each owns a frozen output contract; unsolicited or incidental non-protocol stdout is forbidden and diagnostics belong on stderr. | 1 | Process transcripts |
| `UCI-002` | `uci`, `isready`, `setoption`, `ucinewgame`, `position`, `go`, `stop`, `ponderhit`, `quit` and EOF shall have explicit state-transition and ordering contracts. | 1, 6 | State matrix and transcripts |
| `UCI-003` | Each accepted search-form `go` shall publish exactly one `bestmove` while the protocol session remains writable; diagnostic `go perft` is excluded and owns a separate completion/output contract. Repeated commands, stale stop signals and concurrent completion shall not duplicate or suppress a required `bestmove`. `quit`, EOF or fatal output may end the session before publication. | 1, 4, 6 | Race-oriented process tests |
| `UCI-004` | Clock accounting shall begin when `go` is received, use monotonic time, and include dispatch delay. | 1, 4, 6 | Fake-clock and process tests |
| `UCI-005` | Search-form `go` limits shall use checked parsing and explicit precedence for clocks, increment, moves-to-go, movetime, depth, nodes, mate, infinite, ponder and searchmoves. Diagnostic `go perft` shall be parsed as a mutually exclusive mode with a separately frozen output and completion contract. | 1, 4, 6 | Limit/mode matrix |
| `UCI-006` | Position replacement shall be transactional: a malformed FEN or illegal move list leaves the previous valid position unchanged. | 1–2 | State-preservation tests |
| `UCI-007` | Options, their defaults, ranges, UCI declarations and internal consumers shall derive from one authoritative definition. | 1, 6–8 | Generated/compile-time consistency check |
| `UCI-008` | During an active search, readiness, option barriers, stop, quit and EOF shall remain bounded and deadlock-free under the Phase-1 transcript contract. | 1, 6 | Timed process tests |

## 4. Resources and failure policy

### 4.1 Initial resource limits

| ID | Resource | Accepted bound | Owner | Verification |
|---|---|---|---:|---|
| `RES-001` | One UCI input line | At most 65,536 bytes excluding the line ending; an oversized line is drained before subsequent input is parsed. | 1 | Bounded-parser and process tests |
| `RES-002` | FEN text | At most 1,024 bytes after tokenization. | 1–2 | Parser boundary/property tests |
| `RES-003` | Path or free-form option value | At most 32,768 UTF-8 bytes, followed by checked native-path conversion. | 1 | Parser and native-path boundary tests |
| `RES-004` | Move-list/root/searchmoves capacity | 256 moves; overflow is an invariant failure, not truncation. | 2, 4 | Layout and maximum-move tests |
| `RES-005` | Search ply | `MAX_PLY = 256`, with separately sized and asserted padding. | 2, 4 | Layout and maximum-ply tests |
| `RES-006` | Threads | Public range `1...1024`; default `1`. Raising the maximum later requires measured scheduler, memory and cancellation evidence. | 1, 6 | Option/resource and process tests |
| `RES-007` | Hash | Public range `1...1,048,576` MiB; initial default `64` MiB. A request becomes active only after successful allocation. | 1, 4 | Allocation-failure and option tests |
| `RES-008` | MultiPV | When implemented, public range `1...256`; default `1`. | 10 when demanded | Option and process tests |
| `RES-009` | Clock, node and similar counters | Parse into an unsigned 64-bit intermediate. Reject negatives and overflow; apply the command's semantic cap without wrapping. | 1, 4, 6 | Parser/property boundary tests |
| `RES-010` | Search lifetime | Depth/node/time limits are bounded as specified; `go infinite` and ponder may run until `stop`, `ponderhit`, `quit` or EOF by design. | 1, 4, 6 | Limit and process tests |
| `RES-011` | Control/output mailboxes | Bounded storage with FIFO ordinary commands, coalescible obsolete info and non-droppable completion handling. Output backpressure shall neither create unbounded allocation nor stop the controller servicing lifecycle/control; exact capacities freeze with Phase-1 process evidence. | 1, 6 | Queue-pressure and process tests |
| `RES-012` | Applied `position` move list and pre-search game history | The applied move list is bounded only by `RES-001`, not by `RES-004`: the generated/root move capacity is not the game-length limit. Manta shall apply the whole list or reject the command transactionally under `SAFE-003`, and controller-owned game history shall accommodate any list within the `RES-001` bound. The repetition context handed to a search job is bounded by the halfmove clock since the last irreversible move. | 1–2 | Long-game process tests and repetition property tests |

### 4.2 Failure behaviour

| ID | Condition | Required behaviour | Owner | Verification |
|---|---|---|---:|---|
| `SAFE-001` | Unknown UCI command | Ignore it without changing engine state or writing non-protocol output. | 1 | Process transcripts |
| `SAFE-002` | Malformed supported command | Emit at most one bounded protocol diagnostic where useful, retain the last valid state and remain responsive. | 1 | Parser fuzz/property and process tests |
| `SAFE-003` | Invalid position/FEN/move sequence | Reject the whole replacement atomically and retain the previous valid position. | 1–2 | Transaction/state-preservation tests |
| `SAFE-004` | Failed `Hash`, `Threads` or other resource reconfiguration | Keep the previous working resource and option value; never expose a partially initialized replacement. | 1, 5–6, 8 | Failure injection and option/process tests |
| `SAFE-005` | Missing, unreadable, corrupt or incompatible optional file | Reject or disable only that optional feature, preserve the last valid loaded resource where applicable, and report a bounded diagnostic. | 5, 8 | Loader corruption/failure tests |
| `SAFE-006` | `quit` or stdin EOF | Cancel work, join owned threads, flush complete protocol output as applicable and exit successfully without hanging. | 1, 6 | Timed shutdown process tests |
| `SAFE-007` | Output from multiple workers | One owner serializes complete lines; interleaving and partial publication are forbidden. | 1, 6 | Concurrent-output process tests |
| `SAFE-008` | Internal invariant violation or state corruption | Fail fast with a non-zero exit rather than continue with corrupt state or emit an illegal move. Diagnostic detail goes to stderr. | 1 onward | Invariant-failure process tests |
| `SAFE-009` | Arithmetic, cast, index or allocation boundary | Use checked operations at external boundaries. Any intentionally unchecked hot-path operation requires a documented invariant, focused tests and performance evidence. | 1 onward | Boundary/property tests and hot-path review |

## 5. Files and external data

| ID | Requirement | Owner | Verification |
|---|---|---:|---|
| `FILE-001` | Opening books, tablebases, PGNs, datasets, training outputs, development networks, profiles and binaries shall remain local and gitignored. | 1 onward | Repository policy check |
| `FILE-002` | A reproducible job or release that consumes external data or shared tooling shall record its role, exact source/version identifier, byte size where applicable and cryptographic content hash in a compact committed or archived manifest. | 4 onward | Manifest validation |
| `FILE-003` | Every Manta-defined persisted binary format shall carry a magic identifier, explicit version, byte order, dimensions and integrity checks sufficient to reject incompatible or truncated input. | 7–8 | Loader corruption tests |
| `FILE-004` | Optional file loading shall occur outside search policy and hot paths. Paths shall be explicit options; hidden machine-specific search paths are forbidden. | 0.2, 5, 8 | Dependency tests and process tests |
| `FILE-005` | Release artifacts shall embed or accompany enough version/hash information to identify the source, toolchain, target, features and any embedded data. | 10 | Reproducibility manifest |

## 6. Performance and determinism

| ID | Requirement | Owner | Verification |
|---|---|---:|---|
| `PERF-001` | The portable scalar implementation shall be the semantic oracle. Every optimized backend shall match its results exactly over conformance corpora and randomized legal sequences. | 2, 8, 10 | Backend differential tests |
| `PERF-002` | Performance-sensitive work shall be accepted only after profiling or controlled A/B measurement on clean production builds with identical deterministic results. | 2 onward | Benchmark manifest |
| `PERF-003` | Local peak-performance builds shall use `ReleaseFast` and `cpu=native`. Timings from Debug, ReleaseSafe or a cross-compiled non-native artifact shall not support a peak-speed claim. | 1 onward | Build manifest review |
| `PERF-004` | Release portability shall not force every user onto the slowest implementation: a safe baseline and measured runtime-selected or sibling ISA tiers shall coexist where useful. | 8, 10 | Dispatch and artifact tests |
| `PERF-005` | SIMD/backend changes shall include exact conformance, emitted-instruction inspection, unsupported-hardware behaviour and target-native performance evidence. Compiler auto-vectorization shall not be assumed. | 8, 10 | Disassembly and native A/B |
| `PERF-006` | The deterministic built-in bench shall freeze inputs, reset policy, seeds, work definition and fingerprint. A fingerprint change requires a causal record and correctness evidence. | 4 | Bench regression |
| `PERF-007` | Timing evidence shall use an idle host, warm-up, repeated samples and recorded CPU/OS/power/topology/toolchain data. Long game-testing and tuning jobs shall use a calibrated physical-core placement/concurrency profile for the designated Ryzen 9 5950X, run without competing builds, games, data generation or benchmarks, and be recalibrated after a relevant hardware, OS, runner, clock or placement change. | 2 onward | Manifest validation |
| `PERF-008` | One-thread deterministic behavior is the baseline. Four-thread correctness, time safety, strength and scaling shall be accepted independently; no claim for higher thread counts is inferred without measurement. | 4, 6, 10 | 1T/4T gates and scaling evidence |
| `PERF-009` | Search-owned memory shall be prepared before worker publication and released after all workers join. Ordinary move generation, make/unmake, evaluation, node search and TT access shall perform no heap allocation, formatting or file I/O. | 2–4, 8 | Allocation instrumentation and dependency checks |
| `PERF-010` | Once Phase 4 makes Manta tournament-capable, each playing candidate shall have one prospectively registered, scope-representative time-based promotion gate using final production binaries. Prefer one independently meaningful idea. A coherent reversible bundle is allowed only for inseparable, invalid-in-isolation or individually below-resolution components and shall state one mechanism-level hypothesis; a pass licenses the bundle, not each component. Fixed-node games may diagnose quality per node but shall not promote a candidate. Additional time controls or thread counts are reserved for a distinct claimed scope or cumulative phase/release validation, not automatic duplicate SPRTs for the same change. | 4 onward | Experiment manifest and gate audit |
| `PERF-011` | Reaching a phase shall not by itself authorize SPSA. A run requires frozen parameter consumers, a small sensitivity pilot, evidence that a joint continuous fit is necessary and preferable to deferral or smaller experiments, and a prospectively registered coordinate set, checkpointed budget, wall-time estimate on the designated host, review points and stop rule. Normally tune 4–8 interacting continuous coordinates; more than 12 requires explicit evidence and approval. The normal first opportunity is after the retained NNUE architecture and score scale freeze; any earlier run requires an explicit plan amendment and approval. | 5, 9, 11 | Tuning-necessity review and registered manifest |

## 7. Platform and build contract

The supported source and release matrix is:

| Target | Build gate | Normal execution evidence | Release status |
|---|---|---|---|
| Windows x86-64 | Required | Native Windows development and hosted CI | Initial release target |
| Linux x86-64 | Required | WSL2 locally plus native hosted Linux CI | Initial release target |
| macOS x86-64 | Required | Native hosted macOS CI while available | Initial release target |
| macOS ARM64 | Required | Native hosted macOS CI | Initial release target |
| Linux ARM64 | Required | Native ARM64 runner or named target hardware | Publish only after native gate |
| Windows ARM64 | Required | Native ARM64 runner or named target hardware | Publish only after native gate |

Hosted-runner facts verified on 2026-08-07: `windows-11-arm` and
`ubuntu-24.04-arm` are generally available, and `macos-15-intel` is the final
GitHub-hosted x86-64 macOS image, announced as available until August 2027.
macOS x86-64 therefore has a known end date rather than an open-ended runner
supply; `REL-007` governs withholding that asset if the runner disappears
before a native replacement exists.

| ID | Requirement | Owner | Verification |
|---|---|---:|---|
| `PORT-001` | WSL2 shall be the normal local Linux build, unit/process-test and x86-64 artifact-smoke environment. The manifest shall record distribution, kernel and WSL version when results are retained. | 1 onward | WSL script/manifest |
| `PORT-002` | WSL2 evidence does not replace hosted/native target evidence for release publication, ARM64 behaviour, emitted ISA validation or final platform speed claims. | 1, 10 | Release matrix review |
| `PORT-003` | The default local build shall target the host CPU. Release builds shall declare an explicit portable CPU baseline and every optional ISA requirement in their name and manifest. | 1, 10 | Build metadata tests |
| `PORT-004` | Linux packaging shall first prefer a self-contained Zig binary without a libc dependency where viable. GNU-linked and statically linked musl candidates shall be compared when C integration or deployment requires libc. | 1, 5, 10 | Dependency inspection and A/B |
| `PORT-005` | musl is a compatibility/deployment choice, not a presumed performance winner. A musl asset may accompany the primary Linux artifact only after deterministic parity, WSL/native execution, dependency inspection and controlled performance comparison. | 5, 10 | Linux packaging gate |
| `PORT-006` | The source/build contract shall cover Windows, Linux and macOS on x86-64 and ARM64, and each target shall cross-build once the build spine exists. Cross-compilation and a UCI handshake are necessary but insufficient for a downloadable artifact: the exact artifact requires native correctness, deterministic agreement and backend suitability. | 1, 10 | Build and native target matrix |
| `PORT-007` | The portable runtime path shall reject an unsupported forced backend safely and shall always retain a baseline implementation. | 8, 10 | Feature-mask tests |

## 8. Quality and verification matrix

### 8.1 Exact Zig guard

| ID | Requirement | Owner | Verification |
|---|---|---:|---|
| `QUAL-001` | Development, CI and releases shall use the latest official stable Zig. The accepted version for this revision is exactly `0.16.0`; development/nightly builds are forbidden. | 1 onward | Version command and official-release check |
| `QUAL-002` | `build.zig.zon` shall declare `.minimum_zig_version = "0.16.0"`, while `build.zig` shall independently reject any compiler whose `builtin.zig_version_string` is not exactly `0.16.0`. The advisory package field alone is insufficient. | 1 | Build guard and negative-version test |
| `QUAL-003` | CI shall print and compare `zig version` before invoking any project build step. Toolchain archives/actions shall be pinned and their provenance recorded. | 1 | Workflow inspection and CI log |
| `QUAL-004` | At every numbered phase start and release, a newer official stable version blocks feature work until migration, release-note review and the affected correctness/performance baselines pass. | Every phase/release | Phase-start and release checklist |

Zig 0.16.0 requires explicit `std.Io` plumbing, changes prior stream APIs,
deprecates direct `@cImport` use in favour of build-system C translation, and
provides test timeouts. Architecture and examples therefore use the 0.16.0
APIs, not development documentation. Release performance uses the LLVM-backed
`ReleaseFast` path; Debug output is never a speed reference.

### 8.2 Static and dynamic checks

| ID | Check | Owner / activation |
|---|---|---|
| `QUAL-005` | `zig fmt --check --ast-check .` | Every local gate and CI run |
| `QUAL-006` | `zig build lint`; warnings, forbidden dependency edges, stale generated defaults, unversioned formats and unannotated unsafe operations are failures | Every local gate and CI run; includes format/AST, project policy and architecture-fitness checks |
| `QUAL-007` | ZLint `0.9.1` | Phase 1 pins and evaluates it against Zig 0.16.0; it joins `lint` only after a reviewed zero-warning baseline and reproducible CI pass |
| `QUAL-008` | `zig build test -Doptimize=Debug` | Every implementation change; primary invariant/leak development gate |
| `QUAL-009` | `zig build test -Doptimize=ReleaseSafe` | Every implementation change in CI |
| `QUAL-010` | `zig build test -Doptimize=ReleaseFast` | Phase boundaries, release gates and any production-semantics or performance-sensitive change |
| `QUAL-011` | Process, perft, property/fuzz, bench and backend suites | Activated by their owning phases and retained thereafter |
| `QUAL-012` | Requirements traceability | Every phase exit; every implemented requirement has a cited test/check/evidence location |
| `QUAL-013` | Domain-meaningful tests | Every non-trivial test/suite names the chess rule, search invariant, protocol/ownership contract or performance risk it protects and states important preconditions/exceptions |
| `QUAL-014` | Independent evidence | A test shall not duplicate production logic and call it an oracle; prefer independent recomputation, legal-rule oracle, property/metamorphic, differential or instrumented evidence |
| `QUAL-015` | Intentional exact values | Exact evals, node totals, sizes, constants and tuning values are asserted only as documented contracts, conformance snapshots or diagnostic fingerprints with a reason and update procedure |
| `QUAL-016` | Coding-agent reasoning | Before changing chess/search code, trace producers and consumers and assess legal chess, terminal/draw/special-move, score-bound, cache/allocation/thread and likely strength consequences |

If ZLint proves incompatible or unstable, Manta retains the compiler and
project checks, records the reason, and never downgrades Zig to keep the
linter.

### 8.3 Change-to-gate matrix

| Change | Minimum gate after the owning infrastructure exists |
|---|---|
| Documentation/Phase-0 design | Markdown/internal-link and public-doc policy checks; PLAN/GUIDE/REQUIREMENTS/ARCHITECTURE/ADR consistency; clean diff review |
| Build/toolchain/dependency | Exact Zig guard, format/AST/lint, all three test modes, supported target builds |
| Functional/correctness | Relevant unit/property/process/perft regressions in Debug and ReleaseSafe; ReleaseFast at the phase boundary |
| Behaviour-neutral hot-path work | Full static/test gates, exact one-thread fingerprint and controlled performance A/B |
| UCI/time/SMP | Complete process matrix, bounded stop/quit/EOF, legal output and one scope-matched 1T or 4T time-based game gate when tournament-capable |
| ISA/backend | Scalar differential corpus, fingerprint agreement, disassembly, unsupported-hardware test and target-native A/B |
| Release | Clean exact tag, complete quality/correctness/platform matrix, reproducible assets and manifests, prior-release game gate when applicable |

## 9. CI and release requirements

| ID | Requirement | Owner | Verification |
|---|---|---:|---|
| `REL-001` | Development shall occur on `dev`. `master` shall receive exactly one Phase-0 foundation squash commit establishing the license and accepted contracts on the default branch, and thereafter one squash commit per release through a pull request. | Repository setup | Branch audit |
| `REL-002` | One authoritative CI workflow shall run identically for pull requests targeting `master`, pushes to `master`, and manual dispatch from any branch. | 1 | Trigger tests |
| `REL-003` | Branch protection shall require one stable aggregate check named `CI / gate`; matrix job names may evolve without weakening the aggregate result. | 1 | Repository settings review |
| `REL-004` | CI shall include docs/policy/traceability, exact-toolchain, format/AST/lint, Debug, ReleaseSafe, ReleaseFast and target-build jobs. UCI/perft/bench/backend jobs become mandatory when implemented. | 1 onward | Workflow inspection |
| `REL-005` | A release workflow shall operate only on the exact tagged `master` commit, create a draft release, natively smoke-test every upload, compare fingerprints, generate hashes/manifests and publish only after all eligible assets pass. | 10 | Dry-run release |
| `REL-006` | User-facing release notes shall be extracted from the matching `CHANGELOG.md` version section. Automatically generated pull-request summaries are supplemental only. | 10 | Release-note check |
| `REL-007` | A failed or unavailable native target gate shall withhold that target's asset rather than publish an unverified cross-compiled binary or block already supported targets indefinitely. The omission is stated in the release manifest. | 10 | Release failure-path test |

## 10. Phase traceability

| Requirement families | Primary specification/implementation phases |
|---|---|
| Governance, terminology and quality model | 0.1 |
| Dependency, ownership, allocator and concurrency shape | 0.2–0.3 |
| Domain-meaningful testing and coding-agent reasoning | 0.2 onward |
| UCI state machine, resource parsing and process harness | 1 |
| Chess correctness and representation | 2 |
| Initial score scale and HCE | 3 |
| Deterministic search, first playable and bench | 4 |
| Search evidence, optional contempt investigation and tablebases | 5 |
| Time management and SMP | 6 |
| Data and training formats | 7 |
| NNUE and exact vector backends | 8–9 |
| Native platform, packaging, musl/ABI decision and release | 10 |

The Phase-0.3 audit recorded in `PLAN.md` confirmed that every requirement has
an owner, a feasible verification seam and no unpaid hot-path abstraction
cost. Its independent re-audits on the same date added `RES-012`, `PERF-010`
and `PERF-011` and corrected `FUNC-004`, `UCI-001`, `UCI-003` and `UCI-005`;
this revision therefore contains 90
requirements. Implementation may proceed only within the phase currently
authorized by `PLAN.md`.
