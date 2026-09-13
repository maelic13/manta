# Changelog

All notable user-visible changes to Manta are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases use
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/maelic13/manta/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/maelic13/manta/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/maelic13/manta/releases/tag/v1.0.0
