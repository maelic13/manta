# Manta coding-agent instructions

These instructions apply to the entire repository. They describe how an agent
works here; they do not describe the project's current state. Where the
project stands, what is open and what is permitted are owned by the documents
below and change without this file changing.

## Where the state lives

| Question | Owning document |
|---|---|
| Which step is open, which are prepared, what is next | `GUIDE.md` current checkpoint and roadmap checkboxes |
| A step's tickets, frozen contracts, verification and gates | `PLAN.md`, the section of that step |
| Normative behavior and verification IDs | `REQUIREMENTS.md` |
| Dependency and ownership decisions | `ARCHITECTURE.md` and `docs/adr/` |
| Which candidates are production, rejected, parked or inconclusive | `EXPERIMENTS.md` |
| Production identity and deterministic fingerprint | `GUIDE.md` checkpoint, confirmed by the bench |

Read them in this order before changing anything: `GUIDE.md`, `PLAN.md` for
the open step, `REQUIREMENTS.md` for the affected IDs, `ARCHITECTURE.md` and
the relevant ADRs, then `EXPERIMENTS.md` before proposing or repeating an
experiment. Do not rely on a summary of the state from any other file,
including this one.

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

If a non-blocking bug, chess error or promising improvement is noticed outside
the current scope, finish the approved step first and report the finding
separately at the end without implementing it. If the maintainer interrupts
work with a correction, finish and cheaply qualify that correction, report it
and return control; do not silently resume the interrupted objective unless
asked.

Work only on the step and ticket that `GUIDE.md` marks open and that the
maintainer has approved. A prepared step is not a started step; a sub-ticket's
approval does not cover the next one. Do not implement work from a later step
or phase, and do not start the first step of a new phase without separate
maintainer approval. A rejected, parked or inconclusive candidate recorded in
`EXPERIMENTS.md` stays off; its switch is not revived because a reference
engine has the feature, and its dependent proposals are re-derived against
actual production before implementation. No games, pilots, tuning, data
generation, profile-guided builds or other long runs start without the current
plan explicitly requesting them and the maintainer approving the run.

## Work and token economy

- Read the current checkpoint and the owning sections; do not reread or emit
  whole historical documents when bounded `rg` results and relevant slices
  establish the contract.
- Use cheap compile and focused invariant tests while editing. **Verify
  mechanically, never by eyeballing, and never by assuming a tool did what its
  name says.** Check exit status directly, never masked through a pipe, and
  test behavior or constructs rather than words in a comment. The deterministic
  behavior gate for a search change is the native ReleaseFast `bench 6 1`
  fingerprint in every affected arm; exact `bench` identity is a necessary
  fingerprint, not proof of behavioral identity (evaluation activation,
  terminal logic, time handling and other path-dependent changes can alter play
  while leaving `bench` equal). Full suites are not a routine per-step gate;
  they run before a release or when the maintainer asks, and each step's
  evidence records which gates actually ran. Documentation-only edits get only
  their formatting and policy check.
- Measure only the prospective quantities needed by the current decision.
  Freeze implementation first, then make the final measurement once.
- Treat an exact fingerprint mismatch as a diagnostic: obtain and explain the
  new value with the narrowest available command before deciding whether a full
  suite rerun is necessary.
- Keep commentary to scope decisions, blockers and material milestones. Do not
  repeat command output or narrate routine tool usage. Keep handoff concise.
- Do not create new plans, artifacts, experiment registrations or run
  configurations beyond what the maintainer approved for the turn.

## Delivery, commits and reporting

- `master` is the trunk; nothing else lives long. Every coherent piece of work
  -- one feature or experiment, or one tooling, documentation or release change
  -- lives on its own short-lived branch from `master` and lands as **one
  squash commit** through a pull request: no merge commits and no rebase merges.
  When starting approved work, the coding agent creates that short-lived branch
  from `master` if it is not already on one.
- On the branch, commit in small verified steps once each step or substep's
  gates pass and its documents are reconciled; GitHub retains those working
  commits under the PR (`refs/pull/<n>/head`) after the squash. Do not leave
  finished work uncommitted waiting for permission, and do not ask whether to
  commit. Branch commit subjects are concise and imperative and may name the
  step or ticket; engine changes and tooling or documentation changes go in
  separate commits.
- Before opening the PR, merge `master` into the branch if `master` moved, so
  the PR shows only the branch's own change. After the maintainer confirms the
  squash merge, the coding agent may delete the local branch; deleting the
  remote branch on `origin` happens only when the maintainer explicitly asks.
- **The squash message** -- the PR title and description, which is all that
  reaches `master` -- has a fixed shape:
  - Title: short and imperative, saying what changed (for example, `"Tighten
    late-move reductions"`), with no test results and no phase, plan or ledger
    references.
  - Body: a few plain lines on what and why, wrapped at 72 columns.
  - Results: one per line (for example, `"STC 3+0.03: +32.7 ± 8.9 Elo (2,450
    games)"`, or `"No game test: documentation and tooling only."`).
  - Bench line: `Bench: <nodes>`, the `bench 6 1` node count `master` will have.
  - Empty lines separate the title, body, results and bench line.
- No AI attribution anywhere: no `Co-Authored-By`, no `"Generated with"` line,
  in commits, PRs or files; the maintainer is the sole author of record.
- Do not amend, push, delete a remote branch, open or merge a PR, or rewrite
  history unless the maintainer explicitly asks.
- **Open nontrivial reports with a one-line recommendation** -- what to do next
  and why, in one sentence, before evidence and options. Put runnable
  maintainer commands in their own fenced block and restate them rather than
  referring back. Keep end-step reports concise: outcome, essential
  verification, commit, any separate non-blocking findings and next step.

## Product objective

Manta's goal is the strongest correct chess-playing engine we can produce in
Zig. One-thread behavior is the first-class deterministic baseline. Multi-thread
correctness, time safety, strength and scaling are separate gates; do not infer
them from one-thread results. Treat scaling beyond measured thread counts as a
hypothesis.

Mature engines may accelerate Manta development by supplying candidate ideas,
dependency relationships, failure modes and testing methods. They are study
references, not implementation targets. Manta independently selects each
hypothesis, derives its chess/search rationale, implements original Zig
mechanisms and accepts them only through native evidence. Code similarity,
constant copying and trace convergence are never objectives.

The primary and secondary references, their pinned revisions and the coverage
studies derived from them are recorded in `config/eval-reference.json`,
`docs/HCE_COVERAGE.md` and `docs/SEARCH_COVERAGE.md`. Concept coverage is a
candidate list, never evidence: reference-family ideas have lost games here.
**Implementation parity is forbidden.** Adopt the concept, derive the mechanism
yourself, write original Zig, choose your own values. Do not import tuned
constants, confidence assumptions tied to another evaluator, or trace targets.

Keep the numbered phase order in `GUIDE.md`. Later phases inform earlier work
but do not pull their mechanisms forward or bypass the evidence steps of the
open phase.

Correctness tests, code similarity, node reduction, depth, NPS and static loss
do not prove playing strength. Registered games decide playing changes;
diagnostics explain them. Do not infer safe pruning headroom from a low
re-search rate, unique work from overlapping inclusive counters, or game
strength from fixed-depth node savings.

A retained production-executable candidate requires the registered one-thread
SPRT its `PLAN.md` step specifies; that can include an exact speed
optimization. A candidate claiming behavior identity must reproduce the
accepted fingerprint, PV and results; a diagnosed legal deterministic mismatch
reclassifies it as a playing candidate rather than rejecting it for strength.
Documentation, tests and disabled diagnostics require no games.

For a coherent evaluation-strength candidate, evaluator throughput is a cost
diagnostic rather than an automatic refutation: stronger chess decisions may
justify slower evaluation, and representative time-controlled games measure
the net result. A pre-game cost veto requires an explicit operational or host-
budget derivation; never invent an Elo-equivalent speed threshold.

Promote a playing candidate only through representative time-controlled games
under the accepted clock policy. Prospectively select one time control and
thread scope for the claim and run one authoritative SPRT. Fixed-node games may
diagnose quality per node but never promote a candidate, and the same change
is not automatically re-gated at several time controls or thread counts.
H0, an exhausted cap and a maintainer-stopped inconclusive run do not promote;
none of them authorizes tuning, splicing, extending or an automatic retry.

Reaching a numbered phase does not automatically authorize SPSA. Propose it
only after the affected consumers freeze and evidence shows that a joint fit of
interacting continuous parameters is necessary and worth its game budget.

Prefer one independently meaningful idea per playing candidate. A cohesive
bundle is permitted only when its parts are semantically inseparable,
intermediate states are invalid or misleading, or the expected effects are
individually below the resolution affordable on the designated host. State one
mechanism-level hypothesis, exclude unrelated changes, preserve component
switches and run one final production SPRT. A passing bundle licenses the
bundle, not a claim that every component helped; use targeted,
value-of-information ablations rather than an exhaustive matrix.

Refusing to build a mechanism whose chess rationale, interactions or invariants
do not come out clean, or refuting an unmeasured assumption in `PLAN.md` or
`EXPERIMENTS.md`, is a deliverable of equal standing to a diff. Every refusal
must itself be falsifiable: state the exact invariant or defect and the
cheapest check that would settle it. Never soften a negative result or
manufacture a disagreement.

## Hosts, harnesses and shared tooling

The designated game-testing, tuning and final cross-engine comparison host is
the separate Ryzen 9 5950X, not the development workspace computer. Do not
start long jobs as a coding agent. Prepare exact candidate/baseline source and
binary identities, hashes, toolchain/options, a setup-only command, prospective
pair/game cap, qualified retained pair rate, expected and worst-case wall time,
storage estimate, checkpoint/resume path and stop rule for the maintainer to
run. Require the returned manifest, log, PGN and checkpoint before recording a
verdict. Do not overlap it with data generation or other timed work on that
machine. Measure only on an idle host (check CPU load and running engines,
harnesses or builds first), and never measure strength or NPS on a diagnostic
or tune build. Prove a guard or harness wire live before trusting a null from
it: a known-bad input must make it fail, and an absurd option value must move
the numbers.

A Zig minor or LLVM major upgrade is a speed change even at an identical
fingerprint and owes a controlled speed read before moving the pin; compiler
patch releases owe no games. No compiler step, a patch included, may fall
between an SPRT's arms unless explicitly declared.

Fit each gate to the change rather than copying the last template: size caps to
the expected drift or exposure, and record SPRT boundary estimates as
first-crossing estimates rather than unbiased effect sizes. Never extend or
counterfactually re-score a stopped SPRT.

The Rarog/Basilisk-derived fastchess SPRT harness, its 5950X placement, book,
time control and anomaly checks are battle-tested and trusted. Do not require a
pilot before an ordinary Manta SPRT while those boundaries are unchanged. Reuse
retained rate/storage evidence and proceed directly from a successful setup-only
check to the registered final SPRT. A pilot is warranted only when an
operational boundary changes and specifically needs qualification.

Measured games end only by the rules of chess. ADR-0071 removed adjudication
from every harness: no resignation threshold, no draw-after-N-moves rule, no
move cap, for SPRT, SPSA and data generation alike. Never reintroduce one, and
never propose an adjudication profile to make a run cheaper. That change is an
operational boundary change, so the instrument owes one identical-binary
calibration before the next registered candidate, and results measured before
it are not comparable with results measured after it.

Run gates the way Rarog runs them, because the harness is Rarog's. Register
the gate in `EXPERIMENTS.md` before any game with one verbatim `tools/sprt.ps1`
recipe that relies on the script's defaults (`3+0.03`, Hash 64, Threads 1,
physical cores minus two with affinity, UHO in random order, game end by the
rules of chess, 16,000-game cap) and names only what differs, then spell those
defaults out in the row so it reproduces without the script. Pick the bracket
by `-Mode`: `gainer` (`[3,10]`) to demand a material gain, `simplify`
(`[-5,0]`) for a non-regression or cleanup, `calibrate` for an identical-binary
null, `fixed -Games N` for a direction check or a diagnostic that decides
nothing. Explicit `-Elo0`/`-Elo1` are for a bracket the modes do not offer, and
the reason is written into the registration. Bounds, cap, book and game end
never change after games are seen. The maintainer launches every match; a
coding agent prepares arms, manifests and the recipe. Use the harness and SPSA
tooling that `EXPERIMENTS.md` and `PLAN.md` name as current. Do not substitute
a parked or unqualified harness silently.
`net_trainer` owns engine-agnostic NNUE data, training, export, format and
conformance tooling. Do not fork, vendor or independently reimplement
third-party shared tooling in Manta.

That rule governs shared tools and all third-party code. It does not govern
Basilisk and Rarog, which are the maintainer's own engines under the same
licence: their tooling may be copied into Manta and maintained here as
first-party code, with no vendoring contract and no upstream obligation. Where
both hold a version of the same tool, compare them and take the better one
rather than the nearer one. Everything else in this document still applies to
the result: it becomes Manta code, held to Manta's standards.

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
Every implemented search consumer shares the accepted evidence and depth
contract recorded in the owning ADR; do not add a private depth, ordering or
evaluation policy beside it.

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

Never update an expected value just to make a failure disappear, and never
relax a correctness test in the commit whose change made it fail. Determine
whether the implementation, the expectation or the underlying chess premise
is wrong; if a precondition was wrong, fix it in its own commit with justifying
evidence.

Passing tests is necessary, not sufficient. Ask whether the tested property is
meaningful for legal chess and for the goal of producing a stronger engine.

## Zig and architecture requirements

- Use Zig 0.17.1 until the latest-stable migration rule changes it; never use
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
- Comments in engine code briefly explain the chess or engineering invariant or
  problem, without narrating roadmap step numbers or earlier versions as the
  explanation.
- Preserve unrelated user work and keep public documentation concise.

## Evidence and completion

Run the gate appropriate to the change and its step as `PLAN.md` states it. A
completed step or ticket updates `PLAN.md` and `GUIDE.md`, including the
roadmap checkbox; update `REQUIREMENTS.md`, architecture/ADRs or
`EXPERIMENTS.md` when their contract or evidence changes. Record which gates
actually ran. Store concise evidence in `EXPERIMENTS.md`; raw artifacts stay
ignored. Report outcomes faithfully: a failed gate, a skipped check or an
unverified claim is stated as such, never smoothed over.
