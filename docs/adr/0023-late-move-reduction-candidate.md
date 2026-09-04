# ADR-0023: Conservative late-move reduction candidate

## Status

Accepted for Step 5.1 on 2026-08-12 through `MAN-S04`.

## Context

After verified null-move pruning, Manta still searches every ordered legal move
at full nominal depth. Move ordering makes later quiet moves less likely to
raise alpha, so a cheaper preliminary search may reject many of them. A reduced
search is selective evidence, however: it cannot acquire PV, cutoff, or
full-depth TT authority merely because its numeric result fits the window.

## Candidate decision

- Keep LMR compile-time ablatable and enabled in the accepted production
  search; feature-off remains a diagnostic and regression oracle.
- Reduce exactly one ply for the fourth and later ordered quiet moves at depth
  four or greater. Never reduce captures, promotions, moves from check, or
  moves that give check.
- Search the reduced move through a null window. Any result above alpha is
  re-searched at full depth before it may raise alpha, cut off, extend a PV, or
  produce a lower bound.
- Tag an accepted reduced fail-low as `reduced_search`; suppress its PV
  continuation and reduce its TT depth authority by one ply.
- Preserve unchanged move generation, legality, terminal/draw/history rules,
  make/unmake, evaluator updates, cancellation, and allocation behavior.

The fixed one-ply reduction, fourth-move threshold and depth-four floor are
deliberately conservative reasoning values, not copied or fitted constants. A
depth-three floor was rejected before games because it changed the protected
WAC.001 move from `g3g6` to `f6g4`; the existing tactical canary remains
authoritative. Current
Stockfish supplies the control-flow concept—later ordered moves receive reduced
null-window probes and alpha-raising probes are re-searched—but its logarithmic
tables, history adjustments, node roles, and tuned constants are not portable
evidence for Manta.

## Consequences

- The candidate may change move selection and the deterministic fingerprint;
  fewer nodes or greater depth does not establish strength.
- Full-depth searches remain the only authority for alpha raises and cutoffs.
  Reduced fail-lows may influence ordering through shallow upper-bound TT data.
- No runtime policy object, allocation, I/O, lock, or shared mutable search
  state enters the hot path. Future SMP workers retain local counters.

## Verification and promotion

- Eligibility tests protect early/tactical/checking moves and feature-off
  behavior. Provenance tests protect reduced TT depth authority.
- Search tests require exact completed root evidence, legal sequential PVs,
  complete position restoration, nonzero probes, and one terminal disposition
  per probe (accepted or full-depth re-search).
- The maintainer runs the full ReleaseSafe suite and returns the accepted
  depth-6 benchmark/diagnostic record before a production game gate is admitted.
- The corrected depth-four candidate measured `2,910,189` depth-six nodes
  against accepted MAN-S03's `6,715,524` (56.66% fewer). This admits the final
  correctness rerun but does not itself license games or establish strength.
- The complete ReleaseSafe rerun passed, including all 16 UCI transcripts,
  WAC.001, registered fingerprint, LMR ablation/provenance accounting, legal PV
  and state restoration. This admits exactly one registered playing gate.
- Deterministic evidence admitted one candidate-as-A 1T `3+0.03` normalized
  `[3,10]` SPRT under the retained zero-anomaly fastchess profile; only H1
  could promote.
- The exact clean tested build was candidate `5af4bbb` / SHA-256
  `B69767A11C39667C6BBD3D19A9E2A2DBB92A0979023928BAFC94520BB0854374`
  against accepted MAN-S03 `5711752` /
  `7F55F8560E6873F0F54B2CDCE38178724746044A0C4A0871C6ED4DA5669D1B09`.
  Both manifests record Zig 0.16.0 native non-PGO clean builds.
- The registered SPRT accepted H1 after 842 scored games/421 pairs in 7m34s:
  302 wins, 182 losses and 358 draws, `+69.47 +/- 23.47` nElo and LLR
  2.96. The log contains zero timeout, crash, illegal-move, protocol, process
  or affinity anomaly. Two additional already-running games reached the PGN
  after the paired stop boundary and do not enter the statistic.
- This accepts the complete conservative eligibility, reduced-evidence and
  full-depth re-search contract. It does not establish that its thresholds or
  one-ply reduction are independently optimal.

## Traceability

Supports `SCORE-001`, `PERF-006`, `PERF-009`, `PERF-010`, `QUAL-013`,
`QUAL-014` and `QUAL-016`.
