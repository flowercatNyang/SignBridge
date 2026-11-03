"""Prepare expert and team sequences for the active vocabulary profile."""

import argparse
import json
from pathlib import Path
import sys

# Keep direct CLI execution independent of the working directory.
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.data.migrate_expert_npy import migrate
from scripts.data.audit_dataset import audit
from modules.preprocessing import run_preprocessing, FILENAME_FORMATS, load_manifest
from modules.vocabulary import LABEL_MAP, WORDS, PROCESSED_NAME
from modules.paths import DATA_DIR, PROJECT_ROOT


def main(filename_format="signer-angle-word"):
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-data", type=Path, default=DATA_DIR / "processed")
    parser.add_argument("--raw-mov", type=Path, default=Path.home() / "Downloads" / "raw_mov")
    parser.add_argument("--project-dir", type=Path, default=PROJECT_ROOT)
    parser.add_argument("--processed-root", type=Path, default=DATA_DIR / PROCESSED_NAME)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--filename-format", choices=FILENAME_FORMATS, default=filename_format)
    args = parser.parse_args()
    # Fail before creating output files if the source arrays cannot cover the vocabulary.
    source_map_path = args.source_data / "core_label_map.json"
    source_map = json.loads(source_map_path.read_text(encoding="utf-8"))
    missing = [f"{key} ({word})" for key, word in WORDS.items() if key not in source_map]
    if missing:
        raise ValueError("Expert NPY source is missing active classes: " + ", ".join(missing)
                         + ". Supply arrays and a matching core_label_map.json containing all requested classes.")
    root = args.processed_root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    map_path = root / "core_label_map.json"
    if map_path.exists() and json.loads(map_path.read_text(encoding="utf-8")) != LABEL_MAP:
        raise ValueError("Output vocabulary differs. Use a new --processed-root.")
    (root / "core_label_map.json").write_text(json.dumps(LABEL_MAP, indent=2), encoding="utf-8")
    (root / "core_ksl_word_dictionary.json").write_text(
        json.dumps(WORDS, ensure_ascii=False, indent=2), encoding="utf-8")
    manifest = root / "manifest.csv"
    if args.overwrite or not any(row['domain'] == 'expert' for row in load_manifest(manifest)):
        count, _ = migrate(args.source_data / "X_train.npy", args.source_data / "y_train.npy",
                           root, overwrite=args.overwrite)
        print(f"Selected {count} expert sequences", flush=True)
    processed, failed = run_preprocessing(args.project_dir.resolve(), root / "raw_videos",
                                         root, ("team",), args.overwrite,
                                         args.raw_mov.resolve(), args.filename_format)
    if failed:
        raise RuntimeError(f"{failed} video(s) failed; inspect preprocessing_failures.txt")
    print(f"Team: {processed} clips; manifest: {manifest}", flush=True)
    audit(root)


if __name__ == "__main__":
    main()
