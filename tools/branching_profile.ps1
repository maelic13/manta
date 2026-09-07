#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Step-5.4.0 cross-engine nodes-to-depth and branching-factor profile.

.DESCRIPTION
    Drives any UCI engine with `go depth N` over one fixed position set and
    reports the total nodes each depth costs, plus the ratio between consecutive
    depths. That ratio is the branching factor that decides how deep a node
    budget reaches, unlike a single-depth `nodes^(1/depth)` estimate which folds
    in the fixed cost of the first plies.

    This exists because Manta's own `bench` pins a 16 MiB transposition table at
    comptime so its fingerprint stays deterministic, which is correct for a
    fingerprint and useless for asking whether a branching measurement was
    distorted by table pressure. Driving plain UCI makes Hash a variable.

    Each depth runs in a FRESH engine process. Manta does not need this: a
    direct check shows identical node counts for a position whether searched
    cold, after shallower searches of the same position, or after a search of a
    different one, because `ucinewgame` clears both the transposition table and
    the ordering state. It is kept because this tool drives arbitrary engines and
    not all of them guarantee that, and because an independent process per depth
    makes the guarantee unnecessary to verify per engine.

    HASH SIZE IS PART OF THE MEASUREMENT. Manta scores 171,653,746 nodes at
    depth twelve with 16 MiB and 159,169,542 with 64 MiB, a difference of nearly
    eight percent. Never compare figures taken at different sizes: every row of a
    comparison must be run at one size, and the size belongs in the report.

    Because every engine runs the same positions, the same depths and the same
    hash, the ratio column is directly comparable across engines. Absolute node
    counts are not: engines differ in what they count as a node.

.PARAMETER Engine
    Path to a UCI engine executable.

.PARAMETER Positions
    EPD/FEN file, one position per line. Defaults to Manta's bench corpus.

.EXAMPLE
    pwsh -NoProfile -File .\tools\branching_profile.ps1 -Engine .\zig-out\bin\manta.exe -MaxDepth 9 -Hash 256
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Engine,
    [string]$Positions = "",
    [int]$MinDepth = 4,
    [int]$MaxDepth = 9,
    [int]$Hash = 16,
    [int]$Threads = 1,
    [int]$PositionLimit = 0,
    [string]$OutFile = "",
    [int]$TimeoutMs = 1800000
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $Positions) { $Positions = Join-Path $root "tools\bench_positions.epd" }
foreach ($required in @($Engine, $Positions)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "missing: $required" }
}
$fens = @(Get-Content -LiteralPath $Positions | Where-Object { $_.Trim() })
if ($PositionLimit -gt 0 -and $fens.Count -gt $PositionLimit) {
    $fens = $fens[0..($PositionLimit - 1)]
}

$enginePath = (Resolve-Path -LiteralPath $Engine).Path
$script:proc = $null

function Start-Engine {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $enginePath
    $psi.WorkingDirectory       = (Split-Path -Parent $enginePath)
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $script:proc = [System.Diagnostics.Process]::Start($psi)
}
function Stop-Engine {
    if ($null -eq $script:proc) { return }
    if (-not $script:proc.HasExited) {
        try { $script:proc.StandardInput.WriteLine("quit") } catch {}
        $script:proc.WaitForExit(5000) | Out-Null
    }
    if (-not $script:proc.HasExited) { $script:proc.Kill($true) }
    $script:proc.Dispose()
    $script:proc = $null
}

function Send([string]$text) { $script:proc.StandardInput.WriteLine($text) }
function WaitFor([string]$pattern, [int]$ms) {
    $deadline = [datetime]::UtcNow.AddMilliseconds($ms)
    $seen = New-Object System.Collections.Generic.List[string]
    while ([datetime]::UtcNow -lt $deadline) {
        $line = $script:proc.StandardOutput.ReadLine()
        if ($null -eq $line) { throw "engine closed stdout early" }
        $seen.Add($line)
        if ($line -match $pattern) { return $seen }
    }
    throw "timed out waiting for /$pattern/"
}

try {
    Write-Host "Engine:    $Engine"
    Write-Host "Positions: $($fens.Count) from $(Split-Path -Leaf $Positions)"
    Write-Host "Hash:      $Hash MiB   Threads: $Threads`n"
    $header = "{0,5} {1,16} {2,10} {3,12}" -f "depth", "nodes", "ratio", "time_ms"
    Write-Host $header
    Write-Host ("-" * $header.Length)

    $rows = @(); $positionRows = @(); $previous = 0
    foreach ($depth in $MinDepth..$MaxDepth) {
        # Fresh process per depth: see the note in the description.
        Start-Engine
        Send "uci";     [void](WaitFor '^uciok' 30000)
        Send "setoption name Hash value $Hash"
        Send "setoption name Threads value $Threads"
        Send "isready"; [void](WaitFor '^readyok' 30000)
        $total = [int64]0
        $positionIndex = 0
        $started = Get-Date
        foreach ($fen in $fens) {
            # A fresh game per position keeps one position's table and history
            # from paying for the next one's search.
            Send "ucinewgame"
            Send "isready"; [void](WaitFor '^readyok' 60000)
            Send "position fen $fen"
            Send "go depth $depth"
            $lines = WaitFor '^bestmove' $TimeoutMs
            $nodes = 0
            foreach ($line in $lines) {
                if ($line -match '^info .*\bnodes\s+(\d+)') { $nodes = [int64]$Matches[1] }
            }
            if ($nodes -le 0) { throw "no node count for depth $depth on: $fen" }
            # Per-position rows exist so one opening or ending cannot decide a
            # diagnosis that the aggregate would hide.
            $positionRows += [pscustomobject]@{ depth = $depth; position = $positionIndex; nodes = $nodes }
            $positionIndex += 1
            $total += $nodes
        }
        $elapsed = [int64]((Get-Date) - $started).TotalMilliseconds
        Stop-Engine
        $ratio = if ($previous -gt 0) { [math]::Round($total / $previous, 3) } else { [double]::NaN }
        $rows += [pscustomobject]@{ depth = $depth; nodes = $total; ratio = $ratio; time_ms = $elapsed }
        Write-Host ("{0,5} {1,16:N0} {2,10} {3,12:N0}" -f `
            $depth, $total, $(if ([double]::IsNaN($ratio)) { "-" } else { $ratio }), $elapsed)
        $previous = $total
    }

    $withRatio = $rows | Where-Object { -not [double]::IsNaN($_.ratio) }
    if ($withRatio) {
        $logs = $withRatio | ForEach-Object { [math]::Log($_.ratio) }
        $geometric = [math]::Round([math]::Exp(($logs | Measure-Object -Sum).Sum / $logs.Count), 3)
        Write-Host "`ngeometric mean branching factor over $($withRatio.Count) plies: $geometric"
    }
    if ($OutFile) {
        [pscustomobject]@{
            engine = $psi.FileName; positions = $fens.Count; hash_mb = $Hash
            threads = $Threads; rows = $rows; position_rows = $positionRows
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutFile -Encoding utf8
        Write-Host "report -> $OutFile"
    }
} finally {
    Stop-Engine
}
