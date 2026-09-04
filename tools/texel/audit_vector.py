#!/usr/bin/env python3
"""Semantic audit of a fitted vector against the vector it was fitted from.

The Step-5.3.16 first fit was refuted at source-bake review because four
coordinates crossed a direction that is part of their chess feature identity.
`SEMANTIC_BOUNDS` in fit.py now clamps the six coordinates that failure named,
but a clamp only protects the coordinates someone already thought of. This
audit reports every crossing so review sees them as a list rather than finding
them by eye.

A crossing is not automatically wrong. Piece-square entries legitimately change
sign, and a coefficient whose magnitude was near zero can cross on noise. A
crossing on a named structural term is the one that needs an argument.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def read_vector(path: Path):
    lines = path.read_text(encoding="utf-8").splitlines()
    rows = {}
    for line in lines[1:]:
        if not line:
            continue
        name, value, status, _unit = line.split("\t")
        rows[name] = (int(value), status)
    return lines[0], rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base", help="vector the fit started from")
    parser.add_argument("fitted", help="vector produced by the fit")
    parser.add_argument("--top", type=int, default=20)
    args = parser.parse_args()

    base_schema, base = read_vector(Path(args.base))
    fitted_schema, fitted = read_vector(Path(args.fitted))
    if base_schema != fitted_schema:
        raise SystemExit(f"schema mismatch: {base_schema} vs {fitted_schema}")
    if base.keys() != fitted.keys():
        raise SystemExit("coefficient sets differ")

    crossings, zeroed, revived, moves = [], [], [], []
    for name, (old, status) in base.items():
        new = fitted[name][0]
        if fitted[name][1] != status:
            raise SystemExit(f"status changed for {name}")
        if status != "free" or old == new:
            continue
        moves.append((abs(new - old), name, old, new))
        if old != 0 and new != 0 and (old > 0) != (new > 0):
            crossings.append((name, old, new))
        elif old != 0 and new == 0:
            zeroed.append((name, old))
        elif old == 0 and new != 0:
            revived.append((name, new))

    structural = [item for item in crossings if not item[0].startswith("pst_")]
    print(f"moved {len(moves)} free coefficients; largest |delta| "
          f"{max(moves)[0] if moves else 0}")
    print(f"sign crossings {len(crossings)} ({len(structural)} outside piece-square tables)")
    print(f"driven to zero {len(zeroed)}; lifted off zero {len(revived)}")

    if structural:
        print("\nSTRUCTURAL SIGN CROSSINGS - each needs a chess argument or a bound:")
        for name, old, new in sorted(structural, key=lambda item: -abs(item[2] - item[1])):
            print(f"  {name:34s} {old:6d} -> {new:6d}")
    else:
        print("\nno structural sign crossing")

    if zeroed:
        print("\nDRIVEN TO ZERO - the fit is proposing to delete these:")
        for name, old in sorted(zeroed, key=lambda item: -abs(item[1]))[:args.top]:
            print(f"  {name:34s} {old:6d} ->      0")

    print(f"\nlargest {args.top} moves:")
    for size, name, old, new in sorted(moves, reverse=True)[:args.top]:
        print(f"  {name:34s} {old:6d} -> {new:6d}  ({new - old:+d})")

    if structural:
        print(f"\nVERDICT: {len(structural)} structural crossing(s). Do not bake without review.")
        return 1
    print("\nVERDICT: no structural crossing. Safe to proceed to source-bake review.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
