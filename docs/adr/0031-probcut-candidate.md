# ADR-0031: Bounded ProbCut candidate

## Status

Accepted as `MAN-S12` on 2026-08-14. The exact registered maintainer-owned
playing gate accepted H1 with zero engine or runner anomaly. Step 5.1.4.5 is
open against this frozen ProbCut policy.

## Context

Accepted MAN-S11 freezes Manta's ordinary depth authority, shallow static/
improving evidence, legal tactical generation, SEE-aware ordering, qsearch and
typed TT contracts. Step 5.1.4.4 can therefore test one independent question:
can a bounded capture proof avoid an expensive ordinary subtree when a move is
very likely to exceed beta?

The pinned classical reference supplies the control-flow concept—raised
beta, tactical move selection, qsearch screening, reduced verification and
discounted TT depth—but not Manta's policy or constants. Manta derives its
margin from its 100-units-per-pawn score scale, uses its existing legal move and
ordering contracts, and retains explicit producer provenance. Recorded sibling-
engine weak conversion and a failed formula transplant are additional reasons to
require local population and game evidence rather than reference similarity.

## Decision

- Add independently ablatable `Features.probcut`, default on only for MAN-S12.
  Disabling it restores accepted MAN-S11 exactly.
- Eligibility requires an interior non-PV, non-check, non-exclusion ordinary
  zero-window node at searched depth at least five, known static context and
  side-to-move non-pawn material. Draw/max-ply/TT/depth-zero handling already
  precedes the candidate. Root, decisive-score and pawn-only paths remain in
  ordinary search.
- Generate legal captures and order them with Manta's existing tactical
  ordering. A validated TT move is only an ordering hint; no TT record may
  veto, accept or bypass either proof. Exclude every promotion because its
  discontinuous material semantics remain under ordinary search. En passant is
  an ordinary legal capture whose transition and qsearch account for the
  removed pawn and king safety. Examine at most the first two remaining moves
  to bound miss overhead.
- Raise beta by exactly one evaluator pawn. First search the made capture in
  quiescence at that zero window. A pass has no cutoff authority: search the
  same child again through main search with a three-ply reduction at the same
  threshold. Cancellation from either child unwinds the chess transition and
  incremental evaluator state before propagating.
- Only a verified lower/exact result at the raised threshold cuts. Return the
  original beta as a fail-hard lower bound with distinct `probcut` provenance;
  publish no PV. The verified child searched nominal depth minus one with a
  three-ply reduction, so the parent TT lower bound owns depth minus three and
  stores the proving capture with its producer class.

## Consequences

Terminal and draw decisions remain earlier and authoritative. A stalemate has
no capture that can prove the candidate and therefore reaches ordinary legal
generation. Checked positions, all evasions, promotions, root restrictions,
same-position exclusion searches and pawn-only zugzwang-sensitive positions
never enter ProbCut. Castling is not a capture; en passant uses normal legal
make/unmake. Mate and tablebase bands cannot be raised because both beta and the
raised threshold must remain ordinary.

The mechanism adds one bounded capture generation/order pass and possible
qsearch/reduced-search work at eligible nodes; successful verification can
remove the remaining ordinary branch. It adds no allocation, formatting, I/O,
lock or shared atomic to the hot path. Fixed-depth node reduction and cutoff
conversion diagnose cost only; they do not prove strength.

## Verification

- Pure tests protect every eligibility guard, the ordinary raised threshold and
  depth-minus-three store authority. The legal cancellation test stops inside
  qsearch after a ProbCut capture was made and proves board key/history and
  evaluator state are restored.
- `manta-search-observation-v5` raises only its opening-start case to bounded
  depth nine. It reaches 239 eligible nodes, 41 selected captures, five qsearch
  passes/verifications and four cutoffs; route, prune and ProbCut-provenance TT
  stores reconcile exactly. Two ReleaseSafe reports are byte-identical at
  SHA-256 `6797A49017AF81C4A9B9A3BEAD0EA9878F832EB3FEF789695FDB63292D9FB267`.
- Feature-off depth-six bench is exact MAN-S11 at `956,100`. MAN-S12 is
  `919,299`, 3.85% fewer nodes; this is a diagnostic tree-shape snapshot, not a
  speed or Elo claim.
- Debug, ReleaseSafe and ReleaseFast suites, including all 16 UCI transcripts
  and existing tactical/mate/draw/history canaries, pass. Format, lint and the
  portable build pass. The clean Zig-0.16 native candidate is source
  `7892717a7e032f5b113a88b4af79ba15857be221`, SHA-256
  `AF091EF481EA42EC559FEEC1FB019975C9E6DED05A33A10D695148B68352C86C`,
  bench `919,299`. The frozen accepted MAN-S11 baseline is source
  `ace48de929d94bf4be630ea7362dd5ff4efb280f`, SHA-256
  `78163E47E2CBDB5596A0671D63FD484432B4D04D10E5F9A3B982634D9AE96B0F`,
  bench `956,100`. Both manifests are clean, native, non-PGO and compiler-equal.
- The registered gate is candidate A versus accepted MAN-S11 B, 1T
  `3+0.03`, Hash 64 MiB, concurrency 14 on the Ryzen 9 5950X, explicit physical
  CPUs `0,2,...,26`, UHO book, strength-v1 adjudication, seed `514124`,
  normalized `[3,10]`, alpha/beta 0.05 and at most 12,000 games. Recent gates
  measured about 55 pairs/minute: expect roughly 10–30 minutes for a material
  boundary and about 110 minutes at the cap; stop manually at three hours.
  Budget storage is under 40 MiB. The temporary fastchess bridge has no reliable
  pair-atomic resume, so an interrupted run is restarted rather than combined.
- Only an H1 boundary with zero engine/runner anomaly promotes MAN-S12. H0
  rejects it; reaching the cap without H1 parks/reverts it. No fixed-node,
  alternate-TC or reference-convergence result substitutes for this verdict.
- The registered run accepted H1 after 2,314 scored games/1,157 complete pairs
  in 21m03s: 650 wins, 516 losses and 1,148 draws, pentanomial
  `[63,233,453,323,85]`, `+28.76 +/- 14.16` nElo and LLR 2.95. The complete log
  contains zero timeout, crash, disconnect, illegal-move, forfeit, warning or
  protocol anomaly. Independent PGN reconstruction matches the scored W-D-L
  and pentanomial exactly; two completed in-flight single games, one candidate
  win and one loss, are correctly excluded.
- Run artifacts are manifest SHA-256
  `96D17341352570AD193D481F38ED4D89379EFF4F75B2CE232A6293A13B983939`,
  PGN `AFEAD9EFFFA9F7CDE4062A9F7D69C049C7125F407AF1F536D294299979574913`
  and log `4466C0637C69D37B6A6F54D6F14F280158B054FC2221E686C5AFF408C3062F5F`.
  The verdict retains the complete mechanism, not its individual guards,
  thresholds or constants.

## Traceability

Supports `FUNC-004`, `FUNC-005`, `FUNC-006`, `SCORE-001`, `SCORE-002`,
`SCORE-003`, `SCORE-004`, `SCORE-010`, `SCORE-011`, `SCORE-012`, `PERF-006`,
`PERF-009`, `PERF-010`, `QUAL-005`, `QUAL-013`, `QUAL-014`, `QUAL-015` and
`QUAL-016`.
