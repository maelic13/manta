#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Step-5.4.0 nodes-to-depth and effective branching factor profile.

.DESCRIPTION
    PLAN 5.4.0 owns one number the project has never tracked: how many nodes
    Manta spends to REACH a depth, rather than how many it visits per second.
    A diagnostic gauntlet showed Manta reaching depth 7.6 where two mature
    references reached 11.0 and 12.5 at only two to two-and-a-half times its
    node rate, so five plies separate them at a speed factor of two. That gap
    is tree size per depth, and this script measures it.

    Runs the versioned bench at each depth in turn and reports total nodes, the
    depth-over-depth node ratio, wall time and reported effective branching
    factor. The depth-over-depth ratio is the honest branching measure: the
    engine's own `ebf` field is a single-depth estimate, while the ratio of
    consecutive whole-corpus node counts is what actually decides how deep a
    fixed node budget reaches.

    Deterministic and read-only. It changes no engine state and writes nothing
    except its own report. Node counts are exact, so only the wall-time and
    nps columns need an idle host.

.PARAMETER Binary
    Engine to profile. Defaults to the production build in zig-out/bin.

.PARAMETER MaxDepth
    Highest depth to run. Cost grows by roughly the branching factor per ply,
    so each added depth costs about as much as everything before it.

.EXAMPLE
    pwsh -NoProfile -File .\tools\search_profile.ps1 -MaxDepth 10
#>

[CmdletBinding()]
param(
    [string]$Binary = "",
    [int]$MinDepth = 1,
    [int]$MaxDepth = 10,
    [string]$OutFile = "",
    [int]$TimeoutMs = 1800000
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "harness_common.ps1")

$root = Split-Path -Parent $PSScriptRoot
if (-not $Binary) { $Binary = Join-Path $root "zig-out\bin\manta.exe" }
if (-not (Test-Path -LiteralPath $Binary)) {
    throw "Engine not found: $Binary. Build it with 'zig build -Doptimize=ReleaseFast' first."
}
if ($MinDepth -lt 1 -or $MaxDepth -lt $MinDepth) { throw "Require 1 <= MinDepth <= MaxDepth." }

Write-Host "Search profile: $Binary"
Write-Host "depths $MinDepth..$MaxDepth`n"
$header = "{0,5} {1,16} {2,10} {3,10} {4,12} {5,8}" -f "depth", "nodes", "ratio", "ebf", "time_ms", "Mnps"
Write-Host $header
Write-Host ("-" * $header.Length)

$rows = @()
$previous = 0
foreach ($depth in $MinDepth..$MaxDepth) {
    $line = Invoke-MantaBench -BinaryPath $Binary -Depth $depth -TimeoutMs $TimeoutMs
    if ($line -notmatch 'Nodes searched\s*:\s*(\d+)') { throw "No node count in bench summary: $line" }
    $nodes = [int64]$Matches[1]
    $timeMs = if ($line -match 'Total time \(ms\)\s*:\s*(\d+)') { [int64]$Matches[1] } else { 0 }
    $ebf = if ($line -match 'Geomean EBF\s*:\s*([0-9.]+)') { [double]$Matches[1] } else { [double]::NaN }
    $ratio = if ($previous -gt 0) { [math]::Round($nodes / $previous, 3) } else { [double]::NaN }
    $mnps = if ($timeMs -gt 0) { [math]::Round($nodes / $timeMs / 1000.0, 3) } else { [double]::NaN }

    $rows += [pscustomobject]@{
        depth = $depth; nodes = $nodes; ratio = $ratio; ebf = $ebf; time_ms = $timeMs; mnps = $mnps
    }
    Write-Host ("{0,5} {1,16:N0} {2,10} {3,10} {4,12:N0} {5,8}" -f `
        $depth, $nodes, $(if ([double]::IsNaN($ratio)) { "-" } else { $ratio }), $ebf, $timeMs, $mnps)
    $previous = $nodes
}

# The geometric mean of the last few ratios is the branching factor that
# actually governs how deep a fixed node budget reaches. Early depths are
# dominated by fixed qsearch cost and are excluded.
$tail = $rows | Where-Object { -not [double]::IsNaN($_.ratio) -and $_.depth -ge [math]::Max($MinDepth + 1, $MaxDepth - 3) }
if ($tail) {
    $logs = $tail | ForEach-Object { [math]::Log($_.ratio) }
    $geometric = [math]::Round([math]::Exp(($logs | Measure-Object -Sum).Sum / $logs.Count), 3)
    Write-Host ""
    Write-Host "geometric mean node ratio over the last $($tail.Count) plies: $geometric"
    Write-Host "A well-pruned engine sits near 2. Every 1.0 above that costs roughly"
    Write-Host "one ply per doubling of the node budget."
}

if ($OutFile) {
    $rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutFile -Encoding utf8
    Write-Host "`nreport -> $OutFile"
}
