# ADR-0035: Prospective node expectation and stable staged selection

## Status

Accepted as behavior-neutral Step 5.1.5.1 on 2026-08-14. Production remains
the exact MAN-S13 search policy; Step 5.1.5.2 may now build dynamic base LMR
against this substrate.

## Context

Manta previously transported only a `pv_node` boolean and fully stable-sorted
every generated move list before searching its first move. Later reduction,
history and selectivity work needs to distinguish a principal node from a
non-principal node expected to cut and one expected to fail low. It also needs
one move-selection boundary where TT, tactical, killer and history stages can
gain new evidence without duplicating a move across separately generated
phases.

Neither need is a playing hypothesis. Letting the new node label alter search
or letting staged selection change the accepted order would confound every
later candidate. Legality remains owned by move generation and TT validation;
ordering evidence must not acquire score, bound, terminal, draw or TT-store
authority.

## Decision

- Add `NodeExpectation` with `principal`, `cut` and `all` values. Negamax child
  context preserves a principal child only on a PV continuation and otherwise
  inverts cut/all expectation. Null, singular and ProbCut proof routes state
  their prospective child role explicitly.
- Carry expectation through main search, quiescence, outcome attribution and
  the caller-owned diagnostic sink. Derive the old PV boolean from
  `expectation.isPrincipal()` so there is one node-role source of truth.
- Give expectation no policy consumer in this step. Scores and typed returned
  bounds remain the only completed-outcome authority.
- Add an allocation-free `ordering.Picker` over one caller-owned `MoveList`.
  It ranks the initialized prefix once, selects the best remaining move on
  demand and stably extracts it into the consumed prefix. A strict comparison
  preserves generation order among equal ranks.
- Use the picker in main search, qsearch and ProbCut. TT is only one rank in the
  single generated list, so it cannot be emitted again by a later stage.
  Search without an ordering state retains generation order; the disabled
  observer also avoids unnecessary SEE/source classification.
- Keep the existing full-order APIs as compatibility drains of the same
  picker. A full drain is the accepted stable order; an early cutoff leaves an
  unneeded tail unordered without changing searched evidence.

## Consequences

The ordinary node path remains allocation-free and statically dispatched.
Move generation, legal checks, special-move encoding, make/unmake, terminal and
draw handling are unchanged. History remains worker-local. Later steps may
consume expectation or add new ranks only behind their own behavioral switch
and evidence gate.

The staged-selection property independently verifies one TT emission, stage
precedence, complete move-set emission and stable equal-rank order on a legal
root. Debug, ReleaseSafe and the observation disabled/active comparison retain
legal PV and restored-position contracts. The optimized depth-six production
fingerprint remains MAN-S13 `842,040` nodes.

The version-9 observation report adds node-expectation accounting without a
policy return channel. Two ReleaseSafe reports are byte-identical at SHA-256
`C6AC66C8714DB2D71DB8C34DA40AF2C33F80AE1FF8D91F2BDDDB934BAF88302B`.
Across the unchanged 140,391 nodes it records 5,915 principal, 90,670 cut and
43,806 all expectations. No game test is appropriate because search behavior
is identical by contract.

## Step 6.5.1 follow-up

The later exact staged-generation candidate was rejected on 2026-09-07.
Generating and ranking quiet moves only after tactical children allowed
descendant search to update worker-local main, reply and continuation histories
before the parent consumed them. The resulting move set was identical, but the
depth-six fingerprint changed from production `799,610` to `775,451`.

An eager control retained `799,610`. Forcing the staged prototype to generate
and rank its quiets before the first child also restored `799,610`, isolating
node-entry rank timing as the cause. That exact variant removed the intended
abandoned-tail saving and added stage overhead, so the prototype was removed.
The original initialized-prefix rank snapshot remains authoritative; no new
legality, score, bound, history or pruning authority was accepted.

That evidence rejects only the behavior-identical claim. Phase 6.5.1b now
reconstructs live-history staging as an explicit default-off playing candidate:
legal move membership and uniqueness remain fixed, while stage-time history may
change quiet ordering, PV and the fingerprint. The candidate uses exact
tactical and non-tactical-quiet generator subsets in one caller-owned bounded
list, retains eager root/check/exclusion paths and records stage work through
the existing observer boundary.

Deterministic qualification reproduces the diagnosed `775,451` depth-six
fingerprint, repeats with legal PV and restored state, and passes all twelve
fixed observation cohorts. The cohort records `79,446` staged nodes and
`56,539` quiet-stage entries: `22,907` completed nodes cut off without
generating quiets. A five-repeat development-host depth-six diagnostic measured
baseline/candidate median wall time `791/766 ms` and median NPS
`1,010,884/1,012,338`. Those results established correctness and a live
candidate, not strength or authoritative speed.

Registered remote 1T `MAN-S30` then accepted H1 after 8,752 games at
`+13.19 +/- 7.28` nElo, so live-history staging is accepted and default-on and
the production depth-six fingerprint is `775,451`. The promotion licenses the
staged picker as one mechanism; it does not attribute the gain to any single
stage, and the smaller tree remains a diagnostic rather than the evidence.
Turning `live_history_staging` off still reconstructs the superseded eager
picker at `799,610` for archived diagnostics, so every pre-6.5.1b recorded
fingerprint keeps a faithful reconstruction path. `EXPERIMENTS.md` records the
run's four completed time forfeits, the maintainer's explicit acceptance and
the reconstruction that attributes them to host scheduling pressure rather
than to clock policy.

## Traceability

Supports `FUNC-004` through `FUNC-006`, `SCORE-010`, `SCORE-015`, `PERF-006`,
`PERF-009`, `PERF-010`, `QUAL-013` through `QUAL-016` and Step 5.1.5.1 in
`PLAN.md`.
