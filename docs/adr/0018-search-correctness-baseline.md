# ADR-0018: Search correctness baseline

## Status

Accepted for Step 4.0 on 2026-08-10.

## Context

The first recursive search must establish chess and ownership semantics before
transposition tables, ordering heuristics, pruning, clocks or protocol
concurrency make failures harder to isolate. Static evaluation cannot decide
terminal or history-dependent outcomes, and a partial iteration cannot be
published as if it had completed. The baseline must also leave explicit
evidence categories for later speculative producers.

## Decision

- Use deterministic one-thread iterative deepening over allocation-free,
  caller-owned `ThreadState`. The root position is borrowed and restored; the
  evaluator and stop policy are concrete generic bindings selected outside
  recursion.
- Use alpha-beta/PVS for the main tree. Use quiescence that searches all legal
  evasions in check, and otherwise uses stand pat plus legal captures and
  promotions. Do not add TT, ordering histories, SEE filtering or pruning in
  this step.
- Search owns checkmate, stalemate, dead-position, rule-50 and repetition
  outcomes. Mate values encode ply distance from the root. Static HCE output
  remains ordinary non-terminal evidence.
- Represent a returned value with independent bound and producer provenance.
  Terminal, static evaluation, stand pat, qsearch move, PVS probe, full search
  and fallback are distinct; reduced, null, speculative and tablebase variants
  are reserved before those producers exist.
- Build each PV only from legal moves actually selected by recursive search.
  Terminal no-move roots publish no move. A drawable non-terminal root or an
  interrupted search retains the deterministic first legal root move when no
  completed iteration exists, explicitly tagged as non-authoritative fallback
  where applicable.
- Count one node for every entered main-search or qsearch invocation after the
  stop/limit check. Node limits are exact. An abort reverses the evaluator
  update and position transition on every active ply before returning.
- Publish only complete root iterations. An interrupted deeper iteration keeps
  the prior completed score, PV and best move while reporting current work and
  termination reason separately.

## Consequences

- Step 4.1 can add storage, ordering and diagnostics without redefining legal
  output, terminal ownership, evaluator restoration or result authority.
- The baseline intentionally makes no speed or strength claim. Generation
  order supplies deterministic tie-breaking but is not accepted move-ordering
  policy.
- UCI exactly-once publication, time limits, clocks and worker concurrency are
  still outside this component and remain owned by later steps.

## Verification

- `tests/search_baseline.zig` covers checkmate/stalemate, mate in one, dead and
  rule-50 roots, a true threefold history, legal PV replay and repeatability.
- Exact node interruption proves last-completed-iteration retention and root
  restoration; immediate stop proves legal fallback publication.
- A stateful independent evaluator double proves that every forward update is
  reversed when recursion aborts.
- Debug, ReleaseSafe and ReleaseFast tests plus native and portable builds
  exercise the fixed-storage implementation.
