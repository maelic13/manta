# HCE coverage against the pinned classical reference

Manta's evaluator compared term by term with the pinned final pre-NNUE
Stockfish snapshot recorded in [`config/eval-reference.json`](../config/eval-reference.json),
commit `9587eeeb5ed29f834d4f956b92e0e732877c47a7`.

This is a **coverage map, not a parity target**. It records which chess concepts
the reference prices that Manta does not, so the gaps can be selected
deliberately instead of discovered late. Manta implements every adopted concept
as original Zig from its own derivation; reference code, constants, formulas and
traces are not copied and remain non-goals. A concept listed as missing is a
candidate, not a commitment: each still needs its own chess rationale and
evidence before it enters the evaluator.

Status values are `present`, `partial` (the concept exists but the reference
prices strictly more of it), `missing`, and `archived` (implemented, gated,
rejected, retained default-off as refutation history).

## Material and phase

| Concept | Manta |
|---|---|
| Piece values, piece-square tables, phase tapering, tempo | present |
| Nonlinear material imbalance | archived — rejected `MAN-E07` at `-7.00` Elo |
| Endgame scale factors | present for exact signatures in Step 5.3.13; broad MAN-E05 scaling remains archived after rejection at `-16.32` Elo |
| Value-returning endgame recognisers (`KXK`, `KBNK`, `KNNK`, `KNNKP`, `KPK`, `KQKP`, `KQKR`, `KRKB`, `KRKN`, `KRKP`) | present — Step 5.3.15R.4 replaces KPK heuristics with exact WDL and makes the remaining convertible classes geometry/tempo-aware; values remain ordinary-band only |
| Scale-factor endgame recognisers (`KBPKB`, `KBPKN`, `KBPPKB`, `KPKP`, `KRPKB`, `KRPKR`, `KRPPKRP`) | present — Step 5.3.15R.4 combines exact signatures with pawn/king geometry, race distance and tempo |
| Exact KPK win/draw classification | present — generated 196,608-state normalized bitbase; Syzygy and terminal authority remain search-owned |

## Pawn structure

| Concept | Manta |
|---|---|
| Doubled, isolated | present — Step 5.3.15R.1 assigns the doubled penalty only to rear pawns and makes doubled/isolated/backward ownership disjoint |
| Backward, plus backward-on-open-file | present — implemented in Step 5.3.10; ownership made disjoint in Step 5.3.15R.1 |
| Connected pawns | present — weighted by rank, phalanx, opposition and support count in Step 5.3.10 |
| Weak lever (attacked by two enemy pawns, defended by none) | present — Step 5.3.10 |
| Weak unopposed pawn (no enemy pawn on its file) | present — Step 5.3.10, charged to isolated pawns only |
| Blocked pawn on the fifth or sixth rank | present — Step 5.3.10 |
| Pawnless flank | present — Step 5.3.12, charged inside king safety as the reference does |

## Passed pawns

| Concept | Manta |
|---|---|
| Bonus by advancement rank | present |
| Bonus by file | present — Step 5.3.10 |
| Blocking square occupied, attacked or defended | present — Step 5.3.10 |
| Proximity of *both* kings to the blocking square | present — Step 5.3.10, endgame only and scaled by advancement |
| Whole push path free of enemy attack | superseded — Step 5.3.15R.1 replaced the lossy boolean with per-square evidence |
| Per-square defended and unsafe counts along the path | present — Step 5.3.15R.1 counts every attacked and defended route square while retaining immediate stop-square specialization |
| Candidate and leverable passers, not only fully passed pawns | present — Step 5.3.15R.1 requires no same-file stopper, every adjacent stopper immediately levered, and at least one distinct friendly pawn per stopper |

This was the single largest structural gap. Step 5.3.10 closed most of it and
Step 5.3.15R.1 closed the two remaining rows with cached pawn-only candidate
classification and attack-map path evidence.

## Piece activity

| Concept | Manta |
|---|---|
| Mobility by piece type | present — Step 5.3.15R.2 uses a distinct mobility area and restricts absolutely pinned pieces to their legal king ray |
| Shared attack legality versus explicit x-ray geometry | present — Step 5.3.15R.2 keeps impossible pinned attacks out of mobility, passer, threat and king consumers; named x-ray terms derive raw geometry separately |
| Knight outpost | present — Step 5.3.11 replaced the current-attack test with a pawn-span test, so a square an enemy pawn can still advance to attack is no longer an outpost |
| Bishop outpost, bad outpost, reachable outpost | present — Step 5.3.11 |
| Minor piece behind a pawn | present — Step 5.3.11 |
| King protector (minor's distance to its own king) | present — Step 5.3.11 |
| Bishop pair | present |
| Bishop blocked by pawns on its own square colour | present — Step 5.3.11 |
| Bishop x-ray through pawns | present — Step 5.3.11 |
| Bishop on a long diagonal through the centre | present — Step 5.3.11 |
| Cornered bishop | rejected — Chess960-specific and inapplicable while Manta supports standard chess only |
| Bishop attacking the enemy king ring | present — Step 5.3.11 |
| Rook on open and semi-open file | present |
| Rook on the seventh rank | present — a deliberate Manta term the reference does not carry separately |
| Rook on the enemy queen's file | present — Step 5.3.11 |
| Rook attacking the enemy king ring | present — Step 5.3.11 |
| Trapped rook behind an uncastled king | present — Step 5.3.11, the evaluator's first and only castling-rights consumer |
| Weak queen (discovered-attack exposure) | present — Step 5.3.11 |
| Queen infiltration on the enemy half | present — Step 5.3.11 |

## Threats

| Concept | Manta |
|---|---|
| Threat by minor, by rook, by king | present — Step 5.3.15R.2 excludes pawn-protected and unmatched multi-defended targets |
| Hanging piece | present |
| Threat by a safe pawn | present — Step 5.3.12 |
| Threat by a pawn push | present — Step 5.3.12 |
| Slider on the enemy queen | present — Step 5.3.12 |
| Knight on the enemy queen | present — Step 5.3.12 |
| Restricted piece (enemy defence we deny) | present — Step 5.3.12 |
| Weak queen protection | present — Step 5.3.12 |
| Central, pawn-supported, material-sensitive space | present — Step 5.3.15R.2 replaces the broad whole-home-half count |

## King safety

| Concept | Manta |
|---|---|
| Shelter strength by rank and king-file geometry | present — Step 5.3.15R.3 distinguishes the king file from neighbouring files, including edge-file kings |
| Shelter at a legal future castling destination | rejected — the exact legal-reachability variant measured -44.8% from the 5.3.9 throughput head, outside the 40% allowance; current-square shelter remains authoritative |
| Storm, blocked and unblocked | present |
| Open and semi-open file beside the king | present |
| Attacker count and weight, weak ring squares | present — Step 5.3.15R.3 includes legal pawn attackers in both count and weight |
| Safe and unsafe checks by piece type | present |
| Attacker and defender queen availability | present — Step 5.3.15R.3 adjusts bounded danger without creating a terminal claim |
| Endgame king-to-own-pawn proximity | present — Step 5.3.15R.3, active only at four or fewer non-pawn/non-king pieces |
| Pieces pinned in front of the king (blockers) | present — Step 5.3.12 |
| Sustained attack on the king's flank | present — Step 5.3.12 |
| Pawnless flank | present — Step 5.3.12 |

## Winnability

| Concept | Manta |
|---|---|
| Fifty-move allowance scaling | present — a Manta term the reference does not carry |
| Initiative / complexity from passer count, total pawns, pure-pawn ending, king outflanking, pawns on both flanks, king infiltration and almost-unwinnable material | present — Step 5.3.15R.4 closes total-pawn and pawn-ending facts; adjustment remains bounded and endgame-only |

## Formulation gaps found after coverage closed

Coverage asks whether a concept is priced. It does not ask whether it is priced
the way the reference prices it. A 2026-08-23 re-audit against `9587eeeb` found
three terms that are present and correct as chess but carry a strictly simpler
functional form than the reference. None is a missing concept, none is a defect,
and none may be changed while the Step-5.3.16 gate is open.

| Term | Manta | Reference | Consequence |
|---|---|---|---|
| Space | `space_bonus * (safe + supported)`, gated by a binary `space_material_floor` | `bonus * weight * weight / 16`, where `weight` counts pieces and blocked pawns | Manta cannot say that space is worth more with more pieces on and a more blocked centre. One flat coefficient must average every context. |
| King danger vs shelter | shelter is added to the king score; danger is squared separately | shelter reduces `kingDanger` *before* it is squared | Good shelter offsets danger instead of mitigating it, so a well-sheltered king with three attackers pays the full square-law penalty. |
| Space `supported` lane | squares in the safe area attacked by our own pawns | squares *behind* our own pawns, up to two ranks back, that no enemy piece attacks | Different chess claims. Manta prices pawn control; the reference prices sheltered depth. |

The space finding had an observable fingerprint in the original fit:
`space_bonus` needed a positive semantic clamp while the data wanted it
negative. MAN-E20 tested whether material phase and locked central pawns were
the missing context. Its candidate-only fit again selected a negative optimum
and improved validation only `0.000013762` against its `0.000200` floor, so that
specific explanation is refuted before games. Space remains a priced concept;
the result does not license another magnitude formula or coefficient retry.

Two cautions apply to this work. `MAN-E05` and `MAN-E07` were
both reference-family concepts implemented faithfully, and both lost games here
at `-16.32` and `-7.00` Elo. Reference fidelity is a hypothesis, not an
improvement. And these three changes alter what fitted coefficients consume, so
they remain separate playing hypotheses rather than a reference-parity bundle.
ADR-0058's first candidate, MAN-E20 context-weighted space, is statically
refuted and remains off; schema v3 survives as behavior-neutral cleanup.

ADR-0059's second candidate, MAN-E21 shelter-moderated king danger, passed its
default-off deterministic qualification but its registered `[1,5]` SPRT
accepted H0 at `-9.31 +/- 7.98` nElo. It remains off without retry. It retained
the existing direct shelter score and every coefficient.
After the existing two-attacker threshold, signed middlegame shelter changes
raw danger from `D` to `max(0, D - shelter)` before squaring. This is a
categorical nonlinear consumer, so it receives deterministic properties and
one game gate rather than a static coefficient fit. If promoted, the affected
shelter coefficients' fitting status must be reviewed before any later fit.
The supported-lane replacement remains excluded. MAN-E20 and MAN-E21 close
Step 5.4.3 without a promoted formulation; exact MAN-E19 remains production.

## Reading this table

Roughly twenty-five priced concepts were missing or partial when this table was
first produced. Steps 5.3.10–5.3.15R have now closed every useful standard-
chess row or recorded an explicit rejection. Coverage parity is therefore
closed for the HCE freeze; it remains a concept audit, not strength evidence.

Two corrections worth keeping visible. An external maturity audit found that
the pawnless flank, listed as missing here, had been scheduled into no step at
all — the coverage map recorded the gap and the plan silently dropped it. It is
now owned by 5.3.12. A coverage map is only useful if every row is either
scheduled or explicitly rejected, so that check belongs in the step that reads
this table, not in the reader's memory.

And the first version of this table recorded backward pawns as present. They were not. `backward` and `backward_open` had
been declared with a full rationale in Step 5.3.3 and never consumed by any
evaluator path, and the audit read the parameter list instead of the consumers.
`scale_draw` is still declared and unused inside the archived MAN-E05 scaling.
Audit what the code reads, not what it declares.

Two cautions carry equal weight. Coverage is not strength: `MAN-E05` and
`MAN-E07` were both reference-family concepts and both lost games here, because
a term must fit the evaluator it joins, not the one it came from. And the
reference's values are the product of a long automated fit, so adopting its
concepts with hand-set constants reproduces its structure without its
calibration — which is exactly what Step 5.3.16 exists to repair.
