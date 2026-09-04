# ADR-0065: Integrated completed-root time management

## Status

Accepted for Step 6.3.1 on 2026-08-31. Safety telemetry and MAN-T04 tuning are
complete. MAN-T05 is accepted as the production default by explicit maintainer
judgment after its H1 result; the cumulative Phase-6 4T gate remains.

## Context

The Phase-4 clock divides usable time by a fixed horizon, credits half the
increment and caps the hard budget at twice the soft budget. It is safe but
does not distinguish game phase, easy roots, unstable choices, falling scores,
ponder work or SMP uncertainty. MAN-R01 showed that simply treating three
root facts as reasons to extend the old soft deadline is not sufficient.

Step 6.3 needs the mechanism breadth of mature time management without copying
another engine's formula or fitted constants. Manta already has the required
native producers: receipt-based deadlines, exact completed-root evidence,
once-latched ponder credit and a main-authoritative lazy-SMP pool.

## Decision

- Ordinary clocks receive distinct optimum and maximum budgets. The estimated
  move horizon uses explicit moves-to-go when supplied and otherwise contracts
  gradually from opening to late game. Projected increment is credited across
  that horizon only after future command overhead is reserved.
- Fixed movetime retains its accepted single-overhead, equal optimum/maximum
  contract. Dynamic allocation never applies to fixed work or movetime.
- Worker zero alone decides completed-iteration stopping. Its immutable maximum
  deadline remains rooted at `go` receipt and cannot be extended by root or
  ponder evidence.
- Only a populated, completed, exact ordinary root iteration may adjust the
  optimum. Stability, a best-move change, ordinary score trend and root effort
  concentration form bounded fixed-point factors. One genuinely legal root
  move is forced; a one-move `searchmoves` restriction is not.
- Stable concentrated effort is treated as an easy root and spends less. A
  changed move, falling ordinary score or dispersed effort may spend more.
  This differs from MAN-R01's rejected rule, which treated concentrated effort
  as uncertainty and required a categorical agreement threshold.
- Helpers publish only a monotonic aggregate count when their own completed
  ordinary best move changes. Worker zero drains and normalizes that count by
  helper count at its next completed iteration. No helper move, score, PV or
  result gains authority, and worker count cannot multiply wall time.
- The receipt-to-hit ponder interval is consumed once at a reasoned 75% credit;
  the uncredited quarter acknowledges a wrong ponder line. It may move the
  preferred stop only within the original maximum deadline.
- The preferred stop is disabled below completed depth four. The hard poll,
  cancellation, legal fallback and main-owned publication remain authoritative
  at every depth.
- The complete policy is the production default. The pre-fit policy and
  rejected MAN-R01 switch are retained only for reconstruction and are
  mutually exclusive with the integrated policy.
- The complete MAN-T04 fit freezes candidate defaults at horizon/increment/
  maximum-ratio/stability/score/effort `1034/957/4291/1036/1049/1046`.
  Disabling the compile-time candidate retains the exact untuned values
  `1000/1000/4000/1000/1000/1000` for the playing gate.

## Chess and ownership consequences

Legal generation supplies the unrestricted root count before `searchmoves`.
Terminal and root-draw positions create no dynamic sample; mate and tablebase
scores cannot become ordinary score trends. Castling, en-passant and promotion
need no special clock rule because their encoded identities already survive
the completed-root producer. Allocation adds no recursive-node branch,
allocation, cache access or I/O. Helpers add at most one shared atomic update
per changed completed iteration, never per node.

## Evidence gate

Step 6.3.1 requires directional budget/factor properties, provenance exclusion,
forced-versus-restricted root evidence, ponder saturation, normalized helper
instability, unchanged hard caps, compile-time feature-off equivalence and the
ordinary focused build gates. Step 6.3.2 must then add frozen telemetry and
fake-clock/process qualification at 1/2/4/8T before any SPSA or games.

## Traceability

Supports `UCI-004`, `UCI-005`, `PERF-008` and `SCORE-030`; preserves ADR-0008,
ADR-0020 and ADR-0064 except for the explicitly added bounded helper time
observation.
