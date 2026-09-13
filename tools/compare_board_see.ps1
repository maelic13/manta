#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Setup-only comparison of Manta and Basilisk threshold-SEE decisions.

.DESCRIPTION
    Runs only each existing board benchmark's preflight and SEE signature mode.
    It performs no timing, search or games. Rows are normalized by position and
    UCI move because cross-engine generation order is not a semantic target.
#>

[CmdletBinding()]
param(
    [string]$MantaBench = "",
    [string]$BasiliskBench = "",
    [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $MantaBench) {
    $MantaBench = Join-Path $root "zig-out\bin\manta-board-bench.exe"
}
if (-not $BasiliskBench) {
    $BasiliskBench = "D:\code\basilisk\build\release-pext\board_performance_test.exe"
}
foreach ($required in @($MantaBench, $BasiliskBench)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "missing benchmark executable: $required"
    }
}

function Read-Signature([string]$path, [string]$engine) {
    $resolved = (Resolve-Path -LiteralPath $path).Path
    $output = @(& $resolved --profile cross-engine-board-v1 --preflight-only --see-signature 2>&1 |
        ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -ne 0) {
        throw "$engine preflight failed with exit code $LASTEXITCODE`n$($output -join [Environment]::NewLine)"
    }
    if ($output -notcontains "preflight: PASS") { throw "$engine did not report a passing preflight" }

    $rows = [System.Collections.Generic.List[object]]::new()
    $reportedCount = $null
    foreach ($line in $output) {
        if ($line -match '^SEE-CONTRACT-V1 position=(\d+) move=([a-h][1-8][a-h][1-8][nbrq]?) result=(true|false)$') {
            $rows.Add([pscustomobject]@{
                position = [int]$Matches[1]
                move = $Matches[2]
                result = [bool]::Parse($Matches[3])
            })
        } elseif ($line -match '^SEE-CONTRACT-V1 count=(\d+)$') {
            $reportedCount = [int]$Matches[1]
        }
    }
    if ($null -eq $reportedCount) { throw "$engine omitted the SEE signature count" }
    if ($reportedCount -ne 10 -or $rows.Count -ne $reportedCount) {
        throw "$engine reported $reportedCount SEE rows but emitted $($rows.Count); expected 10"
    }
    $normalized = @($rows | Sort-Object position, move)
    $keys = @($normalized | ForEach-Object { "$($_.position):$($_.move)" })
    if (@($keys | Sort-Object -Unique).Count -ne $keys.Count) {
        throw "$engine emitted a duplicate position/move SEE row"
    }
    return [pscustomobject]@{
        engine = $engine
        path = $resolved
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolved).Hash
        rows = $normalized
    }
}

$manta = Read-Signature $MantaBench "Manta"
$basilisk = Read-Signature $BasiliskBench "Basilisk"
$differences = [System.Collections.Generic.List[object]]::new()
for ($index = 0; $index -lt 10; $index++) {
    $left = $manta.rows[$index]
    $right = $basilisk.rows[$index]
    if ($left.position -ne $right.position -or $left.move -ne $right.move -or $left.result -ne $right.result) {
        $differences.Add([pscustomobject]@{
            manta = "$($left.position):$($left.move):$($left.result)"
            basilisk = "$($right.position):$($right.move):$($right.result)"
        })
    }
}

$report = [pscustomobject]@{
    schema = "manta-board-see-comparison-v1"
    status = if ($differences.Count -eq 0) { "PASS" } else { "FAIL" }
    threshold = 0
    positions = 5
    captures = 10
    semantics = "legal captures; 100/300/300/500/900/20000 piece values; generation order normalized"
    manta = [pscustomobject]@{ path = $manta.path; sha256 = $manta.sha256 }
    basilisk = [pscustomobject]@{ path = $basilisk.path; sha256 = $basilisk.sha256 }
    rows = $manta.rows
    differences = @($differences)
}

if ($OutFile) {
    $reportPath = [System.IO.Path]::GetFullPath($OutFile)
    $parent = Split-Path -Parent $reportPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Path $parent)
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8
    Write-Host "report -> $reportPath"
}

if ($differences.Count -ne 0) {
    $differences | Format-Table -AutoSize | Out-Host
    throw "threshold-SEE signatures differ"
}
Write-Host "SEE comparison: PASS (10/10 decisions, threshold 0)"
Write-Host "Manta:   $($manta.sha256)"
Write-Host "Basilisk: $($basilisk.sha256)"
