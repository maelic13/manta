# ADR-0071 — Measured games end only by the rules of chess

Accepted 2026-09-12 by maintainer decision. Supersedes the `strength-v1` and
`strength-v2` adjudication profiles for every future Manta measurement.

## Context

Every Manta strength measurement to date ran under an adjudication profile
inherited with the ported fastchess harness: two-sided resignation at
`600` cp held for three moves, a draw rule at `10` cp held for eight plies from
move 40, and, for data generation, a `200`-move cap. The profile existed to cut
wall time and draw rate so an SPRT resolves in fewer games.

The cost was never priced. An adjudicator is a second engine passing judgment
on the one under test, and it is neither validated nor measured. Worse, the
positions it truncates are not a random sample: resignation ends games exactly
where conversion technique decides the point, and the draw rule ends them
exactly where fortress recognition, zugzwang and long technical endings decide
it. Those are phases where two engines differ most, and the truncation prices
them by an evaluation whose quality is the thing being tested.

The effect is visible in Manta's own record. ADR-0045 measured 48% of games
ending by adjudication and observed that `resign=600/3` removes the endgames
where mate-distance and clock behavior matter. ADR-0062's SPSA log counted
32,320 resignation adjudications against 48 stalemates. Step 6.5.10.1 then
produced the clearest case: a mechanism that provably reduces mate-proving work
by `88%` on mate positions was measured as neutral, because the gate resigns
those games long before a mate is played out. The instrument could not see the
mechanism it was asked to judge.

## Decision

No adjudication anywhere. A measured game ends only by the rules of chess:
checkmate, stalemate, the fifty-move rule, threefold repetition or insufficient
material. This holds for SPRT, SPSA, data generation and any future harness.

- `tools/harness_common.ps1` owns the contract. `Get-GameEndProfile` returns the
  named `natural-v1` profile with no thresholds, and `Get-GameEndArgs` returns
  an empty argument list so a caller cannot reintroduce `-resign`, `-draw` or
  `-maxmoves` without editing the contract.
- `tools/sprt.ps1`, `tools/step_5_1_fastchess.ps1` and `tools/datagen.ps1`
  consume that contract. Data generation moves to the `datagen-v2` profile for
  the same reason: a label produced by an adjudicator teaches the network the
  adjudicator's opinion, not the game's result.
- The weather-factory SPSA patch already removed adjudication; that is now the
  project rule rather than a tuning-specific exception.
- Every run manifest records `adjudication: none` and the game-end profile name,
  so no future reader can mistake which instrument produced a verdict.

## Consequences

**Comparability breaks at this commit.** Every Manta verdict before it —
MAN-S30, MAN-S34, MAN-S35, the MAN-C cumulative runs, every SPSA fit — was
measured with adjudication. Those results keep their original conditions in
`EXPERIMENTS.md` and are not restated. A new result is not directly comparable
with an old one, and a candidate is never re-gated against a differently
adjudicated baseline.

**The instrument needs re-qualification.** Removing adjudication changes an
operational boundary of the trusted harness, so the standing permission to
proceed from a setup-only check to a registered SPRT does not carry over. The
documented instrument check is `tools/sprt.ps1 -Mode calibrate`, an identical-
binary null match whose entire 95% nElo interval must fall inside `[-5,+5]`
with zero anomalies. Run it before the next registered candidate.

**Games are longer and draws more frequent.** Expect materially lower games per
hour and a higher draw rate, so an SPRT needs more wall time and probably more
games for the same resolution. Game budgets and time estimates derived from
adjudicated runs are obsolete. This is the price of measuring the whole game,
and it is accepted.

**Time-forfeit policy is unchanged.** Completed time losses remain fatal unless
clock policy is the measured subject, and every other engine, protocol,
affinity or infrastructure fault stays fatal.
