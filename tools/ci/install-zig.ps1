$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$version = "0.17.1"

if ($env:RUNNER_OS -ne "Windows") {
    throw "Windows installer received RUNNER_OS='$env:RUNNER_OS'."
}
switch ($env:RUNNER_ARCH) {
    "X64" {
        $artifact = "x86_64-windows"
        $expectedHash = "b03f477a1943673e02aca0f570e8030dffd536ce1f45cbc4d3326ec31159562e"
    }
    "ARM64" {
        $artifact = "aarch64-windows"
        $expectedHash = "4789895bdb1e312a2ea73b2a7c0a0cc8d2ab62ba6976e834a7c54cf443377c15"
    }
    default {
        throw "Unsupported Windows runner architecture '$env:RUNNER_ARCH'."
    }
}

$installDirectory = Join-Path $env:RUNNER_TEMP "zig-$version"
$zigExecutable = Join-Path $installDirectory "zig.exe"

if (-not (Test-Path -LiteralPath $zigExecutable -PathType Leaf)) {
    $archive = Join-Path $env:RUNNER_TEMP "$artifact-$version.zip"
    $staging = Join-Path $env:RUNNER_TEMP "manta-zig-extract-$version"
    if (Test-Path -LiteralPath $installDirectory) {
        throw "Cached Zig directory is incomplete: $installDirectory"
    }
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }

    $url = "https://ziglang.org/download/$version/zig-$artifact-$version.zip"
    Write-Host "Downloading $url"
    & curl.exe --fail --location --retry 3 --retry-all-errors `
        --connect-timeout 20 --max-time 300 --output $archive $url
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download Zig archive (curl exit $LASTEXITCODE)."
    }
    $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Zig archive checksum mismatch: expected $expectedHash, received $actualHash."
    }

    Expand-Archive -LiteralPath $archive -DestinationPath $staging
    Move-Item -LiteralPath (Join-Path $staging "zig-$artifact-$version") -Destination $installDirectory
    Remove-Item -LiteralPath $staging -Recurse -Force
    Remove-Item -LiteralPath $archive -Force
}

$actualVersion = & $zigExecutable version
if ($actualVersion -ne $version) {
    throw "Expected Zig $version, received '$actualVersion'."
}
Add-Content -LiteralPath $env:GITHUB_PATH -Value $installDirectory
Write-Host "Using Zig $actualVersion from $installDirectory"
