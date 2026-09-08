#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Cross-engine nodes-to-depth, elapsed-time and branching-factor profile.

.DESCRIPTION
    Drives one UCI engine over a fixed FEN corpus with a fresh process per
    depth and a fresh game per position. The JSON report binds executable and
    corpus hashes, records monotonic per-position wall time, and reports full
    and ordinary-position aggregates. Position, depth and whole-run deadlines
    are enforced independently; an incomplete search is never reported as fast.

.PARAMETER OrdinaryExcludedPositions
    Zero-based position indices excluded only from the ordinary subset. The
    full aggregate always retains every selected position.

.EXAMPLE
    pwsh -NoProfile -File .\tools\branching_profile.ps1 -Engine .\zig-out\bin\manta.exe -MinDepth 4 -MaxDepth 13 -Hash 64 -OutFile .\zig-out\manta-d4-13.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Engine,
    [string]$Positions = "",
    [ValidateRange(1, 256)][int]$MinDepth = 4,
    [ValidateRange(1, 256)][int]$MaxDepth = 9,
    [ValidateRange(1, 1048576)][int]$Hash = 16,
    [ValidateRange(1, 1024)][int]$Threads = 1,
    [ValidateRange(0, 1000000)][int]$PositionLimit = 0,
    [int[]]$OrdinaryExcludedPositions = @(6, 30),
    [string]$OutFile = "",
    [Alias("TimeoutMs")][ValidateRange(1, 2147483647)][int]$PositionTimeoutMs = 60000,
    [ValidateRange(1, 2147483647)][int]$DepthTimeoutMs = 300000,
    [ValidateRange(1, 2147483647)][int]$RunTimeoutMs = 900000,
    [string]$SourceRevision = "",
    [string]$BuildManifest = ""
)

$ErrorActionPreference = "Stop"
if ($MinDepth -gt $MaxDepth) { throw "MinDepth must not exceed MaxDepth" }
$root = Split-Path -Parent $PSScriptRoot
if (-not $Positions) { $Positions = Join-Path $root "tools\bench_positions.epd" }
foreach ($required in @($Engine, $Positions)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "missing: $required" }
}
if ($BuildManifest -and -not (Test-Path -LiteralPath $BuildManifest -PathType Leaf)) {
    throw "missing build manifest: $BuildManifest"
}

$allFens = @(Get-Content -LiteralPath $Positions | Where-Object { $_.Trim() })
$fens = $allFens
if ($PositionLimit -gt 0 -and $fens.Count -gt $PositionLimit) {
    $fens = $fens[0..($PositionLimit - 1)]
}
if ($fens.Count -eq 0) { throw "position corpus is empty" }
foreach ($index in $OrdinaryExcludedPositions) {
    if ($index -lt 0) { throw "ordinary excluded position indices must be non-negative" }
}

$enginePath = (Resolve-Path -LiteralPath $Engine).Path
$positionsPath = (Resolve-Path -LiteralPath $Positions).Path
$manifestPath = if ($BuildManifest) { (Resolve-Path -LiteralPath $BuildManifest).Path } else { $null }
$engineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $enginePath).Hash
$positionsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $positionsPath).Hash
$manifestHash = if ($manifestPath) { (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash } else { $null }
$script:proc = $null
$rows = @()
$positionRows = @()
$engineName = $null
$runWatch = [System.Diagnostics.Stopwatch]::StartNew()

function Start-Engine {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $enginePath
    $psi.WorkingDirectory = Split-Path -Parent $enginePath
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $script:proc = [System.Diagnostics.Process]::Start($psi)
}

function Stop-Engine {
    if ($null -eq $script:proc) { return }
    if (-not $script:proc.HasExited) {
        try { $script:proc.StandardInput.WriteLine("quit") } catch {}
        [void]$script:proc.WaitForExit(5000)
    }
    if (-not $script:proc.HasExited) { $script:proc.Kill($true) }
    $script:proc.Dispose()
    $script:proc = $null
}

function Send([string]$text) {
    $script:proc.StandardInput.WriteLine($text)
    $script:proc.StandardInput.Flush()
}

function Remaining-Milliseconds(
    [System.Diagnostics.Stopwatch]$watch,
    [int]$limit,
    [string]$scope
) {
    $remaining = [int64]$limit - $watch.ElapsedMilliseconds
    if ($remaining -le 0) { throw "$scope timeout after $limit ms" }
    return [int][math]::Min($remaining, [int]::MaxValue)
}

function Bounded-Wait([string]$pattern, [int]$maximumMs, [string]$scope) {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $seen = [System.Collections.Generic.List[string]]::new()
    while ($true) {
        $remaining = [int64]$maximumMs - $watch.ElapsedMilliseconds
        if ($remaining -le 0) { throw "$scope timeout waiting for /$pattern/ after $maximumMs ms" }
        $readTask = $script:proc.StandardOutput.ReadLineAsync()
        if (-not $readTask.Wait([int][math]::Min($remaining, [int]::MaxValue))) {
            throw "$scope timeout waiting for /$pattern/ after $maximumMs ms"
        }
        $line = $readTask.Result
        if ($null -eq $line) {
            $stderr = $script:proc.StandardError.ReadToEnd()
            throw "engine closed stdout early in $scope; stderr: $stderr"
        }
        $seen.Add($line)
        if ($line -match $pattern) { return $seen }
    }
}

function Minimum-Timeout([int[]]$values) {
    return ($values | Measure-Object -Minimum).Minimum
}

function Report-Object([string]$status, [string]$failure) {
    return [pscustomobject]@{
        schema = "manta-branching-profile-v2"
        status = $status
        failure = if ($failure) { $failure } else { $null }
        engine = [pscustomobject]@{
            path = $enginePath
            sha256 = $engineHash
            reported_name = $engineName
            source_revision = if ($SourceRevision) { $SourceRevision } else { $null }
            build_manifest = $manifestPath
            build_manifest_sha256 = $manifestHash
        }
        corpus = [pscustomobject]@{
            path = $positionsPath
            sha256 = $positionsHash
            available_positions = $allFens.Count
            selected_positions = $fens.Count
            ordinary_excluded_zero_based = @($OrdinaryExcludedPositions)
        }
        hash_mb = $Hash
        threads = $Threads
        min_depth = $MinDepth
        max_depth = $MaxDepth
        timeouts_ms = [pscustomobject]@{
            position = $PositionTimeoutMs
            depth = $DepthTimeoutMs
            run = $RunTimeoutMs
        }
        reset_policy = "fresh process per depth; ucinewgame plus isready per position"
        timing_scope = "per-position monotonic wall time from ucinewgame send through bestmove receipt"
        run_wall_ms = $runWatch.ElapsedMilliseconds
        rows = @($rows)
        position_rows = @($positionRows)
    }
}

function Write-Report([string]$status, [string]$failure) {
    if (-not $OutFile) { return }
    $reportPath = [System.IO.Path]::GetFullPath($OutFile)
    $parent = Split-Path -Parent $reportPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Path $parent)
    }
    Report-Object $status $failure |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $reportPath -Encoding utf8
    Write-Host "report -> $reportPath"
}

try {
    Write-Host "Engine:    $enginePath"
    Write-Host "SHA-256:   $engineHash"
    Write-Host "Positions: $($fens.Count) from $(Split-Path -Leaf $positionsPath) ($positionsHash)"
    Write-Host "Hash:      $Hash MiB   Threads: $Threads"
    Write-Host "Timeouts:  position=$PositionTimeoutMs depth=$DepthTimeoutMs run=$RunTimeoutMs ms`n"
    $header = "{0,5} {1,16} {2,10} {3,14} {4,14}" -f "depth", "nodes", "ratio", "full_time_ms", "ordinary_ms"
    Write-Host $header
    Write-Host ("-" * $header.Length)

    $previous = 0
    foreach ($depth in $MinDepth..$MaxDepth) {
        [void](Remaining-Milliseconds $runWatch $RunTimeoutMs "whole run")
        $depthWatch = [System.Diagnostics.Stopwatch]::StartNew()
        Start-Engine
        Send "uci"
        $uciLines = Bounded-Wait '^uciok' (Minimum-Timeout @(
            (Remaining-Milliseconds $depthWatch $DepthTimeoutMs "depth $depth"),
            (Remaining-Milliseconds $runWatch $RunTimeoutMs "whole run"),
            30000
        )) "depth $depth UCI handshake"
        if (-not $engineName) {
            $nameLine = $uciLines | Where-Object { $_ -match '^id name\s+(.+)$' } | Select-Object -Last 1
            if ($nameLine -and $nameLine -match '^id name\s+(.+)$') { $engineName = $Matches[1] }
        }
        Send "setoption name Hash value $Hash"
        Send "setoption name Threads value $Threads"
        Send "isready"
        [void](Bounded-Wait '^readyok' (Minimum-Timeout @(
            (Remaining-Milliseconds $depthWatch $DepthTimeoutMs "depth $depth"),
            (Remaining-Milliseconds $runWatch $RunTimeoutMs "whole run"),
            30000
        )) "depth $depth setup")

        $totalNodes = [int64]0
        $ordinaryNodes = [int64]0
        $fullTime = [int64]0
        $ordinaryTime = [int64]0
        for ($positionIndex = 0; $positionIndex -lt $fens.Count; $positionIndex++) {
            $fen = $fens[$positionIndex]
            $positionWatch = [System.Diagnostics.Stopwatch]::StartNew()
            Send "ucinewgame"
            Send "isready"
            [void](Bounded-Wait '^readyok' (Minimum-Timeout @(
                (Remaining-Milliseconds $positionWatch $PositionTimeoutMs "depth $depth position $positionIndex"),
                (Remaining-Milliseconds $depthWatch $DepthTimeoutMs "depth $depth"),
                (Remaining-Milliseconds $runWatch $RunTimeoutMs "whole run")
            )) "depth $depth position $positionIndex reset")
            Send "position fen $fen"
            Send "go depth $depth"
            $lines = Bounded-Wait '^bestmove' (Minimum-Timeout @(
                (Remaining-Milliseconds $positionWatch $PositionTimeoutMs "depth $depth position $positionIndex"),
                (Remaining-Milliseconds $depthWatch $DepthTimeoutMs "depth $depth"),
                (Remaining-Milliseconds $runWatch $RunTimeoutMs "whole run")
            )) "depth $depth position $positionIndex search"
            $positionWatch.Stop()

            $nodes = [int64]0
            $uciTime = [int64]0
            foreach ($line in $lines) {
                if ($line -match '^info .*\bnodes\s+(\d+)') { $nodes = [int64]$Matches[1] }
                if ($line -match '^info .*\btime\s+(\d+)') { $uciTime = [int64]$Matches[1] }
            }
            if ($nodes -le 0) { throw "no node count for depth $depth position $positionIndex" }
            $isOrdinary = $OrdinaryExcludedPositions -notcontains $positionIndex
            $elapsed = [int64]$positionWatch.ElapsedMilliseconds
            $positionRows += [pscustomobject]@{
                depth = $depth; position = $positionIndex; ordinary = $isOrdinary
                nodes = $nodes; time_ms = $elapsed; uci_time_ms = $uciTime
            }
            $totalNodes += $nodes
            $fullTime += $elapsed
            if ($isOrdinary) { $ordinaryNodes += $nodes; $ordinaryTime += $elapsed }
        }
        Stop-Engine
        $depthWatch.Stop()
        $ratio = if ($previous -gt 0) { [math]::Round($totalNodes / $previous, 3) } else { [double]::NaN }
        $rows += [pscustomobject]@{
            depth = $depth; nodes = $totalNodes; ratio = $ratio; time_ms = $fullTime
            ordinary_nodes = $ordinaryNodes; ordinary_time_ms = $ordinaryTime
            depth_wall_ms = [int64]$depthWatch.ElapsedMilliseconds
        }
        Write-Host ("{0,5} {1,16:N0} {2,10} {3,14:N0} {4,14:N0}" -f `
            $depth, $totalNodes, $(if ([double]::IsNaN($ratio)) { "-" } else { $ratio }), $fullTime, $ordinaryTime)
        $previous = $totalNodes
    }

    $withRatio = @($rows | Where-Object { -not [double]::IsNaN($_.ratio) })
    if ($withRatio.Count -gt 0) {
        $logs = $withRatio | ForEach-Object { [math]::Log($_.ratio) }
        $geometric = [math]::Round([math]::Exp(($logs | Measure-Object -Sum).Sum / $logs.Count), 3)
        Write-Host "`ngeometric mean branching factor over $($withRatio.Count) plies: $geometric"
    }
    Write-Report "complete" $null
} catch {
    $failureMessage = $_.Exception.Message
    Write-Report "incomplete" $failureMessage
    throw
} finally {
    Stop-Engine
    $runWatch.Stop()
}
