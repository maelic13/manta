# Releasing Manta

Manta uses semantic-version-compatible release numbers and `vMAJOR.MINOR.PATCH`
Git tags. The engine reports the same version without the `v` prefix.

- **Major** (`2.0.0`) marks a major engine generation or incompatible public
  contract. A major generation may be displayed informally as “Manta 2”.
- **Minor** (`1.1.0`) marks a meaningful backward-compatible feature or
  playing-strength release.
- **Patch** (`1.0.1`) marks correctness, portability, build or documentation
  fixes and deliberately small changes.

## Release procedure

1. Set the version in `build_support/version.zig` and `build.zig.zon`.
2. Move user-visible changes from `Unreleased` to a dated changelog section.
3. Run the complete local release gate and open the `dev` to `master` pull
   request. Required CI must pass before squash-merging it.
4. On the clean release commit, create and push an annotated tag:

   ```text
   git tag -a v1.0.0 -m "Manta 1.0.0"
   git push origin v1.0.0
   ```

5. Create the GitHub Release for that existing tag using the matching
   `CHANGELOG.md` section as its notes. Publishing it starts the release
   workflow.
6. Confirm that all five binaries and `SHA256SUMS` are attached and that the
   release workflow passed its native smoke tests and cross-platform bench
   agreement.

The workflow builds portable ReleaseFast binaries natively on Windows x86-64,
Linux x86-64, Linux ARM64, macOS x86-64 and macOS ARM64. It rejects a tag that
does not match the package version. Tags, pushes and GitHub Releases remain
maintainer-owned actions.
