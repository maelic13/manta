# Manta

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logo/manta_dark.png">
    <source media="(prefers-color-scheme: light)" srcset="logo/manta_light.png">
    <img alt="Manta logo" src="logo/manta_light.png" width="320">
  </picture>
</p>

Manta is an open-source UCI chess engine written in Zig.

## Status

Manta's development foundations are complete, and engine implementation is
beginning. There is no playable release yet.

The first release will support standard chess through the UCI protocol. Manta
does not include a graphical user interface; it is intended to run in a
compatible chess GUI or other UCI host.

## Releases

Verified binaries for supported platforms will be attached to published GitHub
releases. User-visible changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## Development

Development requires Zig 0.16.0. Build with `zig build`; contributors should
follow the complete [development and editor guidance](docs/DEVELOPMENT.md).

Usage instructions will be added when the engine becomes playable.

## License

Copyright (C) 2026 Miloslav Macůrek.

Manta is free software licensed under the
[GNU General Public License version 3 or later](LICENSE).
