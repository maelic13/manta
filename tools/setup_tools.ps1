<#
.SYNOPSIS
    One-shot setup: download fastchess, stage the opening book, and clone and
    patch weather-factory into tools/.

.DESCRIPTION
    Makes the Manta tuning toolchain self-contained inside the repo. Run this
    once after cloning if tools/bin/fastchess.exe or tools/weather-factory is
    missing.

    After this script:
      - tools/bin/fastchess.exe            (pinned release, affinity-capable)
      - tools/books/UHO_Lichess_4852_v1.epd (if a source copy was found)
      - tools/weather-factory/             (pinned revision + the four patches)
      - matplotlib installed for Python

    The four weather-factory patches are the same corrections Rarog validated
    over ~160,000 tuning games; without them a tune anneals wrongly, ignores
    affinity, cannot freeze architecture options, and adjudicates differently
    from sprt.ps1. spsa.ps1 refuses to launch unless all four markers are
    present, so this script is not optional.

.PARAMETER FastchessTag
    GitHub release tag to download. Default v1.8.0-alpha, a pinned release
    containing the Windows process-affinity fix introduced before v1.7.0.

.PARAMETER BookSource
    Directory to copy UHO_Lichess_4852_v1.epd from. Default D:\chess\books.
    Skipped silently if the book is already staged; warned if neither exists.

.EXAMPLE
    ./tools/setup_tools.ps1
#>
param(
    [string]$FastchessTag = "v1.8.0-alpha",
    [string]$BookSource = "D:\chess\books"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "harness_common.ps1")

# Every textual patch below is written against this exact upstream revision.
# A floating clone can accept an anchor while changing surrounding semantics,
# which is unacceptable for a runner that will consume tens of thousands of
# games.
$weatherFactoryRevision = "19b4805c9a2372955c29666118070269f34aa2eb"

$binDir   = Join-Path $PSScriptRoot "bin"
$booksDir = Join-Path $PSScriptRoot "books"
$wfDir    = Join-Path $PSScriptRoot "weather-factory"
New-Item -ItemType Directory -Force -Path $binDir   | Out-Null
New-Item -ItemType Directory -Force -Path $booksDir | Out-Null

# ─── fastchess ────────────────────────────────────────────────────────────
$fastchessExe = Join-Path $binDir "fastchess.exe"
$downloadFastchess = -not (Test-Path $fastchessExe)
if (Test-Path $fastchessExe) {
    try {
        $info = Assert-AffinityFastchess -Path $fastchessExe
        Write-Host "fastchess already present: $($info.Text)"
        Write-Host "  Existing compatible runner retained (version is recorded per match)."
    } catch {
        Write-Warning $_.Exception.Message
        Write-Host "  Replacing incompatible runner with $FastchessTag."
        $downloadFastchess = $true
    }
}
if ($downloadFastchess) {
    Write-Host "Downloading fastchess ($FastchessTag)..."

    $apiUrl = if ($FastchessTag -eq "latest") {
        "https://api.github.com/repos/Disservin/fastchess/releases/latest"
    } else {
        "https://api.github.com/repos/Disservin/fastchess/releases/tags/$FastchessTag"
    }

    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ Accept = "application/vnd.github.v3+json" }
    $asset = $release.assets |
        Where-Object { $_.name -like "*windows-x86-64*" } |
        Select-Object -First 1

    if (-not $asset) {
        throw "No windows-x86-64 asset found in fastchess release $($release.tag_name). Download manually to tools/bin/fastchess.exe."
    }

    $zipPath = Join-Path $binDir "fastchess.zip"
    Write-Host "  Downloading $($asset.name) from $($release.tag_name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
    if ($asset.digest -match '^sha256:(?<hash>[0-9a-fA-F]{64})$') {
        $actualHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash
        if ($actualHash -ne $Matches['hash']) {
            throw "fastchess archive SHA-256 mismatch: expected $($Matches['hash']), got $actualHash"
        }
        Write-Host "  Archive SHA-256 verified."
    }
    Write-Host "  Extracting..."
    $extractDir = Join-Path ([System.IO.Path]::GetTempPath()) ("manta-fastchess-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $extractDir | Out-Null
    try {
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        $extracted = @(Get-ChildItem -LiteralPath $extractDir -Recurse -Filter "fastchess.exe" -File)
        if ($extracted.Count -ne 1) {
            throw "Expected one fastchess.exe in $($asset.name), found $($extracted.Count)."
        }
        Copy-Item -LiteralPath $extracted[0].FullName -Destination $fastchessExe -Force
    } finally {
        Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path $fastchessExe)) {
        throw "fastchess.exe not found in tools/bin after extraction. Check zip contents and extract manually."
    }

    $ver = & $fastchessExe --version 2>&1 | Select-Object -First 1
    Write-Host "  Done: $ver"
    Assert-AffinityFastchess -Path $fastchessExe | Out-Null
}

# ─── opening book ─────────────────────────────────────────────────────────
# The book is git-ignored (175 MB) but is a measurement input: sprt.ps1 and
# spsa.ps1 both record its SHA-256 in their manifests, so it must be the same
# file Rarog uses for the two ledgers to be comparable.
$bookName = "UHO_Lichess_4852_v1.epd"
$bookDest = Join-Path $booksDir $bookName
if (Test-Path $bookDest) {
    Write-Host "Opening book already staged: $bookDest"
} else {
    $bookSrc = Join-Path $BookSource $bookName
    if (Test-Path $bookSrc) {
        Write-Host "Copying $bookName (175 MB) -> tools/books/ ..."
        Copy-Item -LiteralPath $bookSrc -Destination $bookDest -Force
        Write-Host "  Done. SHA-256: $(Get-HarnessSha256 $bookDest)"
    } else {
        Write-Warning ("$bookName not found in '$BookSource'. Copy it into tools/books/ " +
            "before running sprt.ps1 or spsa.ps1, or pass -Book explicitly.")
    }
}

# ─── weather-factory ──────────────────────────────────────────────────────
if (Test-Path (Join-Path $wfDir "main.py")) {
    Write-Host "weather-factory already present at tools/weather-factory/; skipping clone."
} else {
    Write-Host "Cloning weather-factory -> tools/weather-factory/ ..."
    git clone https://github.com/jnlt3/weather-factory $wfDir
    if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
    git -C $wfDir checkout --detach $weatherFactoryRevision
    if ($LASTEXITCODE -ne 0) { throw "Could not checkout pinned weather-factory revision $weatherFactoryRevision" }
    Write-Host "  Done."
}

$actualWeatherFactoryRevision = (git -C $wfDir rev-parse HEAD).Trim()
if ($actualWeatherFactoryRevision -ne $weatherFactoryRevision) {
    throw ("weather-factory is at $actualWeatherFactoryRevision, expected pinned revision " +
        "$weatherFactoryRevision. Preserve any tuner state, recreate tools/weather-factory, and rerun setup.")
}
Write-Host "weather-factory revision verified: $weatherFactoryRevision"

# NORMALIZE LINE ENDINGS before patching. Several anchors below are literal
# multi-line strings, and git hands out CRLF or LF depending on the machine's
# core.autocrlf — so an unnormalized clone makes a patch fail on one host and
# succeed on another for reasons that have nothing to do with upstream. Convert
# to LF once, and trim trailing whitespace so repeated setup runs converge
# instead of accreting a blank line each time.
foreach ($pyFile in @("cutechess.py", "spsa.py", "main.py")) {
    $pyPath = Join-Path $wfDir $pyFile
    if (-not (Test-Path $pyPath)) { continue }
    $text = (Get-Content $pyPath -Raw) -replace "`r`n", "`n"
    Set-Content -Path $pyPath -Value ($text.TrimEnd() + "`n") -Encoding utf8 -NoNewline
}
Write-Host "  Normalized weather-factory sources to LF for deterministic patching."

# PATCH 1 — AFFINITY. weather-factory has no native affinity setting. Patch its
# generated fastchess command with the OS-derived physical-core list. Rebuild
# this line on every setup so moving the clone to other hardware cannot retain
# stale IDs.
$wfCute = Join-Path $wfDir "cutechess.py"
if (Test-Path $wfCute) {
    $c = Get-Content $wfCute -Raw
    $allPhysicalCpus = (Get-HarnessPhysicalCpus).Cpu -join ','
    $c = $c -replace '(?m)^\s*\+ \("-use-affinity " if self\.use_fastchess else ""\).*\r?\n?', ''
    $c = $c -replace '(?m)^.*MANTA_AFFINITY_PATCH_V2.*\r?\n?', ''
    $anchor = 'f"-concurrency {self.threads} "'
    $patch = $anchor + "`n" + ('            f"{''-use-affinity ' + $allPhysicalCpus + ' '' if self.use_fastchess else ''''}"  # MANTA_AFFINITY_PATCH_V2')
    if (-not $c.Contains($anchor)) {
        throw "weather-factory/cutechess.py affinity patch anchor not found; upstream changed."
    }
    $c = $c.Replace($anchor, $patch)
    Set-Content -Path $wfCute -Value $c -Encoding utf8

    python -m py_compile $wfCute
    if ($LASTEXITCODE -ne 0) {
        throw "weather-factory affinity patch failed Python syntax validation: $wfCute"
    }
    Write-Host "  weather-factory affinity patch and Python syntax verified."
}

# PATCH 2 — FIXED OPTIONS. A tune freezes discrete architecture outside SPSA and
# tunes only the continuous consumers. Teach the runner to apply those fixed UCI
# options identically to both perturbed engines; they are deliberately absent
# from config.json, so they cannot receive another parameter's noisy gradient.
if (Test-Path $wfCute) {
    $c = Get-Content $wfCute -Raw
    if ($c -match 'MANTA_FIXED_OPTIONS_V1') {
        Write-Host "  weather-factory fixed-option support already present."
    } else {
        $signatureAnchor = '        use_fastchess: bool = True'
        if (-not $c.Contains($signatureAnchor)) {
            throw "weather-factory/cutechess.py fixed-option signature anchor not found; upstream changed."
        }
        $c = $c.Replace($signatureAnchor, "        use_fastchess: bool = True,`n        fixed_options: dict | None = None")

        $fieldAnchor = '        self.use_fastchess = use_fastchess'
        if (-not $c.Contains($fieldAnchor)) {
            throw "weather-factory/cutechess.py fixed-option field anchor not found; upstream changed."
        }
        $c = $c.Replace($fieldAnchor,
            $fieldAnchor + "`n        self.fixed_options = fixed_options or {}  # MANTA_FIXED_OPTIONS_V1")

        $commandAnchor = "        return (`n            f`"{command} `""
        if (-not $c.Contains($commandAnchor)) {
            throw "weather-factory/cutechess.py fixed-option command anchor not found; upstream changed."
        }
        $commandReplacement = "        fixed = ' '.join(f'option.{name}={value}' for name, value in self.fixed_options.items())`n" +
            "        fixed = (fixed + ' ') if fixed else ''`n`n" + $commandAnchor
        $c = $c.Replace($commandAnchor, $commandReplacement)
        $c = $c.Replace('f"option.Hash={self.hash_size} {'' ''.join(params_a)} "',
            'f"option.Hash={self.hash_size} {fixed}{'' ''.join(params_a)} "')
        $c = $c.Replace('f"option.Hash={self.hash_size} {'' ''.join(params_b)} "',
            'f"option.Hash={self.hash_size} {fixed}{'' ''.join(params_b)} "')

        Set-Content -Path $wfCute -Value $c -Encoding utf8
        python -m py_compile $wfCute
        if ($LASTEXITCODE -ne 0) {
            throw "weather-factory fixed-option patch failed Python syntax validation: $wfCute"
        }
        Write-Host "  weather-factory fixed-option support verified."
    }
}

# PATCH 3 — NO ADJUDICATION. The 2026-09-01 Rarog harness revision removed
# both weather-factory defaults. Draw adjudication truncates conversion/endgame
# time, while conservative resignation saves little. A clock tune must sample
# natural termination and actual clock demand. Never apply this patch to an
# in-progress run; spsa.ps1 permits old state to finish under its original rule.
if (Test-Path $wfCute) {
    $a = Get-Content $wfCute -Raw
    if ($a -match 'MANTA_ADJUDICATION_PATCH_V4') {
        Write-Host "  weather-factory adjudication patch already present (V4: none)."
    } else {
        $resignPattern = '(?m)^\s*"-resign[^"]*"(\s*#\s*MANTA_ADJUDICATION_PATCH_V[0-9][^\r\n]*)?\r?\n'
        $drawPattern = '(?m)^\s*"-draw[^"]*"(\s*#[^\r\n]*)?\r?\n'
        if ($a -notmatch $resignPattern) {
            throw ("weather-factory/cutechess.py adjudication anchor not found; upstream changed. " +
                "Inspect it before assuming the tuner runs without resignation adjudication.")
        }
        if ($a -notmatch $drawPattern) {
            throw ("weather-factory/cutechess.py draw anchor not found; upstream changed. " +
                "Inspect it before assuming the tuner runs without draw adjudication.")
        }
        $marker = '            ""  # MANTA_ADJUDICATION_PATCH_V4: adjudication off' + "`n"
        $a = [regex]::Replace($a, $resignPattern, $marker)
        $a = [regex]::Replace($a, $drawPattern, '')
        Set-Content -Path $wfCute -Value $a -Encoding utf8

        python -m py_compile $wfCute
        if ($LASTEXITCODE -ne 0) {
            throw "weather-factory adjudication patch failed Python syntax validation: $wfCute"
        }
        if ((Get-Content $wfCute -Raw) -match '(?m)^\s*"-(resign|draw)') {
            throw "weather-factory/cutechess.py still passes adjudication after the V4 patch."
        }
        Write-Host "  weather-factory adjudication removed (V4) and Python syntax verified."
    }
}

# PATCH 4a — SCHEDULE UNITS. weather-factory's SPSA schedule feeds t (GAMES,
# 32/iteration) into Spall's decay, which is designed per-iteration — the gain
# anneals 32^0.601 ~= 8x too fast and every tune freezes after a few hundred
# iterations. Patch step() to convert units; t/state.json stay in games so old
# states resume correctly.
$wfSpsa = Join-Path $wfDir "spsa.py"
if (Test-Path $wfSpsa) {
    $s = Get-Content $wfSpsa -Raw
    if ($s -match 'MANTA_SCHEDULE_FIX_V1') {
        Write-Host "  weather-factory SPSA schedule patch already present."
    } else {
        $anchorA = 'a_t = self.spsa.a / (self.t + self.spsa.A) ** self.spsa.alpha'
        $anchorC = 'c_t = self.spsa.c / self.t ** self.spsa.gamma'
        if (-not ($s.Contains($anchorA) -and $s.Contains($anchorC))) {
            throw "weather-factory/spsa.py schedule patch anchors not found; upstream changed."
        }
        $s = $s.Replace($anchorA,
            "it = self.t / self.cutechess.games  # MANTA_SCHEDULE_FIX_V1: Spall decay per-iteration; t/state.json stay in games`n" +
            "        a_t = self.spsa.a / (it + self.spsa.A) ** self.spsa.alpha")
        $s = $s.Replace($anchorC, 'c_t = self.spsa.c / it ** self.spsa.gamma')
        Set-Content -Path $wfSpsa -Value $s -Encoding utf8

        python -m py_compile $wfSpsa
        if ($LASTEXITCODE -ne 0) {
            throw "weather-factory schedule patch failed Python syntax validation: $wfSpsa"
        }
        Write-Host "  weather-factory SPSA schedule patch and Python syntax verified."
    }
}

# PATCH 4b — TRANSACTIONAL STEP. Commit the iteration counter only after the
# mini-match and parameter update complete. Upstream advances it before
# launching fastchess, so Ctrl-C can save an unplayed point as completed and
# resume from the wrong annealing step. Also roll back the parameter-update
# section if an interrupt lands inside it; otherwise state could contain half an
# update paired with the old counter.
if (Test-Path $wfSpsa) {
    $s = Get-Content $wfSpsa -Raw
    if ($s -notmatch 'MANTA_TRANSACTIONAL_STEP_V1') {
        $advanceAnchor = '(?m)^        self\.t \+= self\.cutechess\.games\r?\n        it = self\.t / self\.cutechess\.games  # MANTA_SCHEDULE_FIX_V1: Spall decay per-iteration; t/state\.json stay in games\r?$'
        if (-not [regex]::IsMatch($s, $advanceAnchor)) {
            throw "weather-factory/spsa.py transactional-step advance anchor not found; upstream changed."
        }
        $advanceReplacement = "        next_t = self.t + self.cutechess.games  # MANTA_TRANSACTIONAL_STEP_V1: commit after completed update`n" +
            "        it = next_t / self.cutechess.games  # MANTA_SCHEDULE_FIX_V1: Spall decay per-iteration; t/state.json stay in games"
        $s = [regex]::Replace($s, $advanceAnchor, $advanceReplacement)

        $commitAnchor = '(?m)^            param\.update\(-param_grad \* a_t \* param\.step\)\r?\n\r?\n    @property\r?$'
        if (-not [regex]::IsMatch($s, $commitAnchor)) {
            throw "weather-factory/spsa.py transactional-step commit anchor not found; upstream changed."
        }
        $commitReplacement = "            param.update(-param_grad * a_t * param.step)`n`n        self.t = next_t`n`n    @property"
        $s = [regex]::Replace($s, $commitAnchor, $commitReplacement)
        Set-Content -Path $wfSpsa -Value $s -Encoding utf8
    }

    $s = Get-Content $wfSpsa -Raw
    if ($s -notmatch 'MANTA_TRANSACTIONAL_STEP_V2') {
        $updateAnchor = '(?m)^        for param, delta, param in zip\(self\.uci_params, self\.delta, self\.uci_params\):\r?\n            param_grad = gradient / \(delta \* c_t\)\r?\n            param\.update\(-param_grad \* a_t \* param\.step\)\r?\n\r?\n        self\.t = next_t\r?$'
        if (-not [regex]::IsMatch($s, $updateAnchor)) {
            throw "weather-factory/spsa.py rollback anchor not found; upstream changed."
        }
        $updateReplacement = @'
        old_values = [param.value for param in self.uci_params]
        try:
            for param, delta in zip(self.uci_params, self.delta):
                param_grad = gradient / (delta * c_t)
                param.update(-param_grad * a_t * param.step)
        except BaseException:
            for param, old_value in zip(self.uci_params, old_values):
                param.value = old_value
            raise

        self.t = next_t  # MANTA_TRANSACTIONAL_STEP_V2: params and counter commit together
'@
        $s = [regex]::Replace($s, $updateAnchor, $updateReplacement)
        Set-Content -Path $wfSpsa -Value $s -Encoding utf8
    }

    if ((Get-Content $wfSpsa -Raw) -match 'MANTA_TRANSACTIONAL_STEP_V2') {
        python -m py_compile $wfSpsa
        if ($LASTEXITCODE -ne 0) {
            throw "weather-factory transactional-step patch failed Python syntax validation: $wfSpsa"
        }
        Write-Host "  weather-factory transactional SPSA step verified."
    } else {
        throw "weather-factory transactional SPSA V2 marker missing after patch."
    }
}

# PATCH 5 — ITERATION TARGET. weather-factory's main.py loops forever
# (`while True:`), so a target iteration count exists only in the operator's
# head — unworkable for multi-thousand-iteration tunes that always span several
# sessions. Patch it to stop cleanly at $env:MANTA_MAX_ITERS (0/unset =
# unbounded), and guard the finally-block rate prints against a zero-length
# session (resuming an already-complete run would otherwise ZeroDivisionError
# after saving).
$wfMain = Join-Path $wfDir "main.py"
if (Test-Path $wfMain) {
    $m = Get-Content $wfMain -Raw
    if ($m -match 'MANTA_MAX_ITERS_V1') {
        Write-Host "  weather-factory main.py iteration-target patch already present."
    } else {
        $anchor = '(?m)^(    try:\r?\n)(        while True:\r?\n)(            start = time\.time\(\))'
        if (-not [regex]::IsMatch($m, $anchor)) {
            throw "weather-factory/main.py loop anchor not found; upstream changed."
        }
        $m = [regex]::Replace($m, '(?m)^import dataclasses', "import dataclasses`nimport os")
        $repl = "    max_iters = int(os.environ.get('MANTA_MAX_ITERS', '0'))  # MANTA_MAX_ITERS_V1`n" +
                "    if max_iters:`n        print(f'Target: {max_iters} iterations (set MANTA_MAX_ITERS=0 to run unbounded).')`n" +
                '$1$2' +
                "            if max_iters and spsa.t / cutechess.games >= max_iters:`n" +
                "                print(f'Reached target {max_iters} iterations - stopping cleanly.')`n" +
                "                break`n" + '$3'
        $m = [regex]::Replace($m, $anchor, $repl)
        $m = $m.Replace('(spsa.t - start_t)', 'max(1, spsa.t - start_t)')
        Set-Content -Path $wfMain -Value $m -Encoding utf8

        python -m py_compile $wfMain
        if ($LASTEXITCODE -ne 0) {
            throw "weather-factory main.py patch failed Python syntax validation: $wfMain"
        }
        Write-Host "  weather-factory main.py iteration-target patch and Python syntax verified."
    }
}

# PATCH 6 — OPTION-NAME QUOTING. Manta-specific, and not present in Rarog's
# copy. weather-factory builds its runner command as one STRING and launches it
# with `Popen(cmd.split())`, a bare whitespace split. Rarog's knobs are all
# single-word (TmOptScale), so it never noticed; Manta's option registry uses
# spaced display names (`Move Overhead`, `Clear Hash`, docs/UCI.md §7), and
# `option.Move Overhead=25` splits into two argv entries — fastchess then sees a
# malformed option plus a stray token. Quote each option argument and split with
# shlex so a spaced name survives to the engine intact.
if ((Test-Path $wfCute) -and (Test-Path $wfSpsa)) {
    $c = Get-Content $wfCute -Raw
    $s = Get-Content $wfSpsa -Raw
    if (($c -match 'MANTA_OPTION_QUOTING_V1') -and ($s -match 'MANTA_OPTION_QUOTING_V1')) {
        Write-Host "  weather-factory option-name quoting already present."
    } else {
        $importAnchor = 'from subprocess import PIPE, Popen'
        $splitAnchor  = 'cutechess = Popen(cmd.split(), stdout=PIPE)'
        $fixedAnchor  = "f'option.{name}={value}'"
        $uciAnchor    = 'return f"option.{self.name}={self.get()}"'
        foreach ($probe in @(
            @($c, $importAnchor, 'cutechess.py subprocess import'),
            @($c, $splitAnchor,  'cutechess.py Popen split'),
            @($c, $fixedAnchor,  'cutechess.py fixed-option formatting'),
            @($s, $uciAnchor,    'spsa.py as_uci formatting'))) {
            if (-not $probe[0].Contains($probe[1])) {
                throw "weather-factory $($probe[2]) anchor not found; upstream changed."
            }
        }

        $c = $c.Replace($importAnchor, "$importAnchor`nimport shlex  # MANTA_OPTION_QUOTING_V1")
        $c = $c.Replace($splitAnchor, 'cutechess = Popen(shlex.split(cmd), stdout=PIPE)  # MANTA_OPTION_QUOTING_V1')
        $c = $c.Replace($fixedAnchor, "f'`"option.{name}={value}`"'")
        Set-Content -Path $wfCute -Value $c -Encoding utf8

        $s = $s.Replace($uciAnchor, "return f'`"option.{self.name}={self.get()}`"'  # MANTA_OPTION_QUOTING_V1")
        Set-Content -Path $wfSpsa -Value $s -Encoding utf8

        foreach ($file in @($wfCute, $wfSpsa)) {
            python -m py_compile $file
            if ($LASTEXITCODE -ne 0) {
                throw "weather-factory option-quoting patch failed Python syntax validation: $file"
            }
        }
        Write-Host "  weather-factory option-name quoting and Python syntax verified."
    }
}

# PATCH 7 — FAIL-CLOSED MATCHES AND CONTROLLER MARGIN. The original runner
# used `-recover` and returned a score even after a time loss or connection
# stall, so MAN-T02 committed contaminated gradients. Match Manta's qualified
# fastchess profile with a 20 ms controller margin and reject every incomplete,
# anomalous or nonzero-exit mini-match before SpsaTuner can commit its update.
if (Test-Path $wfCute) {
    $c = Get-Content $wfCute -Raw
    if ($c -notmatch 'MANTA_TIME_MARGIN_PATCH_V1') {
        $signatureAnchor = '        fixed_options: dict | None = None'
        $fieldAnchor = '        self.fixed_options = fixed_options or {}  # MANTA_FIXED_OPTIONS_V1'
        $timeAnchor = '            f"-each tc={self.tc}+{self.inc} "'
        foreach ($probe in @($signatureAnchor, $fieldAnchor, $timeAnchor)) {
            if (-not $c.Contains($probe)) {
                throw "weather-factory/cutechess.py time-margin anchor not found; upstream changed."
            }
        }
        $c = $c.Replace($signatureAnchor,
            $signatureAnchor + ",`n        time_margin: int = 20")
        $c = $c.Replace($fieldAnchor,
            $fieldAnchor + "`n        self.time_margin = time_margin")
        $c = $c.Replace($timeAnchor,
            '            f"-each tc={self.tc}+{self.inc} timemargin={self.time_margin} "  # MANTA_TIME_MARGIN_PATCH_V1')
    }

    if ($c -notmatch 'MANTA_FAIL_CLOSED_MATCH_V1') {
        $stateAnchor = @'
        score = [0, 0, 0]
        elo_diff = 0.0
'@
        $loopAnchor = @'
            print(line)
            if not line:
                cutechess.wait()
                return MatchResult(*score, elo_diff)
'@
        if (-not ($c.Contains($stateAnchor) -and $c.Contains($loopAnchor))) {
            throw "weather-factory/cutechess.py fail-closed anchors not found; upstream changed."
        }
        $stateReplacement = @'
        score = [0, 0, 0]
        elo_diff = 0.0
        finished_match = False
'@
        $loopReplacement = @'
            print(line)
            if not line:
                return_code = cutechess.wait()
                if return_code != 0:
                    raise RuntimeError(f"fastchess exited with code {return_code}")
                if not finished_match or sum(score) != self.games:
                    raise RuntimeError(
                        f"fastchess match incomplete: finished={finished_match}, "
                        f"scored={sum(score)}/{self.games}"
                    )
                return MatchResult(*score, elo_diff)

            lower_line = line.lower()
            fault_markers = (  # MANTA_FAIL_CLOSED_MATCH_V1
                "loses on time", "connection stalls", "not responsive",
                "disconnect", "illegal move", "crash", "forfeit",
                "failed to set cpu affinity", "no cores available",
            )
            if any(marker in lower_line for marker in fault_markers):
                if cutechess.poll() is None:
                    cutechess.kill()
                cutechess.wait()
                raise RuntimeError(f"fastchess infrastructure/engine fault: {line}")
            if line == "Finished match":
                finished_match = True
'@
        $c = $c.Replace($stateAnchor, $stateReplacement)
        $c = $c.Replace($loopAnchor, $loopReplacement)
    }

    $c = $c -replace '(?m)^\s*"-recover "\r?\n', ''
    Set-Content -Path $wfCute -Value $c -Encoding utf8
    python -m py_compile $wfCute
    if ($LASTEXITCODE -ne 0) {
        throw "weather-factory fail-closed/time-margin patch failed Python syntax validation: $wfCute"
    }
    $verifiedCute = Get-Content $wfCute -Raw
    if ($verifiedCute -notmatch 'MANTA_TIME_MARGIN_PATCH_V1' -or
        $verifiedCute -notmatch 'MANTA_FAIL_CLOSED_MATCH_V1' -or
        $verifiedCute -match '"-recover "') {
        throw "weather-factory fail-closed/time-margin patch is incomplete."
    }
    Write-Host "  weather-factory 20 ms margin and fail-closed mini-match verified."
}

# PATCH 8 — TIME-LOSS OUTCOME POLICY. A completed time forfeit is an engine
# fault for ordinary search/eval tuning, but is part of the objective when the
# perturbed parameters themselves allocate time. Keep strict behavior as the
# default and let only an explicitly configured clock tune score such games.
if (Test-Path $wfCute) {
    $c = Get-Content $wfCute -Raw
    if ($c -notmatch 'MANTA_TIME_LOSS_POLICY_V1') {
        $signatureAnchor = '        time_margin: int = 20'
        $fieldAnchor = '        self.time_margin = time_margin'
        $faultAnchor = @'
            fault_markers = (  # MANTA_FAIL_CLOSED_MATCH_V1
                "loses on time", "connection stalls", "not responsive",
                "disconnect", "illegal move", "crash", "forfeit",
                "failed to set cpu affinity", "no cores available",
            )
            if any(marker in lower_line for marker in fault_markers):
'@
        foreach ($probe in @($signatureAnchor, $fieldAnchor, $faultAnchor)) {
            if (-not $c.Contains($probe)) {
                throw "weather-factory/cutechess.py time-loss-policy anchor not found; upstream changed."
            }
        }
        $c = $c.Replace($signatureAnchor,
            $signatureAnchor + ",`n        score_time_losses: bool = False")
        $c = $c.Replace($fieldAnchor,
            $fieldAnchor + "`n        self.score_time_losses = score_time_losses  # MANTA_TIME_LOSS_POLICY_V1")
        $faultReplacement = @'
            time_fault_markers = ("loses on time", "no output from")
            fault_markers = (  # MANTA_FAIL_CLOSED_MATCH_V1
                "connection stalls", "not responsive", "disconnect",
                "illegal move", "crash", "forfeit",
                "failed to set cpu affinity", "no cores available",
            )
            rejected_time_fault = (
                not self.score_time_losses
                and any(marker in lower_line for marker in time_fault_markers)
            )
            if rejected_time_fault or any(marker in lower_line for marker in fault_markers):
'@
        $c = $c.Replace($faultAnchor, $faultReplacement)
        Set-Content -Path $wfCute -Value $c -Encoding utf8
    }
    python -m py_compile $wfCute
    if ($LASTEXITCODE -ne 0) {
        throw "weather-factory time-loss-policy patch failed Python syntax validation: $wfCute"
    }
    if ((Get-Content $wfCute -Raw) -notmatch 'MANTA_TIME_LOSS_POLICY_V1') {
        throw "weather-factory time-loss-policy patch is incomplete."
    }
    Write-Host "  weather-factory tune-specific time-loss policy verified."
}

python (Join-Path $PSScriptRoot "spsa_harness_test.py")
if ($LASTEXITCODE -ne 0) {
    throw "weather-factory SPSA harness self-test failed."
}

Write-Host "Installing matplotlib (weather-factory dependency)..."
pip install matplotlib --quiet
if ($LASTEXITCODE -ne 0) { Write-Warning "pip install matplotlib failed; run manually if needed." }

Write-Host ""
Write-Host "============================================================"
Write-Host "  Toolchain setup complete."
Write-Host ""
Write-Host "  Next steps:"
Write-Host "    1. Build a test binary:"
Write-Host "         ./tools/build_test.ps1 -Suffix head"
Write-Host "    2. SPRT two binaries:"
Write-Host "         ./tools/sprt.ps1 -EngineA tools\test_engines\manta-cand.exe ``"
Write-Host "                          -EngineB tools\test_engines\manta-head.exe"
Write-Host "    3. Configure and start SPSA (setup + launch, one command):"
Write-Host "         ./tools/spsa.ps1 -ConfigGroup <group> -EngineSuffix head"
Write-Host "============================================================"
