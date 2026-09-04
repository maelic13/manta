#!/usr/bin/env python3
"""Score an actual compiled HCE dataset without fitting or opening another split."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import numpy as np

import fit


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vector", required=True)
    parser.add_argument("--dataset-prefix", required=True)
    parser.add_argument("--k", type=float, required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--batch-samples", type=int, default=32768)
    parser.add_argument("--require-below", type=float)
    args = parser.parse_args()
    if args.k <= 0 or args.batch_samples <= 0:
        parser.error("K and batch size must be positive")

    vector_path = Path(args.vector)
    out_path = Path(args.out)
    if out_path.exists():
        raise FileExistsError(f"refusing to overwrite {out_path}")
    schema, _names, values, _statuses, _units = fit.read_vector(vector_path)
    dataset = fit.Dataset(args.dataset_prefix, schema, len(values))
    loss, phases, counts = fit.loss_report(
        dataset, np.zeros(len(values), dtype=np.float64), args.k, args.batch_samples)
    accepted = args.require_below is None or loss < args.require_below
    report = {
        "schema": "manta-hce-actual-loss-v1",
        "parameter_schema": schema,
        "vector": {"path": str(vector_path.resolve()), "sha256": fit.sha256(vector_path)},
        "dataset": dataset.hashes(),
        "k": args.k,
        "samples": int(len(dataset.samples)),
        "loss": loss,
        "phase": fit.phase_dict(phases, counts),
        "require_below": args.require_below,
        "accepted": accepted,
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = out_path.with_name(out_path.name + ".tmp")
    temporary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    os.replace(temporary, out_path)
    print(f"actual loss={loss:.9f} samples={len(dataset.samples):,} accepted={accepted}")
    print(f"report -> {out_path.resolve()}")
    return 0 if accepted else 2


if __name__ == "__main__":
    raise SystemExit(main())
