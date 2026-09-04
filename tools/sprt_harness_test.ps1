$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'harness_common.ps1')

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("manta-sprt-test-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    function Write-TestLog([string]$Name, [string[]]$Lines) {
        $path = Join-Path $testRoot $Name
        $Lines | Set-Content -LiteralPath $path -Encoding utf8
        $path
    }
    function Assert-Throws([scriptblock]$Action, [string]$Label) {
        try { & $Action; throw "Expected rejection: $Label" }
        catch { if ($_.Exception.Message -eq "Expected rejection: $Label") { throw } }
    }

    if ((Get-HarnessBuildContract 'native') -ne 'native') { throw 'native contract failed' }
    if ((Get-HarnessBuildContract 'native-integrated-time') -ne 'native') { throw 'feature normalization failed' }
    if ((Get-HarnessBuildContract 'portable-pgo-tune') -ne 'portable-pgo') { throw 'PGO contract failed' }

    $clean = Write-TestLog 'clean.log' @('Player: A', 'Timeouts: 0', 'Crashed: 0')
    Assert-StrengthMatchLog -LogPath $clean

    $clock = Write-TestLog 'clock.log' @(
        'Finished game 9 (A vs B): 0-1 {White loses on time}',
        'Player: A', 'Timeouts: 1', 'Crashed: 0',
        'Player: B', 'Timeouts: 0', 'Crashed: 0')
    Assert-Throws { Assert-StrengthMatchLog -LogPath $clock } 'strict timeout'
    Assert-StrengthMatchLog -LogPath $clock -ScoreCompletedTimeForfeits

    $unreconciled = Write-TestLog 'unreconciled.log' @(
        'Finished game 9 (A vs B): 0-1 {White loses on time}',
        'Player: A', 'Timeouts: 0', 'Crashed: 0')
    Assert-Throws { Assert-StrengthMatchLog -LogPath $unreconciled -ScoreCompletedTimeForfeits } 'unreconciled timeout'

    $crash = Write-TestLog 'crash.log' @('Player: A', 'Timeouts: 0', 'Crashed: 1')
    Assert-Throws { Assert-StrengthMatchLog -LogPath $crash -ScoreCompletedTimeForfeits } 'crash'

    Write-Host 'SPRT harness tests passed.' -ForegroundColor Green
} finally {
    $resolvedRoot = [System.IO.Path]::GetFullPath($testRoot)
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove test directory outside the system temp root: $resolvedRoot"
    }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}
