<#
.SYNOPSIS
    Run an SPRT self-play match between two Manta binaries using fastchess.

.DESCRIPTION
    Starts a fastchess match with the built-in SPRT stopping rule.  The match
    runs until the test accepts H0, accepts H1, or exhausts the registered game
    budget. Real-time output is printed to the console. A budget-exhausted test
    has not accepted H1 and therefore cannot promote the candidate.

    This is the Rarog harness ported to Manta. It was originally unchanged in
    every measurement-affecting respect so the two ledgers stayed comparable;
    Manta has since removed adjudication entirely (see GAME END below), which
    is a deliberate divergence and breaks comparability with any adjudicated
    ledger, Manta's own pre-2026-09-12 results included. Other Manta-specific
    differences are limited to:
      - the provenance sidecar records `zig` instead of `rustc`;
      - `option.Threads` is sent only if the engine actually advertises it
        (docs/UCI.md §7 stages the option registry by phase; a build without
        SMP answers `info string unknown option "threads" ignored`).

    Tooling:
      - fastchess (NOT cutechess-cli): faster, no Qt dependency, built-in SPRT.
        Install with ./tools/setup_tools.ps1, which places the pinned release
        at tools\bin\fastchess.exe. The cutechess GUI is still handy for
        *viewing* the resulting PGNs, but is not used to run matches.

    Conditions (unified with SPSA — one TC for tune and confirm, so there is no
    tune->confirm transfer gap):
      - tc=3+0.03 -> 3 s + 30 ms/move increment, CLOCK-based (default $TC).
                   Exercises the real time-management code (active under a
                   clock, unlike fixed movetime). 1% increment = the Stockfish
                   convention; generalizes across time controls.
      - LTC confirmation runs at tc=10+0.1 (pass -TC "10+0.1") at phase
        boundaries and for TC-suspect features.
      - Pass -MoveTime 0.1 for a fixed 100 ms/move sanity gauntlet.
      - Pass -Nodes N for a fixed-NODES diagnostic — it removes speed AND time
        management, so it answers "is the remaining gap pure search quality?"
        and nothing else. Never a strength gate.
      - Hash 64 MB, UHO_Lichess_4852_v1.epd opening book (random order): the
        Stockfish/OpenBench-standard "Unbalanced Human Openings" set —
        2,632,036 positions, 3-4 moves deep, curated to a ~+0.5-pawn White
        edge. Played from both colours per pair, so the imbalance is
        symmetric: unbiased but decisive. Cuts the draw rate, so SPRTs resolve
        in substantially fewer games, and it is large enough that opening reuse
        never correlates pairs. Legacy PGN books still work via -Book (format
        auto-detected from the extension).
      - GAME END: no adjudication of any kind. No resignation threshold, no
        draw-after-N-moves rule, no move cap. A game ends only by the rules of
        chess: checkmate, stalemate, fifty-move, threefold repetition or
        insufficient material. An adjudicator is a second, unvalidated engine
        judging the one under test, and it truncates precisely the conversion,
        fortress and mating phases where engines differ. Games are longer and
        the draw rate is higher than any adjudicated ledger, so results are not
        comparable across that boundary.
      - AFFINITY: fastchess before 1.7.0 did not correctly apply Windows
        process affinity, and 1.8.0 auto-topology guesses SMT siblings from
        alternating logical CPU IDs. This harness requires >=1.7.0, discovers
        physical cores through Windows, and supplies an explicit CPU list.
      - model=normalized (nElo) — fastchess default, more time-control-robust
        than logistic Elo.

    IMPORTANT - concurrency:
      In a self-play game only the side to move computes, so ~16 concurrent
      games already saturate 16 physical cores. Oversubscribing (e.g. the 32
      logical processors) halves NPS and changes the depth reached, distorting
      results. The default detects physical cores and leaves two free; it does
      not derive concurrency or affinity from logical-CPU numbering.

    CALIBRATION CHECK - run after a relevant runner, scheduler, topology,
    placement, TC, book, game-end policy, OS or hardware change:
        ./tools/sprt.ps1 `
            -EngineA "tools\test_engines\manta-null.exe" `
            -EngineB "tools\test_engines\manta-null.exe" `
            -NameA "NullA" -NameB "NullB" -Mode calibrate
        Calibration is a fixed 30,000-game identical-binary match. PASS
        requires the entire 95% normalized-Elo (nElo) interval inside
        [-5,+5] and zero anomalies. A project may inherit an unchanged exact
        instrument's retained qualification; do not rerun a null for each
        engine or candidate. Calibration never replaces compiler/build
        provenance for a non-identical A/B pair.

.PARAMETER EngineA
    Path to the new/candidate engine (usually in tools\test_engines).

.PARAMETER EngineB
    Path to the baseline engine (the current integration head, or a frozen
    reference copied into tools\test_engines).

.PARAMETER NameA / NameB
    Display names. Defaults: "New" / "Base".

.PARAMETER Mode
    "gainer"    -> H0: elo<=3,  H1: elo>=10 (default; demand a material gain).
    "simplify"  -> H0: elo<=-5, H1: elo>=0  (non-regression / cleanup).
    "calibrate" -> fixed-size identical-binary null match; no SPRT.
    "fixed"     -> fixed-size match, no SPRT stop rule (smoke tests, pilots).
    The explicit -Elo0/-Elo1 parameters override the mode if supplied.

.PARAMETER MaxGames
    Maximum games for an SPRT mode. Default 16000 and must be positive/even.
    Reaching it without H1 means park/revert, not acceptance from the point
    estimate. Fixed/calibration modes continue to use -Games.

.PARAMETER Hash
    Hash MB per engine. Default 64 (matches deployment).

.PARAMETER Concurrency
    Parallel games. Default 0 auto-detects physical cores and leaves two free.

.PARAMETER Threads / ThreadsA / ThreadsB
    Engine Threads for both sides (or per side). REQUIRES the engine to
    advertise a Threads option; a build that does not is refused for
    Threads > 1 rather than silently searching with one thread.

.PARAMETER Games
    Fixed game count for -Mode calibrate / -Mode fixed. Default 30000.

.PARAMETER CalibrationTolerance
    Calibration equivalence tolerance. Default 5 nElo. PASS requires the full
    reported 95% confidence interval inside [-tolerance,+tolerance].

.PARAMETER Seed
    Opening randomization seed. Default 0 generates and records a seed.

.PARAMETER TC
    Clock time control "base+inc" in seconds. Default "3+0.03".

.PARAMETER MoveTime
    Fixed seconds-per-move. Default 0 (use clock TC instead).

.PARAMETER Nodes
    Fixed NODES-per-move (fastchess `nodes=N`). Default 0 (use clock TC).
    Mutually exclusive with -MoveTime. Diagnostic only, never a strength gate.

.PARAMETER TimeMargin
    fastchess timeout margin in milliseconds. Default 20. This prevents small
    Windows scheduler / process IO jitter from being counted as a time
    forfeit. It does not change the engine's own time budget.

.PARAMETER ScoreCompletedTimeForfeits
    Score fully completed `loses on time` games when clock policy is part of
    the measured subject. The final timeout totals must exactly reconcile with
    completed game lines. Calibration, fixed-time and fixed-node runs cannot
    use this switch; non-time engine/protocol/infrastructure faults stay fatal.

.PARAMETER DryRun
    Resolve engines, manifests, options, placement, seed and test design, then
    exit before creating result artifacts or starting fastchess.

.PARAMETER Book
    Opening book, PGN or EPD (format auto-detected from the extension).
    Default tools\books\UHO_Lichess_4852_v1.epd.

.PARAMETER FastchessPath
    Path to fastchess.exe. Default tools\bin\fastchess.exe (or found on PATH).

.EXAMPLE
    ./tools/sprt.ps1 `
        -EngineA "tools\test_engines\manta-nullmove.exe" `
        -EngineB "tools\test_engines\manta-head.exe" `
        -NameA "NullMove" -NameB "Head" -Elo0 3 -Elo1 10 -MaxGames 16000

.EXAMPLE
    # 20-game smoke test that the harness itself works:
    ./tools/sprt.ps1 -EngineA a.exe -EngineB b.exe -Mode fixed -Games 20 -TC "1+0.01"
#>
param(
    [Parameter(Mandatory)][string]$EngineA,
    [Parameter(Mandatory)][string]$EngineB,
    [string]$NameA = "New",
    [string]$NameB = "Base",
    [ValidateSet("gainer", "simplify", "calibrate", "fixed")][string]$Mode = "gainer",
    [Nullable[int]]$Elo0 = $null,
    [Nullable[int]]$Elo1 = $null,
    [double]$Alpha = 0.05,
    [double]$Beta  = 0.05,
    [int]$Hash = 64,
    [int]$Concurrency = 0,
    [int]$Threads = 1,
    [Nullable[int]]$ThreadsA = $null,
    [Nullable[int]]$ThreadsB = $null,
    [int]$Games = 30000,
    [int]$MaxGames = 16000,
    [double]$CalibrationTolerance = 5,
    [int]$Seed = 0,
    [string[]]$OptionsA = @(),
    [string[]]$OptionsB = @(),
    [string]$TC = "3+0.03",
    [double]$MoveTime = 0,
    [int]$Nodes = 0,
    [int]$TimeMargin = 20,
    [switch]$ScoreCompletedTimeForfeits,
    [switch]$DryRun,
    [string]$Book = "$PSScriptRoot\books\UHO_Lichess_4852_v1.epd",
    [string]$FastchessPath = "$PSScriptRoot\bin\fastchess.exe"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "harness_common.ps1")

$gameEndProfile = Get-GameEndProfile
$gameEndArgs = @(Get-GameEndArgs)

# Per-engine Threads resolve to $Threads unless overridden. The game slot must
# hold the larger of the two, so the core arithmetic uses max(ThreadsA,ThreadsB).
if ($null -eq $ThreadsA) { $ThreadsA = $Threads }
if ($null -eq $ThreadsB) { $ThreadsB = $Threads }
if ($ThreadsA -lt 1 -or $ThreadsB -lt 1) { throw "-ThreadsA/-ThreadsB must be >= 1." }
$maxThreads = [Math]::Max($ThreadsA, $ThreadsB)

$concurrencyInfo = Resolve-HarnessConcurrency -Requested $Concurrency -ThreadsPerGame $maxThreads
$Concurrency = $concurrencyInfo.Concurrency
$AffinityCpus = Get-HarnessAffinityCpuList -Concurrency $Concurrency -ThreadsPerGame $maxThreads
$Seed = New-HarnessSeed -Requested $Seed

# AFFINITY vs THREADS: fastchess 1.8.0 `-use-affinity` binds each GAME to a
# single core regardless of the engine Threads option — verified by direct core
# sampling on Rarog: Threads=4 concurrency=3 pinned only 3 cores (4 engine
# threads crammed onto 1), starving every multi-thread search. At Threads=1 the
# one-core-per-game rule is exactly right and the explicit list still removes
# the Zen-3 CCX placement bias, so it stays. At Threads>1 the OS scheduler
# spreads the pool across cores far better than fastchess's broken pinning, so
# `-use-affinity` is dropped, so Threads>1 requires a matching retained null
# calibration for this OS-scheduled placement.
if ($maxThreads -gt 1) {
    $affinityArgs = @()
    Write-Host "AFFINITY: -use-affinity DROPPED for Threads>1 (fastchess 1.8.0 pins 1 core/game, which starves multi-thread engines). OS-scheduled across all physical cores; requires matching retained Threads calibration." -ForegroundColor Yellow
} else {
    $affinityArgs = @('-use-affinity', $AffinityCpus)
}

if ($Mode -eq "calibrate" -or $Mode -eq "fixed") {
    if ($Games -lt 2 -or ($Games % 2) -ne 0) { throw "-Games must be a positive even number." }
    if ($CalibrationTolerance -le 0) { throw "-CalibrationTolerance must be positive." }
    if ($ThreadsA -ne $ThreadsB) { throw "Calibration must be symmetric: -ThreadsA ($ThreadsA) must equal -ThreadsB ($ThreadsB)." }
}
if ($Mode -ne "calibrate" -and $Mode -ne "fixed" -and
    ($MaxGames -lt 2 -or ($MaxGames % 2) -ne 0)) {
    throw "-MaxGames must be a positive even number."
}

# Resolve SPRT bounds from mode unless explicitly overridden.
if ($null -eq $Elo0) { $Elo0 = if ($Mode -eq "simplify") { -5 } else { 3 } }
if ($null -eq $Elo1) { $Elo1 = if ($Mode -eq "simplify") {  0 } else { 10 } }
if ($Mode -ne "calibrate" -and $Mode -ne "fixed" -and $Elo0 -ge $Elo1) {
    throw "SPRT requires -Elo0 lower than -Elo1."
}

# Resolve the search limit: clock (default) unless a fixed movetime or a fixed
# node count is given. All three are mutually exclusive; fastchess would accept
# two limits at once and silently apply whichever it parses last, so refuse.
if ($MoveTime -gt 0 -and $Nodes -gt 0) {
    throw "-MoveTime and -Nodes are mutually exclusive: pick one search limit."
}
if ($ScoreCompletedTimeForfeits -and
    ($Mode -eq 'calibrate' -or $MoveTime -gt 0 -or $Nodes -gt 0)) {
    throw "-ScoreCompletedTimeForfeits is permitted only for a non-calibration clock match."
}
if ($Nodes -gt 0) {
    $tcArg   = "nodes=$Nodes"
    $tcLabel = "nodes=$Nodes (fixed nodes/move; NO time management)"
    Write-Host "NOTE: fixed-nodes match - speed and time management are both removed." -ForegroundColor Yellow
    Write-Host "      Diagnostic only. Not a strength gate: TM is invisible here." -ForegroundColor Yellow
} elseif ($MoveTime -gt 0) {
    $tcArg   = "st=$MoveTime"
    $tcLabel = "st=$MoveTime (fixed ${MoveTime}s/move)"
} else {
    $tcArg   = "tc=$TC"
    $tcLabel = "tc=$TC (clock)"
}

# Locate fastchess.
$fastchess = $FastchessPath
if (-not (Test-Path $fastchess)) {
    $onPath = Get-Command fastchess -ErrorAction SilentlyContinue
    if ($onPath) { $fastchess = $onPath.Source }
    else {
        throw "fastchess not found at '$FastchessPath' or on PATH. Run ./tools/setup_tools.ps1."
    }
}
foreach ($p in @($EngineA, $EngineB, $Book)) {
    if (-not (Test-Path $p)) { throw "Not found: $p" }
}

$EngineA = (Resolve-Path $EngineA).Path
$EngineB = (Resolve-Path $EngineB).Path
$Book    = (Resolve-Path $Book).Path

# MANTA OPTION REGISTRY (docs/UCI.md §7). Options are advertised only when the
# owning capability exists, so the harness asks each binary what it supports
# instead of assuming. Sending an unsupported option is not a hard error in
# Manta — it answers `info string unknown option ... ignored` — which is
# exactly why it must be caught here: a Threads=4 match against a build with no
# SMP would run single-threaded and report a meaningless number.
$optionsAdvertisedA = @(Get-EngineUciOptions -Path $EngineA)
$optionsAdvertisedB = @(Get-EngineUciOptions -Path $EngineB)
$supportsThreadsA = $optionsAdvertisedA -contains 'Threads'
$supportsThreadsB = $optionsAdvertisedB -contains 'Threads'
if ($ThreadsA -gt 1 -and -not $supportsThreadsA) {
    throw "$NameA does not advertise a Threads option; -ThreadsA $ThreadsA cannot be honoured."
}
if ($ThreadsB -gt 1 -and -not $supportsThreadsB) {
    throw "$NameB does not advertise a Threads option; -ThreadsB $ThreadsB cannot be honoured."
}
# Assign in statements, NOT as `$x = if (...) { @("...") }`: a single-element
# array returned from an `if` expression unrolls to a bare string, and splatting
# a string into a native command spreads it one CHARACTER per argument
# (fastchess: 'Option "-engine" expects key=value pairs, got "o"').
$threadArgsA = @()
$threadArgsB = @()
if ($supportsThreadsA) { $threadArgsA = @("option.Threads=$ThreadsA") }
if ($supportsThreadsB) { $threadArgsB = @("option.Threads=$ThreadsB") }
if (-not ($supportsThreadsA -and $supportsThreadsB)) {
    Write-Host "NOTE: Threads option not advertised by $(@(if(-not $supportsThreadsA){$NameA}; if(-not $supportsThreadsB){$NameB}) -join ' and ') - not sent. Engines run at their built-in one-thread default." -ForegroundColor Yellow
}
if ($optionsAdvertisedA -notcontains 'Hash') {
    throw "$NameA does not advertise a Hash option; the -Hash $Hash setting would be silently ignored."
}
if ($optionsAdvertisedB -notcontains 'Hash') {
    throw "$NameB does not advertise a Hash option; the -Hash $Hash setting would be silently ignored."
}

$shaA = Get-HarnessSha256 $EngineA
$shaB = Get-HarnessSha256 $EngineB
if ($Mode -eq "calibrate" -and $shaA -ne $shaB) {
    throw "Calibration requires byte-identical engine binaries (SHA-256 differs)."
}
if ($Mode -eq "gainer" -or $Mode -eq "simplify") {
    # Identical binaries ARE legitimate when the two sides differ by UCI options
    # or by Threads — running one binary removes the per-build codegen offset
    # from the measurement. Refuse only when the binary, the options AND the
    # thread counts all match, because then the "test" is a null dressed as an
    # SPRT.
    if ($shaA -eq $shaB) {
        $sameOptions = (($OptionsA -join '|') -eq ($OptionsB -join '|'))
        if ($sameOptions -and $ThreadsA -eq $ThreadsB) {
            throw "Identical binaries, options AND Threads require -Mode calibrate; an SPRT centered around 0 is not a valid null calibration."
        }
        Write-Host "NOTE: same binary on both sides, differing only by UCI options -" -ForegroundColor Yellow
        Write-Host "      A: $($OptionsA -join ', ')   B: $($OptionsB -join ', ')" -ForegroundColor Yellow
    }
}
$fcInfo = Assert-AffinityFastchess -Path $fastchess

# Book format auto-detected from the extension (.epd -> format=epd, else pgn),
# so -Book can point at either the UHO EPD or a legacy PGN book.
$bookFormat = if ([System.IO.Path]::GetExtension($Book) -ieq ".epd") { "epd" } else { "pgn" }

# Validate both engines' provenance manifests (written by build_test.ps1).
# A real run copies them into the result dir, so the result is
# permanently self-describing. Schema 2 binds the sidecar to the exact binary;
# a stale or swapped sidecar fails before any games start. Warn-not-fail on
# absence for legacy hand-built binaries.
# Local-only: tools/results/ is gitignored; nothing here reaches a release.
$engineManifests = @{}
$engineManifestPaths = @{}
foreach ($pair in @(@($EngineA, $NameA), @($EngineB, $NameB))) {
    $manifest = [System.IO.Path]::ChangeExtension($pair[0], ".json")
    if (Test-Path $manifest) {
        $manifestData = Get-Content $manifest -Raw | ConvertFrom-Json
        $engineManifests[$pair[1]] = $manifestData
        $engineManifestPaths[$pair[1]] = $manifest
        if ($manifestData.binary_sha256) {
            $actualHash = Get-HarnessSha256 $pair[0]
            if ($actualHash -ne $manifestData.binary_sha256) {
                throw ("PROVENANCE MISMATCH - sidecar does not describe the selected binary.`n" +
                       "  Engine:   $($pair[1])`n" +
                       "  Actual:   $actualHash`n" +
                       "  Sidecar:  $($manifestData.binary_sha256)`n" +
                       "Rebuild it with tools/build_test.ps1.")
            }
        } else {
            Write-Warning "Legacy manifest for $($pair[1]) is not bound to its binary SHA-256."
        }
        if ($manifestData.git_dirty) {
            Write-Warning "Manifest for $($pair[1]) records a dirty source tree; the build is not reproducible from git_sha alone."
        }
    } else {
        Write-Host "NOTE: no manifest next to $(Split-Path $pair[0] -Leaf) - result will lack provenance for $($pair[1])." -ForegroundColor Yellow
    }
}

# COMPILER-EQUALITY GUARD - the toolchain-pin analogue for BINARIES. A zig
# version change between building engine A and engine B folds the compiler
# delta into the measured Elo, and no null pair can see it: a null runs ONE
# binary against itself, so both sides always share a compiler. Rarog hit this
# for real (a rustc patch bump produced three unrelated subsystems all reading
# about -8 Elo), which is why this hard-fails rather than warns.
$compilers = @{}
foreach ($pair in @(@($EngineA, $NameA), @($EngineB, $NameB))) {
    if ($engineManifests.ContainsKey($pair[1])) {
        $compilers[$pair[1]] = $engineManifests[$pair[1]].zig
    } else {
        Write-Warning ("No manifest for $($pair[1]) - compiler equality NOT checkable. " +
            "Rebuild it with tools/build_test.ps1 before trusting a small verdict.")
    }
}
if ($compilers.Count -eq 2 -and $compilers[$NameA] -and $compilers[$NameB]) {
    $cA = $compilers[$NameA]; $cB = $compilers[$NameB]
    if ($cA -ne $cB) {
        throw ("COMPILER MISMATCH - this match would measure the compiler, not the change.`n" +
               "  $NameA : $cA`n  $NameB : $cB`n" +
               "Rebuild BOTH engines with the pinned toolchain " +
               "(build_support/zig_version.zig) via tools/build_test.ps1, then re-run.")
    }
    Write-Host "  Compiler equality OK: zig $cA"
}

if ($engineManifests.Count -eq 2) {
    $flavorA = $engineManifests[$NameA].flavor
    $flavorB = $engineManifests[$NameB].flavor
    $contractA = if ($flavorA) { Get-HarnessBuildContract -Flavor $flavorA } else { $null }
    $contractB = if ($flavorB) { Get-HarnessBuildContract -Flavor $flavorB } else { $null }
    if ($contractA -and $contractB -and $contractA -ne $contractB) {
        throw ("BUILD FLAVOR MISMATCH - both sides must use the same target/PGO contract.`n" +
               "  $NameA : $flavorA ($contractA)`n  $NameB : $flavorB ($contractB)")
    }
    if ($contractA -and $contractB) {
        Write-Host "  Build contract equality OK: $contractA (features remain manifest-visible)"
    }
}

if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN: preflight passed; no game process or result artifact was started." -ForegroundColor Yellow
    Write-Host "  ${NameA}: SHA-256 $shaA, Threads=$ThreadsA"
    Write-Host "  ${NameB}: SHA-256 $shaB, Threads=$ThreadsB"
    Write-Host "  TC: $tcLabel; Hash=${Hash}MB; concurrency=$Concurrency; seed=$Seed"
    Write-Host "  SPRT: [$Elo0,$Elo1], alpha=$Alpha, beta=$Beta, cap=$MaxGames"
    Write-Host "  Completed time forfeits: $(if ($ScoreCompletedTimeForfeits) { 'scored after reconciliation' } else { 'fatal' })"
    exit 0
}

$resultsDir = Join-Path $PSScriptRoot "results"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$pgnOut    = Join-Path $resultsDir "sprt_${NameA}_vs_${NameB}_${timestamp}.pgn"
$logOut    = Join-Path $resultsDir "sprt_${NameA}_vs_${NameB}_${timestamp}.log"
$manifestPath = [System.IO.Path]::ChangeExtension($pgnOut, ".manifest.txt")
foreach ($name in $engineManifestPaths.Keys) {
    Copy-Item -LiteralPath $engineManifestPaths[$name] `
        -Destination (Join-Path $resultsDir "sprt_${NameA}_vs_${NameB}_${timestamp}.${name}.manifest.json") -Force
}

$repoSha = (git rev-parse HEAD 2>$null)
if (-not $repoSha) { $repoSha = "n/a" } else { $repoSha = $repoSha.Trim() }
@(
    "mode:            $Mode"
    "engineA:         $NameA = $EngineA"
    "engineA_sha256:  $shaA"
    "engineB:         $NameB = $EngineB"
    "engineB_sha256:  $shaB"
    "repo_revision:   $repoSha"
    "test_design:     $(if ($Mode -eq 'calibrate') { "fixed ${Games}-game null; tolerance +/-${CalibrationTolerance} nElo" } elseif ($Mode -eq 'fixed') { "fixed ${Games}-game match; no stop rule" } else { "SPRT elo0=$Elo0 elo1=$Elo1 alpha=$Alpha beta=$Beta model=normalized" })"
    "game_budget:     $(if ($Mode -eq 'calibrate' -or $Mode -eq 'fixed') { $Games } else { $MaxGames })"
    "time_control:    $tcLabel; timemargin=${TimeMargin}ms"
    "game_end:        $($gameEndProfile.Name); $($gameEndProfile.Description)"
    "adjudication:    none"
    "hash_mb:         $Hash"
    "threads:         $(if (-not ($supportsThreadsA -and $supportsThreadsB)) { 'option not advertised; not sent' } elseif ($ThreadsA -eq $ThreadsB) { $ThreadsA } else { "$NameA=$ThreadsA $NameB=$ThreadsB" })"
    "concurrency:     $Concurrency"
    "physical_cores:  $($concurrencyInfo.PhysicalCores)"
    "affinity_cpus:   $(if ($maxThreads -gt 1) { "(dropped: Threads>1, fastchess 1.8.0 1-core/game starves multi-thread; OS-scheduled)" } else { $AffinityCpus })"
    "book:            $Book"
    "book_sha256:     $(Get-HarnessSha256 $Book)"
    "opening_order:   random"
    "opening_seed:    $Seed"
    "optionsA:        $(if ($OptionsA) { $OptionsA -join ' ' } else { '(none)' })"
    "optionsB:        $(if ($OptionsB) { $OptionsB -join ' ' } else { '(none)' })"
    "completed_time_forfeits: $(if ($ScoreCompletedTimeForfeits) { 'scored after reconciliation' } else { 'fatal' })"
    "advertised_A:    $($optionsAdvertisedA -join ', ')"
    "advertised_B:    $($optionsAdvertisedB -join ', ')"
    "fastchess:       $($fcInfo.Text)"
    "fastchess_sha256: $(Get-HarnessSha256 $fastchess)"
    "started_utc:     $((Get-Date).ToUniversalTime().ToString('u'))"
) | Set-Content -Path $manifestPath -Encoding utf8

Write-Host ""
Write-Host "======================================================="
Write-Host "  SPRT ($Mode): $NameA  vs  $NameB"
if ($Mode -eq "calibrate") {
    Write-Host "  Fixed null calibration: $Games games; 95% nElo CI must fit inside +/-$CalibrationTolerance"
} elseif ($Mode -eq "fixed") {
    Write-Host "  Fixed-size match: $Games games; no SPRT stop rule"
} else {
    Write-Host "  H0: elo<=$Elo0   H1: elo>=$Elo1   alpha=$Alpha  beta=$Beta  (nElo)"
    Write-Host "  Budget: $MaxGames games; no H1 at the cap means park/revert"
}
Write-Host "  TC: $tcLabel   Margin: ${TimeMargin} ms   Hash: ${Hash} MB   Conc: $Concurrency"
Write-Host "  Game end: no adjudication; chess rules only (profile $($gameEndProfile.Name))"
Write-Host "  CPUs: $AffinityCpus"
Write-Host "  Book: $(Split-Path $Book -Leaf)"
Write-Host "  Runner: $($fcInfo.Text)"
Write-Host "  Manifest: $manifestPath"
Write-Host "  PGN:  $pgnOut"
Write-Host "  Log:  $logOut  (full output; console shows report blocks only)"
Write-Host "======================================================="
Write-Host ""

# Per-engine UCI options: "Name=Value" pairs become option.Name=Value so ONE
# binary can be A/B-tested on a knob without a rebuild.
$optArgsA = @($OptionsA | ForEach-Object { "option.$_" })
$optArgsB = @($OptionsB | ForEach-Object { "option.$_" })

$rounds = if ($Mode -eq "calibrate" -or $Mode -eq "fixed") {
    [int]($Games / 2)
} else {
    [int]($MaxGames / 2)
}
$sprtArgs = if ($Mode -eq "calibrate" -or $Mode -eq "fixed") {
    @()
} else {
    @('-sprt', "elo0=$Elo0", "elo1=$Elo1", "alpha=$Alpha", "beta=$Beta", 'model=normalized')
}

# Console-noise filter: the per-game 'Started game ...' / normal 'Finished game
# ... {Draw by threefold repetition}' / 'Score of ...' lines bury the periodic
# Elo/LLR report blocks. So: TEE the FULL stream to $logOut (nothing lost), and
# on the CONSOLE keep everything EXCEPT that per-game noise. Keep-by-default is
# deliberate — report blocks, errors, and any time-loss / disconnect / illegal
# 'Finished game' lines (the SPRT canaries) all still print.
$dropNoise = {
    param($l)
    $l = "$l"
    if ($l -match '^\s*Started game \d+ of') { return $true }
    if ($l -match '^\s*Score of .+ vs .+:\s*\d+ - \d+ - \d+') { return $true }
    if (($l -match '^\s*Finished game \d') -and
        ($l -notmatch '(?i)(on time|timeout|disconnect|illegal|crash|forfeit|stall)')) { return $true }
    return $false
}

& $fastchess `
    -engine "cmd=$EngineA" "name=$NameA" "option.Hash=$Hash" @threadArgsA @optArgsA `
    -engine "cmd=$EngineB" "name=$NameB" "option.Hash=$Hash" @threadArgsB @optArgsB `
    -each $tcArg "timemargin=$TimeMargin" `
    -openings "file=$Book" "format=$bookFormat" order=random `
    -rounds $rounds -games 2 -repeat `
    -concurrency $Concurrency `
    @affinityArgs `
    -srand $Seed `
    -ratinginterval 20 `
    @sprtArgs `
    @gameEndArgs `
    -pgnout "file=$pgnOut" `
    -output format=fastchess 2>&1 |
    Tee-Object -FilePath $logOut |
    Where-Object { -not (& $dropNoise $_) }
# $LASTEXITCODE reflects fastchess (Tee-Object/Where-Object are cmdlets and do
# not touch it), so the exit check below stays valid.

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Error "fastchess exited with code $LASTEXITCODE - no games were played."
} else {
    Assert-NoAffinityFailure -LogPath $logOut

    # A statistical verdict never overrides process safety. Clock-policy gates
    # may explicitly score completed time losses, but only after their summary
    # counts reconcile; every non-time fault remains fatal.
    Assert-StrengthMatchLog -LogPath $logOut `
        -ScoreCompletedTimeForfeits:$ScoreCompletedTimeForfeits

    Write-Host ""
    Write-Host "Match finished. PGN: $pgnOut"
    Write-Host "Full console log (all per-game lines): $logOut"

    if ($Mode -eq "gainer" -or $Mode -eq "simplify") {
        Write-Host "Only an H1 boundary in the log promotes the candidate; a game-budget stop is unresolved and must be parked/reverted."
    }

    if ($Mode -eq "calibrate") {
        $eloLine = Select-String -LiteralPath $logOut `
            -Pattern '\bnElo:\s*(?<estimate>[+-]?\d+(?:\.\d+)?)\s*\+/-\s*(?<error>\d+(?:\.\d+)?)' |
            Select-Object -Last 1
        if (-not $eloLine) { throw "Could not parse the final Elo confidence interval from '$logOut'." }

        $estimate = [double]$eloLine.Matches[0].Groups['estimate'].Value
        $error = [double]$eloLine.Matches[0].Groups['error'].Value
        $lower = $estimate - $error
        $upper = $estimate + $error
        $passes = $lower -ge -$CalibrationTolerance -and $upper -le $CalibrationTolerance
        Write-Host ""
        Write-Host ("Calibration 95% nElo CI: [{0:F2}, {1:F2}]; required inside [-{2:F2}, +{2:F2}]" -f $lower, $upper, $CalibrationTolerance)
        if ($passes) {
            Write-Host "CALIBRATION PASS" -ForegroundColor Green
        } else {
            throw "CALIBRATION INCONCLUSIVE/FAIL: the confidence interval does not establish the requested bias bound. Increase -Games only after resolving anomalies."
        }
    }
}
