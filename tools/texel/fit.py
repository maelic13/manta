#!/usr/bin/env python3
"""Fit Manta HCE schema-v2 free weights from compiled sparse WDL datasets."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
import os
from pathlib import Path

import numpy as np


PHASE_NAMES = ("deep_endgame", "endgame", "middlegame", "early_mid", "opening")
# These are feature-identity constraints, not tuned priors. Each coefficient
# multiplies a non-negative count whose direction is part of the evaluator's
# documented chess meaning. Crossing zero would silently turn protection or
# space into its opposite while still improving an aggregate correlated loss.
SEMANTIC_BOUNDS = {
    "king_pawn_proximity[0]": (None, -1.0),
    "space_bonus[0]": (1.0, None),
}
SAMPLE_DTYPE = np.dtype({
    "names": ("offset", "base", "target", "count", "phase", "reserved"),
    "formats": ("<u8", "<f4", "<f4", "<u2", "u1", "u1"),
    "offsets": (0, 8, 12, 16, 18, 19),
    "itemsize": 20,
})
EVENT_DTYPE = np.dtype({
    "names": ("index", "reserved", "coefficient"),
    "formats": ("<u2", "<u2", "<f4"),
    "offsets": (0, 2, 4),
    "itemsize": 8,
})


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def read_kv(path: Path) -> dict[str, str]:
    result = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw:
            continue
        key, value = raw.split("\t", 1)
        result[key] = value
    return result


class Dataset:
    def __init__(self, prefix: str, expected_schema: str, coefficients: int):
        self.prefix = Path(prefix)
        self.samples_path = Path(prefix + ".samples.bin")
        self.events_path = Path(prefix + ".events.bin")
        self.manifest_path = Path(prefix + ".manifest")
        manifest = read_kv(self.manifest_path)
        if manifest.get("schema") != expected_schema or manifest.get("dataset") != "manta-hce-sparse-v1":
            raise ValueError(f"schema mismatch in {self.manifest_path}")
        if int(manifest["coefficients"]) != coefficients:
            raise ValueError(f"coefficient mismatch in {self.manifest_path}")
        if int(manifest["sample_record_bytes"]) != SAMPLE_DTYPE.itemsize:
            raise ValueError("sample record size mismatch")
        if int(manifest["event_record_bytes"]) != EVENT_DTYPE.itemsize:
            raise ValueError("event record size mismatch")
        sample_count = int(manifest["samples"])
        event_count = int(manifest["events"])
        if self.samples_path.stat().st_size != sample_count * SAMPLE_DTYPE.itemsize:
            raise ValueError(f"sample file size mismatch: {self.samples_path}")
        if self.events_path.stat().st_size != event_count * EVENT_DTYPE.itemsize:
            raise ValueError(f"event file size mismatch: {self.events_path}")
        self.samples = np.memmap(self.samples_path, dtype=SAMPLE_DTYPE, mode="r")
        self.events = np.memmap(self.events_path, dtype=EVENT_DTYPE, mode="r")
        if len(self.samples) == 0:
            raise ValueError(f"empty dataset: {prefix}")

    def hashes(self) -> dict[str, str]:
        return {"manifest": sha256(self.manifest_path),
                "samples": sha256(self.samples_path),
                "events": sha256(self.events_path)}


def read_vector(path: Path):
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines:
        raise ValueError("empty vector")
    schema = lines[0]
    names, values, statuses, units = [], [], [], []
    for line in lines[1:]:
        if not line:
            continue
        fields = line.split("\t")
        if len(fields) != 4:
            raise ValueError(f"bad vector row: {line}")
        name, value, status, unit = fields
        if status not in ("free", "fixed", "excluded"):
            raise ValueError(f"bad status for {name}")
        names.append(name)
        values.append(float(value))
        statuses.append(status)
        units.append(unit)
    return schema, names, np.asarray(values, dtype=np.float64), np.asarray(statuses), units


def sigmoid(score: np.ndarray, k_value: float) -> np.ndarray:
    exponent = np.clip(-k_value * score / 400.0, -60.0, 60.0)
    return 1.0 / (1.0 + np.exp(exponent))


def phase_bucket(phase: np.ndarray) -> np.ndarray:
    return np.select((phase <= 2, phase <= 7, phase <= 13, phase <= 19),
                     (0, 1, 2, 3), default=4).astype(np.int8)


def chunks(dataset: Dataset, batch: int):
    for start in range(0, len(dataset.samples), batch):
        end = min(start + batch, len(dataset.samples))
        samples = dataset.samples[start:end]
        first = int(samples["offset"][0])
        last = int(samples["offset"][-1]) + int(samples["count"][-1])
        events = dataset.events[first:last]
        counts = np.asarray(samples["count"], dtype=np.int64)
        sample_ids = np.repeat(np.arange(len(samples), dtype=np.int32), counts)
        yield samples, events, sample_ids


def scores_for(samples, events, sample_ids, delta: np.ndarray) -> np.ndarray:
    scores = np.asarray(samples["base"], dtype=np.float64).copy()
    if len(events):
        contribution = np.asarray(events["coefficient"], dtype=np.float64) * delta[events["index"]]
        scores += np.bincount(sample_ids, weights=contribution, minlength=len(samples))
    return scores


def loss_report(dataset: Dataset, delta: np.ndarray, k_value: float, batch: int):
    total = 0.0
    count = 0
    phase_sum = np.zeros(5, dtype=np.float64)
    phase_count = np.zeros(5, dtype=np.int64)
    for samples, events, sample_ids in chunks(dataset, batch):
        scores = scores_for(samples, events, sample_ids, delta)
        error = np.asarray(samples["target"], dtype=np.float64) - sigmoid(scores, k_value)
        squared = error * error
        total += float(squared.sum())
        count += len(samples)
        buckets = phase_bucket(samples["phase"])
        phase_sum += np.bincount(buckets, weights=squared, minlength=5)
        phase_count += np.bincount(buckets, minlength=5)
    losses = np.divide(phase_sum, phase_count, out=np.full(5, np.nan), where=phase_count != 0)
    return total / count, losses, phase_count


def fit_k(dataset: Dataset) -> float:
    scores = np.asarray(dataset.samples["base"], dtype=np.float64)
    targets = np.asarray(dataset.samples["target"], dtype=np.float64)
    low, high = 0.5, 2.5
    for _ in range(50):
        first = low + (high - low) / 3.0
        second = high - (high - low) / 3.0
        first_loss = np.mean((targets - sigmoid(scores, first)) ** 2)
        second_loss = np.mean((targets - sigmoid(scores, second)) ** 2)
        if first_loss < second_loss:
            high = second
        else:
            low = first
    return (low + high) / 2.0


def support(dataset: Dataset, coefficients: int, batch: int) -> np.ndarray:
    result = np.zeros(coefficients, dtype=np.int64)
    for _samples, events, _sample_ids in chunks(dataset, batch):
        result += np.bincount(events["index"], minlength=coefficients)
    return result


def constrained_bounds(names: list[str], base: np.ndarray, max_delta: float):
    lower = np.maximum(-32768.0, base - max_delta)
    upper = np.minimum(32767.0, base + max_delta)
    applied = []
    for index, name in enumerate(names):
        bounds = SEMANTIC_BOUNDS.get(name)
        if name.startswith("king_protector["):
            bounds = (None, -1.0)
        if bounds is None:
            continue
        minimum, maximum = bounds
        if minimum is not None:
            lower[index] = max(lower[index], minimum)
        if maximum is not None:
            upper[index] = min(upper[index], maximum)
        if lower[index] > upper[index] or not lower[index] <= base[index] <= upper[index]:
            raise ValueError(f"base value violates semantic bounds: {name}={base[index]}")
        applied.append({"name": name, "minimum": minimum, "maximum": maximum})
    return lower, upper, applied


def gradient_range(dataset: Dataset, start: int, end: int, delta: np.ndarray,
                   k_value: float, coefficients: int):
    samples = dataset.samples[start:end]
    first = int(samples["offset"][0])
    last = int(samples["offset"][-1]) + int(samples["count"][-1])
    events = dataset.events[first:last]
    counts = np.asarray(samples["count"], dtype=np.int64)
    sample_ids = np.repeat(np.arange(len(samples), dtype=np.int32), counts)
    scores = scores_for(samples, events, sample_ids, delta)
    prediction = sigmoid(scores, k_value)
    target = np.asarray(samples["target"], dtype=np.float64)
    error = target - prediction
    derivative = -2.0 * error * prediction * (1.0 - prediction) * (k_value / 400.0)
    result = np.zeros(coefficients, dtype=np.float64)
    if len(events):
        weights = np.asarray(events["coefficient"], dtype=np.float64) * derivative[sample_ids]
        result += np.bincount(events["index"], weights=weights, minlength=coefficients)
    return result, float(np.dot(error, error)), len(samples)


def gradient(dataset: Dataset, delta: np.ndarray, k_value: float,
             coefficients: int, batch: int, executor: ThreadPoolExecutor | None = None):
    result = np.zeros(coefficients, dtype=np.float64)
    total_loss = 0.0
    total_count = 0
    ranges = [(start, min(start + batch, len(dataset.samples)))
              for start in range(0, len(dataset.samples), batch)]

    def evaluate(bounds):
        return gradient_range(dataset, bounds[0], bounds[1], delta, k_value, coefficients)

    partials = map(evaluate, ranges) if executor is None else executor.map(evaluate, ranges)
    # Executor.map preserves range order. Ordered reduction keeps a fixed result
    # for a fixed dataset, batch size and worker count.
    for partial, loss, count in partials:
        result += partial
        total_loss += loss
        total_count += count
    return result / total_count, total_loss / total_count


def stage_vector(path: Path, schema: str, names: list[str], values: np.ndarray,
                 statuses: np.ndarray, units: list[str]) -> Path:
    if path.exists():
        raise FileExistsError(f"refusing to overwrite {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as output:
        output.write(schema + "\n")
        for name, value, status, unit in zip(names, values, statuses, units):
            output.write(f"{name}\t{int(value)}\t{status}\t{unit}\n")
    return temporary


def phase_dict(losses: np.ndarray, counts: np.ndarray) -> dict:
    return {name: {"loss": None if math.isnan(float(losses[index])) else float(losses[index]),
                   "positions": int(counts[index])}
            for index, name in enumerate(PHASE_NAMES)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vector", required=True)
    parser.add_argument("--train-prefix", required=True)
    parser.add_argument("--validation-prefix", required=True)
    parser.add_argument("--test-prefix", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--epochs", type=int, default=200)
    parser.add_argument("--learning-rate", type=float, default=0.3)
    parser.add_argument("--lr-decay", type=float, default=1.0,
                        help="per-epoch multiplicative learning-rate decay; 1.0 disables it "
                             "and reproduces the undecayed schedule exactly")
    parser.add_argument("--l2", type=float, default=1e-6)
    parser.add_argument("--patience", type=int, default=30)
    parser.add_argument("--batch-samples", type=int, default=32768)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--min-train-support", type=int, default=300)
    parser.add_argument("--min-validation-support", type=int, default=50)
    parser.add_argument("--max-delta", type=float, default=512.0)
    parser.add_argument("--max-phase-regression", type=float, default=0.001,
                        help="maximum relative frozen-test phase loss regression")
    args = parser.parse_args()
    if min(args.epochs, args.patience, args.batch_samples, args.jobs) <= 0:
        parser.error("epochs, patience, batch size and jobs must be positive")
    if min(args.learning_rate, args.l2, args.max_delta, args.max_phase_regression) < 0:
        parser.error("numeric controls cannot be negative")
    if not 0.0 < args.lr_decay <= 1.0:
        parser.error("lr-decay must be in (0, 1]")

    vector_path = Path(args.vector)
    out_path = Path(args.out)
    report_path = Path(str(out_path) + ".report.json")
    if out_path.exists() or report_path.exists():
        raise FileExistsError("output vector/report already exists")
    schema, names, base, statuses, units = read_vector(vector_path)
    coefficients = len(base)
    train = Dataset(args.train_prefix, schema, coefficients)
    validation = Dataset(args.validation_prefix, schema, coefficients)
    test = Dataset(args.test_prefix, schema, coefficients)
    k_value = fit_k(validation)
    train_support = support(train, coefficients, args.batch_samples)
    validation_support = support(validation, coefficients, args.batch_samples)
    active = ((statuses == "free") & (train_support >= args.min_train_support)
              & (validation_support >= args.min_validation_support))
    print(f"schema={schema} coefficients={coefficients} active={int(active.sum())} "
          f"train={len(train.samples):,} validation={len(validation.samples):,} "
          f"test={len(test.samples):,} K={k_value:.8f}")
    if not active.any():
        raise ValueError("no adequately supported free coefficient")

    weights = base.copy()
    best = weights.copy()
    moment = np.zeros(coefficients, dtype=np.float64)
    variance = np.zeros(coefficients, dtype=np.float64)
    zero = np.zeros(coefficients, dtype=np.float64)
    base_validation, base_validation_phase, validation_counts = loss_report(
        validation, zero, k_value, args.batch_samples)
    best_validation = base_validation
    final_validation = base_validation
    best_epoch = 0
    last_epoch = 0
    stale = 0
    lower, upper, semantic_bounds = constrained_bounds(names, base, args.max_delta)
    executor = ThreadPoolExecutor(max_workers=args.jobs) if args.jobs > 1 else None
    try:
        for epoch in range(1, args.epochs + 1):
            last_epoch = epoch
            delta = weights - base
            grad, train_loss = gradient(
                train, delta, k_value, coefficients, args.batch_samples, executor)
            grad += 2.0 * args.l2 * delta
            grad[~active] = 0.0
            moment = 0.9 * moment + 0.1 * grad
            variance = 0.999 * variance + 0.001 * grad * grad
            corrected_m = moment / (1.0 - 0.9 ** epoch)
            corrected_v = variance / (1.0 - 0.999 ** epoch)
            # At the default decay of 1.0 this is exactly args.learning_rate,
            # so an undecayed run reproduces its previous result bit for bit.
            rate = args.learning_rate * (args.lr_decay ** (epoch - 1))
            weights[active] -= (
                rate * corrected_m[active]
                / (np.sqrt(corrected_v[active]) + 1e-8))
            weights = np.clip(weights, lower, upper)
            validation_loss, _phase, _counts = loss_report(
                validation, weights - base, k_value, args.batch_samples)
            final_validation = validation_loss
            if validation_loss < best_validation:
                best_validation = validation_loss
                best_epoch = epoch
                best = weights.copy()
                stale = 0
            else:
                stale += 1
            if epoch == 1 or epoch % 10 == 0 or stale >= args.patience or epoch == args.epochs:
                print(f"epoch={epoch:4d} train={train_loss:.9f} validation={validation_loss:.9f} "
                      f"best={best_validation:.9f}@{best_epoch}")
            if stale >= args.patience:
                break
    finally:
        if executor is not None:
            executor.shutdown()

    rounded = base.copy()
    rounded[active] = np.rint(best[active])
    rounded = np.clip(rounded, lower, upper)
    rounded_validation, rounded_validation_phase, _ = loss_report(
        validation, rounded - base, k_value, args.batch_samples)
    if rounded_validation >= base_validation:
        raise RuntimeError("rounded vector does not improve validation loss")

    # The frozen test is first read for scoring only after K, active support,
    # epoch selection and integer rounding are final.
    base_test, base_test_phase, test_counts = loss_report(test, zero, k_value, args.batch_samples)
    fitted_test, fitted_test_phase, _ = loss_report(
        test, rounded - base, k_value, args.batch_samples)
    regressions = []
    for index, name in enumerate(PHASE_NAMES):
        if test_counts[index] and fitted_test_phase[index] > base_test_phase[index] * (1.0 + args.max_phase_regression):
            regressions.append(name)
    print(f"frozen_test base={base_test:.9f} fitted={fitted_test:.9f} "
          f"delta={fitted_test-base_test:+.9f}")
    if fitted_test >= base_test or regressions:
        raise RuntimeError(f"frozen-test refutation: aggregate={fitted_test-base_test:+.9f}, "
                           f"phase_regressions={regressions}")

    moved = np.flatnonzero(rounded != base)
    report = {
        "schema": "manta-hce-fit-report-v3",
        "parameter_schema": schema,
        "vector_input": {"path": str(vector_path.resolve()), "sha256": sha256(vector_path)},
        "datasets": {"train": train.hashes(), "validation": validation.hashes(), "test": test.hashes()},
        "settings": vars(args),
        "semantic_bounds": semantic_bounds,
        "k": k_value,
        "active_coefficients": int(active.sum()),
        "unsupported_free_coefficients": int(((statuses == "free") & ~active).sum()),
        "unsupported": [
            {"name": names[index], "train_events": int(train_support[index]),
             "validation_events": int(validation_support[index])}
            for index in np.flatnonzero((statuses == "free") & ~active)
        ],
        "best_epoch": best_epoch,
        "last_epoch": last_epoch,
        # A run whose final loss is far above its best never settled: the
        # trajectory passed through the reported minimum instead of converging
        # on it. Rank configurations on the settled value, not the minimum.
        "validation": {"base_loss": base_validation, "float_best_loss": best_validation,
                       "final_loss": final_validation,
                       "rounded_loss": rounded_validation,
                       "base_phase": phase_dict(base_validation_phase, validation_counts),
                       "rounded_phase": phase_dict(rounded_validation_phase, validation_counts)},
        "frozen_test": {"base_loss": base_test, "fitted_loss": fitted_test,
                        "base_phase": phase_dict(base_test_phase, test_counts),
                        "fitted_phase": phase_dict(fitted_test_phase, test_counts)},
        "moved_coefficients": int(len(moved)),
        "largest_deltas": sorted(
            ({"name": names[index], "from": int(base[index]), "to": int(rounded[index]),
              "delta": int(rounded[index] - base[index])} for index in moved),
            key=lambda item: abs(item["delta"]), reverse=True)[:100],
    }
    vector_tmp = stage_vector(out_path, schema, names, rounded, statuses, units)
    report["output_vector_sha256"] = sha256(vector_tmp)
    report_tmp = report_path.with_name(report_path.name + ".tmp")
    report_tmp.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    os.replace(vector_tmp, out_path)
    os.replace(report_tmp, report_path)
    print(f"accepted offline vector: moved={len(moved)} -> {out_path}")
    print(f"report -> {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
