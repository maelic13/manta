# ADR-0028: Search context and prospective-depth vocabulary

## Status

Accepted for Step 5.1.4.1 on 2026-08-12. This is behavior-neutral search
infrastructure and receives no playing gate.

## Context

Accepted MAN-S07 passes raw depth integers and node flags through recursive
PVS. Later check extension, IIR, singular/exclusion search, shallow pruning and
contextual history need to distinguish the requested child horizon from an
extension or reduction, and to distinguish how a node was reached from what
score/bound evidence it returned. Inferring those facts later from a raw depth,
move index or numeric score would couple consumers and repeat the attribution
problem exposed by rejected MAN-S06.

## Decision

- Represent prospective depth as `DepthIntent`: nominal child horizon plus
  explicit extension and reduction plies. `searched()` is the saturating
  composition and exactly reproduces every current full, LMR and null depth.
- Record caller-produced `EntryRoute` values for root, first move, scout,
  PV re-search, reduced probe/re-search, null probe/verification, singular
  exclusion, ProbCut and qsearch.
- Keep one factual `PlyContext` slot per search ply. It records root, ordinary
  move or null arrival, the exact encoded prior move, an optional excluded move
  and the resulting in-check fact. Special-move identity is preserved but
  chess-rule meaning remains owned by board transition code.
- Derive `NodeDisposition` only from the returned typed bound: upper is
  fail-low, exact is exact and lower is cutoff. `OutcomeAttribution` carries
  that classification together with route, depth and existing typed evidence;
  score magnitude and provenance never substitute for bound authority.
- Keep the entire path compile-time ablatable. Step 5.1.4.1 consumers are
  diagnostics only and have no return channel into policy.

## Consequences

- Recursive callers produce arrival, route and depth intent; move/null
  transitions produce resulting check state; completed main/qsearch nodes
  produce typed outcomes. The caller-owned observer is the only current
  consumer. Step 5.1.4.2 may consume the vocabulary only through separately
  reviewed playing mechanisms.
- Legal generation, terminal and mate-distance handling, repetition/rule-50,
  castling, en-passant, promotion, qsearch, scores, bounds, TT storage, PV
  construction, move ordering and accepted history behavior are unchanged.
- `ThreadState` gains fixed per-ply storage. Recursive search performs no heap
  allocation, formatting, I/O, lock, atomic or shared-state operation. The
  future SMP contract remains worker-local.
- The context may affect instruction count and stack-resident state while
  enabled, but it cannot claim speed or strength. The exact enabled/disabled
  search tree is the behavior-neutral acceptance condition.

## Verification

- Pure tests independently cover depth composition, bound-only disposition
  mapping and exact castling/en-passant/promotion move identity.
- A legal middlegame search with separate TT and ordering state proves
  context-on/off identity for best move, score/bound/provenance, node count,
  selective depth, completed depth and legal PV, plus full board restoration.
- The production and feature-off depth-six fingerprints are both accepted
  MAN-S07's `2,288,471` nodes. All tactical, mate, draw/history, state and UCI
  gates remain authoritative.
- `manta-search-observation-v2` retains the same 12 legal roots and reset
  policy while adding route, arrival, depth and outcome accounting. Two
  ReleaseSafe reports are byte-identical at SHA-256
  `634722084BA01823E100825827E287EFE9CBF77A795B73B696603C2F6C81A598`.
  They account for all 70,373 nodes/outcomes: 11,915 fail-lows, 1,143 exact
  results and 57,315 cutoffs; 255 reduced probes, two reduction re-searches,
  one null probe and zero extensions.
- No SPRT is authorized. Step 5.1.4.2 opens from accepted MAN-S07 plus this
  inert vocabulary.

## Traceability

Supports `SCORE-003`, `SCORE-010`, `PERF-006`, `PERF-009`, `QUAL-013`,
`QUAL-014`, `QUAL-015` and `QUAL-016`.
