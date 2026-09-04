# HCE fitting substrate

`manta-hce-fit-v3` is the current interface. Step-5.4.3 removes the rejected
MAN-E18 rows, the superseded bootstrap outpost row and the material-floor row,
then records the candidate's context-weighted `space_bonus` feature. It is
tooling, not a runtime configuration system: fitted values are generated back
into `src/eval/hce_params.zig` and compiled into the engine. The later sections
retain the completed Step-5.3.16 v2 procedure as historical evidence; MAN-E20
recompiled only the existing train/validation CSVs and fitted only
`space_bonus`. The schema-v3 corpus and candidate-only fit are complete;
MAN-E20 failed its static gates and no candidate vector, binary or game exists.

## Parameter schema

The tool parses every committed `pub const` parameter declaration and flattens
source array order as `group[index]`. The source array is the canonical shape;
the manifest gives every scalar coefficient a stable name, current value,
status and unit. The current schema contains:

| Status | Count | Meaning |
|---|---:|---|
| free | 1,109 | Linear coefficients exposed to the static fit, including `space_bonus`, graded passer paths, file-aware shelter and king-pawn proximity |
| fixed | 17 | Phase/divisor/cap structure and zero material sentinels |
| excluded | 103 | Nonlinear king danger, independently truncated connected-rank tables, capped winnability, exact endgames and archived broad scaling |
| **total** | **1,229** | 125 source groups; binary feature switches are absent |

Excluded does not mean forgotten. The catalog names and preserves every value,
and each sample carries their combined `fixed_residual`. They receive no
gradient because a linear count model would misrepresent their caps, squares,
per-application truncation or dispatch. The six winnability coefficients are
therefore excluded despite being reasoned starting values; fitting them would
require a nonlinear model rather than pretending the capped term is linear.

## Offline exploration sweep

The registered Step-5.3.16 fit used `--learning-rate 0.3` with one full-batch
Adam step per epoch, so a coordinate could travel about `lr x epochs` and the
observed maximum displacement was seven. That bound, not convergence, may be
what stopped it. `tools/texel/fit_sweep.ps1` tests this on the existing
compiled corpus: it runs eight configurations that widen the learning rate and
the epoch budget, then `tools/texel/sweep_report.py` ranks them.

`--lr-decay` supplies per-epoch multiplicative annealing so a high-travel run
can still refine to a sub-integer step. It defaults to `1.0`, which reproduces
the undecayed schedule exactly; the accepted vector re-emerges bit for bit at
`--learning-rate 0.3 --lr-decay 1.0` with best epoch 37, 142 moved coefficients
and rounded validation `0.10365193196244439`.

**The sweep never opens the frozen test.** Every configuration passes the
validation set as `--test-prefix`, so `test.samples.bin` keeps its
one-time-opened role and each report's `frozen_test` block is a duplicate of
validation. Rank on validation only, then read the real frozen test exactly
once, for the single winning configuration, as a registered read.

The sweep is read-only against the corpus and writes only under
`tools/texel/out/diag`. It needs an idle host but no game reservation.

### Sweep result: the fit is at its limit

Fourteen configurations ran on 2026-08-22/23. Thirteen converge to the same
point, `train 0.1033551` and `validation 0.1036881`, agreeing to six or seven
significant figures across learning rates from `0.3` to `30` and decays from
`1.0` to `0.93`. The two exceptions are a run whose `--l2 1e-4` swamped the data
gradient and one lr-`30` run that had not finished converging. This surface has
one attractor and every schedule finds it, so **there is no better basin and the
registered fit was not travel-limited**.

The consequence is the reverse of the first reading. Converged validation is
`0.1036881`, while the accepted constrained vector sits at `0.1036519`: the
accepted vector is **better than the converged optimum**, because stopping at
epoch 37 regularized it. Every apparent gain beyond the converged point is an
early-stopping position, not a deeper minimum.

That also explains the flythrough readings. At high rates the trajectory
oscillates violently — `conv-lr10-d95` passes `0.103477` at epoch 10, `0.102877`
at epoch 12 and `0.104702` at epoch 20 — so a minimum taken over two hundred
such epochs finds an outlier, not a basin. The `0.1028` figures are single-epoch
dips on the way to the same attractor.

The best remaining candidate, `lr1.0-flat` at `0.1035006`, is simply a different
early-stopping position selected on validation from about 160 candidates. It is
`0.000151` better than the accepted vector, under 10% of what the accepted run
captured. Whether that generalizes is exactly the question validation selection
cannot answer, and the frozen test was not spent on it: the read could not
change the action, because a static gain of this size does not justify a rebake
that moves the production fingerprint, re-records eighteen archived snapshots
and invalidates the prepared gate binaries.

**The fitting question is closed. The accepted constrained vector stands.**
Remaining evaluation leverage is in the 5.4.3 formulation cluster and the 103
excluded nonlinear coefficients, not in further fitting of this feature set.

### Step-5.4.4 repeated-cycle decision

Step 5.4.4 closes without generating another corpus or repeating the fit. The
single-attractor sweep already refutes optimizer travel or basin selection as
the limitation, and the accepted early-stopped vector generalizes better than
the converged point. Fifty-eight unsupported coordinates are unreachable on a
legal production board; the ten rare coordinates remain below the deliberate
noise guard. Better self-play labels would still provide no gradient to the
103 excluded nonlinear, capped or dispatch values.

No accepted change after the original corpus created a new fitted consumer,
and no residual or disagreement measurement identifies label quality as the
current bottleneck. MAN-E20 failed its candidate-only fit and MAN-E21 lost its
playing gate; neither licenses a refit. The previous generation cost 1,162,814
unique starts, 1.59 GiB of PGNs and about six hours of host time before
extraction/fitting. Reopen a cycle only after a changed model class or measured
label-disagreement signal supplies a prospective mechanism and a new held-out
policy; do not self-distil the unchanged linear model by default.

## Registered Step-5.4.3 schema-v3 use

ADR-0058 registers `MAN-E20`; it does not reopen the joint fit. Schema v3
projects the accepted vector by deleting the rejected MAN-E18 nine-coefficient
block, unreachable `knight_outpost[0..1]` and fixed
`space_material_floor`. The switch-off evaluator must remain exact at
fingerprint `724,563`; the frozen floor value 12 survives only as an internal
legacy-arm constant. The resulting contract is 1,229 coefficients in 125
groups.

Recompile the existing labelled train and validation CSVs only after the
implementation is approved. Do not generate new games and do not open the old
frozen-test split again: it was already read during Step 5.3.16 and cannot be
new held-out evidence. Freeze every accepted coefficient except `space_bonus`.
The candidate is refuted before binaries unless its unconstrained float optimum
is at least `0.5`, its rounded validation loss improves on the migrated accepted
baseline by at least `0.000200`, and no validation phase regresses by more than
0.1 percent. These are selection-aware filters, not promotion evidence; only
the registered SPRT may promote the formulation.

`tools/texel/fit_man_e20.py` is the narrow fitter for this decision. It has no
frozen-test argument, fixes WDL conversion at the accepted
`K = 1.62679234682616`, derives the float optimum from training only and reads
validation only for the registered filters. The numerical search may cross
zero but remains inside the source coefficient's `i16` representation. Once
the `0.5` directional gate passes, explicit half-up rounding maps `0.5` to `1`;
this avoids NumPy's ties-to-even result and gives the registered boundary its
stated positive meaning. The output vector is emitted only when exactly
`space_bonus[0]` changes and every filter passes; a refutation emits only its
hash-bound report.

The MAN-E20 run compiled 3,000,000 training and 166,667 validation samples into
214,622,496 and 11,911,358 sparse events respectively, with zero rejected rows.
The frozen test was neither compiled nor opened. `space_bonus` had 1,662,778
training and 92,387 validation events. At fixed
`K = 1.62679234682616`, training selected the unconstrained optimum
`-3.403923499`, below the `0.5` positive-meaning gate. Its rounded value `-3`
improved validation from `0.103648340983299` to `0.103634579079070`, only
`0.000013761904229` against the registered `0.000200` floor. The report SHA-256
is `AF1EC32006AC19559A6AB48AC4DB06A4D286376FF9957FC073CA73A8CF02ABA1`.
No output vector was emitted, so MAN-E20 is refuted before source bake, binaries
or games.

## Permanently unsupported free coefficients

Sixty-eight free coefficients received no gradient in the Step-5.3.16 fit. Fifty-eight
of them record exactly zero events across all 3,333,334 compiled samples, and they
always will:

- pawn piece-square entries on ranks one and eight (`pst_mg[0..7]`, `pst_mg[56..63]`
  and the `pst_eg` equivalents), plus rank-one and rank-eight lanes of
  `passed_*`, `candidate_*`, `storm_rank` and `storm_blocked`. These index states
  that cannot exist on a legal board;
- `knight_outpost[0..1]`, which Step 5.3.11 superseded with `outpost[0]`. The
  bootstrap term survives only inside the `piece_detail = false` branch, so a
  production-shaped corpus can never activate it.

The remaining ten are genuinely rare rather than impossible: `weak_lever`
(483/525 train events), `mob_q_mg[26..27]` and `mob_q_eg[26..27]` (624/655),
`pst_mg[127]`/`pst_eg[127]` (756) and `pst_mg[376]`/`pst_eg[376]` (1,008/1,079).
Lowering `--min-train-support` would admit them, but Adam normalizes per
coordinate and `--l2` is `1e-6`, so a thinly supported coordinate moves as fast
as a well-determined one. Treat the threshold as a noise guard, not a budget.

Reclassifying or deleting any of these changes the vector's status line or its
coefficient count. Both break `--verify-vector` against the archived MAN-E17
vector, and a count change additionally invalidates the 2,002,005,496-byte
compiled corpus, which binds `coefficients 1241` in every manifest. Batch such
changes into a single schema migration once the fitting program closes.

## Commands

```text
zig build hce-fit-schema
zig build hce-fit-schema -- --emit-vector PATH
zig build hce-fit-schema -- --trace-fen "FEN"
zig build hce-fit-schema -- --extract-fen "FEN" PATH
zig build hce-fit-schema -- --compile-dataset INPUT.csv OUTPUT_PREFIX
zig build hce-fit-schema -- --verify-vector PATH
zig build hce-fit-schema -- --apply-vector PATH
zig build hce-fit-test
```

The emitted vector starts with the schema ID and then one row per coefficient:
name, value, status and unit. Applying a vector verifies schema, order, status,
units, coefficient count and the `i16` free-value range. Fixed or excluded
changes are rejected. A successful apply rewrites only numeric tokens in the
committed production parameter source; unchanged tokens, comments and layout
round-trip byte exactly. Normal builds read no sidecar.

One-position extraction writes production score, linear score,
`fixed_residual`, then sparse nonzero `(coefficient, component, lane, count)`
events. It enables the prospective imbalance block for feature production but
anchors `fixed_residual` to current production, so the current vector still
reconstructs production exactly and the fit can estimate the block without
tuning its binary switch.

## Verification

Normal evaluator sinks have no `coefficient` method, so sparse recording calls
are removed at comptime and production behavior is unchanged. The fitting sink
is allocation-free for one position and bounded at 512 merged events.

Tests protect three distinct contracts:

- byte-exact source/vector round-trip and rejection of binary switches from the
  free schema;
- exact per-component dot products for every fully linear component, preventing
  the fixed residual from hiding a missed free application; and
- exact whole-score reconstruction on the frozen 5.3.0 corpus and a
  deterministic 96-ply legal random walk, including phase, exact endgames,
  tempo, unwinnable and rule-50 effects through the fixed residual.

Schema v1 remains the incompatible pre-repair snapshot. V2 changes both shape
and meaning and must never read or apply a v1 vector.

The substrate proves representation conformance only. Dataset generation,
labelling, optimization, validation and games remain Step-5.3.16 long jobs.
The registered Manta self-play data contract and exact pilot commands are in
[`HCE_DATAGEN.md`](HCE_DATAGEN.md) and ADR-0056.

## Joint fit commands

Run these only after `HCE_DATAGEN.md` has published the exact three CSVs. The
compile and optimizer are CPU/I/O-heavy and must wait for an idle host.

```powershell
$data = (Resolve-Path ".\tools\texel\data\hce-v1").Path
$out = (Join-Path (Resolve-Path ".\tools\texel\out").Path "hce-v1")
New-Item -ItemType Directory -Force -Path $out | Out-Null

zig build hce-fit-schema -Doptimize=ReleaseSafe -- `
  --emit-vector "$out\current.tsv"

zig build hce-fit-schema -Doptimize=ReleaseFast -- `
  --compile-dataset "$data\train.csv" "$out\train"
zig build hce-fit-schema -Doptimize=ReleaseFast -- `
  --compile-dataset "$data\validation.csv" "$out\validation"
zig build hce-fit-schema -Doptimize=ReleaseFast -- `
  --compile-dataset "$data\test.csv" "$out\test"

.\.venv\Scripts\python.exe tools\texel\fit.py `
  --vector "$out\current.tsv" `
  --train-prefix "$out\train" `
  --validation-prefix "$out\validation" `
  --test-prefix "$out\test" `
  --out "$out\fitted-constrained.tsv" `
  --epochs 200 --learning-rate 0.3 --l2 0.000001 --patience 30 `
  --batch-samples 32768 --jobs 16 --min-train-support 300 `
  --min-validation-support 50 --max-delta 512

zig build hce-fit-schema -Doptimize=ReleaseSafe -- `
  --verify-vector "$out\fitted-constrained.tsv"
```

Stop after verification and provide `fitted-constrained.tsv` plus its report
for review. Do not run `--apply-vector` yourself: the source bake,
actual-evaluator residual check, imbalance on/off binary pair and SPRT
registration are the next committed evidence step.

Three relations have strict semantic bounds because their recorded counts are
non-negative and their direction is part of the chess feature identity:
central supported space remains a bonus, while distance from a minor to its
king and distance from a low-material king to its pawns remain penalties. The
optimizer clips these six coordinates at every update and records the bounds
in the v2 report. This prevents correlated aggregate loss from silently
turning protection or space into its opposite.

The first, unconstrained diagnostic fit selected epoch 30 and stopped at 60,
activated 1,051 free coordinates, retained 68 priors for low support and moved
133 rounded values by at most seven. Validation improved from 0.105517988 to
0.103537536 and the once-opened frozen test improved from 0.104461517 to
0.102432536 in all five phases. It is **not admissible for source bake**:
`space_bonus`, two `king_protector` lanes and `king_pawn_proximity` crossed
zero, refuting three domain-relation tests. Its diagnostic vector SHA-256 is
`008B9D76B9E8D95AEDAA3F348B629C4828F4FB9EECBAD37E50EB02E4FF7DFBDB`;
report SHA-256 is
`8DF8A082F81095C496EF5A8E723F706CE0ED394C1C8F7D49D72057F6ED9FC3A5`.

The constrained rerun selected epoch 37 and stopped at 67. It retained 1,051
supported coordinates and 68 priors, moved 142 rounded values by at most seven,
and placed all six directional coordinates exactly on their admissible bound.
Validation improves from 0.105517988 to 0.103651932; the already-opened frozen
test improves from 0.104461517 to 0.102574754, with every phase improving.
Vector SHA-256 is
`FF520504F23058191E80E30B15206B4E27E29E8DA1F59BE250FEAA80666D3716`;
report SHA-256 is
`7F5DAF5905FE8BE0CA95A3D856C5590D2F1D179FB68EB622FAA4812AD245FB6D`.

After reviewed source bake, compile the validation CSV again under a distinct
prefix and score its actual production value at the frozen fitted K. This does
not reopen the frozen test or apply another gradient:

```powershell
zig build hce-fit-schema -Doptimize=ReleaseFast -- `
  --compile-dataset "$data\validation.csv" "$out\validation-constrained-baked"

.\.venv\Scripts\python.exe tools\texel\score.py `
  --vector "$out\baked-constrained.tsv" `
  --dataset-prefix "$out\validation-constrained-baked" `
  --k 1.62679234682616 --require-below 0.10551798832517 `
  --out "$out\validation-constrained-baked.loss.json"
```

The baked-source vector must be byte-identical to `fitted-constrained.tsv`.
Aggregate loss and every validation phase must remain below the pre-fit
baseline before any engine binary or game ablation is prepared.

The exact source round-trip passes. Actual compiled production validation is
0.103648341 and improves every phase by 1.25%–3.24%; its report SHA-256 is
`7AAF5382C57217622F61C9962A9189636A2F7354F5835D7B15FA0A4AC9ACB8BB`.
Production keeps material imbalance off until the registered binary ablation.

`MAN-E18` compares two native binaries from one clean source revision. The
baseline is an ordinary build; the candidate alone adds
`-Dhce-material-imbalance=true`. `tools/build_test.ps1` exposes this as
`-HceMaterialImbalance` and records the boolean plus the exact build command in
each hash-bound sidecar. The switch is comptime-only: it neither adds a UCI
option nor a runtime evaluator branch. Its registered `[1,5]` normalized SPRT
retains the block only on H1; H0 or the cap deletes it.

The clean `d7cfc74` native artifacts are:

| Arm | Binary | SHA-256 | Depth-6 nodes |
|---|---|---|---:|
| Off / baseline B | `manta-hce-fit-imbalance-off.exe` | `E3091BB0CE37154DB7336790D491A3E54F2A65B6F41BB510F8EDDE6827457A21` | 724,563 |
| On / candidate A | `manta-hce-fit-imbalance-on.exe` | `8B135153B4D7973357A0B78BB08FE67F838DD209DB28AAFCBF5C1FA3595A842F` | 723,829 |

Launch the maintainer-owned run from the repository root without another timed
workload. Omit `-Seed` deliberately: the harness generates and records a fresh
prospective seed.

```powershell
& .\tools\sprt.ps1 -EngineA .\tools\test_engines\manta-hce-fit-imbalance-on.exe -EngineB .\tools\test_engines\manta-hce-fit-imbalance-off.exe -NameA MAN-E18-fitted-imbalance-on -NameB MAN-E18-fitted-imbalance-off -Mode gainer -Elo0 1 -Elo1 5 -Alpha 0.05 -Beta 0.05 -MaxGames 16000 -Hash 64 -Concurrency 14 -Threads 1 -TC "3+0.03" -TimeMargin 20 -Book .\tools\books\UHO_Lichess_4852_v1.epd -FastchessPath .\tools\bin\fastchess.exe
```

The compiler uses two documented little-endian records: 20 bytes per position
and 8 bytes per sparse event. The completed corpus contains 3,333,334 samples
and 241,917,352 events in 2,002,005,496 bytes, with zero rejected rows. The
optimizer memory-maps these files and processes bounded sample batches rather
than loading a dense `positions × 1,241` matrix. Full-train batch gradients run
on 16 workers and reduce their partials in fixed range order; validation and
frozen-test scoring remain serial and deterministic.
