#!/usr/bin/env python3
"""Extract grouped, phase-balanced quiet WDL rows from Manta self-play PGNs."""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import math
import os
import random
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

try:
    import chess
    import chess.pgn
except ImportError:
    print("ERROR: install tools/texel/requirements.txt", file=sys.stderr)
    raise SystemExit(1)


RESULT_MAP = {"1-0": 1.0, "0-1": 0.0, "1/2-1/2": 0.5}
PHASE_W = {chess.KNIGHT: 1, chess.BISHOP: 1, chess.ROOK: 2, chess.QUEEN: 4}
PHASE_BUCKETS = (
    ("opening", 20, 24),
    ("early_mid", 14, 19),
    ("middlegame", 8, 13),
    ("endgame", 3, 7),
    ("deep_endgame", 0, 2),
)
BUCKET_NAMES = tuple(item[0] for item in PHASE_BUCKETS)
PIECE_VALUE = {chess.PAWN: 1, chess.KNIGHT: 3, chess.BISHOP: 3,
               chess.ROOK: 5, chess.QUEEN: 9, chess.KING: 20}
SPLITS = ("train", "validation", "test")


def game_phase(board: chess.Board) -> int:
    return min(24, sum(PHASE_W[piece_type] * len(board.pieces(piece_type, colour))
                       for piece_type in PHASE_W for colour in (chess.WHITE, chess.BLACK)))


def phase_bucket(phase: int) -> int:
    for index, (_name, low, high) in enumerate(PHASE_BUCKETS):
        if low <= phase <= high:
            return index
    raise ValueError(f"phase outside 0..24: {phase}")


def fen_key(fen: str) -> str:
    """Static-eval identity: retain halfmove clock, discard fullmove number."""
    return " ".join(fen.split()[:5])


def start_key(game: chess.pgn.Game) -> str:
    """Every game from the same supplied start stays in the same split."""
    return " ".join(game.board().fen().split()[:4])


def start_digest(game: chess.pgn.Game) -> int:
    return int.from_bytes(hashlib.sha256(start_key(game).encode("utf-8")).digest()[:8], "big")


def split_for_key(key: str, validation_pct: float, test_pct: float) -> str:
    digest = int.from_bytes(hashlib.sha256(key.encode("utf-8")).digest()[:8], "big")
    slot = digest % 1_000_000
    test_cut = round(test_pct * 10_000)
    validation_cut = test_cut + round(validation_pct * 10_000)
    if slot < test_cut:
        return "test"
    if slot < validation_cut:
        return "validation"
    return "train"


def split_for(game: chess.pgn.Game, validation_pct: float, test_pct: float) -> str:
    return split_for_key(start_key(game), validation_pct, test_pct)


def has_winning_capture(board: chess.Board) -> bool:
    for move in board.generate_legal_captures():
        victim = board.piece_type_at(move.to_square) or chess.PAWN
        attacker = board.piece_type_at(move.from_square)
        if attacker is None:
            continue
        if PIECE_VALUE[victim] > PIECE_VALUE[attacker]:
            return True
        if not board.is_attacked_by(not board.turn, move.to_square):
            return True
    return False


@dataclass
class Reservoir:
    capacity: int
    rng: random.Random

    def __post_init__(self) -> None:
        self.seen = 0
        self.items: list[tuple[str, float, int]] = []

    def offer(self, item: tuple[str, float, int]) -> None:
        self.seen += 1
        if len(self.items) < self.capacity:
            self.items.append(item)
        else:
            pick = self.rng.randrange(self.seen)
            if pick < self.capacity:
                self.items[pick] = item


def allocate(total: int, weights: list[float]) -> list[int]:
    if total < 0 or len(weights) != 5 or any(weight <= 0 for weight in weights):
        raise ValueError("total must be non-negative and five weights positive")
    raw = [total * weight / sum(weights) for weight in weights]
    result = [math.floor(value) for value in raw]
    order = sorted(range(5), key=lambda i: (raw[i] - result[i], -i), reverse=True)
    for index in order[:total - sum(result)]:
        result[index] += 1
    return result


def parse_phase_weights(text: str) -> list[float]:
    try:
        result = [float(item) for item in text.split(",")]
    except ValueError as error:
        raise argparse.ArgumentTypeError("phase weights must be numbers") from error
    if len(result) != 5 or any(item <= 0 for item in result):
        raise argparse.ArgumentTypeError("provide five positive phase weights")
    return result


def process_game(game: chess.pgn.Game, skip_start: int, skip_end: int,
                 max_per_phase: int, max_per_game: int, quiet_filter: bool,
                 rng: random.Random) -> tuple[list[tuple[str, int]], int]:
    if game.headers.get("Result", "*") not in RESULT_MAP:
        return [], 0
    board = game.board()
    nodes = list(game.mainline())
    by_phase: list[list[tuple[str, int]]] = [[] for _ in PHASE_BUCKETS]
    rejected = 0
    for ply, node in enumerate(nodes):
        move = node.move
        if (ply >= skip_start and ply < len(nodes) - skip_end
                and not board.is_check() and not board.is_capture(move)
                and move.promotion is None):
            bucket = phase_bucket(game_phase(board))
            by_phase[bucket].append((board.fen(), bucket))
        board.push(move)

    selected: list[tuple[str, int]] = []
    for candidates in by_phase:
        check_cap = max_per_phase * (3 if quiet_filter else 1)
        if len(candidates) > check_cap:
            candidates = rng.sample(candidates, check_cap)
        if quiet_filter:
            quiet = []
            for item in candidates:
                if has_winning_capture(chess.Board(item[0])):
                    rejected += 1
                else:
                    quiet.append(item)
            candidates = quiet
        if len(candidates) > max_per_phase:
            candidates = rng.sample(candidates, max_per_phase)
        selected.extend(candidates)
    if max_per_game and len(selected) > max_per_game:
        selected = rng.sample(selected, max_per_game)
    return selected, rejected


def input_paths(inputs: list[str]) -> list[Path]:
    result: list[Path] = []
    for source in inputs:
        matches = sorted(glob.glob(source)) or ([source] if os.path.exists(source) else [])
        for match in matches:
            path = Path(match).resolve()
            result.extend(sorted(path.glob("*.pgn")) if path.is_dir() else [path])
    unique = list(dict.fromkeys(result))
    if not unique or any(not path.is_file() for path in unique):
        raise SystemExit("no readable PGN input")
    return unique


def split_counts(train: int, validation_pct: float, test_pct: float) -> dict[str, int]:
    train_fraction = 1.0 - (validation_pct + test_pct) / 100.0
    return {"train": train,
            "validation": round(train * validation_pct / 100.0 / train_fraction),
            "test": round(train * test_pct / 100.0 / train_fraction)}


def make_reservoirs(counts: dict[str, int], weights: list[float], seed: int):
    quotas = {split: allocate(counts[split], weights) for split in SPLITS}
    reservoirs = {
        split: [Reservoir(quota, random.Random(seed ^ (split_index + 1) * 0x9E3779B1
                                               ^ (phase + 1) * 0x85EBCA77))
                for phase, quota in enumerate(quotas[split])]
        for split_index, split in enumerate(SPLITS)
    }
    return quotas, reservoirs


def stage_rows(path: Path, rows: list[tuple[str, float]]) -> Path:
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as output:
        for fen, target in rows:
            output.write(f"{fen};{target:g}\n")
    return temporary


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("pgn", nargs="+")
    result.add_argument("--out-dir", default="tools/texel/data/hce-v1")
    result.add_argument("--target-train", type=int, default=3_000_000)
    result.add_argument("--validation-pct", type=float, default=5.0)
    result.add_argument("--test-pct", type=float, default=5.0)
    result.add_argument("--phase-weights", type=parse_phase_weights,
                        default=parse_phase_weights("1,1,1,1,1"))
    result.add_argument("--max-per-phase-per-game", type=int, default=8)
    result.add_argument("--max-per-game", type=int, default=16)
    result.add_argument("--skip-start", type=int, default=0)
    result.add_argument("--skip-end", type=int, default=6)
    result.add_argument("--seed", type=int, default=5_316_002)
    result.add_argument("--preflight-games", type=int, default=0)
    result.add_argument("--preflight-safety", type=float, default=1.20)
    result.add_argument("--no-quiet-filter", dest="quiet_filter", action="store_false")
    return result


def validate_args(args, command: argparse.ArgumentParser) -> None:
    if args.target_train <= 0 or args.max_per_phase_per_game <= 0 or args.max_per_game <= 0:
        command.error("targets and per-game caps must be positive")
    if args.max_per_game < args.max_per_phase_per_game:
        command.error("max per game cannot be smaller than max per phase")
    if min(args.validation_pct, args.test_pct) < 0 or args.validation_pct + args.test_pct >= 100:
        command.error("validation/test percentages must be non-negative and sum below 100")
    if args.skip_start < 0 or args.skip_end < 0:
        command.error("skip counts cannot be negative")


def main() -> int:
    command = parser()
    args = command.parse_args()
    validate_args(args, command)
    paths = input_paths(args.pgn)
    counts = split_counts(args.target_train, args.validation_pct, args.test_pct)
    quotas, reservoirs = make_reservoirs(counts, args.phase_weights, args.seed)
    seen: set[str] = set()
    unique = {split: [0] * 5 for split in SPLITS}
    split_games = Counter()
    games = recorded_games = skipped = raw = quiet_rejected = parse_errors = 0
    seen_starts: set[str] = set()

    for path in paths:
        print(f"Reading {path}")
        with path.open(encoding="utf-8", errors="replace") as stream:
            while not args.preflight_games or games < args.preflight_games:
                try:
                    game = chess.pgn.read_game(stream)
                except Exception as error:
                    print(f"WARNING: PGN parse error: {error}", file=sys.stderr)
                    parse_errors += 1
                    continue
                if game is None:
                    break
                recorded_games += 1
                opening = start_key(game)
                if opening in seen_starts:
                    continue
                seen_starts.add(opening)
                games += 1
                split = split_for(game, args.validation_pct, args.test_pct)
                split_games[split] += 1
                candidates, rejected = process_game(
                    game, args.skip_start, args.skip_end, args.max_per_phase_per_game,
                    args.max_per_game, args.quiet_filter,
                    random.Random(args.seed ^ start_digest(game)))
                quiet_rejected += rejected
                if not candidates:
                    skipped += 1
                    continue
                raw += len(candidates)
                target = RESULT_MAP[game.headers["Result"]]
                for fen, bucket in candidates:
                    key = fen_key(fen)
                    if key in seen:
                        continue
                    seen.add(key)
                    unique[split][bucket] += 1
                    reservoirs[split][bucket].offer((fen, target, bucket))
        if args.preflight_games and games >= args.preflight_games:
            break

    print(f"Independent starts={games:,} recorded_games={recorded_games:,} "
          f"paired_replays={recorded_games-games:,} skipped={skipped:,} parse_errors={parse_errors:,} "
          f"raw={raw:,} unique={len(seen):,} quiet_rejected={quiet_rejected:,}")
    if args.preflight_games:
        required = 0
        incomplete = False
        print("Preflight by split/phase (safety included):")
        for split in SPLITS:
            for phase, name in enumerate(BUCKET_NAMES):
                rate = unique[split][phase] / max(games, 1)
                estimate = math.ceil(quotas[split][phase] / rate * args.preflight_safety) if rate else math.inf
                if estimate != math.inf:
                    required = max(required, estimate)
                else:
                    incomplete = True
                print(f"  {split:10}/{name:13} rate={rate:7.4f}/game required={estimate:,}")
        if incomplete:
            print("No recommendation: at least one split/phase had zero pilot yield.", file=sys.stderr)
            return 2
        print(f"Recommended total independent games: {required:,}")
        return 0

    short = []
    for split in SPLITS:
        for phase, name in enumerate(BUCKET_NAMES):
            have = len(reservoirs[split][phase].items)
            want = quotas[split][phase]
            print(f"  {split:10}/{name:13}: {have:,}/{want:,} eligible={reservoirs[split][phase].seen:,}")
            if have < want:
                short.append((split, name))
    if short:
        print("ERROR: exact quotas not met; existing outputs unchanged.", file=sys.stderr)
        return 2

    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    staged = []
    output_hashes = {}
    rng = random.Random(args.seed)
    for split in SPLITS:
        rows = [(fen, target) for phase in reservoirs[split]
                for fen, target, _bucket in phase.items]
        rng.shuffle(rows)
        path = out_dir / f"{split}.csv"
        temporary = stage_rows(path, rows)
        staged.append((temporary, path))
        output_hashes[split] = sha256_file(temporary)

    manifest = {
        "schema": "manta-hce-wdl-v2",
        "inputs": [{"path": str(path), "bytes": path.stat().st_size,
                    "sha256": sha256_file(path)} for path in paths],
        "seed": args.seed,
        "independent_starts": games,
        "recorded_games": recorded_games,
        "paired_replays_discarded": recorded_games - games,
        "skipped_games": skipped,
        "games_by_split": dict(split_games),
        "rows": counts,
        "phase_quotas": {split: dict(zip(BUCKET_NAMES, quotas[split])) for split in SPLITS},
        "output_sha256": output_hashes,
        "dedup_fields": 5,
        "filters": {"quiet": args.quiet_filter, "skip_start": args.skip_start,
                    "skip_end": args.skip_end,
                    "max_per_phase_per_game": args.max_per_phase_per_game,
                    "max_per_game": args.max_per_game},
        "label": "white-perspective self-play WDL",
    }
    manifest_tmp = out_dir / "manifest.json.tmp"
    manifest_tmp.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    for temporary, path in staged:
        os.replace(temporary, path)
    os.replace(manifest_tmp, out_dir / "manifest.json")
    print(f"Published {sum(counts.values()):,} rows under {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
