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
| `SCORE-001` | Draw and neutral evaluation shall be `0`. Positive scores favour the side to move at an internal node; root UCI output shall be from the root side's perspective. Static evaluation shall not manufacture terminal, repetition/rule draw or tablebase evidence owned by search. | 3–4 | Score/evaluator unit tests and later terminal search tests |
| `SCORE-002` | Search calculations shall use a strong four-byte type over a signed 32-bit score domain. `MATE` shall be `32000`, `INFINITY` shall be `32001`, and `NONE` shall be `32002`. `INFINITY` is a search bound; `NONE` is a sentinel and shall never enter arithmetic or UCI output. Any later compact storage representation requires checked, lossless conversion for every representable search score. | 3–4 | Compile-time size, range and sentinel tests |
| `SCORE-003` | `MAX_PLY` shall be `256`. Valid search-ply indices are `0...255`; per-ply storage shall add and document any sentinel or look-ahead padding separately. Every consumer shall alias the one chess-domain constant rather than introduce a second limit. | 0.2, 2, 4 | Layout, alias and boundary tests |
| `SCORE-004` | A win in `p` plies shall be `MATE - p`; a loss in `p` plies shall be `-MATE + p`. Transposition-table storage shall normalize mate distance to and from the current ply without changing ordering. | 4 | Mate and TT round-trip tests |
| `SCORE-005` | The lowest mate-band magnitude shall be `MATE - MAX_PLY` (`31744`). Future tablebase magnitudes shall occupy the distinct 256-value band `31488...31743`; ordinary evaluation magnitude shall be at most `31487`. | 3, 5 | Compile-time band assertions and conversion tests |
| `SCORE-006` | A requested UCI search depth shall be represented as an optional limit and normalized to at most `MAX_PLY - 1`. Manta shall not introduce a second unrelated maximum-search-depth constant. | 1, 4 | Parser and boundary transcripts |
| `SCORE-007` | UCI mate output shall count moves, not plies: positive internal distance uses `(plies + 1) / 2`; negative distance uses division by two toward zero. A currently checkmated root reports `score mate 0`. | 1, 4 | Exact mate transcript corpus |
| `SCORE-008` | The search-facing evaluator scale shall use 100 units per pawn and map directly to user-facing cp. A later evaluator may use another internal scale only behind an explicit signed-symmetric, tested conversion to this search scale. | 3, 8 | Evaluator-scale, evaluation and UCI tests |
| `SCORE-009` | The accepted baseline shall have no contempt adjustment and no public contempt option. After the single-thread baseline freezes, Phase 5 shall investigate static/dynamic contempt, analysis/play behaviour and draw-rule interactions; an option is added only after positive native evidence. | 5 | Registered experiment or parked verdict |
| `SCORE-010` | Selective search shall represent nominal child horizon, extension and reduction separately before composing searched depth. Node-entry route and completed outcome attribution shall remain distinct from score/bound/provenance authority; an upper bound denotes fail-low, exact denotes exact and lower denotes cutoff. Context infrastructure alone shall not affect legality, terminal/draw handling, TT/PV authority or playing policy. | 5 | Context on/off equivalence, depth properties and observation accounting |
| `SCORE-011` | Depth authority shall extend legal check evasions without changing nominal completed-root depth, reduce only eligible non-root searches whose missing move evidence warrants lower confidence, and derive singular extensions only from legal ordinary TT evidence after a same-position exclusion search fails low. Exclusion searches shall not manufacture terminal, TT, PV, history, null-move or reusable score authority. The complete family and each producer shall remain compile-time ablatable. | 5 | Focused check/IIR/singular/exclusion tests, family-off fingerprint and observation accounting |
| `SCORE-012` | ProbCut shall be a non-root, non-PV, non-check, ordinary zero-window tactical proof over legal non-promotion captures. A raised-beta quiescence pass alone shall not cut: a reduced main search must verify it. Returned evidence shall be a fail-hard typed lower bound; any TT store shall use only the reconstructed reduced parent horizon and retain ProbCut provenance. Root, exclusion, pawn-only, decisive-score, promotion and cancellation paths shall retain ordinary authority, and the mechanism shall remain independently ablatable. | 5 | Eligibility/score/depth properties, legal-population accounting, cancellation unwind, feature-off fingerprint and registered games |
| `SCORE-013` | Contextual quiet history shall consume only a real immediately preceding move plus an authoritative exact/cutoff main-search winner. It shall distinguish previous/current piece type and normalized destination, penalize only actually searched quiet alternatives, and shall not learn from root, null, fail-low, exclusion, pruned or unsearched moves. It may influence quiet ordering only; score, bound, PV, TT, terminal/draw, pruning and reduction authority remain unchanged. Storage shall be worker-local, bounded and independently ablatable. | 5 | Key symmetry/special-move properties, bounded updates, ordering isolation, outcome accounting, feature-off fingerprint and registered games |
| `SCORE-014` | An independently ablatable LMR/reply-history synchronization may add one negative contextual update only when an eligible quiet reduced probe rises above alpha and its mandatory full-depth re-search returns an upper bound at or below that same alpha. Reduced evidence alone, root, null, exclusion, capture, promotion, pruned, aborted and unsearched paths shall not train it. The update shall occur after unmake, shall not be duplicated by later node-outcome attribution and may affect only future quiet ordering; disabling it shall restore the accepted contextual-history baseline exactly. | 5 | Full-depth-bound accounting, legal PV/state restoration, candidate-off fingerprint and registered games |
| `SCORE-015` | Main and quiescence search shall carry an explicit prospective node expectation (`principal`, `cut` or `all`) separately from returned score, bound and provenance. Until an owning behavioral step activates a consumer, expectation shall have no pruning, reduction, extension, TT, PV, terminal or draw authority. Move selection shall incrementally emit every already-generated legal move exactly once from caller-owned bounded storage, emit a legal TT move in only its one ranked position, preserve accepted stage precedence and generation order among equal ranks, and allocate nothing in the node path. | 5 | Expectation transition/accounting properties, staged-order uniqueness/stability property, legal PV/state restoration and unchanged production fingerprint |
| `SCORE-016` | Dynamic base late-move reduction shall derive magnitude only from nominal depth and the searched legal-move ordinal, increase monotonically in either input, and retain at least one main-search child ply. Existing quiet/tactical, in-check, checking-move, singular and history guards remain authoritative. Reduced fail-low evidence shall retain reduced provenance/depth authority; every reduced alpha rise shall receive mandatory full-depth verification before it can affect a PV, cutoff, exact score or outcome-history update. The magnitude policy shall remain independently ablatable to the accepted fixed one-ply baseline. | 5 | Monotonicity/bounds properties, reduction accounting, legal PV/state restoration, feature-off fingerprint and registered games |
| `SCORE-017` | Capture history shall be bounded, worker-local evidence keyed by the resulting mover type, side-relative destination and actual victim type. En-passant and promotion captures shall retain their chess facts. Only completed non-root, non-exclusion main-search exact/cutoff capture winners may receive rewards, and only actually searched capture alternatives may receive penalties; fail-low, pruned, aborted and unsearched paths shall not train. The evidence may order moves only within their existing good- or bad-tactical SEE stage in main search, quiescence and ProbCut. It shall have no legality, score, bound, PV, TT, terminal/draw, pruning or reduction authority and shall remain independently ablatable to the accepted baseline. | 5 | Color/special-move key properties, bounded-update and stage-isolation properties, producer/consumer accounting, feature-off fingerprint and registered games |
| `SCORE-018` | Multi-distance continuation history shall retain immutable facts for real historical moves and sever relations across root or synthetic-null arrivals. Two-, four- and six-ply contexts shall distinguish the historical resulting piece, side-relative destination, whether its parent was in check and whether it was a capture or promotion. Only authoritative exact/cutoff quiet outcomes may train the bounded worker-local table against actually searched quiet alternatives. It may augment quiet ordering only and shall have no legality, terminal/draw, score, bound, PV, TT, pruning or reduction authority. The bundle and each distance shall remain compile-time ablatable; counter-move and low-ply tables require independent evidence that they add information beyond existing killers and histories. | 5 | Historical-fact/symmetry/null-boundary properties, per-distance population and update accounting, bundle-off fingerprint and registered cluster games |
| `SCORE-019` | The archived synchronized-LMR mechanism shall retain the accepted nominal-depth/searched-move base and may alter it by at most one child ply only after at least two independent typed signals agree. Improving trend, prospective principal/cut expectation, legal TT evidence, verified singular context and majority-direction accepted quiet/reply/continuation history shall remain independently ablatable; ties and isolated facts preserve the base. Every reduced alpha rise still requires full-depth verification. Only the final full-depth result may add symmetric reply/continuation feedback after unmake, and that move shall not be trained again by the same node outcome. Root, null, exclusion, tactical, checking, singular-move, terminal/draw, PV, score/bound and TT authority remain unchanged. The umbrella shall default off after MAN-S18's H0 verdict. | 5 | Bounded/agreement properties, per-modifier and feedback accounting, default MAN-S17 fingerprint, legal PV/state restoration and registered cluster games |
| `SCORE-020` | Raw HCE, pruning evaluation, quiescence stand pat and searched TT value/bound shall remain distinct evidence. An authenticated same-position TT entry may cache exact representable raw HCE without changing entry/cluster layout; outliers shall be absent rather than clipped. Only ordinary searched evidence may refine pruning evaluation, and only in its proven bound direction; raw improving history remains unrefined. Qsearch delta pruning shall exclude PV, check/evasion, promotion, decisive-score and negative-SEE paths, shall retain a pawn-scale cushion, and shall make a candidate before exempting checks. Actual final provenance shall name stand pat, TT refinement or searched qsearch move. The cluster and each producer/consumer shall remain compile-time ablatable to exact MAN-S17. | 5 | TT packing/round-trip/key tests, directional/provenance properties, delta special-move/check canaries, accounting, feature-off fingerprint and registered cluster games |
| `SCORE-021` | Main selectivity shall preserve the verified null-move proof, ProbCut's reduced-horizon authority, accepted quiet-history ownership and MAN-S19's raw/pruning-evaluation separation. Dynamic null reduction may make only the probe shallower, shall retain at least one ordinary probe ply and two same-node verification plies, and shall use the identical reduction for mandatory verification; pawn-only, check, PV, after-null and decisive paths remain excluded. ProbCut may reuse only sufficient-depth ordinary searched TT evidence: lower/exact evidence above its raised threshold may cut, while upper/exact evidence below it may only suppress the speculative probe. Consensus accepted quiet history may adjust late-move count by at most one and protect a quiet-futility candidate, without gaining score/bound/PV/TT authority. Capture futility may only tighten the existing SEE threshold from ordinary TT-refined pruning evaluation and alpha with a depth-scaled pawn cushion; promotions and post-move checks remain searched. The cluster and each consumer shall remain compile-time ablatable to exact MAN-S19. | 5 | Reduction/threshold/provenance properties, legal PV/mate/draw/zugzwang canaries, diagnostic accounting, cluster-off fingerprint and registered games |
| `SCORE-022` | Extension/depth synchronization shall preserve principal-node IIR and may reduce only a mature non-root, non-check, non-exclusion expected-cut node that lacks a legal TT move. Singular verification shall require a legal ordinary lower/exact move from ordinary full/PVS TT provenance. One-ply extension requires searched exclusion fail-low; a second ply additionally requires deep exact principal evidence and a second pawn of separation. Multi-cut shall operate only at an expected-cut ordinary window and return fail-hard speculative lower evidence only after an exclusion lower/exact result actually proves beta; exclusion results shall not be stored, published as PV or train history. Negative and historical move extensions remain parked until they have an independent authority contract. The cluster and each consumer shall remain compile-time ablatable to exact MAN-S19. | 5 | Expectation/provenance/bound/depth properties, exclusion cancellation and state/PV/TT isolation, observation population, cluster-off fingerprint and registered games |
| `SCORE-023` | Static-evaluation correction history shall be bounded, worker-local evidence keyed by side to move and pawn structure. Only an ordinary completed main-search result at positive depth, outside check and exclusion search, may train it: exact evidence always, a lower bound only above raw HCE and an upper bound only below it. Reduced-provenance and shallow-pruned incomplete fail-lows shall not train. The Step-5.4.1 consumer may adjust qsearch stand pat inside the ordinary score band; raw HCE shall continue to own TT static storage, improving history, pruning evaluation and every pruning/reduction decision until a later prospective gate explicitly grants selectivity authority. Terminal, draw, mate, tablebase, aborted, depth-zero and unavailable-evaluation paths shall not train it. The producer/consumer shall remain compile-time ablatable to exact MAN-S19 and shall default off after MAN-S25 accepted H0. | 5 | Bound-direction/check/exclusion/depth properties, reduced/pruned fail-low rejection, evaluation-versus-selectivity isolation, raw-TT test, table population/cap telemetry, online pre-update residual, candidate-off fingerprint and registered games |
| `SCORE-024` | The Step-5.4.3 contextual-space candidate shall retain the accepted central safe-space and pawn-support facts, and may change only their middlegame magnitude. Per-side space shall be weighted by `floor(raw_space * phase * (4 + central_locks) / 96)` before colour subtraction, with phase in `0...24` and immediately opposed c–f pawn pairs capped at four. The candidate shall be compile-time ablatable to exact MAN-E19 evaluator behavior on MAN-S19 search and shall gain no legality, terminal/draw, tablebase, score-bound/provenance, TT/PV, pruning/reduction, correction, cache or thread authority. Schema v3 shall delete only rejected, unreachable or superseded rows, preserve switch-off fingerprint `724,563`, and bind 1,229 coefficients in 125 groups. | 5 | Phase/lock monotonicity and bound properties, colour mirroring, schema/source/sparse/full conformance, exact switch-off fingerprint, controlled evaluator cost, registered validation refutation filter and candidate games |
| `SCORE-025` | The Step-5.4.3 shelter-moderated king-danger candidate shall retain the accepted signed shelter/storm/open-file score and every raw-danger producer. After the existing two-attacker threshold and immediately before the middlegame square-law penalty, its sole new transformation shall be `max(0, raw_danger - shelter_middlegame)`: positive shelter may only relieve danger, negative shelter may only amplify it and zero shelter shall be inert. Every accepted coefficient shall freeze. The candidate shall remain compile-time ablatable to exact MAN-E19 evaluator behavior on MAN-S19 search and shall gain no legality, terminal/mate/draw, tablebase, rule-fifty, score-bound/provenance, TT/PV, pruning/reduction, correction/history, cache or thread authority. | 5 | Transform monotonicity/threshold/symmetry properties, legal shelter/attack counterexamples, ordinary-band and overflow safety, incremental/full conformance, populated relief/amplification/zero-transition accounting, exact switch-off fingerprint, controlled evaluator cost and registered candidate games |
| `SCORE-026` | The accepted Step-5.4.6 MAN-S29 production policy shall be the nearest-integer bake of MAN-S28's complete iteration-2,000 theta: ProbCut/reverse-futility/LMR-extra `103/68/116`, late-move base/depth/improving `4/3/4`, SEE/qsearch-delta `107/122`, reply/continuation weights `116/118`, with quiet futility unchanged at `100`. The complete vector shall be the sole ordinary default after its H1 verdict; the temporary candidate selector shall be removed, while frozen MAN-S19 values may reconstruct archived diagnostics only. The bake adds no legality, terminal/mate/draw, tablebase, score-bound/provenance, TT/PV, cache, allocation or thread authority; the accepted producers, guards, full-depth verification and state restoration remain unchanged. | 5 | Exact production-vector test, parameter ranges and search invariants, production and explicit historical fingerprints, and the accepted candidate-as-A `[1,5]` SPRT |
| `SCORE-027` | Root-confidence evidence shall be bounded and worker-local. Each searched legal root move may contribute its encoded move, typed score/bound/provenance and child-node effort only after the complete exact root iteration finishes. Upper/lower bounds shall not enter exact-score variance. Aspiration retries, warm root-TT completions without child work, terminal/draw roots and aborted partial iterations shall create no observation, and a new search shall reset the model. The Step-6.0.1 producer itself shall have no allocation, aspiration, fallback, legality, terminal/draw, PV, TT, score, clock, stopping, cache or thread authority; any later consumer requires its own explicit contract and gate. | 6 | Exact-variance/bound property, special-move identity, complete-population, warm-TT, reset/abort isolation and unchanged production fingerprint |
| `SCORE-028` | The default-off Step-6.0.2 soft-time candidate may consume only the latest complete root-confidence snapshot after an exact root iteration. Its uncertainty facts shall be: the best move changed on the latest populated iteration, the exact completed-best score fell, and the best move consumed a strict majority of that iteration's root effort. Zero or one fact preserves the Phase-4 soft deadline, two move the completed-iteration stop to the midpoint of the existing soft-to-hard interval, and all three permit work through the unchanged hard deadline. It shall never stop before the base soft deadline or extend beyond the receipt-derived hard deadline. Fixed movetime, Move Overhead and scheduling reserves, node-polled hard stopping, epoch cancellation, legal/terminal/draw behavior, score/bound/PV/TT authority, fallback, cache and thread ownership remain unchanged. MAN-R01 accepted H0, so the consumer shall remain archived default-off without threshold tuning or retry. | 6 | Signal/agreement/deadline-bound properties, candidate-on fake-clock test, feature-off fingerprint, time-safety transcripts and registered games |
| `SCORE-029` | The default-off Step-6.0.3 aspiration candidate may narrow the next root iteration to a symmetric one-pawn window around the prior exact ordinary completed score only when at least two populated completed iterations retain the same best move and the latest exact score delta is at most one pawn. Decisive, bounded, unpopulated, insufficient or unstable evidence shall retain the full window. Fail-low/high retries shall widen symmetrically to the full window and reset scratch evidence before every attempt; only the final exact iteration may commit root confidence. Each candidate-on/off arm shall independently return an exact completed result, legal PV and restored root, but their score and PV need not match because window-dependent selective search and TT interactions are playing behavior owned by the prospective game gate. Legality, terminal/draw/tablebase authority, mate distance, fallback, clock, cache allocation and thread ownership remain unchanged. MAN-R02 exhausted its registered 16,000-game cap without either boundary, so this consumer shall remain archived default-off without tuning or retry under the current HCE/search head. | 6 | Eligibility/boundary properties, decisive-root exclusion, exact result/legal PV/state, retry/root-confidence accounting, feature-off fingerprint, deterministic population/work diagnostic and capped registered games |
| `SCORE-030` | The Step-6.3 integrated clock policy shall derive distinct optimum and immutable maximum budgets from remaining time, increment, moves-to-go and game ply after explicit move/scheduling reserves. Only populated completed exact ordinary root evidence may adjust the optimum through bounded best-move stability/change, ordinary score trend, effort and genuinely forced/easy-root facts. Ponder credit shall be consumed once without restarting time or extending maximum. Helper evidence shall be a normalized bounded instability count with no move/score/PV/result authority; thread count shall never multiply time. Terminal, draw, mate, tablebase, warm-TT-unpopulated and aborted evidence shall not become dynamic samples. Fixed movetime, hard polling, epoch cancellation, legal fallback and worker-zero publication remain unchanged. Candidate diagnostics shall expose initial budgets, each multiplier, ponder/helper inputs, final target and stop reason, and hard-deadline overshoot without acquiring search authority. The tune-only 1T surface shall expose exactly the jointly active horizon, increment, maximum-ratio and stability/score/effort-response controls from one registry; it shall not expose hard safety, evidence thresholds, categorical switches, ponder-only or SMP-only controls to a run that cannot sample them. A completed time forfeit shall be scored as the engine's game loss when clock policy is the measured subject; incomplete games and non-time engine, protocol, affinity or infrastructure faults remain anomalies. Other SPSA groups remain strict. Production shall use MAN-T04's complete rounded vector `1034/957/4291/1036/1049/1046`; explicit integrated-time-off reconstruction retains `1000/1000/4000/1000/1000/1000`. MAN-T05's promotion carries the documented post-result maintainer waiver rather than a claim that its original zero-timeout gate passed. | 6 | Budget/horizon and registry properties, provenance and forced-root tests, ponder saturation, normalized SMP evidence, tune handshake/range checks, fixed-work fingerprint, fake-clock/process and 1/2/4/8T qualification, completed-time-loss scoring, strict fault rollback, exact production/reconstruction vectors and registered games |

## 3. Product and protocol requirements

| ID | Requirement | Owner | Verification |
|---|---|---:|---|
| `FUNC-001` | Manta shall implement orthodox standard chess correctly. No variant behaviour is part of the initial product contract. | 2–4 | Perft, invariants and game tests |
| `FUNC-002` | Rules, search, evaluation and external adapters shall remain separable enough to add a variant later without embedding variant conditionals throughout the hot path. No speculative variant implementation is required. | 0.2–0.3 | ADR and dependency-fitness review |
| `FUNC-003` | The first-playable engine shall be a portable, scalar, single-thread UCI executable with complete legal move handling, deterministic search, an original HCE, depth/node/movetime/infinite/stop control and a conservative deterministic policy for ordinary clocks/increments/moves-to-go. | 4 | Phase-4 acceptance matrix |
| `FUNC-004` | Every completed search shall return exactly one legal `bestmove`, or, in a terminal position, the no-legal-move token frozen by the Phase-1 transcript contract. Every reported PV shall be a sequentially legal line from its reported root; legality of only the first move is insufficient. UCI itself defines no no-legal-move token, so the chosen spelling is a deliberate compatibility decision, not an inherited default. Cancellation and failure shall never publish an illegal move. | 1, 4, 6 | Independent legal-PV replay and process transcript tests |
| `FUNC-005` | One-thread search from a fixed position, configuration, seed and cleared state shall be deterministic across supported targets and exact backends. | 4, 8, 10 | Fingerprint and backend tests |
| `FUNC-006` | Manta's engineering objective shall be playing strength under correct chess and UCI semantics. Design and implementation work shall consider chess meaning, search quality, throughput and measured 1T/4T behavior rather than similarity to an existing implementation or preservation of incidental numbers. | All | Review, diagnostics and registered games |

Phase 1 shall expand the following protocol requirements into a complete
command/state/output transcript matrix before chess behaviour is implemented:

| ID | Requirement | Owner | Verification |
|---|---|---:|---|
| `UCI-001` | After successful startup and before reading input, Manta shall emit exactly one bounded identity line. It shall then implement UCI with complete, serialized stdout lines. While a protocol session is active, stdout shall carry protocol output plus the output of explicitly specified diagnostic commands only. `bench` (§4.2 of `PLAN.md`) and `go perft` are such commands and each owns a frozen output contract; unsolicited or incidental non-protocol stdout is forbidden and non-protocol diagnostics belong on stderr. | 1 | Process transcripts |
| `UCI-002` | `uci`, `debug`, `isready`, `setoption`, `ucinewgame`, `position`, search-form `go`, diagnostic `go perft`, `stop`, `ponderhit`, `bench`, `quit` and EOF shall have explicit state-transition and ordering contracts. A frozen command not yet activated shall be reported as reserved but unavailable, never partially executed or misreported as arbitrary input. | 1, 6 | State matrix and transcripts |
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
| `RES-011` | Control/output mailboxes | Phase 1 fixes each mailbox at 64 records and each formatted output record at 4,096 bytes. Storage remains bounded with FIFO ordinary commands, coalescible obsolete info and non-droppable completion handling. Output backpressure shall neither create unbounded allocation nor stop the controller servicing lifecycle/control; a later capacity change requires renewed process evidence. | 1, 6 | Queue-pressure and process tests |
| `RES-012` | Applied `position` move list and pre-search game history | The applied move list is bounded only by `RES-001`, not by `RES-004`: the generated/root move capacity is not the game-length limit. Manta shall apply the whole list or reject the command transactionally under `SAFE-003`, and controller-owned game history shall accommodate any list within the `RES-001` bound. The repetition context handed to a search job is bounded by the halfmove clock since the last irreversible move. | 1–2 | Long-game process tests and repetition property tests |

### 4.2 Failure behaviour

| ID | Condition | Required behaviour | Owner | Verification |
|---|---|---|---:|---|
| `SAFE-001` | Unknown UCI command | Emit exactly one bounded `info string` stating that the command was unknown and ignored, change no engine state and remain responsive. | 1 | Process transcripts |
| `SAFE-002` | Malformed supported command | Emit exactly one bounded `info string` with the command and reason, retain the last valid state and remain responsive. | 1 | Parser fuzz/property and process tests |
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
| `PERF-008` | One-thread deterministic behavior is the baseline. Four-thread correctness, time safety and strength shall be accepted independently. Scaling remains an objective beyond four threads and shall be measured through at least 1/2/4/8T plus justified higher host-supported counts; throughput never establishes higher-thread playing strength. | 4, 6, 10 | 1T/4T gates and extended scaling evidence |
| `PERF-009` | Search-owned memory shall be prepared before worker publication and released after all workers join. Ordinary move generation, make/unmake, evaluation, node search and TT access shall perform no heap allocation, formatting or file I/O. | 2–4, 8 | Allocation instrumentation and dependency checks |
| `PERF-010` | Once Phase 4 makes Manta tournament-capable, each playing candidate shall have one prospectively registered, scope-representative time-based promotion gate using final production binaries. The runner's measured null-bias envelope shall be materially below the claimed resolution; a conditionally bounded runner may be used only in its recorded coarse scope and role orientation. Prefer one independently meaningful idea. A coherent reversible bundle is allowed only for inseparable, invalid-in-isolation or individually below-resolution components and shall state one mechanism-level hypothesis; a pass licenses the bundle, not each component. Fixed-node games may diagnose quality per node but shall not promote a candidate. Additional time controls or thread counts are reserved for a distinct claimed scope or cumulative phase/release validation, not automatic duplicate SPRTs for the same change. | 4 onward | Experiment manifest and gate audit |
| `PERF-011` | Reaching a phase shall not by itself authorize SPSA. A run requires frozen parameter consumers, evidence that a joint continuous fit is necessary and preferable to deferral or smaller experiments, and a prospectively registered coordinate set, checkpointed budget, wall-time estimate on the designated host, review points and stop rule. Normally obtain that evidence through a small sensitivity pilot. The maintainer may explicitly replace the separate pilot with one horizon-matched full run only after accepting its complete game budget and recording existing consumer-activity and instrument evidence; intermediate checkpoints then have no parameter-selection authority. Normally begin with 4–8 interacting continuous coordinates; a wider set requires evidence for every consumer and explicit acceptance of its game cost rather than an arbitrary numeric cap. The normal first opportunity is after the retained NNUE architecture and score scale freeze; any earlier run requires an explicit plan amendment and approval. | 5, 9, 11 | Tuning-necessity review and registered manifest |

## 7. Platform and build contract

Manta is a 64-bit-only engine. The only supported architecture families are
x86-64 and ARM64; x86, ARM32 and every other 32-bit target are out of scope and
shall fail build configuration before engine compilation. In-memory hot-path
layouts may therefore rely on 64-bit pointers and `usize`, while protocols and
persisted formats remain explicitly width-defined and never inherit native
layout.

The supported source and release matrix is:

| Target | Build gate | Normal execution evidence | Release status |
|---|---|---|---|
| Windows x86-64 | Required | Native Windows development and hosted CI | Initial release target |
| Linux x86-64 | Required | WSL2 locally plus native hosted Linux CI | Initial release target |
| macOS x86-64 | Required | Native hosted macOS CI while available | Initial release target |
| macOS ARM64 | Required | Native hosted macOS CI | Initial release target |
| Linux ARM64 | Required | Native ARM64 runner or named target hardware | Publish only after native gate |

Windows ARM64 is not currently supported. Zig 0.16.0's native compiler crashed
on the hosted runner during independent project tests, so the target may return
only after a later stable Zig toolchain passes the ordinary build, test and
smoke gates without a target-specific bypass.

Hosted-runner facts verified on 2026-08-07: `ubuntu-24.04-arm` is available as
a public preview, so stable native publication must account for that service
status. GitHub now provides `macos-26-intel`, so the earlier assumption that
`macos-15-intel` was the final hosted x86-64 macOS image is retired. `REL-007`
governs withholding an asset if its native runner disappears before a
replacement exists.

| ID | Requirement | Owner | Verification |
|---|---|---:|---|
| `PORT-001` | WSL2 shall be the normal local Linux build, unit/process-test and x86-64 artifact-smoke environment. The manifest shall record distribution, kernel and WSL version when results are retained. | 1 onward | WSL script/manifest |
| `PORT-002` | WSL2 evidence does not replace hosted/native target evidence for release publication, ARM64 behaviour, emitted ISA validation or final platform speed claims. | 1, 10 | Release matrix review |
| `PORT-003` | `zig build` shall default to ReleaseFast, the host CPU and the best retained `auto` profile. `-Dportable` shall use only the platform baseline; `-Dnative` and `-Dportable` are mutually exclusive. Canonical artifacts shall name version, OS, curated ISA profile, native status when applicable and PGO status. Unimplemented profiles, premature PGO, cross-target overrides and misleading raw CPU overrides shall fail explicitly. Phase 10 may extend `auto` only through measured microarchitecture preferences and shall retain the portable fallback. | 1, 4, 10 | Build-policy, metadata and native smoke tests |
| `PORT-004` | Linux packaging shall first prefer a self-contained Zig binary without a libc dependency where viable. GNU-linked and statically linked musl candidates shall be compared when C integration or deployment requires libc. | 1, 5, 10 | Dependency inspection and A/B |
| `PORT-005` | musl is a compatibility/deployment choice, not a presumed performance winner. A musl asset may accompany the primary Linux artifact only after deterministic parity, WSL/native execution, dependency inspection and controlled performance comparison. | 5, 10 | Linux packaging gate |
| `PORT-006` | The source/build contract is 64-bit-only: it shall reject 32-bit targets and compile and execute natively on Windows x86-64 plus Linux and macOS on x86-64 and ARM64. Hot in-memory code may rely on 64-bit pointers and `usize`; external formats remain fixed-width. A downloadable artifact requires target-native correctness, deterministic agreement and backend suitability. Windows ARM64 remains excluded until a stable Zig toolchain passes the ordinary native gates without special handling. | 1, 10 | Build-policy and native target matrix |
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
| `QUAL-017` | Dependency-complete playing evidence | A playing feature shall be tested independently only when its producers and consumers form a meaningful standalone mechanism. Mutually dependent or individually below-resolution parts shall retain component switches and receive one prospectively registered bundle gate. Categorical choices shall freeze before SPSA; binary switches shall not be tuning coordinates, and a baked continuous fit shall still pass a clean time-based confirmation gate. |

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
| `REL-001` | Development shall occur on `dev`. `master` shall receive exactly one Phase-0 foundation squash commit establishing the license and accepted contracts on the default branch, and thereafter one squash commit per release through a pull request. After the release commit and all gates are clean, `dev` shall be reset to that finalized `master` state. | Repository setup | Branch audit |
| `REL-002` | One authoritative CI workflow shall run identically for pull requests targeting `master`, pushes to `master`, and manual dispatch from any branch. | 1 | Trigger tests |
| `REL-003` | The sole publisher shall require one stable aggregate check named `CI / gate` before accepting the release pull request, verify the post-merge `master` run and a clean worktree, and only then reset `dev`. This is a maintainer-enforced release procedure rather than a repository branch-protection rule; matrix job names may evolve without weakening the aggregate result. | 1 | Release checklist review |
| `REL-004` | CI shall include docs/policy/traceability, exact-toolchain, format/AST/lint, Debug, ReleaseSafe, ReleaseFast and target-build jobs. UCI/perft/bench/backend jobs become mandatory when implemented. | 1 onward | Workflow inspection |
| `REL-005` | A release workflow shall operate only on the exact tagged `master` commit, create a draft release, natively smoke-test every upload, compare fingerprints, generate hashes/manifests and publish only after all eligible assets pass. | 10 | Dry-run release |
| `REL-006` | User-facing release notes shall be extracted from the matching `CHANGELOG.md` version section. Automatically generated pull-request summaries are supplemental only. | 10 | Release-note check |
| `REL-007` | A failed or unavailable native target gate shall withhold that target's asset rather than publish an unverified binary or block already supported targets indefinitely. The omission is stated in the release manifest. | 10 | Release failure-path test |

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
| Classical search/HCE convergence, synchronization, optional fit, contempt and tablebases | 5 |
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

Step 1.1 subsequently froze the startup identity, command/state matrix, staged
transcript corpus, and explicit unknown/malformed-command diagnostics. It
refined `UCI-001`, `UCI-002`, `SAFE-001`, and `SAFE-002` without adding or
removing requirement IDs; the total remains 90.

Steps 5.1.4.2–5.1.4.6 subsequently added `SCORE-011` through `SCORE-014` for
depth authority, ProbCut, contextual history and the rejected-but-preserved LMR
feedback contract; unrelated completed work added the remaining rows. ADR-0034
then added `QUAL-017` for dependency-complete cluster and tuning evidence.
Step 5.1.5.1 added `SCORE-015` for prospective node expectation and stable
allocation-free staged selection. Step 5.1.5.2 added `SCORE-016` for dynamic
base-LMR magnitude and full-depth authority. Step 5.1.5.3 added `SCORE-017` for
bounded capture-history production and ordering-only consumption; Step
5.1.5.4 added `SCORE-018` for multi-distance continuation evidence; Step
5.1.5.5 adds `SCORE-019` for bounded synchronized LMR and full-depth-only
feedback; Step 5.1.5.6 adds `SCORE-020` for raw/pruning/TT/qsearch evidence
separation and bounded delta eligibility; Step 5.1.5.7 adds `SCORE-021` for
verified-null, ProbCut-TT, history and capture-selectivity synchronization; Step
5.1.5.8 adds `SCORE-022` for expectation-aware IIR and searched singular/
multi-cut authority. Step 6.0.3 adds `SCORE-029` for stability-gated root
aspiration and retry authority. The current total is 105
requirements.

Step 6.1 activates the already-frozen `UCI-002`–`UCI-008` ponder, option,
ordering, receipt-time and exactly-once contracts plus `RES-010`–`RES-011`.
It adds no requirement ID; the total remains 105.

Step 6.0.4 realizes the existing `UCI-004` receipt-time and `RES-010` ponder-
lifetime contracts as a matching-epoch, once-latched receipt-to-hit credit for
the later integrated time policy. It adds no requirement ID or playing
consumer; the total remains 105.
