# ADR-0016: Bounded original bootstrap HCE and reference snapshot

## Status

Accepted for Step 3.1 on 2026-08-10.

## Context

Manta needs a deterministic static evaluator before search, but the planned
strategic evaluator is NNUE. Recreating the reference engine's accumulated HCE wholesale
would import historical search coupling, caching and endgame policy while
spending the evaluation budget on a fallback. Mechanical translation would
also violate Manta's originality and ownership rules.

The one-time source snapshot is version `v1.9.3`, commit
`61e6f233879a132d966118ab2304f923eb855162`. The inspected files were clean
relative to that tag despite an unrelated dirty test file in its checkout:

| File | SHA-256 |
|---|---|
| `src/eval.cpp` | `504f7b9adcbf4e86178db990f5d5d6eb5805f5e76c3d5caae52549631d646cfc` |
| `src/eval_params.h` | `bcc8c4dcee2cb135befdc22cb71ffe0945cb835b00e654ec94028e70cec42d31` |

## Decision

- Manta independently composes a scalar, white-centric tapered evaluator from
  board facts. It converts to side-to-move at the final boundary and then adds
  tempo. No C++ control structure, cache layout or evaluation table is linked.
- The frozen value snapshot retains the source snapshot's accepted material, piece-square,
  phase, passed-pawn, doubled/isolated/connected pawn, bishop-pair, rook-file,
  rook-seventh, knight-outpost, mobility, pawn-threat and tempo values.
- Four trace components are stable: material/PST, pawns, activity and pawn
  threats, followed by phase and final total. `tests/eval_reference.zig` is the
  conformance snapshot and update procedure: an intentional change requires a
  new ADR or superseding ADR, a native experiment-ledger entry and corpus
  review; values are never changed merely to make a failure pass.
- Evaluation is full-refresh. `State` is zero-sized and factual delta updates
  are no-ops. A cache or incremental representation requires Step-3.2
  measurement plus full-refresh equivalence evidence.
- Ordinary evaluation is deterministic and allocation-, I/O-, lock- and
  shared-atomic-free. Tracing writes only to a bounded caller-owned sink.

## Intentional deviations from the reference

These differences are one bounded bootstrap decision, registered as MAN-E01:

1. Manta mobility counts geometric destinations excluding own occupancy and
   enemy pawn attacks. It does not import the reference's pinned-piece/blocker and
   extended mobility-area composition.
2. The bootstrap omits backward/refined pawn terms, passer-path/king-distance
   terms, material imbalance and survey additions, rook/passer relationships,
   trapped-bishop logic, king shelter/storm and danger, advanced threats and
   space. They are not silently valued at zero; they are outside this HCE.
3. Manta has no lazy-evaluation exit, pawn hash, evaluator telemetry or runtime
   parameter loader. Those are performance/tooling mechanisms, not chess facts.
4. Static evaluation does not apply rule-50 damping, dead-position or KPK
   verdicts, opposite-bishop/endgame scaling, lone-king mate drive, or terminal
   overrides. Search/draw/tablebase layers own that evidence under SCORE-001.
5. Manta uses four reviewable trace groups rather than the reference's tuner-oriented
   parameter trace. The retained constants are a one-time snapshot and will not
   synchronize with later upstream changes.

The frozen full reference totals for the five Manta corpus positions are
`20, -73, -70, 0, 0`; Manta totals are `20, -94, -42, 216, 254`. Only the
opening is exactly equal. The differences are expected consequences of the
listed semantic boundary, not evidence that either evaluator is stronger.

## Consequences

- Manta has a usable, traceable static signal for later search integration
  without allowing static heuristics to impersonate proven chess outcomes.
- The scalar implementation is the only backend and semantic oracle in this
  step. Step 3.2 owns symmetry, endgame-scale and throughput closure.
- No strength claim follows from reference similarity, corpus stability or
  deterministic tests. No tuning or game job is authorized.

## Verification

- The corpus checks exact component pairs, phase, total and trace/no-trace
  identity over opening, middlegame, pawn-ending, passed-pawn and threat cases.
- A focused regression proves rule-50 history does not change static output.
- Compile-time checks instantiate the evaluator contract and keep state
  zero-sized; repository gates cover Debug, ReleaseSafe and ReleaseFast.
