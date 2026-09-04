# ADR-0038: Multi-distance continuation-history candidate

## Status

Accepted as MAN-S17 on 2026-08-14. The registered `[1,5]` cluster SPRT
accepted H1; MAN-S17 is the production baseline for Step 5.1.5.5.

## Context

Accepted MAN-S13 learns one immediately preceding move relation, but a quiet
move's usefulness often depends on an earlier tactical exchange, check escape
or piece placement. MAN-S15 now supplies a stable dynamic LMR consumer for a
later step, so Step 5.1.5.4 first needs richer ordering evidence without letting
history control reduction. Rejected MAN-S16 capture history remains off.

Historical facts cannot be reconstructed from the current board: the mover may
have moved again, promoted or been captured. Root and synthetic null arrivals
also cannot be treated as legal move relations. Counter-move and low-ply tables
would overlap accepted killers, main history and the new continuation evidence;
the current diagnostics provide no reason to pay their state and game cost.

## Decision

- Extend each per-ply move arrival with the resulting piece type, absolute
  destination, whether its parent position was in check and whether the move
  was a capture or promotion. Castling records the king, en-passant the pawn
  and promotion the promoted piece. These are transported facts only.
- Preserve MAN-S13's accepted one-ply reply table. Add one shared exact table
  for two-, four- and six-ply contexts, keyed by historical check/tactical
  flags, historical resulting piece/side-relative destination, and current
  quiet piece/side-relative destination. Sharing deliberately generalizes the
  same relation across distances.
- A context exists only when every intervening arrival is a real move. Root,
  null and insufficient history suppress it. Each distance and the whole
  bundle have compile-time switches.
- Train only completed non-root, non-exclusion main-search exact/cutoff quiet
  winners. Reward the winner and penalize distinct current piece/destination
  relations only when they survived pruning and were actually searched. Use
  the accepted bounded depth-squared gravity law.
- Sum populated continuation entries with accepted main and reply history only
  inside the quiet stage. No continuation value changes SEE stage, legality,
  score, bound, provenance, PV, TT, terminal/draw, pruning or reduction policy.
- Do not add counter-move or low-ply history in MAN-S17. A later proposal needs
  a new information-overlap diagnostic and its own mechanism rationale.

## Deterministic evidence and registered gate

The table adds 1.125 MiB to each worker; complete ordering state remains below
1.5 MiB. Ordinary node paths allocate nothing and use no lock, I/O or shared
atomic. Feature-off restores accepted MAN-S15's depth-six fingerprint
`750,869`; MAN-S17 is `755,581`. ReleaseSafe, UCI transcripts, legal PV/state,
mate/draw, cancellation and focused relation/null-boundary properties pass.

Two `manta-search-observation-v13` reports are byte-identical at SHA-256
`6AA4A347571BD915BEA67E613237E622CB797581011F730F3F511FB1A51E1148`.
Across 143,644 nodes, distance 2/4/6 records respectively 226,882/198,183/
132,077 lookups, 62,915/122,041/110,883 nonzero values, 9,885/7,857/4,009
authoritative rewards and 6,382/4,398/2,439 searched-alternative penalties.
Check contexts populate 2,259/3,176/664 lookups and tactical contexts populate
12,353/12,298/889, refuting a vacuous-context implementation.

The registered gate used candidate as A on the designated Ryzen 9 5950X, one
search thread per engine, `3+0.03`, Hash 64 MiB, concurrency 14, pinned book,
adjudication and physical-core placement, seed `515174`, normalized `[1,5]`
and a 20,000-game cap. It accepted H1 after 5,640 games/2,820 pairs in 51m13s:
1,460 wins, 1,256 losses and 2,924 draws, pentanomial
`[128,608,1180,740,164]`, `+18.87 +/- 9.07` nElo and LLR 2.95. The PGN contains
exactly those 5,640 games and the log contains no timeout, crash, disconnect,
illegal-move, forfeit, stall, warning or error marker. One integrated verdict
licenses only the complete bundle; it does not prove an individual distance.

## Consequences

The exact table is materially larger than earlier histories and increases
cache pressure, so games—not the small diagnostic tree change—decide whether
the richer relation earns its cost. Later LMR synchronization may consume the
accepted MAN-S17 bundle. MAN-S16 capture history is not revived implicitly. A
conditional 5.1.5.6R repeat may open only after accepted static-eval/TT/qsearch
work supplies a structurally new, populated capture relation that diagnostics
separate from SEE and MAN-S17; otherwise it is skipped without code or games.

## Traceability

Supports `FUNC-004` through `FUNC-006`, `SCORE-010`, `SCORE-013`, `SCORE-018`,
`PERF-006`, `PERF-009`, `PERF-010`, `QUAL-013` through `QUAL-017`, and Step
5.1.5.4 in `PLAN.md`. Run evidence: manifest SHA-256
`02859F4587677BFFC098CED17CD245831EDDC7CE818A8D45CEA67F4F8BF8BC91`,
candidate sidecar `A4A2DC4133731A87B86C05C55BA3EC61CFA1985CCBC8721B8384DF6EDB55561E`,
baseline sidecar `20EF73B506F7CCAAE4B9E207C9E9C4F004CE00635E712C4C96B56FE2409A52DC`,
PGN `2A8D9C8076499F94D5CAE22D5BA540C56342836E2BD3D136D03D03D401617703`
and log `5ACF77CED9FB79228030DBB944BC7F6950ECCF6737680371D49808B5D30FC353`.
