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

- [Latest release](https://github.com/maelic13/manta/releases/latest)
- [All releases](https://github.com/maelic13/manta/releases)

Each release has one file per system. Pick the one that matches your computer:

| Your computer | File ends with |
|---|---|
| Windows PC with an Intel or AMD processor | `windows-x86-64.exe` |
| Windows PC with an ARM processor, such as Snapdragon | `windows-arm64.exe` |
| Linux with an Intel or AMD processor | `linux-x86-64` |
| Linux on ARM, such as a Raspberry Pi 4 or 5 with a 64-bit system | `linux-arm64` |
| Mac with an Intel processor | `macos-x86-64` |
| Mac with Apple silicon (M1 or later) | `macos-arm64` |

On Windows, *Settings → System → About → System type* tells you whether you
have an x64-based or an ARM-based processor.

The Intel and AMD downloads need a processor from 2008 or later: Intel Core i3,
i5 or i7 and newer, or AMD from the 2011 FX series onward (the `x86-64-v2`
level). Every PC that runs current Windows 11 qualifies. On an older processor,
such as a Core 2 or a Phenom II, the download stops immediately with an
illegal-instruction error; [build Manta from source](#build-from-source)
instead. The ARM downloads run on any 64-bit ARM processor.

The downloads are built to run on as many computers as possible. A build from
source targets your exact processor and is usually a little faster.

## Use Manta

1. Download the file for your computer, as described above.
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

Manta requires Zig 0.17.0. From the repository root:

```text
zig build
```

This creates a native `ReleaseFast` executable under `zig-out/bin` and a named
artifact under `zig-out/dist`. It is the fastest build Manta offers: the
compiler targets the exact processor it runs on, so the binary is typically
faster than the release download, but it may not start on a different
computer. To build the same kind of portable binary as a release download:

```text
zig build -Dportable
```

Useful build options are:

| Option | Meaning |
|---|---|
| `-Dnative` | Optimize for the build machine; this is the default |
| `-Dportable` | Build like the release downloads: `x86-64-v2` on Intel and AMD, any 64-bit ARM processor on ARM |
| `-Dprofile=x86-64` or `-Dprofile=arm64` | Select the matching portable architecture profile |
| `-Doptimize=Debug\|ReleaseSafe\|ReleaseFast\|ReleaseSmall` | Select the Zig optimization mode |
| `-Dversion=X.Y.Z` | Override the embedded semantic version for a controlled build |

Cross-compilation is not supported, and the reserved `avx2`, `pext` and
`avx512` profiles and `-Dpgo` fail rather than silently degrade; the native
default already uses every instruction-set extension the host provides.
Release artifacts are built natively on each supported platform.

To run the focused development gate or the complete test suite:

```text
zig build test-fast
zig build test
```

Additional development commands and build contracts are documented in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Benchmark

Type `bench` into the running engine, the same way a chess interface sends it
commands. It searches 40 fixed positions to depth 6, or to the depth you give,
and can repeat the whole set up to 16 times:

```text
bench
bench 11
bench 11 3
```

Bench always uses one thread and its own 16 MiB hash, whatever `Threads` and
`Hash` are set to. The summary at the end reports the nodes searched, the time
taken and the speed in nodes per second. Speed depends on your computer, but
the node count does not, so it shows whether your build behaves correctly. For
Manta 1.2.1, plain `bench` searches `355,879` nodes on every supported system.

## License

Manta is released under the GNU General Public License version 3 or later. See
[LICENSE](LICENSE). The bundled Fathom tablebase probing code retains its own
copyright notices under `third_party/fathom`.

## Acknowledgements

Manta benefits from the knowledge shared by the open-source chess-programming
community. Special thanks go to the Stockfish project and its contributors for
their exceptional public engineering, testing culture and research.
