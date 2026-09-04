#!/usr/bin/env python3
"""Fit only MAN-E20's context-weighted space coefficient.

This selection-aware tool deliberately has no frozen-test input. It finds the
unconstrained training optimum for space_bonus[0], rounds it explicitly, and
uses validation only for the prospectively registered MAN-E20 filters.
"""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path

import numpy as np

import fit


TARGET = "space_bonus[0]"
K_VALUE = 1.62679234682616
MINIMUM_VALIDATION_IMPROVEMENT = 0.000200
MAXIMUM_PHASE_REGRESSION = 0.001
MINIMUM_FLOAT_OPTIMUM = 0.5
I16_MIN = -32768.0
I16_MAX = 32767.0


def selected_signal(dataset: fit.Dataset, index: int, batch: int) -> tuple[np.ndarray, int]:
    """Return each sample's complete linear multiplier for one coefficient."""
    signal = np.zeros(len(dataset.samples), dtype=np.float64)
    support = 0
    cursor = 0
    for samples, events, sample_ids in fit.chunks(dataset, batch):
        selected = np.asarray(events["index"] == index)
        support += int(np.count_nonzero(selected))
        if selected.any():
            weights = np.asarray(events["coefficient"][selected], dtype=np.float64)
            selected_samples = sample_ids[selected]
            signal[cursor:cursor + len(samples)] = np.bincount(
                selected_samples, weights=weights, minlength=len(samples))
        cursor += len(samples)
    return signal, support


def scalar_loss(base_scores: np.ndarray, targets: np.ndarray, signal: np.ndarray,
                base_value: float, value: float, k_value: float = K_VALUE) -> float:
    scores = base_scores + (value - base_value) * signal
    error = targets - fit.sigmoid(scores, k_value)
    return float(np.mean(error * error))


def expanding_bracket(objective, start: float, direction: float,
                      first_loss: float) -> tuple[float, float]:
    previous = start
    current = start + direction
    current_loss = first_loss
    step = 1.0
    boundary = I16_MAX if direction > 0 else I16_MIN
    while current != boundary:
        step *= 2.0
        following = min(start + step, boundary) if direction > 0 else max(start - step, boundary)
        following_loss = objective(following)
        if following_loss > current_loss:
            return min(previous, following), max(previous, following)
        previous = current
        current = following
        current_loss = following_loss
    raise RuntimeError("training optimum reached the i16 representation boundary")


def golden_minimum(objective, lower: float, upper: float) -> tuple[float, float]:
    inverse_phi = (math.sqrt(5.0) - 1.0) / 2.0
    left = upper - inverse_phi * (upper - lower)
    right = lower + inverse_phi * (upper - lower)
    left_loss = objective(left)
    right_loss = objective(right)
    for _ in range(80):
        if upper - lower <= 1e-8:
            break
        if left_loss <= right_loss:
            upper, right, right_loss = right, left, left_loss
            left = upper - inverse_phi * (upper - lower)
            left_loss = objective(left)
        else:
            lower, left, left_loss = left, right, right_loss
            right = lower + inverse_phi * (upper - lower)
            right_loss = objective(right)
    value = (lower + upper) / 2.0
    return value, objective(value)


def unconstrained_optimum(objective, start: float) -> tuple[float, float]:
    if not I16_MIN < start < I16_MAX:
        raise ValueError("starting coefficient is outside the searchable i16 interior")
    center_loss = objective(start)
    left_loss = objective(start - 1.0)
    right_loss = objective(start + 1.0)
    brackets = []
    if left_loss < center_loss:
        brackets.append(expanding_bracket(objective, start, -1.0, left_loss))
    if right_loss < center_loss:
        brackets.append(expanding_bracket(objective, start, 1.0, right_loss))
    if not brackets:
        brackets.append((start - 1.0, start + 1.0))
    candidates = [golden_minimum(objective, lower, upper) for lower, upper in brackets]
    candidates.append((start, center_loss))
    return min(candidates, key=lambda candidate: candidate[1])


def round_half_up(value: float) -> int:
    """Round ties toward positive infinity; in particular, map 0.5 to one."""
    return math.floor(value + 0.5)


def array_loss_report(base_scores: np.ndarray, targets: np.ndarray, phases: np.ndarray,
                      signal: np.ndarray, base_value: float, value: float):
    scores = base_scores + (value - base_value) * signal
    error = targets - fit.sigmoid(scores, K_VALUE)
    squared = error * error
    buckets = fit.phase_bucket(phases)
    counts = np.bincount(buckets, minlength=5).astype(np.int64)
    sums = np.bincount(buckets, weights=squared, minlength=5)
    losses = np.divide(sums, counts, out=np.full(5, np.nan), where=counts != 0)
    return float(np.mean(squared)), losses, counts


def gate_failures(optimum: float, base_loss: float, rounded_loss: float,
                  base_phases: np.ndarray, rounded_phases: np.ndarray,
                  phase_counts: np.ndarray) -> list[str]:
    failures = []
    if optimum < MINIMUM_FLOAT_OPTIMUM:
        failures.append(
            f"float optimum {optimum:.9f} is below {MINIMUM_FLOAT_OPTIMUM:.1f}")
    improvement = base_loss - rounded_loss
    if improvement < MINIMUM_VALIDATION_IMPROVEMENT:
        failures.append(
            f"validation improvement {improvement:.9f} is below "
            f"{MINIMUM_VALIDATION_IMPROVEMENT:.6f}")
    regressions = [
        fit.PHASE_NAMES[index]
        for index in range(len(fit.PHASE_NAMES))
        if phase_counts[index]
        and rounded_phases[index] > base_phases[index] * (1.0 + MAXIMUM_PHASE_REGRESSION)
    ]
    if regressions:
        failures.append(f"validation phase regression exceeds 0.1%: {regressions}")
    return failures


def write_report(path: Path, report: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vector", required=True)
    parser.add_argument("--train-prefix", required=True)
    parser.add_argument("--validation-prefix", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--batch-samples", type=int, default=32768)
    args = parser.parse_args()
    if args.batch_samples <= 0:
        parser.error("batch size must be positive")

    vector_path = Path(args.vector)
    out_path = Path(args.out)
    report_path = Path(str(out_path) + ".report.json")
    if out_path.exists() or report_path.exists():
        raise FileExistsError("output vector/report already exists")

    schema, names, base, statuses, units = fit.read_vector(vector_path)
    if schema != "manta-hce-fit-v3":
        raise ValueError(f"MAN-E20 requires manta-hce-fit-v3, found {schema}")
    if names.count(TARGET) != 1:
        raise ValueError(f"expected exactly one {TARGET} row")
    index = names.index(TARGET)
    if statuses[index] != "free":
        raise ValueError(f"{TARGET} is not a free coefficient")
    base_value = float(base[index])

    train = fit.Dataset(args.train_prefix, schema, len(base))
    validation = fit.Dataset(args.validation_prefix, schema, len(base))
    train_signal, train_support = selected_signal(train, index, args.batch_samples)
    validation_signal, validation_support = selected_signal(validation, index, args.batch_samples)
    if train_support == 0 or validation_support == 0:
        raise ValueError(
            f"{TARGET} lacks support: train={train_support}, validation={validation_support}")

    train_base = np.asarray(train.samples["base"], dtype=np.float64)
    train_targets = np.asarray(train.samples["target"], dtype=np.float64)
    objective = lambda value: scalar_loss(
        train_base, train_targets, train_signal, base_value, value)
    optimum, optimum_train_loss = unconstrained_optimum(objective, base_value)

    validation_base = np.asarray(validation.samples["base"], dtype=np.float64)
    validation_targets = np.asarray(validation.samples["target"], dtype=np.float64)
    validation_phases = np.asarray(validation.samples["phase"], dtype=np.uint8)
    base_loss, base_phases, phase_counts = array_loss_report(
        validation_base, validation_targets, validation_phases,
        validation_signal, base_value, base_value)

    rounded = round_half_up(optimum)
    rounded_loss, rounded_phases, _ = array_loss_report(
        validation_base, validation_targets, validation_phases,
        validation_signal, base_value, float(rounded))
    failures = gate_failures(
        optimum, base_loss, rounded_loss, base_phases, rounded_phases, phase_counts)

    report = {
        "schema": "manta-man-e20-fit-report-v1",
        "parameter_schema": schema,
        "parameter": TARGET,
        "vector_input": {"path": str(vector_path.resolve()), "sha256": fit.sha256(vector_path)},
        "datasets": {"train": train.hashes(), "validation": validation.hashes()},
        "settings": {
            "k": K_VALUE,
            "batch_samples": args.batch_samples,
            "minimum_float_optimum": MINIMUM_FLOAT_OPTIMUM,
            "minimum_validation_improvement": MINIMUM_VALIDATION_IMPROVEMENT,
            "maximum_phase_regression": MAXIMUM_PHASE_REGRESSION,
            "rounding": "half-up after positive-optimum gate",
        },
        "support": {"train_events": train_support, "validation_events": validation_support},
        "training": {
            "base_value": base_value,
            "float_optimum": optimum,
            "base_loss": objective(base_value),
            "float_optimum_loss": optimum_train_loss,
        },
        "validation": {
            "base_loss": base_loss,
            "rounded_value": rounded,
            "rounded_loss": rounded_loss,
            "improvement": base_loss - rounded_loss,
            "base_phase": fit.phase_dict(base_phases, phase_counts),
            "rounded_phase": fit.phase_dict(rounded_phases, phase_counts),
        },
        "accepted_offline": not failures,
        "failures": failures,
    }

    if failures:
        write_report(report_path, report)
        print("MAN-E20 refuted before binaries:")
        for failure in failures:
            print(f"- {failure}")
        print(f"report -> {report_path}")
        return 2

    candidate = base.copy()
    candidate[index] = rounded
    changed = np.flatnonzero(candidate != base)
    if not np.array_equal(changed, np.asarray([index])):
        raise RuntimeError("candidate must change only space_bonus[0]")
    vector_tmp = fit.stage_vector(out_path, schema, names, candidate, statuses, units)
    report["output_vector_sha256"] = fit.sha256(vector_tmp)
    os.replace(vector_tmp, out_path)
    write_report(report_path, report)
    print(
        f"MAN-E20 passed offline filters: {TARGET} {int(base_value)} -> {rounded}; "
        f"validation improvement={base_loss - rounded_loss:.9f}")
    print(f"vector -> {out_path}")
    print(f"report -> {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
