# Manta development

Manta requires exactly Zig 0.16.0. Use ZLS 0.16.0 so editor diagnostics
match the compiler; no editor-specific configuration is required.

During an edit loop, run the bounded subset first:

```powershell
zig build test-fast -Doptimize=Debug
```

It runs executable library/domain and UCI unit tests plus build-version,
artifact and repository-policy checks. It deliberately excludes long search
qualification, fuzz, child-process transcript and historical-tool suites; it
never replaces the full gate required after behavior freezes.

For UCI/controller work, the focused process gate avoids unrelated long
qualification suites while still building and driving every active transcript:

```powershell
zig build test-uci -Doptimize=Debug
zig build test-uci -Doptimize=ReleaseSafe
```

Run these gates before committing:

```powershell
zig build check
zig build lint
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
```

The full `test` step compiles its artifacts in parallel and then executes test
processes serially. Several qualification roots are CPU-heavy; launching them
together can starve a correct Zig test runner beyond its fixed response bound.
Do not add `-j1`: ordinary build parallelism remains available during compile,
while the build graph itself owns reliable test-process scheduling.

Native fuzz exploration uses Zig's bounded fuzzer under Linux. Zig 0.16 does
not implement its built-in fuzzer on Windows, so Windows development uses WSL2:

```text
zig build fuzz -Doptimize=ReleaseSafe \
  --cache-dir /tmp/manta-zig-cache/local \
  --global-cache-dir /tmp/manta-zig-cache/global \
  --fuzz=100K
```

The ordinary `test` gate still runs each fuzz entry point as a deterministic
smoke test on every supported platform. Any discovered failure must be reduced
to a chess-meaningful deterministic regression before it is considered fixed.
Linux-local cache paths avoid unreliable cache renames when the checkout is on
the Windows-mounted `/mnt` filesystem.

The versioned board workload can be preflighted without timing or run in its
required modes:

```text
zig build board-bench -- --preflight-only
zig build board-bench -Doptimize=Debug
zig build board-bench -Doptimize=ReleaseFast
```

See [`BOARD_BENCHMARK.md`](BOARD_BENCHMARK.md) for the exact profile and
measurement contract. Build before beginning a timed run and keep the host
idle throughout measurement.

The scalar fallback evaluator has a separate versioned preflight and bounded
throughput diagnostic:

```text
zig build eval-bench -- --preflight-only
zig build eval-bench -Doptimize=ReleaseFast
```

See [`EVAL_BENCHMARK.md`](EVAL_BENCHMARK.md) for its frozen corpus, checksum,
sampling and Step-3.2 baseline.

Build the fastest supported executable for the current machine with one
command:

```powershell
zig build
```

This defaults to `ReleaseFast`, host-native code generation and
`-Dprofile=auto`. It keeps the ordinary development executable in
`zig-out/bin` and also writes a truthful, versioned filename under
`zig-out/dist`, for example
`manta-v1.0.0-windows-x86-64-native.exe`.

Build the portable baseline for the current platform with:

```powershell
zig build -Dportable
```

`-Dnative` is an explicit spelling of the default and cannot be combined with
`-Dportable`. `-Dprofile=x86-64` and `-Dprofile=arm64` select the matching
current baseline. The reserved `avx2`, `pext` and `avx512` profiles fail until
measured implementations exist. `-Dpgo` likewise fails until the representative
bench and PGO pipeline exist; no optimization request is silently ignored.
Manta supports native builds only, so direct `-Dtarget` and `-Dcpu` overrides
are rejected. Non-default `-Doptimize` modes are available for diagnosis and
are stated in the canonical filename.

`zig build fmt` checks canonical formatting and parses every repository Zig
source. `zig build policy` checks required files, local Markdown links and
anchors, PLAN/GUIDE step synchronization, requirement IDs, dependency
direction and public-reference policy. Both are included in `zig build lint`.
`zig build test` also builds Manta and drives every currently active canonical
UCI transcript as a real child process with bounded waits.

Compare deterministic random perft divide maps with a locally supplied UCI
oracle executable using:

```powershell
zig build differential-perft -- --oracle C:\path\to\engine.exe --positions 1000 --depth 3
```

The executable is a local development input and is never downloaded, embedded
or committed by this command. The fixed default seed is printed with the result
and can be overridden explicitly with `--seed`.

Sliding-attack tables are checked-in deterministic build inputs, so ordinary
builds never search for constants or initialize them at runtime. After an
intentional change to their generator or magic constants, regenerate them with:

```powershell
zig build generate-attacks
```

Then run the complete tests and review the binary diff. The exhaustive chess-
domain test compares both retained sliding algorithms with an independent
coordinate oracle over every relevant blocker subset.

Tests use named fixed seeds from `tests/support/seeds.zig`; never seed a
reproducible test from the clock or operating system. Temporary files use the
test runner's temporary directory and disappear on success. Retained local
failure evidence belongs under the gitignored `artifacts/<suite>/` tree and
must be enabled explicitly; normal test runs leave the worktree untouched.

The lint command builds the source-pinned ZLint 0.9.1 executable for the host
and applies the reviewed rules in [`zlint.json`](../zlint.json). Its isolated
tool package may fetch sources into ignored `tools/zlint/zig-pkg/`; ordinary
build, check and test commands never resolve those dependencies. ZLint is a
development tool, never a Manta runtime dependency. The repository avoids
negated `.gitignore` entries because this ZLint release interprets them as
lint exclusions.

The authoritative CI workflow runs identically for pull requests to `master`,
pushes to `master` and manual dispatches. It checks five native host targets,
then reduces the quality and native results to `CI / gate`. CI installs the
exact compiler from official platform archives, checks their pinned SHA-256
values and caches only the verified toolchain through current major action
versions. Setup is bounded to six minutes. This pull-request workflow validates
artifacts but does not publish them.

Each native matrix job builds and smoke-tests its canonically named portable
baseline through the same build entry point used locally. The supported native
matrix is Windows x86-64 plus Linux and macOS on x86-64
and ARM64. Windows ARM64 is excluded because Zig 0.16.0's native compiler
crashed during ordinary project tests on the hosted runner. Reconsider it at a
stable Zig upgrade, and restore it only when the normal build/test/smoke path
passes without target-specific handling.

Protocol work must follow the normative [UCI behavioral contract](UCI.md) and
its [canonical transcript corpus](../tests/uci/README.md). Activate a staged
transcript only in its owning phase; do not weaken expected behavior to match an
incomplete implementation.

The separate `release.yml` workflow runs for a published semantic-version tag
or by manual dispatch against an existing tag. It builds the five supported
portable binaries natively, verifies UCI identity and cross-platform bench
agreement, creates `SHA256SUMS` and uploads the assets to that GitHub Release.
The exact maintainer procedure is in [`RELEASING.md`](RELEASING.md).

WSL2 is the normal local Linux x86-64 environment; native target execution
remains required before a release artifact can be published. The sole
publisher verifies the release pull-request gate and post-merge `master` gate,
then resets `dev` only after the release and local worktree are final and clean.
