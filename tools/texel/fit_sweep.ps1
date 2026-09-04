#!/usr/bin/env pwsh
# Step-5.3.16 offline fit exploration sweep.
#
# Answers one question: is the accepted constrained vector a converged optimum,
# or did the registered run simply run out of travel? The accepted run used
# lr 0.3 with one full-batch Adam step per epoch, so its reachable displacement
# was about lr x epochs = 11 and its observed maximum was 7. This sweep widens
# lr and the epoch budget and reports whether validation loss falls further.
#
# The frozen test is NOT read. Every configuration passes the validation set as
# --test-prefix, so tools/texel/out/hce-v1/test.* is never opened and keeps its
# one-time-opened role for the final decision. Read results on validation only:
# the "frozen_test" block in each sweep report is a duplicate of validation and
# is meaningless here.
#
# Read-only against the corpus. Writes only under tools/texel/out/diag.
# Run on an idle host with no other timed job.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root

$python = Join-Path $root ".venv\Scripts\python.exe"
$data   = Join-Path $root "tools\texel\out\hce-v1"
$out    = Join-Path $root "tools\texel\out\diag"
$fit    = Join-Path $root "tools\texel\fit.py"

foreach ($required in @($python, $fit, "$data\train.samples.bin", "$data\validation.samples.bin", "$data\current.tsv")) {
    if (-not (Test-Path -LiteralPath $required)) { throw "missing prerequisite: $required" }
}
New-Item -ItemType Directory -Force -Path $out | Out-Null

# name, learning-rate, lr-decay, epochs, patience, l2, min-train-support
#
# The accepted run is lr 0.3 undecayed, which travels about lr x epochs and
# stopped at 7. Each annealed configuration below can travel lr/(1-decay):
# roughly 1,000 at lr 3.0 decay 0.997 and 6,000 at lr 30 decay 0.995, while
# still refining to a sub-integer step before patience stops it.
$configs = @(
    @("control-lr0.3",          0.3, 1.000, 1200, 150, 1e-6, 300),
    @("lr1.0-flat",             1.0, 1.000, 1200, 150, 1e-6, 300),
    @("lr3.0-flat",             3.0, 1.000, 1200, 150, 1e-6, 300),
    @("lr3.0-anneal",           3.0, 0.997, 1200, 150, 1e-6, 300),
    @("lr10-anneal",           10.0, 0.997, 1200, 150, 1e-6, 300),
    @("lr30-anneal",           30.0, 0.995, 1200, 150, 1e-6, 300),
    @("lr3.0-anneal-l2-1e-4",   3.0, 0.997, 1200, 150, 1e-4, 300),
    @("lr3.0-anneal-sup100",    3.0, 0.997, 1200, 150, 1e-6, 100),

    # Stage two. The stage-one high-rate runs never settled: lr10 started worse
    # than the unfitted base at 0.1129, dipped to 0.1028 at epoch 10 and then
    # climbed back to 0.1037, so its reported minimum is a point the trajectory
    # passed through. These decays collapse the rate fast enough that a run has
    # to converge, which is the only way to tell a real basin from a flythrough.
    @("conv-lr3-d95",           3.0, 0.950, 1200, 200, 1e-6, 300),
    @("conv-lr10-d95",         10.0, 0.950, 1200, 200, 1e-6, 300),
    @("conv-lr10-d97",         10.0, 0.970, 1200, 200, 1e-6, 300),
    @("conv-lr30-d93",         30.0, 0.930, 1200, 200, 1e-6, 300),
    @("conv-lr3-d99",           3.0, 0.990, 1200, 200, 1e-6, 300),
    @("conv-lr1-d99",           1.0, 0.990, 1200, 200, 1e-6, 300)
)

$started = Get-Date
Write-Host "sweep started $($started.ToString('u'))  configurations: $($configs.Count)"
Write-Host "frozen test is sealed: --test-prefix points at validation`n"

foreach ($config in $configs) {
    $name, $lr, $decay, $epochs, $patience, $l2, $support = $config
    $vector = Join-Path $out "$name.tsv"
    $log    = Join-Path $out "$name.log"
    if (Test-Path -LiteralPath $vector) { Write-Host "skip $name (already present)"; continue }

    Write-Host "=== $name : lr=$lr decay=$decay epochs=$epochs patience=$patience l2=$l2 support=$support"
    $begin = Get-Date
    try {
        & $python $fit `
            --vector "$data\current.tsv" `
            --train-prefix "$data\train" `
            --validation-prefix "$data\validation" `
            --test-prefix "$data\validation" `
            --out "$vector" `
            --epochs $epochs --learning-rate $lr --lr-decay $decay --l2 $l2 --patience $patience `
            --batch-samples 32768 --jobs 16 `
            --min-train-support $support --min-validation-support 50 `
            --max-delta 512 2>&1 | Tee-Object -FilePath $log
    } catch {
        # A configuration that fails its own improvement check is a result, not
        # a reason to abandon the remaining configurations.
        Write-Host "  $name did not produce an accepted vector: $_"
    }
    Write-Host "  elapsed $([int]((Get-Date) - $begin).TotalSeconds)s`n"
}

Write-Host "sweep finished in $([int]((Get-Date) - $started).TotalMinutes) minutes`n"
& $python (Join-Path $root "tools\texel\sweep_report.py") $out
