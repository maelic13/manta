# HCE benchmark contract

`manta-hce-bench-v2` is descriptive throughput evidence for Manta's scalar,
full-refresh bootstrap evaluator. It is not a playing-strength test and does
not compare evaluator quality.

## Frozen corpus and work

| Label | FEN | Score at the current evaluator |
|---|---|---:|
| start | `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1` | 20 |
| middlegame | `r3k2r/p1ppqpb1/bn2pnp1/2pP4/1p2P3/2N2N2/PPQBBPPP/R3K2R w KQkq - 0 1` | -243 |
| pawn ending | `8/2p5/3p4/1P1P4/8/4k3/8/4K3 w - - 0 40` | -74 |
| passed pawn | `4k3/8/8/3P4/8/8/4K3/8 w - - 0 1` | 215 |
| pawn threat | `4k3/8/8/8/8/2n5/3P4/4K3 b - - 0 1` | 0 |

One iteration evaluates all five positions through the trace-disabled scalar
HCE and sums their side-to-move scores. Positions, position states and
evaluator state are prepared before timing. The timed path does not allocate,
format, perform I/O, lock or mutate shared state. Dead-code elimination
barriers consume the position pointer and every score.

Version 2 changes only state lifetime: one evaluator state is prepared per
suite, matching one persistent worker state in search. Version 1 recreated a
zero-sized state inside each iteration; after ADR-0052 added a pawn cache, that
would have measured clearing the cache rather than using it. The corpus and
five full-refresh calls are unchanged, so v2 remains comparable with v1's
zero-state measurements. Any later change to corpus, work, backend or state
preparation creates another schema version. The expected
checksum is not part of that identity: it is a dead-code guard whose value is a
property of the evaluator under test, so it moves whenever an accepted step
changes evaluated scores. Conformance is owned by the reference corpus in
`tests/eval_reference.zig` and by the bench fingerprint, not by this number.

An expected checksum is never updated merely to make preflight pass. Each
change below was caused by an accepted evaluator step and re-recorded with its
reason; throughput values recorded under different checksums remain comparable
because the corpus and work are identical.

| Checksum | From | Cause |
|---:|---|---|
| 354 | Step 3.2 | Bootstrap evaluator baseline |
| 100 | Step 5.3.1 | Unwinnable material began scoring as drawn |
| 80 | Steps 5.3.3–5.3.5 | Shelter, storm and king safety |
| 86 | Step 5.3.6 | Threats and space |
| 86 | Step 5.3.8 | Imbalance moved only the clamped `pawn threat` case, so the sum is unchanged |
| 60 | Step 5.3.10 | Pawn-structure and passed-pawn completion |
| 2 | Step 5.3.11 | Piece-detail completion |
| -95 | Step 5.3.12 | Threat and king-safety completion |
| -85 | Step 5.3.13 | Exact KPK knowledge moves the supported central passer |
| -82 | Step 5.3.14 | Winnability narrows the low-complexity pawn ending |
| -44 | Step 5.3.15R.1 | Disjoint pawn-weakness ownership and graded passer paths |
| 23 | Step 5.3.15R.2 | Legal pinned attacks, protection-aware threats and central space |
| 23 | Step 5.3.15R.3 | File-aware shelter, endgame king-pawn proximity and complete danger inputs; offsetting corpus changes leave the sum unchanged |
| -166 | Step 5.3.15R.4 | Exact KPK WDL, geometry/tempo endgames and completed winnability facts |

## Step-5.3.13 measurement

| Item | Value |
|---|---|
| Date | 2026-08-21 |
| Host/toolchain | Ryzen 9 5950X; Windows 11; Zig 0.16.0; ReleaseFast native x86-64 |
| Schema/checksum | `manta-hce-bench-v2`; `-85` |
| Throughput | 3,634,675 eval/s |
| MAD | 28,505 eval/s (0.78%) |
| Step-5.3.9 comparison | -32.8% from 5,410,463 eval/s; within the 40% structural allowance |

The measurement includes the worker-local pawn cache justified by ADR-0052.
It is descriptive cost evidence, not a strength claim.

## Step-5.3.14 measurement

| Item | Value |
|---|---|
| Date | 2026-08-21 |
| Host/toolchain | Ryzen 9 5950X; Windows 11; Zig 0.16.0; ReleaseFast native x86-64 |
| Schema/checksum | `manta-hce-bench-v2`; `-82` |
| Throughput | 3,581,285 eval/s |
| MAD | 70,453 eval/s (1.97%) |
| Step-5.3.9 comparison | -33.8% from 5,410,463 eval/s; inside the 40% structural allowance |

This is the final structural-head cost checkpoint before the Step-5.3.15
freeze. It is descriptive cost evidence, not a strength claim.

## Step-5.3.15R.1 measurement

| Item | Value |
|---|---|
| Date | 2026-08-21 |
| Host/toolchain | Ryzen 9 5950X; Windows 11; Zig 0.16.0; ReleaseFast native x86-64 |
| Schema/checksum | `manta-hce-bench-v2`; `-44` |
| Throughput | 3,483,258 eval/s |
| MAD | 19,806 eval/s (0.57%) |
| Step-5.3.9 comparison | -35.6% from 5,410,463 eval/s; inside the 40% structural allowance |

The added candidate proof is bounded by the pawn count and cached with the
other pawn-only facts. This is descriptive cost evidence, not a strength
claim.

## Step-5.3.15R.2 measurement

| Item | Value |
|---|---|
| Date | 2026-08-21 |
| Host/toolchain | Ryzen 9 5950X; Windows 11; Zig 0.16.0; ReleaseFast native x86-64 |
| Schema/checksum | `manta-hce-bench-v2`; `23` |
| Throughput | 3,576,957 eval/s |
| MAD | 10,961 eval/s (0.31%) |
| Step-5.3.9 comparison | -33.9% from 5,410,463 eval/s; inside the 40% structural allowance |

Pin classification is bounded by the piece count and raw x-rays remain local
to their named consumers. This is descriptive cost evidence, not a strength
claim.

## Step-5.3.15R.3 measurement

| Item | Value |
|---|---|
| Date | 2026-08-21 |
| Host/toolchain | Ryzen 9 5950X; Windows 11; Zig 0.16.0; ReleaseFast native x86-64 |
| Schema/checksum | `manta-hce-bench-v2`; `23` |
| Throughput | 3,286,940 eval/s |
| MAD | 10,541 eval/s (0.32%) |
| Step-5.3.9 comparison | -39.3% from 5,410,463 eval/s; inside the 40% structural allowance |

The legal future-castling shelter variant measured 2,987,482 eval/s (-44.8%)
after bounded optimization and was rejected before this retained measurement.
Current-square shelter remains file-aware; low-material king-pawn proximity and
pawn/queen danger inputs are retained. This is descriptive cost evidence, not
a strength claim.

## Step-5.3.15R.4 measurement

| Item | Value |
|---|---|
| Date | 2026-08-21 |
| Host/toolchain | Ryzen 9 5950X; Windows 11; Zig 0.16.0; ReleaseFast native x86-64 |
| Schema/checksum | `manta-hce-bench-v2`; `-166` |
| Throughput | 3,294,829 eval/s |
| MAD | 1,436 eval/s (0.04%) |
| Step-5.3.9 comparison | -39.1% from 5,410,463 eval/s; inside the 40% structural allowance |

The exact KPK table is a checked 24 KiB embedded artifact, so generation is
not part of this runtime measurement. This is descriptive cost evidence, not
a strength claim.

## Step-5.3.16 constrained-fit measurement

| Item | Value |
|---|---|
| Date | 2026-08-22 |
| Host/toolchain | Ryzen 9 5950X; Windows 11; Zig 0.16.0; ReleaseFast native x86-64 |
| Schema/checksum | `manta-hce-bench-v2`; `-260` |
| Throughput | 3,451,257 eval/s |
| MAD | 4,445 eval/s (0.13%) |
| Step-5.3.9 comparison | -36.2% from 5,410,463 eval/s; inside the 40% structural allowance |

The fit changes coefficients only, not evaluator work or ownership. This is
descriptive cost evidence, not a strength claim.

## Step-5.4.3 MAN-E20 cost diagnostic

| Item | Switch-off | MAN-E20 |
|---|---:|---:|
| ReleaseFast median, baseline-first pair | 3,340,415 eval/s (0.19% MAD) | 3,281,808 eval/s (0.09% MAD) |
| ReleaseFast median, candidate-first pair | 3,349,299 eval/s (0.05% MAD) | 3,161,950 eval/s (1.96% MAD) |
| Geometric mean | 3,344,854 eval/s | 3,221,322 eval/s |
| Relative throughput | 100% | **96.307%** |

The 2026-08-24 idle-host preflight reported 2.7%, 4.0% and 2.8% total CPU.
Both arms passed checksum `-260`; MAN-E20 changes none of the five corpus
scores, so no benchmark checksum change was required. The order and geometric-
mean rule were fixed before timing: switch-off, candidate, candidate,
switch-off. MAN-E20's 3.693% regression is retained as cost evidence. The
original 2% hard veto was withdrawn by explicit maintainer amendment because
it had no Elo, integrated-NPS or feasibility derivation; time-controlled games
will decide the net quality/speed result if static fitting gates pass. The
noisier second candidate result is retained rather than rerun after seeing it.

## Step-5.4.3 MAN-E21 cost diagnostic

| Item | Switch-off | MAN-E21 |
|---|---:|---:|
| ReleaseFast median, baseline-first pair | 3,336,244 eval/s (0.23% MAD) | 3,401,036 eval/s (0.63% MAD) |
| ReleaseFast median, candidate-first pair | 3,374,970 eval/s (0.42% MAD) | 3,408,151 eval/s (0.22% MAD) |
| Geometric mean | 3,355,551 eval/s | 3,404,592 eval/s |
| Relative throughput | 100% | **101.461%** |

The 2026-08-24 idle-host preflight reported 0.3%, 0.7% and 0.0% total CPU.
The predeclared order was switch-off, candidate, candidate, switch-off. Both
arms passed checksum `-260` and kept all five corpus scores. The measured 1.461%
candidate increase is retained as a code-layout-sensitive cost diagnostic; the
candidate still requires time-controlled games because evaluator throughput
does not prove playing strength or integrated search speed.

## Sampling

The tool runs one 150 ms warm-up, calibrates a batch to approximately one
millisecond, then records eleven independent 150 ms samples. It reports median
evaluations per second, median absolute deviation (MAD), MAD percentage, total
iterations and the checksum. Debug is preflight/instrumentation context only.
Throughput evidence uses ReleaseFast, a native target and an otherwise idle
host; concurrent builds, games, data generation and other timed work invalidate
the sample.

## Step-3.2 baseline

| Item | Value |
|---|---|
| Date | 2026-08-10 |
| Host | AMD Ryzen 9 5950X, 16 physical cores / 32 logical processors |
| OS | Windows 11 Pro 10.0.26200 |
| Toolchain/build | Zig 0.16.0, ReleaseFast, native x86-64 |
| Sampling | 150 ms warm-up; 11 × 150 ms; median ± MAD |
| Throughput | 6,313,094 eval/s |
| MAD | 20,481 eval/s (0.32%) |
| Total iterations | 2,089,725 |
| Checksum | 354 per iteration |

This single baseline sizes the fallback evaluator. It is not an A/B speed
claim and does not license a playing change. It was taken at checksum `354`,
before Steps 5.3.1 to 5.3.8 changed evaluated scores; the corpus and work are
unchanged, so later throughput values compare directly against it.

## Commands

```text
zig build eval-bench -- --preflight-only
zig build eval-bench -Doptimize=Debug
zig build eval-bench -Doptimize=ReleaseFast
```
