# ADR-0030: Shallow-selectivity family candidate

## Status

Accepted as `MAN-S11` on 2026-08-14. The exact registered Ryzen playing gate
accepted H1 with zero infrastructure anomaly. Step 5.1.4.4 is open against this
frozen shallow-selectivity policy.

## Context

Accepted MAN-S10 freezes check extension, IIR and TT-dependent singular
extension over the frozen `manta-search-observation-v3` context vocabulary.
Step 5.1.4.3 reopens the shallow-node family PLAN §5.1.4 named beside it:
reverse futility, razoring, quiet futility, late-move pruning and main-search
SEE pruning, all sharing one pre-move evidence model of check, PV/window,
improving/static authority, prospective depth and zugzwang guards.

Parked ADR-0027/`MAN-S08` already qualified a depth-one reverse-futility
component but explicitly deferred its eligibility, margin and consumers to
this step. Every new mechanism below needs the same raw-static-evaluation
foundation plus a two-ply "improving" trend that did not exist before this
candidate, because a static score is only as trustworthy as its recent
direction: an evaluation confirmed by the last time the same side moved
deserves a smaller cushion before search acts on it, and an unconfirmed one
deserves a larger cushion. That single principle (`shallowConfidenceBonus`)
sets every margin and threshold below; no coefficient is imported from a
reference engine.

## Decision

- Cache one raw HCE evaluation per non-check, non-exclusion main node in a new
  per-ply `ThreadState.static_evals` trail. A node in check, or a same-position
  singular-exclusion probe, never writes or reads this trail: exclusion
  searches manufacture no reusable score authority (ADR-0029), and a checked
  side has no static option to compare. "Improving" compares this node's
  evaluation with the same side's evaluation two plies earlier only when that
  earlier ply was itself known; otherwise the position is conservatively
  treated as not improving.
- Add `Features.shallow_selectivity` as the family umbrella and five
  independently ablatable producers: `reverse_futility`, `razoring`,
  `quiet_futility`, `late_move_pruning` and `see_pruning`. Disabling the
  umbrella alone restores accepted MAN-S10 exactly. The qualified depth-one
  ADR-0027 reverse-futility producer now reuses the shared cached evaluation
  and defaults on inside this family.
- Razoring, at a non-PV, non-exclusion, zugzwang-safe node with ordinary
  alpha, replaces the remaining move search with the same verified
  quiescence call the depth-zero frontier already uses whenever static
  evaluation plus its margin cannot reach alpha. Its evidence is therefore
  exactly as authoritative as any other depth-zero dispatch; nothing is
  fabricated from the static comparison alone.
- Quiet futility, late-move pruning and main-search SEE pruning apply only to
  the second and later ordered legal moves at an ordinary zero-window, non-PV,
  depth-at-most-three, zugzwang-safe node, so a node can never finish without
  at least one fully searched move. Quiet
  futility skips a quiet move whose static evaluation plus margin cannot reach
  the current alpha; late-move pruning skips a quiet move once the searched
  ordinal passes a depth/improving-scaled threshold; SEE pruning skips an
  ordinary non-promotion capture whose SEE falls below a depth-scaled
  threshold, exactly as accepted qsearch SEE (ADR-0026) already treats SEE as
  eligibility only, never score evidence. Every skip first makes the move to
  read its true post-move checking status and unmakes it only if the move does
  not give check, mirroring ADR-0026's own capture-eligibility idiom.
- A fail-low result that skipped at least one late move stores at one ply less
  than nominal TT depth, matching the existing `reduced_search` discount,
  because an omitted sibling was never shown not to raise alpha. An exact
  result already came from a fully searched move and keeps full authority
  regardless of unrelated moves skipped afterward.

## Consequences

- Producers are raw HCE evaluation and the cached two-ply trend; the resulting
  post-move checking fact comes from authoritative board transition. Immediate
  consumers are the parent alpha-beta comparison and, for razoring, the
  existing verified quiescence dispatch. No new TT, PV, terminal, draw or
  reusable score authority is created; legal generation, make/unmake, check
  evasion, castling, en passant, promotion and mate-distance handling are
  unchanged.
- An initial depth-one-through-three razoring implementation still changed the
  WAC.001 forcing-move canary at root depth three, the same failure mode
  ADR-0027 already refuted for a wider reverse-futility scope. Rather than
  search a margin space with only deterministic canaries as a refutation
  oracle, razoring is retained as the sole parked family component: implemented,
  independently ablatable and tested, but default off and excluded from the
  family's own default-on state. Reverse futility, quiet futility, late-move
  pruning and main-search SEE pruning independently preserve every existing tactical,
  mate, draw/history and UCI gate with the family enabled.
- Every consumer adds no allocation, formatting, I/O, lock or shared atomic.
  Caching one evaluation per non-check node when the family is enabled adds
  real per-node cost; this is a deliberate diagnostic trade-off inert when
  disabled, not a claimed throughput or strength result.

## Verification

- Debug, ReleaseSafe and ReleaseFast suites cover pure eligibility/margin
  functions, feature-on/off equivalence, nonzero candidate/prune populations
  per producer, the parked-razoring exemption, zugzwang-sensitive pawn-only
  exemption for every producer, the reduced-TT-depth discount, legal PV/state
  restoration and the complete tactical/mate canary set with the family
  enabled.
- Family-off depth-six bench remains exactly accepted MAN-S10's `3,581,485`.
  The default family (razoring excluded) fingerprint is `956,100`; enabling
  the parked razoring component alongside it changes it to `948,920`.
  Both are diagnostic tree-shape snapshots, not strength evidence.
- The versioned `manta-search-observation-v4` population adds one printed
  shallow-selectivity accounting line; two ReleaseSafe reports are
  byte-identical at SHA-256
  `0F55460D5B70B14EC6D47C80CC5590AECA7684334C3C639B5D2F3F145CF175AE`, and
  its `.see` `PruneCause` tag is now shared by qsearch and main search, each
  with an independently audited counter summing to that one aggregate.
- The exact clean native candidate is source `ace48de`, binary SHA-256
  `78163E47E2CBDB5596A0671D63FD484432B4D04D10E5F9A3B982634D9AE96B0F`;
  the frozen clean native MAN-S10 baseline is source `9cc14ce`, binary SHA-256
  `394F14160485AEFDFE0A39AF028E626339C833F870A68D48C827FCD705F70002`.
  Both use Zig 0.16.0 and the candidate sidecar records bench `956,100`.
- The registered maintainer-run candidate-as-A gate is 1T `3+0.03`, Hash 64
  MiB, concurrency 14 on the Ryzen 9 5950X, UHO book, strength-v1
  adjudication, seed `514113`, normalized `[3,10]`, alpha/beta 0.05 and a
  12,000-game/6,000-pair cap. Recent accepted gates measured about 56 pairs per
  minute: expect roughly 10–30 minutes for a material boundary and about 107
  minutes at the cap; stop manually at three hours. Budget storage is under 40
  MiB. The temporary fastchess bridge has no reliable pair-atomic checkpoint/
  resume contract, so an interrupted run is not continued as evidence.
- Only H1 promotes the default family (razoring excluded). H0 rejects it; the
  cap without H1 is unresolved and must be parked/reverted. H0 would be the
  second coherent Step-5.1 family failure after rejected MAN-S06, triggering
  the required 5.1.1 scope/value review rather than continuing to 5.1.4.4.
- The registered run accepted H1 after 414 scored games/207 complete pairs in
  3m45s: 186 wins, 52 losses and 176 draws, pentanomial
  `[5,16,70,72,44]`, `+162.92 +/- 33.47` nElo and LLR 2.96. The complete log
  contains zero timeout, crash, disconnect, illegal-move, forfeit, warning or
  protocol anomaly. Independent PGN reconstruction matches the scored W-D-L
  and pentanomial; one extra completed unpaired baseline win is correctly
  excluded from the statistic.
- Run artifacts are manifest SHA-256
  `43E7D3686076FE9771C70F5B7904FBCA48CFA5FE622C825890AD5FFFE59001F5`,
  PGN `05914FDFC20F9C2025EE067465306EFA3857E9535051A3FC99842E42A2BCB044`
  and log `399BC0D4A0CF2E172D17F4FF374D20FEFFA1FFA86EFAE07E91DC6A7F61EB1226`.
  This verdict retains the complete default family, not its individual guards,
  thresholds or constants; razoring remains parked off.

## Traceability

Supports `FUNC-004`, `FUNC-005`, `FUNC-006`, `SCORE-001`, `SCORE-003`,
`SCORE-004`, `SCORE-010`, `SCORE-011`, `PERF-006`, `PERF-009`, `PERF-010`,
`QUAL-005`, `QUAL-013`, `QUAL-014`, `QUAL-015` and `QUAL-016`.
