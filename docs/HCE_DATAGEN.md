# HCE self-play data generation

ADR-0056 uses Manta self-play results rather than an external evaluation
oracle. The Beast file supplies starts only. Every retained row receives the
White-perspective result of its own game, and the extractor limits correlated
rows from that game before balancing the global corpus.

All commands below run from the Manta repository root. Do not overlap start
sampling, self-play, extraction or fitting with another timed job on the Ryzen
9 5950X. In particular, wait for the current engine SPRT to finish.

## One-time bounded checks

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r tools\texel\requirements.txt
.\.venv\Scripts\python.exe -m unittest discover -s tools\texel -p "test_*.py"
zig build hce-fit-test -Doptimize=ReleaseSafe
```

The source file is opened read-only. The sampler writes only beneath the
ignored `tools/texel/data` directory. Supplemental sampling accepts hashed
EPD/PGN exclusions and counts their pawn families against the same cap.

## Start book and label-engine preparation

These commands scan/build and therefore wait for an idle host:

```powershell
.\.venv\Scripts\python.exe tools\texel\sample_fens.py `
  "A:\Chess\Beast\data\txt\positions.txt" `
  --out tools\texel\data\beast-seed-v1.epd `
  --count 1000000 --seed 5316001 --max-per-pawn-family 4

.\.venv\Scripts\python.exe tools\texel\audit_starts.py tools\texel\data\beast-seed-v1.epd
.\tools\build_test.ps1 -Suffix hce-datagen-v1 -BenchDepth 6
```

The engine manifest must report a clean tree. The sampler manifest records the
source and book hashes, exact phase quotas, distinct pawn families, effective
family count and largest family.

## Required 20k pilot

```powershell
.\tools\datagen.ps1 -Suffix hce-datagen-v1 -Rounds 20000 `
  -Start 1 -Seed 5316003 -Nodes 8000 -Hash 16 -Concurrency 30 -SetupOnly

.\tools\datagen.ps1 -Suffix hce-datagen-v1 -Rounds 20000 `
  -Start 1 -Seed 5316003 -Nodes 8000 -Hash 16 -Concurrency 30
```

This is Manta's first-party adaptation of Rarog's proven fastchess datagen
launcher. Weather-factory is not involved; it owns SPSA only. One game is
played from each independently shuffled opening, avoiding the redundant
colour-swapped replay required by Colosseum's fixed match. Fixed nodes make
high unaffined concurrency a throughput choice rather than a clock bias.

The 60-game qualification smoke launched 30 games before the first completion,
finished in 10 seconds, produced 60 unique starts and projected about 29 MiB of
pilot PGN. Allow up to one hour and 1 GiB for the 20k pilot; stop at two hours
or on any engine/protocol failure. Existing outputs are never overwritten or
appended. If interrupted, retain the partial archive for diagnosis and launch
the same registered segment again under a newly named output. Never combine
the incomplete archive with its replacement or claim that fastchess resumed.

```powershell
$pilot = ".\tools\texel\data\selfplay-hce-datagen-v1-n8000-s1-g20000.pgn"
.\.venv\Scripts\python.exe tools\texel\audit_starts.py $pilot
.\.venv\Scripts\python.exe tools\texel\extract.py $pilot `
  --preflight-games 20000 --target-train 3000000 `
  --validation-pct 5 --test-pct 5 --max-per-phase-per-game 8 `
  --max-per-game 16 --skip-start 0 --skip-end 6 --seed 5316002
```

The completed pilot reported 208,973 unique quiet rows with no parse errors.
Frozen-test/opening yield was limiting, registering 1,162,814 total independent
games after the prospective 20% safety margin. Its PGN is 28.08 MiB and its
SHA-256 is `DCFBF059B6AF055E278AD19E799F134E72929C28D9E85DC89A2E59A030519EFB`.

At the measured 51.55 games/s, the remaining 1,142,814 games should take 6.16
hours and produce about 1.57 GiB of PGN. Stop the combined segments if they
exceed 12.5 hours or on any engine/protocol failure. Retain the 150 GiB corpus
workspace reserve because extracted CSV and sparse event files are additional.

## Continuation and exact dataset

First create a supplemental book. This is a whole-source read and therefore a
maintainer-run long operation. The original million-start book is an exclusion
input: no start is reused, and its family counts consume the global cap.

```powershell
.\.venv\Scripts\python.exe tools\texel\sample_fens.py `
  "A:\Chess\Beast\data\txt\positions.txt" `
  --out tools\texel\data\beast-supplement-v1.epd `
  --count 200000 --seed 5316004 --max-per-pawn-family 4 `
  --exclude tools\texel\data\beast-seed-v1.epd

.\.venv\Scripts\python.exe tools\texel\audit_starts.py `
  tools\texel\data\beast-seed-v1.epd `
  tools\texel\data\beast-supplement-v1.epd
```

The completed supplement has SHA-256
`B101CA773D0227127C0AC8C938CF2382086B9DCAE1C182651481AAA224B99240`.
The combined audit reports 1,200,000 exact-unique starts, exactly 240,000 per
phase and largest pawn family four. Its schema-v2 manifest hashes the immutable
source and the full excluded original book.

Then generate two non-wrapping continuation segments, never concurrently:

```powershell
.\tools\datagen.ps1 -Suffix hce-datagen-v1 -Rounds 980000 `
  -Start 20001 -Seed 5316003 -Nodes 8000 -Hash 16 -Concurrency 30 `
  -Book .\tools\texel\data\beast-seed-v1.epd

.\tools\datagen.ps1 -Suffix hce-datagen-v1 -Rounds 162814 `
  -Start 1 -Seed 5316005 -Nodes 8000 -Hash 16 -Concurrency 30 `
  -Book .\tools\texel\data\beast-supplement-v1.epd

.\.venv\Scripts\python.exe tools\texel\extract_parallel.py `
  ".\tools\texel\data\selfplay-hce-datagen-v1-n8000-s1-g20000.pgn" `
  ".\tools\texel\data\selfplay-hce-datagen-v1-n8000-s20001-g980000.pgn" `
  ".\tools\texel\data\selfplay-hce-datagen-v1-n8000-s1-g162814.pgn" `
  --out-dir tools\texel\data\hce-v1 --target-train 3000000 `
  --validation-pct 5 --test-pct 5 --max-per-phase-per-game 8 `
  --max-per-game 16 --skip-start 0 --skip-end 6 --seed 5316002 --jobs 16
```

The completed 980,000-game segment took 5:03:09 and produced a 1.342 GiB PGN
with SHA-256
`CE753DE61D570CB7A2722627D0C7AE258D5915DF11EE10CE7DA154A1D8642C26`.
Together with the pilot it contains exactly one million unique starts, exactly
200,000 per phase and pawn-family maximum four. At its measured 53.88 games/s,
the final segment should take about 50 minutes and add about 0.223 GiB.

The final segment completed in 50:16 and its 227.67 MiB PGN matches SHA-256
`7A14DF6069B69E9E48B1FAC77C6BEECE0F1CB1927F363898CF22694AA376871D`.
All three PGNs total 1.59 GiB and 1,162,814 exact-unique starts. Phase counts
range from 232,486 to 232,715 and the global pawn-family maximum remains four.

Extraction publishes `train.csv`, `validation.csv`, `test.csv` and
`manifest.json` only after every exact phase quota is full. The fit commands
are documented in `docs/HCE_FITTING.md`; they consume these three files and do
not modify the read-only source or generated PGNs.

The completed extraction parsed all games with zero errors, observed
12,051,850 globally unique eligible rows and filled every quota. It published
exactly 3,000,000 train, 166,667 validation and 166,667 test rows. Manifest v2
records 1,162,814 independent starts, zero replays, 30,641 games with no
retained quiet row and split counts 1,046,168/58,142/58,504. The three CSV
hashes were independently verified. Empty-row games do not enter a reservoir
or consume RNG, so correcting their initial parallel counter omission changed
no selected row or output hash.
