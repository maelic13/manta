# ADR-0010: Scalar oracle and coarse runtime ISA selection

- Status: Accepted
- Date: 2026-08-07

## Context

Manta needs portable releases and host-specialized local builds without
duplicating chess semantics or executing unsupported instructions. Dispatch at
every small operation would harm inlining, while deciding a particular stable
Zig multiversioning mechanism years early would be brittle.

## Decision

- The portable scalar implementation is always present and is the semantic
  oracle.
- CPU detection is an outer adapter run at startup. Capabilities are modeled
  independently rather than as one broad architecture label.
- Backend requirements, build flags, artifact names and runtime validation form
  one manifest-visible contract.
- Backend selection occurs at startup, search entry or a sufficiently coarse
  heavy-kernel boundary.
- Prefer `comptime` monomorphization when code size is reasonable. Permit an
  indirect heavy-kernel call only after measurement.
- A native build may compile directly for the host. A portable release may use
  runtime siblings or accurately named assets; Phase 10 decides using the
  current stable Zig and native evidence.
- A forced unsupported backend is rejected and scalar remains usable.
- Every optimized integer kernel is bit-exact with scalar behavior.

## Consequences

- No backend switch is hidden inside every bitboard primitive.
- HCE/NNUE/backend combinations must be managed to avoid uncontrolled code
  size and build-time multiplication.
- Portable release speed can improve without removing the broad fallback.
- Presence of an instruction does not itself prove that implementation fastest
  on a microarchitecture.

## Verification

- Feature-mask and forced-backend tests, including unsupported hardware.
- Scalar/backend randomized and corpus conformance plus bench fingerprint.
- Disassembly verifies baseline ISA and optimized instructions.
- Target-native NPS/profile evidence and artifact manifest audit.

## Traceability

Supports `PERF-001`, `PERF-004`, `PERF-005`, `PORT-003`, `PORT-006` and
`PORT-007`.
