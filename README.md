# Manta

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logo/manta_dark.png">
    <source media="(prefers-color-scheme: light)" srcset="logo/manta_light.png">
    <img alt="Manta logo" src="logo/manta_light.png" width="360">
  </picture>
</p>

Manta is a strong, open-source UCI chess engine written in Zig. It provides the
chess-playing engine only; use it with a UCI-compatible chess interface for a
graphical board, game management and engine matches.

Manta 1 combines a tuned classical evaluation with alpha-beta search, lazy SMP,
clock management, pondering and optional Syzygy tablebase probing. Its
one-thread search is deterministic, and its built-in benchmark provides a
reproducible installation check.

## Download

Download Manta from the [latest GitHub Release](https://github.com/maelic13/manta/releases/latest).
Manta 1.0.0 provides portable 64-bit binaries for:

- Windows x86-64: `manta-v1.0.0-windows-x86-64.exe`
- Linux x86-64: `manta-v1.0.0-linux-x86-64`
- Linux ARM64: `manta-v1.0.0-linux-arm64`
- macOS x86-64: `manta-v1.0.0-macos-x86-64`
- macOS ARM64: `manta-v1.0.0-macos-arm64`

The first release contains portable builds only. It does not contain separate
PEXT, AVX2, AVX-512 or profile-guided builds.

Every release also publishes `SHA256SUMS`. Verify a download against it with
`sha256sum -c SHA256SUMS --ignore-missing` on Linux, `shasum -a 256 -c
SHA256SUMS --ignore-missing` on macOS, or `Get-FileHash <binary> -Algorithm
SHA256` on Windows.

## Use Manta

1. Download the binary for your operating system and processor.
2. On Linux or macOS, make it executable with `chmod +x <binary>`.
3. Add the executable as a UCI engine in your chess interface.
4. Configure its options in the interface and start an analysis or game.

Release binaries are not code-signed or notarized. macOS quarantines a
downloaded executable until you clear it with
`xattr -d com.apple.quarantine <binary>`, and Windows SmartScreen may warn on
first run.

The engine supports the standard UCI lifecycle, position and search commands,
including `uci`, `isready`, `setoption`, `ucinewgame`, `position`, `go`, `stop`,
`ponderhit` and `quit`. It also provides `bench` for deterministic diagnostics.
See [docs/UCI.md](docs/UCI.md) for the complete protocol contract.

### UCI options

| Option | Default | Range or values | Purpose |
|---|---:|---|---|
| `Threads` | 1 | 1–1024 | Search worker threads |
| `Hash` | 64 | 1–1048576 MiB | Transposition-table size |
| `Clear Hash` | — | button | Clear the transposition table |
| `Ponder` | false | true/false | Allow pondering |
| `Move Overhead` | 10 | 0–5000 ms | Reserve time for GUI, OS and network delay |
| `SyzygyPath` | empty | path list | Directories containing Syzygy tablebases |
| `SyzygyProbeDepth` | 1 | 1–100 | Minimum search depth for non-root probing |
| `SyzygyProbeLimit` | 7 | 0–7 pieces | Largest tablebase cardinality to probe |
| `Syzygy50MoveRule` | true | true/false | Respect the fifty-move rule in tablebase results |

## Build from source

Manta requires Zig 0.16.0. From the repository root:

```text
zig build
```

This creates a native `ReleaseFast` executable under `zig-out/bin` and a named
artifact under `zig-out/dist`. For a portable binary suitable for distribution:

```text
zig build -Dportable
```

Useful build options are:

| Option | Meaning |
|---|---|
| `-Dnative` | Optimize for the build machine; this is the default |
| `-Dportable` | Use the portable baseline for the current OS and architecture |
| `-Dprofile=x86-64` or `-Dprofile=arm64` | Select the matching portable architecture profile |
| `-Doptimize=Debug\|ReleaseSafe\|ReleaseFast\|ReleaseSmall` | Select the Zig optimization mode |
| `-Dversion=X.Y.Z` | Override the embedded semantic version for a controlled build |

Cross-compilation and specialized ISA/PGO profiles are not supported in Manta
1.0.0. Release artifacts are built natively on each supported platform.

To run the focused development gate or the complete test suite:

```text
zig build test-fast
zig build test
```

Additional development commands and build contracts are documented in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Benchmark

Run `bench` through the UCI input stream. An optional depth, thread count and
hash size may be supplied:

```text
bench
bench 13
bench 13 1 64
```

The final `bench total` line reports elapsed time, nodes, nodes per second and
the deterministic one-thread node fingerprint. Throughput varies by hardware;
the node count is the useful compatibility check.

## License

Manta is released under the GNU General Public License version 3 or later. See
[LICENSE](LICENSE). The bundled Fathom tablebase probing code retains its own
copyright notices under `third_party/fathom`.

## Acknowledgements

Manta benefits from the knowledge shared by the open-source chess-programming
community. Special thanks go to the Stockfish project and its contributors for
their exceptional public engineering, testing culture and research.
