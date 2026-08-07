# ADR-0011: Versioned little-endian persisted formats

- Status: Accepted
- Date: 2026-08-07

## Context

Networks, datasets and manifests must remain reproducible across OS/CPU targets
and fail safely when corrupt or incompatible. Native struct dumps silently
couple files to alignment, padding, endianness and compiler details.

## Decision

- Manta-defined binary formats are canonical little-endian and never direct
  dumps of in-memory Zig structs.
- Every binary header contains magic, schema version, header/payload lengths,
  required dimensions/feature identifiers and integrity metadata.
- Network headers additionally identify architecture, quantization and payload
  hash. Dataset shards have a versioned binary schema and external manifest.
- Versioned UTF-8 JSON is used for human-readable experiment/release manifests;
  large numerical payloads remain binary.
- Standard text formats use strict named parser profiles without proprietary
  wrapping.
- Unknown versions, wrong dimensions, forbidden trailing bytes, truncation and
  corruption are rejected before publication.
- Loading/replacement is transactional and occurs only while search is idle.
- Legacy conversion is an offline tool responsibility; the engine does not
  accumulate in-place migration chains.
- TT is not persisted, and no general configuration file is introduced
  initially.

## Consequences

- File codecs are explicit adapters/format modules and can be fuzzed without
  search.
- In-memory layout can evolve independently from disk schemas.
- Manifests can identify every external artifact without committing large
  files.
- A format change requires a version decision and compatibility test, not an
  accidental parser change.

## Verification

- Golden minimal files plus independent field decoding.
- Round-trip and cross-target byte identity.
- Corruption/truncation/wrong-endian/version/dimension matrix and fuzzing.
- Release/data manifests validate size and cryptographic hashes.

## Traceability

Supports `FILE-001`–`FILE-005`, `SAFE-005`, `PORT-006` and the Phase-7/8/10
format/release gates.
