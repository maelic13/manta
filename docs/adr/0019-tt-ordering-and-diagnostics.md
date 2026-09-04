# ADR-0019: TT, ordering, and diagnostics substrate

## Status

Accepted for Step 4.1 on 2026-08-10.

## Context

Search needs reusable bounds and deterministic ordering before later pruning or
clock work. The table must already be safe for eventual shared access, stored
moves must remain untrusted until checked against current chess state, and mate
distance cannot depend on the ply where an entry happens to be reused.
Observability must explain tree changes without becoming a policy input.

## Decision

- Use caller-allocated, 64-byte-aligned clusters containing four 16-byte
  entries. Each entry has atomic 64-bit payload and guard words; no 128-bit
  atomic or per-access lock is required.
- Invalidate the guard, write the packed payload, then release-publish
  `full_key XOR payload`. Probe acquires the guard before and after the payload
  and accepts only an unchanged nonzero checksum. Concurrent mixtures and
  deliberately invalidated entries are misses.
- Pack move, signed score, depth, bound, generation and producer provenance.
  Normalize mate values on the sole table conversion path. Validate every
  nonempty stored move with current legal move rules before it can order a move
  or enter a PV.
- Replace an eligible same-key record, otherwise an empty entry, otherwise the
  greatest modular age, shallowest depth and non-exact bound in that order.
  Preserve the first physical slot on an exact tie. This is deterministic and
  contains no tuned weighting constant.
- Order stably by legal TT move, non-losing SEE tactical, first killer, second
  killer, quiet history and losing SEE tactical. Preserve generator order for
  equal ranks. Reward a quiet beta cutoff by nominal depth with signed
  saturation and rotate the two ply killers.
- Make SEE piece values an evaluator declaration exposed through its concrete
  binding. Search calls the board's generic SEE operation and never imports HCE
  parameter storage.
- Emit diagnostics through a compile-time observer with no policy return
  value. Counters cover tree shape, pruning overlap, TT provenance/use/recall,
  root changes and stop polling. Disabled and enabled observers must preserve
  complete deterministic search identity.

## Consequences

- TT false misses are permitted under races; mixed or unauthenticated records
  are never hits. Clear, resize and generation ownership remain outside active
  workers.
- The atomic table is the semantic baseline for both 1T and later SMP. A 1T
  specialization requires identical encoding/replacement behavior and measured
  benefit.
- Ordering can change tree size and tied best-move selection but cannot change
  terminal/draw ownership or exact minimax value. No pruning or playing-strength
  claim is licensed by this step.

## Verification

- `src/search/tt.zig` tests mate conversion across storage plies, checksum
  rejection of a mixed payload and deterministic replacement.
- `tests/search_substrate.zig` proves warm-table score/legal-move equivalence,
  rejects an illegal stored move, exercises stage order and verifies diagnostic
  enabled/disabled identity plus exact node accounting.
- Saturation tests bound histories and killer rotation; ordinary search tests
  continue to prove board/evaluator restoration and legal PVs.
- Debug, ReleaseSafe and ReleaseFast tests plus native and portable builds
  exercise the same atomic layout.
