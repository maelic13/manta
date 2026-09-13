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
  `1.8` per ply instead of `2.2`, reaching a given depth with roughly a tenth of
  the nodes. Accepted after a 670-game one-thread match at `3+0.03` against the
  previous search, about `+109` Elo.
- Tactical-only quiescence generation at ordinary non-check nodes, keeping a
  complete legal stalemate witness. Accepted after a 1,614-game one-thread
  match.
- Every non-root search node now clips its window to the mate distances the
  rules still allow, replacing a test that only fired when the requested window
  already lay outside them.
- `bench` reports each position as it finishes instead of printing the whole
  report at the end, so a long run gives progress feedback.
- Measured games end only by the rules of chess. Resignation, draw-after-N-moves
  and move-cap adjudication are removed from every harness.
- Ordinary interior search nodes now generate captures and promotions first and
  delay non-tactical quiet generation until no transposition or good tactical
  move remains, ranking those quiets from history that descendant searches have
  already updated. Accepted after an 8,752-game one-thread match.

### Fixed

- The crashes seen in Manta 1.0.0 tournament play no longer occur in this
  build.

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
