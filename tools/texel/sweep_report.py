#!/usr/bin/env python3
"""Summarise a tools/texel/fit_sweep.ps1 run.

Comparison is on validation loss only. The sweep never opens the frozen test,
so each report's "frozen_test" block duplicates validation and is ignored here.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ACCEPTED_VALIDATION = 0.10365193196244439
BASE_VALIDATION = 0.10551798832517009


def final_from_log(log: Path):
    """Recover the last epoch's validation loss for reports written before
    fit.py recorded it. The sweep tees each run's console output."""
    if not log.exists():
        return None
    last = None
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"epoch=\s*(\d+) train=\S+ validation=(\S+)", line.strip())
        if match:
            last = float(match.group(2))
    return last


def main() -> int:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "tools/texel/out/diag")
    rows = []
    for report in sorted(out.glob("*.tsv.report.json")):
        data = json.loads(report.read_text(encoding="utf-8"))
        settings = data["settings"]
        deltas = [abs(item["delta"]) for item in data["largest_deltas"]]
        rows.append({
            "name": report.name[:-len(".tsv.report.json")],
            "lr": settings["learning_rate"],
            "decay": settings.get("lr_decay", 1.0),
            "l2": settings["l2"],
            "support": settings["min_train_support"],
            "epoch": data["best_epoch"],
            "active": data["active_coefficients"],
            "moved": data["moved_coefficients"],
            "max_delta": max(deltas) if deltas else 0,
            "validation": data["validation"]["rounded_loss"],
            "float": data["validation"]["float_best_loss"],
            "final": (data["validation"].get("final_loss")
                      or final_from_log(report.parent / (report.name[:-len(".tsv.report.json")] + ".log"))),
            "last": data.get("last_epoch"),
        })
    if not rows:
        print(f"no reports under {out}")
        return 1

    for row in rows:
        # Settled runs end near their best. A run that ends far above it flew
        # through the minimum, so its reported loss is selection on a
        # trajectory rather than a converged result.
        row["flythrough"] = (row["final"] is None
                             or row["final"] - row["float"] > 0.0002)
        row["unknown"] = row["final"] is None
    rows.sort(key=lambda r: (r["flythrough"], r["validation"]))
    header = (f'{"configuration":24s} {"lr":>6s} {"decay":>6s} {"l2":>7s} {"sup":>4s} {"epoch":>6s} '
              f'{"moved":>6s} {"maxd":>5s} {"validation":>13s} {"vs accepted":>12s}  note')
    print()
    print(header)
    print("-" * len(header))
    for row in rows:
        gain = ACCEPTED_VALIDATION - row["validation"]
        print(f'{row["name"]:24s} {row["lr"]:6.1f} {row["decay"]:6.3f} {row["l2"]:7.0e} {row["support"]:4d} '
              f'{row["epoch"]:6d} {row["moved"]:6d} {row["max_delta"]:5d} '
              f'{row["validation"]:13.9f} {gain:+12.9f}'
              f'{"  NO TRAJECTORY" if row["unknown"] else ("  FLYTHROUGH - not settled" if row["flythrough"] else "")}')

    settled = [row for row in rows if not row["flythrough"]]
    if not settled:
        print("\nEvery configuration flew through its minimum. None converged; "
              "rerun with a harder decay before reading any of these as a result.")
        return 1
    best = settled[0]
    print(f'\naccepted constrained vector: {ACCEPTED_VALIDATION:.9f}')
    print(f'unfitted base vector:        {BASE_VALIDATION:.9f}')
    print(f'best sweep configuration:    {best["validation"]:.9f}  ({best["name"]})')
    improvement = ACCEPTED_VALIDATION - best["validation"]
    captured = BASE_VALIDATION - ACCEPTED_VALIDATION
    print(f'\nimprovement over accepted:   {improvement:+.9f}')
    print(f'accepted run captured:       {captured:+.9f}')
    if improvement <= 0:
        print('\nREADING: no configuration beat the accepted vector. The registered run\n'
              'was converged, not truncated, and the seeded values are near optimal for\n'
              'this feature set. Data quality, not optimizer travel, is the binding\n'
              'constraint -- proceed to the cycle program.')
    elif improvement < 0.1 * captured:
        print(f'\nREADING: a further {improvement:.9f} is available, under 10% of what the\n'
              'accepted run already captured. Real but marginal; the accepted vector is\n'
              'close to this model class\'s limit.')
    else:
        print(f'\nREADING: a further {improvement:.9f} is available, {improvement/captured:.0%} of what the\n'
              'accepted run captured. The registered run was travel-limited. Refit before\n'
              'gating anything, and treat the winning configuration as cycle 1.')
    print('\nBefore promoting any vector: rerun the winner with --test-prefix pointed at\n'
          'the real frozen test exactly once, and register that read.')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
