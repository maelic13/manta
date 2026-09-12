# ADR-0070: Shared search evidence and depth contract

## Status and boundary

Design complete in Step 6.5.8, 2026-09-09, against production commit
`016025dfccd2143505911c87d3cafdb44313aa22`. This is a future implementation contract,
not a production policy change or experiment registration. ADR-0068 owns the
two performance targets; the pinned reference and inspected relationships are
recorded in [SEARCH_COVERAGE](../SEARCH_COVERAGE.md). Existing accepted score,
history, TT, qsearch and clock contracts remain authoritative until a separately
approved candidate explicitly changes them. Rejected switches remain off.

Step 6.5.9 implements exact adapters and disabled observation, not new pruning,
history learning or ordering. Step 6.5.10 derives candidate coefficients on
Manta's scale before coding consumers; this ADR freezes interfaces, eligibility,
publication authority and package boundaries, not speculative tuning values.

## Why this structure

Alpha-beta can spend less work on late, low-confidence alternatives if ordering
and pruning agree about their prospective depth. An alpha rise from a reduced
probe is a reason to verify, not evidence that the full-depth move wins.
Check extensions and singular proofs change the horizon that both consumers
must see. Joining these decisions could reduce wasted work without discarding
important alternatives; tactical misses, costly re-search tails or losing
time-controlled games can refute that hypothesis.

The current implementation has useful pieces, but not this unified contract:

- `baseline.zig:negamax` adds check depth at entry; IIR later changes active
  node depth. Shallow move tests use parent depth before LMR chooses child depth.
- The move-loop `searched_move_count` advances before shallow omission. Its
  current ordinal includes omitted moves; it is not an actually-searched count.
- `DepthIntent` separates nominal/extension/reduction, but route, TT producer
  and completed verification are not a single authority certificate. `probeTable`
  retains the original record while returned evidence uses `tt_exact/tt_bound`.
- The TT has depth, bound and producer, but no independent PV-origin bit.
  An exact bound must not be relabelled as PV-origin evidence.
- Main history is positive saturated legacy evidence; reply/continuation use
  signed feedback. Continuation distances 2/4/6 read one shared table, not three
  independent observations. None supplies a calibrated sample-confidence value.

These are design gaps, not newly established correctness bugs. Exact adapters
must preserve the legacy semantics, including its ordinal, until a registered
playing candidate owns the difference. Source remains in `src/search/`; no
search policy moves into board or evaluation modules.

## Interfaces and ownership

Names below are the implementation vocabulary. Use concrete value types and
existing domain types; an optional fact is unknown, never a fabricated zero.
Do not build a runtime policy graph or widen every TT entry to carry local facts.

| Value | Producer, lifetime and fields | Permitted consumers |
|---|---|---|
| `StaticFacts` | Node-local raw ordinary HCE, optional compatible ordinary TT refinement, optional correction, and separately optional own/opponent raw-eval trends. Stack entries carry validity and root/null/exclusion boundaries; compare same perspective explicitly. | Existing static consumers through a legacy adapter in 9. Candidate futility/null/depth may consume named fields, never an undifferentiated corrected score. Raw TT cache remains uncorrected. |
| `TtFacts` | `probeTable`: authenticated record, legal optional move, normalized score, bound, original producer, stored depth, generation freshness and compatibility flags. `pv_origin` is unknown with the current format. One probe/node lifetime. | Move ordering, ordinary refinement, cutoff, IIR and singular each have separate eligibility; legal move availability is not sufficient score authority. |
| `WindowFacts` | Root iteration owns optional reference width; invocation owns alpha/beta/current width and PV/cut/all expectation. Width is signed score-domain arithmetic after valid narrowing, not an overflow-prone packed score. | PVS and the optional window-aware depth/aspiration package. Expected node type is not a returned bound or observed outcome. |
| `MoveFacts` | Legal picker plus made-child check state: move, actual victim (including EP), resulting piece (including promotion), tactical/quiet, TT, evasion, gives-check, selected ordinal and actually-searched count. | Ordering and shared depth/pruning eligibility. Unknown gives-check cannot authorize omission. |
| `HistoryFacts` | Live worker-local lookup when the quiet stage is ranked, then a per-move snapshot for depth. Keep raw main/reply/continuation components and source keys separate. Optional paired signed outcome/support cells are diagnostic in 9. | Existing ordering/LMR use exact legacy views. New shared-confidence consumers use only their explicitly named, populated sources. |
| `NodeDepthPlan` | Node entry: requested horizon, admitted entry check extension, active horizon after IIR, ply capacity and scope. Immutable once node pruning starts. | Node-level margins, child plan construction and storage eligibility. IIR is applied once, not again by every move consumer. |
| `MoveDepthPlan` | Construct from active node depth, legal move facts, completed singular proof and the frozen reduction policy: nominal child, admitted move/child-check extensions, signed proposed reduction, prospective probe and authoritative verification horizons, prune-depth view, omission eligibility. | LMP/futility/SEE, reduced dispatch and mandatory verification read this same plan. No consumer recomputes a private depth formula. |
| `SearchOutcome` | Completed invocation: score/bound, original producer, route, requested/searched horizon, verification status, scope and whether selective siblings were omitted. Interrupted work is a separate incomplete outcome. | Parent negation/comparison, publication, history and TT storage through separate predicates. A route change or parent negation cannot erase restrictive origin/scope. |

Scopes distinguish ordinary, restricted-root, exclusion, null probe, ProbCut
and history-local evidence. Child board/history changes and same-ply exclusion
or null verification must restore both position and stack facts on every exit.
Worker zero alone publishes root/time/UCI results. Histories and optional
support remain worker-local; the shared TT does not transport local confidence.
An ordinary completed search can establish an outcome for its own horizon;
it need not label the whole tree as qsearch merely because its leaves used
qsearch. Conversely, wrapping or negating an unverified probe does not establish
that new authority. Successful mandatory re-search replaces the probe outcome
with its own completed certificate; history-local restrictions still propagate
where the returned bound depends on them.

### History support and feedback

In 9, define a bounded signed outcome cell plus `u8` saturating support. Its
update takes an explicit signed bonus and limit, applies the existing bounded
gravity primitive, and increments support once for that eligible update.
Support means admitted updates since clear, not independent samples or a
probability of correctness. Value and support clear together with their owner;
there is no new periodic aging schedule. Signed gravity forgets value gradually,
but saturated lifetime support is not recent reliability. A future recency
consumer must add and qualify a paired aging contract before using that claim.

The build selector `search-evidence-observation` defaults false and adds no UCI
option. Compile-time-disabled shadow tables may use only existing main/reply/continuation
keys, with value/support trained together. Do not attach filtered counts to
unfiltered legacy values and call them paired evidence. No new capture,
low-ply, countermove or static-feedback table is part of 9 or the initial core.
No shadow table storage or updates survive in the default build. State size and
allocation lifetime are checked when the diagnostic feature is enabled.

An update packet is constructed once after undo and final verification, from a
completed non-root, non-exclusion ordinary main-search exact/cutoff result.
Only the selected winning move and actually searched eligible alternatives
are candidates for feedback; omitted siblings are not failures. Reduced probes
alone, stand-pat, null/ProbCut/exclusion, decisive/draw/history-local results,
aborts and retries with no committed outcome do not train the new relation.
Context lookup cannot cross root or null discontinuities. Existing production
feedback remains untouched in 9; its adapter is not a claim that all legacy
updates already satisfy this new admission predicate.

## Ordered pipeline and depth arithmetic

1. Poll/visit under the existing clock contract. Resolve reached draw/terminal
   rules with checkmate precedence, ply safety and legal-root restrictions.
   The mate-bound package then narrows a non-root window before TT cutoffs.
   Future upcoming repetition is a history-local optional lower-bound producer,
   not a replacement for reached-draw adjudication.
2. Authenticate TT once; separate move, cutoff and raw/static-refinement uses.
   Establish `NodeDepthPlan`, including the existing check and IIR ownership,
   before applicable static node pruning. Scope disallows proof reuse where
   required. Ordinary raw HCE/trends stay distinct from searched bounds.
3. Run eligible node-level proof/pruning consumers. Each returns its own
   producer and searched horizon; none masquerades as ordinary exact search.
   Null verification uses the restored position and a scoped null restriction.
4. Select legal moves using accepted live staging. Record selected ordinal
   separately from the count incremented only immediately before recursion.
   Resolve singular evidence for the eligible TT move without recursively
   invoking the same exclusion policy. A pending proof grants no extension.
5. Make the move when child check state is required, compute the final
   `MoveDepthPlan`, then commit any shallow omission. A tentative pre-make test
   may save arithmetic but cannot omit a move until all exemptions are known.
   Every make is undone, including omissions and cancellation.
6. Search at the planned probe horizon. A reduced result above alpha requires
   the planned full-horizon null-window verification; a PV result inside the
   window then receives the required full-window PVS search. Probe failure
   remains selective evidence, not a verified full-depth win.
7. Undo, classify the final outcome, update eligible feedback once, update PV
   only with appropriate authority, and store TT only under its source/scope
   predicate. A completed root iteration commits once; aborted aspiration or
   partial root work cannot replace the retained completed result.

For an ordinary move, in signed ply arithmetic:

```
base_child = active_node_depth - 1
verification = base_child + admitted_move_extension + admitted_child_check
probe = verification - proposed_reduction
```

Clamp only at the dispatcher boundary to the existing legal ply capacity;
non-positive depth dispatches qsearch under its existing check/evasion policy.
The initial core permits nonnegative reductions only and clamps probe no deeper
than verification. Its `prune_depth` is the finalized prospective probe horizon
clamped to zero for shallow tests. Verification never shrinks because a reduced
probe scored well. At ply capacity the existing safe terminal/evaluation exit
wins over extension arithmetic. Null and same-position verification have their
own constructors: a verification does not consume a fictional played move.

Entry and child check extension are two descriptions of the same grant, never
two grants. In 9, the observational legacy adapter records existing wrapper
behavior without moving it. The core's explicit dispatch must carry an
already-accounted check grant so the child wrapper cannot add it again. In
particular, depth-zero checking children retain the accepted extension/evasion
semantics. Singular plus check extensions are bounded by the same capacity;
changing the accepted forcing eligibility or consecutive-extension policy is
not hidden inside this representation change.

The current ordinal is retained by 9's legacy view. The core uses selected
ordinal for its declared reduction surface and actually-searched count for
fallback and sibling feedback. Do not substitute one count for the other.

## Eligibility and authority matrix

This freezes the initial candidate envelope; broader classes need a new ticket.
An alpha-beta exact result means exact within the engine's selective policy,
not a proof that omitted chess continuations cannot matter.

| Consumer | Required / excluded evidence | Result and publication authority |
|---|---|---|
| Mate windows | Non-root legal ply bounds; reached draw/checkmate and mate normalization preserved | Bound from the tightened window; no heuristic history sample or fabricated PV. Root completion remains ordinary completed-root logic. |
| Ordinary TT | Authenticated compatible source/depth/bound, normalized score, existing rule/history guards; no restricted/exclusion leakage | Cutoff only under its predicate. Static refinement additionally requires ordinary compatible score/direction. Exact does not imply PV origin. No new TT format in 9/initial core. |
| LMR core | Non-root non-check, quiet non-promotion, non-checking, not singular-extended; protect first actually searched move and first PV move | Probe fail-low may remain selective. Any alpha rise must pass full planned verification before winner/PV/full-depth feedback authority. Capture/evasion/check LMR stays unchanged/off. |
| LMP / quiet futility | Non-root non-PV non-check ordinary node, ordinary score window, quiet non-promotion non-checking move, at least one legal move actually searched | Omission only, not terminal truth. Shared prospective depth; preserve TT/forcing exemptions. No new independent history-pruning switch. |
| Main SEE | Existing eligible move classes with promotions, checks/evasions and decisive-window safeguards; candidate changes only its depth input | Failed threshold permits selective omission after legal/check safeguards, never a searched failure. No capture-futility addition. |
| Check / singular / IIR | Keep accepted eligibility; singular needs legal compatible ordinary TT and completed same-position exclusion evidence | Explicit admitted depth once. Exclusion evidence selects extension; it is not an unrestricted TT score or history winner. |
| Null / verification | No PV/check/consecutive-null or unsafe pawn/zugzwang case; decisive scores excluded; restored-position verification and scoped null suppression | Null probe is speculative. Completed real-move verification carries its actual horizon/source, not nominal full-depth exact authority. Dynamic reduction and suppression scope are one later package. |
| ProbCut / razoring | Ordinary eligible window and phase-specific tactical/qsearch verification; no in-check or decisive shortcut | Keep probabilistic/qsearch producer and horizon. TT reuse needs explicit source/depth compatibility, not numeric fail-high alone. Separate later candidates. |
| Upcoming repetition | Proven legal reversible move plus qualifying root/search history; null, rights, EP and check legality accounted for | History-local lower bound toward draw, not forced exact draw; no reusable TT cutoff/store or history training from that local bound, including dependent ancestors. |
| Qsearch | Preserve MAN-S34 legal witness, complete evasions, tactical partition/order, check and promotion safeguards | Stand-pat differs from searched tactical evidence; raw cached eval remains raw; main-search full-depth history cannot train from depth-zero results. |
| Optional correction | Ordinary paired raw HCE and eligible completed searched target; no draw/mate/TB/null/exclusion/abort | Correction remains separate from raw cache; only explicitly qualified consumers may read it. No permission to enable MAN-S25. |

TT storage must distinguish a shorter searched horizon from omission of siblings
at the requested horizon. Neither is converted to an unrestricted proof by
renaming the route. Step 9 records these facts but leaves the existing storage
policy exact; any changed TT authority/encoding requires a separately frozen
contract before the dependent playing package, not an incidental substrate fix.

### Which certificate describes a completed node

Amended 2026-09-12 by the Step-6.5.9 third repair, after the repeated authority
review found the rule implicit. The bound that a node returns decides which
certificate describes it:

- **Fail-high.** The cutting move alone establishes the bound, so the winner's
  certificate applies: its producer, horizon and verification state.
- **Exact.** The winning move establishes the value. Its producer, horizon and
  verification state apply. Restrictive scope and omitted siblings stay
  aggregated across searched siblings, because those describe the regime the
  node ran in rather than the value it returned.
- **Fail-low.** No move reached alpha, so the claim rests on every searched
  sibling and the weakest one bounds it: aggregate horizon, scope, verification
  and omission.

A sibling searched only as a reduced probe is reported as `reduced_siblings`,
never by shortening the winner's horizon. This follows the authority rule above:
an ordinary completed search establishes an outcome for its own horizon, and
the rejected alternative -- a subtree minimum -- made a node's horizon one plus
the shortest searched path to a quiescence leaf through any sibling anywhere
below it, which is not a statement about the returned value at all.

**Measured consequence, recorded so 6.5.10 does not assume otherwise.** The
correction does not make the paired relation depth-stratified. Counting nodes
reaching the shadow admission predicate, enabled build, depth-9 search of
`r2qr1k1/p4ppp/1pn1bn2/2b1p3/4P3/1BN1BN2/PPP2PPP/R2QR1K1 b - - 6 10`:

| Node depth | Admitted before | Admitted after | Refused after |
|---|---|---|---|
| 1 | 0 | 0 | 6895 |
| 2 | 3037 | 2906 | 1130 |
| 3 | 25 | 37 | 498 |
| 4 | 61 | 64 | 20 |
| 5 | 0 | 2 | 22 |
| 6-7 | 0 | 0 | 9 |

Per candidate, the first failing admission condition in that run is the
producer rule in about 90% of refusals, reduced-only verification in about 6%,
horizon in about 3% and restrictive scope in about 1%. The horizon rule was
never the gate. The gate is this ADR's own feedback rule: only a
`full_search`/`pvs_probe` winner trains the relation, which excludes
transposition cutoffs, reduced-search winners and every depth-one node, whose
winning child is a quiescence leaf. The relation is therefore trained mostly at
low remaining depth by construction. Step 6.5.10 must not expect a
depth-balanced sample, and must not read a low deep-node count as evidence that
deep outcomes are unreliable. Widening the producer rule is a separate decision
for the consumer package, not a substrate repair.

## Candidate boundaries and refutation

1. **10.1 complete mate windows:** independent from ordering/depth changes;
   test and qualify separately. MAN-S32 is not automatically promoted or retried.
2. **10.2 shared selective-depth core:** one reduction surface and one prospective
   depth input for existing LMP/futility/SEE, using accepted live history/node/TT
   facts and explicit unchanged forcing ownership. These consumers must agree
   about the move horizon; qualifying only LMR would not qualify that interaction.
   No new feedback, ranking, capture history, aspiration, null, correction or
   singular-proof formulation belongs in the initial package. The richer shadow
   outcomes from 9 remain diagnostic. An independently useful new ordering or
   feedback consumer needs its own frozen follow-on ticket, not silent inclusion.
3. **10.3 window-aware aspiration:** conditional on accepted core, one package
   containing root window production and its actual depth consumer. Reference
   width is frozen from the first finite attempt of that iteration; retry width
   is current, and full-window/no prior ordinary result is explicitly unknown.
   Retries widen the failed side, with bounded recovery to full window. Without
   a distinct populated window/depth relation, defer rather than repeat MAN-R02.
4. **10.4 forcing-policy decision:** review only after accepted core evidence.
   Preserve current checks/singular unless a new relation justifies a separately
   bounded candidate. S31/S33 outcomes do not authorize stripping extensions.
5. **11.1–11.5:** upcoming repetition, null+verification, ProbCut proof reuse,
   singular/IIR review, and verified razoring are separate decisions in that
   order on the actual accepted head. Deferral/rejection is a valid closure.
6. **12:** reliability/correction is conditional, not mandatory feature coverage.
   It requires systematic held-out error and a new populated consumer relation.

Every playing package gets its own prospective membership, feature-off
reconstruction, deterministic/safety gates and one final registered 1T SPRT;
no games or registrations are authorized by this design. The trusted unchanged
harness needs setup-only verification, not a pilot. H0/cap/maintainer stop does
not authorize tuning or automatic retry. A rejection forces re-derivation of
dependent packages against actual production before implementation.

Refute the core on authority/legality failures; inspect legal tactical changes,
ordinary-position depth curves and per-position elapsed tails rather than
rejecting every different score as a bug. Exclusive node attribution can locate
work; inclusive counters cannot be summed as unique work or CPU time. Compare
nodes, elapsed and NPS separately. No target re-search percentage proves safe
pruning and no node saving proves Elo. Board parity remains an independent open
cost target owned by 6.5.13/6.5.15; this design cannot promise either final target.

## Required edge cases and independent gates

| Cases | Invariant / oracle |
|---|---|
| Checkmate at rule-fifty boundary; stalemate; quiet-only mobility; empty tactical set | Independent complete legal generation and chess terminal rules take precedence over pruning/stand-pat. |
| Depth zero in check, checking child, singular checking move, maximum ply | Exactly one admitted check grant, no unsigned underflow or out-of-range stack access; complete legal evasions and bounded depth. |
| EP discovery/pin, quiet/capture underpromotion, castling check | Legal generator and made-child check state establish move class/exemptions; exact full state restoration. |
| Mate at different plies, tight/crossing windows, TT mate round trip | Independently derived legal mate-distance bounds; correct bound, no invented PV, root mate completion unchanged. |
| Absent/illegal TT move, old/shallow/decisive/nonordinary TT score, exact non-PV record | Separate move/refinement/cutoff eligibility; unknown PV-origin remains unknown; source restrictions survive read and negation. |
| Reduced fail-low, alpha rise then verify fail-low, cutoff then PV re-search | Scripted search outcomes exercise orchestration independently of the reduction formula; no probe-only winner or double feedback. |
| Pruned siblings before a late candidate; fail-low node; first legal fallback | Selected ordinal differs from actually-searched count; unsearched moves never train; omission never fabricates mate/stalemate. |
| Exclusion and null verification re-entering same ply; cancellation at each stage | Position, stack, path accounting, suppression scope and publication restore exactly. |
| Root/null history break, repeated continuation key, saturation/reset | Paired outcome/support update once; shared-table aliases are not independent confidence; production adapter remains exact. |
| Restricted roots, aspiration retries, stop/ponder, helper result | Legal retained root result and once-only completed iteration remain worker-zero authority; no restricted/history-local TT leakage. |
| Zugzwang, fortress, only move, reversible cycle with rights/EP differences | Independent real-move/history walk; failed null verification stays in the safety corpus; possible draw differs from forced draw. |
| Raw/refined/corrected HCE with draw/mate/TB values | Only ordinary compatible evidence drives/trains permitted consumers; raw cache identity is preserved. |

Step 9 must pass production-on/diagnostic-off exact nodes, legal PV, result and
fingerprint `775451`, plus enabled-observation equivalence, focused property
tests, allocation/lifetime checks and its owning safety gate. A legal mismatch
is still outside its behavior-neutral scope: diagnose before reclassifying or
proposing a playing candidate. Documentation-only Step 8 runs policy and diff
checks, not builds of engine variants, benchmarks or games.
