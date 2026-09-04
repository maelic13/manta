#!/usr/bin/env python3
"""Audit exact and pawn-family concentration of EPD or PGN start positions."""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

import chess

import extract
import sample_fens


def pgn_fen(line: str) -> str | None:
    prefix = '[FEN "'
    line = line.rstrip("\r\n")
    if not line.startswith(prefix) or not line.endswith('"]'):
        return None
    fields = line[len(prefix):-2].split()
    return " ".join(fields[:4]) if len(fields) >= 4 else None


def iter_starts(path: Path):
    if path.suffix.lower() == ".pgn":
        with path.open(encoding="utf-8", errors="replace") as stream:
            for line in stream:
                fen = pgn_fen(line)
                if fen:
                    yield fen
    else:
        with path.open(encoding="utf-8", errors="replace") as stream:
            for line in stream:
                fields = line.split()
                if len(fields) >= 4:
                    yield " ".join(fields[:4])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+")
    parser.add_argument("--validation-pct", type=float)
    parser.add_argument("--test-pct", type=float)
    args = parser.parse_args()
    if (args.validation_pct is None) != (args.test_pct is None):
        parser.error("validation and test percentages must be supplied together")
    if args.validation_pct is not None and (
            min(args.validation_pct, args.test_pct) < 0
            or args.validation_pct + args.test_pct >= 100):
        parser.error("validation/test percentages must be non-negative and sum below 100")
    exact = Counter()
    phases = Counter()
    splits = Counter()
    families = [Counter() for _ in sample_fens.PHASE_BUCKETS]
    for text in args.inputs:
        for fen in iter_starts(Path(text)):
            bucket = sample_fens.phase_bucket(fen)
            if not exact[fen] and args.validation_pct is not None:
                splits[extract.split_for_key(fen, args.validation_pct, args.test_pct)] += 1
            exact[fen] += 1
            phases[bucket] += 1
            families[bucket][sample_fens.pawn_family(fen)] += 1
    total = sum(exact.values())
    print(f"Starts={total:,} exact_unique={len(exact):,} duplicates={total-len(exact):,}")
    for index, (name, _low, _high) in enumerate(sample_fens.PHASE_BUCKETS):
        family = families[index]
        print(f"  {name:13}: starts={phases[index]:,} families={len(family):,} "
              f"effective={sample_fens.effective_count(family):,.0f} "
              f"largest={max(family.values(), default=0)}")
    print("Pawn family is a correlation proxy; the source contains no original game IDs.")
    if args.validation_pct is not None:
        print("Independent starts by split: " + " ".join(
            f"{name}={splits[name]:,}" for name in ("train", "validation", "test")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
