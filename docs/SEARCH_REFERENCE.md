# Classical search reference and observation contract

This document freezes the Step-5.1.1 comparison inputs and translates useful
ideas into Manta-owned work. Its purpose is to accelerate hypothesis discovery,
dependency mapping and test design. It is not a behavior or implementation
target, an Elo claim, or permission to copy foreign formulas and constants.
Manta remains an independently reasoned and implemented Zig engine.

## Frozen references

The machine-readable provenance and critical-file SHA-256 values are in
[`config/phase-5.1.1-reference.json`](../config/phase-5.1.1-reference.json).
It also records the Git blob identities of the exact Rarog planning and hybrid
materials consulted. Manta vendors none of this source.

| Role | Exact revision | Why it exists |
|---|---|---|
| Last released pure-HCE engine | Stockfish 11 tag `sf_11`, commit `c3483fa9a7d7c0ffa9fcc32b467ca844cfb63790`, tree `93525fdd9d189002afdb47518c0d2d64e8066ea3` | Released classical evaluator and search contract |
| Strongest final pre-NNUE snapshot | Stockfish commit `9587eeeb5ed29f834d4f956b92e0e732877c47a7`, tree `195aaf13e94aac16e4065e76b67aafd5f8704f63` | Later classical search/evaluator source specification |
| Isolation prior | Rarog `hybrid` at `75d0d43af230ecf969aac13dfdbde05344c99a42` | Shows that holding one HCE constant under another search can answer an architectural question |
| Sequencing prior | Rarog `codex/search-convergence` at `19c803388f0edcead17afc45f5457c032b1b3e64` | Supplies dependency-complete search/HCE audit and ordering methods, not accepted Manta mechanisms |

Stockfish is GPL-3.0 and Manta is GPL-3.0-or-later. Licensing permits study,
but Manta's project contract still requires original Zig implementation and
explicit local reasoning. The reference revisions never move silently.

## Observation population

The current `manta-search-observation-v22` is defined in
[`src/search/observation.zig`](../src/search/observation.zig). It contains two
legal, nonterminal roots in each cohort: opening, quiet middlegame, tactical,
check/evasion, zugzwang-sensitive pawn endings, and general endgames. Every
case uses its registered fixed depth. TT and ordering history are cleared
before every case, so a changed order cannot create cross-position cache
history. Hash is fixed at 16 MiB.

Run the offline report with:

```powershell
zig build search-observe -Doptimize=ReleaseSafe
```

The report contains no clock-derived value. It records:

- main/qsearch and PV/non-PV nodes;
- prospective principal/cut/all node expectations;
- generated and searched moves;
- ordering source and fail-high move-index populations;
- TT probes, usable hits and stores by bound and producer;
- quiet-history rewards and accumulated nominal depth;
- contextual quiet-history lookups, nonzero consumers, exact/cutoff updates
  and authoritative full-depth LMR false-positive penalties;
- capture-history selections by main/qsearch/ProbCut plus authoritative
  exact/cutoff rewards and searched-alternative penalties;
- two-/four-/six-ply continuation lookups, nonzero values, historical
  check/tactical populations and authoritative outcome updates;
- null-move and LMR attempt/re-search/acceptance populations;
- ProbCut eligible-node, capture, qsearch-pass, verification and cutoff populations;
- root/move/null arrival, recursive route and nominal/searched-depth populations;
- typed fail-low/exact/cutoff outcomes by existing evidence producer;
- named prune and extension causes; and
- completed-root depth, bound, producer, best-move and score stability; and
- stability-gated aspiration attempts, fail-low/high retries and the final
  completed-root population, stability run and score delta.

The counter sink is caller-owned and has no policy return channel. The
disabled specialization performs no source classification and must preserve
the complete result, legal PV, node total and accepted production fingerprint.
Exact observation totals are diagnostic snapshots: a causal search change may
change them, but doing so requires a versioned record rather than editing a
test merely to regain green status.

Version 22 adds the Step-6.0.3 stability-gated aspiration population and retry
fields. Candidate builds use the same frozen legal roots and independently
validate exact completion, legal PVs, restored state and counter accounting;
the default-off report remains the accepted MAN-S29 search policy. Candidate-
off score/PV identity is deliberately not asserted because root-window changes
alter selective-search and TT interactions, which the playing gate must judge.

Version 21 retains the frozen MAN-S19 search policy and changes only its HCE
input to the constrained Step-5.3.16 coefficient vector. The evaluator can
change static bounds, ordering and pruning populations without changing search
code; the version bump makes that causal tree-shape change explicit.

The Step-5.1.5.0 accepted-policy rebaseline restores MAN-S13 and records zero
rejected MAN-S14 updates. Two v8 reports are byte-identical at SHA-256
`BFDDE5CA3228321B11F6847049C5A8D797294CC9076FF40BD5C4243EA7C5C8BE`.
Across 12 legal roots: 140,391 nodes; 4,013 LMR probes, 107 re-searches and
3,906 accepted reductions; 220,828 contextual lookups and 126,551 nonzero
consumers; 250 exact and 11,156 cutoff updates; 6,040 penalties; and zero
LMR-failure feedback updates. This is the frozen diagnostic entry point for
5.1.5.1, not a playing-strength claim.

Step 5.1.5.1 adds behavior-neutral node expectation and staged selection under
ADR-0035. The picker consumes one generated list, emits each entry once and
stably preserves generation order within equal TT/tactical/killer/history
ranks. Expectation and stage remain diagnostics with no score, bound, pruning,
reduction, extension or TT-store authority. The production fingerprint remains
`842,040`. Two v9 reports are byte-identical at SHA-256
`C6AC66C8714DB2D71DB8C34DA40AF2C33F80AE1FF8D91F2BDDDB934BAF88302B`;
the unchanged 140,391 nodes divide into 5,915 principal, 90,670 cut and 43,806
all expectations. This is the frozen entry substrate for dynamic LMR.

Step 5.1.5.3 tested MAN-S16 under ADR-0037. Its original capture relation is
resulting mover / side-relative destination / victim, with explicit
en-passant and promotion semantics. Only authoritative main-search exact or
cutoff outcomes train actually searched captures; qsearch and ProbCut only
consume the bounded value inside their existing SEE stage. Feature-off is
exact MAN-S15. Two v11 reports are byte-identical at SHA-256
`BAB955D764C55A6E06CCE94D638DCEFFB808FCE7F69CA8A7EC6990A1DF5FA3BE` and
record 38,755 selections (10,560 main, 28,184 qsearch, 11 ProbCut), 45 exact
and 4,700 cutoff rewards, and 319 penalties across 122,976 nodes. Its registered
`[1,5]` games accepted H0 at `-20.07 +/- 10.95` nElo, so it defaults off and
MAN-S15 remains production. Two v12 reports are byte-identical at SHA-256
`67A74760E21D614AC3F5A2EDFDD07F758718AF042266C0F772D972BB8DF0915D`;
the restored 124,188-node population records zero capture-history activity.

Step 5.1.5.4 accepts MAN-S17 under ADR-0038. Accepted one-ply reply history is
unchanged; one shared exact worker-local table adds real-move continuation
contexts at distances two, four and six, including historical check/tactical
facts. Root/null boundaries sever the chain. Counter-move and low-ply tables
remain absent because no diagnostic currently shows information beyond
killers, main history and continuation evidence. Bundle-off is exact MAN-S15
`750,869`; the candidate is `755,581`. Two v13 reports match at SHA-256
`6AA4A347571BD915BEA67E613237E622CB797581011F730F3F511FB1A51E1148`.
Across 143,644 nodes, distance 2/4/6 has 226,882/198,183/132,077 lookups,
62,915/122,041/110,883 nonzero values and 9,885/7,857/4,009 authoritative
rewards. Its registered `[1,5]` cluster SPRT accepted H1 after 5,640 games at
`+18.87 +/- 9.07` nElo and LLR 2.95, so MAN-S17 is production. Rejected
capture history has one conditional repeat at 5.1.5.6R: it opens only after
accepted static-eval/TT/qsearch work supplies a new populated relation that is
non-redundant with SEE and MAN-S17.

Step 5.1.5.5 tested MAN-S18 under ADR-0039. Manta did not adopt a reference
formula or constants: its accepted base surface remains authoritative and a
categorical vote layer changes it by at most one ply only after two independent
facts agree. Improving, node expectation, legal TT presence, verified singular
context and accepted-history consensus are separately switched and counted.
The final full-depth re-search result supplies symmetric contextual feedback
without duplicate node-outcome training. Umbrella-off is exact MAN-S17. Its
integrated `[1,5]` SPRT accepted H0 at `-6.61 +/- 7.07` nElo after 9,288 games,
so MAN-S18 is archived default off.

Step 5.1.5.6 accepted MAN-S19 under ADR-0040. Exact raw HCE in `[-255,255]`
uses nine spare authenticated TT bits without changing the old payload fields,
entry size or cluster associativity. Improving remains raw; only direction-
compatible ordinary searched evidence refines a separate pruning evaluation.
Qsearch retains explicit stand-pat/TT/searched-move provenance and a one-pawn-
cushioned SEE delta filter with PV/check/promotion/decisive guards and post-move
check exemption. Cluster-off is exact MAN-S17 `755,581`; MAN-S19 is `744,899`.
Two v16 reports match at SHA-256
`D4186FCB7675D5213716F648B5A8143825BE7849A475BCFA38DD946540965118`.
Across 192,340 nodes they record 20,538 TT raw-eval hits, 4,156 refinements and
5,403 delta candidates, including 361 checking exemptions. The registered
`[1,5]` SPRT accepted H1 after 8,922 scored games at `+13.02 +/- 7.21` nElo;
5.1.5.6R closed skipped because the cluster adds no contextual capture relation.

## Search contract map

“Equivalent” means the relevant semantic capability exists, not that the
implementation or constants match. “Partial” identifies a populated Manta
consumer with a narrower evidence model. “Missing” is a hypothesis source, not
an automatic task. “Deferred” preserves the current phase boundary.

| Reference contract | Manta producer and consumers | State | Owner / implication |
|---|---|---|---|
| Iterative deepening and completed root authority | `baseline.runRestrictedWithFeatures` produces `CompletedIteration`; UCI/time/fallback consume only completed evidence | Equivalent at the current 1T scope; MAN-S22 changes no behavior | Preserve through the cumulative freeze and Phase 5 |
| Aspiration retries | Parked compile-time candidate around completed ordinary scores | Intentionally different/inert | Revisit with root confidence in 6.0, not in 5.1.2 |
| PV/non-PV PVS and full-depth verification | `NodeExpectation` carries principal/cut/all context while `negamax` produces typed `full_search`, `pvs_probe` and `reduced_search`; PV/TT/root consume only completed provenance | MAN-S18's bounded expectation consumer was rejected; outcome authority is unchanged | Retain MAN-S17 policy; 5.1.5.8R closed skipped without new evidence |
| Staged TT/good tactical/killer/history/bad tactical ordering | `ordering.Picker`, SEE, TT move, killers and accepted quiet/reply history feed one stable allocation-free selector; MAN-S16 capture history is archived default off | Accepted substrate; capture evidence rejected | 5.1.5.4 starts from MAN-S15 without tactical history |
| Rich history families and outcome attribution | MAN-S13 supplies accepted one-ply reply evidence; MAN-S17 adds switched two-/four-/six-ply check/tactical continuation contexts through one worker-local table. Capture history was rejected; low-ply/counter evidence remains absent as unproven overlap. | MAN-S17 accepted; MAN-S18's majority consumer rejected | Capture history may repeat only through the 5.1.5.6R trigger |
| Contextual LMR and post-reduction feedback | Accepted MAN-S15 supplies the monotone nominal-depth/searched-move base and mandatory alpha-rise re-search. MAN-S18 added a one-ply-bounded two-signal vote layer plus symmetric full-depth-only contextual feedback. | MAN-S18 rejected on H0; archived off | 5.1.5.8R closed skipped: the accepted head supplied no materially new populated relation |
| Raw static evaluation versus searched/TT evidence | MAN-S19 caches exact near-balanced raw HCE in spare authenticated TT bits, keeps improving raw and refines a separate pruning evaluation only with compatible ordinary searched bounds | Accepted on the integrated `[1,5]` SPRT; exact feature-off identity and populated diagnostics | Production input to 5.1.5.7 |
| Quiescence check/evasion and tactical ordering | All evasions in check; otherwise typed stand pat/TT refinement, all promotions, negative-SEE filtering and bounded one-pawn-cushioned delta with post-move check exemption. TT/good-SEE/bad-SEE ordering remains; MAN-S16 is off. | MAN-S19 accepted; complete authority guards and accounting | 5.1.5.6R closed skipped because no new contextual capture relation exists |
| Null-move pruning | MAN-S19 retains MAN-S03 fixed-reduction same-node verification and pawn-only guard; MAN-S20's depth/eval reduction is archived off | MAN-S20 was populated but rejected on H0 | Reconsider only from measured 5.4.2 compatibility evidence |
| RFP, razoring, move-count/futility/SEE pruning | MAN-S11 accepts reverse/quiet futility, late-move and main-search SEE pruning; MAN-S20's extra history/move-count and pruning-eval/capture-SEE consumers are archived off while razoring stays parked | MAN-S20 rejected; MAN-S29 retunes only the accepted continuous consumers | Rejected categorical policies remain off |
| IIR, singular and other extensions | MAN-S19 retains MAN-S10 check/principal-IIR and one-ply singular search; MAN-S21's cut-IIR, provenance gate, double extension and searched multi-cut are archived off | MAN-S21 was correct/populated but exhausted its `[1,5]` cap near zero without H1 | Retry only from measured 5.4.2 compatibility evidence; negative/recapture/passed-pawn/last-capture/castling extensions remain parked |
| ProbCut | MAN-S19 retains MAN-S12's two legal non-promotion captures and qsearch/main verification; MAN-S20's direct TT decision is archived off | MAN-S20 rejected; capture history also remains rejected | Preserve accepted MAN-S12 authority in 5.1.5.8 |
| Correction history as residual/confidence evidence | No current producer or consumer | Missing/coupled | 5.4 owns it only after search and HCE residual/scale freeze |
| Persistent per-root-move effort/variance | Only completed best move/score stability is retained | Partial | Deferred to root-confidence Step 6.0 |
| Time allocation and publication | Conservative receipt-based clock and direct completion semaphore | Intentionally conservative | Phase 6.0; do not entangle with interior search development |

Accepted ADR-0043/`MAN-S22` freezes this table's accepted production
disposition as an executable `Features{}` default-policy ledger. The ledger is
behavior-neutral: it supplies no new chess evidence or authority and exists to
prevent a rejected or parked switch from silently entering the cumulative
candidate. Its registered cumulative gate against MAN-S13 accepted H1 at
`+13.32 +/- 7.83` nElo after 7,564 scored games, so every "accepted" row above
is now frozen production for Steps 5.2 and 5.3. Rows still marked missing,
parked or deferred stay closed until their owning later phase opens them.
| SMP search and shared histories | 1T worker-local state only; TT layout is already race-safe | Deferred | Phase 6.2 owns correctness, 4T strength and wider scaling |

## Decision boundary

Step 5.1.2 selected MAN-S06 from accepted MAN-S04. Its signed outcome producer
and narrow first-reducible-quiet consumer are independently ablatable. An
initial exemption for every positive-history late quiet was rejected before
games after decision-worthy ablations showed severe tree expansion; this is
the intended use of diagnostics, not tuning toward a reference trace. The
narrowed candidate passed deterministic gates but its registered `[3,10]`
time-based game test accepted H0 after 2,448 scored games. It is rejected and
disabled; MAN-S04 remains the accepted production mechanism. Fixed-depth
results, node reduction, source recall and reference comparisons can reject or
explain a candidate; similarity is never an objective or verdict. The game
result closes 5.1.2 and opens 5.1.3 without expanding to the whole table above.

Step 5.1.3 selects MAN-S07 from MAN-S04. It does not transplant a reference
formula: Manta's existing pin-aware, evaluator-valued SEE supplies a local
eligibility predicate, and the resulting Manta position supplies checking
status after make. SEE has no score/bound authority. All evasions, promotions
and negative-SEE checking captures remain searched; stand-pat TT provenance
follows the actual best source. The feature-off fingerprint is exactly MAN-S04.
The deterministic tree reduction admitted one registered game gate but did not
promote by itself. The `[3,10]` gate accepted H1 after 1,202 games at
`+49.54 +/- 19.64` nElo, so ADR-0026 is retained and 5.1.4 opens from MAN-S07.

MAN-S06 remains useful refutation evidence, not a closed verdict on history as
a mechanism class. Its context-free from/to producer and sign-only LMR
consumer must not be retuned. A later retry requires frozen 5.1.4 outcomes and
a new contextual attribution/consumer hypothesis; otherwise history redesign
waits for the Phase-9 post-NNUE search fit.

MAN-S08 studied a raw-HCE consumer deliberately smaller
than the mapped reference family: depth one only, non-PV zero window, not in
check, ordinary beta, side-to-move non-pawn material and a margin derived from
Manta's one-pawn score scale. The initial depth-through-three scope failed a
forcing tactical canary and was rejected rather than tuned. The surviving
candidate returns typed speculative beta, creates no PV/move and stores no TT
record. Deterministic qualification preserves it as a useful component
checkpoint, but the study preceded the shared depth-authority and neighboring
shallow-selectivity consumers. It therefore defaults off and receives no
isolated game gate. Step 5.1.4 proceeds through behavior-neutral context/depth
vocabulary, a complete depth-authority family, the shallow-selectivity family
that reconsiders MAN-S08, ProbCut, then a contextual-history decision.

ADR-0028 completes that behavior-neutral vocabulary. Recursive routes,
per-ply arrival/check facts, prospective depth components and typed outcomes
are populated and observable but have no policy return channel. Context-on/off
identity preserves accepted MAN-S07 and supplies the factual input now consumed
by MAN-S10's complete depth-authority candidate.

ADR-0029 builds that family as MAN-S10. Check state is authoritative extension
evidence; absence of a legal TT move at a mature non-root PV node is IIR
confidence evidence; and only a legal ordinary TT lower/exact record can seed a
same-position exclusion proof. Exclusion has no terminal, TT, PV, history or
null-move authority. Family-off is exact MAN-S07 and focused component
ablations populate every mechanism. The registered `[3,10]` gate accepted H1,
so the complete family is retained and Step 5.1.4.3 may now build its shallow
selectivity policy against this frozen depth authority.

ADR-0030 builds that policy as MAN-S11. One raw-static-evaluation cache plus
its two-ply same-side improving trend is the sole shared evidence; a checked
or same-position exclusion node never writes or reads it. Depth-one reverse
futility consumes that evidence before move generation. Quiet futility,
late-move pruning and main-search SEE pruning act only on the second and later
ordered legal move at an ordinary zero-window, non-PV, depth-at-most-three,
zugzwang-safe node and make their candidate move before deciding, mirroring
MAN-S07's own capture-eligibility idiom, so a node can never finish without one
fully searched move. Razoring substitutes the
accepted frontier verified-quiescence dispatch for the remaining move search
instead of a static bound, so its evidence carries full dispatch authority.
An initial depth-one-through-three razoring implementation still changed the
WAC.001 canary at root depth three, the same failure mode MAN-S08 already
refuted at a wider scope; razoring is therefore the sole parked component,
while reverse futility, quiet futility, late-move and SEE pruning default on
under the family umbrella. Family-off is exact MAN-S10. The exact candidate-as-A
`[3,10]` gate accepted H1 with zero infrastructure anomaly, so the complete
default family is retained and Step 5.1.4.4 opens against this frozen policy.

ADR-0031 builds MAN-S12 as a deliberately bounded ProbCut candidate rather
than translating a reference formula. It consumes Manta's ordinary score
scale, legal capture generator, accepted tactical ordering and typed depth
intent. Root, PV, checked, exclusion, pawn-only, promotion and decisive-score
paths remain ordinary. Existing TT evidence can order a legal capture but
cannot veto, shortcut or replace the qsearch-plus-reduced-search proof. The
mechanism returns fail-hard beta and persists only depth-minus-three lower-bound
authority with explicit ProbCut provenance. Its feature-off fingerprint is
exact MAN-S11; its legal observation population reaches every stage, including
verified cutoffs. Its registered candidate-as-A `[3,10]` gate accepted H1, so
the complete mechanism is retained and Step 5.1.4.5 opens from MAN-S12.

MAN-S13 uses the newly stable context and outcomes for one bounded retry. Its
original Zig table relates only the immediately previous resulting piece/to to
the current quiet piece/to after color-symmetric square normalization. Exact
and cutoff quiet winners train it against actually searched quiet alternatives;
fail-low, root, null, exclusion and pruned paths cannot. It augments quiet
ordering only, so it neither retunes MAN-S06 nor imports the reference's
multi-distance tables or reduction formulas. Feature-off is exact MAN-S12 and
the observation population shows nonzero exact/cutoff producers and consumers.
Its registered candidate-as-A `[3,10]` game gate accepted H1, so the complete
ordering-only mechanism is retained.

The first whole-stack audit selected MAN-S14 as one bounded synchronization
candidate rather than opening another broad feature family. An LMR probe that
rises above alpha has no training authority by itself. If its mandatory
full-depth re-search returns an upper bound at or below the same alpha, that
result specifically refutes the probe's apparent improvement. After unmake,
MAN-S14 applies one negative update to the accepted reply entry and removes
the move from any later node-outcome loser set, so it is never trained twice.
It does not let history alter reduction, pruning or score authority and is
materially different from rejected MAN-S06. Feature-off is exact MAN-S13 and
the archived v7 observation population records 63 such outcomes among 98 LMR
re-searches. The registered run stopped before a formal H0 boundary; its last
complete block at 3,558 games was `-5.87 +/- 11.42` nElo and LLR `-2.55`, with
zero recorded anomaly. The maintainer rejected the negative candidate,
MAN-S14 now defaults off and Step 5.1.4 closes with MAN-S13 restored.

ADR-0034 corrects the earlier assumption that this also completed Step 5.1.
The remaining search work is dependency ordered rather than parity ordered:
behavior-neutral node expectation/staged selection; independently gated
dynamic base LMR and capture history; one multi-distance continuation producer
bundle; then history/context-aware LMR, static/TT/qsearch, main selectivity and
extension/depth clusters. Root/time remains 6.0, shared SMP state 6.2 and
correction history 5.4 after HCE freezes. This map prevents a missing producer
from making a downstream feature look weak while still retaining attribution
for mechanisms that are meaningful on their own.

An FFI hybrid is not part of this step. It may be proposed later only when the
source map and native diagnostics cannot resolve a decision-relevant
search-versus-evaluation or joint-tuning ambiguity at lower cost. The same
boundary permits a prospectively bounded behavioral-convergence diagnostic
when native candidate families stall. Such an experiment isolates a mechanism;
it neither licenses copied implementation nor promotes reference parity.
