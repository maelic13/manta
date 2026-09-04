# Changelog

All notable user-visible changes to Manta are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases use
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/maelic13/manta/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/maelic13/manta/releases/tag/v1.0.0
