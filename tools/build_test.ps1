<#
.SYNOPSIS
    Build a Manta test binary and copy it to the test-engines folder.

.DESCRIPTION
    Wraps the normal `zig build` install step and drops the result in
    tools\test_engines\ with a provenance sidecar JSON next to it. This is the Zig counterpart of Rarog's
    tools/build_test.ps1 and exists for one reason: sprt.ps1 hard-fails on a
    COMPILER MISMATCH between the two sides of a match, and it can only see the
    compiler through this sidecar.

    Two flavours:

      Native (default): `zig build -Dnative` — codegen tuned for this exact
      host CPU. Use for local A/B testing where both sides are built the same
      way; do NOT distribute.

      Portable (-Portable): `zig build -Dportable` — the supported platform
      baseline, i.e. what actually ships. Use when the gate must reflect the
      released artifact.

    -Pgo adds `-Dpgo` to either flavour. Keep PGO consistent across BOTH sides
    of a match: a PGO/non-PGO pair measures the profile, not the change.

    -ContextualSpace adds the narrow compile-time Step-5.4.3 MAN-E20
    context-weighted-space candidate. It changes no UCI surface and leaves
    ordinary builds default-off.

    -ShelterDangerCoupling adds the narrow compile-time Step-5.4.3 MAN-E21
    shelter-moderated king-danger candidate. It changes no UCI surface and
    leaves ordinary builds default-off.

    -CorrectionHistory adds the compile-time Step-5.4.1 MAN-S25 candidate. It
    changes no UCI surface and leaves ordinary builds default-off.

    -Tune exposes the Step-5.4.5 search-parameter UCI surface and, together
    with -IntegratedTime, the Step-6.3.3 clock-policy surface. Defaults remain
    production-equivalent; ordinary builds do not advertise these options.

    -RootConfidenceTime enables the default-off Step-6.0.2 completed-root
    confidence soft-time consumer. It changes no UCI surface.

    Integrated time management is the accepted production default.
    -IntegratedTime:$false reconstructs the pre-fit clock policy; -Tune
    additionally exposes its six sensitivity controls when integrated time is
    enabled. The off arm is required with the rejected MAN-R01 consumer.

    -StabilityAspiration enables the default-off Step-6.0.3 stability-gated
    aspiration candidate. It changes no UCI surface.

    The accepted Step-6.5.1b live-history staged picker is the production
    default. -LiveHistoryStaging:$false reconstructs the superseded MAN-S29
    eager picker for archived diagnostics. It changes no UCI surface.

    By default the build is smoke-tested before the manifest is written: the
    freshly built binary runs `bench` and must report a positive node count, so
    a broken build fails here rather than 3 hours into an SPRT. `-BuildOnly`
    records compiler/source/build/binary provenance without launching the
    engine; use it when execution belongs to the maintainer.

.PARAMETER Suffix
    Short label for the output file: manta-<Suffix>.exe

.PARAMETER Portable
    Build the supported platform baseline instead of a host-native binary.

.PARAMETER Pgo
    Add -Dpgo (the measured PGO pipeline, when available).

.PARAMETER ContextualSpace
    Build the MAN-E20 context-weighted-space candidate arm. The default is the
    exact MAN-E19 production arm.

.PARAMETER ShelterDangerCoupling
    Build the MAN-E21 shelter-moderated king-danger candidate arm. The default
    is the exact MAN-E19 production arm.

.PARAMETER CorrectionHistory
    Build the MAN-S25 correction-history candidate arm. The default is the
    production off arm.

.PARAMETER Tune
    Expose tune-only parameter registries for SPSA binaries. The Step-6.3.3
    clock registry also requires -IntegratedTime.

.PARAMETER RootConfidenceTime
    Build the Step-6.0.2 confidence-driven soft-time candidate arm.

.PARAMETER IntegratedTime
    Select integrated time management explicitly. It defaults on; pass
    -IntegratedTime:$false only for an archived pre-fit reconstruction.

.PARAMETER StabilityAspiration
    Build the Step-6.0.3 stability-gated aspiration candidate arm.

.PARAMETER LiveHistoryStaging
    Select the Step-6.5.1b live-history staged picker explicitly. It defaults
    on; pass -LiveHistoryStaging:$false only for an archived reconstruction.

.PARAMETER NonrootCheckExtension
    Keep production non-root check extension. Pass
    -NonrootCheckExtension:$false for the archived MAN-S31 candidate.

.PARAMETER MateWindows
    Build the Step-6.5.10.1 complete mate-window candidate arm. It defaults
    off; the production arm omits the switch.

.PARAMETER SingularExclusionHorizon
    Build the default-off Step-6.5.5 singular-exclusion-horizon candidate arm.
    It changes only the depth of the same-position exclusion probe.

.PARAMETER QsearchTacticalGeneration
    Keep the accepted Step-6.5.7 tactical-only non-check qsearch path. It
    defaults on; pass -QsearchTacticalGeneration:$false to reconstruct MAN-S30.

.PARAMETER BenchDepth
    Depth for the verification bench. Default 6 (the manta-search-bench-v1
    default). Lower it for a quicker smoke test; the node count is only a
    fingerprint, so any depth is fine as long as it is recorded.

.PARAMETER TestEnginesDir
    Destination directory. Default: tools\test_engines

.PARAMETER SourceRoot
    Repository worktree to build. Default: the repository containing this
    script. This permits a frozen baseline worktree and candidate worktree to
    use the same checked builder.

.PARAMETER BuildOnly
    Build and write a hash-bound provenance manifest without launching the
    engine. The manifest explicitly records that bench verification was not
    run.

.EXAMPLE
    ./tools/build_test.ps1 -Suffix head

.EXAMPLE
    ./tools/build_test.ps1 -Suffix nullmove -Portable -Pgo
#>
param(
    [Parameter(Mandatory)][string]$Suffix,
    [switch]$Portable,
    [switch]$Pgo,
    [switch]$ContextualSpace,
    [switch]$ShelterDangerCoupling,
    [switch]$CorrectionHistory,
    [switch]$Tune,
    [switch]$RootConfidenceTime,
    [switch]$IntegratedTime,
    [switch]$StabilityAspiration,
    [switch]$LiveHistoryStaging,
    [switch]$NonrootCheckExtension,
    [switch]$MateWindows,
    [switch]$SingularExclusionHorizon,
    [switch]$QsearchTacticalGeneration,
    [switch]$BuildOnly,
    [int]$BenchDepth = 6,
    [string]$TestEnginesDir = "$PSScriptRoot\test_engines",
    [string]$SourceRoot = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "harness_common.ps1")

$integratedTimeEnabled = if ($PSBoundParameters.ContainsKey("IntegratedTime")) {
    [bool]$IntegratedTime
} else {
    $true
}
$liveHistoryStagingEnabled = if ($PSBoundParameters.ContainsKey("LiveHistoryStaging")) {
    [bool]$LiveHistoryStaging
} else {
    $true
}
$qsearchTacticalGenerationEnabled = if ($PSBoundParameters.ContainsKey("QsearchTacticalGeneration")) {
    [bool]$QsearchTacticalGeneration
} else {
    $true
}

if ($BenchDepth -lt 1) { throw "-BenchDepth must be positive." }

$nonrootCheckExtensionEnabled = if ($PSBoundParameters.ContainsKey("NonrootCheckExtension")) {
    [bool]$NonrootCheckExtension
} else {
    $true
}

# Manta's bench holds the job until it completes, and both `quit` and EOF
# cancel it (docs/UCI.md §4.2). Piping "bench`nquit" therefore returns nothing.
# Feed `bench` and keep stdin OPEN until the total line arrives.
# Invoke-MantaBench now lives in harness_common.ps1, which this script already
# dot-sources above, so search_profile.ps1 drives the bench the same way.

# Every test binary gets a sidecar JSON next to it: git SHA + dirty flag,
# branch, zig version, and a bench fingerprint VERIFIED by running the binary
# just built. sprt.ps1 copies both engines' manifests into the result dir, so
# every result is permanently self-describing.
#
# LOCAL-ONLY BY DESIGN: manifests exist for development provenance.
# tools/test_engines/ and tools/results/ are gitignored, and no release
# workflow reads them.
function Write-EngineManifest {
    param(
        [Parameter(Mandatory)][string]$BinaryPath,
        [Parameter(Mandatory)][string]$Suffix,
        [Parameter(Mandatory)][string]$Flavor,
        [Parameter(Mandatory)][int]$Depth,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$BuildCommand,
        [Parameter(Mandatory)][bool]$ContextualSpace,
        [Parameter(Mandatory)][bool]$ShelterDangerCoupling,
        [Parameter(Mandatory)][bool]$CorrectionHistory,
        [Parameter(Mandatory)][bool]$Tune,
        [Parameter(Mandatory)][bool]$RootConfidenceTime,
        [Parameter(Mandatory)][bool]$IntegratedTime,
        [Parameter(Mandatory)][bool]$StabilityAspiration,
        [Parameter(Mandatory)][bool]$LiveHistoryStaging,
        [Parameter(Mandatory)][bool]$NonrootCheckExtension,
        [Parameter(Mandatory)][bool]$MateWindows,
        [Parameter(Mandatory)][bool]$SingularExclusionHorizon,
        [Parameter(Mandatory)][bool]$QsearchTacticalGeneration,
        [switch]$SkipBench
    )

    $sha    = (& git -C $RepositoryRoot rev-parse HEAD).Trim()
    $branch = (& git -C $RepositoryRoot rev-parse --abbrev-ref HEAD).Trim()
    $tree   = (& git -C $RepositoryRoot rev-parse 'HEAD^{tree}').Trim()
    $dirty  = [bool](& git -C $RepositoryRoot status --porcelain)
    $zig    = (zig version).Trim()
    $binary = Get-Item -LiteralPath $BinaryPath
    $binaryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $BinaryPath).Hash

    $benchLine = $null
    $nodes = $null
    if (-not $SkipBench) {
        Write-Host "Verifying bench fingerprint of $([IO.Path]::GetFileName($BinaryPath)) (depth $Depth) ..."
        $benchLine = Invoke-MantaBench -BinaryPath $BinaryPath -Depth $Depth
        if ($benchLine -notmatch 'Nodes searched\s*:\s*(?<nodes>\d+)') {
            throw "Could not parse a bench node count from '$benchLine' - refusing to write a manifest for an unverified engine."
        }
        $nodes = [int64]$Matches['nodes']
        if ($nodes -le 0) { throw "Bench reported $nodes nodes - broken binary." }
    }

    $manifest = [ordered]@{
        schema_version     = 9
        engine             = $binary.Name
        binary_sha256      = $binaryHash
        binary_size_bytes  = $binary.Length
        suffix             = $Suffix
        flavor             = $Flavor
        build_command       = $BuildCommand
        contextual_space   = $ContextualSpace
        shelter_danger_coupling = $ShelterDangerCoupling
        correction_history = $CorrectionHistory
        tune                = $Tune
        root_confidence_time = $RootConfidenceTime
        integrated_time     = $IntegratedTime
        stability_aspiration = $StabilityAspiration
        live_history_staging = $LiveHistoryStaging
        nonroot_check_extension = $NonrootCheckExtension
        mate_windows = $MateWindows
        singular_exclusion_horizon = $SingularExclusionHorizon
        qsearch_tactical_generation = $QsearchTacticalGeneration
        search_spsa_bake    = $false
        git_sha            = $sha
        git_tree           = $tree
        git_branch         = $branch
        git_dirty          = $dirty
        zig                = $zig
        verification       = if ($SkipBench) { "build-only" } else { "bench" }
        bench_depth        = if ($SkipBench) { $null } else { $Depth }
        bench_nodes        = $nodes
        bench_line         = if ($benchLine) { $benchLine.Trim() } else { $null }
        built_utc          = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    $manifestPath = [IO.Path]::ChangeExtension($BinaryPath, ".json")
    $manifest | ConvertTo-Json | Out-File -FilePath $manifestPath -Encoding utf8
    $verification = if ($SkipBench) { "build-only; engine not launched" } else { "bench $nodes" }
    Write-Host "Manifest: $manifestPath  ($verification$(if ($dirty) { ', DIRTY WORKING TREE' }))"
    if ($dirty) {
        Write-Host "WARNING: built from a DIRTY working tree - this binary is not reproducible from git_sha alone." -ForegroundColor Yellow
    }
}

$repoRoot = if ($SourceRoot) {
    (Resolve-Path -LiteralPath $SourceRoot).Path
} else {
    Split-Path -Parent $PSScriptRoot
}
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "build.zig") -PathType Leaf)) {
    throw "-SourceRoot is not a Manta worktree: $repoRoot"
}
Push-Location $repoRoot
try {
    $buildArgs = @("build")
    $buildArgs += if ($Portable) { "-Dportable" } else { "-Dnative" }
    if ($Pgo) { $buildArgs += "-Dpgo" }
    if ($ContextualSpace) { $buildArgs += "-Dcontextual-space=true" }
    if ($ShelterDangerCoupling) { $buildArgs += "-Dshelter-danger-coupling=true" }
    if ($CorrectionHistory) { $buildArgs += "-Dcorrection-history=true" }
    if ($Tune) { $buildArgs += "-Dtune=true" }
    if ($RootConfidenceTime) { $buildArgs += "-Droot-confidence-time=true" }
    $integratedTimeText = $integratedTimeEnabled.ToString().ToLowerInvariant()
    $buildArgs += "-Dintegrated-time=$integratedTimeText"
    if ($StabilityAspiration) { $buildArgs += "-Dstability-aspiration=true" }
    $liveHistoryStagingText = $liveHistoryStagingEnabled.ToString().ToLowerInvariant()
    $buildArgs += "-Dlive-history-staging=$liveHistoryStagingText"
    $nonrootCheckExtensionText = $nonrootCheckExtensionEnabled.ToString().ToLowerInvariant()
    $buildArgs += "-Dnonroot-check-extension=$nonrootCheckExtensionText"
    if ($MateWindows) { $buildArgs += "-Dmate-windows=true" }
    if ($SingularExclusionHorizon) { $buildArgs += "-Dsingular-exclusion-horizon=true" }
    $qsearchTacticalGenerationText = $qsearchTacticalGenerationEnabled.ToString().ToLowerInvariant()
    $buildArgs += "-Dqsearch-tactical-generation=$qsearchTacticalGenerationText"
    $flavor = "$(if ($Portable) { 'portable' } else { 'native' })$(if ($Pgo) { '-pgo' } else { '' })$(if ($Tune) { '-tune' } else { '' })$(if ($RootConfidenceTime) { '-root-confidence-time' } else { '' })$(if ($integratedTimeEnabled) { '-integrated-time' } else { '-untuned-time' })$(if ($StabilityAspiration) { '-stability-aspiration' } else { '' })$(if ($liveHistoryStagingEnabled) { '-live-history-staging' } else { '-eager-picker' })$(if ($nonrootCheckExtensionEnabled) { '' } else { '-no-check-extension' })$(if ($MateWindows) { '-mate-windows' } else { '' })$(if ($SingularExclusionHorizon) { '-singular-exclusion-horizon' } else { '' })$(if ($qsearchTacticalGenerationEnabled) { '-qsearch-tacticals' } else { '-full-qsearch-generation' })"

    Write-Host ""
    Write-Host "Building Manta ($flavor) - suffix: $Suffix"
    Write-Host "  zig $($buildArgs -join ' ')"
    Write-Host ""

    & zig @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "zig build failed (exit $LASTEXITCODE)" }

    # The normal install step guarantees this path. The narrower custom `dist`
    # step installs only zig-out/dist, so selecting bin after it could reuse a
    # stale artifact from an earlier build.
    $builtBinary = Join-Path $repoRoot "zig-out\bin\manta.exe"
    if (-not (Test-Path -LiteralPath $builtBinary -PathType Leaf)) {
        throw "No zig-out/bin/manta.exe found - check the zig build output above."
    }

    if (-not (Test-Path $TestEnginesDir)) {
        New-Item -ItemType Directory -Path $TestEnginesDir | Out-Null
    }

    $dest = Join-Path $TestEnginesDir "manta-$Suffix.exe"
    Copy-Item -LiteralPath $builtBinary -Destination $dest -Force
    $buildCommand = "zig $($buildArgs -join ' ')"
    Write-EngineManifest -BinaryPath $dest -Suffix $Suffix -Flavor $flavor -Depth $BenchDepth `
        -RepositoryRoot $repoRoot -BuildCommand $buildCommand `
        -ContextualSpace ([bool]$ContextualSpace) `
        -ShelterDangerCoupling ([bool]$ShelterDangerCoupling) `
        -CorrectionHistory ([bool]$CorrectionHistory) -Tune ([bool]$Tune) `
        -RootConfidenceTime ([bool]$RootConfidenceTime) `
        -IntegratedTime $integratedTimeEnabled `
        -StabilityAspiration ([bool]$StabilityAspiration) `
        -LiveHistoryStaging $liveHistoryStagingEnabled `
        -NonrootCheckExtension $nonrootCheckExtensionEnabled `
        -MateWindows ([bool]$MateWindows) `
        -SingularExclusionHorizon ([bool]$SingularExclusionHorizon) `
        -QsearchTacticalGeneration $qsearchTacticalGenerationEnabled -SkipBench:$BuildOnly
    Write-Host ""
    Write-Host "Done: $dest"
    Write-Host ""
} finally {
    Pop-Location
}
