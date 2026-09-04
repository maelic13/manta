# ADR-0007: Inward engine contracts and responsive UCI control plane

- Status: Accepted
- Date: 2026-08-07
- Amended: 2026-08-29

## Context

Blocking input, active search and asynchronous output must coexist without
duplicated best moves, stale stop signals or UCI dependencies inside engine
policy. Letting the controller write stdout would also reverse the Clean
Architecture dependency.

## Decision

- `engine` owns tagged `EngineCommand` and `EngineEvent` contracts plus a
  coarse `EventSink` port and narrow `EngineControl` handle.
- `uci` owns bounded text parsing and event presentation. It depends inward on
  engine contracts; engine/search never import UCI or stdout.
- One logical input task reads through explicit `std.Io`, timestamps complete
  `go` receipt, parses bounded syntax, observes the controller-owned search
  epoch and transfers an owned command to a bounded mailbox. The epoch is
  minted by the controller, never by the adapter.
- The engine controller is the sole owner of current position, options,
  resources and active-job state.
- CPU search runs on separately owned worker threads. Workers publish typed
  info/completion events and never format/write output.
- The controller calls the event sink; the executable's UCI presenter is the
  sole stdout writer. Tests use an in-memory recorder.
- Stop, quit and ponderhit call the engine-owned handle to publish
  epoch-tagged urgent atomic state in addition to ordered commands, and they do
  so before queueing the ordered command so a full mailbox cannot delay
  cancellation. The adapter never accesses a worker directly.
- Production `EventSink` is a non-blocking offer into a bounded output mailbox
  drained by the sole UCI presenter task. A blocked stdout therefore does not
  block the controller.
- Info may be coalesced under pressure. If completion cannot transfer, the
  controller retains one pending critical event, starts no new search, keeps
  servicing control and retries after presenter progress. Completion is not
  dropped and no unbounded queue is created.
- Worker progress is likewise coalescible, while each active worker/job owns
  one bounded completion slot or equivalent joined result. Workers never wait
  for UCI presentation.
- Presenter I/O must be interruptible during process shutdown. A permanently
  blocked or failed output cannot force `quit` or EOF to hang indefinitely.
- Exactly-once completion requires the active epoch and a controller-owned
  publication state.
- Step 6.1 realizes the worker side as one coalescible progress slot plus a
  separate joined completion result. Epoch-specific atomics provide immediate
  control; the corresponding queued command remains FIFO-authoritative so a
  stop after a queued replacement `go` controls the replacement.

The concrete input/presenter tasks may use Zig 0.16 `std.Io.concurrent` or
dedicated adapter threads; Phase 1 selects the simpler correct form. CPU search
workers use a project-owned persistent `std.Thread` pool.

## Consequences

- `Threads` counts search workers, not input/controller support tasks.
- Controller tests need no pipes or formatted text; UCI process tests cover the
  input/output adapters and backpressure separately.
- Mailbox memory is bounded and urgent cancellation remains responsive.
- Output formatting and write failure stay external to search policy.

## Verification

- Complete command/state/output transcript corpus including queue pressure.
- Repeated-go, stale-epoch, stop/quit/EOF and ponder race tests.
- One writer/interleaving assertions and exactly one `bestmove`.
- Dependency lint forbids UCI/stdout imports inward.
- The active 20-case Phase-6.1 process matrix and secondary-reference ponder
  lifecycle comparison cover retained completion and live reporting.

## Traceability

Supports `UCI-001`–`UCI-008`, `SAFE-001`–`SAFE-008`, `RES-001`–`RES-003`,
`RES-011` and `RES-012`.
