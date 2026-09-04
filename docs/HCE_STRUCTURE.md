# Final frozen Phase-5 HCE structure

Step 5.3.15R.5 refreezes the classical evaluator's structure before fitting. The
score scale is deliberately not frozen: Step 5.3.16 may change coefficients,
but it may not add terms, change their producers or introduce a binary switch
without a new prospective decision.

| Component / stage | Producers | Transformation | Consumers |
|---|---|---|---|
| `material_pst` | Authoritative piece/color/square placement | Piece value plus color-relative PST; material phase count | Tapered total, SEE's separately frozen MG values |
| `imbalance` | Piece and total-pawn counts | Four signed count products | Prospective fitted candidate only; production switch remains off until the registered ablation |
| `pawns` | Full pawn placement and exact pawn sets | Disjoint doubled/isolated/backward ownership, weak lever/unopposed, blocked, connected/support | Tapered total; pawn sets are reused by passers and winnability |
| `activity` | Piece placement, occupancy, attack tables, pawn spans and king rings | Legal-ray mobility, outposts, bishop/rook/queen detail; produces legality-filtered shared attack maps while named x-ray terms derive raw geometry explicitly | Tapered total, passed pawns, threats, king safety |
| `passed` | Cached pawn sets, occupancy, shared attacks, both king squares | Candidate/leverable classification, rank/file, per-square path attack/defence and king race | Tapered total and winnability passer count |
| `king_safety` | King/pawn placement, shared attacks, blockers and queen availability | File-aware current shelter, endgame king-pawn proximity and excluded nonlinear squared danger with pawn/piece attackers | Tapered total |
| `pawn_threats` | Pawn attack maps and enemy non-pawn placement | Signed attacked-piece count | Tapered total |
| `threats_space` | Shared attack maps, placement and material phase | Piece threats, restrictions, queen pressure and phase-gated space | Tapered total |
| `winnability` | Combined EG score, passed set, kings, total pawns, pawn flanks and leader material | Excluded capped/sign-dependent EG adjustment including pure-pawn endings | Tapered EG total |
| Phase interpolation | Frozen material phase | Convex MG/EG interpolation with integer truncation | Ordinary white-relative score |
| Exact endgames | Exact material signatures, side to move and board geometry | Exact generated KPK WDL plus geometry/tempo-aware ordinary values and scales | Replaces/scales interpolated ordinary evidence; Syzygy remains search-owned |
| Final rules | Side to move, tempo, mating material, rule-50 clock | STM conversion, tempo, unwinnable clamp, rule-50 scaling | Static ordinary `Score`; MAN-S19 raw-eval cache and search |

All ordinary search consumers remain those frozen by MAN-S19/MAN-S22. The
fitting path does not alter terminal, repetition, Syzygy, TT-bound, PV,
legality or history ownership. Evaluator state remains one bounded worker-local
pawn cache; feature extraction is offline and never enters search.

The authoritative fitting contract is [`HCE_FITTING.md`](HCE_FITTING.md).
