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

## Traceability

Supports `FUNC-004` through `FUNC-006`, `SCORE-010`, `SCORE-015`, `PERF-006`,
`PERF-009`, `PERF-010`, `QUAL-013` through `QUAL-016` and Step 5.1.5.1 in
`PLAN.md`.
