# Board benchmark contract

The board benchmark is descriptive throughput evidence, not a playing-strength
test. Its versioned profiles freeze chess inputs, exact work, sampling and
output semantics so results with the same profile name are comparable.

## Cross-engine profile

`cross-engine-board-v1` uses these positions in order:

| Label | FEN |
|---|---|
| startpos | `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1` |
| kiwipete | `r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1` |
| midgame | `rnbq1k1r/pppp1ppp/4pn2/8/1b1PP3/2N2N2/PPP2PPP/R1BQKB1R w KQ - 2 5` |
| endgame | `8/2p5/3p4/KP5r/8/8/8/7k w - - 0 1` |
| in-check | `rnbqkb1r/pppp1ppp/5n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 3 3` |

| Workload | Exact operation | Operations/iteration |
|---|---|---:|
| Legal moves | Generate the complete legal move list for every position. | 128 moves |
| Legal captures | Generate the legal capture list for every position. | 10 moves |
| Make/unmake | Generate legal moves, make and immediately unmake each one using stable preallocated state. | 128 moves |
| Threshold SEE | Evaluate `SEE >= 0` for every legal capture using P/N/B/R/Q/K values 100/300/300/500/900/20000. | 10 captures |
| Perft | Count start-position depth-four legal leaves. | 197,281 nodes |
| Two-ply simulation | Make each legal root move, generate the reply list, count replies, then unmake. | 4,597 moves |

The working set is created before timing and is neither allocated nor copied in
the timed region. Every workload must restore it exactly. A dead-code-
elimination barrier consumes generated lists, state or results. Preflight must
match every operation count before timing begins.

Each workload receives a 150 ms warm-up followed by eleven independent 150 ms
samples. Report the median operations per second, median absolute deviation,
MAD percentage, operations per iteration and total iterations.

Within a sample the deadline clock is read once per calibrated batch, not once
per iteration. A monotonic clock read costs tens of nanoseconds while the
ten-operation workloads complete an iteration in roughly a hundred, so a
per-iteration deadline test would leave a double-digit percentage of clock
overhead inside the timed region and report it as board throughput. The batch
is sized during warm-up to about one millisecond of work, which puts the
residual clock cost near 0.002% and leaves the estimator, sample count and work
quanta unchanged. Debug results are correctness and instrumentation context
only. Peak-speed evidence requires
`ReleaseFast`, a native CPU target, an idle stable-power host and a complete
machine/toolchain/build manifest.

## Historical profiles

`legacy-board-a-v1` uses the cross-engine corpus and six workloads, but
reproduces the earlier fixed iteration/warm-up schedule and eleven-sample
median/MAD estimator.

`legacy-board-b-v1` substitutes the FEN
`8/8/3p4/KPp4r/8/8/8/7k w - c6 0 1`, measures cached check detection instead
of threshold SEE, and reproduces its earlier Debug/optimized iteration counts
and best-of-three estimator. Its work quanta are 129 legal moves, 10 captures,
129 make/unmakes, 5 check tests, 197,281 perft nodes and 4,603 simulated replies.

Historical results are comparable only within the exact matching legacy
profile. They must never be mixed with the reconciled profile or used to infer
playing strength.

## Commands

```text
zig build board-bench -Doptimize=Debug -- --profile cross-engine-board-v1
zig build board-bench -Doptimize=ReleaseFast -- --profile cross-engine-board-v1
zig build board-bench -Doptimize=ReleaseFast -- --profile legacy-board-a-v1
zig build board-bench -Doptimize=ReleaseFast -- --profile legacy-board-b-v1
zig build board-bench -- --preflight-only
```

Do not compile, run games, generate data or execute another timed workload
during a measurement. Discard contaminated results instead of adjusting them.
