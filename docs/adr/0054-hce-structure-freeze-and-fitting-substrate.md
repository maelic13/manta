# ADR-0054: Freeze HCE structure and fit only its linear coefficient surface

## Status

Accepted for Step 5.3.15 on 2026-08-21. Parameter values remain unfrozen and
the fitted evaluator is not promoted until Step 5.3.16.

## Context

The aggregated evaluator trace can explain residuals but cannot fit a model:
it reports a cluster score without reporting how often each coefficient
applied. The completed structure also contains genuinely nonlinear mechanisms
whose values cannot be represented honestly as fixed linear feature counts.

## Decision

- Freeze the producer, transformation and consumer map in
  `docs/HCE_STRUCTURE.md`. Later coefficient changes are allowed; new terms or
  changed ownership require a new prospective decision.
- Derive schema v1 from every committed Zig parameter declaration. Flatten
  arrays in source order and classify each scalar as free, structurally fixed
  or excluded. Binary switches are not parameters.
- Fit the 1,092 honest linear coefficients. Preserve 19 fixed values and name
  but exclude 95 nonlinear, independently truncated, specialized or archived
  values. In particular, squared king danger, capped winnability and exact
  endgame dispatch do not receive a false linear gradient.
- Emit sparse per-coefficient count events from the production fact paths.
  Sinks without the fitting method compile every event away.
- Carry the excluded/post-processing contribution as a fixed per-position
  residual. Require exact dot products for fully linear trace components so
  this residual cannot conceal missing free features, then require exact final
  reconstruction on conformance and randomized legal positions.
- Include MAN-E07's four linear imbalance pairs in the free surface. Extraction
  enables that prospective block while anchoring the residual to production;
  the binary switch remains outside the vector and is decided only by the
  registered post-fit ablation.
- Generate a checked fitted vector back into `hce_params.zig`. No runtime
  sidecar, parsing, allocation or indirection enters the engine.

## Consequences

The current catalog has 121 groups and 1,206 coefficients: 1,092 free, 19
fixed and 95 excluded. Source round-trip is byte exact at the current vector.
Component dots and complete scores reproduce on the frozen reference corpus
and a deterministic 96-ply legal random walk. Normal search fingerprints stay
unchanged because production sinks erase recording at comptime.

The fit cannot claim to calibrate excluded nonlinear subsystems. That is an
honest limitation and a safer contract than optimizing a linear surrogate the
engine does not play. Step 5.3.16 remains responsible for data provenance,
quiet filtering, train/validation separation, optimization, baking, residual
validation, the imbalance ablation and the registered game gate.

## Traceability

- `PLAN.md` 5.3.15; `docs/HCE_STRUCTURE.md`; `docs/HCE_FITTING.md`.
- `src/eval/fit.zig`, `src/eval/hce.zig`, `src/eval/hce_params.zig`,
  `tools/hce_fit.zig`, `build.zig`.
- ADR-0050, ADR-0051, `QUAL-015`, `PERF-002`, `PERF-006`.
