# ADR-0024: Classical search reference and observation contract

## Status

Accepted for Step 5.1.1 on 2026-08-12 through `MAN-S05`.

## Context

MAN-S03 and MAN-S04 established strong local mechanisms, but the next search
work spans ordering evidence, history attribution and reduction confidence.
Implementing isolated familiar formulas would leave producer/consumer
contracts implicit. Node counts or superficial agreement with Stockfish would
also be insufficient: legal chess, typed score authority and registered games
remain the independent correctness and strength evidence.

## Decision

- Freeze Stockfish 11 and the final pre-NNUE Stockfish commit by exact commit,
  tree and critical-file SHA-256 in
  `config/phase-5.1.1-reference.json`. Do not vendor or mechanically translate
  the source; formulas and fitted constants remain unlicensed hypotheses.
- Keep `manta-search-observation-v1` as a versioned balanced population of two
  legal, nonterminal roots in each of six cohorts: opening, quiet middlegame,
  tactical, check/evasion, zugzwang-sensitive and general endgame.
- Clear a private 16 MiB TT and caller-owned ordering history before every
  fixed-depth case. Record deterministic search facts only; clocks, NPS and
  playing claims do not enter this report.
- Extend the compile-time observer with move source/fail-high index, TT
  bound/provenance, history reward, null/LMR, prune/extension and
  completed-root counters. Search may publish facts after a decision, but the
  observer has no return channel into policy.
- Keep formatting, allocation and I/O in `tools/search_observe.zig`. The
  disabled specialization does not reconstruct move sources and must preserve
  exact best move, score/bound/provenance, nodes, completed depth and legal PV.
- Use `docs/SEARCH_REFERENCE.md` as the producer/transformation/consumer map.
  Its classifications sequence work; they do not authorize the wholesale
  table. Root/time and SMP remain in Phase 6.
- Treat the frozen engines as hypothesis, dependency and test-design sources,
  not behavioral or implementation targets. Manta-specific reasoning, original
  Zig design and native evidence remain mandatory; similarity has no verdict
  role.
- Do not build the optional HCE/search FFI hybrid. Reconsider it only if this
  cheaper native map leaves a decision-relevant ambiguity.

## Consequences

- Observation is caller-owned and thread-local. Ordinary nodes gain no
  allocation, I/O, lock or shared atomic; disabled production search retains
  compile-time no-op observer calls.
- Exact observation totals are diagnostic snapshots, not normative strength
  values. A causal search change may alter them, but the population or record
  must be versioned instead of silently updating an expected output.
- A reference comparison, smaller tree or higher recall can reject or explain
  a candidate. Similarity is not an objective; only the prospective registered
  Manta game gate can promote it.
- Step 5.1.2 begins from accepted MAN-S04 and owns exactly one coherent
  ordering/history/LMR family.

## Verification

- Every root parses consistently, has a legal move and satisfies its cohort
  invariant; the population contains exactly two cases per cohort.
- Enabled reports validate complete main/qsearch, move-source, cutoff, TT,
  LMR/null and root accounting. Named unsupported mechanisms remain explicit
  zero populations rather than inferred implementation.
- For every case, enabled and disabled observers preserve exact result and
  completed legal PV. The ordinary production fingerprint remains
  `2,910,189` nodes.
- Debug, ReleaseSafe and ReleaseFast suites pass. Two ReleaseSafe reports are
  byte-identical at SHA-256
  `F42380FB199C332CC51EBF9518E58FCF854707FCC632AC54432731F780D73078`.

## Traceability

Supports `FUNC-004`, `FUNC-005`, `FUNC-006`, `FILE-002`, `PERF-006`,
`PERF-009`, `PERF-010`, `QUAL-005`, `QUAL-013`, `QUAL-014`, `QUAL-015` and
`QUAL-016`.
