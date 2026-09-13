# Shared preflight for clock-based fastchess harnesses.
#
# Ported from Rarog's tools/harness_common.ps1 so that Manta's SPRT/SPSA
# instrument is the SAME instrument: identical physical-core discovery,
# identical affinity contract.
#
# Manta runs NO adjudication anywhere. Only the rules of chess end a game:
# checkmate, stalemate, the fifty-move rule, threefold repetition and
# insufficient material. There is no resignation threshold, no draw-after-N-
# moves rule and no move cap. An adjudicator is a second, unvalidated engine
# sitting in judgment on the one being measured: it truncates exactly the
# conversion, fortress and mating phases where engines differ most, and it
# prices those phases by the same evaluation whose quality is under test.
# Verdicts produced before this change were measured with `strength-v2`
# adjudication and are NOT directly comparable with verdicts produced after it.

$script:MinimumAffinityFastchessVersion = [version]"1.7.0"
$script:HarnessIsWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT

# One named source of truth for how a measured game ends. The profile carries
# no thresholds because there are none: every caller passes an empty argument
# list to the runner and lets the rules of chess decide. The name is recorded
# in every manifest so a result can never be mistaken for an adjudicated one.
function Get-GameEndProfile {
    [pscustomobject]@{
        Name        = "natural-v1"
        Adjudicated = $false
        Description = "chess rules only: mate, stalemate, fifty-move, threefold, insufficient material"
    }
}

# Returns the runner arguments that configure game termination. Deliberately
# empty. It exists so a caller cannot quietly reintroduce `-resign`, `-draw`
# or `-maxmoves` without editing this contract.
function Get-GameEndArgs {
    @()
}

# Compare only the build dimensions that can introduce unrelated codegen
# differences. Candidate feature labels remain recorded in full manifests, but
# they are the intended subject of an A/B test and therefore are not themselves
# a flavor mismatch.
function Get-HarnessBuildContract {
    param([Parameter(Mandatory)][string]$Flavor)

    $match = [regex]::Match($Flavor, '^(?<target>native|portable)(?<pgo>-pgo)?(?:-|$)')
    if (-not $match.Success) {
        throw "Unrecognized engine build flavor '$Flavor'; expected native or portable, optionally with PGO."
    }
    "$($match.Groups['target'].Value)$(if ($match.Groups['pgo'].Success) { '-pgo' })"
}

# A completed clock loss is chess evidence only when the caller explicitly
# measures time management. Reconcile every reported timeout with a completed
# `Finished game ... loses on time` result; all other engine/protocol/placement
# faults remain fatal.
function Assert-StrengthMatchLog {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [switch]$ScoreCompletedTimeForfeits
    )

    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        throw "Match log not found: $LogPath"
    }

    $lines = @(Get-Content -LiteralPath $LogPath)
    $nonTimeFault = @($lines | Where-Object {
        $_ -match '(?i)(\bcrash(?:ed)?\b(?!:\s*0\b)|disconnect|illegal move|stalled\s*/\s*disconnected|connection stall|not responsive|no output from|failed to set cpu affinity|no cores available|\bforfeit\b)'
    })
    if ($nonTimeFault.Count -gt 0) {
        throw "Match contained an engine, protocol, affinity or infrastructure anomaly. See '$LogPath'."
    }

    $completedTimeLosses = @($lines | Where-Object {
        $_ -match '(?i)^\s*Finished game \d+ .*\{(?:White|Black) loses on time\}\s*$'
    }).Count
    $otherTimeLossLines = @($lines | Where-Object {
        ($_ -match '(?i)loses on time') -and
        ($_ -notmatch '(?i)^\s*Finished game \d+ .*\{(?:White|Black) loses on time\}\s*$')
    })

    $reportedTimeouts = 0
    $timeoutSummaries = @($lines | Where-Object { $_ -match '(?i)^\s*Timeouts:\s*(?<count>\d+)\s*$' })
    foreach ($line in $timeoutSummaries) {
        [void]($line -match '(?i)^\s*Timeouts:\s*(?<count>\d+)\s*$')
        $reportedTimeouts += [int]$Matches['count']
    }

    if (-not $ScoreCompletedTimeForfeits) {
        if ($completedTimeLosses -gt 0 -or $otherTimeLossLines.Count -gt 0 -or $reportedTimeouts -gt 0) {
            throw "Match contained a timeout and is invalid under the strict clock contract. See '$LogPath'."
        }
        return
    }

    if ($otherTimeLossLines.Count -gt 0 -or $reportedTimeouts -ne $completedTimeLosses) {
        throw "Match timeout accounting is incomplete: $completedTimeLosses completed time losses but $reportedTimeouts reported timeouts. See '$LogPath'."
    }
}

function Get-HarnessPhysicalCpus {
    if ($script:HarnessIsWindows) {
        if (-not ('MantaHarness.CpuTopology' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.InteropServices;

namespace MantaHarness {
    public sealed class CpuCore {
        public int Cpu { get; set; }
        public int EfficiencyClass { get; set; }
    }

    public static class CpuTopology {
        private const int RelationProcessorCore = 0;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetLogicalProcessorInformationEx(
            int relationship, IntPtr buffer, ref uint returnedLength);

        public static CpuCore[] PhysicalCpus() {
            uint length = 0;
            GetLogicalProcessorInformationEx(RelationProcessorCore, IntPtr.Zero, ref length);
            if (length == 0) throw new Win32Exception(Marshal.GetLastWin32Error());

            IntPtr buffer = Marshal.AllocHGlobal((int)length);
            try {
                if (!GetLogicalProcessorInformationEx(RelationProcessorCore, buffer, ref length))
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                var result = new List<CpuCore>();
                int offset = 0;
                int groupAffinitySize = IntPtr.Size + 8;
                while (offset < length) {
                    IntPtr entry = IntPtr.Add(buffer, offset);
                    int relationship = Marshal.ReadInt32(entry, 0);
                    int size = Marshal.ReadInt32(entry, 4);
                    if (size <= 0 || offset + size > length)
                        throw new InvalidOperationException("Invalid Windows CPU-topology record.");

                    if (relationship == RelationProcessorCore) {
                        int efficiencyClass = Marshal.ReadByte(entry, 9);
                        int groupCount = (ushort)Marshal.ReadInt16(entry, 30);
                        var logical = new List<int>();
                        for (int groupIndex = 0; groupIndex < groupCount; ++groupIndex) {
                            int gaOffset = 32 + groupIndex * groupAffinitySize;
                            ulong mask = IntPtr.Size == 8
                                ? unchecked((ulong)Marshal.ReadInt64(entry, gaOffset))
                                : unchecked((uint)Marshal.ReadInt32(entry, gaOffset));
                            int group = (ushort)Marshal.ReadInt16(entry, gaOffset + IntPtr.Size);
                            for (int bit = 0; bit < IntPtr.Size * 8; ++bit)
                                if ((mask & (1UL << bit)) != 0) logical.Add(group * 64 + bit);
                        }
                        if (logical.Count == 0)
                            throw new InvalidOperationException("A physical core has no logical processors.");
                        result.Add(new CpuCore {
                            Cpu = logical.Min(),
                            EfficiencyClass = efficiencyClass
                        });
                    }
                    offset += size;
                }

                return result
                    .OrderByDescending(c => c.EfficiencyClass)
                    .ThenBy(c => c.Cpu)
                    .ToArray();
            } finally {
                Marshal.FreeHGlobal(buffer);
            }
        }
    }
}
'@
        }
        return [MantaHarness.CpuTopology]::PhysicalCpus()
    }

    if (Get-Command lscpu -ErrorAction SilentlyContinue) {
        $seen = @{}
        $cores = foreach ($line in (& lscpu '-p=CPU,CORE,SOCKET' 2>$null)) {
            if (-not $line -or $line.StartsWith('#')) { continue }
            $cpu, $core, $socket = $line.Split(',')
            $key = "$socket,$core"
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                [pscustomobject]@{ Cpu = [int]$cpu; EfficiencyClass = 0 }
            }
        }
        return @($cores | Sort-Object Cpu)
    }

    return @(0..([Environment]::ProcessorCount - 1) |
        ForEach-Object { [pscustomobject]@{ Cpu = $_; EfficiencyClass = 0 } })
}

function Get-FastchessVersion {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { throw "fastchess not found: $Path" }

    $line = (& $Path --version 2>&1 | Select-Object -First 1)
    if (-not $line) { throw "Could not query fastchess version at '$Path'." }

    $match = [regex]::Match("$line", '(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)')
    if (-not $match.Success) { throw "Unrecognized fastchess version string: '$line'." }

    [pscustomobject]@{
        Text    = "$line".Trim()
        Version = [version]::new(
            [int]$match.Groups['major'].Value,
            [int]$match.Groups['minor'].Value,
            [int]$match.Groups['patch'].Value)
    }
}

function Assert-AffinityFastchess {
    param([Parameter(Mandatory)][string]$Path)

    $info = Get-FastchessVersion -Path $Path
    if ($script:HarnessIsWindows -and $info.Version -lt $script:MinimumAffinityFastchessVersion) {
        throw "fastchess $($info.Version) is too old for reliable Windows affinity. " +
              "Version 1.7.0 contains the process-affinity fix; run tools/setup_tools.ps1 " +
              "to install the pinned runner. Found: $($info.Text)"
    }
    $info
}

# Manta-specific: the option registry is staged by phase (docs/UCI.md §7), so a
# harness that blindly sends `option.Threads` to a build that has not activated
# SMP produces one `info string unknown option` per game and silently measures
# something other than what the manifest claims. Ask the engine what it
# actually advertises instead of assuming.
function Get-EngineUciOptions {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$TimeoutMs = 15000,
        [switch]$Detailed
    )

    if (-not (Test-Path -LiteralPath $Path)) { throw "Engine not found: $Path" }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = (Resolve-Path -LiteralPath $Path).Path
    $psi.WorkingDirectory       = (Split-Path -Parent (Resolve-Path -LiteralPath $Path).Path)
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false

    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $proc.StandardInput.WriteLine("uci")
        $proc.StandardInput.WriteLine("quit")
        $proc.StandardInput.Close()
        if (-not $proc.WaitForExit($TimeoutMs)) {
            throw "Engine '$Path' did not answer 'uci' within ${TimeoutMs} ms."
        }
        $text = $stdout.Result
    } finally {
        if (-not $proc.HasExited) { $proc.Kill($true) }
        $proc.Dispose()
    }

    if ($text -notmatch '(?m)^\s*uciok\s*$') {
        throw "Engine '$Path' did not emit 'uciok'; it is not a working UCI engine."
    }

    $options = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($text -split "`r?`n")) {
        $m = [regex]::Match($line, '^\s*option\s+name\s+(?<name>.+?)\s+type\s+(?<type>\S+)(?<tail>.*)$')
        if (-not $m.Success) { continue }
        $tail = $m.Groups['tail'].Value
        $defaultMatch = [regex]::Match($tail, '(?:^|\s)default\s+(?<value>\S+)')
        $minMatch = [regex]::Match($tail, '(?:^|\s)min\s+(?<value>-?\d+)')
        $maxMatch = [regex]::Match($tail, '(?:^|\s)max\s+(?<value>-?\d+)')
        $options.Add([pscustomobject]@{
            Name = $m.Groups['name'].Value.Trim()
            Type = $m.Groups['type'].Value
            Default = if ($defaultMatch.Success) { $defaultMatch.Groups['value'].Value } else { $null }
            Min = if ($minMatch.Success) { [int64]$minMatch.Groups['value'].Value } else { $null }
            Max = if ($maxMatch.Success) { [int64]$maxMatch.Groups['value'].Value } else { $null }
            Raw = $line.Trim()
        })
    }
    if ($Detailed) { $options.ToArray(); return }
    # Emitted unrolled, not as a unary-comma array: the unary comma survives a
    # direct assignment but collapses to a single nested element when a caller
    # writes `@(Get-EngineUciOptions ...)`, which is how every caller uses it.
    # Callers wrap in @() to normalise the zero/one-option cases.
    $options.Name
}

function Test-EngineSupportsOption {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    # docs/UCI.md §1: option names match case-insensitively after collapsing
    # internal separator runs, so compare the same way ("Move  Overhead" is
    # "Move Overhead").
    $normalize = { param($s) ($s -replace '\s+', ' ').Trim().ToLowerInvariant() }
    $target = & $normalize $Name
    foreach ($advertised in (Get-EngineUciOptions -Path $Path)) {
        if ((& $normalize $advertised) -eq $target) { return $true }
    }
    $false
}

function Get-PhysicalCoreCount {
    $count = @(Get-HarnessPhysicalCpus).Count
    if (-not $count -or $count -lt 1) { $count = 1 }
    [int]$count
}

function Resolve-HarnessConcurrency {
    # `ThreadsPerGame` generalises this past the 1-thread assumption. Each
    # concurrent game needs `ThreadsPerGame` physical cores, so the core budget
    # is divided, not handed out one game per core. At Threads=1 the arithmetic
    # is identical, so 1-thread runs are unaffected.
    param([int]$Requested, [int]$ReservePhysicalCores = 2, [int]$ThreadsPerGame = 1)

    if ($ThreadsPerGame -lt 1) { throw "ThreadsPerGame must be >= 1 (got $ThreadsPerGame)." }
    $physical = Get-PhysicalCoreCount
    $budget = [Math]::Max(1, $physical - $ReservePhysicalCores)
    $recommended = [Math]::Max(1, [Math]::Floor($budget / $ThreadsPerGame))
    $resolved = if ($Requested -gt 0) { $Requested } else { $recommended }
    $needed = $resolved * $ThreadsPerGame
    if ($needed -gt $physical) {
        throw ("Concurrency $resolved x Threads $ThreadsPerGame = $needed cores, " +
               "which exceeds the detected $physical physical cores.")
    }
    [pscustomobject]@{
        Concurrency    = [int]$resolved
        PhysicalCores  = [int]$physical
        CoresUsed      = [int]$needed
        ThreadsPerGame = [int]$ThreadsPerGame
        AutoSelected   = ($Requested -le 0)
    }
}

function Get-HarnessAffinityCpuList {
    # The pinned set must cover EVERY core the games will use, i.e.
    # Concurrency x ThreadsPerGame — not one core per game. Under-sizing this
    # list silently oversubscribes cores and reintroduces exactly the hidden
    # per-run offset the affinity pinning exists to remove.
    param([Parameter(Mandatory)][int]$Concurrency, [int]$ThreadsPerGame = 1)

    $cores = @(Get-HarnessPhysicalCpus)
    $needed = $Concurrency * $ThreadsPerGame
    if ($needed -gt $cores.Count) {
        throw "Concurrency $Concurrency x Threads $ThreadsPerGame = $needed exceeds $($cores.Count) physical cores."
    }
    (($cores | Select-Object -First $needed).Cpu -join ',')
}

function New-HarnessSeed {
    param([int]$Requested)
    if ($Requested -ne 0) { return $Requested }
    Get-Random -Minimum 1 -Maximum ([int]::MaxValue)
}

function Get-HarnessSha256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Assert-NoAffinityFailure {
    param([Parameter(Mandatory)][string]$LogPath)

    $failure = Select-String -LiteralPath $LogPath `
        -Pattern '(?i)(failed to set cpu affinity|no cores available)' `
        -ErrorAction SilentlyContinue
    if ($failure) {
        throw "fastchess reported an affinity failure; the match is invalid. See '$LogPath'."
    }
}

# Manta's bench holds the job until it completes, and both `quit` and EOF
# cancel it (docs/UCI.md 4.2). Piping "bench`nquit" therefore returns nothing.
# Feed `bench` and keep stdin OPEN until the Rarog-compatible summary arrives. Shared so the
# sidecar verifier and the search profiler drive the engine identically.
function Invoke-MantaBench {
    param(
        [Parameter(Mandatory)][string]$BinaryPath,
        [Parameter(Mandatory)][int]$Depth,
        [int]$TimeoutMs = 600000
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $BinaryPath
    $psi.WorkingDirectory       = (Split-Path -Parent $BinaryPath)
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false

    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        $proc.StandardInput.WriteLine("bench $Depth")
        $deadline = [datetime]::UtcNow.AddMilliseconds($TimeoutMs)
        $summaryLines = [ordered]@{}
        while ([datetime]::UtcNow -lt $deadline) {
            $line = $proc.StandardOutput.ReadLine()
            if ($null -eq $line) { break }
            if ($line -match '^Nodes searched\s*:') { $summaryLines.nodes = $line }
            elseif ($line -match '^Geomean EBF\s*:') { $summaryLines.ebf = $line }
            elseif ($line -match '^Total time \(ms\)\s*:') { $summaryLines.time = $line }
            elseif ($line -match '^Nodes/second\s*:') {
                $summaryLines.nps = $line
                $proc.StandardInput.WriteLine("quit")
                $proc.StandardInput.Close()
                $proc.WaitForExit(10000) | Out-Null
                if (-not $summaryLines.nodes -or -not $summaryLines.ebf -or -not $summaryLines.time) {
                    throw "Incomplete bench summary from $BinaryPath."
                }
                return ($summaryLines.Values -join '; ')
            }
        }
        throw "Timed out waiting for the 'bench $Depth' summary from $BinaryPath."
    } finally {
        if (-not $proc.HasExited) { $proc.Kill($true) }
        $proc.Dispose()
    }
}
