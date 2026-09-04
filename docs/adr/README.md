# Architecture decision records

These records define and refine Manta's architecture. ADRs 0001–0012
established the Phase-0.2 design; later records state their current status and
close their owning evidence steps. They are read with [`ARCHITECTURE.md`](../../ARCHITECTURE.md) and
[`REQUIREMENTS.md`](../../REQUIREMENTS.md).

| ADR | Decision |
|---|---|
| [0001](0001-clean-dependency-boundaries.md) | Clean dependency boundaries and Zig source organization |
| [0002](0002-ownership-and-allocation.md) | Explicit ownership, lifetimes and allocation |
| [0003](0003-position-state-selection.md) | Position/state separation and evidence-led representation selection |
| [0004](0004-make-unmake-ownership.md) | Caller-owned make/unmake state and history |
| [0005](0005-evaluator-composition.md) | Statically specialized, replaceable evaluators |
| [0006](0006-search-composition.md) | Concrete evidence-coherent search composition |
| [0007](0007-uci-control-plane.md) | Inward engine contracts and responsive UCI control plane |
| [0008](0008-clock-and-time.md) | Injected monotonic clock and receipt-based time accounting |
| [0009](0009-tt-concurrency.md) | Lock-free shared TT semantics without undefined races |
| [0010](0010-runtime-isa-dispatch.md) | Scalar oracle and coarse runtime ISA selection |
| [0011](0011-persisted-formats.md) | Versioned little-endian persisted formats |
| [0012](0012-error-flow.md) | Typed errors follow ownership and adapters own presentation |
| [0013](0013-board-representation.md) | Hybrid board, compact moves, caller-owned state and static attack geometry |
| [0014](0014-board-throughput-and-64-bit-targets.md) | Board throughput specialization and 64-bit x86-64/ARM64 target boundary |
| [0015](0015-score-and-evaluation-boundary.md) | Score bands, phase interpolation and statically bound evaluation |
| [0016](0016-bootstrap-hce-snapshot.md) | Bounded original bootstrap HCE and one-time reference snapshot |
| [0017](0017-strategic-hce-freeze.md) | Strategic HCE correctness, throughput and scope freeze |
| [0018](0018-search-correctness-baseline.md) | Deterministic search correctness, evidence and interruption ownership |
| [0019](0019-tt-ordering-and-diagnostics.md) | Validated TT, staged ordering and behavior-inert diagnostics |
| [0020](0020-uci-search-and-clock-baseline.md) | Persistent one-thread UCI jobs and conservative receipt-based clock |
| [0021](0021-search-benchmark-and-qualification.md) | Versioned whole-search fingerprint and diagnostic qualification boundary |
| [0022](0022-verified-null-move-candidate.md) | Accepted verified null-move pruning and promotion evidence |
| [0023](0023-late-move-reduction-candidate.md) | Accepted conservative late-move reduction and promotion evidence |
| [0024](0024-search-reference-observation.md) | Frozen classical search references and behavior-inert observation contract |
| [0025](0025-balanced-quiet-history-candidate.md) | Rejected balanced quiet-history and conservative reduction-confidence candidate |
| [0026](0026-qsearch-see-authority-candidate.md) | Accepted quiescence SEE eligibility and evidence-authority mechanism |
| [0027](0027-frontier-reverse-futility-candidate.md) | Parked frontier reverse-futility component checkpoint |
| [0028](0028-search-context-and-depth-vocabulary.md) | Accepted behavior-neutral search context and prospective-depth vocabulary |
| [0029](0029-depth-authority-candidate.md) | Accepted check-extension, IIR and TT-dependent singular/exclusion family |
| [0030](0030-shallow-selectivity-family-candidate.md) | Accepted shallow-selectivity family: reverse/quiet futility, late-move and main-search SEE pruning, with razoring parked |
| [0031](0031-probcut-candidate.md) | Accepted bounded ProbCut with two-stage verification and reduced typed TT authority |
| [0032](0032-contextual-reply-history-candidate.md) | Accepted normalized one-ply reply history for quiet ordering |
| [0033](0033-lmr-reply-feedback-candidate.md) | Rejected isolated full-depth LMR false-positive feedback for reply ordering |
| [0034](0034-pre-nnue-classical-convergence.md) | Dependency-ordered pre-NNUE search, HCE and synchronization programme |
| [0035](0035-node-expectation-and-staged-selection.md) | Behavior-neutral prospective node expectation and stable allocation-free staged selection |
| [0036](0036-dynamic-base-lmr-candidate.md) | Monotone depth/move-index dynamic base-LMR candidate |
| [0037](0037-capture-history-candidate.md) | Rejected bounded worker-local capture-history ordering candidate |
| [0038](0038-multi-distance-continuation-history-candidate.md) | Accepted multi-distance continuation-history candidate |
| [0039](0039-lmr-synchronization-candidate.md) | Rejected bounded evidence-vote LMR synchronization candidate |
| [0040](0040-static-eval-tt-qsearch-candidate.md) | Accepted static-evaluation/TT refinement and bounded qsearch-delta cluster |
| [0041](0041-main-selectivity-candidate.md) | Verified-null, ProbCut-TT, history and capture-selectivity cluster |
| [0042](0042-extension-depth-authority-candidate.md) | Expectation-aware IIR, provenance-checked singular extension and searched multi-cut cluster |
| [0043](0043-search-only-cumulative-freeze.md) | Accepted production-switch ledger and cumulative MAN-S19 freeze of the one-thread search head |
| [0044](0044-syzygy-probe-boundary.md) | Vendored Fathom probe layer, typed WDL/DTZ contract and reserved-band tablebase score conversion |
| [0045](0045-score-foundation-and-dispatch.md) | Proposed unwinnable-material clamp and fifty-move score scaling in the evaluator foundation |
| [0046](0046-king-safety-cluster.md) | Accepted shelter, shared attack maps and the first king-safety model |
| [0047](0047-threats-and-space.md) | Accepted piece threats, undefended-material pressure and space control |
| [0048](0048-imbalance-and-evaluation-cost.md) | Accepted constant-time repetition state and fused evaluation producers; proposed nonlinear material imbalance |
| [0049](0049-separating-behaviour-neutral-cost-from-chess-terms.md) | Gate chess terms alone against an accepted head, accept behaviour-neutral work on its fingerprint, and fit the HCE in Phase 5 |
| [0050](0050-primary-reference-switch-and-phase-5-3-resequence.md) | Primary design reference switched, evaluator coverage parity becomes a Phase-5 goal, and Step 5.3 is re-sequenced around structural completion before the fit |
| [0051](0051-maturity-audit-closures.md) | Endgame recogniser authority split, fitting substrate at the structure freeze, and a prospectively registered failure branch for the fit gate |
| [0052](0052-endgame-knowledge-and-pawn-cache.md) | Ordinary-band exact-signature endgame knowledge, throughput-only evaluator budget and worker-local pawn-cache retry |
| [0053](0053-bounded-winnability-and-initiative.md) | Bounded endgame-only winnability from five existing conversion facts |
| [0054](0054-hce-structure-freeze-and-fitting-substrate.md) | Frozen HCE producer/consumer map, complete coefficient schema, sparse features and checked source round-trip |
| [0055](0055-final-hce-maturity-repair.md) | One final pre-fit HCE maturity repair for pawn, attack, king and endgame relations before refreezing the fitting surface |
| [0056](0056-hce-selfplay-data-and-fit.md) | Registered self-play WDL data contract, constrained sparse HCE fit and compiled-vector conformance |
| [0057](0057-correction-history-candidate.md) | Rejected bounded pawn-structure correction producer with isolated qsearch evaluation authority |
| [0058](0058-context-weighted-space-candidate.md) | Statically refuted context-weighted space formulation; retained schema-v3 boundary |
| [0059](0059-shelter-moderated-king-danger-candidate.md) | Prospectively registered signed shelter as a moderator of nonlinear king danger |
| [0060](0060-search-selectivity-sensitivity-pilot.md) | Six live selectivity margins and a bounded SPSA sensitivity pilot |
| [0061](0061-full-search-selectivity-spsa.md) | Withdrawn unrun five-coordinate, 5,000-iteration SPSA proposal |
| [0062](0062-complete-search-spsa.md) | Ten-coordinate production-search SPSA with a 2,000-iteration horizon and staged stop |
| [0063](0063-baked-search-spsa-candidate.md) | Rounded complete-search SPSA vector and its single production SPRT |
| [0064](0064-lazy-smp-ownership.md) | Main-authoritative lazy SMP with worker-local search state and shared validated TT evidence |
| [0065](0065-integrated-time-management.md) | Integrated optimum/maximum clock policy from completed-root, ponder and normalized SMP evidence |

An ADR records the accepted decision and its boundary, not implementation
detail that still requires evidence. A later incompatible choice adds a new
ADR that supersedes the old one; it does not rewrite history silently.
