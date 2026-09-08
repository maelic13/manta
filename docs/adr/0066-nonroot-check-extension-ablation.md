# ADR-0066: Non-root blanket check-extension ablation

## Status

Rejected. `MAN-S31` ran its registered gate and the maintainer stopped it by
judgment at 7,958 games and `-3.08 +/- 7.63` nElo, LLR `-1.60` of `-2.94`, with
no anomaly. Production remains MAN-S30 at `775,451` nodes and the switch stays
archived with blanket extension on. The isolated formulation is unpromoted,
not statistically refuted. Step 6.5.3 is closed; ADR-0068 supersedes follow-on
sequencing and assigns a distinct policy review to reworked Steps 6.5.8–6.5.10.

## Mechanism and boundary

The hypothesis is that automatically spending one extra ply at every checked
interior node costs more time than its tactical protection earns. Step 6.5.2
found short check chains (maximum five), so this is a bounded search-allocation
question. Reduced node counts cannot establish a playing gain.

`-Dnonroot-check-extension=false` suppresses only the check increment at
`ply > 0`. The default is true; the existing `check_extension` whole-producer
ablation remains independent. Checked-root extension is retained because the
owning plan permits changing only non-root allocation. Nominal completed-root
depth stays fixed. No evasion/check LMR or shallow-pruning exemption changes
are included; those would require separate evidence and playing candidates.

Authoritative board checker state produces the fact. The compile-time switch
gates its transformation into `DepthIntent.extension`. Recursion, horizon-to-
qsearch dispatch, depth-dependent pruning/LMR/IIR/singular/tablebase eligibility,
TT probe/store depth, PV/result evidence and diagnostics consume the resulting
searched horizon. Consequently scores, PV, ordering-history updates and TT
traffic may change legally. Their existing bound/provenance contracts remain:
reduced alpha rises require full-depth verification and speculative evidence
cannot acquire ordinary authority merely through a changed horizon.

Move generation and make/unmake still own castling, en-passant, promotion and
checker correctness. In-check qsearch searches legal evasions without stand
pat; main search still protects evasions and checks from existing reductions
and shallow move pruning. Terminal, repetition/rule-50 precedence, mate-distance
encoding and MAX_PLY are unchanged. Each worker uses the same compile-time
policy and retains its own position/history; no allocation, locks, formatting,
I/O or shared atomics are added. Changed tree shape can change cache pressure
and branch counts; no throughput or multi-thread-strength claim follows.

## Deterministic qualification

Focused properties check that a checked root emits exactly one check increment
per completed iteration while non-checked roots emit none in the candidate;
mate in one, checkmate before rule-50, stalemate and a free queen capture retain
their independently derived outcomes. Restricted promotion, en-passant and
castling roots preserve legal PVs and complete root-state restoration in both
arms. The observation suite checks observer-on/off equivalence and evidence
accounting. The production fingerprint test explicitly selects accepted
features so a candidate build never silently redefines that snapshot.

Required gates: ReleaseSafe full tests (including both-arm properties and UCI
process cases), ReleaseFast full tests, formatting/policy/lint, repeated
candidate bench and explicit production bench, fixed tactical/endgame
observation and the complete 40-position depth-4..12 curve at Hash 64 MiB.
Reported observation timings are instrumentation cost, not throughput.

## Prospective playing registration

Qualification evidence is recorded below; none of it grants promotion.

- Candidate A: MAN-S31, all production defaults except
  `nonroot_check_extension=false`; baseline B: exact MAN-S30 with it true.
- Both: same frozen source, Zig 0.16.0, native ReleaseFast, non-PGO, ordinary
  non-tune build; default MAN-E19, MAN-S29 parameters, MAN-T05 clock and MAN-S30
  picker. Build both natively on the separate Ryzen 9 5950X.
- Checked `tools/step_5_1_fastchess.ps1`, `strength-v2`, randomized paired UHO,
  1T, Hash 64 MiB, 14 games on 14 physical cores, `3+0.03`, existing 20 ms
  controller margin and `Move Overhead=10`.
- Normalized `[1,5]`, alpha/beta 0.05, seed `6533108`, maximum 8,000 pairs /
  16,000 games. Stop at H1, H0, cap, anomaly or 3.5 hours. Only clean H1
  promotes. H0/cap leave production untouched; no automatic tuning or retry.
- Zero timeout/crash/disconnect/illegal-move/affinity/incomplete-score/nonzero-
  exit anomalies. Earlier post-result timeout waivers do not change this gate.
- No pilot: the qualified shared harness, 5950X host, placement, book,
  time control, clock margin, adjudication and anomaly boundary are unchanged
  and already qualified. MAN-S30's retained 4,376 pairs / 5,142 seconds gives
  about 2.61 hours at the 8,000-pair cap, or 3.26 hours with 25% headroom;
  retain the registered 3.5-hour stop.
- Reserve 1 GiB for run artifacts based on retained comparable runs. Keep
  manifest, PGN, console and engine logs under `zig-out/fastchess/MAN-S31-*`.
- The existing bridge has no pair-atomic checkpoint/resume support. Preserve
  interrupted artifacts as incomplete; never splice or resume a different
  invocation into this verdict. A restart needs a new prospective registration.
- Return source revision plus dirty-source content identity (or source archive
  SHA-256), both binary manifests/hashes, Zig/build flags, checked runner/book
  hashes, dry-run output, final manifest/logs/PGN and the
  explicit absent-checkpoint status before a verdict is recorded.

## Maintainer handoff

From the frozen source on the idle 5950X, build the two native arms:

```powershell
./tools/build_test.ps1 -Suffix MAN-S31-base -NonrootCheckExtension:$true
./tools/build_test.ps1 -Suffix MAN-S31-candidate -NonrootCheckExtension:$false
```

Setup only (does not start engines or games):

```powershell
./tools/step_5_1_fastchess.ps1 -Job sprt -RunId MAN-S31 -Candidate ./tools/test_engines/manta-MAN-S31-candidate.exe -Baseline ./tools/test_engines/manta-MAN-S31-base.exe -CandidateName MAN-S31 -BaselineName MAN-S30 -SprtSeed 6533108 -SprtElo0 1 -SprtElo1 5 -MaxGames 16000 -DryRun
```

The final registered run is the same command without `-DryRun`. No pilot is
required. Do not overlap datagen or other timed work.

## Qualification evidence (2026-09-08)

The local default build still gives `775,451` depth-six nodes. The candidate
repeats at `492,469` (two independent bench searches); the 36.49% change is
expected because interior checked nodes no longer add a main-search ply.
It is a playing candidate, not a behavior-identical optimization. The unchanged
root/check/draw contracts passed both-arm properties. ReleaseSafe passed
389 tests with eight optional skips and all 24 UCI process cases; the complete
ReleaseFast gate also passed, including all 24 process cases. Formatting,
policy and lint passed. WAC.001 still returns `g3g6`, `mate 2` and the legal
`g3g6 g7f6 g6h7` PV at depths three and five in the actual candidate binary.
The twelve-case v24 observer passes and agrees with observer-disabled search;
its KBNK and rook-pawn cohorts retain positive scores and legal PVs.

Complete forty-position curve, Hash 64 MiB, cleared TT/history per position:

| Depth | Production nodes | MAN-S31 nodes | Reduction |
|---|---:|---:|---:|
| 4 | 149,063 | 123,446 | 17.19% |
| 5 | 343,126 | 262,432 | 23.52% |
| 6 | 782,298 | 497,868 | 36.36% |
| 7 | 1,798,886 | 1,236,341 | 31.27% |
| 8 | 4,424,221 | 2,497,119 | 43.56% |
| 9 | 11,650,070 | 5,269,940 | 54.76% |
| 10 | 26,778,901 | 11,641,147 | 56.53% |
| 11 | 79,180,184 | 23,694,522 | 70.08% |
| 12 | 170,853,905 | 48,206,266 | 71.79% |

Baseline rows reuse the exact Step-6.5.2 production reports at this checkpoint;
the baseline fingerprint was freshly verified, and no baseline sweep was
repeated. Depth-six curve totals differ from bench because bench fixes Hash
at 16 MiB. At depth ten, excluding the two known mate-heavy positions 6/30
reduces nodes from `14,063,000` to `9,092,569` (35.34%). Of forty positions,
32 shrink and eight grow; position 12 grows from `480,018` to `993,383`.
The aggregate saving is therefore neither uniform nor a strength verdict.

At depth ten, check increments fall from `1,714,018` to `10` (only the one
checked root across ten iterations). In-check nodes fall from `2,370,514` to
`1,206,722`; longest check chain remains five. Maximum extension chain falls
from five to two (retained root/singular extension). Main searched moves fall
from `16,420,591` to `6,450,317`; LMR probes/re-searches change from
`546,443/3,888` to `347,315/3,524`. Check/evasion reduction and pruning guards
are unchanged. Whole-tree charge accounting passes throughout the sweep.
The saved downstream horizon work exceeds the directly extended-node share;
that share was never a bound on total counterfactual savings. Missing
mate-distance pruning was separate historical Step 6.5.5 work; ADR-0068 now
assigns its full contract to the integrated search design.

Frozen local artifacts (native ReleaseFast, Zig 0.16.0, no PGO):

| Artifact | SHA-256 |
|---|---|
| `tools/test_engines/manta-MAN-S31-base.exe` | `FBA2BB1F3318A9ECA4DF75F5ADEBE2DA7C6A6E0F29BB1271FD4FA644949D122E` |
| `tools/test_engines/manta-MAN-S31-candidate.exe` | `52F4089BECFD050B6FECC81B9ED4D158FE52686C9F0BE9D2F7AD05CD79FF5A97` |
| `zig-out/MAN-S31-candidate/source-identity.json` | `1E35DA86D92F4095B29152F58AA6C9E65333EEEC3EC2C7E385B055F2DEC6C46D` |
| `zig-out/MAN-S31-candidate/attribution.json` | `F6F8F6D2724077817361B2E64B72350DB935DB4A38913C7E0AFEA6EE9E4C95CF` |
| `zig-out/MAN-S31-candidate/observation.txt` | `0E372FF112CD1EAED192062F8405816FD9B5F1B2C54142EBDA1A1489D63300E2` |
| `tools/step_5_1_fastchess.ps1` | `5E810F3948F7396B73CD5F635A665B0942170705A084DCEDE331795CD70FB337` |
| `zig-out/MAN-S31-candidate/setup-only.txt` | `BC07F454AA685AA45B4238BCAA9BAB12DA99B3467757077049348170CA92FF7E` |

Both adjacent binary JSON manifests record explicit build flags and compiler.
They say build-only because the builder did not run another bench; the
identical hashes bind them to the separately verified binaries above.
Source identity is commit `580a96f69b0418221f6e64559ae4240245e11845` plus the
ten exact changed source/build/test file hashes in `source-identity.json`,
not the base commit alone. Preserve that file with the uncommitted source or
freeze a source archive before transferring to the game host.

The checked setup-only command passed, including tool/book hashes and the
14-physical-core placement, and started no engine or game. Its displayed run
directory was prospective; the completed gate and final verdict are recorded
below. Step 6.5.3 is closed.

## Traceability

`SCORE-003`, `SCORE-004`, `SCORE-010`, `SCORE-011`, `SCORE-016`, `FUNC-004`
through `FUNC-006`, `PERF-006`, `QUAL-013` through `QUAL-016`; PLAN Step 6.5.3.

## Outcome and corrected interpretation (2026-09-08)

The gate produced `2,049` wins, `2,098` losses and `3,811` draws across 7,958
games for `49.69%`, pentanomial `[242, 993, 1538, 984, 222]`, pairs ratio
`0.98`. The maintainer rejected the candidate by judgment at
`-3.08 +/- 7.63` nElo, LLR `-1.60`, without anomaly. Neither boundary was
crossed; an adverse trajectory did not settle a formal SPRT verdict.

The 56.53% depth-ten node saving (35.34% excluding the mate-heavy positions)
changed forcing-line coverage. The game interval establishes neither a loss
nor equivalence. The former explanation that other checking-move exemptions
caused the result, and that removing them together would repair it, is
withdrawn as an untested hypothesis.

ADR-0068 supersedes follow-on sequencing. The archived switch may inform a
new shared-depth policy in PLAN 6.5.10 only after its design contract in 6.5.8.
No standalone retry or automatic extension removal is authorized. Node savings
are not a proxy for strength.
