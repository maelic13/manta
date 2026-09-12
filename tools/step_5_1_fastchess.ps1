<#
.SYNOPSIS
    Temporary Rarog-fastchess bridge for Manta one-thread playing gates.

.DESCRIPTION
    Runs an explicitly identified one-thread candidate and accepted baseline
    with the checked Manta-local bridge inputs inherited from Rarog's pinned
    fastchess, opening book and experiment policy while Colosseum lacks shared
    per-game CPU placement. Manta owns only this narrow orchestration bridge.

    The bridge is intentionally restricted to the qualified 1T 3+0.03 gate on
    the designated 16-core Ryzen 9 5950X. It verifies every borrowed input by
    SHA-256 before invoking it and leaves two physical cores free, producing
    14 concurrent games pinned one game per physical core.

    No job is launched with -DryRun. Long jobs remain maintainer-owned.
#>
[CmdletBinding()]
param(
    [ValidateSet("pilot", "calibrate", "sprt")]
    [string]$Job = "sprt",

    [string]$ToolRoot = $PSScriptRoot,
    [Parameter(Mandatory)]
    [string]$Candidate,
    [Parameter(Mandatory)]
    [string]$Baseline,
    [Parameter(Mandatory)]
    [string]$CandidateName,
    [Parameter(Mandatory)]
    [string]$BaselineName,
    [Parameter(Mandatory)]
    [string]$RunId,

    [int]$PilotGames = 100,
    [int]$CalibrationGames = 30000,
    [int]$MaxGames = 12000,
    [int]$PilotSeed = 512060,
    [int]$CalibrationSeed = 510040,
    [int]$SprtSeed = 0,
    [int]$SprtElo0 = 3,
    [int]$SprtElo1 = 10,
    [switch]$DiagnosticNoAffinity,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$expected = [ordered]@{
    common     = "12BA1D05CBFC0A7E0AFAA56599528A18DCE863CAE3359E3687D09C8B5BCAD930"
    fastchess  = "8444E73965AE44E716CDE1BB546A7D7C8C9FC7A442A44194A0C71A3BFFA7DD0D"
    book       = "7A7F6470615A69C6CF23D565417701D38732876F480AF90D67B42ABADE35644A"
}

function Resolve-ExistingFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label not found: $Path"
    }
    (Resolve-Path -LiteralPath $Path).Path
}

function Assert-ExpectedHash {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedHash,
        [Parameter(Mandatory)][string]$Label
    )

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedHash) {
        throw "$Label SHA-256 changed. Expected $ExpectedHash, found $actual at $Path. Review and update the bridge before running games."
    }
    $actual
}

if ($PilotGames -lt 2 -or ($PilotGames % 2) -ne 0) {
    throw "PilotGames must be a positive even number."
}
if ($CalibrationGames -lt 2 -or ($CalibrationGames % 2) -ne 0) {
    throw "CalibrationGames must be a positive even number."
}
if ($MaxGames -lt 2 -or ($MaxGames % 2) -ne 0) {
    throw "MaxGames must be a positive even number."
}
if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "RunId must contain only letters, digits, dot, underscore and hyphen."
}
if ($Job -eq "sprt" -and $SprtSeed -le 0) {
    throw "SprtSeed must be prospectively registered and supplied for a playing gate."
}
if ($PSBoundParameters.ContainsKey("SprtElo0") -xor $PSBoundParameters.ContainsKey("SprtElo1")) {
    throw "Supply SprtElo0 and SprtElo1 together so a registered gate cannot inherit half of the default bounds."
}
if ($SprtElo0 -lt 0 -or $SprtElo1 -le $SprtElo0) {
    throw "SPRT bounds must satisfy 0 <= SprtElo0 < SprtElo1."
}
if ($DiagnosticNoAffinity -and $Job -ne "pilot") {
    throw "DiagnosticNoAffinity is restricted to the non-authoritative pilot."
}

$toolsRoot = (Resolve-Path -LiteralPath $ToolRoot).Path
$commonScript = Resolve-ExistingFile (Join-Path $toolsRoot "harness_common.ps1") "checked harness helpers"
$fastchess = Resolve-ExistingFile (Join-Path $toolsRoot "bin\fastchess.exe") "fastchess"
$book = Resolve-ExistingFile (Join-Path $toolsRoot "books\UHO_Lichess_4852_v1.epd") "UHO book"
$candidatePath = Resolve-ExistingFile $Candidate "candidate"
$baselinePath = Resolve-ExistingFile $Baseline "accepted baseline"

$resolvedHashes = [ordered]@{
    common = Assert-ExpectedHash $commonScript $expected.common "checked harness helpers"
    fastchess = Assert-ExpectedHash $fastchess $expected.fastchess "fastchess"
    book = Assert-ExpectedHash $book $expected.book "UHO book"
    candidate = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
    baseline = (Get-FileHash -LiteralPath $baselinePath -Algorithm SHA256).Hash
}

if ($resolvedHashes.candidate -eq $resolvedHashes.baseline) {
    throw "Candidate and baseline are byte-identical; the playing gate would not test $RunId."
}

# Use the exact checked local topology helpers before dispatch so the launcher
# itself demonstrates the intended 14-core layout without starting a game.
. $commonScript
$gameEndProfile = Get-GameEndProfile
$gameEndArgs = @(Get-GameEndArgs)
$placement = Resolve-HarnessConcurrency -Requested 14 -ThreadsPerGame 1
$affinityCpus = Get-HarnessAffinityCpuList -Concurrency $placement.Concurrency -ThreadsPerGame 1
$affinityArgs = if ($DiagnosticNoAffinity) { @() } else { @("-use-affinity", $affinityCpus) }
$fastchessInfo = Assert-AffinityFastchess -Path $fastchess
$processorNames = @(
    Get-CimInstance Win32_Processor | ForEach-Object { $_.Name.Trim() }
)
$requiredProcessor = "AMD Ryzen 9 5950X 16-Core Processor"
if ($processorNames.Count -ne 1 -or $processorNames[0] -ne $requiredProcessor) {
    throw "The authoritative Step-5.1 bridge requires '$requiredProcessor'; detected '$($processorNames -join "; ")'."
}
if ($placement.PhysicalCores -ne 16 -or $placement.CoresUsed -ne 14) {
    throw "This checked bridge requires the designated 16-physical-core host and 14 game cores; detected $($placement.PhysicalCores) physical cores and $($placement.CoresUsed) requested cores."
}

$engineA = $candidatePath
$engineB = $baselinePath
$nameA = $CandidateName
$nameB = $BaselineName
$games = $PilotGames
$max = $PilotGames
$seed = $PilotSeed

switch ($Job) {
    "calibrate" {
        $engineA = $baselinePath
        $engineB = $baselinePath
        $nameA = "Manta-null-A"
        $nameB = "Manta-null-B"
        $games = $CalibrationGames
        $max = $MaxGames
        $seed = $CalibrationSeed
    }
    "sprt" {
        $games = $PilotGames
        $max = $MaxGames
        $seed = $SprtSeed
    }
}

$repoRevision = (& git -C (Join-Path $PSScriptRoot "..") rev-parse HEAD 2>$null).Trim()
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path (Join-Path $PSScriptRoot "..\zig-out\fastchess") "$RunId-$Job-$timestamp")
)
$summary = [ordered]@{
    job = $Job
    execution_owner = "maintainer"
    manta_revision = $repoRevision
    bridge_revision = $repoRevision
    runner = $fastchessInfo.Text
    engines = [ordered]@{
        a = [ordered]@{ name = $nameA; path = $engineA; sha256 = (Get-FileHash $engineA -Algorithm SHA256).Hash }
        b = [ordered]@{ name = $nameB; path = $engineB; sha256 = (Get-FileHash $engineB -Algorithm SHA256).Hash }
    }
    test = [ordered]@{
        model = if ($Job -eq "calibrate") {
            "fixed-N normalized-Elo equivalence"
        } elseif ($Job -eq "pilot") {
            "bounded workflow pilot using the [$SprtElo0,$SprtElo1] stop rule; no strength verdict"
        } else {
            "normalized-Elo SPRT [$SprtElo0,$SprtElo1]"
        }
        game_budget = if ($Job -eq "calibrate") { $CalibrationGames } else { $max }
        tc = "3+0.03"
        margin_ms = 20
        hash_mb_per_engine = 64
        threads_per_engine = 1
        uci_options_sent = @("Hash=64")
        threads_option_sent = $false
        concurrency = 14
        processor = $processorNames[0]
        physical_cores = $placement.PhysicalCores
        affinity_cpus = if ($DiagnosticNoAffinity) { "disabled for diagnostic isolation" } else { $affinityCpus }
        authoritative_placement = (-not $DiagnosticNoAffinity)
        ponder = $false
        adjudication = "none"
        game_end = "$($gameEndProfile.Name): $($gameEndProfile.Description)"
        sprt = if ($Job -eq "calibrate") { $null } else { [ordered]@{
            elo0 = $SprtElo0
            elo1 = $SprtElo1
            alpha = 0.05
            beta = 0.05
            model = "normalized"
        } }
        pilot_engine_communication_trace = ($Job -eq "pilot")
        seed = $seed
        expected_wall_time = switch ($Job) {
            "pilot" { "about 1 minute; stop at 5 minutes" }
            "calibrate" { "about 5.2 hours; stop at 6.5 hours" }
            "sprt" { "at most about 2.9 hours; stop at 3.5 hours" }
        }
    }
    dependencies = [ordered]@{
        harness_common = [ordered]@{ path = $commonScript; sha256 = $resolvedHashes.common }
        fastchess = [ordered]@{ path = $fastchess; sha256 = $resolvedHashes.fastchess }
        book = [ordered]@{ path = $book; sha256 = $resolvedHashes.book }
    }
    artifacts = $runDirectory
    limitations = @(
        "Temporary bridge; Colosseum remains the strategic runner.",
        "fastchess has no pair-atomic checkpoint/resume contract in this launcher.",
        $(if ($Job -eq "pilot") { "Pilot is a bounded workflow/fault check, not a strength verdict." } else { "This is the registered final SPRT; no candidate-specific pilot is required." }),
        $(if ($DiagnosticNoAffinity) { "DiagnosticNoAffinity disables required placement; its output cannot support calibration or strength claims." } else { "Required one-core-per-game affinity is enabled." })
    )
}

Write-Host ($summary | ConvertTo-Json -Depth 8)
Write-Host ""
Write-Host "Manta artifacts will be written under: $($summary.artifacts)"

if ($DryRun) {
    Write-Host "DRY RUN: no engine process or game was started." -ForegroundColor Yellow
    exit 0
}

New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
$manifestPath = Join-Path $runDirectory "bridge-manifest.json"
$consoleLog = Join-Path $runDirectory "fastchess.log"
$engineLog = Join-Path $runDirectory "engine-comms.log"
$pgnPath = Join-Path $runDirectory "games.pgn"
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8

$rounds = if ($Job -eq "calibrate") {
    [int]($CalibrationGames / 2)
} else {
    [int]($max / 2)
}
$sprtArguments = if ($Job -eq "calibrate") {
    @()
} else {
    @(
        "-sprt", "elo0=$SprtElo0", "elo1=$SprtElo1",
        "alpha=0.05", "beta=0.05", "model=normalized"
    )
}
$engineLogLevel = if ($Job -eq "pilot") { "trace" } else { "warn" }
$engineCommunication = if ($Job -eq "pilot") { "true" } else { "false" }
$fastchessArguments = @(
    "-engine", "cmd=$engineA", "name=$nameA", "option.Hash=64",
    "-engine", "cmd=$engineB", "name=$nameB", "option.Hash=64",
    "-each", "tc=3+0.03", "timemargin=20",
    "-openings", "file=$book", "format=epd", "order=random",
    "-rounds", "$rounds", "-games", "2", "-repeat",
    "-concurrency", "14"
) + $affinityArgs + @(
    "-srand", "$seed",
    "-ratinginterval", "20"
) + $sprtArguments + $gameEndArgs + @(
    "-pgnout", "file=$pgnPath", "append=false",
    "-log", "file=$engineLog", "level=$engineLogLevel", "engine=$engineCommunication", "append=false", "realtime=true",
    "-output", "format=fastchess"
)

$dropNoise = {
    param($line)
    $text = "$line"
    if ($text -match '^\s*Started game \d+ of') { return $true }
    if ($text -match '^\s*Score of .+ vs .+:\s*\d+ - \d+ - \d+') { return $true }
    if (($text -match '^\s*Finished game \d') -and
        ($text -notmatch '(?i)(on time|timeout|disconnect|illegal|crash|forfeit|stall)')) {
        return $true
    }
    return $false
}

Write-Host "Starting maintainer-owned $Job job through pinned fastchess." -ForegroundColor Yellow
Write-Host "This Manta gate is fixed at one search thread, so no unsupported Threads option is sent."
Write-Host "Manifest: $manifestPath"
Write-Host "PGN: $pgnPath"
Write-Host "Console log: $consoleLog"
Write-Host "Engine communications: $engineLog"

Push-Location $runDirectory
try {
    & $fastchess @fastchessArguments 2>&1 |
        Tee-Object -FilePath $consoleLog |
        Where-Object { -not (& $dropNoise $_) }
    $fastchessExit = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($fastchessExit -ne 0) {
    throw "fastchess exited with code $fastchessExit. The run is invalid; inspect $consoleLog and $engineLog."
}

$anomaly = Select-String -LiteralPath $consoleLog `
    -Pattern '(?i)(stalled\s*/\s*disconnected|loses on time|timeout|crashed|illegal move|forfeit|failed to set cpu affinity|no cores available)' `
    -ErrorAction SilentlyContinue
if ($anomaly) {
    throw "The run contains an engine, clock, protocol or affinity anomaly and is invalid. Inspect $consoleLog and $engineLog."
}

if ($Job -eq "calibrate") {
    $eloLine = Select-String -LiteralPath $consoleLog `
        -Pattern '\bnElo:\s*(?<estimate>[+-]?\d+(?:\.\d+)?)\s*\+/-\s*(?<error>\d+(?:\.\d+)?)' |
        Select-Object -Last 1
    if (-not $eloLine) {
        throw "Could not parse the final calibration interval from $consoleLog."
    }
    $estimate = [double]$eloLine.Matches[0].Groups['estimate'].Value
    $error = [double]$eloLine.Matches[0].Groups['error'].Value
    $lower = $estimate - $error
    $upper = $estimate + $error
    if ($lower -lt -5 -or $upper -gt 5) {
        throw ("Calibration did not establish the registered +/-5 nElo bound: [{0:F2}, {1:F2}]." -f $lower, $upper)
    }
    Write-Host ("Calibration passed: 95% nElo CI [{0:F2}, {1:F2}]." -f $lower, $upper) -ForegroundColor Green
}

Write-Host "Job completed without a recorded infrastructure anomaly. Artifacts: $runDirectory" -ForegroundColor Green
