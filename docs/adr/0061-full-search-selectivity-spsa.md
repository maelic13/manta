# ADR-0061: Full search-selectivity SPSA

## Status

Withdrawn unrun on 2026-08-25 and superseded by ADR-0062. The parameter audit
that followed registration found high-activity production consumers absent
from this five-coordinate set. No MAN-S27 game ran and it grants no tuning or
playing authority. Production remains exact MAN-E19/MAN-S19.

## Context

`MAN-S26` established live, coherent sensitivity in five interacting search
coordinates. Late-move depth scale and qsearch delta moved most persistently;
ProbCut, reverse futility and SEE showed smaller compatible movement. Quiet
futility returned to its seed and is excluded. Because these consumers jointly
shape the same tree, testing hand-picked values separately would not estimate
their interaction.

The full horizon is 5,000 rather than 2,000 iterations. Two thousand would be
the cost-efficient choice and would likely find the main direction. Five
thousand provides more averaging of game noise and more time for the decreasing
gain schedule to settle. That benefit has diminishing returns and cannot
guarantee Elo, but it better serves the maintainer's stated priority of maximum
plausible strength.

## Decision

Register `MAN-S27` from accepted production defaults, not the pilot theta:

| Option | Start | Range | SPSA step | Search consumer |
|---|---:|---:|---:|---|
| `ProbCutMargin` | 100 | 25–300 | 20 | tactical pre-verification threshold |
| `ReverseFutilityMargin` | 100 | 25–300 | 20 | depth-one static cutoff |
| `LateMoveDepthScale` | 2 | 1–6 | 2 | shallow late-move count threshold |
| `SeePruningUnit` | 100 | 25–300 | 20 | main-search capture SEE threshold |
| `QsearchDeltaCushion` | 100 | 25–300 | 20 | non-losing qsearch capture cushion |

`QuietFutilityUnit` stays at its accepted value 100 and is not emitted by the
tuner. No categorical switch, evaluation coefficient, dormant consumer or
time-management option enters the run.

The registered run is 5,000 iterations × 32 games = 160,000 games at 1T
`3+0.03`, Hash 64 MiB, paired UHO openings and concurrency 14 on the designated
Ryzen 9 5950X. The pilot's measured 26.92 seconds/iteration predicts 37.39
hours. Reserve 45 hours and 550 MiB, and do not overlap another timed workload.

The horizon-matched schedule is `alpha = 0.601`, `gamma = 0.102`, `A = 500`,
`c = 1.0`, end learning rate `0.0031`, and serialized derived gain
`a = 0.09655`. At iteration 5,000 the perturbation multiplier is about
`0.419474`: about 8.39 centipawns for each margin coordinate and 0.839 for the
integer late-move scale. Thus every coordinate remains measurably perturbed at
the registered endpoint.

State is checkpointed every ten iterations and may resume only toward the
registered iteration 5,000. The complete iteration-5,000 theta is the only
estimator; do not select an intermediate checkpoint. Operational reviews near
iterations 1,000, 2,500 and 4,000 may detect a broken run but have no candidate
selection authority. Stop and report option/config/hash/manifest mismatch,
state corruption, game or placement anomalies, or sustained rail pinning that
shows the registered range is invalid.

## Evidence gate

Before launch, a clean tune executable must reproduce fingerprint `724,563`,
advertise the five registered options with exact defaults/ranges, and pass the
setup-only schedule, book, affinity, integer-perturbation and manifest checks.
The repository must be clean and the manifest must bind the exact executable,
configuration and source revision.

Completion of SPSA produces only a proposed vector. Step 5.4.6 must round and
bake the final theta into one clean candidate, requalify its deterministic
behavior and run one registered 1T `3+0.03` SPRT against untuned production.
Only that game gate can promote the fitted values.

## Consequences

The longer horizon spends about 2.5 times the games of the 2,000-iteration
alternative for improved convergence confidence, not a promised proportional
strength gain. Production behavior and public UCI options remain unchanged
until and unless the baked candidate wins its post-fit SPRT.

This remains the historical record of the unlaunched maximum-horizon proposal.
ADR-0062 owns the replacement parameter set, horizon and staged stop contract.
