# ADR-0060: Search-selectivity sensitivity pilot

## Status

Pilot accepted on 2026-08-25. It established sufficient live directional
signal to justify proposing a full five-coordinate tune, but promoted no
values. The full tune is not authorized and production remains exact
MAN-E19/MAN-S19.

## Context

Step 5.4.0 measured Manta's tree about `1.50x` wider per ply than the pinned
reference while `86.45%` of cutoffs occurred on the first searched move.
Ordering can explain only a minority of that gap. The engine already has the
major selectivity families, but several accepted margins consume the same
static-evaluation, window, depth and move-order evidence and can substitute for
one another. `MAN-S23` then showed that one hand-shaped LMR replacement failed
its prospective branching filter. Joint calibration is therefore plausible,
but a full tune is not yet earned.

SPSA may receive only numeric consumers active in production. The review
excluded `NullExtraMargin`, because dynamic null reduction is behind rejected
`main_selectivity_sync`, and `RazoringUnit`, because razoring is parked off.
Giving either a coordinate would let it random-walk on other parameters'
gradient while never changing a game.

## Decision

Add an immutable `search.params.Values` copied from the controller into each
search job. Ordinary builds use its accepted defaults and advertise no new UCI
options. An explicit `-Dtune=true` build advertises six spin options from the
same declarations that own their defaults and ranges:

| Option | Accepted default | Pilot range | Initial step | Existing consumer |
|---|---:|---:|---:|---|
| `ProbCutMargin` | 100 | 25–300 | 20 | tactical pre-verification threshold |
| `ReverseFutilityMargin` | 100 | 25–300 | 20 | depth-one static cutoff |
| `LateMoveDepthScale` | 2 | 1–6 | 2 | shallow late-move count threshold |
| `QuietFutilityUnit` | 100 | 25–300 | 20 | shallow quiet futility margin |
| `SeePruningUnit` | 100 | 25–300 | 20 | main-search capture SEE threshold |
| `QsearchDeltaCushion` | 100 | 25–300 | 20 | non-losing qsearch capture cushion |

These values change only selectivity. Legal move generation, check/evasion,
PV, first-move, promotion, terminal, draw/history, mate-score, ordinary-score,
bound/provenance, TT authority, zugzwang and special-move guards remain fixed.
The job takes a value copy before its worker starts; recursive nodes read that
immutable copy without allocation, I/O, locks, atomics or runtime indirection.

The registered `MAN-S26` pilot is 128 SPSA iterations with 32 games each:
exactly 4,096 games at 1T `3+0.03`, Hash 64 MiB, paired UHO openings and 14
concurrent games on the designated Ryzen 9 5950X. The complete iteration-128
theta is the only estimator; no intermediate checkpoint may be selected. The
recent MAN-S25/MAN-E21 host rate predicts about 37 minutes; the reserved
worst-case allowance is 60 minutes and 16 MiB. State is saved every ten
iterations and may resume only to the registered iteration 128.

## Evidence gate

Before launch:

- Debug and ReleaseSafe tests pass with tune mode on;
- production and tune-default depth-six bench fingerprints are both `724,563`;
- production advertises none of the six options, while the tune binary
  advertises all six with matching defaults/ranges;
- strict parsing rejects invalid and out-of-range values;
- focused searches or the frozen observation corpus establish a live consumer
  for every coordinate; and
- `tools/spsa.ps1 -SetupOnly` validates the binary, config, integer
  perturbation lifetime, affinity, schedule, book and checkpoint manifest
  without starting games.

The pilot does not tune or promote Manta. It authorizes a full SPSA proposal
only if all coordinates remain perturbed through iteration 128 and the logged
trajectory shows stable directional movement rather than inactivity,
contradictory oscillation or rail pinning. Otherwise Step 5.4.5 closes without
a tune. Any full run needs a new explicit maintainer approval with its horizon,
game count, wall time and stop rule. A resulting final theta would still be
only a candidate for Step 5.4.6's clean bake and one registered SPRT.

## Consequences

Production chess behavior and its public UCI registry remain unchanged. Tune
builds gain a narrow experimental boundary whose defaults are production
equivalent. No categorical switch, evaluation coefficient, rejected mechanism
or time-management value enters the pilot.

## Pilot result

The registered run stopped cleanly at 128 iterations/4,096 games, averaging
26.92 seconds per iteration and 0.84 seconds per game (about 57 minutes total,
inside the 60-minute allowance). The PGN holds exactly 4,096 complete games;
the log contains no timeout, time forfeit, illegal move, crash, disconnect,
affinity failure, invalid option or infrastructure error.

The floating final state and movement from accepted defaults are:

| Coordinate | Final | Movement | Disposition |
|---|---:|---:|---|
| `ProbCutMargin` | 96.45 | -3.55 | retain for a full proposal |
| `ReverseFutilityMargin` | 97.99 | -2.01 | retain for a full proposal |
| `LateMoveDepthScale` | 3.31 | +1.31 | strongest persistent movement; retain |
| `QuietFutilityUnit` | 99.97 | -0.03 | returned to its seed; exclude as noise-only |
| `SeePruningUnit` | 97.97 | -2.03 | retain for a full proposal |
| `QsearchDeltaCushion` | 104.69 | +4.69 | persistent movement; retain |

No coordinate approached a rail. Quarter checkpoints show persistent movement
for late-move depth scale and qsearch delta, a modest downward direction for
ProbCut/reverse-futility/SEE, and quiet futility wandering back to its exact
seed. This passes the prospective sensitivity gate while giving no strength or
convergence claim. The pilot theta must not be baked or tested as a candidate.

SHA-256s: state
`821D8B1A3C28BBE1151E033A01123F5A8D09E554CF7B5F39BA531B485AECECA5`,
log `9E337D1A4E999BEA0BB6C353657645A41820EE011441F92BE235CACFCDB166A5`,
PGN `59CABACA5363E6C17E21A26A699FF4CAC9E695C3B6A0F294DB80D954CC5CC3BE`
and run manifest
`6D01BC074B002A4033A8CE177127FCAD359D55ACA2D0C97AF052D3CC5F3DC915`.

A prospective full run should start again from accepted defaults, omit quiet
futility, use the complete final theta only and receive its own explicit
maintainer approval, horizon, game/storage budget and stop rule.
