# Manta Experiment Ledger

This file is the compact decision index for tuning, playing-strength and
performance evidence. Exact registrations, hashes, raw artifacts and detailed
reasoning remain in the cited ADRs, `tools/results`, Git history and retained
run directories.

## Evidence rules

- Register the candidate, baseline, hypothesis, time/thread/hash/opening setup,
  seed, bounds, game cap, anomaly policy and stop rule before a playing run.
- Only a clean H1 SPRT promotes a prospectively registered candidate. H0 rejects;
  a game-cap stop is unresolved and does not promote.
- A post-result maintainer waiver is recorded explicitly and never rewritten as
  a clean prospective gate.
- Static tests, loss, fixed-node quality, speed and fingerprints are diagnostic
  filters. They do not prove playing strength.
- During Phase 6.5, every retained production-executable candidate—including
  behavior-identical speed and PGO work—requires its own clean 1T H1. Tests,
  documentation and disabled diagnostics are not production candidates.
- Phase-6.5 games run on the separate designated Ryzen 9 5950X. Registration
  and returned evidence bind source/archive identity, candidate/baseline binary
  hashes, Zig/build options, feature switches, runner/book hashes, setup-only
  output, manifest, log, PGN and checkpoint. Development-machine games cannot
  promote a candidate.
- SPSA pilots establish coordinate activity only. Promote only a complete rounded
  fit after its own clean game gate.
- Do not repeat a rejected mechanism without the recorded trigger or genuinely
  new evidence.

## Manta 1 production state

| Area | Released state | Evidence |
|---|---|---|
| Classical evaluation | MAN-E19 fitted structural HCE | Accepted H1 over the prior evaluator after 1,932 scored games at `+50.09 +/- 15.49` nElo; ADR-0056 |
| One-thread search | MAN-S29 complete rounded search fit | Accepted H1 over MAN-S19 after 4,596 games at `+22.49 +/- 10.04` nElo; ADR-0063 |
| Clock policy | MAN-T05 complete rounded time fit | H1 after 4,188 games at `+24.48 +/- 10.52` nElo, accepted by explicit maintainer judgment despite the wrapper's prospective zero-timeout rejection; candidate had one completed time forfeit and baseline five |
| SMP | MAN-R03 main-authoritative lazy SMP | 4T versus 1T accepted H1 after 194 games at `+187.72 +/- 48.89` nElo; ADR-0064 |
| Move ordering | MAN-S30 live-history staged picker | Accepted H1 over MAN-S29 after 8,752 games at `+13.19 +/- 7.28` nElo; ADR-0035 |
| Deterministic identity | One-thread depth-6 bench | `775,451` nodes |

These measurements establish promotion decisions under their registered
conditions. Small decisive samples, especially cumulative and 4T-versus-1T
runs, are not precise ratings and cannot attribute value to individual bundled
components.

## Cumulative release evidence

| ID | Comparison | Verdict |
|---|---|---|
| `MAN-C01` | Final Phase-5 MAN-E19/MAN-S29 versus corrected Phase-5.0, 1T, `3+0.03`, `[5,20]` | Accepted H1 after 126 games at `+459.61 +/- 60.66` nElo without anomaly. This proves a material cumulative Phase-5 gain, not a precise 460-nElo rating. |
| `MAN-C02` | Final MAN-T05 at 4T versus final Phase-5 MAN-S29 at 1T, `3+0.03`, `[5,20]` | Accepted H1 after 150 scored games at `+305.51 +/- 55.60` nElo without anomaly. This closes Phase 6 but does not isolate UCI, time or SMP value. |

Raw cumulative evidence is retained under
`tools/results/sprt_MAN-C01-*` and `tools/results/sprt_MAN-C02-*`.

## Accepted development lineage

| ID | Decision retained in production |
|---|---|
| `MAN-S15` | Pre-NNUE search baseline after the rejected singular-extension candidate |
| `MAN-S17` | Continuation-history evidence |
| `MAN-S19` | Static-eval, TT and qsearch synchronization; final pre-fit search head |
| `MAN-S22` | Behavior-identical convergence checkpoint |
| `MAN-E19` | Completed classical evaluator coverage plus constrained fit |
| `MAN-S29` | Complete ten-coordinate search SPSA bake |
| `MAN-R03` | Main-authoritative lazy SMP pool |
| `MAN-T05` | Complete six-coordinate integrated time-management fit |
| `MAN-S30` | Live-history staged move picker |

Acceptance of a bundle does not establish that every included term helped.
Frozen baselines exist only for reconstruction and do not remain runtime
selectors unless a requirement explicitly needs them.

## Tuning history

| ID | Scope and outcome |
|---|---|
| `MAN-S26` | Six-coordinate, 128-iteration search sensitivity pilot completed 4,096 games; pilot theta was not promoted. |
| `MAN-S27` | Withdrawn before running because it omitted live interacting search/history controls. |
| `MAN-S28` | Ten-coordinate search SPSA completed 2,000 iterations / 64,000 games; every coordinate remained active and away from rails. |
| `MAN-S29` | Sole rounded MAN-S28 bake; accepted H1 and became production. |
| `MAN-T01` | Colosseum time pilot invalid at iteration zero after engine faults; withdrawn. |
| `MAN-T02` | Weather Factory replacement invalid because its recovering runner committed across an infrastructure stall; theta rejected. |
| `MAN-T03` | Clean replacement prepared, then withdrawn unrun. |
| `MAN-T04` | Six-coordinate Weather Factory time fit completed 1,000 iterations / 32,000 games with final floating theta `1034/957/4291/1036/1049/1046`. |
| `MAN-T05` | Sole nearest-integer time bake, accepted by the documented maintainer judgment and made production. |

The time-sensitivity runner scores completed time forfeits as chess outcomes
because clock safety is part of that fit. Crashes, disconnects, illegal moves,
affinity faults, incomplete results and nonzero exits remain fatal. Other SPSA
groups retain strict timeout handling.

## Phase 6.5 search evidence

| ID | Candidate and hypothesis | Registered gate | Result |
|---|---|---|---|
| `MAN-S30` | Phase-6.5.1b live-history staged picker against production MAN-S29. Delaying non-tactical quiet generation and consuming descendant-completed worker-local history will reduce abandoned generation and improve time-controlled play without changing chess or evidence authority. | Candidate A, 1T `3+0.03`, Hash 64 MiB, concurrency 14, paired randomized UHO, `strength-v2`, normalized `[1,5]`, alpha/beta 0.05, 16,000-game cap, seed `1445075129` | Accepted H1 after 8,752 games at `+13.19 +/- 7.28` nElo (`+8.93 +/- 4.93` Elo, LLR `2.95`); promoted to production |

`MAN-S30` ran on the separate designated Ryzen 9 5950X from candidate
fingerprint `775,451` against baseline `799,610`, both clean native ReleaseFast
non-PGO Zig 0.16.0 builds of `72732d6` differing only in
`-Dlive-history-staging`. The run crossed the H1 boundary in `01:25:42`:
`2,308` wins, `2,083` losses and `4,361` draws for `4,488.5` points (`51.29%`),
`Ptnml(0-2) = [210, 1020, 1731, 1165, 250]`, pairs ratio `1.15`, LOS `99.98%`.
Artifacts are in `zig-out/fastchess/MAN-S30-sprt-20260907_212733`. The measured
interval is a rating estimate under these registered conditions only, and the
accepted mechanism is the whole staged picker rather than any single stage.

The bridge nevertheless rejected the run under its registered zero-timeout rule:
four completed games ended in time forfeit, three lost by baseline MAN-S29 and
one by the candidate, with zero crashes, disconnects, illegal moves or affinity
faults. The maintainer accepted the result by explicit judgment. Independent
reconstruction of the four games from the PGN move times supports that
judgment and finds no clock defect:

- Every forfeit occurred late in a long game in which **both** engines had
  already spent their base clock down to tens of milliseconds, which is the
  expected terminal state of sudden death plus a 30 ms increment. Across the
  whole run about `22%` of game sides dip below 20 ms of remaining time at some
  point, at nearly identical rates in the two arms.
- No move in any forfeit game took longer than `0.35 s`, and the largest single
  move in the entire run was `0.505 s`. There is no overspending spike; the
  engine keeps two Move Overheads (`20 ms`) unspent and the controller allows a
  further `20 ms` margin, so a forfeit needs an external stall beyond roughly
  `40 ms`.
- Four failures across roughly `400,000` played moves is about one in
  `100,000`, is spread over both arms and is consistent with host scheduling
  pressure at concurrency 14 rather than an allocation error.
- The four games contribute a net two-game advantage to the candidate, against
  its `225`-game win-loss lead. They cannot explain the verdict.

This remains a post-result evidence waiver on the same footing as `MAN-T05`,
not a prospective precedent. No time-management parameter, `Move Overhead`
value or reserve was changed in response; any such change would be a playing
candidate needing its own gate. The operational lesson is that the game host
must stay otherwise idle for the registered rule to hold.

## Rejected or parked hypotheses

| ID or area | Verdict | Reopen only when |
|---|---|---|
| `MAN-S14` singular-extension family | Rejected and disabled | A new, independently justified extension authority exists |
| `MAN-S16` capture history | Rejected and disabled | New evidence identifies the original missing relation |
| `MAN-S18` LMR synchronization | Rejected | Search architecture changes invalidate the old result |
| `MAN-S20` main selectivity | H0; disabled | A new producer/consumer relation changes the hypothesis |
| `MAN-S21` extension/depth authority | Exhausted cap without H1; disabled | Materially new evidence and a newly registered candidate exist |
| `MAN-S23` / `MAN-S24` correction selectivity | Deterministically refuted / never opened | A valid structural producer first passes its own gate |
| `MAN-S25` pawn-structure correction history | H0; archived default-off | New evidence changes the producer or authority contract |
| `MAN-E20` context-weighted space | Static fit reversed sign and missed validation floor | A different chess mechanism and label-quality case are established |
| `MAN-E21` shelter-moderated king danger | H0 at `-9.31 +/- 7.98` nElo | A materially different coupling is derived |
| `MAN-R01` root-uncertainty time consumer | H0; disabled | Root evidence or time architecture changes materially |
| `MAN-R02` stability-gated aspiration | 16,000-game cap without H1; disabled | Evaluator/search head changes make the old gate stale |
| Colosseum | Parked by maintainer direction | The maintainer explicitly authorizes re-evaluation |
| Additional classical HCE fitting | Closed in the normal path | Serious NNUE retries fail and Phase 11 is explicitly entered |
| Additional pre-NNUE search/time SPSA | Closed | Phase-9 co-adaptation freezes new interacting consumers and justifies a fit |

## New experiment template

Before creating a configuration or binary, record:

1. ID, owning GUIDE/PLAN step and one mechanism-level hypothesis.
2. Exact candidate and baseline revisions, binary hashes and switches.
3. Chess/search producer, transformations, consumers and refutation evidence.
4. Host, concurrency/affinity, time control, threads, hash, openings and
   adjudication.
5. SPRT bounds/alpha/beta/cap/seed, or SPSA coordinates/ranges/schedule/resume.
6. Engine-fault, clock-forfeit and infrastructure-anomaly policy.
7. Expected and worst-case time/storage and the maintainer-run command.
8. Result, independent reconciliation, artifact hashes and the precise decision.
