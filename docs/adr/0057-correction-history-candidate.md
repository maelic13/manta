# ADR-0057: Bounded pawn-structure correction-history candidate

## Status

Rejected by its registered one-thread SPRT on 2026-08-24 after passing the
Step-5.4.1 design and deterministic producer gate. `MAN-S25` remains archived
default-off and exact MAN-S19 remains production.

## Context

The frozen HCE residual corpus shows that searched ordinary values repeatedly
depart from raw evaluation by much more than noise. The 5.4.0 coverage audit
identified correction history as the one missing search/evaluator relation
owned before Phase 6. ADR-0034 requires its producer to prove bounded,
populated semantics before correction can control pruning or reduction.

The first implementation accidentally placed the corrected value in the
two-ply `improving` stack while qsearch stand pat continued to use uncorrected
pruning evaluation. That made selectivity the effective consumer and left the
declared evaluation consumer unwired. Default builds also failed to instantiate
the candidate generic, allowing an unrelated field-access error to survive the
ordinary suite. Both defects are part of the evidence for this boundary.

## Decision

- Keep one fixed worker-local table with 16,384 slots per side, indexed by the
  existing pawn Zobrist key. Pawn structure changes slowly enough to identify a
  recurring evaluation class; side to move separates opposite tempo and
  perspective effects. Collisions age toward the combined observed residual
  rather than acquiring position or score authority.
- Store a signed fixed-point exponential moving average. Depth supplies bounded
  update weight; the applied correction is capped at 48 centipawns and the
  resulting score remains inside the ordinary band.
- Train only from known non-check, non-exclusion main-search evidence at
  positive depth. Exact results authorize either direction. A lower bound
  trains only when above raw HCE; an upper bound only when below it. Draw,
  terminal, mate/tablebase, depth-zero and aborted paths contribute nothing.
  Reduced-provenance fail-lows and fail-lows that skipped shallow-pruned
  siblings do not carry nominal-depth upper-bound authority and cannot train.
- Preserve raw HCE as TT static storage and as the source of two-ply improving,
  pruning evaluation and all pruning/reduction margins. Qsearch stand pat is
  the sole Step-5.4.1 correction consumer. Accepted MAN-S19 TT refinement is
  applied independently in its proven direction to both the raw pruning value
  and the corrected stand-pat value.
- Compile the candidate path in the ordinary optimized suite. Diagnostic
  observers record lookups, bound/direction populations and pre-update exact
  residuals; a post-search scan reports occupied signs and cap pressure without
  adding work to the node path.

## Deterministic evidence

The 18-position residual cohort starts each arm with a clear TT and ordering
state. For each exact update it compares the result against raw HCE and against
the correction available **before** that result is learned. Lower and upper
bounds count population but do not enter the two-sided absolute-error claim.

`MAN-S25` produced 141,868 lookups, 40,464 nonzero lookups, 762 exact samples,
12,225 lower-bound updates and 1,266 upper-bound updates. Across independently
reset searches, 1,711 slots populated (`1,591` positive, `120` negative), no slot reached the
near-cap band, and the largest applied correction was 46 cp. Exact aggregate
absolute residual fell from 55,349 to 54,269, a 1.95 percent improvement.
Candidate nodes fell from 380,457 to 373,812, 1.74 percent; that is diagnostic
tree-shape evidence, not speed or strength. The depth-six candidate fingerprint
is 760,161 versus production 724,563. Production remains unchanged.

This accepts the bounded producer and isolated evaluation consumer for a game
gate. It does not accept the feature into production, its constants
individually, or any correction-controlled pruning/reduction consumer.

## Game evidence

The registered candidate-as-A 1T `3+0.03`, Hash-64, concurrency-14 normalized
`[3,10]` SPRT accepted H0 after 5,958 games/2,979 complete pairs in 53m40s:
1,535 wins, 1,559 losses and 2,864 draws, pentanomial
`[162, 744, 1201, 700, 172]`, `-2.05 +/- 8.82` nElo
(`-1.40 +/- 6.03` Elo), LLR `-2.95` and LOS `32.45%`.

Independent reconstruction of the PGN reproduces the complete-pair totals and
pentanomial exactly. The PGN also contains two normal completed games whose
partners were still in flight at the boundary; they are unpaired and excluded
from the authoritative statistic. All 5,958 scored games use the registered
time control, their terminations are normal chess or adjudication, and the
checked logs contain no timeout, crash, illegal-move, disconnect, forfeit,
affinity or other recorded infrastructure anomaly. Compiler-equal clean native
binaries match their hash-bound sidecars and the bridge manifest.

## Consequences

`MAN-S25` accepted H0, so the switch stays off and this mechanism closes without
a constant retune. Deterministic residual improvement established that the
producer was well formed; it did not establish playing value. The rejected
result grants no correction-controlled selectivity consumer or Step-5.4.2
compatibility trigger.

The checked `-Dcorrection-history=true` build option selects the candidate at
comptime; the ordinary build selects exact production. `tools/build_test.ps1`
records that switch, compiler, source tree, binary hash and bench fingerprint
in each sidecar. The registered playing seed was `1475838799`.

The run used the designated Ryzen 9 5950X profile: 14 concurrent one-thread
games on explicit physical CPUs with two cores reserved, Hash 64 MiB, paired
randomized UHO, strength-v1 adjudication, normalized `[3,10]`, alpha/beta 0.05
and a 12,000-game/6,000-pair cap. It stopped normally at the H0 boundary.
Artifacts remain below `zig-out/fastchess/MAN-S25-sprt-20260824_065924`.

The archived table is cleared with the worker ordering state, allocated nowhere
in the node path and remains private to one worker when explicitly enabled.

## Traceability

- `REQUIREMENTS.md` `SCORE-020`, `SCORE-023`.
- `PLAN.md` 5.4.1; `EXPERIMENTS.md` `MAN-S25`.
- `src/search/baseline.zig`, `src/search/ordering.zig`,
  `src/search/diagnostics.zig`.
- `tools/eval_residual.zig`, `tests/bench_qualification.zig`.
- ADR-0034 and ADR-0040.
