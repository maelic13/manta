# Changelog

All notable user-visible changes to Manta are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases use
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.1] - 2026-10-08

### Changed

- Manta now builds with Zig 0.17.0, which also builds and runs natively on
  Windows ARM64. Playing behavior is unchanged: the one-thread depth-6
  fingerprint stays `355,879`.

## [1.2.0] - 2026-09-16

### Fixed

- A won game is no longer drawn by repetition. Returning to a position it had
  already searched, the engine replayed that earlier decision without looking
  again, walked into a threefold and reported a winning score while doing it.
  Reported in issue #4.
- The only legal move is played at once instead of being thought about.
  Reported in issue #4.
- A proven mate ends the search, instead of repeating the same line once per
  remaining ply and reporting depths that describe no work.
- `go infinite` no longer answers with `bestmove` before `stop` asks for it,
  even when the search has nothing left to examine.
- With more than one thread, `nodes` and `nps` count every thread's work during
  the search; they previously showed one thread's and understated the search.
- One move can no longer take an outsized share of a short clock, so a long
  game keeps time for its endgame instead of arriving on the increment.
- The displayed principal variation stops where the rules end the game. Near
  the fifty-move limit it continued into moves that would never be played,
  which interfaces report as a principal variation continuing after the
  fifty-move rule.

### Changed

- Principal variations are lines the search actually walked. Manta used to end
  a line wherever it met a stored position and then pad the display from its
  own tables; now every principal node is searched for itself. On a warm table
  at depth 12 the searched line grew from about two moves to the full depth,
  and the padding is gone. Playing strength is unchanged; the searched line was
  the point.
- Search information follows the field order interfaces expect:
  `depth`, `seldepth`, `score`, `nodes`, `nps`, `hashfull`, `tbhits`, `time`,
  `pv`. Table occupancy (`hashfull`) is new. Lines reporting the move being
  searched are trimmed to `currmove` and `currmovenumber`, and appear only once
  a search has run for three seconds.

## [1.1.0] - 2026-09-13

### Changed

- Much stronger play from a new coordinated selective search: history-driven
  late-move reductions, pruning judged at the depth a move will really be
  searched, deeper forward pruning, a failed-side root aspiration window and
  quiet checks in the first quiescence ply. The search tree grows by about
  `1.8` per ply instead of `2.2`, reaching a given depth with roughly a tenth
  of the nodes, and the engine plays about `110` Elo stronger than 1.0.0 at
  fast time controls.
- Interior search nodes generate captures and promotions first and delay quiet
  move generation until no transposition or good tactical move remains,
  ranking those quiets from up-to-date history.
- Quiescence search generates only tactical moves at ordinary non-check nodes
  while keeping a complete legal stalemate witness.
- Every non-root search node clips its window to the mate distances the rules
  still allow.
- `bench` reports each position as it finishes instead of printing the whole
  report at the end. The one-thread depth-6 fingerprint is now `359,259` nodes.
- Principal variations no longer stop at a transposition-table hit. The
  displayed line continues from the table with legal stored moves, so a depth
  resolved from memory shows the line its score stands on instead of a single
  move, and the suggested ponder move is available in more positions.

### Fixed

- The engine no longer loses its connection mid-game with more than one thread:
  a transposition table replacement could read an entry another thread was
  rewriting. Reported in issue #2.
- A full output queue no longer ends the session: the engine waits for an
  interface that reads slowly instead of exiting. Reported in issue #2.
- Every completed depth reports its score and principal variation, in depth
  order, with any thread count; previously most depths showed only `currmove`
  progress. Reported in issue #2.
- `quit` exits within a bound even when the interface has stopped reading
  output.
- With more than one thread, a search that reaches its depth limit no longer
  prints its last depth twice.
- On Windows the engine no longer dies silently under interfaces that create
  asynchronous pipes, such as fastchess, once its output runs ahead of the
  reader: standard output now follows the inherited handle's I/O mode, as
  standard input already did.

## [1.0.0] - 2026-09-04

### Added

- A complete UCI chess engine with legal move generation, repetition and draw
  handling, transposition tables and deterministic one-thread search.
- A tuned classical tapered evaluation covering material, piece-square terms,
  mobility, pawn structure, king safety, threats, space and endgame scaling.
- Principal-variation alpha-beta search with quiescence search, iterative
  deepening, aspiration windows, move ordering and selective pruning.
- Main-authoritative lazy SMP with configurable thread count and deterministic
  single-thread behavior.
- Clock management, move-overhead protection, pondering and live search
  control through UCI.
- Optional Syzygy tablebase probing for up to seven pieces.
- Configurable hash, threads, time overhead and tablebase UCI options.
- A built-in deterministic benchmark and focused correctness, safety, protocol
  and concurrency tests.
- Portable 64-bit release builds for Windows x86-64, Linux x86-64, Linux ARM64,
  macOS x86-64 and macOS ARM64.

[Unreleased]: https://github.com/maelic13/manta/compare/v1.2.1...HEAD
[1.2.1]: https://github.com/maelic13/manta/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/maelic13/manta/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/maelic13/manta/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/maelic13/manta/releases/tag/v1.0.0
