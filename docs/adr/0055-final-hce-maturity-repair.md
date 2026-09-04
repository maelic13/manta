# ADR-0055: Reopen the HCE structure for one final maturity repair

## Status

Accepted and completed for Step 5.3.15R on 2026-08-21 by maintainer direction.
Supersedes ADR-0054's structural/schema-v1 freeze while retaining its fitting
representation and zero-runtime-cost requirements. Interior one-thread search
remains frozen.

## Context

The first post-freeze audit found that concept-name coverage had been mistaken
for mechanism maturity. The repository still named candidate/leverable passers
as missing and graded passer-path safety as partial. Several rows recorded as
present used deliberately small first implementations: pseudo-attacks from
pinned pieces fed mobility and downstream consumers, space was an unweighted
home-half count, shelter ignored possible castling destinations, king danger
did not fully combine pawn and piece attackers, and several exact-signature
endgames reduced their geometry to a constant or a coarse rank rule.

A coefficient fit cannot repair an absent producer, an incorrectly classified
feature or an excluded nonlinear consumer. Generating the long labelled corpus
before resolving those facts would either freeze known gaps or force a second
fit. The maintainer intends the HCE to be a finished fallback if NNUE succeeds,
so this is the last normal-path structural review rather than Phase-11 work.

## Decision

Add Step 5.3.15R, committed and verified one substep at a time:

1. **5.3.15R.0 — contract.** Reconcile the coverage ledger with consumers and
   state the refutation gates before changing behavior.
2. **5.3.15R.1 — pawns and passers.** Make doubled/isolated/backward ownership
   non-overlapping, add candidate/leverable passers, and grade every promotion-
   path square by attack and defence rather than one clean-path bit.
3. **5.3.15R.2 — attacks, mobility, threats and space.** Restrict pinned-piece
   evidence to its legal ray, define a mobility area distinct from raw attacks,
   preserve x-ray intent explicitly, align threat classes with protection, and
   make space central, pawn-supported and material-sensitive.
4. **5.3.15R.3 — king safety.** Make shelter depend on file geometry, consider
   legal castling destinations, add endgame king-to-pawn proximity, and combine
   pawn/piece attackers, checking-square safety, defender resources and queen
   availability without granting terminal authority.
5. **5.3.15R.4 — endgames and winnability.** Use exact KPK WDL classification
   inside the ordinary score band, replace constant exact-signature values and
   broad scale guesses with geometry/tempo rules, and close the omitted
   winnability facts. Syzygy remains search-owned and higher authority.
6. **5.3.15R.5 — refreeze.** Reconcile every coverage row, update the parameter
   schema and sparse extraction, reproduce production exactly, and restate the
   bounded throughput and residual evidence before datagen.

No reference formula or constant is an implementation target. Each mechanism
is derived from the chess relation above and uses original Zig. A relation may
be explicitly rejected if an independent counterexample shows it is unsound;
an unimplemented or merely named row may not be called complete.

### R.3 outcome

The legal future-castling shelter relation was implemented with orthodox
rights, occupancy, check and attacked-transit preconditions, then rejected at
the prospective performance gate. Its optimized form measured 2,987,482
eval/s, -44.8% from the Step-5.3.9 head and outside the 40% allowance. The
retained design evaluates the king's current shelter with exact file identity,
including edge files, and keeps endgame king-pawn proximity plus pawn-attacker
and queen-availability danger. Castling rights therefore remain search/legal
state and are not an HCE input.

### R.4 outcome

KPK now uses a checked, generated win/draw bitbase rather than rank and
opposition guesses. Its legal-move generator is retained under
`zig build generate-kpk`; engine builds embed the 24 KiB result and never run
retrograde analysis. Other exact-signature values and scales consume king
geometry and/or side-to-move tempo. Winnability additionally consumes total
pawn count and the pure-pawn-ending fact; an initial aggressive weighting was
rejected because it worsened the frozen held-out residual, and the retained
conservative rebase restores that property. All results remain ordinary static
evidence below Syzygy, search terminal and draw authority.

### R.5 outcome

The final producer/consumer map is frozen in `docs/HCE_STRUCTURE.md` and every
standard-chess coverage row is present, superseded or explicitly rejected.
`manta-hce-fit-v2` inventories 132 groups and 1,241 coefficients: 1,119 honest
linear free values, 19 structural fixed values and 103 named exclusions.
Current-vector sparse extraction reconstructs production exactly across the
frozen cohort and deterministic legal walk. V1 remains only the incompatible
pre-repair snapshot. Debug, ReleaseSafe and ReleaseFast tests, the portable
build, formatting, policy and lint pass. Because R.5 changes only offline
tooling and documentation, it retains R.4's `720,169` production fingerprint,
held-out residual result and 3,294,829 eval/s (`-39.1%`) throughput evidence.

## Authority and behavior

The producers remain legal position state, exact piece/pawn placement, shared
attack geometry, castling rights and the existing phase/endgame facts. The
transformations are evaluator-local and allocation-free. Consumers remain the
tapered ordinary static score, the exact raw-evaluation cache and the offline
feature sink. No repair may create a mate/tablebase band, search bound, draw
verdict, PV, TT result, history update or legality decision.

Promotion is represented by resulting material; en-passant affects current
occupancy and pawn attacks; castling rights do not affect retained HCE shelter;
rule-50 scaling stays after ordinary evaluation. Terminal, repetition,
insufficient-material and Syzygy contracts are unchanged. State stays bounded
and worker-local, so one-thread determinism and later per-worker SMP ownership
remain intact.

## Refutation evidence

Every substep needs independent legal-position counterexamples, colour/rank
symmetry, feature-off attribution and full state/PV/search safety gates. Attack
repairs additionally require pinned/unpinned metamorphic cases; pawn work needs
candidate creation/destruction and path-square monotonicity; shelter needs
castling-right and flank mirrors; endgames need both-colour win/draw boundary
oracles and ordinary-band checks. The final refreeze requires exact sparse
reconstruction, Debug/ReleaseSafe/ReleaseFast and portable tests, lint/format,
all archived fingerprints, held-out residual reporting and the existing
40-percent evaluator-throughput allowance. Games still promote only the baked
Step-5.3.16 fit.

## Consequences

Step 5.3.16 datagen begins only after this completed refreeze. Existing schema
v1 remains a conformance snapshot of the pre-repair evaluator and is versioned
rather than silently reinterpreted. Phase 11 stays closed unless the normal
NNUE retry map later opens it explicitly.

## Traceability

- `PLAN.md` 5.3.15R; `GUIDE.md`; `docs/HCE_COVERAGE.md`.
- `src/eval/hce.zig`, `src/eval/endgame.zig`,
  `src/eval/winnability.zig`, `src/eval/fit.zig`.
- ADR-0050 through ADR-0054; `SCORE-001`, `PERF-002`, `QUAL-015`.
