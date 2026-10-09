import argparse
import json
import os
from pathlib import Path

import numpy as np

from modules.migration import convert_expert_sequence
from modules.preprocessing import load_manifest, validate_counts, write_manifest


def validate_inputs(features, labels, label_map):
    if features.ndim != 3:
        raise ValueError(f"X must have shape [N, T, C], found {features.shape}")
    if labels.ndim != 1:
        raise ValueError(f"y must have shape [N], found {labels.shape}")
    if len(features) != len(labels):
        raise ValueError(f"X has {len(features)} samples but y has {len(labels)}")
    if len(label_map) != 73 or set(label_map.values()) != set(range(73)):
        raise ValueError("core_label_map.json must contain contiguous labels 0..72")
    if not np.issubdtype(labels.dtype, np.integer):
        if not np.isfinite(labels).all() or not np.equal(labels, labels.astype(np.int64)).all():
            raise ValueError("y must contain integer class labels")
    labels = labels.astype(np.int64)
    if np.any((labels < 0) | (labels >= 73)):
        raise ValueError("y contains a label outside 0..72")
    counts = np.bincount(labels, minlength=73)
    missing = [f"label {index}: {count} found, 50 required" for index, count in enumerate(counts) if count < 50]
    if missing:
        raise ValueError("Expert count validation failed:\n" + "\n".join(missing[:20]))
    return labels


def migrate(x_path, y_path, processed_root, overwrite=False):
    processed_root = Path(processed_root)
    label_map_path = processed_root / "core_label_map.json"
    with label_map_path.open("r", encoding="utf-8") as handle:
        label_map = json.load(handle)
    index_to_key = {label: class_key for class_key, label in label_map.items()}

    features = np.load(x_path, mmap_mode="r")
    raw_labels = np.load(y_path, mmap_mode="r")
    labels = validate_inputs(features, raw_labels, label_map)

    manifest_path = processed_root / "manifest.csv"
    existing = load_manifest(manifest_path)
    if any(row["domain"] == "expert" for row in existing) and not overwrite:
        raise FileExistsError(
            "Expert rows already exist in manifest.csv. Use --overwrite to replace them."
        )

    rows = [row for row in existing if row["domain"] != "expert"]
    expert_rows = []
    for index, label in enumerate(labels):
        class_key = index_to_key[int(label)]
        output_path = (
            processed_root
            / "sequences"
            / "expert"
            / class_key
            / "expert_unknown"
            / f"expert_{index:06d}.npz"
        )
        if overwrite or not output_path.exists():
            sequence = convert_expert_sequence(features[index])
            output_path.parent.mkdir(parents=True, exist_ok=True)
            np.savez_compressed(output_path, x=sequence)
        expert_rows.append(
            {
                "path": os.path.relpath(output_path, processed_root),
                "label": int(label),
                "class_key": class_key,
                "domain": "expert",
                "signer_id": "expert_unknown",
                "source_video": f"{Path(x_path).resolve()}#{index}",
            }
        )

    rows.extend(expert_rows)
    validate_counts(rows, label_map, {"expert"})
    write_manifest(manifest_path, rows)
    return len(expert_rows), manifest_path


def main():
    parser = argparse.ArgumentParser(
        description="Migrate legacy expert X/y NPY files to per-sample NPZ files"
    )
    parser.add_argument("--x", type=Path, default=Path("data/processed/X_train.npy"))
    parser.add_argument("--y", type=Path, default=Path("data/processed/y_train.npy"))
    parser.add_argument("--processed-root", type=Path, default=Path("data/processed"))
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()

    count, manifest_path = migrate(
        args.x.resolve(),
        args.y.resolve(),
        args.processed_root.resolve(),
        args.overwrite,
    )
    print(f"Migrated {count} expert samples.")
    print(f"Manifest: {manifest_path}")


if __name__ == "__main__":
    main()
