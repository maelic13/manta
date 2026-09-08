# Manta coding-agent instructions

These instructions apply to the entire repository.

## Read before acting

Read the current checkpoint and owning contract before changing anything:

1. `GUIDE.md` for the current phase and permitted work;
2. `REQUIREMENTS.md` for normative behavior and verification IDs;
3. `ARCHITECTURE.md` and the relevant ADRs for dependency/ownership decisions;
4. `PLAN.md` for sequencing and evidence gates; and
5. `EXPERIMENTS.md` before proposing or repeating an experiment.

## Scope and approval checkpoint

Before the first edit, state a small worklist: requested outcome, expected
files/areas and verification gate. Approval covers only that list and these
direct consequences:

- read-only inspection needed to understand the owning contract;
- the direct implementation and focused tests for the requested behavior;
- minimal compile, formatting and policy repairs caused by those edits; and
- required updates to the owning contract/evidence documents for that decision.

Anything else is a scope change. **Notify the maintainer and wait for explicit
approval before doing it.** This includes adjacent mechanisms, broad cleanup,
build/launcher features, job preparation, unrelated documentation, new
measurement programmes, phase advances and follow-on implementation.
"Fix what needs fixing" authorizes defects that are necessary for the named
outcome and its current gate; it does not authorize nearby work.

If new evidence invalidates the approach or exposes another defect, stop before
editing that scope. Report the evidence and blocking status, smallest proposed
change, expected files/gate and whether approved work can finish without it.
Do not bundle the proposal while waiting. Urgent correctness or data-loss risk
may justify stopping immediately, never quietly expanding scope.

## Work and token economy

- Read the current checkpoint and the owning sections; do not reread or emit
  whole historical documents when bounded `rg` results and relevant slices
  establish the contract.
- Use cheap compile/focused tests while editing, then run each required full
  gate once after behavior freezes. Documentation-only edits get only their
  applicable formatting/policy check.
- Measure only the prospective quantities needed by the current decision.
  Freeze implementation first, then make the final measurement once.
- Treat an exact fingerprint mismatch as a diagnostic: obtain and explain the
  new value with the narrowest available command before deciding whether a full
  suite rerun is necessary.
- Keep commentary to scope decisions, blockers and material milestones. Do not
  repeat command output or narrate routine tool usage. Keep handoff concise.
- Do not create new plans, artifacts, commits, experiment registrations or run
  configurations beyond what the maintainer approved for the turn.

Do not implement work from a later phase. Phases 0–4 and Steps 5.0–5.1.4 are
complete; rejected MAN-S14 is disabled and production is MAN-S15. Step 5.1.5.0
pre-NNUE search convergence rebaseline and Step 5.1.5.1 behavior-neutral node
expectation/move-order substrate and Step 5.1.5.2 MAN-S15 dynamic base LMR are
complete; Step 5.1.5.3 MAN-S16 capture history was rejected and defaults off.
MAN-S17 continuation evidence accepted H1 in Step 5.1.5.4; Step 5.1.5.5
MAN-S18 LMR synchronization is rejected. Step 5.1.5.6 MAN-S19 static-eval/TT/
qsearch accepted H1 and is production. Step 5.1.5.6R closed skipped because it
created no new contextual capture relation. Step 5.1.5.7 MAN-S20 main
selectivity accepted H0 and defaults off. Step 5.1.5.8 extension and depth
authority exhausted MAN-S21's full game cap without H1 and defaults off.
Step 5.1.5.8R closed skipped because no accepted new reduction-confidence
relation met its trigger. Step 5.1.5.9 is complete: behavior-identical MAN-S22
accepted H1 against MAN-S13, freezing exact MAN-S19 as the one-thread interior
search head. Step 5.2 Syzygy and Steps 5.3.0–5.3.17 HCE convergence are
complete; MAN-E19 promoted the fitted structural HCE head and Phase 5.3 is
closed. Step 5.4.0 search coverage is complete. Step-5.4.2 MAN-S23 was refuted
by its deterministic branching filter and conditional MAN-S24 never opened.
Step 5.4.1 is closed after MAN-S25 bounded pawn-structure correction history
accepted H0; it remains archived default-off and exact MAN-S19 remains
production. The rejected evidence grants no correction-selectivity authority
or Step-5.4.2 trigger. Step-5.4.3 MAN-E20 context-weighted space is statically
refuted after its fitted coefficient reversed sign and missed the validation
floor; schema v3 remains as behavior-neutral cleanup. MAN-E21 shelter-moderated
king danger passed deterministic qualification but its `[1,5]` SPRT accepted
H0 at -9.31 +/- 7.98 nElo; it remains default-off without retry. Step 5.4.3 is
closed with no promoted formulation and exact MAN-E19 remains production.
Step 5.4.4 closed without another data/fit cycle because the fitted linear
surface is saturated and no measured label-quality bottleneck justifies the
long run. Step 5.4.5 is complete. `MAN-S26` completed its six-coordinate,
4,096-game SPSA sensitivity pilot cleanly; five coordinates passed the signal
gate and quiet futility returned to its seed. The pilot theta is not promoted.
Unrun five-coordinate `MAN-S27` was withdrawn after an activity audit found it
omitted live LMR, late-move-count and contextual-history controls. `MAN-S28`
completed its ten-coordinate 2,000-iteration/64,000-game horizon cleanly; every
coordinate stayed active and away from its rails. Step 5.4.6 is complete.
Its sole rounded complete-theta bake `MAN-S29` accepted H1 after 4,596 games at
`+22.49 +/- 10.04` nElo without anomaly. MAN-S29 is production at fingerprint
`799,610`; the temporary bake selector is removed, frozen MAN-S19 values exist
only for archived diagnostic reconstruction, and the final deterministic gates
pass. Step 5.4.7 and Phase 5 are complete. Cumulative `MAN-C01` compared final
MAN-E19/MAN-S29 against corrected Phase-5.0 `632f93c` and accepted H1 after
126 games at `+459.61 +/- 60.66` nElo without anomaly. The short decisive gate
establishes a material cumulative gain, not a precise rating. Phase 6.0 clock
and root confidence is current. Step 6.0.1 is complete: bounded worker-local
per-root-move score/bound, effort and exact-variance evidence commits only from
whole iterations, remains diagnostic-only and preserves fingerprint `799,610`.
Step 6.0.2 now has a frozen default-off soft-time candidate: two agreeing root-
uncertainty facts spend half of the existing soft-to-hard interval and all
three may spend through the unchanged hard deadline. MAN-R01 accepted H0 at
`-8.36 +/- 7.66` nElo without anomaly, so the consumer remains default-off and
Step 6.0.2 is closed. Step 6.0.3 stability-gated aspiration is closed: the v22
legal-root diagnostic used 22 narrow attempts, one clean fail-low retry and
`24.72%` fewer nodes, but MAN-R02 exhausted its 16,000-game `[1,5]` cap at
`+0.68 +/- 5.38` nElo and LLR `-1.23` without anomaly. The consumer remains
archived default-off without tuning or retry under the current HCE/search head;
the root-confidence producer remains available to later time-management work.
Production remains exact `799,610`. Step 6.1 full UCI parity is complete: one
authoritative public option registry, epoch-scoped urgent signals plus FIFO
ordered control, opt-in completed-result-retaining ponder, original receipt-
based hit timing and bounded coalesced live root/iteration reporting pass the
20-case process matrix and Basilisk lifecycle cross-check. Step 6.0.4 is
complete with an exact once-latched, matching-epoch receipt-to-hit ponder credit;
the existing receipt-based deadlines consume it exactly once, no playing
consumer was added and production remains `799,610`. Steps 6.0 and 6.1 are
closed. Step 6.2 main-authoritative lazy SMP is complete: deterministic 1T
remains `799,610`, fixed-work 1/2/4/8T scaling reached
`1.00x/2.16x/4.17x/7.68x`, and MAN-R03 4T-versus-1T accepted H1 after 194
games at `+187.72 +/- 48.89` nElo without anomaly. The short gate qualifies
the 4T pool, not a precise rating or higher-thread playing strength. Step 6.3.1
is complete: ADR-0065 freezes a default-off integrated optimum/maximum policy
using game progress, completed ordinary root stability/score/effort,
once-counted ponder credit and normalized helper instability without changing
hard safety or worker-zero result authority. Step 6.3.2 is complete: typed
worker-zero telemetry exposes budgets, factors, ponder/helper evidence, stop
reason and hard overshoot; fake-clock and all 23 process cases pass, including
identical allocation at 1/2/4/8T, and production/candidate remain `799,610`.
Step 6.3.3a is complete: the default-exact six-coordinate 1T clock surface is
frozen. The Colosseum `MAN-T01` attempt committed zero iterations before three
engine faults invalidated iteration zero and is withdrawn. Colosseum is parked
by maintainer direction until explicitly re-enabled. The replacement
Weather Factory/fastchess `MAN-T02` completed 128 iterations but is invalid:
its recovering runner committed gradients across one connection stall and did
not distinguish completed clock outcomes from infrastructure faults. Its theta
is rejected. The bridge uses the qualified 20 ms controller margin and commits
only complete mini-matches. Completed time forfeits are scored only for the
`time_sensitivity` group because clock safety is part of that fit's objective;
all other SPSA groups remain strict, and crashes, disconnects, illegal moves,
affinity faults, incomplete scores and nonzero exits still abort. A targeted
64-game stress passed without anomaly and `Move Overhead=10` remains unchanged.
Clean 128-iteration replacement `MAN-T03` was prepared but withdrawn unrun.
`MAN-T04` completed all 1,000 iterations/32,000 committed games cleanly at
theta `1034/957/4291/1036/1049/1046`. Attempted iteration 842 had produced one
completed time forfeit and was discarded under the former policy; its exact
arms then passed a 20-game replay. All coordinates stayed active and far from
their rails, and the final 100-iteration spans were bounded. Step 6.3.3b is
complete. Sole rounded bake `MAN-T05` crossed its `[1,5]` H1 boundary after
4,188 games at `+24.48 +/- 10.52` nElo. The harness rejected the run under its
registered zero-timeout rule because candidate/baseline lost one/five completed
games on time, with no crash. The maintainer explicitly accepted the result by
judgment: completed time forfeits are clock-policy outcomes, their net four-game
contribution is small beside the candidate's 192-game W-L lead, and the
candidate was safer than baseline. This is a post-result evidence waiver, not a
clean prospective-gate precedent. MAN-T05 is production; integrated time and
the fitted vector default on, while the off arm reconstructs untuned MAN-S29.
The cumulative `MAN-C02` final MAN-T05-4T versus final-Phase-5-1T gate accepted
H1 after 150 scored games at `+305.51 +/- 55.60` nElo without anomaly. The
short decisive gate establishes a material cumulative gain, not a precise
rating or component attribution. Step 6.3.3c and Phase 6 are complete. Targeted
pre-NNUE Phase 6.5 is current. Step 6.5.1a rejected only the behavior-identical
staged-picker formulation. Step 6.5.1b is complete: `MAN-S30` accepted H1 after
8,752 games at `+13.19 +/- 7.28` nElo, so live-history staging is production and
the deterministic one-thread depth-6 fingerprint is now `775,451`. Disabling
`-Dlive-history-staging` reconstructs the superseded MAN-S29 eager picker at
`799,610` for archived diagnostics. The run's four completed time forfeits
(three baseline, one candidate, no other fault) tripped the bridge's
zero-timeout rule and carry an explicit post-result maintainer waiver, not a
prospective precedent. Step 6.5.2 whole-tree attribution and Step 6.5.3 are
closed. MAN-S31 was rejected by maintainer judgment at 7,958 games,
`-3.08 +/- 7.63` nElo, not formal H0. MAN-S32 remains parked default-off.
The maintainer stopped MAN-S33; the supplied 6,640-game snapshot is
`+1.24 +/- 8.36` nElo, LLR `-0.39`: inconclusive, unpromoted, no automatic
retry. Final artifact reconciliation is not permission for new games.
Production remains MAN-S30 at `775,451`.

ADR-0068 and the reworked PLAN supersede the old open Phase-6.5 sequence.
Step 6.5.4 is prepared but not complete: PLAN records frozen limits/identities,
bounded tickets and completed profiler/SEE setup tooling. The ten-capture
threshold-zero comparison passes; source-bound designated-host board/search
baselines remain. Do not start 6.5.5 before its gate closes. Steps 6.5.5–6.5.7 improve
the board backbone and exact
qsearch cost; 6.5.8–6.5.12 derive a coordinated modern search; 6.5.13 addresses
measured residual cost; 6.5.14 is an optional fit decision; 6.5.15 separately
qualifies board parity, depth-13 elapsed time and strength. Modern Stockfish's
pinned search structure and feature relationships may be reimplemented as
original Zig with Manta-owned contracts and scales. Reference constants, NNUE
confidence assumptions and trace matching are not targets.
Do not infer safe pruning headroom from a low re-search rate, unique work from
overlapping inclusive counters, or game strength from fixed-depth node savings.
Do not revive rejected umbrellas merely because the reference has them.
Every implemented consumer must share the accepted evidence/depth contract.
No automatic games, pilots, PGO, SPSA or Phase-7 implementation. Stop before
Phase 7; its first step requires separate maintainer approval.

## Product objective

Manta's goal is the strongest correct chess-playing engine we can produce in
Zig. One-thread behavior is the first-class deterministic baseline. Four-thread
correctness, time safety, strength and scaling are separate later gates; do not
infer them from one-thread results. Treat scaling beyond measured thread counts
as a hypothesis.

Mature engines may accelerate Manta development by supplying candidate ideas,
dependency relationships, failure modes and testing methods. They are study
references, not implementation targets. Manta independently selects each
hypothesis, derives its chess/search rationale, implements original Zig
mechanisms and accepts them only through native evidence. Code similarity,
constant copying and trace convergence are never objectives.

**Stockfish is the primary reference** as of ADR-0050, in the final pre-NNUE
classical snapshot pinned in `config/eval-reference.json`; Basilisk is the
secondary cross-check. One narrow goal changed with it: **coverage parity for
the Phase-5 evaluator is a goal** — the set of chess concepts Manta prices
should reach the reference's maturity before Phase 5 closes, tracked in
`docs/HCE_COVERAGE.md`. **Implementation parity remains forbidden.** Adopt the
concept, derive the mechanism yourself, write original Zig, choose your own
values. Coverage is a candidate list, never evidence: rejected `MAN-E05` and
`MAN-E07` were both reference-family ideas that lost games here.

Keep the numbered phase order. Complete the classical evaluator, one-thread
search, time/UCI and SMP build-up in Phases 5–6 before starting the Phase-7
NNUE runway. Modern NNUE engines inform the later work but do not pull NNUE
forward or bypass the current HCE/search evidence steps.

Correctness tests, code similarity, node reduction, depth, NPS and static loss
do not prove playing strength. Once tournament-capable, registered games decide
playing changes; diagnostics explain them.

During Phase 6.5, every retained production-executable candidate, including an
exact speed optimization, requires one prospectively registered 1T SPRT. A
candidate claiming behavior identity must reproduce the accepted fingerprint,
PV and results; a diagnosed legal deterministic mismatch reclassifies it as a
playing candidate rather than rejecting it for strength. Documentation, tests
and disabled diagnostics require no games.

For a coherent evaluation-strength candidate, evaluator throughput is a cost
diagnostic rather than an automatic refutation: stronger chess decisions may
justify slower evaluation, and representative time-controlled games measure
the net result. A pre-game cost veto requires an explicit operational or host-
budget derivation; never invent an Elo-equivalent speed threshold.

No playing candidate is promoted before Phase 4 provides the conservative 1T
clock policy required for representative time-based games. After that point,
prospectively select one time control and thread scope for the claim and run one
authoritative SPRT. Fixed-node games may diagnose quality per node but never
promote a candidate, and the same change is not automatically re-gated at
several time controls or thread counts.

Reaching a numbered phase does not automatically authorize SPSA. Propose it
only after the affected consumers freeze and evidence shows that a joint fit of
interacting continuous parameters is necessary and worth its game budget.

Prefer one independently meaningful idea per playing candidate. A cohesive
bundle is permitted only when its parts are semantically inseparable,
intermediate states are invalid or misleading, or the expected effects are
individually below the resolution affordable on the designated host. State one
mechanism-level hypothesis, exclude unrelated changes, preserve component
switches and run one final production SPRT. A passing bundle licenses the bundle,
not a claim that every component helped; use targeted, value-of-information
ablations rather than an exhaustive matrix.

The designated game-testing, tuning and final cross-engine comparison host is
the separate Ryzen 9 5950X, not the development workspace computer. Do not
start long jobs as a coding agent. Prepare exact candidate/baseline source and
binary identities, hashes, toolchain/options, a setup-only command, prospective
pair/game cap, qualified retained pair rate, expected and worst-case wall time,
storage estimate, checkpoint/resume path and stop rule for the user to run.
Require the returned manifest, log, PGN and checkpoint before recording a
verdict. Do not overlap it with data generation or other timed work on that
machine.

The Rarog/Basilisk-derived fastchess SPRT harness, its 5950X placement, book,
time control, adjudication and anomaly checks are battle-tested and trusted.
Do not require a pilot before an ordinary Manta SPRT while those boundaries are
unchanged. Reuse retained rate/storage evidence and proceed directly from a
successful setup-only check to the registered final SPRT. A pilot is warranted
only when an operational boundary changes and specifically needs qualification.

Colosseum is parked until the maintainer explicitly authorizes trying it again.
Until then, use Manta's checked Rarog-derived fastchess bridge for matches and
its existing pinned local Weather Factory checkout plus first-party wrapper for
SPSA. Do not silently substitute Colosseum. `net_trainer` owns engine-agnostic
NNUE data, training, export, format and conformance tooling. Do not fork, vendor
or independently reimplement third-party shared tooling in Manta.

That rule governs the **shared** tools above and all third-party code. It does
not govern Basilisk and Rarog, which are the maintainer's own engines under the
same licence: their tooling may be copied into Manta and maintained here as
first-party code, with no vendoring contract and no upstream obligation. Where
both hold a version of the same tool, compare them and take the better one
rather than the nearer one. Everything else in this document still applies to
the result — it becomes Manta code, held to Manta's standards.

## Chess-domain reasoning is mandatory

Before implementing or reviewing a chess/search change, state:

- the chess rule or search/evaluation mechanism involved;
- the producer, transformations and every consumer of changed state/evidence;
- legal-position, terminal, draw/history and special-move consequences;
- score/bound/provenance assumptions;
- expected node, branch, cache, allocation and thread behavior;
- why the change could improve correctness, speed or playing strength; and
- which evidence can refute the hypothesis.

Do not mechanically translate another implementation, preserve a formula
because it is familiar, or accept a mechanism because current tests pass.

## Test requirements

Every non-trivial test or suite must identify the domain invariant or
engineering contract it protects. Prefer an independent oracle or property:

- legal chess rules, independently derived perft or terminal outcomes;
- randomized make/unmake plus complete state recomputation;
- metamorphic properties with their chess preconditions and exceptions stated;
- legal PV/bestmove, mate-distance and draw-history semantics;
- feature-on/off equivalence where a mechanism must preserve results;
- allocation, bounds, cancellation, ordering and concurrency instrumentation;
- scalar/backend and incremental/full-refresh conformance; and
- domain-realistic benchmarks and game evidence.

Do not reproduce production logic inside the test and call it independent.
Do not assert an exact evaluation, node count, byte size, constant or tuning
value merely because it is the current output. Exact values are appropriate
only for a documented protocol/format contract, a deliberately frozen
conformance snapshot, or a diagnostic fingerprint with an update procedure.

Never update an expected value just to make a failure disappear. Determine
whether the implementation, the expectation or the underlying chess premise
is wrong, and record the reason for an intentional change.

Passing tests is necessary, not sufficient. Ask whether the tested property is
meaningful for legal chess and for the goal of producing a stronger engine.

## Zig and architecture requirements

- Use Zig 0.16.0 until the latest-stable migration rule changes it; never use
  nightly syntax or compatibility shims.
- Follow the inward dependency graph in `ARCHITECTURE.md`.
- Use explicit allocators/ownership, precise types, optionals, error unions and
  tagged unions.
- Prefer `comptime` specialization and concrete hot-path types. Runtime
  indirection belongs only at an approved coarse boundary.
- No allocation, formatting, I/O, locks or avoidable shared atomics in ordinary
  node/move/evaluate hot paths.
- Keep unsafe/unchecked operations local, documented by an invariant and
  covered by safety builds plus focused tests.
- The scalar implementation is authoritative; optimized backends are exact.
- Preserve unrelated user work and keep public documentation concise.

## Evidence and completion

Run the gate appropriate to the change and its current phase. A completed step
updates `PLAN.md` and `GUIDE.md`; update `REQUIREMENTS.md`, architecture/ADRs or
`EXPERIMENTS.md` when their contract/evidence changes. Do not run long games,
tuning, datagen, PGO or timed work unless the current plan explicitly requests
it.
