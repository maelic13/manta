# ADR-0012: Typed errors follow ownership and adapters own presentation

- Status: Accepted
- Date: 2026-08-07

## Context

Zig error unions make recoverable failure explicit, but broad errors in node
search would add noise and cost. Threads cannot unwind errors to their creator,
and core layers must not format UCI or platform diagnostics.

## Decision

- External text/file/allocation/foreign failures use narrow typed errors at the
  boundary that can recover.
- Parsing and resource replacement are transactional; failure preserves the
  prior valid state/resource.
- Core chess/search/evaluation code never logs or constructs presentation text.
  The controller emits typed events and outer adapters format them.
- Worker entry catches its error union and publishes a typed completion because
  errors cannot unwind across an OS-thread boundary.
- Hot make/search/evaluate APIs use proven preconditions and safety-build
  assertions. Internal invariant corruption fails fast instead of becoming an
  `anyerror` branch throughout recursive search.
- External input, allocation and I/O failures never use `catch unreachable`.
- Input EOF is a successful orderly shutdown. Fatal process I/O/initialization
  failure cancels and joins work before returning a non-zero exit.
- Foreign status and pointers are translated/contained in their adapter.

## Consequences

- Error ownership is visible in signatures and lifecycle diagrams.
- Protocol presentation can evolve without changing domain errors.
- Tests can inject allocation, file, clock and worker failures without pipes.
- Truly impossible hot-path states remain assertions with independent invariant
  coverage rather than recoverable protocol behavior.

## Verification

- Compile-time/narrow-error API review and dependency lint.
- Failure-injection tests at parser, allocator, loader, worker and output
  boundaries.
- Transaction tests confirm old position/resources survive recoverable errors.
- Process tests verify EOF success, fatal-output cleanup and bounded diagnostics.

## Traceability

Supports `SAFE-001`–`SAFE-009`, `UCI-006`, `FILE-003`–`FILE-005` and the
Phase-0.3 error-flow audit.
