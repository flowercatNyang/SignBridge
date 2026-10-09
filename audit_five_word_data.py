"""Count processed samples and record resampled hand-detection coverage."""

import argparse
import csv
import json
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

from modules.vocabulary import LABEL_MAP, WORDS


def audit(root):
    root = Path(root)
    with (root / "manifest.csv").open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    counts = Counter((row["domain"], row["class_key"]) for row in rows)
    signer_counts = Counter(row["signer_id"] for row in rows if row["domain"] == "team")
    coverage = defaultdict(list)
    low_coverage = []
    for row in rows:
        with np.load(root / row["path"]) as archive:
            sequence = archive["x"]
        if sequence.shape != (30, 452) or not np.isfinite(sequence).all():
            raise ValueError(f"Invalid sequence {row['path']}")
        if row["domain"] == "team":
            ratio = float(np.mean(np.any(sequence[:, -2:] > 0.5, axis=1)))
            coverage[row["signer_id"]].append(ratio)
            if ratio < 0.5:
                low_coverage.append({"source_video": row["source_video"],
                                     "word": WORDS[row["class_key"]],
                                     "resampled_any_hand_fraction": ratio})
    report = {
        "samples": len(rows), "shape": [30, 452], "all_finite": True,
        "class_counts": {WORDS[key]: {domain: counts[domain, key] for domain in ("expert", "team")}
                         for key in LABEL_MAP},
        "signer_counts": dict(signer_counts),
        "resampled_any_hand_fraction_by_signer": {
            signer: float(np.mean(ratios)) for signer, ratios in coverage.items()},
        "low_coverage_clips": low_coverage,
        "coverage_note": "This measures resampled masks over the entire clip, including preparation/rest frames; it is not detector accuracy.",
    }
    (root / "dataset_summary.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--processed-root", type=Path, default=Path("data/processed_five"))
    args = parser.parse_args()
    report = audit(args.processed_root)
    print(json.dumps({key: value for key, value in report.items() if key != "low_coverage_clips"},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
