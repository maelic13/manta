$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($env:RUNNER_OS -ne "Windows" -or $env:RUNNER_ARCH -ne "ARM64") {
    throw "The direct native gate requires a Windows ARM64 runner."
}

function Invoke-Zig {
    param([Parameter(Mandatory)][string[]] $ZigArguments)

    Write-Host "zig $($ZigArguments -join ' ')"
    & zig @ZigArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Zig failed with exit code $LASTEXITCODE."
    }
}

$runnerTemp = $env:RUNNER_TEMP
if ([string]::IsNullOrWhiteSpace($runnerTemp)) {
    throw "RUNNER_TEMP must identify the GitHub runner's temporary directory."
}

$outputDirectory = Join-Path $runnerTemp "manta-windows-arm64"
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

Invoke-Zig -ZigArguments @(
    "test", "-O", "ReleaseSafe",
    "--dep", "manta",
    "-Mroot=tests/root.zig",
    "-Mmanta=src/manta.zig"
)
Invoke-Zig -ZigArguments @(
    "test", "-O", "ReleaseSafe",
    "-Mroot=build_support/zig_version.zig"
)
Invoke-Zig -ZigArguments @(
    "test", "-O", "ReleaseSafe",
    "-Mroot=tools/policy_check.zig"
)

$policyExecutable = Join-Path $outputDirectory "manta-policy-check.exe"
Invoke-Zig -ZigArguments @(
    "build-exe", "-O", "ReleaseSafe",
    "-femit-bin=$policyExecutable",
    "-Mroot=tools/policy_check.zig"
)
& $policyExecutable
if ($LASTEXITCODE -ne 0) {
    throw "Policy checker failed with exit code $LASTEXITCODE."
}

$safeExecutable = Join-Path $outputDirectory "manta-release-safe.exe"
Invoke-Zig -ZigArguments @(
    "build-exe", "-O", "ReleaseSafe",
    "-femit-bin=$safeExecutable",
    "--dep", "manta",
    "-Mroot=src/main.zig",
    "-Mmanta=src/manta.zig"
)

$fastExecutable = Join-Path $outputDirectory "manta-release-fast.exe"
Invoke-Zig -ZigArguments @(
    "build-exe", "-O", "ReleaseFast",
    "-femit-bin=$fastExecutable",
    "--dep", "manta",
    "-Mroot=src/main.zig",
    "-Mmanta=src/manta.zig"
)
& $fastExecutable
if ($LASTEXITCODE -ne 0) {
    throw "ReleaseFast smoke test failed with exit code $LASTEXITCODE."
}
