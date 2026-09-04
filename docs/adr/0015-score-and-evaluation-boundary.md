# ADR-0015: Score bands and statically bound evaluation

- Status: Accepted
- Date: 2026-08-10

## Context

Phase 3 needs one search-facing score domain that cannot confuse static
evaluation with mate, future tablebase proof, bounds or the `NONE` sentinel.
It also needs a replaceable HCE/NNUE seam without committing the recursive hot
path to runtime dispatch, evaluator-owned position fields or diagnostic cost.
Legal promotions can exceed the nominal opening material phase, and make and
unmake consume the same factual child-state move delta in opposite directions.

## Decision

- `Score` is a four-byte strong type over the signed 32-bit search domain.
  Search units are centipawns: 100 units approximate one pawn. An evaluator
  with another internal scale converts explicitly at its boundary.
- Mate magnitudes occupy 31,744 through 32,000. Magnitudes 31,488 through
  31,743 are reserved for future tablebase values, one value per supported
  search ply. Ordinary evaluation is limited to magnitude 31,487.
- `INFINITY` remains a search bound at 32,001 and `NONE` remains a sentinel at
  32,002. The strong type prevents ordinary integer arithmetic on either value;
  checked operations reject `NONE` and invalid encodings.
- Static evaluation is from the side-to-move perspective. Search, not the
  evaluator, owns checkmate, stalemate, repetition, rule-50/rule-75 and future
  tablebase outcomes and their provenance.
- The evaluator structural contract exposes concrete `State` and `TraceEntry`
  types plus `refresh`, directional `update` and `evaluate`. Search binds the
  evaluator and trace sink at compile time. A runtime evaluator choice may
  switch only outside recursive search.
- Forward and backward updates consume the child state's factual `MoveDelta`;
  the supplied position is always the post-transition position. Null moves
  have an empty piece delta, while the position still supplies the changed
  side-to-move perspective.
- Tapered interpolation is a convex middlegame/endgame blend with signed
  truncation toward zero. Phase above its nominal opening total is clamped so
  legal promotions cannot extrapolate beyond the opening endpoint.
- Diagnostic traces use evaluator-defined entries and a bounded caller-owned
  sink. The production disabled sink is zero-sized and selected at compile
  time; evaluation results are identical with tracing enabled or disabled.

## Consequences

- HCE and future NNUE implementations share one evaluator-independent search
  API while retaining concrete evaluator-local state and scalar reference
  implementations.
- Decisive proof cannot be manufactured by a large static evaluation, and UCI
  cp conversion rejects decisive and sentinel values.
- Trace capacity is explicit and allocation-free. Overflow truncates
  diagnostics without changing evaluation or adding a hot-path error.
- Phase 4 still owns mate presentation, score provenance, TT normalization and
  terminal-search behavior. Phase 5 still owns actual tablebase integration.

## Verification

- Score tests cover exact bands, mate distance, invalid/sentinel rejection and
  signed evaluator-scale conversion.
- Phase properties cover endpoints, color antisymmetry and promotion clamping.
- Structural-contract tests reject incomplete evaluators and instantiate the
  same scalar evaluator with disabled and bounded trace sinks.
- Forward/backward update tests exercise the maximum three-piece promotion
  capture delta and restore evaluator test state.
- ReleaseFast assembly has no evaluator/binding code symbol or call target
  outside debug metadata for the statically bound scalar probe.
- ZLint, all three test modes and native/portable builds cover the boundary.

## Traceability

Supports `SCORE-001`–`SCORE-005`, `SCORE-008`, `PERF-001`, `PERF-004`,
`QUAL-011`, `QUAL-012` and Phase 3 Step 3.0.
