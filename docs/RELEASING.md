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

A release is cut by pushing an annotated `vX.Y.Z` tag on `master` through
`.github/workflows/release.yml`; nothing else creates a GitHub Release. There
are no permanent release branches.

1. Branch from `master` and set the version in `build_support/version.zig` and
   `build.zig.zon`.
2. Move user-visible changes from `Unreleased` to a dated
   `## [X.Y.Z] - YYYY-MM-DD` section in `CHANGELOG.md` that opens with a short
   summary paragraph and a `### Highlights` list (the GitHub Release page shows
   the unwrapped summary, the `### Highlights` list and a link to the full
   changelog at the tag), then commit the release preparation on the branch.
3. Run the local release gate (`zig build lint`, `zig build check`,
   `zig build test` in Debug/ReleaseSafe/ReleaseFast, and
   `python tools/ci/release_check.py check vX.Y.Z --base HEAD`) and open a pull
   request to `master` using the structured squash format (short imperative
   title, 72-column summary, test/gate results, and `Bench: <nodes>`).
4. **The PR is the release rehearsal.** Both `CI / gate` and
   `Release / Verify the complete matrix` must pass: the candidate run
   validates the metadata, builds all six portable binaries, smoke-tests and
   fingerprints every one against the declared `bench 6` count, packages the
   six archives with licences, `README.md` and `CHANGELOG.md`, and checks
   `SHA256SUMS`. Squash-merge the PR once green and delete the branch.
5. On the clean merged `master` commit, create and push the annotated tag:

   ```text
   git switch master
   git pull --ff-only origin master
   git tag -a v1.2.2 -m "Manta 1.2.2"
   git push origin v1.2.2
   ```

6. Pushing the tag triggers `.github/workflows/release.yml` in release mode. It
   re-validates the tag and ancestry on `master`, builds and smoke-tests all
   six portable targets, requires one shared `bench 6` fingerprint matching the
   declared count, packages the six archives and `SHA256SUMS`, and publishes
   the GitHub Release only after every check passes. Nothing is published on a
   failed run; to repair, delete the tag locally and on `origin`, fix `master`
   through a PR, and tag again.

## Patch release while `master` holds unreleased work

Land the fix on `master` by its own PR first. Then branch from the last release
tag (`vX.Y.0` or `vX.Y.(Z-1)`), cherry-pick the fix with `-x`, make the release
commit for `X.Y.Z`, rehearse it via manual `workflow_dispatch` of `Release` on
that branch, tag and push the tag, then delete the temporary patch branch.
`release_check.py line` accepts a patch tag (`Z > 0`) descending from `vX.Y.0`
on `master`.

The workflow builds portable ReleaseFast binaries natively on Windows, Linux
and macOS, each on x86-64 and ARM64. Portable binaries target `x86-64-v2` or the
ARM64 baseline, never the runner's processor. Tags, pushes and release merges
remain maintainer-owned actions.
