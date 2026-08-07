# Manta coding-agent instructions

These instructions apply to the entire repository.

## Read before acting

Read the current checkpoint and owning contract before changing anything:

1. `GUIDE.md` for the current phase and permitted work;
2. `REQUIREMENTS.md` for normative behavior and verification IDs;
3. `ARCHITECTURE.md` and the relevant ADRs for dependency/ownership decisions;
4. `PLAN.md` for sequencing and evidence gates; and
5. `EXPERIMENTS.md` before proposing or repeating an experiment.

Do not implement work from a later phase. The Phase-0.3 gate has opened Phase 1
only; board, evaluation, search and other later-phase work remain unauthorized
until `PLAN.md` reaches their owning phase.

## Product objective

Manta's goal is the strongest correct chess-playing engine we can produce in
Zig. One-thread behavior is the first-class deterministic baseline. Four-thread
correctness, time safety, strength and scaling are separate later gates; do not
infer them from one-thread results. Treat scaling beyond measured thread counts
as a hypothesis.

Correctness tests, code similarity, node reduction, depth, NPS and static loss
do not prove playing strength. Once tournament-capable, registered games decide
playing changes; diagnostics explain them.

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

The designated game-testing and tuning host is one Ryzen 9 5950X. Do not start
long jobs as a coding agent. Prepare a bounded Colosseum job with an exact host
profile, prospective pair/game cap, pilot-measured pair rate, expected and
worst-case wall time, storage estimate, checkpoint/resume path and stop rule
for the user to run. Do not overlap it with data generation or other timed work
on that machine.

Colosseum owns engine-agnostic match, SPRT, SPSA, calibration, placement and run
records. `net_trainer` owns engine-agnostic NNUE data, training, export, format
and conformance tooling. Fix reusable gaps in their upstream repositories;
Manta owns only checked configurations and original Zig engine integration.
Do not fork, vendor or independently reimplement shared tooling in Manta.

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
