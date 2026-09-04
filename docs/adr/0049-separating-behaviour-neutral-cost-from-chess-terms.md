# ADR-0049: Separating behaviour-neutral cost from chess terms, and fitting the HCE in Phase 5

## Status

Accepted 2026-08-17. Supersedes the bundling decision in
[ADR-0048](0048-imbalance-and-evaluation-cost.md) and amends `PLAN.md` 5.3.9
and 5.3.10.

**Partly superseded the same day by
[ADR-0050](0050-primary-reference-switch-and-phase-5-3-resequence.md).** The
step numbers below are the ones this record was written against; the structure
freeze is now 5.3.15 and the fit is now 5.3.16, with structural completion
inserted between. The decisions here otherwise stand, with one narrowing:
ADR-0050 permits rejected `MAN-E07` into the fit as a free coefficient block
decided by a post-fit ablation, because the double-counting failure mode is a
claim about joint scale that the "negative untuned means refuted" rule below
does not correctly cover.

## Context

Step 5.3.8 registered one gate, `MAN-E06`, over a binary containing two
unrelated changes: behaviour-neutral speed work that moved no frozen
fingerprint, and a new evaluation term that moved all eighteen.

The argument for bundling them was that the two halves were separately
*attributable*. It is true that they were. The fingerprints prove the cost work
changed no tree, so any node-count difference belongs to the imbalance term and
any time difference to the cost work. That reasoning is sound and it is also
beside the point, which is why it survived review twice before failing.

A strength gate does not return node counts. It returns one Elo estimate. No
fingerprint attributes that estimate, so a bundle of a `-7.4%` wall-time gain
and an unmeasured chess term produces a verdict that cannot be decomposed:
H1 would not show the term helped, and H0 would not show it hurt. The first
launch reached 2,520 games at `+1.38 +/- 9.11` Elo before host-side timeouts
stopped it — an interval wide enough to contain "speed helped and the term is
neutral" and "speed helped and the term cost about as much", which are
different conclusions with different consequences.

`AGENTS.md` already forbade this: a bundle is permitted only where the parts
are semantically inseparable, intermediate states are invalid or misleading, or
the effects are individually below the affordable resolution. None applied. The
registration said as much in its own words — inseparable "only in the sense
that both land in one binary" — which is a statement that the rule does not
apply, written as though it did.

Separately, every coefficient in the evaluator is a hand-reasoned starting
value. That was correct for selecting mechanisms, because a gate on hand-set
values measures the mechanism rather than the fit. It is not a defensible
place to stop, and each accepted step has added to the debt.

## Decision

### Behaviour-neutral work does not take a strength gate

`PLAN.md`'s evidence table already gates behaviour-neutral work on format and
lint, the required test modes, and an exact 1T bench fingerprint. That is the
whole gate. Where the work is also a speed change, add a controlled throughput
measurement, and prefer the case where the fingerprint is unchanged: identical
nodes make the NPS ratio exactly the time ratio, which is a stronger claim than
any game sample of comparable cost would produce.

Games are spent on questions that only games can answer. "Is the same search
faster" is not one of them.

### A chess term is gated alone, against the accepted head

Where behaviour-neutral work and a chess change are ready together, the cost
work lands and is accepted first, and the chess term is gated against that
accepted head. This costs one run rather than two and yields an interpretable
verdict. "Both are ready at the same time" is a scheduling fact and not a
licence to bundle.

### Speed is measured order-balanced on a verified-idle host

Every throughput claim states its idle check, alternates run order across
rounds, pins the process, and reports medians with observed ranges. The
unbalanced figures Step 5.3.8 originally carried overstated a bench gain by
nearly a factor of two — `+14.7%` claimed against `+8` to `+9%` measured — with
error at both ends, which is the signature of drift in an unbalanced sample
rather than of noise. Quote the result as a range across at least two built
instances, since `MAN-P02` shows codegen alone moves it by about a point.

### The HCE is fitted before Phase 5 closes

Maintainer decision: a non-fitted HCE is not an acceptable Phase-5 output.
Step 5.3.9 freezes evaluator **structure** — which terms exist, what each
consumes, how they compose — and new Step 5.3.10 fits the coefficients of that
frozen structure by static loss against labelled positions.

This is a texel-style fit and deliberately not SPSA. The distinction is what
makes it affordable: a static fit evaluates positions instead of playing games,
so its cost is data preparation and compute rather than a game budget. SPSA
remains conditional, game-based and separately authorized at 5.4.3; nothing
here pre-authorizes it, and a disappointing fit does not escalate into one.

The fit requires a registered data plan, an explicit free/fixed/excluded
coefficient split, held-out validation through the 5.3.0 residual harness, and
a stated stop rule. Binary feature switches never receive a gradient. A reduced
static loss is a proposal: the baked binary takes one registered 1T `3+0.03`
SPRT against the untuned accepted structural head, and H0 restores the reasoned
values without discarding any structurally accepted mechanism.

## Consequences

`MAN-E06` is withdrawn before verdict and split into accepted `MAN-P01` and
pending `MAN-E07`. No games carry across; the design changed, so the evidence
restarts.

A term that reaches H0 on reasoned coefficients now has two possible
explanations rather than one — wrong relations, or right relations at the wrong
scale — and 5.3.10 is where the second is tested. This is not a licence to
retain failed mechanisms in the hope that fitting rescues them: a term whose
sign structure is right should show directional signal untuned, and the
`MAN-E05` prohibition on retuning coefficients and re-running a failed gate
stands unchanged. The distinction is that 5.3.10 fits everything at once
against static loss, rather than hand-adjusting one rejected term until its
gate passes.

The Phase-11 HCE tuning entry in the retry map narrows to work beyond the
5.3.10 fit.

Chasing a hash mismatch between two builds of one commit during `MAN-P01`
established that Manta's build is not byte-reproducible (`MAN-P02`). That does
not affect any behavioural claim — every such binary reproduced the same bench
fingerprint — but it does mean a recorded artifact hash names which bytes ran
rather than certifying their source, and that a speed result carries codegen
variance of about one point. Speed claims are therefore quoted as a range
across built instances, and the artifact contract now says so.

## Traceability

- `PLAN.md` 5.3.8, 5.3.9, 5.3.10; `GUIDE.md` current checkpoint.
- `EXPERIMENTS.md` `MAN-E06`, `MAN-P01`, `MAN-P02`, `MAN-E07`, the artifact
  contract and the retry map.
- [ADR-0048](0048-imbalance-and-evaluation-cost.md).
