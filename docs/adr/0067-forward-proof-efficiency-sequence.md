# ADR-0067: Forward-proof efficiency candidate sequence

## Status

Accepted as the Step-6.5.5 sequencing and authority contract. `MAN-S32` is a
qualified default-off below-resolution component. `MAN-S33` is implemented,
locally qualified and prospectively registered for one remote-host 1T SPRT.

## Context

Step 6.5.2 found three independent forward-proof costs: mate-band searches
dominated by a few proven-mate positions, a depth-minus-two singular exclusion
probe covering `5.1%` of the depth-ten tree, and null probes whose same-depth
mandatory verification confirms `99.91%` of fail-highs. A shared theme does not
make the mechanisms mutually dependent. `QUAL-017` permits a bundle only after
each component is shown individually below affordable resolution or when an
intermediate state is invalid.

## Decision

- Retain `MAN-S32` mate-distance pruning default-off. Its ordinary-position
  effect is below standalone SPRT resolution, so it waits for a compatible
  independently measured below-resolution component.
- Test `MAN-S33` singular-exclusion horizon independently. It replaces only
  the exclusion search's `depth - 2` horizon with `ceil(depth / 2)`, retaining
  at least three plies at the first eligible depth. The legal ordinary TT move,
  threshold, exact excluded move, disabled-null route and searched fail-low
  requirement remain authoritative.
- Test deeper null reduction and verification scope later as one coupled
  candidate with separate switches. A deeper reduction without a safety policy
  and a verification policy without the deeper probe are misleading
  intermediate states. That candidate must supersede the relevant parts of
  ADR-0022 and `SCORE-021` prospectively before implementation.
- After Step 6.5.4 freezes prospective reduced depth, test LMP/futility/SEE
  consumption and ProbCut changes independently. Every idea receives an
  explicit accepted, rejected or parked verdict before Step 6.5.5 closes.

## MAN-S33 mechanism and consequences

The TT supplies a legality-validated ordinary lower/exact move, score, bound,
depth and provenance. Search derives the singular threshold, installs that one
move as worker-local excluded state and searches the unchanged position. Only
an upper-bound result below the threshold extends the TT move. The candidate
changes the probe horizon, so extension decisions, tree shape, cache traffic
and final play may change; no score, bound, PV, TT, terminal, draw, history or
legality authority changes.

Castling, en-passant and promotion remain ordinary legal alternatives. Search
draw and terminal precedence still run before selectivity. Cancellation
restores the excluded-move marker, PV length, evaluator and board. The hot path
adds no allocation, I/O, lock, formatting or shared atomic, and every worker
uses the same compile-time policy over worker-local state.

The qualified 64-MiB depth curve is:

| Depth | Production | MAN-S33 | Change |
|---:|---:|---:|---:|
| 4 | 149,063 | 149,063 | 0.00% |
| 6 | 782,298 | 778,777 | -0.45% |
| 8 | 4,424,221 | 4,217,596 | -4.67% |
| 10 | 26,778,901 | 24,335,279 | -9.13% |

At depth ten all forty positions change: 25 shrink and 15 grow. Attempts move
from `3,009` to `2,853`, extensions from `285` to `266`, and conversion from
`9.47%` to `9.32%`. The ordinary depth-six bench fingerprint is `773,779`
against production `775,451`. This breadth makes MAN-S33 an independent
playing candidate; node reduction and retained conversion diagnose it but do
not prove strength.

## Verification and promotion

Focused tests cover the bounded monotonic horizon, a seeded legal TT producer,
exclusion-only TT authority, legal PV, completed nominal depth and restored
state. Debug, ReleaseSafe and ReleaseFast suites pass, including all 24 UCI
process cases. Format, lint and policy pass. Two normalized ReleaseSafe
observer reports are byte-identical at SHA-256
`6EE371BCBA84E224BE328EB936AF7ACF43C896189AC4C9AC5238CA5BB415338A`.

## Prospective playing registration

- Candidate A is MAN-S33 with `singular_exclusion_horizon=true`; baseline B is
  exact production MAN-S30 with the switch false. Mate-distance pruning and
  every other default-off candidate remain off in both arms.
- Both arms use the same frozen source, Zig 0.16.0, native ReleaseFast,
  non-PGO, non-tune builds with MAN-E19, MAN-S29 parameters, MAN-T05 clock and
  MAN-S30 staging.
- Use the checked `tools/step_5_1_fastchess.ps1` bridge, `strength-v2`, paired
  randomized UHO, 1T, Hash 64 MiB, concurrency 14 on 14 physical cores,
  `3+0.03`, the existing 20 ms controller margin and `Move Overhead=10`.
- Normalized `[1,5]`, alpha/beta 0.05, seed `1844484847`, maximum 8,000 pairs /
  16,000 games. Stop at H1, H0, cap, anomaly or 3.5 hours. Only clean H1
  promotes; H0 or cap leaves production unchanged without automatic retry.
- Zero timeout, crash, disconnect, illegal-move, affinity, incomplete-score or
  nonzero-exit anomalies. Prior post-result timeout waivers do not alter this
  prospective gate.
- The operational boundary is unchanged, so no pilot is required. Reserve
  1 GiB for artifacts under `zig-out/fastchess/MAN-S33-*`. The bridge has no
  pair-atomic checkpoint/resume; preserve interrupted output as incomplete and
  never splice runs.
- Return source identity, both binary manifests and hashes, runner/book hashes,
  setup-only output, final manifest/logs/PGN and explicit absent-checkpoint
  status before recording a verdict.

From frozen source on the idle designated 5950X, build both arms:

```powershell
./tools/build_test.ps1 -Suffix MAN-S33-base
./tools/build_test.ps1 -Suffix MAN-S33-candidate -SingularExclusionHorizon
```

Setup only; this starts no engine or game:

```powershell
./tools/step_5_1_fastchess.ps1 -Job sprt -RunId MAN-S33 -Candidate ./tools/test_engines/manta-MAN-S33-candidate.exe -Baseline ./tools/test_engines/manta-MAN-S33-base.exe -CandidateName MAN-S33 -BaselineName MAN-S30 -SprtSeed 1844484847 -SprtElo0 1 -SprtElo1 5 -MaxGames 16000 -DryRun
```

The registered final command is identical without `-DryRun`. Do not overlap
it with datagen, tuning or other timed work.

The development-workspace dry-run was correctly rejected before either engine
started because the bridge detected the Intel development CPU instead of the
required Ryzen 9 5950X. Setup validation therefore remains a designated-host
handoff item, not a local anomaly or permission to weaken the host guard.

## Traceability

Supports `FUNC-004` through `FUNC-006`, `SCORE-003`, `SCORE-004`, `SCORE-010`,
`SCORE-011`, `PERF-006`, `PERF-009`, `PERF-010` and `QUAL-013` through
`QUAL-017`; PLAN Step 6.5.5.
