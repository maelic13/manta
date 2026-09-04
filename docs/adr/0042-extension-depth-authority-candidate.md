# ADR-0042: Extension and depth-authority candidate

## Status

Parked and reverted on 2026-08-15. Deterministic qualification passed, but the
registered maintainer-owned SPRT reached its full budget without accepting H1.

## Context

Accepted MAN-S10 provides check extension, principal-node IIR and one-ply
singular extension. MAN-S15 supplies typed dynamic LMR, MAN-S19 supplies raw
evaluation and TT provenance, and prospective node expectation is now explicit.
The remaining question is not feature parity: it is whether those accepted
facts can safely distinguish missing move authority, uniquely forcing TT moves
and positions where more than one move proves a cutoff.

The pinned final pre-NNUE Stockfish source supplies the concepts of reduced
same-position exclusion and verified multi-cut. Later source demonstrates that
stronger singular separation can justify more depth. Manta derives its own
typed policy, thresholds and guards; no foreign formula, constant, table or
control flow is copied.

## Decision

- Preserve MAN-S10 principal-node IIR. Add one-ply IIR only to non-root,
  non-check, non-exclusion expected-cut nodes of searched depth at least seven
  that lack a legal TT move. `all` nodes remain full depth. The reduced active
  depth, not nominal depth, owns any later TT store.
- A singular candidate must now come from a legal ordinary lower/exact TT move
  produced by an ordinary full or PVS search. Reduced, null, ProbCut,
  speculative, qsearch, terminal, tablebase and recursively read TT producers
  cannot seed exclusion authority.
- Retain MAN-S10's one-pawn singular threshold and two-ply-shallower first
  exclusion search. An upper bound below that target extends the TT move once.
  At a deep principal node, an exact one-ply-shallow-or-better record plus a
  second pawn of searched alternative separation permits two extension plies.
- At an expected-cut node, a non-singular exclusion result may prune only from
  searched evidence. If the first exclusion lower bound already proves beta,
  return fail-hard beta. Otherwise a TT value above beta merely authorizes a
  second half-depth exclusion search at beta; only its lower/exact result at
  beta cuts. The cutoff is typed `speculative_cutoff`, is not stored at the
  same node and never builds a PV/history result.
- Keep an umbrella and separate cut-IIR, TT-provenance, multi-cut and double-
  extension switches. Umbrella-off must be exact MAN-S19.
- Park negative extension. Manta currently cannot reduce an early TT move and
  guarantee that a fail-low cannot inherit full result/TT authority without a
  new verified-reduction contract; MAN-S18's rejected reduction synchronization
  provides no license. Also park recapture, passed-pawn, last-capture and
  castling extensions: names alone do not establish an independent chess
  signal beyond existing check/singular search.

## Consequences

Draw/repetition, maximum ply and terminal handling still precede selectivity.
Exclusion state is saved and restored on success, cutoff and cancellation.
Castling, en-passant and promotions need no special new path because only a
legality-validated encoded TT move is excluded; ordinary move generation owns
all alternatives. No new mutable state, allocation, I/O, lock or shared atomic
enters the hot path.

Cluster-off and the candidate both have the depth-six fingerprint `744,899`
because the new mechanisms begin beyond that horizon; this equality is not a
strength or inactivity claim. Repeated `manta-search-observation-v19` reports
match at SHA-256
`2183992E0236F040B497D48304192A7A85D8F61639C53B585F8C35863227B433`.
Across 195,832 nodes they record three expected-cut IIR events, 74 singular
attempts, 41 beta-verification probes and 36 multi-cut cutoffs. Focused tests
cover principal IIR preservation, provenance rejection, bounded double
extension, exclusion bound direction, nominal completed depth, legal PV,
restored state and zero exclusion TT stores.

The candidate-as-A 1T `3+0.03`, Hash-64, concurrency-14, seed-`515218`,
normalized `[1,5]` SPRT exhausted its 20,000-game budget in 3h01m13s without
accepting either boundary: 4,728-4,743-10,529, pentanomial
`[459,2466,4196,2389,490]`, `-0.40 +/- 4.82` nElo and LLR -2.25. The exact
20,000-game PGN and log contain no infrastructure anomaly. Per the prospective
rule, a cap without H1 cannot promote; the umbrella defaults off and exact
MAN-S19 remains production. No immediate ablation or constant retry is worth
another full budget. Step 5.4.2 may formulate a structurally new retry only if
frozen HCE/correction evidence creates and populates a depth/selectivity
relation unavailable here; otherwise the mechanism remains archived.
Repeated production `manta-search-observation-v20` reports match at SHA-256
`0C488A2413038DC1EFF1DFA88152C28BBCF0C84C34F5EA6E00E42018B7098144`,
restore MAN-S19's 192,340 nodes and prove zero cut-IIR/multi-cut activity.

## Traceability

Supports `FUNC-004` through `FUNC-006`, `SCORE-003`, `SCORE-004`, `SCORE-010`,
`SCORE-011`, `SCORE-015`, `SCORE-016`, `SCORE-022`, `PERF-006`, `PERF-009`,
`PERF-010`, `QUAL-013` through `QUAL-017`, and Step 5.1.5.8 in `PLAN.md`.
