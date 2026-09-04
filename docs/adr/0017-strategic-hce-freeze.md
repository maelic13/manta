# ADR-0017: Strategic HCE freeze

## Status

Accepted for Step 3.2 on 2026-08-10.

## Context

The bootstrap HCE must be reliable enough to bring up deterministic search,
diagnose later evaluator integration and remain a fallback. It must not become
an open-ended feature/tuning program when NNUE is the strategic evaluation
path. Step 3.2 therefore needs a correctness and cost boundary, not another
playing candidate.

## Decision

- Freeze the Step-3.1 scalar algorithm and parameter snapshot. Reopen an HCE
  mechanism only for a demonstrated correctness defect, a later search/profile
  bottleneck, a targeted diagnostic with clear value of information, or the
  explicitly authorized optional fallback phase.
- Retain full refresh and zero-sized evaluator state. The versioned native
  baseline exceeds six million evaluations per second with low sample spread;
  without search attribution there is no evidence that an incremental cache,
  pawn hash or optimized backend would repay its ownership and conformance
  surface.
- Treat rank-flip/color-swap equality as the primary evaluator metamorphic
  invariant. Every white-centric component must negate, phase must remain
  equal and the final side-to-move score including tempo must remain equal.
- Keep rights, en-passant availability, move clocks, repetition, dead-position,
  terminal and future tablebase facts outside static evaluation. Checkmate and
  stalemate positions deliberately return ordinary heuristic scores; search
  supplies decisive provenance.
- Preserve ordinary-score separation under the maximum orthodox promoted
  material budget. Static HCE output may not enter future tablebase or mate
  bands regardless of material advantage.
- Version the benchmark corpus, checksum, work and sampling. Its throughput is
  descriptive engineering evidence, never evidence of chess strength.

## Consequences

- Phase 4 can consume a deterministic, allocation-free scalar fallback without
  inheriting evaluator caches, runtime dispatch or terminal-policy ambiguity.
- No HCE tuning, game test, broad feature survey or speculative optimization is
  authorized by completing Phase 3.
- Later NNUE work keeps the same evaluator boundary and factual dirty records;
  HCE remains buildable and tested rather than becoming the position owner.

## Verification

- `tests/eval_invariants.zig` covers complete color symmetry, trace-component
  negation, rights/history independence, endgame ordering, terminal ownership
  and decisive-band separation at maximum promotion material.
- `manta-hce-bench-v1` preflights five scores and checksum `354`, performs only
  trace-disabled full-refresh evaluation in the timed path and reports robust
  median/MAD statistics.
- Debug, ReleaseSafe and ReleaseFast tests plus native/portable builds preserve
  the scalar result.
