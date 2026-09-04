# ADR-0052: Ordinary-authority endgame knowledge and a worker-local pawn cache

## Status

Accepted for Step 5.3.13 on 2026-08-21. The endgame structure remains subject
to the shared Step-5.3.16 fit and playing gate; this record accepts its
authority boundary and deterministic qualification, not playing strength.

## Context

Manta had no specialized endgame recognizer. Its rejected MAN-E05 scaling
damped broad material classes without first deciding which exact endings were
convertible. ADR-0051 therefore bound Step 5.3.13 to ten value recognizers and
seven scale recognizers and prohibited the evaluator from imitating terminal
or tablebase evidence.

Step 5.3.12 also exposed two measurement issues. Fixed-depth wall time mixed
evaluator cost with the node-count behavior changed by evaluation, so it could
not be a cost budget. Evaluator throughput remained the honest common-work
metric. Separately, Step 5.3.10's richer pawn model fired ADR-0048's explicit
retry condition for a pawn cache.

## Decision

- Add exact-material recognizers for `KXK`, `KBNK`, `KNNK`, `KNNKP`, `KPK`,
  `KQKP`, `KQKR`, `KRKB`, `KRKN`, `KRKP`, `KBPKB`, `KBPKN`, `KBPPKB`, `KPKP`,
  `KRPKB`, `KRPKR` and `KRPPKRP` behind `endgame_knowledge`.
- Value recognizers return a white-relative ordinary score. Scale recognizers
  return a bounded factor out of 64. Neither form can carry a search bound,
  provenance, mate distance, draw verdict or tablebase band.
- Dispatch from one compact material signature per side after a seven-piece
  cutoff. Promotion needs no special case because its resulting material is
  already authoritative; castling and en-passant rights do not participate.
- Replace MAN-E05's broad scaling retry with these exact recognizers. The
  rejected switch remains archived and default-off.
- Add a 16-entry direct-mapped pawn cache to concrete evaluator state. It
  stores pawn sets and their pawn-only tapered score under the complete 64-bit
  pawn key. A collision is a miss and recomputation, never a false hit. The
  cache is worker-local, bounded below 4 KiB, allocation-free and independently
  ablatable through `pawn_cache`.
- Restate the structural cost budget on evaluator throughput alone. Node count
  remains a search-behavior diagnostic owned by 5.4.0; fixed-depth wall time is
  not an evaluator-cost oracle.
- Bump the HCE benchmark to `manta-hce-bench-v2`. Evaluator state is created
  once per suite, matching one state per worker. Recreating a nonzero cache on
  every timed iteration would measure clearing rather than evaluation.

## Consequences

Producers are exact piece counts, piece and king squares, pawn placement and
the existing ordinary evaluation. Consumers are final static evaluation and
MAN-S19's exact raw-evaluation cache. Terminal, repetition, rule-50, Syzygy,
TT-bound, PV and legality ownership do not change.

All seventeen signatures are exercised on both colors. Nearby material
counterexamples, conversion boundaries, ordinary-band checks, switch-off
identity, held-out residual improvement and full-key cache collision identity
protect the mechanism. The five-position conformance checksum changes from
`-95` to `-85`; production's depth-six fingerprint changes from `742,820` to
`736,492`, and all eighteen archived fingerprints are re-recorded together.

On the idle development host, benchmark v2 reports `3,634,675` eval/s with
0.78% MAD. Against the Step-5.3.9 `5,410,463` baseline this is `-32.8%`, inside
the structural block's 40 percent allowance. This is cost evidence only.

## Traceability

- `PLAN.md` 5.3.12 and 5.3.13; `GUIDE.md`; `docs/HCE_COVERAGE.md`.
- `src/eval/endgame.zig`, `src/eval/hce.zig`, `tools/eval_bench.zig`.
- `SCORE-001`, `SCORE-005`, `PERF-002`, `PERF-006`, `PERF-009`, `QUAL-015`.
