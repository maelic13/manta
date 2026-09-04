# SPSA tuning with weather-factory + fastchess

fastchess does **not** have a built-in SPSA tuner. The community-standard tuner
is **weather-factory** (https://github.com/jnlt3/weather-factory), a small
Python driver that perturbs UCI options and runs mini-matches via fastchess.
This folder holds weather-factory config files for Manta.

The whole harness is Rarog's, ported unchanged in every measurement-affecting
respect (book, adjudication, time control, affinity, schedule mathematics) so
the two engines' ledgers stay comparable.

## One-time setup

```powershell
./tools/setup_tools.ps1
```

This keeps helper tools inside the Manta repo:

| Tool | Repo-local path |
|---|---|
| fastchess | `tools\bin\fastchess.exe` |
| weather-factory | `tools\weather-factory\` |
| opening book | `tools\books\UHO_Lichess_4852_v1.epd` |
| test engines | `tools\test_engines\` |
| results / logs / PGN | `tools\results\` |

All five are git-ignored. `tools\spsa.ps1` populates
`tools\weather-factory\tuner\` and launches the run.

## Setup + run — one command

`spsa.ps1` writes three config files into the weather-factory root (next to
`main.py`) and then launches the tuner:

- `cutechess.json` — runner settings (same for every group)
- `spsa.json` — SPSA hyper-parameters; `A = iterations / 10`, `a` derived from
  `r_end` and the horizon
- `config_<group>.json` → copied to `config.json` (the parameter set)

```powershell
./tools/build_test.ps1 -Suffix tune -Tune
./tools/spsa.ps1 -ConfigGroup smoke -EngineSuffix tune -Iterations 5000
```

It runs from the repo root (no `cd`), pipes the console through `watch.ps1`
(per-game noise → the log, only parameter/report blocks on screen), stops
itself at the target iteration count, and can be resumed:

```powershell
./tools/spsa.ps1 -ConfigGroup smoke -LaunchOnly -Iterations 5000
```

For a planned checkpoint, keep `-Iterations` fixed at the full horizon and set
an absolute `-StopAfter`. Re-run the same command after Ctrl-C to resume toward
that stop; remove or raise `-StopAfter` only after the checkpoint is accepted.

Read the current values at any time without touching the run:

```powershell
./tools/spsa.ps1 -ShowValues
```

## Config file format

One JSON object per tuned UCI option:

```json
{
    "Move Overhead": {
        "value": 10,
        "min_value": 0,
        "max_value": 200,
        "step": 8
    }
}
```

`step` is the perturbation size at **iteration 1**, not at the horizon. It
decays as `step * c_t(it)` with `c_t(it) = it^-0.102`, so `c_t(5000) = 0.4195`.
The engine receives `round(value)`, so an integer knob needs
`step * c_t(N) >= 0.5` — i.e. **`step >= 2`** for a 5,000-iteration run. A
step-1 integer knob goes dead after roughly iteration 894.

A sibling `fixed_<group>.json` (same folder, flat `"Name": value` pairs) pins
options to a constant for both perturbed engines. Use it to freeze discrete
architecture that must not absorb a tuned knob's noisy gradient.

New tunes use natural game termination: the Rarog/Manta V4 harness removes
weather-factory's draw and resignation adjudication. This matters especially
for time management because adjudication hides conversion and endgame clock
demand. An already-started older run must resume under its original rule.

## What Manta can currently tune

`spsa.ps1` asks the binary what it advertises and **refuses to start** if a
config names an option the engine does not expose — a tune over invisible
options burns days of games measuring pure noise. As of Phase 5 the registry is:

| Option | Type | Tunable? |
|---|---|---|
| `Hash` | spin | no — the runner owns it (64 MB) |
| `Clear Hash` | button | no — not a value |
| `Move Overhead` | spin 0–5000 | yes, but it is a time-policy knob |

Step 5.4.5 adds a tune-only registry behind `-Dtune=true`. Production binaries
still expose none of these options. The `sensitivity` group contains six
default-equivalent selectivity consumers and is a bounded pilot, not an
accepted tune:

```powershell
./tools/build_test.ps1 -Suffix MAN-S26-sensitivity -Tune
./tools/spsa.ps1 -ConfigGroup sensitivity -EngineSuffix MAN-S26-sensitivity `
    -Iterations 128 -GamesPerIteration 32
```

That is exactly 4,096 games. Stop after iteration 128; do not resume it into a
full tune. The decision gate is whether the log shows every coordinate receiving
nonzero perturbations and a coherent, non-edge-pinned trajectory large enough
to justify prospectively registering a full run. Noise, inactive coordinates,
or contradictory edge pinning closes Step 5.4.5 without tuning.

The passed pilot excludes quiet futility. The initially registered five-value
`MAN-S27` was withdrawn without games after a complete activity audit found it
omitted high-activity LMR, late-move-count and contextual-history controls.
`MAN-S28` starts all ten coordinates from accepted production defaults:

```powershell
./tools/build_test.ps1 -Suffix MAN-S28-search-complete -Tune
./tools/spsa.ps1 -ConfigGroup search_complete `
    -EngineSuffix MAN-S28-search-complete -Iterations 2000 `
    -GamesPerIteration 32 -StopAfter 128 -SetupOnly
```

Setup derives the schedule for the complete 2,000-iteration horizon and does
not start games. Launch the mandatory 128-iteration/4,096-game checkpoint with:

```powershell
./tools/spsa.ps1 -ConfigGroup search_complete -LaunchOnly `
    -Iterations 2000 -StopAfter 128
```

If interrupted before 128, re-run that exact command. After the checkpoint is
reviewed and accepted, resume the same state to the full horizon with:

```powershell
./tools/spsa.ps1 -ConfigGroup search_complete -LaunchOnly -Iterations 2000
```

The full run is 64,000 games. Use only complete iteration-2,000 theta; the
iteration-128 checkpoint is for activity/range/anomaly review, never candidate
selection. State is saved every ten iterations and the log appends on resume.

## Step 6.3.3 clock-policy fit

`MAN-T01` was the first Colosseum instrument attempt. It committed zero
iterations and was withdrawn after three engine faults made iteration zero
invalid. Colosseum remains parked until the maintainer explicitly re-enables
it. `MAN-T02` then completed 128 iterations through the established Weather
Factory/fastchess harness, but its recovering runner committed gradients across
one connection stall and could not distinguish clock outcomes from instrument
faults. Its theta is rejected. The bridge now uses the qualified 20 ms
controller margin and commits only complete mini-matches. `MAN-T03` qualified
that repair but was withdrawn before launch when the maintainer accepted the
full-run budget. `MAN-T04` is the horizon-matched fit.

The `time_sensitivity` group contains the complete active six-coordinate 1T
clock surface. `MAN-T04` runs 1,000 iterations/32,000 games with the schedule
derived for that horizon from `r_end=0.0031`. Only its complete final theta may
be considered for a bake; intermediate checkpoints are operational only.
For this group only, a completed time forfeit is scored as a loss because the
perturbed clock policy must be penalized for unsafe allocation. Other SPSA
groups still reject time forfeits; every group rejects crashes, stalls,
disconnects, illegal moves, affinity failures, incomplete scores and nonzero
runner exits before a gradient commits. The final baked candidate must still
pass the ordinary zero-forfeit clock-safety gate.

`MAN-T04` completed all 1,000 iterations/32,000 committed games. Its final
continuous theta is `1033.824752/957.397991/4290.857445/1035.972822/
1048.504906/1045.885957`, with sole rounded bake
`1034/957/4291/1036/1049/1046`. All coordinates remained active and away from
their rails; do not resume or extend this completed run.

Prepare without launching games:

```powershell
./tools/build_test.ps1 -Suffix MAN-T04-time-fit -Tune -IntegratedTime
./tools/spsa.ps1 -ConfigGroup time_sensitivity `
    -EngineSuffix MAN-T04-time-fit -Iterations 1000 `
    -GamesPerIteration 32 -Concurrency 14 -REnd 0.0031 `
    -StopAfter 1000 -SetupOnly
```

Launch or resume with the same absolute target:

```powershell
./tools/spsa.ps1 -ConfigGroup time_sensitivity -LaunchOnly `
    -Iterations 1000 -StopAfter 1000 -Concurrency 14
```

Weather Factory checkpoints every ten iterations and also saves state on a
clean interrupt. Re-running the launch command resumes that state; it does not
restart or change the annealing horizon.

`config_smoke.json` tunes `Move Overhead`. It exists to prove the tuner
plumbing end to end — perturbation → engine option → mini-match → gradient →
`state.json` — on a real advertised spin option. It is **not** a strength
program. Search knobs are available only in an explicit `-Tune` test binary;
ordinary production and GUI binaries retain the smaller public registry above.

### Naming constraint for future knobs

weather-factory builds its runner command as a string. Manta's setup patches it
(`MANTA_OPTION_QUOTING_V1`) to quote option arguments and split with `shlex`, so
spaced names like `Move Overhead` survive. That patch is verified on every
launch — but single-word names (Rarog's `TmOptScale` style) remain the simpler
choice for new tuning knobs.
