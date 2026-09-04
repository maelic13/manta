# ADR-0056: Fit the frozen HCE from grouped Manta self-play outcomes

## Status

Accepted prospectively for Step 5.3.16 on 2026-08-21 by maintainer direction.
This record prepares tooling and commands; it does not authorize the coding
agent to run data generation, fitting or games on the designated host.

## Chess and evidence mechanism

The immutable Beast file supplies legal starting positions, not labels. One
clean, fixed-node Manta binary plays both colours from each sampled start. The
game result is a noisy observation of whether White converted or held the
position, so the extractor assigns `1`, `0.5` or `0` to a bounded sample of
quiet positions that the game actually visited. It does not copy a static
Manta score down the game and does not use an external evaluator as an oracle.

The producers are the read-only start FEN, Manta's legal move/search output and
the terminal or conservatively adjudicated game result. The checked fastchess
launcher transforms them into PGN archives with hash-complete sidecars.
Extraction keeps complete FEN state,
filters tactical transition points, groups every split by start game, caps
within-game rows, deduplicates globally and balances material phase. The
fitter transforms the remaining sparse linear feature events into a versioned
parameter vector. The only eventual runtime consumer is a reviewed source bake
followed by the ordinary evaluator, raw-eval cache and frozen search.

Check, capture, promotion and the final six plies are excluded from training
rows. Castling and en-passant fields and the halfmove clock remain in each FEN;
the fullmove number is irrelevant. Terminal positions are never sampled.
Repetition history cannot be reconstructed from FEN and therefore grants no
static-evaluation authority. Self-play owns legal terminal/draw outcomes;
Syzygy, mate bands, search bounds, TT provenance and history remain unchanged.

Feature extraction and fitting are offline, allocation-heavy work. Production
evaluation remains allocation-free and schema machinery is erased at comptime.
The data and fit are deterministic for fixed inputs and seeds. They create no
threaded engine behavior; the later one-thread SPRT remains the promotion gate.

## Data contract

- Source: `A:\Chess\Beast\data\txt\positions.txt`, opened read-only and
  streamed once by reservoir sampling. Outputs live under ignored
  `tools/texel/data/`; the source is never rewritten or copied.
- Starts: the pilot book has one million requested positions, five equal material-phase
  reservoirs, legal non-terminal positions, minimum six pieces, no side in
  check, exact deduplication and a default cap of four selected starts per pawn
  structure family. A seeded whole-file reservoir removes dependence on input
  order. A manifest records source/book hashes and concentration statistics.
  If the pilot requires more starts, each supplemental book hashes its excluded
  predecessors, removes their exact starts before reservoir sampling and counts
  their pawn families against the same cap.
- Labels: identical clean Manta binaries, 8,000 nodes per move, fixed one
  thread and 16 MiB hash. Rarog's first-party fastchess launcher is adapted
  locally to play one game per independently shuffled opening; an identical-
  engine colour replay would be bit-identical and is not generated. Draw
  adjudication is move 40 / 8 plies / 10 cp; two-sided resignation is 600 cp
  for 3 plies; move 200 is a draw. These are a named data-label policy, not a
  strength gate.
- Pilot: exactly 20,000 independent starts and recorded games first. Measured
  unique quiet yield by the limiting phase determines the continuation. The
  full run must not wrap or reuse a start and must not overlap another timed
  workload on the 5950X.
- Rows: exactly 3,000,000 training positions, equal across five material
  phases. Validation and frozen test each receive five percent of whole games
  (about 166,667 rows each), also phase-balanced. A game belongs wholly to one
  split. At most eight rows per phase and sixteen total come from one game;
  positions are globally deduplicated using board, side, castling, en-passant
  and halfmove-clock state.
- Quiet filter: reject check, a played capture or promotion, and a position
  with an immediately profitable legal capture. Skip the final six plies.
- Provenance: book, engine, PGN/run-record and dataset manifests name hashes,
  seeds, ranges, counts, filters and split rules. Published CSVs are atomic and
  stay outside Git.

Three million balanced rows are the first-fit target, not a claim that more
data cannot help. Five million correlated rows are not equivalent to five
million independent observations. The 20k pilot may justify a larger corpus
only if held-out phase support or start-family effective count is deficient.

## Fit and refutation contract

Fit all supported schema-v2 free linear coefficients jointly against
White-perspective WDL with a fitted Texel sigmoid scale, L2 shrinkage to the
reasoned vector and validation-selected early stopping. Structurally fixed and
excluded nonlinear coefficients never receive a gradient. Free coefficients
without adequate train and validation activation remain at their prior value.
The rejected MAN-E07 imbalance block is traced during the joint fit exactly as
authorized by ADR-0050; enabling it in an engine remains a separate post-fit
ablation.

Validation may select the epoch and therefore is not unbiased evidence. The
frozen test split is opened once after selection. Reject the vector before a
source bake if rounded weights fail to improve aggregate frozen-test loss, if
a material-phase bucket regresses materially, if reconstruction/schema checks
fail, or if any fitted value escapes its checked integer range. After baking,
re-extract a bounded conformance cohort with the actual evaluator and require
the reported loss direction to survive integer interpolation and excluded
residuals.

Static loss can reject or propose the fit but cannot promote it. The registered
Step-5.3.16 one-thread SPRT and its already-fixed H0 attribution branch remain
the only playing-strength decision. No SPSA follows a disappointing fit.

The fitted imbalance attribution is `MAN-E18`: candidate A enables only that
jointly fitted coefficient block and baseline B leaves it off from the same
source tree. `-Dhce-material-imbalance=true` selects the candidate at comptime;
the ordinary build remains off and no runtime option or hot-path branch is
added. The registered gate is 1T `3+0.03`, Hash 64 MiB, concurrency 14,
paired random UHO openings, normalized `[1,5]`, alpha/beta 0.05 and a 16,000-
game cap with a fresh harness-recorded seed. Only H1 rescues the block. H0 or
the cap deletes it before the final fitted-head gate. An interrupted or
anomalous run is void and restarts under a new result manifest; it is not
statistically resumed.

## Consequences

Preparation is split into committed substeps: contract, start/extraction
pipeline, sparse fitter/bake workflow, then the maintainer-run pilot. The
coding agent stops after producing and dry-running exact commands. Dataset
size is revised only from pilot evidence, never because a round number such as
five million sounds safer.

## Preparation outcome

Substeps 5.3.16.0–.3 are complete. The checked
sampler, grouped extractor and audit implement the data contract. Colosseum's
synchronous per-game checkpoint/PGN rewrite collapsed effective concurrency
and triggered a Windows checkpoint-sharing failure, so the maintainer selected
the copied Rarog fastchess launcher as the temporary fixed-node producer.
`manta-hce-fit` compiles labelled CSV rows into bounded little-endian
sparse records, and the NumPy optimizer memory-maps them, fits only supported
free coefficients, selects on validation, reports the frozen test once and
emits a schema-checked integer vector. A 60-game real-engine smoke started 30
games before the first completion, finished in 10 seconds, produced 60 unique
starts across all five phases and wrote a checked provenance manifest. This is
engineering evidence only. The production pilot then completed 20,000 games
in 388 seconds. Its manifest and PGN hashes agree; all starts are unique, the
largest pawn family is two and all games parse without error into 208,973
unique eligible rows. Frozen-test/opening yield is limiting. The prospective
20% margin registers 1,162,814 total games, so the continuation consumes the
remaining 980,000 starts in the original book plus 162,814 starts from a
200,000-position supplement that excludes the original book. At pilot rate the
continuation is 6.16 hours and about 1.57 GiB of PGN. The supplemental source
scan then wrote 200,000 starts with SHA-256
`B101CA773D0227127C0AC8C938CF2382086B9DCAE1C182651481AAA224B99240`.
Its manifest hashes all one million excluded starts. The combined books have
1.2M exact-unique starts, exactly 240k per phase and global pawn-family maximum
four. The 980,000-game original-book segment subsequently completed in 5:03:09
with no reported faults; the
1.342 GiB PGN matches SHA-256
`CE753DE61D570CB7A2722627D0C7AE258D5915DF11EE10CE7DA154A1D8642C26`.
Together with the pilot it has exactly one million unique starts and 200k per
phase. The final 162,814-game supplemental segment completed in 50:16 with no
reported faults, and its 227.67 MiB PGN matches
SHA-256 `7A14DF6069B69E9E48B1FAC77C6BEECE0F1CB1927F363898CF22694AA376871D`.
The full three-segment corpus contains 1,162,814 exact-unique starts, phase
counts within 229 of one another and global pawn-family maximum four. Datagen
took just under six hours and produced 1.59 GiB of PGN. Exact grouped extraction
then parsed all games without error and published exactly 3,000,000 train plus
166,667 validation and 166,667 frozen-test rows with every phase quota full.
The output hashes were independently verified. A parallel accounting defect
omitted 30,641 empty-row games from its start counts; exact FEN-header
reconstruction proved 1,162,814 independent starts and zero replays. Because an
empty game never reaches a reservoir or consumes its RNG, CSV selection was
unchanged. Manifest schema v2 records the corrected split/skipped counts, and a
worker regression prevents recurrence. Sparse compilation was the next boundary.
Compilation then accepted all 3,333,334 rows with zero rejection and emitted
241,917,352 sparse events in 2,002,005,496 bytes. Exact record-size checks pass
for every split, and the frozen 1,241-coefficient input vector verifies under
schema v2. Full-train gradient batches run on 16 threads with fixed-order
reduction and exact serial/threaded fixture equivalence; validation selection
and the post-selection frozen-test read remain serial. The fit is the next
maintainer-run boundary.

The first registered fit activated 1,051 free coordinates and retained 68 priors for
low support. Validation selected epoch 30; patience stopped at 60. Integer
rounding moved 133 coordinates by at most seven. Validation loss improved from
0.105517988 to 0.103537536. The once-opened frozen test improved from
0.104461517 to 0.102432536, and every phase improved by 1.22%–4.27%. All report,
dataset and vector hashes verify. The switch-off imbalance projection also
improves every phase, while enabling its fitted coordinates adds only a small
0.000016312 aggregate frozen-test improvement. Source review nevertheless
refuted the vector: central supported space crossed from bonus to penalty, two
minor-to-king distance lanes crossed from penalty to reward, and low-material
king-to-pawn distance crossed from penalty to reward. Those directions are
part of the retained feature identity, not optional coefficient priors.

The optimizer therefore applies and reports six semantic bounds: four
`king_protector` lanes and `king_pawn_proximity` stay strictly negative, while
`space_bonus` stays strictly positive. Production was restored to the accepted
pre-fit vector before the rerun; the already opened frozen test remained
reporting evidence and was not reused for selection.

The constrained rerun selected epoch 37 and stopped at 67. It moved 142
rounded coordinates by at most seven and improved validation from 0.105517988
to 0.103651932. The frozen test improved from 0.104461517 to 0.102574754, with
every phase improving. Its vector SHA-256 is
`FF520504F23058191E80E30B15206B4E27E29E8DA1F59BE250FEAA80666D3716`.
Source re-emission is byte-identical. Recompiling validation against the baked
production evaluator, with imbalance still default-off, gives 0.103648341 and
improves every phase. This accepts the offline vector and deterministic bake,
not the engine's playing-strength claim; the imbalance ablation and final
fitted-HCE gate remain mandatory.

`MAN-E18` artifacts were then built clean from `d7cfc74` with Zig 0.16.0,
native non-PGO. The off arm is
`E3091BB0CE37154DB7336790D491A3E54F2A65B6F41BB510F8EDDE6827457A21`
at fingerprint `724,563`; the on arm is
`8B135153B4D7973357A0B78BB08FE67F838DD209DB28AAFCBF5C1FA3595A842F`
at `723,829`. Hash-bound sidecars record the same source/tree/compiler and
opposite false/true compile-time switch values. No games were started.

## Traceability

- `PLAN.md` and `GUIDE.md`, Step 5.3.16.
- ADR-0049, ADR-0050, ADR-0051, ADR-0054 and ADR-0055.
- `docs/HCE_FITTING.md`; `SCORE-001`, `PERF-002`, `QUAL-015`.
