# ADR-0062: Complete production-search SPSA with a staged stop

## Status

Completed cleanly on 2026-08-26 at the registered 2,000-iteration horizon.
The final theta is tuning evidence only; production remains exact
MAN-E19/MAN-S19 until the separately registered MAN-S29 game gate decides it.

## Context

MAN-S26 proved that game-based SPSA has usable signal in five continuous search
consumers and that quiet futility did not. The first full proposal, MAN-S27,
covered only those pilot coordinates. A whole-search audit then found three
high-activity parameter classes omitted from that proposal: base LMR magnitude,
late-move-count shape, and accepted reply/continuation ordering weights. On the
fixed deep observation, LMR reduced 19,868 moves and researched 593; late-move
pruning rejected 723,567 of 895,805 eligible candidates; reply evidence was
nonzero 757,312 times, and distance-2/4/6 continuation evidence was nonzero
522,276/761,511/722,364 times. These are live, interacting consumers of the
same tree and belong in the joint fit.

More iterations reduce stochastic error only with diminishing returns. On the
usual inverse-square-root approximation, 5,000 iterations has about 37% less
sampling error than 2,000, but costs 2.5 times as many games. There is no basis
for claiming that the extra 96,000 games are worth ten Elo, or any fixed Elo.
Two thousand is therefore the shortest defensible full horizon for ten jointly
perturbed coordinates. The requested “about 95% of value” is a practical
diminishing-returns target, not a measurable confidence guarantee.

## Decision

Withdraw unrun MAN-S27 and register `MAN-S28` from accepted defaults:

| Option | Start | Range | Step | Consumer |
|---|---:|---:|---:|---|
| `ProbCutMargin` | 100 | 25–300 | 20 | tactical pre-verification threshold |
| `ReverseFutilityMargin` | 100 | 25–300 | 20 | depth-one static cutoff |
| `LmrExtraScale` | 100 | 50–200 | 50 | evidence-derived LMR plies, excluding its one-ply floor |
| `LateMoveBase` | 3 | 1–8 | 2 | base quiet move-count allowance |
| `LateMoveDepthScale` | 2 | 0–6 | 2 | depth contribution to that allowance |
| `LateMoveImprovingBonus` | 2 | 0–6 | 2 | extra allowance when evaluation improves |
| `SeePruningUnit` | 100 | 25–300 | 20 | main-search capture SEE threshold |
| `QsearchDeltaCushion` | 100 | 25–300 | 20 | non-losing qsearch capture cushion |
| `ReplyHistoryWeight` | 100 | 0–200 | 25 | accepted one-ply reply-ordering evidence |
| `ContinuationHistoryWeight` | 100 | 0–200 | 25 | shared distance-2/4/6 continuation-ordering evidence |

The main quiet-history scale remains the reference 100. One shared continuation
weight avoids fitting three correlated views of the same table. Quiet futility
is excluded by the pilot. Fixed/discrete null-move, ProbCut, IIR, extension and
singular depths are excluded; singular evidence is also sparse. Rule constants,
objective SEE zero, HCE values, time management, default-off/rejected branches
and categorical switches are not SPSA coordinates.

The registered horizon is 2,000 iterations x 32 games = 64,000 games at 1T
`3+0.03`, Hash 64 MiB, paired UHO openings and concurrency 14 on the designated
Ryzen 9 5950X. MAN-S26's measured 26.92 seconds/iteration predicts 14.96 hours;
reserve 20 hours and 300 MiB and run no overlapping timed workload.

The horizon schedule is `alpha = 0.601`, `gamma = 0.102`, `A = 200`, `c = 1`,
end learning rate `0.0031`, and serialized derived gain `a = 0.06710`. At
iteration 2,000 the perturbation multiplier is about 0.46057: step-2 integer
coordinates still perturb by about 0.921 and therefore remain live after
rounding.

The run is staged without changing that schedule. Its first invocation stops
at absolute iteration 128 (4,096 games, about 57 minutes). That checkpoint is
for activity, trajectory, anomaly and range review, not parameter selection.
If coherent, the same state resumes toward iteration 2,000; it is never restarted
from the checkpoint theta. The launcher stores every ten iterations, appends
the log, preserves the original horizon in the manifest, and separates
`StopAfter` from `Iterations`. Ctrl-C may stop any session; relaunching the same
command resumes toward the same absolute stop. Only iteration-2,000 theta is an
estimator.

## Run evidence

The staged run resumed the same state after its iteration-128 review and
completed exactly 2,000 iterations/64,000 games at 27.16 seconds per iteration
and 0.85 seconds per game. Every coordinate received 4,000 perturbed option
assignments, none approached a range rail, and the 64,000 PGN events match the
64,000 completed-game log records. The ending inventory is 29,366 threefold
draws, 17,248 white adjudications, 15,072 black adjudications, 1,307
insufficient-material draws, 905 draw adjudications, 48 stalemates, 31
fifty-move draws and 23 checkmates. A zero-hit anomaly scan covered timeout,
forfeit, disconnect, illegal move, crash, exception, option and termination
failures.

The complete floating theta and its prospectively nearest-integer bake are:

| Option | Floating theta | MAN-S29 integer |
|---|---:|---:|
| `ProbCutMargin` | 102.837129953 | 103 |
| `ReverseFutilityMargin` | 68.219123899 | 68 |
| `LmrExtraScale` | 115.576951140 | 116 |
| `LateMoveBase` | 3.814528172 | 4 |
| `LateMoveDepthScale` | 2.962735580 | 3 |
| `LateMoveImprovingBonus` | 3.507625112 | 4 |
| `SeePruningUnit` | 106.525305020 | 107 |
| `QsearchDeltaCushion` | 122.126273080 | 122 |
| `ReplyHistoryWeight` | 115.508984763 | 116 |
| `ContinuationHistoryWeight` | 117.752396011 | 118 |

The console's resumed-run parenthetical deltas used the iteration-128 theta as
their display origin. The serialized theta above is authoritative; this was a
presentation artifact and did not alter perturbations, gradients or state.
SHA-256 evidence: state
`080E1F9B5B402ABEA959EF30C376233C5E808A3C0988F5BFCA04CB314E748AFC`,
log `935CAD8510EC45575999D3BF3666CD0FEC450A18561CA8FB87C81D14C7E7E583`,
PGN `FBC12DCC1452F153B2EF6351C98496037E92DE5609A0A1D088A73514B5876A0F`
and run manifest
`C44F81C7C0BE5B98DD7F7012415308A027FA8B439026AE90C2C730158C97C219`.

## Evidence gate

Before launch, Debug and ReleaseSafe tune tests, policy checks, and the clean
tune-default fingerprint must pass. Setup must bind the clean revision, exact
binary/config/book/runner hashes, ten advertised options, 2,000-iteration
schedule, and 128-iteration first stop. Stop and report an option/config/hash/
manifest mismatch, corrupt state, placement or game anomaly, inactive added
coordinate, or sustained rail pinning.

Completion produced only the proposed vector above. ADR-0063 owns its clean
MAN-S29 bake and one registered 1T `3+0.03` SPRT against untuned production.
Games alone decide whether the changed tree is stronger at the target clock.

## Consequences

Production and ordinary public UCI remain unchanged. Tune builds gain five
default-equivalent controls. MAN-S28 spends 40% of MAN-S27's game budget while
covering the important active continuous search surface more completely; this
is an efficiency judgment, not a promise of 95% of an unknown Elo optimum.
