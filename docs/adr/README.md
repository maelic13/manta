# Architecture decision records

These accepted records define Manta's Phase-0.2 architecture. They are read
with [`ARCHITECTURE.md`](../../ARCHITECTURE.md) and
[`REQUIREMENTS.md`](../../REQUIREMENTS.md).

| ADR | Decision |
|---|---|
| [0001](0001-clean-dependency-boundaries.md) | Clean dependency boundaries and Zig source organization |
| [0002](0002-ownership-and-allocation.md) | Explicit ownership, lifetimes and allocation |
| [0003](0003-position-state-selection.md) | Position/state separation and evidence-led representation selection |
| [0004](0004-make-unmake-ownership.md) | Caller-owned make/unmake state and history |
| [0005](0005-evaluator-composition.md) | Statically specialized, replaceable evaluators |
| [0006](0006-search-composition.md) | Concrete evidence-coherent search composition |
| [0007](0007-uci-control-plane.md) | Inward engine contracts and responsive UCI control plane |
| [0008](0008-clock-and-time.md) | Injected monotonic clock and receipt-based time accounting |
| [0009](0009-tt-concurrency.md) | Lock-free shared TT semantics without undefined races |
| [0010](0010-runtime-isa-dispatch.md) | Scalar oracle and coarse runtime ISA selection |
| [0011](0011-persisted-formats.md) | Versioned little-endian persisted formats |
| [0012](0012-error-flow.md) | Typed errors follow ownership and adapters own presentation |

An ADR records the accepted decision and its boundary, not implementation
detail that still requires evidence. A later incompatible choice adds a new
ADR that supersedes the old one; it does not rewrite history silently.
