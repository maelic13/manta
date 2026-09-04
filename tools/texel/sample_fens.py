#!/usr/bin/env python3
"""Stream an immutable FEN pool into a diverse, phase-balanced EPD book."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import sys
from collections import Counter
from pathlib import Path

try:
    import chess
except ImportError:
    print("ERROR: install tools/texel/requirements.txt", file=sys.stderr)
    raise SystemExit(1)


PHASE_W = {"n": 1, "b": 1, "r": 2, "q": 4,
           "N": 1, "B": 1, "R": 2, "Q": 4}
PHASE_BUCKETS = (
    ("opening", 20, 24),
    ("early_mid", 14, 19),
    ("middlegame", 8, 13),
    ("endgame", 3, 7),
    ("deep_endgame", 0, 2),
)


def phase_bucket(epd: str) -> int:
    phase = min(sum(PHASE_W.get(char, 0) for char in epd.split()[0]), 24)
    for index, (_name, low, high) in enumerate(PHASE_BUCKETS):
        if low <= phase <= high:
            return index
    raise ValueError(f"phase outside 0..24: {phase}")


def bucket_targets(total: int) -> list[int]:
    base, extra = divmod(total, len(PHASE_BUCKETS))
    return [base + (index < extra) for index in range(len(PHASE_BUCKETS))]


def parse_line(raw: bytes) -> str | None:
    line = raw.decode("utf-8", errors="replace").strip()
    if not line:
        return None
    if "\t" in line:
        line = line.rsplit("\t", 1)[0]
    elif ";" in line:
        line = line.rsplit(";", 1)[0]
    fields = line.split()
    return " ".join(fields[:4]) if len(fields) >= 4 else None


def pgn_fen(line: str) -> str | None:
    prefix = '[FEN "'
    line = line.rstrip("\r\n")
    if not line.startswith(prefix) or not line.endswith('"]'):
        return None
    fields = line[len(prefix):-2].split()
    return " ".join(fields[:4]) if len(fields) >= 4 else None


def iter_start_epds(path: Path):
    if path.suffix.lower() == ".pgn":
        with path.open(encoding="utf-8", errors="replace") as stream:
            for line in stream:
                epd = pgn_fen(line)
                if epd is not None:
                    yield epd
    else:
        with path.open("rb") as stream:
            for raw in stream:
                epd = parse_line(raw)
                if epd is not None:
                    yield epd


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def load_exclusions(paths: list[Path]) -> tuple[set[str], Counter]:
    excluded: set[str] = set()
    family_usage: Counter = Counter()
    for path in paths:
        for epd in iter_start_epds(path):
            if epd in excluded:
                continue
            excluded.add(epd)
            family_usage[pawn_family(epd)] += 1
    return excluded, family_usage


def pawn_family(epd: str) -> tuple[int, int, str]:
    board = chess.Board(epd + " 0 1")
    white = board.pieces(chess.PAWN, chess.WHITE).mask
    black = board.pieces(chess.PAWN, chess.BLACK).mask
    # Pawn placement is the useful adjacent-game proxy. With at most two pawns
    # it becomes too coarse (all pawnless endings would be one family), so add
    # non-king piece placement while still grouping ordinary king manoeuvres.
    sparse_material = ""
    if (white | black).bit_count() <= 2:
        sparse_material = "/".join(
            f"{square}:{piece.symbol()}" for square, piece in board.piece_map().items()
            if piece.piece_type not in (chess.PAWN, chess.KING)
        )
    return (white, black, sparse_material)


def effective_count(counter: Counter) -> float:
    total = sum(counter.values())
    denominator = sum(count * count for count in counter.values())
    return total * total / denominator if denominator else 0.0


def is_eligible(epd: str, minimum_pieces: int, maximum_pieces: int) -> bool:
    try:
        board = chess.Board(epd + " 0 1")
    except ValueError:
        return False
    pieces = len(board.piece_map())
    return (minimum_pieces <= pieces <= maximum_pieces
            and board.is_valid()
            and not board.is_game_over(claim_draw=False)
            and not board.is_check())


def write_atomic(path: Path, data: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(data, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("--out", default="tools/texel/data/beast-seed-v1.epd")
    parser.add_argument("--count", type=int, default=1_000_000)
    parser.add_argument("--seed", type=int, default=5_316_001)
    parser.add_argument("--oversample", type=int, default=3)
    parser.add_argument("--max-per-pawn-family", type=int, default=4)
    parser.add_argument("--min-pieces", type=int, default=6)
    parser.add_argument("--max-pieces", type=int, default=32)
    parser.add_argument("--exclude", action="append", default=[],
                        help="EPD/PGN starts to exclude; repeat for multiple inputs")
    parser.add_argument("--max-read", type=int, default=0,
                        help="test-only line cap; production uses the whole file")
    parser.add_argument("--progress-every", type=int, default=5_000_000)
    args = parser.parse_args()

    source = Path(args.source).resolve()
    output = Path(args.out).resolve()
    if not source.is_file():
        parser.error(f"source not found: {source}")
    if source == output:
        parser.error("source and output must differ")
    if args.count <= 0 or args.oversample <= 0 or args.max_per_pawn_family <= 0:
        parser.error("count, oversample and family cap must be positive")

    exclude_paths: list[Path] = []
    for text in args.exclude:
        path = Path(text).resolve()
        if not path.is_file():
            parser.error(f"exclude input not found: {path}")
        if path == output:
            parser.error("output cannot also be an exclude input")
        if path not in exclude_paths:
            exclude_paths.append(path)
    excluded, family_usage = load_exclusions(exclude_paths)

    rng = random.Random(args.seed)
    targets = bucket_targets(args.count)
    capacities = [target * args.oversample for target in targets]
    reservoirs: list[list[str]] = [[] for _ in PHASE_BUCKETS]
    seen_by_phase = [0] * len(PHASE_BUCKETS)
    source_hash = hashlib.sha256()
    lines_read = candidates = excluded_source_lines = 0

    print(f"Read-only source: {source}")
    print(f"Target: {args.count:,} starts -> {output}")
    if exclude_paths:
        print(f"Excluded starts: {len(excluded):,} from {len(exclude_paths)} input(s)")
    with source.open("rb") as stream:
        for raw in stream:
            source_hash.update(raw)
            lines_read += 1
            epd = parse_line(raw)
            if epd is not None:
                candidates += 1
                if epd in excluded:
                    excluded_source_lines += 1
                else:
                    bucket = phase_bucket(epd)
                    seen_by_phase[bucket] += 1
                    reservoir = reservoirs[bucket]
                    if len(reservoir) < capacities[bucket]:
                        reservoir.append(epd)
                    else:
                        pick = rng.randrange(seen_by_phase[bucket])
                        if pick < capacities[bucket]:
                            reservoir[pick] = epd
            if args.progress_every and lines_read % args.progress_every == 0:
                print(f"  read={lines_read:,} candidates={candidates:,}")
            if args.max_read and lines_read >= args.max_read:
                break

    for reservoir in reservoirs:
        rng.shuffle(reservoir)
    selected: list[list[str]] = [[] for _ in PHASE_BUCKETS]
    cursors = [0] * len(PHASE_BUCKETS)
    exact: set[str] = set()
    selected_families: Counter = Counter()
    while any(len(selected[index]) < targets[index] for index in range(len(PHASE_BUCKETS))):
        progressed = False
        for index in range(len(PHASE_BUCKETS)):
            if len(selected[index]) >= targets[index]:
                continue
            reservoir = reservoirs[index]
            while cursors[index] < len(reservoir):
                epd = reservoir[cursors[index]]
                cursors[index] += 1
                if epd in exact or not is_eligible(epd, args.min_pieces, args.max_pieces):
                    continue
                family = pawn_family(epd)
                if family_usage[family] >= args.max_per_pawn_family:
                    continue
                exact.add(epd)
                family_usage[family] += 1
                selected_families[family] += 1
                selected[index].append(epd)
                progressed = True
                break
        if not progressed:
            break

    phase_counts = [len(bucket) for bucket in selected]
    if phase_counts != targets:
        print("ERROR: exact phase/family quotas were not met; output unchanged.", file=sys.stderr)
        for index, (name, _low, _high) in enumerate(PHASE_BUCKETS):
            print(f"  {name:13}: {phase_counts[index]:,}/{targets[index]:,}", file=sys.stderr)
        return 2

    rows = [epd for bucket in selected for epd in bucket]
    rng.shuffle(rows)
    book_text = "".join(row + "\n" for row in rows)
    book_hash = hashlib.sha256(book_text.encode("utf-8")).hexdigest().upper()
    write_atomic(output, book_text)
    manifest = {
        "schema": "manta-hce-starts-v2",
        "source": str(source),
        "source_size_bytes": source.stat().st_size,
        "source_sha256": source_hash.hexdigest().upper(),
        "book": str(output),
        "book_sha256": book_hash,
        "seed": args.seed,
        "lines_read": lines_read,
        "candidates": candidates,
        "exclude_inputs": [
            {"path": str(path), "size_bytes": path.stat().st_size,
             "sha256": sha256_file(path)} for path in exclude_paths
        ],
        "excluded_unique_starts": len(excluded),
        "excluded_source_lines": excluded_source_lines,
        "count": len(rows),
        "phase_counts": {PHASE_BUCKETS[i][0]: phase_counts[i] for i in range(5)},
        "max_per_pawn_family": args.max_per_pawn_family,
        "pawn_families": len(selected_families),
        "pawn_family_effective_count": effective_count(selected_families),
        "largest_pawn_family": max(selected_families.values(), default=0),
        "combined_pawn_families": len(family_usage),
        "combined_pawn_family_effective_count": effective_count(family_usage),
        "combined_largest_pawn_family": max(family_usage.values(), default=0),
        "filters": {"min_pieces": args.min_pieces, "max_pieces": args.max_pieces,
                    "legal": True, "non_terminal": True, "not_in_check": True},
    }
    write_atomic(output.with_suffix(output.suffix + ".manifest.json"),
                 json.dumps(manifest, indent=2) + "\n")

    print(f"Written: {len(rows):,}; SHA-256 {book_hash}")
    print(f"Pawn families: {len(selected_families):,}; "
          f"effective={effective_count(selected_families):,.0f}; "
          f"largest={max(selected_families.values(), default=0)}")
    if exclude_paths:
        print(f"Combined pawn families: {len(family_usage):,}; "
              f"effective={effective_count(family_usage):,.0f}; "
              f"largest={max(family_usage.values(), default=0)}; "
              f"excluded source lines={excluded_source_lines:,}")
    for index, (name, _low, _high) in enumerate(PHASE_BUCKETS):
        print(f"  {name:13}: saw={seen_by_phase[index]:,} selected={phase_counts[index]:,}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
