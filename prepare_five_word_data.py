"""Select expert NPY classes and process signer_[angle_]word team videos."""

import argparse
import json
from pathlib import Path

from migrate_expert_npy import migrate
from audit_five_word_data import audit
from modules.preprocessing import run_preprocessing
from modules.vocabulary import LABEL_MAP, WORDS


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-data", type=Path, default=Path("data"))
    parser.add_argument("--raw-mov", type=Path, default=Path.home() / "Downloads" / "raw_mov")
    parser.add_argument("--project-dir", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--processed-root", type=Path, default=Path("data/processed_five"))
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()
    root = args.processed_root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    (root / "core_label_map.json").write_text(json.dumps(LABEL_MAP, indent=2), encoding="utf-8")
    (root / "core_ksl_word_dictionary.json").write_text(
        json.dumps(WORDS, ensure_ascii=False, indent=2), encoding="utf-8")
    manifest = root / "manifest.csv"
    if args.overwrite or not manifest.exists():
        count, _ = migrate(args.source_data / "X_train.npy", args.source_data / "y_train.npy",
                           root, overwrite=args.overwrite)
        print(f"Selected {count} expert sequences", flush=True)
    processed, failed = run_preprocessing(args.project_dir.resolve(), root / "raw_videos",
                                         root, ("team",), args.overwrite,
                                         args.raw_mov.resolve())
    if failed:
        raise RuntimeError(f"{failed} video(s) failed; inspect preprocessing_failures.txt")
    print(f"Team: {processed} clips; manifest: {manifest}", flush=True)
    audit(root)


if __name__ == "__main__":
    main()
