<#
.SYNOPSIS
    Generate a deterministic Manta self-play PGN segment for HCE fitting.

.DESCRIPTION
    Manta-owned adaptation of Rarog's proven fixed-node fastchess datagen
    launcher. One game is played from each independently sampled opening.
    A fixed seed shuffles the opening book reproducibly; Start and Rounds name
    a non-wrapping segment, so later segments cannot silently reuse starts.

    Games use the Step-5.3.16 datagen-v1 label policy: 8,000 nodes per move by
    default, draw 40/8/10, two-sided resignation 600/3, and a 200-move cap.
    Fixed-node games may use high concurrency without creating clock bias.

    Existing PGNs and manifests are never overwritten or appended. An
    interrupted partial PGN is retained for diagnosis; restart it as a new
    explicitly named segment rather than mixing provenance.

.PARAMETER Suffix
    Engine suffix. Resolves tools\test_engines\manta-<Suffix>.exe and its JSON
    build manifest.

.PARAMETER Rounds
    Independent games in this segment. Zero consumes the remaining book tail.

.PARAMETER Start
    One-based start in the deterministically shuffled opening order.

.PARAMETER Concurrency
    Simultaneous fixed-node games. Zero uses logical processors minus two.

.PARAMETER SetupOnly
    Validate and print the exact command without creating outputs or games.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Suffix,
    [int]$Rounds = 0,
    [int]$Start = 1,
    [int]$Seed = 5316003,
    [int]$Nodes = 8000,
    [int]$Hash = 16,
    [int]$Concurrency = 0,
    [string]$OutputPgn = "",
    [string]$Book = "",
    [ValidateSet("pgn", "epd")][string]$BookFormat = "epd",
    [string]$FastchessPath = "",
    [switch]$SetupOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "harness_common.ps1")

$expectedFastchessSha256 = "8444E73965AE44E716CDE1BB546A7D7C8C9FC7A442A44194A0C71A3BFFA7DD0D"

function Get-TextLineCount([string]$Path) {
    $reader = [System.IO.File]::OpenText($Path)
    try {
        $count = 0
        while ($null -ne $reader.ReadLine()) { $count++ }
        $count
    } finally {
        $reader.Dispose()
    }
}

function Get-DatagenProfile {
    [pscustomobject]@{
        Name = "datagen-v1"
        DrawMoveNumber = 40
        DrawMoveCount = 8
        DrawScore = 10
        ResignMoveCount = 3
        ResignScore = 600
        ResignTwoSided = $true
        MaxMoves = 200
    }
}

function Write-JsonAtomic([string]$Path, [object]$Value) {
    $temporary = "$Path.tmp"
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    if (-not $Book) {
        $Book = Join-Path $PSScriptRoot "texel\data\beast-seed-v1.epd"
    }
    if (-not $FastchessPath) {
        $FastchessPath = Join-Path $PSScriptRoot "bin\fastchess.exe"
    }
    $enginePath = Join-Path $PSScriptRoot "test_engines\manta-$Suffix.exe"

    foreach ($inputPath in @($Book, $FastchessPath, $enginePath)) {
        if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
            throw "Required input not found: $inputPath"
        }
    }
    $Book = (Resolve-Path -LiteralPath $Book).Path
    $FastchessPath = (Resolve-Path -LiteralPath $FastchessPath).Path
    $enginePath = (Resolve-Path -LiteralPath $enginePath).Path

    if ($Start -lt 1) { throw "Start must be at least one (got $Start)." }
    if ($Rounds -lt 0) { throw "Rounds must be non-negative (got $Rounds)." }
    if ($Seed -lt 1) { throw "Seed must be positive (got $Seed)." }
    if ($Nodes -lt 1) { throw "Nodes must be positive (got $Nodes)." }
    if ($Hash -lt 1) { throw "Hash must be positive (got $Hash)." }

    if ($Concurrency -le 0) {
        $Concurrency = [Math]::Max(1, [Environment]::ProcessorCount - 2)
    }

    $openings = if ($BookFormat -eq "epd") {
        Get-TextLineCount $Book
    } else {
        (Select-String -LiteralPath $Book -Pattern '^\[Event ').Count
    }
    if ($openings -le 0) { throw "No openings found in $Book." }
    if ($Start -gt $openings) {
        throw "Start $Start exceeds the $openings openings in the book."
    }
    $remaining = $openings - $Start + 1
    if ($Rounds -eq 0) { $Rounds = $remaining }
    if ($Rounds -gt $remaining) {
        throw "Segment $Start..$($Start + $Rounds - 1) exceeds the $openings-opening book."
    }
    $segmentEnd = $Start + $Rounds - 1

    if (-not $OutputPgn) {
        $OutputPgn = Join-Path $PSScriptRoot "texel\data\selfplay-$Suffix-n$Nodes-s$Start-g$Rounds.pgn"
    }
    $OutputPgn = [System.IO.Path]::GetFullPath($OutputPgn)
    $outputManifest = [System.IO.Path]::ChangeExtension($OutputPgn, ".manifest.json")
    foreach ($output in @($OutputPgn, $outputManifest)) {
        if (Test-Path -LiteralPath $output) {
            throw "Output already exists and will not be overwritten: $output"
        }
    }

    $engineManifestPath = [System.IO.Path]::ChangeExtension($enginePath, ".json")
    if (-not (Test-Path -LiteralPath $engineManifestPath -PathType Leaf)) {
        throw "Missing engine manifest: $engineManifestPath"
    }
    $engineManifest = Get-Content -Raw -LiteralPath $engineManifestPath | ConvertFrom-Json
    if ($engineManifest.engine -ne [System.IO.Path]::GetFileName($enginePath)) {
        throw "Engine manifest names '$($engineManifest.engine)', expected '$([System.IO.Path]::GetFileName($enginePath))'."
    }
    if ([bool]$engineManifest.git_dirty) {
        throw "Datagen engine was built from a dirty tree."
    }
    if ($engineManifest.verification -ne "bench") {
        throw "Datagen engine manifest does not record bench verification."
    }

    $engineHash = Get-HarnessSha256 -Path $enginePath
    if ($engineManifest.binary_sha256 -ne $engineHash) {
        throw "Engine binary SHA-256 does not match its manifest."
    }
    $bookHash = Get-HarnessSha256 -Path $Book
    $fastchessHash = Get-HarnessSha256 -Path $FastchessPath
    if ($fastchessHash -ne $expectedFastchessSha256) {
        throw "fastchess SHA-256 changed: expected $expectedFastchessSha256, found $fastchessHash."
    }
    $fastchessInfo = Get-FastchessVersion -Path $FastchessPath

    if (-not (Test-EngineSupportsOption -Path $enginePath -Name "Hash")) {
        throw "Manta does not advertise the required Hash UCI option."
    }
    $threadsAdvertised = Test-EngineSupportsOption -Path $enginePath -Name "Threads"
    if ($threadsAdvertised) {
        throw "This Phase-5 launcher expects fixed-1T Manta without a Threads option; review the policy before using an SMP build."
    }

    $profile = Get-DatagenProfile
    $fastchessArgs = @(
        '-engine', "cmd=$enginePath", 'name=A', "option.Hash=$Hash",
        '-engine', "cmd=$enginePath", 'name=B', "option.Hash=$Hash",
        '-each', 'tc=inf', "nodes=$Nodes",
        '-openings', "file=$Book", "format=$BookFormat", 'order=random', "start=$Start",
        '-srand', "$Seed",
        '-rounds', "$Rounds", '-games', '1',
        '-concurrency', "$Concurrency",
        '-draw', "movenumber=$($profile.DrawMoveNumber)", "movecount=$($profile.DrawMoveCount)", "score=$($profile.DrawScore)",
        '-resign', "movecount=$($profile.ResignMoveCount)", "score=$($profile.ResignScore)", 'twosided=true',
        '-maxmoves', "$($profile.MaxMoves)",
        '-pgnout', "file=$OutputPgn", 'append=false',
        '-output', 'format=fastchess'
    )

    $quotedArgs = $fastchessArgs | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }
    Write-Host ""
    Write-Host "Manta HCE datagen-v1"
    Write-Host "  Engine      : $enginePath"
    Write-Host "  Engine SHA  : $engineHash"
    Write-Host "  Games       : $Rounds (one independent opening each)"
    Write-Host "  Segment     : $Start..$segmentEnd of $openings (seed $Seed)"
    Write-Host "  Search      : $Nodes nodes/move, fixed 1T, Hash $Hash MiB"
    Write-Host "  Concurrency : $Concurrency (unaffined fixed-node games)"
    Write-Host "  Policy      : draw 40/8/10; resign 600/3 two-sided; max 200 moves"
    Write-Host "  Book SHA    : $bookHash"
    Write-Host "  Runner      : $($fastchessInfo.Text)"
    Write-Host "  Runner SHA  : $fastchessHash"
    Write-Host "  Output      : $OutputPgn"
    Write-Host "  Command     : & `"$FastchessPath`" $($quotedArgs -join ' ')"

    if ($SetupOnly) {
        Write-Host "SetupOnly: validation passed; no output or game was created."
        return
    }

    $outputDirectory = Split-Path -Parent $OutputPgn
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    }

    $startedUtc = (Get-Date).ToUniversalTime()
    & $FastchessPath @fastchessArgs
    $runnerExit = $LASTEXITCODE
    if ($runnerExit -ne 0) {
        throw "fastchess exited with code $runnerExit; partial PGN retained at $OutputPgn."
    }
    if (-not (Test-Path -LiteralPath $OutputPgn -PathType Leaf)) {
        throw "fastchess exited successfully without producing $OutputPgn."
    }

    $pgnHash = Get-HarnessSha256 -Path $OutputPgn
    $pgnBytes = (Get-Item -LiteralPath $OutputPgn).Length
    $manifest = [ordered]@{
        schema = "manta-fastchess-datagen-v1"
        started_utc = $startedUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
        completed_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        engine = [ordered]@{
            path = $enginePath
            sha256 = $engineHash
            manifest = $engineManifestPath
            git_sha = $engineManifest.git_sha
            git_tree = $engineManifest.git_tree
            git_branch = $engineManifest.git_branch
            git_dirty = [bool]$engineManifest.git_dirty
            bench_nodes = [int64]$engineManifest.bench_nodes
            built_utc = $engineManifest.built_utc
        }
        book = [ordered]@{
            path = $Book
            format = $BookFormat
            sha256 = $bookHash
            openings = $openings
            seed = $Seed
            start = $Start
            end = $segmentEnd
        }
        games = $Rounds
        nodes_per_move = $Nodes
        hash_mb = $Hash
        effective_threads = 1
        threads_option_sent = $false
        concurrency = $Concurrency
        adjudication = $profile
        fastchess = [ordered]@{ version = $fastchessInfo.Text; sha256 = $fastchessHash }
        output = [ordered]@{ path = $OutputPgn; bytes = $pgnBytes; sha256 = $pgnHash }
    }
    Write-JsonAtomic -Path $outputManifest -Value $manifest
    Write-Host "Done: $OutputPgn"
    Write-Host "Manifest: $outputManifest"
} finally {
    Pop-Location
}
