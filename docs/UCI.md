# Manta UCI behavioral contract

This document is the normative text-boundary contract for Manta. It freezes
observable behavior before the protocol shell, chess position, and search are
implemented. The canonical process examples live in the
[UCI transcript corpus](../tests/uci/README.md).

Later phases may activate a transcript when its required capability exists,
but they may not silently change an expected line, ordering rule, state
transition, or failure policy. A deliberate change updates this contract, its
transcripts, `REQUIREMENTS.md`, and the owning plan entry together.

## 1. Text framing and bounds

- Input accepts LF and CRLF. One command occupies one complete line.
- ASCII space and horizontal tab separate tokens. Leading and trailing
  separators are ignored. An empty or separator-only line is ignored without
  output.
- Command keywords and `go` keywords are lowercase and case-sensitive. UCI
  option names are matched case-insensitively in ASCII after collapsing
  internal separator runs to one space.
- Protocol keywords, moves, FEN fields, and numeric values are ASCII. Free-form
  option values are valid UTF-8 without NUL bytes and undergo checked native
  path conversion when applicable; invalid text rejects the complete command.
- One input line is limited by `RES-001`. An oversized line is drained through
  its line ending, rejected once with
  `info string invalid input: line exceeds 65536 bytes`, and cannot prefix a
  second command.
- Every stdout record is one complete, LF-terminated line. The presenter is the
  only stdout writer and flushes each published record before the next one.
- While the protocol session is active, stdout contains only UCI records and
  the explicitly specified `bench` and `go perft` records. Incidental logging,
  stack traces, and fatal details go to stderr.
- Parsing is bounded and transactional. No malformed command partially changes
  controller state.

## 2. Identity and startup

Immediately after successful process initialization, and before reading the
first command, Manta writes exactly one introduction line:

```text
Manta <version> by Miloslav Macurek
```

`<version>` is the authoritative build version; the first release is `1.0.0`. The
startup line is not repeated. Failure before successful initialization writes
only to stderr and exits non-zero.

Every accepted `uci` command emits a fresh handshake in this order:

```text
id name Manta <version>
id author Miloslav Macurek
<zero or more active option declarations>
uciok
```

Option declarations use the order in §7. Repeated `uci` commands are safe and
do not reset options, position, resources, or an active search.

## 3. Diagnostics

### 3.1 Unknown commands

A non-empty line whose first token is not a supported command emits exactly:

```text
info string unknown command "<token>" ignored
```

The command is otherwise ignored and the process remains responsive. This
diagnostic does not stop a search or alter any state.

For diagnostics, a token is rendered with printable ASCII unchanged except
that `\` and `"` become `\\` and `\"`. Other bytes become uppercase `\xHH`.
The rendered token is capped at 256 bytes; truncation replaces the final three
bytes with `...`. Consequently hostile input cannot create unbounded output or
inject a second line.

### 3.2 Reserved but inactive commands

A command frozen by this contract but not activated in the current development
phase emits exactly:

```text
info string command "<command>" is not available yet
```

The command is ignored without partial behavior or state changes. This
temporary distinction keeps staged commands such as `position` and `go` from
being misreported as arbitrary input; it disappears for each command when its
owning phase activates the complete behavior.

### 3.3 Malformed supported commands

A known command with invalid syntax, an unknown sub-token, a missing value, an
out-of-range value, or a contradictory mode emits exactly one bounded line:

```text
info string invalid <command>: <reason>
```

Reasons are stable, short ASCII phrases owned by the command specification.
The rejected command has no state effect. A rejected search-form `go` does not
create a search epoch and does not emit `bestmove`.

An unknown option is distinct from an unknown command:

```text
info string unknown option "<normalized-name>" ignored
```

A syntactically valid command whose external operation fails emits:

```text
info string failed <command>: <reason>
```

This is not a parse rejection. Its transactional effect is defined by the
owning resource or file contract.

## 4. Session states and ordering

The observable session states are:

| State | Meaning |
|---|---|
| Idle | No search or diagnostic job is active. |
| Searching | A normal search owns the active epoch. |
| Pondering | A ponder search is running but may not publish `bestmove`. |
| Ponder complete | Ponder work finished; one result is retained pending `ponderhit` or `stop`. |
| Diagnostic | `go perft` or `bench` owns the engine job slot. |
| Closing | Shutdown was requested; no new command is accepted. |

Only the controller mints search epochs and owns transitions. Urgent
cancellation or ponder-hit state is published before its ordered command is
enqueued. The atomic targets only the epoch visible at receipt; the queued
command retains FIFO authority over any preceding replacement `go`. Stale urgent
signals carry an epoch and cannot affect a later search.

### 4.1 Barriers

`setoption`, `ucinewgame`, and `position` are ordered state barriers. Syntax and
ordinary values are validated before urgent control is published, so a
malformed barrier does not stop an active job. Position replacement is also
constructed and validated transactionally before commit. If an accepted
barrier arrives during search or diagnostic work, Manta requests cancellation,
finishes the active job's required publication exactly once, and joins its
owned workers before committing the prepared position or option value.

A resource-changing option follows the stricter ownership order in
`ARCHITECTURE.md`: validate syntax and range, stop and join workers, retain the
old generation, construct and validate the replacement while idle, swap only
on success, then destroy the old generation. A construction failure therefore
leaves the old resource and option value active, although the preceding search
has already completed.

A valid replacement search-form `go`, `go perft`, or `bench` behaves the same
way: the old job completes its required publication before the replacement
starts. A rejected replacement leaves the old job running. There is never more
than one active job.

`isready` acknowledges all earlier accepted barriers. With no pending barrier,
including during any active job, it replies promptly without stopping that
job.

### 4.2 Completion and shutdown

- Every accepted search-form `go` publishes exactly one `bestmove` unless
  `quit`, EOF, or fatal output closes the session first.
- `stop` requests urgent cancellation of the matching active job. A search
  publishes its one required `bestmove`; a diagnostic job publishes only its
  specified cancellation completion. Repeated or stale `stop` commands do not
  produce additional output.
- `quit` and EOF enter Closing, cancel the active job, discard queued jobs that
  have not started, join owned tasks, and exit successfully. They do not require
  a pending `bestmove` to be published.
- A failed or permanently blocked stdout closes presentation, cancels work, and
  cannot make shutdown unbounded.

## 5. Command matrix

| Command | Accepted form | Success output | State rule |
|---|---|---|---|
| `uci` | `uci` | Identity, active options, `uciok` | Safe in every non-closing state; no reset. |
| `debug` | `debug on`, `debug off` | None by itself | Adapter-local toggle; malformed values are rejected. |
| `isready` | `isready` | `readyok` | Prompt during search; waits for prior barriers. |
| `setoption` | `setoption name <name> [value <value>]` | None | Transactional ordered barrier. |
| `ucinewgame` | `ucinewgame` | None | Ordered barrier; clears game/search state, not user options. |
| `position` | `position startpos [moves ...]`, `position fen <six fields> [moves ...]` | None | Transactional ordered barrier. |
| `go` | Search form in §6 or diagnostic `go perft <depth>` | Search info and one `bestmove`, or perft records only | Replaces an active job in order. |
| `stop` | `stop` | Required search or diagnostic completion, if active | Urgent and epoch-tagged; otherwise no-op. |
| `ponderhit` | `ponderhit` | Retained or eventual `bestmove` when normal limits end | Valid only for matching ponder epoch; otherwise no-op. |
| `bench` | `bench [depth] [repeats]` | Rarog-compatible bench records and summary only | Diagnostic job; contract is in `PLAN.md` §4.2. |
| `quit` | `quit` | None required | Urgent bounded shutdown with exit code 0. |
| EOF | Input stream closes | None required | Same lifecycle as `quit`. |

Extra tokens on fixed-form commands are malformed. Successful `position`,
`setoption`, `ucinewgame`, `debug`, `stop`, `ponderhit`, and `quit` never emit
acknowledgement chatter.

## 6. Search and diagnostic `go`

### 6.1 Parsing

Supported search keywords are `wtime`, `btime`, `winc`, `binc`, `movestogo`,
`movetime`, `depth`, `nodes`, `mate`, `infinite`, `ponder`, and `searchmoves`.
All numeric text is decimal and parsed through an unsigned 64-bit intermediate.
Signs, overflow, missing values, duplicate keywords, and unknown tokens reject
the entire command.

`searchmoves` consumes move tokens until the next recognized keyword or end of
line. It must contain at least one unique legal root move. Duplicate moves are
collapsed while preserving their first occurrence. Any malformed or illegal
move rejects the whole `go`; an empty legal root set is not silently broadened.
More than 256 unique moves is rejected under `RES-004`.

Requested `depth` is normalized to at most `MAX_PLY - 1`. `nodes`, clocks, and
`movetime` retain unsigned 64-bit boundary values internally and are narrowed
only through checked policy conversions. Positive `mate N` targets mate within
`N` moves and shares the authoritative depth ceiling.

### 6.2 Modes and combinations

`go perft <depth>` is a mutually exclusive diagnostic form. No other token may
accompany it. Depth zero is valid and returns one leaf. Perft remains
interruptible by `stop`, replacement, `quit`, and EOF, but emits no
`bestmove`.

Search-form modes are:

| Mode | Contract |
|---|---|
| Fixed move time | `movetime` supplies the time budget and cannot coexist with clock fields or `movestogo`. `depth`, `nodes`, `mate`, and `searchmoves` may add earlier hard limits. |
| Clock | The side-to-move clock is required. Missing increments mean zero; missing `movestogo` means sudden death. `depth`, `nodes`, `mate`, and `searchmoves` may add earlier limits. |
| Fixed work | At least one of `depth`, `nodes`, or `mate`, optionally with `searchmoves`. If several are present, the first satisfied limit ends search. |
| Infinite | `infinite`, optionally with `searchmoves`, runs until explicit control. It cannot coexist with another limit or `ponder`. |
| Ponder | `ponder` uses supplied clock data and may include fixed-work limits and `searchmoves`. Completion is retained until `ponderhit` or `stop`. |

`go` without a usable mode or limit is rejected with
`info string invalid go: no search limit`. Zero is valid for clocks and
increments, but `movetime`, `depth`, `nodes`, `mate`, and `movestogo` must be
positive.

Time accounting starts when the complete `go` line is received. `ponderhit`
does not restart elapsed time. A spent budget produces a legal deterministic
fallback rather than an illegal move or a time reset.

Internally, the matching ponder epoch latches the monotonic interval from `go`
receipt through `ponderhit` exactly once. The interval is diagnostic input for
the later integrated time policy; Step 6.0.4 does not alter the current soft or
hard deadline.

Ponder mode is accepted only while the `Ponder` option is `true`; otherwise the
command is rejected without affecting an active job.

An engine compiled with the default-off Step-6.3 integrated-time candidate
emits one bounded diagnostic immediately before `bestmove` for a timed search:

```text
info string time optimum_ms <u64> maximum_ms <u64> root <permille> stability <permille> score <permille> effort <permille> smp <permille> combined <permille> ponder_credit_ns <u64> helper_events <u64> helpers <u16> target_ns <u64> reason <tag> hard_overshoot_ns <u64>
```

This is a final worker-zero snapshot. It reports allocation and completed
evidence but cannot change the move, PV, stop decision or result owner. Normal
production builds do not emit this candidate diagnostic.

### 6.3 Perft output

Root moves are printed in ascending UCI text order:

```text
info string perft move <move> nodes <unsigned-nodes>
```

Completion is exactly:

```text
info string perft depth <depth> nodes <unsigned-total>
```

Depth zero has no root-move lines. Cancellation emits one completion line for
the fully completed work with an additional final field `cancelled true`.
Perft never emits search `info` or `bestmove` records.

### 6.4 Bench output

`bench` follows the versioned 40-position work contract in `PLAN.md` §4.2.
Arguments are positive decimal integers and requested depth shares the
authoritative depth ceiling. `manta-search-bench-v1` defaults to depth `6`;
its optional arguments are depth then whole-suite repeat count, matching Rarog.
Single-run output reports each position's completed depth, score, nodes, EBF,
elapsed milliseconds and NPS, followed by the same aggregate summary layout.
Repeats default to one and are capped at `16`; the deterministic bench keeps
its independent one-thread scope after SMP activation.
Bench does not consult the current
Hash or Threads options. Each repeat clears a private 16 MiB TT and ordering
history once, then shares those caches across the ordered positions. The
current game and options are unchanged; ordinary TT/history are clear after
completion.

A single repeat emits 40 ordered records:

```text
bench <index>/40  depth <depth>  score <score>  nodes <nodes>  ebf <ebf>  time <time>ms  nps <nps>
```

It then emits exactly:

```text
=========================
Nodes searched  : <nodes>
Geomean EBF     : <ebf>
Median nodes    : <nodes>
Top-pos share   : <percent>%  (<maximum> nodes)
Total time (ms) : <time>
Nodes/second    : <nps>
```

Multiple repeats omit position records, emit one compact line per run, then a
summary. `fingerprint_nodes` is the deterministic node total from run one:

```text
run <index>/<repeats>  nodes <nodes>  time <time>ms  nps <nps>
=========================
Nodes searched  : <fingerprint-nodes>
Geomean EBF     : <ebf>
Median nodes    : <nodes>
Top-pos share   : <percent>%  (<maximum> nodes)
Nodes/second    : <best-nps>   (best of <repeats>; median <median-nps>, min <minimum-nps>)
```

Cancellation emits one final line for fully completed work:

```text
info string bench cancelled run <run>/<repeats> positions <completed>/40 nodes <nodes>
```

Bench emits no `bestmove`. Timing, NPS, EBF, median, and share values are
diagnostic measurements; the one-thread node total is the behavior
fingerprint. Position EBF uses two decimal places, aggregate EBF uses three,
top share is a one-decimal percentage with the maximum node count, and the
even-sized corpus reports the upper median. A zero-millisecond position reports
its node count as NPS rather than inventing elapsed precision.

## 7. UCI options

One authoritative registry owns option declarations, defaults, parsing,
current values, and consumers. An option is advertised only when its behavior
is implemented. The initial product registry and canonical order are:

| Order | Declaration | Owning capability |
|---:|---|---|
| 1 | `option name Threads type spin default 1 min 1 max 1024` | SMP worker pool |
| 2 | `option name Hash type spin default 64 min 1 max 1048576` | Transposition table |
| 3 | `option name Clear Hash type button` | Transposition table |
| 4 | `option name Ponder type check default false` | Ponder control |
| 5 | `option name Move Overhead type spin default 10 min 0 max 5000` | Time policy |
| 6 | `option name SyzygyPath type string default <empty>` | Syzygy tablebases |
| 7 | `option name SyzygyProbeDepth type spin default 1 min 1 max 100` | Syzygy tablebases |
| 8 | `option name SyzygyProbeLimit type spin default 7 min 0 max 7` | Syzygy tablebases |
| 9 | `option name Syzygy50MoveRule type check default true` | Syzygy tablebases |

Spin values outside their advertised range are rejected rather than clamped.
Check values are exactly `true` or `false`, case-insensitively. A button takes
no `value`. A failed resource replacement leaves both the previous active
resource and its advertised current value unchanged.

`Threads` selects CPU search workers. Worker zero alone publishes completed
depth, PV and `bestmove`; helpers own private positions, evaluators and
histories and contribute only validated shared-TT evidence. A node limit is one
aggregate budget and all workers use the same absolute deadlines. Perft and
the deterministic bench remain one-thread operations.

`SyzygyPath` takes the remainder of the `setoption` line verbatim, because a
path may contain spaces and platform separators. The literal value `<empty>`
unloads the current tables rather than naming a directory. Loading is a
resource replacement under the same rule as `Hash`: any active search is
cancelled first, because the probe library's initialization is not thread
safe. A path naming no readable tables is not a failure; it reports
`info string SyzygyPath loaded no tablebase files` and the engine continues
without tablebase evidence. A successful load reports the covered piece count.

`SyzygyProbeLimit` caps the piece count that may be probed, independently of
how many pieces the loaded set covers. `Syzygy50MoveRule` selects whether
tablebase verdicts honour the fifty-move rule: with it enabled, which is the
default and the only setting correct for ordinary play, a cursed win and a
blessed loss are drawn; disabling it reports the theoretical result instead
and is an analysis setting.

No variant, contempt, MultiPV, evaluator or network option is advertised until
its owning phase explicitly accepts it. Step 5.4.5 tune binaries are the sole
exception for tuning options: an explicit `-Dtune=true` build appends the six
spin options registered in ADR-0060, while ordinary production builds retain
the public registry above. Their accepted defaults reproduce production and
out-of-range values are rejected under the same spin contract.

## 8. Search output

Search `info` lines follow UCI field semantics and contain a legal PV from the
root position. Once emitted, a line is immutable and complete. Node counts are
nondecreasing within an epoch. Time is elapsed milliseconds from `go` receipt.
`nps` is derived from the same node and time snapshot. `tbhits` counts
positions resolved from tablebase evidence and is emitted only when that count
is nonzero, so a deployment without tablebases produces the same fields as
before Step 5.2.

Scores use the root side's perspective. Centipawn and mate values obey
`SCORE-001`–`SCORE-008`; mate is reported in moves, and an already checkmated
root uses `score mate 0`. Bound tags are emitted only when the score is actually
a lower or upper bound.

During search, the bounded coalescible progress channel may emit:

```text
info depth <D> currmove <legal-root-move> currmovenumber <N> nodes <N> time <MS>
```

Each fully completed iteration may emit the ordinary score/depth/PV line.
Intermediate root information is observational only and may be replaced under
load; a completed result and its required `bestmove` are not droppable. Partial
or aborted iterations never manufacture PV, score or bound authority.

Normal completion is:

```text
bestmove <legal-uci-move> [ponder <legal-uci-move>]
```

The optional ponder move must be legal after the best move. Checkmate or
stalemate at the root is represented as:

```text
bestmove (none)
```

`0000` is not Manta's terminal-position token. Cancellation and internal
failure may use only a legal completed result or a deterministic legal
fallback; they cannot publish a pseudo-legal, excluded, or stale-epoch move.

## 9. Debug mode

`debug on` enables one bounded receipt line before processing each subsequent
non-empty command:

```text
info string debug received "<sanitized-input>"
```

Sanitization and the 256-byte rendered cap follow §3.1. The enabling
`debug on` line is not echoed. `debug off` is echoed and then disables the
mode. Debug mode never changes chess, search, time, or option semantics.

## 10. Transcript activation

The corpus assigns each transcript to the first phase capable of satisfying
it. Phase 6.2 cumulatively activates all 22 current process cases: the earlier
shell, Hash, position, one-thread search, clock, terminal, perft, shutdown and
bench cases plus live analysis, ponder lifecycle, transactional `Threads`
replacement and joined four-worker search. Later options remain absent until
their owning phases provide real consumers.

Real timing assertions use bounded waits only where responsiveness is the
subject. Logical ordering uses eventual output assertions and deterministic
fake clocks rather than sleeps.
