# Manta development

Manta requires exactly Zig 0.16.0. Use ZLS 0.16.0 so editor diagnostics
match the compiler; no editor-specific configuration is required.

Run these gates before committing:

```powershell
zig build check
zig build lint
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
```

`zig build fmt` checks canonical formatting and parses every repository Zig
source. `zig build policy` checks required files, local Markdown links and
anchors, PLAN/GUIDE step synchronization, requirement IDs and public-reference
policy. Both are included in `zig build lint`.

The lint command builds the source-pinned ZLint 0.9.1 executable for the host
and applies the reviewed rules in [`zlint.json`](../zlint.json). Its first run
may fetch source packages into the ignored `zig-pkg/` directory. ZLint is a
development tool, never a Manta runtime dependency. The repository avoids
negated `.gitignore` entries because this ZLint release interprets them as
lint exclusions.

For the fastest local executable, use:

```powershell
zig build -Doptimize=ReleaseFast -Dcpu=native
```

The authoritative CI workflow runs identically for pull requests to `master`,
pushes to `master` and manual dispatches. It checks all six native host targets,
cross-builds all six explicit target triples and reduces the result to
`CI / gate`. It does not publish artifacts.

GitHub enables manual dispatch only after the workflow exists on default
`master`. Before its first release merge, validate it by pushing `dev` and
opening an unmerged draft pull request to `master`.

WSL2 is the normal local Linux x86-64 environment; native target execution
remains required before a release artifact can be published. The sole
publisher verifies the release pull-request gate and post-merge `master` gate,
then resets `dev` only after the release and local worktree are final and clean.
