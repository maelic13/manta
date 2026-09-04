# ADR-0044: Syzygy probe boundary and vendored Fathom

## Status

Accepted for Step 5.2 on 2026-08-16. This record covers the dependency and
ownership boundary. Root filtering and interior probe policy are search
behavior and receive their own decision and gate before they may change play.

## Context

Step 5.2 adds Syzygy tablebase support to the frozen MAN-S19 search head. The
Syzygy on-disk format is a compressed, permutation-indexed encoding whose
decoder is intricate and whose failure mode is silent: a subtly wrong decode
returns a confident, wrong result for a position the engine believes is
perfectly known. That risk, not implementation effort alone, is why `PLAN.md`
pre-authorized Fathom as the single third-party source exception.

Manta otherwise has no C dependency and does not link libc. Vendoring Fathom
changes that for every build.

## Decision

- Vendor Fathom from `https://github.com/jdart1/Fathom` at commit
  `c9c6fef0dddc05d2e242c183acf5833149ab676d` into `third_party/fathom/`,
  unmodified. Its MIT license and per-file notices are preserved verbatim, and
  MIT is compatible with Manta's GPL-3.0-or-later distribution. The upstream
  revision and per-file SHA-256 values are pinned in
  `config/fathom-vendor.json`; changing the revision requires re-recording
  every hash, rerunning the gates and amending this record.
- Vendor only the probe and format layer: `tbprobe.c`, `tbchess.c`,
  `tbprobe.h`, `tbconfig.h`, `stdendian.h` and `LICENSE`. The upstream CLI
  driver and Makefile are excluded. Only `tbprobe.c` is compiled, because it
  textually includes `tbchess.c`.
- Link libc unconditionally. The maintainer chose this over gating tablebases
  behind a build option or writing a native decoder, accepting that libc-free
  Linux packaging is withdrawn as a release candidate. `PLAN.md` and `GUIDE.md`
  record the withdrawal.
- Own the meaning of tablebase evidence in `src/search/tablebase.zig`: the WDL
  vocabulary, probe preconditions, reserved-band score conversion and typed
  evidence. This module has no file, library or allocation dependency, so
  search policy stays testable with no tablebase file present.
- Confine every call into Fathom to `src/engine/syzygy.zig`. That adapter
  translates the board into Fathom's bitboard convention and translates the
  result back into the inward contract. It makes no chess-policy decision.
- Treat preconditions as chess-rule facts owned by the inward layer: Syzygy
  indexes positions without castling rights, and its WDL tables are valid only
  at a reset halfmove clock. Both are checked before the adapter probes.
- Score a proven win as `tablebase_max - ply` inside the reserved
  `31,488...31,743` band, so a nearer conversion outranks a deeper one while
  every tablebase magnitude stays below the mate band and above the ordinary
  band. Score cursed wins and blessed losses as exact zero: under the
  fifty-move rule those games are drawn, and a partial bonus would make search
  chase a conversion the rules forbid.
- Carry `tablebase` provenance and an exact bound on every hit. Perfect play is
  not an estimate, and no consumer may mistake it for a searched score.
- Degrade safely by construction. A missing, empty or unreadable path yields a
  handle with `largest == 0`, which every consumer already treats as "no
  evidence". Absent tablebases are an ordinary state, never an engine failure.

## Consequences

Producers are the board's bitboards, side to move, castling rights, halfmove
clock and en-passant square. The adapter transforms them; the inward contract
transforms Fathom's answer into typed evidence. Consumers are the future root
filter and interior probe, neither of which this record authorizes.

Terminal, repetition and fifty-move detection continue to run before any
selective mechanism, so tablebase evidence can never overwrite a result the
rules already decide. Legality, castling, en-passant and promotion identity
remain owned by the board layer.

`tb_init` is not thread safe; the handle therefore follows the existing
resource-generation rule and is built before workers publish and freed after
they join. WDL probing is thread safe once initialized, so Phase 6.2 SMP needs
no new contract here. Probing performs file-backed reads inside Fathom, which
is why the adapter sits in the engine layer rather than the pure search layer.

Linking libc is a permanent, cross-cutting change to every artifact. It also
means the build now compiles C, so a toolchain or vendored-source problem can
break builds in a way no Zig-only change could.

## Verification

- Pure inward tests cover WDL negation symmetry, every precondition, the
  reserved-band boundaries at ply zero and `MAX_PLY - 1`, score antisymmetry,
  exact-zero rule-fifty conversion and typed provenance. None needs a
  tablebase file.
- Adapter tests prove an empty path, a nonexistent path and an uninitialized
  handle all degrade to a safe unloaded state, and that paths which cannot
  cross the C ABI are rejected before probing.
- A compile-time assertion binds Manta's WDL enum to Fathom's constants, so a
  renumbered upstream fails the build instead of silently misreporting.
- Debug, ReleaseSafe and ReleaseFast suites, `zig fmt`, lint, the policy check
  and the portable build all pass. The frozen MAN-S19 depth-six fingerprint
  remains exactly `744,899`: this step adds no search behavior.
- Native Windows x86-64 is validated locally. Linux and macOS builds with libc
  linked are **not** locally validated, because this build rejects
  cross-targets by policy and the local WSL2 environment has no Zig toolchain.
  Required CI must confirm the remaining supported targets before release.

## Traceability

Supports `FUNC-004`, `FUNC-005`, `SCORE-001`, `SCORE-005`, `PERF-009`,
`FILE-001`, `QUAL-013` through `QUAL-016`, and Step 5.2 in `PLAN.md`.
