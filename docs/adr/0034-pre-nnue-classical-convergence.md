# ADR-0034: Dependency-ordered pre-NNUE classical convergence

## Status

Accepted as the Phase-5 programme on 2026-08-14. Step 5.1.4 is complete with
MAN-S14 rejected and disabled; MAN-S13 is the immutable entry baseline.
Steps 5.1.5.0–5.1.5.8R are complete: MAN-S18 and MAN-S20 were rejected,
MAN-S19 accepted, MAN-S21 exhausted its cap without promotion, and both
conditional repeats closed skipped. Step 5.1.5.9 is complete: behavior-
identical MAN-S22 accepted H1 against MAN-S13 at `+13.32 +/- 7.83` nElo, so
exact MAN-S19 is the frozen one-thread search head and Step 5.2 is open.
Phase 7 NNUE remains blocked until the extended
Phase-5 classical work and Phase-6 root/time/UCI/SMP work complete.

## Context

Manta's first search pass produced a coherent, substantially stronger native
engine, but it did not implement every important classical-search contract in
the frozen Stockfish 11/final-pre-NNUE reference map. In particular, Manta has
fixed one-ply LMR, one-ply quiet reply history and no capture history, explicit
cut-node reduction model, multi-distance continuation evidence or complete
history/selectivity synchronization. MAN-S14 showed why adding one downstream
feedback event alone is not enough: its correct, populated implementation was
centered below zero in games.

The Rarog `hybrid` result and `codex/search-convergence` plan provide two
development priors only: holding evaluation fixed can isolate search value, and
ordering/history/LMR plus static/TT/qsearch plus selectivity/depth should be
treated as dependency clusters. They are not Manta results and do not license
foreign code, constants, formulas, behavior or feature parity.

Testing every small subcomponent separately risks rejecting evidence producers
whose useful consumer does not exist yet. Implementing everything and asking
one final SPRT hides attribution and lets a harmful arm ride with a strong one.
SPSA cannot solve either problem: its gradient can tune continuous values only
after the categorical architecture, score scale and parameter consumers are
valid and frozen.

## Decision

- Extend Phase 5 with Step 5.1.5 search convergence, Step 5.3 HCE convergence
  and Step 5.4 joint synchronization/final fit. Keep Phase 5.2 Syzygy between
  search and HCE so endgame truth is available to the evaluator audit.
- Freeze the original Manta HCE throughout 5.1.5. Freeze the accepted search
  head throughout 5.3. Joint behavioral changes belong only to 5.4.
- Implement search in evidence-flow order: node/cut and move-order substrate;
  dynamic base LMR; capture history; multi-distance continuation producers;
  history/context-aware LMR; static/TT/qsearch; main selectivity; extensions;
  then a cumulative search checkpoint.
- Give dynamic base LMR and capture-history ordering individual SPRTs because
  each has a complete standalone mechanism and plausible material signal.
- Treat multi-distance continuation state as one producer bundle and
  history/context-aware LMR as a later consumer bundle. Preserve compile-time
  switches for every meaningful component, but do not spend one SPRT per
  history distance or test a history consumer before its producer freezes.
- Treat static/TT/qsearch, main selectivity and extension/depth authority as
  separate dependency-complete clusters. Each cluster receives one registered
  game gate after deterministic producer/consumer accounting; allow only
  value-of-information ablations, never an exhaustive switch matrix.
- Develop the HCE in dependency clusters: score foundation/dispatch;
  pawn/endgame; activity/threat/space; king safety/imbalance; cost and
  search-conditioned activation; then a cumulative HCE checkpoint.
- Add correction history and evaluator/search compatibility only after the HCE
  residual and score scale freeze. A correction producer first proves bounded,
  populated semantics before pruning or reduction can consume it.
- SPSA is conditional. First resolve every categorical switch by ordinary
  evidence, freeze consumers/defaults/ranges, complete a sensitivity and
  identifiability review, and obtain explicit maintainer authorization. Tune
  normally 4–8 continuous coordinates; more than 12 requires a new plan
  amendment. Binary features never become SPSA coordinates.
- A baked tune receives one production 1T `3+0.03` SPRT against the untuned
  accepted structural head. H0/cap restores accepted defaults but does not
  erase structurally accepted mechanisms. Phase 5 ends with a cumulative
  classical freeze before Phase 6.
- Root aspiration/confidence/time remain in 6.0; UCI lifecycle in 6.1; shared
  histories, helper search and scaling in 6.2. NNUE later reopens evaluator-
  dependent search assumptions in 9.2–9.3 instead of treating HCE-era choices
  as permanently optimal.

## Consequences

The programme is longer than the original Phase 5, but every step has an
accepted checkpoint and explicit stopping point. Infrastructure must be
behavior-identical. Independent mechanisms remain attributable. Coupled
features are tested only when their prerequisites make their result meaningful.
Two coherent cluster failures trigger a map/value review rather than automatic
continuation, and a surprising result permits at most one or two registered
high-information ablations.

Ordinary search nodes retain allocation-free concrete Zig paths. History stays
worker-local until SMP owns sharing. New evidence never acquires score, bound,
PV, TT, terminal or draw authority implicitly. All legal-position, check,
special-move, mate-distance, rule-50, cancellation and make/unmake contracts
remain gates for every cluster.

Reference similarity, node reduction and static teacher loss remain diagnostic.
Only clean time-based games promote playing behavior. The final classical
baseline is expected to be strong and coherent, not a line-for-line or
feature-for-feature copy of another engine.

## Traceability

Supports `FUNC-004`, `FUNC-005`, `FUNC-006`, `SCORE-008`, `SCORE-010` through
`SCORE-021`, `PERF-006`, `PERF-009`, `PERF-010`, `QUAL-013` through
`QUAL-017` and the Phase-5/6 gates in `PLAN.md`.
