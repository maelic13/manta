# ADR-0001: Clean dependency boundaries and Zig source organization

- Status: Accepted
- Date: 2026-08-07

## Context

Manta needs separation between chess/search policy and UCI, files, clocks and
the operating system, but conventional object-oriented Clean Architecture can
add interfaces, allocation and indirection that are inappropriate in a chess
engine hot path. Zig instead provides file namespaces, explicit imports,
tagged unions, error unions and compile-time structural composition.

## Decision

Use a functional core and imperative shell with inward dependency direction:

1. `chess`, `score` and `time` contain narrow domain values/rules and the
   inward monotonic-clock contract.
2. `eval` and `search` contain engine policy and depend only inward.
3. `engine` contains application commands/events, resource lifecycle and the
   controller.
4. `uci` and `adapters` translate external I/O/platform services into inward
   contracts.
5. `main.zig` is the only complete composition root.
6. `manta.zig` is a narrow non-UCI library facade for tests/tools.

Port contracts live with the inward consumer. Runtime callbacks are permitted
only at coarse adapter boundaries. Hot policy uses concrete types and
`comptime` specialization.

Use a small number of Zig build modules and file namespaces, not one build
module or container type per conceptual class. Keep declarations private by
default. Do not create `utils`, `common` or other unowned dependency magnets.

## Consequences

- Core tests can run without stdin/stdout, files or OS scheduling.
- UCI and future direct-library tools share application use cases.
- TT remains an internal search structure because abstracting each probe would
  impose cost without improving the dependency rule.
- Some ports use a context pointer/function pointer, but none are called at
  ordinary node frequency without separate measurement.
- Cross-layer types must have an explicit owner instead of living in a generic
  shared package.

## Verification

- Project lint scans imports and public declarations.
- `chess`, `score`, `eval` and `search` cannot import `uci`, `std.Io`, concrete
  files, process APIs or external adapters.
- Disassembly checks reject unintended indirect calls in recursive search and
  evaluation.
- Direct-library tests construct the engine without UCI.

## Traceability

Supports `FUNC-002`, `FILE-004`, `PERF-001`, `QUAL-006` and the Phase-0
zero-cost dependency gate.
