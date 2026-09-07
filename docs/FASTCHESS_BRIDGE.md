# Temporary fastchess bridge

Colosseum remains Manta's strategic experiment runner. Its current CLI assigns
one physical core separately to each engine process, so it cannot reproduce the
required one-core-per-game 1T placement. Until the corrected CLI qualifies,
`tools/step_5_1_fastchess.ps1` invokes the checked Manta-local topology helper
with Rarog's pinned fastchess and UHO book under a narrow Manta-owned Phase-5
one-thread policy. These are the same resolved inputs used by the accepted MAN-S04 gate;
Rarog's current checkout no longer carries the retired bridge files.

The bridge is intentionally narrow:

- 1T `3+0.03`, Hash 64 MiB, 20 ms fastchess margin;
- 14 concurrent games on 14 distinct physical cores, leaving two free;
- paired randomized UHO openings and shared `strength-v2` adjudication;
- normalized-Elo SPRT bounds supplied prospectively for each candidate
  (`[3,10]` by default), alpha/beta 0.05 and an even game cap; and
- explicitly named, hash-recorded candidate and accepted-baseline artifacts.

The prospective capacity estimate used the retained Manta seven-slot rate and
Rarog's observed 14-slot rate under the same clock. The first corrected Manta
pilot completed 100 games in 65 seconds (about 5,538 games/hour) with 50 paired
openings and no anomaly. Its following SPRT reached H1 after 1,176 games but
contained two baseline timeouts and is invalid under Manta's zero-forfeit gate.
The engine now wakes the controller directly on worker completion and reserves
separate ordinary-clock scheduling/publication time. The wrapper rejects any
timeout/crash/protocol anomaly even when fastchess returns success.

| Job | Game cap | Expected wall time | Conservative stop/reserve |
|---|---:|---:|---:|
| Pilot | 100 | about 1 minute | stop at 5 minutes; reserve 5 MiB |
| Playing SPRT | 16,000 | at most about 2.9 hours | stop at 3.5 hours; reserve 100 MiB |

No new Manta identical-binary calibration is required for this 1T gate. The
maintainer explicitly inherits the retained Rarog/Basilisk qualification: the
same Ryzen 9 5950X host and one-core-per-game placement, fastchess SHA-256
`8444E73965AE44E716CDE1BB546A7D7C8C9FC7A442A44194A0C71A3BFFA7DD0D`, UHO
book SHA-256 `7A7F6470615A69C6CF23D565417701D38732876F480AF90D67B42ABADE35644A`,
1T `3+0.03`, Hash 64 MiB and `strength-v2` two-sided adjudication are unchanged.
Historical gates completed before the shared profile transition retain their
recorded `strength-v1` conditions; they are not reinterpreted. The
Manta pilot separately qualifies its engine/protocol boundary. Recalibrate
only after a relevant runner, scheduler, topology, placement, TC, book,
adjudication, OS or hardware change. This inheritance does not waive matched
compiler and build provenance for the two SPRT binaries.

The retained shared profile owns topology, affinity, fastchess and the opening
book. The Manta launcher pins their exact SHA-256 identities and refuses a
silent helper, tool or book update. Each admitted gate is fixed at one Manta
search thread, so the launcher does not send the unavailable future `Threads`
UCI option. Results remain under
`D:\code\manta\zig-out\fastchess`; pilots retain trace-level engine
communications for disconnect diagnosis.

The launcher has no candidate defaults. A candidate-specific registered gate
must supply `Candidate`, `Baseline`, both names, `RunId` and `SprtSeed` before
the maintainer inspects or launches it. `SprtElo0` and `SprtElo1` default to
`3` and `10`; a different prospectively registered gate must supply both
explicitly.

## Pending MAN-S30 gate

Phase 6.5.1b is implemented behind the default-off live-history staged-picker
switch. On the separate clean 5950X checkout, build both sides from the same
frozen revision with Zig 0.16.0:

```powershell
& .\tools\build_test.ps1 -Suffix MAN-S30-candidate -LiveHistoryStaging
& .\tools\build_test.ps1 -Suffix MAN-S30-baseline
```

The schema-7 sidecars must report native ReleaseFast, non-PGO, integrated time
enabled, candidate `live_history_staging: true`, baseline `false`, candidate
fingerprint `775451`, baseline `799610`, clean source and distinct binary
SHA-256s. This is an internal-search-only candidate: engine protocol, clock
policy, runner, Ryzen host, placement, book and adjudication are unchanged and
already qualified by retained Manta, Rarog and Basilisk evidence, so no fresh
pilot is required. Dry-run and then launch the exact registered SPRT shape:

```powershell
& .\tools\step_5_1_fastchess.ps1 -Job sprt -DryRun `
  -Candidate .\tools\test_engines\manta-MAN-S30-candidate.exe `
  -Baseline .\tools\test_engines\manta-MAN-S30-baseline.exe `
  -CandidateName MAN-S30-live-history-staging -BaselineName MAN-S29 `
  -RunId MAN-S30 -SprtSeed 1445075129 -SprtElo0 1 -SprtElo1 5 `
  -MaxGames 16000
```

Any timeout, crash, disconnect, illegal move, incomplete result, nonzero exit or
affinity anomaly invalidates the run. The coding agent does not remove
`-DryRun` or start the remote job.

## Archived MAN-R02 gate

Step 6.0.3 uses the unchanged qualified one-thread bridge. Clean native Zig
0.16.0 binaries from `7b4b61a` are candidate
`188982C566E46BC6DB6F3E54AC1A498C1380D00E4BB298D3CADABBCA1A1F7196`
at fingerprint `777,105` and baseline
`2ECF1F2DCB15BF304D0A44ED3932F7A665158527F624E924358A2CD4EDA76054`
at production fingerprint `799,610`. The registered dry-run and launch shape
is:

```powershell
& .\tools\step_5_1_fastchess.ps1 -Job sprt -DryRun `
  -Candidate .\tools\test_engines\manta-MAN-R02-candidate.exe `
  -Baseline .\tools\test_engines\manta-MAN-R02-baseline.exe `
  -CandidateName MAN-R02-stability-aspiration -BaselineName MAN-S29 `
  -RunId MAN-R02 -SprtSeed 1643796853 -SprtElo0 1 -SprtElo1 5 `
  -MaxGames 16000
```

The maintainer removes only `-DryRun` to launch. Reserve 45–90 minutes normally,
with a 2.9-hour/64-MiB planning ceiling and 3.5-hour operational stop. Do not
overlap compilation, games, datagen or timed measurement. This bridge has no
pair-atomic resume; an interrupted run restarts from zero with the same
registered command and seed.

## Completed MAN-C01 cumulative Phase-5 gate

Candidate A is the final MAN-E19/MAN-S29 production head at clean `81facb6`,
fingerprint `799,610`, binary SHA-256
`F6F22A912CBAE0DE3FD69C6C33B3CBDE4A2B71B4AF1F285B12649F1E5BAA145C`.
Baseline B is corrected Phase-5.0 `632f93c`, binary SHA-256
`97ABB22AEE1AED7E77638CEBA5D96D975248ADD8A3D11C8C08883278D69C151B`.
The original `0cdd42d` artifact is not used because it predates the required
Windows completion-semaphore repair. The registered gate is 1T `3+0.03`, Hash
64 MiB, concurrency 14, paired UHO, normalized `[5,20]`, alpha/beta 0.05,
16,000-game cap and seed `925419508`. It accepted H1 after 126 games/63 pairs
in 1m09s: 90-6-30, pentanomial `[0,0,9,24,30]`, `+279.59 +/- 56.15` Elo
(`+459.61 +/- 60.66` nElo), LOS 100.00% and LLR `2.95`. Independent PGN
reconstruction matches exactly; 93 endings were adjudicated and 33 normal,
with no infrastructure anomaly. Artifacts are under
`zig-out/fastchess/MAN-C01-sprt-20260826_134613`. The result establishes the
registered material cumulative gain and closes Phase 5; its 63-pair rating
estimate is descriptive rather than precise.

## Completed MAN-S29 gate

MAN-S29 was the sole rounded bake of MAN-S28's complete ten-coordinate search
theta. Its candidate-as-A normalized `[1,5]` gate against MAN-S19 used the
unchanged 1T `3+0.03`, Hash-64, concurrency-14 bridge at source revision
`76b7b08`, seed `651364430` and a 16,000-game cap. The candidate and baseline
SHA-256s were respectively
`77304ED6D0C13268206D6E2E01C8B683E34BD42641F54C62210DD828811E486A` and
`873F30823E0F63B68775740CA51FA373E9AE847AF70209623515B657CA0C8DEB`.

The SPRT accepted H1 after 4,596 scored games/2,298 complete pairs in 41m38s:
1,272-1,069-2,255, pentanomial `[104,524,876,653,141]`,
`+15.36 +/- 6.87` Elo (`+22.49 +/- 10.04` nElo), LOS 100.00% and LLR `2.95`.
Independent complete-round PGN reconstruction matches. One later unpaired
candidate win is excluded; the scored sample contains 2,401 adjudications and
2,195 normal endings with no infrastructure anomaly. Artifacts are under
`zig-out/fastchess/MAN-S29-sprt-20260826_082935`. MAN-S29 is promoted as the
complete vector; its temporary bake selector is retired.

## Completed MAN-E21 gate

MAN-E21 is the deterministically qualified Step-5.4.3 shelter-moderated
king-danger candidate. It changes only the static evaluator; protocol, clock,
runner, placement, book, adjudication, OS and host are unchanged, so no new
pilot is required. The clean Zig-0.16 native non-PGO binaries are:

| Side | File | Clean source | SHA-256 | Bench |
|---|---|---|---|---:|
| Candidate A | `tools/test_engines/manta-MAN-E21-candidate.exe` | `1bc3fe0` | `037C144D82C2591F064507ED27E8AB7A0CAC4A5E1A53CEF7562556A18604BE1C` | 763,658 |
| Baseline B | `tools/test_engines/manta-MAN-E21-baseline.exe` | `1bc3fe0` | `EF41532949426C85008C9534C9CA76802D3C58564AA6B96528CDF71EDA5CEAF8` | 724,563 |

The prospectively fixed candidate-as-A gate is normalized `[1,5]`, alpha/beta
0.05, 1T `3+0.03`, Hash 64 MiB, concurrency 14, paired randomized UHO,
16,000-game cap and seed `675534226`. Dry-run the exact launch first:

```powershell
& .\tools\step_5_1_fastchess.ps1 -Job sprt -DryRun `
  -Candidate .\tools\test_engines\manta-MAN-E21-candidate.exe `
  -Baseline .\tools\test_engines\manta-MAN-E21-baseline.exe `
  -CandidateName MAN-E21-shelter-danger -BaselineName MAN-E19 `
  -RunId MAN-E21 -SprtSeed 675534226 -SprtElo0 1 -SprtElo1 5 `
  -MaxGames 16000
```

The maintainer launched the identical command without `-DryRun`. The normalized
`[1,5]` SPRT accepted H0 after 7,284 scored games/3,642 pairs in 1h05m42s:
1,838-1,973-3,473, pentanomial `[228,929,1434,852,199]`, `-6.44 +/- 5.52`
Elo (`-9.31 +/- 7.98` nElo), LOS 1.11% and LLR `-2.97`. Independent PGN
reconstruction matches the scored pairs; one later completed unpaired game is
excluded. All scored games ended by normal chess or adjudication, and no
infrastructure anomaly was recorded. Artifacts are under
`zig-out/fastchess/MAN-E21-sprt-20260824_200408`. MAN-E21 is rejected and
remains default-off without retry.

## Completed MAN-S25 gate

Step 5.4.1 reused the unchanged qualified one-thread bridge because the
candidate changes only interior search evaluation; protocol, clock, runner,
placement, book, adjudication, OS and host were unchanged. The checked clean
compiler-equal native non-PGO artifacts were built with:

```powershell
& .\tools\build_test.ps1 -Suffix MAN-S25-candidate -CorrectionHistory
& .\tools\build_test.ps1 -Suffix MAN-S25-baseline
```

The candidate manifest reports `correction_history: true` and bench `760161`;
the baseline reports `false` and `724563`. The launch was dry-run first with:

```powershell
& .\tools\step_5_1_fastchess.ps1 -Job sprt -DryRun `
  -Candidate .\tools\test_engines\manta-MAN-S25-candidate.exe `
  -Baseline .\tools\test_engines\manta-MAN-S25-baseline.exe `
  -CandidateName MAN-S25-correction -BaselineName MAN-S19 `
  -RunId MAN-S25 -SprtSeed 1475838799 -MaxGames 12000
```

The maintainer launched the identical command without `-DryRun`. The registered
candidate-A normalized `[3,10]` SPRT accepted H0 after 5,958 games/2,979 pairs
in 53m40s: 1,535-1,559-2,864, pentanomial
`[162, 744, 1201, 700, 172]`, `-2.05 +/- 8.82` nElo and LLR `-2.95`.
Independent PGN reconstruction matches the scored pairs exactly. Two extra
normal games are unpaired in-flight completions and excluded; the logs contain
no recorded infrastructure anomaly. Artifacts are under
`zig-out/fastchess/MAN-S25-sprt-20260824_065924`.

The general dry-run shape is:

```powershell
& .\tools\step_5_1_fastchess.ps1 -Job pilot -DryRun `
  -Candidate "C:\path\candidate.exe" -Baseline "C:\path\baseline.exe" `
  -CandidateName "candidate-name" -BaselineName "baseline-name" `
  -RunId "registered-run-id"
```

Then the maintainer runs the bounded 100-game pilot:

```powershell
& .\tools\step_5_1_fastchess.ps1 -Job pilot `
  -Candidate "C:\path\candidate.exe" -Baseline "C:\path\baseline.exe" `
  -CandidateName "candidate-name" -BaselineName "baseline-name" `
  -RunId "registered-run-id"
```

If the ordinary pilot fails only while many Manta processes are launched, the
maintainer may isolate fastchess process affinity with this non-authoritative
workflow probe:

```powershell
& .\tools\step_5_1_fastchess.ps1 -Job pilot -DiagnosticNoAffinity `
  -Candidate "C:\path\candidate.exe" -Baseline "C:\path\baseline.exe" `
  -CandidateName "candidate-name" -BaselineName "baseline-name" `
  -RunId "registered-run-id"
```

This switch is rejected for calibration and SPRT. Its result cannot support a
placement, calibration, or strength claim.

Return the pilot log and manifest for fault/rate review before starting the
long command.

The final pair is prepared under `tools\test_engines`:

| Side | File | Clean source | SHA-256 |
|---|---|---|---|
| Candidate | `manta-nullmove-sprt.exe` | `f5c61b2` | `8BBCA8116B3EADDAFF4BA4088F982DFEE47132DA25D0C9BC79997EF1E6EF4F23` |
| Baseline | `manta-phase-5.0-sprt.exe` | `632f93c` | `97ABB22AEE1AED7E77638CEBA5D96D975248ADD8A3D11C8C08883278D69C151B` |

Both schema-2 sidecars bind those hashes and record Zig 0.16.0, native
ReleaseFast, non-PGO, clean worktrees and build-only verification. They have
compiled but have not been launched by the coding agent.

The maintainer first runs the ReleaseSafe suite and a fresh fixed pilot:

```powershell
zig build test -Doptimize=ReleaseSafe

& .\tools\sprt.ps1 `
  -EngineA .\tools\test_engines\manta-nullmove-sprt.exe `
  -EngineB .\tools\test_engines\manta-phase-5.0-sprt.exe `
  -NameA MAN-S03-null-wakeup-pilot `
  -NameB Manta-phase-5.0-wakeup-pilot `
  -Mode fixed `
  -Games 100 `
  -TC "3+0.03" `
  -Concurrency 14
```

The wakeup pilot completed 100/100 games in 62 seconds, scored candidate
35-31-34 and contained no timeout, crash, protocol, process or affinity
anomaly. All 100 PGNs are present. Only 19.82% of 8,002 move-time samples were
within 1.5 ms of a 15.625 ms Windows tick multiple, down from 82.98% before the
repair and aligned with Rarog/Basilisk. The pilot therefore admits the fresh
strength run below after ReleaseSafe confirmation.

The playing SPRT is a maintainer-owned long job and is never started by a
coding agent:

```powershell
& .\tools\sprt.ps1 `
  -EngineA .\tools\test_engines\manta-nullmove-sprt.exe `
  -EngineB .\tools\test_engines\manta-phase-5.0-sprt.exe `
  -NameA MAN-S03-null `
  -NameB Manta-phase-5.0 `
  -Mode gainer `
  -TC "3+0.03" `
  -Concurrency 14 `
  -MaxGames 16000
```

Do not pass `-Seed`: the harness generates and records the fresh prospective
seed when its default zero value is used.

The resulting seed `417776518` run accepted H1 after 1,070 scored games/535
pairs in 9m39s: candidate 407-281-382, `+56.04 +/- 20.82` normalized Elo and
LLR 2.96. No timeout, crash, illegal move, protocol, process or affinity anomaly
occurred. Candidate and baseline hashes matched the table above. Fastchess
completed two already-running games after the paired boundary and stopped 13
in-flight games; these are normal concurrent shutdown and are excluded from the
paired statistic. ADR-0022 accepts verified null-move pruning.

Run only one timed workload on the host. The bridge does not provide
Colosseum's pair-atomic checkpoint/resume durability, so an interrupted job
must be treated as incomplete. Remove this bridge after the corrected
Colosseum revision passes exact-condition qualification.

## Completed MAN-S06 gate

MAN-S06 was the deterministically qualified Step-5.1.2 candidate; MAN-S04 was
the accepted playing baseline. Both were built with Zig 0.16.0 native
ReleaseFast, non-PGO on the registered Ryzen host:

| Side | File | Clean source | SHA-256 |
|---|---|---|---|
| Candidate | `tools/test_engines/manta-MAN-S06-history-sprt.exe` | `18929fb4c1b16b35c913761873c530faf095c4df` | `D41B267729654EA5F316AE282CD2F4E17427C5D80635E81E8A646BEB9AC54659` |
| Baseline | `tools/test_engines/manta-MAN-S04-baseline-sprt.exe` | `d43b6762dcaa61181d50b6250cb3fc8ff40ee893` | `89258DCDF9AE79F408AC1FA08AE8BEFEC754188FDD50E2EEAEAC1CCB3F58E6B6` |

The earlier Intel-native preparation hashes were ineligible and were replaced
by these returned Ryzen-native sidecars before interpreting games.

Pure internal-search candidates do not require a fresh pilot when the engine
protocol, clock policy, runner, OS, hardware, placement, book and adjudication
are unchanged. MAN-S06 meets that condition. A pilot remains mandatory after a
change to one of those boundaries or after any unexplained game-run anomaly.

At the recorded launcher revision, the exact dry-run and launch commands were:

```powershell
& .\tools\step_5_1_fastchess.ps1 -Job sprt -DryRun
```

The launcher required the exact `AMD Ryzen 9 5950X 16-Core Processor` model,
14 one-core games and two reserved physical cores. A machine that merely had
16 heterogeneous or otherwise different cores was refused.

```powershell
& .\tools\step_5_1_fastchess.ps1 -Job sprt
```

The candidate-as-A normalized `[3,10]`, alpha/beta 0.05, seed-`512061` gate
accepted H0 after 2,448 scored games/1,224 pairs in 21m39s: 620-690-1,138,
pentanomial `[78,321,490,263,72]`, `-14.31 +/- 13.76` nElo and LLR -2.95.
Independent PGN reconstruction matches those totals. At the paired H0 boundary
fastchess stopped an in-flight candidate process; that disconnect and two
completed unpaired games were excluded from the statistic. No scored engine,
clock, protocol or placement anomaly occurred. Archive SHA-256 is
`F85134A6D4056165F94A00984125FAFF8F4190A3838E890F25B87FD4F381549E`;
PGN SHA-256 is
`40037499C7105FE1483D92AD77452ACE68E962BF732A71535462D1CBCF3FD878`.
MAN-S06 is rejected and disabled; MAN-S04 remains production behavior.

## Completed MAN-S07 gate

MAN-S07 was the deterministically qualified Step-5.1.3 qsearch-SEE candidate;
MAN-S04 was its accepted playing baseline. At the recorded revision the bridge
defaults named `manta-MAN-S07-qsearch-see-sprt.exe` as candidate and launched the authoritative
SPRT directly. No fresh pilot is required because the engine protocol, clock
policy, runner, OS, Ryzen host, placement, book and adjudication are unchanged.

The gate was candidate-as-A, one thread, `3+0.03`, Hash 64 MiB,
14 one-core games with two physical cores reserved, seed `513071`, normalized
`[3,10]`, alpha/beta 0.05 and at most 12,000 games. Expected duration is at
most about 2.2 hours; stop at three hours and reserve 250 MiB. The
paired SPRT boundary is the stop rule. Any timeout, crash, illegal move,
protocol/affinity mismatch or unexplained infrastructure anomaly invalidates
interpretation pending audit. It accepted H1 after 1,202 games/601 pairs in
10m43s: 382-265-555, pentanomial `[21,117,240,170,53]`,
`+49.54 +/- 19.64` nElo and LLR 2.95. MAN-S07 is retained. The returned summary
did not include the run archive or binary hashes; capture them before release.

## Completed MAN-S10 gate

MAN-S08 remains parked default-off and must not be run in isolation. MAN-S10 is
the deterministically qualified Step-5.1.4.2 depth-authority candidate against
accepted MAN-S07 behavior at baseline revision `20cf48b`. The retained host
qualification is inherited because the runner, Ryzen host, placement, book,
clock policy, protocol, Hash and adjudication boundary are unchanged.

The gate was candidate-as-A, one thread, `3+0.03`, Hash 64 MiB,
14 one-core games with two physical cores reserved, seed `514102`, normalized
`[3,10]`, alpha/beta 0.05 and at most 12,000 games. Recent accepted jobs sustain
about 56 pairs/minute, implying roughly 1.8 hours at the full 6,000-pair cap;
use 2.2 hours as the planning estimate, stop at three hours and reserve 250 MiB.
The paired SPRT boundary was the normal stop rule. It accepted H1 after 1,818
games/909 pairs in 16m09s: 547-424-847, pentanomial `[39,182,365,263,60]`,
`+34.91 +/- 15.97` nElo and LLR 2.95. No infrastructure anomaly was reported.
MAN-S10 is retained. The returned summary did not include the run archive or
binary hashes; capture them before release if they become available.
