# UCI transcript corpus

These files are the canonical process-level examples for the
[Manta UCI behavioral contract](../../docs/UCI.md). They freeze observable
behavior before the asynchronous process harness exists.

## Transcript notation

| Prefix | Meaning |
|---|---|
| `@phase N` | First numbered phase that must activate the transcript. |
| `< text` | Send `text` followed by LF to stdin. |
| `> text` | Require this exact next stdout line. |
| `! silence D` | Require no stdout for duration `D`, except well-formed search info inside an `allow-info` region. |
| `! send-oversized-line` | Send a line larger than `RES-001` without storing it in the corpus. |
| `! allow-info begin/end` | Permit well-formed search `info` lines between the markers. |
| `! close-stdin` | Close the process stdin stream. |
| `! block-stdout` / `! unblock-stdout` | Apply or release presenter backpressure. |
| `! fail-next K` | Inject the named resource failure at its owning port. |
| `! exit CODE within D` | Require process exit with the code inside the bound. |
| `---` | End one process case and start a fresh process for the next case. |

Unlisted stdout is forbidden. stderr is captured separately and may contain
only diagnostics allowed by the behavioral contract. Durations are upper
bounds, not sleeps.

The harness substitutes these typed placeholders:

| Placeholder | Meaning |
|---|---|
| `{{VERSION}}` | Exact authoritative build version. |
| `{{OPTION_DECLARATIONS}}` | Zero or more exact declarations from the active authoritative registry, in canonical order. |
| `{{U64}}` | One unsigned decimal 64-bit value. |
| `{{I64}}` | One signed decimal 64-bit value. |
| `{{POSITIVE_U64}}` | One positive unsigned decimal 64-bit value. |
| `{{DECIMAL}}` | One finite non-negative decimal value. |
| `{{EMPTY}}` | One empty output line. |
| `{{ROOT_MOVE_INFO}}` | One syntactically valid live root-move line with legal UCI move text and bounded numeric fields. |
| `{{ITERATION_INFO}}` | One completed-iteration score/depth/PV line satisfying the ordinary search-info contract. |
| `{{SEARCH_INFO}}` | One valid coalescible root-move or completed-iteration line; it does not require both optional forms to survive coalescing. |
| `{{BESTMOVE_LINE}}` | One legal `bestmove`, with an optional legal `ponder` continuation. |
| `{{PONDER}}` | Either nothing or one ` ponder <legal UCI move>` continuation. |
| `{{BENCH_POSITION_LINES}}` | Exactly 40 ordered Rarog-compatible lines of `bench <index>/40  depth {{U64}}  score {{I64}}  nodes {{U64}}  ebf {{DECIMAL}}  time {{U64}}ms  nps {{U64}}`, with contiguous indices 1 through 40. |

Placeholders never match line endings or arbitrary text. Phase 1.2 owns the
parser for this notation and must reject unknown directives or placeholders.

The harness validates the complete corpus on every run and executes every case
at or before active Step 6.3.2. All 23 current process cases are active. A frozen
command owned by a later phase receives the exact temporary `not available
yet` diagnostic; its eventual implementation must activate the staged case
rather than add partial behavior.

## Corpus

- [Startup and handshake](01-startup-handshake.transcript)
- [Unknown commands and debug](02-unknown-debug.transcript)
- [Readiness and ordered barriers](03-readiness-barriers.transcript)
- [Option transactions](04-options.transcript)
- [Transactional position replacement](05-position-transaction.transcript)
- [Search lifecycle](06-search-lifecycle.transcript)
- [Ponder lifecycle](07-ponder-lifecycle.transcript)
- [Perft diagnostic](08-perft.transcript)
- [Terminal positions](09-terminal-position.transcript)
- [Quit and EOF](10-shutdown.transcript)
- [Built-in bench](11-bench.transcript)
- [Output backpressure](12-output-backpressure.transcript)
- [SMP ownership and lifecycle](13-smp.transcript)
- [Integrated time telemetry and thread allocation](14-time-management.transcript)
