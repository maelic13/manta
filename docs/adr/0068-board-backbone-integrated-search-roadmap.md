# ADR-0068: Board backbone and integrated search roadmap

## Status

Accepted for planning by the maintainer's 2026-09-08 request. Supersedes the
open-step sequence in ADR-0067 and the follow-on causal/sequencing claims of
ADR-0066. It changes no engine defaults, experiment verdict, licensing or
architecture dependency. Implementation and jobs require separate approval.

## Decision

Preserve completed Steps 6.5.0–6.5.3 and historical experiment identities.
Renumber remaining work as PLAN 6.5.4–6.5.15: target contracts; legal generation;
transition/SEE; exact qsearch cost; modern search design; shared outcome
evidence; integrated selective depth; forward proofs; conditional evaluation
reliability; residual cost/build optimization; conditional fit; final gates.

Two operational goals are independent of the strength gate. With the pinned
comparison engine and matched native host/work semantics, the board suite
requires a six-cell throughput-ratio geometric mean >= 1.00 and every cell
>= 0.95. Common-corpus 1T/64-MiB depth-13 elapsed must be <= 1.10 times the
comparison engine, both over all forty cases and the preidentified ordinary
subset. A separate routine `bench 13 1 1` has a prospectively fixed absolute
time limit. PLAN 6.5.4 freezes identities, timing protocol and that limit.
These tolerances operationalize the requested goals; they are not measured
capabilities. No post-result relaxation or substitution of one goal for another.

Use the pinned modern reference's structure and connected feature relationships
as design input, reimplemented in original Zig with Manta-owned scales and
contracts. The current coverage and pin are in
[SEARCH_COVERAGE.md](../SEARCH_COVERAGE.md); historical classical evaluator
references do not define this modern search backlog.

## Shared ownership and search contract

Board state owns exact legal facts and restoration. Search owns worker-local
ordering/outcome evidence and one prospective depth policy. Evaluation owns raw
HCE; ordinary refinement/correction remains separately typed search evidence.
Root completion owns time/UCI publication. No new inward dependency violation,
hot-path allocation, shared lock or avoidable atomic is authorized.

Derive terminal/mate/TT authority before selective consumers. Ordering,
history, window/node confidence, LMR, shallow pruning and forcing extensions
must use compatible facts and depth units. Reduced/probabilistic/exclusion
evidence cannot silently become full-depth exact evidence. Verification and
feedback consume authoritative searched outcomes without duplicate training.
Null and root boundaries, history-sensitive draws, all legal evasions, king
safety, castling, EP and promotion consequences remain explicit.

Steps are implementation tickets, not necessarily independent playing features.
Dependent producer/consumer tickets may form one prospectively frozen package
with switches. Semantic separability requires separate qualification unless
documented below-resolution evidence justifies a cohesive package. No umbrella
revival, all-feature bundle or late membership change. Each later proposal
uses the actual accepted earlier head; rejection requires dependency review.

## Evidence correction and stop rules

MAN-S31 was rejected by judgment, not formal H0. MAN-S33 was stopped
inconclusive and remains unpromoted; final artifact reconciliation must not be
confused with permission to run more games. The smaller fixed-depth trees do
not prove dispensable search, equivalence or a known cause of the results.
Low re-search frequency does not measure missed refutations; inclusive cost
shares overlap; rare null-verification disagreements can be valuable.

Use existing diagnostics and only necessary missing counters. Keep all board
cells and both whole/ordinary search cohorts visible. Exact speed claims need
identical results/PV/fingerprint and resolved whole-search timing. Every
retained production candidate/package still requires its registered 1T H1;
the phase ends with cumulative H1. The trusted match harness needs setup-only
validation, not candidate pilots. No automatic extra time control or retry.

PGO, new history tables, correction and fitting are conditional decisions, not
mandatory projects. Missed operational targets remain open or require explicit
maintainer objective revision. Completion by exhausting candidate ideas is not
completion of the objective. Phase 7 remains blocked and separately approved.

## Traceability

PLAN and GUIDE 6.5.4–6.5.15; REQUIREMENTS PERF-001, PERF-002, PERF-006 through
PERF-011 and QUAL-013 through QUAL-017; existing SCORE terminal, depth,
provenance and completed-root contracts remain authoritative until a specific
implementation ADR explicitly changes their affected clauses.
