"""Build an inference-only archive without training data or environments."""

import argparse
import hashlib
import zipfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.repo.resolve()
    files = ["apps/webcam/handsign_translate.py", "assets/mediapipe/hand_landmarker.task", "assets/mediapipe/pose_landmarker_lite.task",
             "requirements.txt", "docs/HANDOFF.md", "docs/RUN_RESULTS.md",
             "models/sign_language_five_words.pth"]
    files.extend(str(path.relative_to(root)) for path in sorted((root / "modules").glob("*.py")))
    for name in files:
        if not (root / name).is_file():
            raise FileNotFoundError(root / name)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    manifest = []
    with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in files:
            archive.write(root / name, "SignBridge/" + name)
            digest = hashlib.sha256((root / name).read_bytes()).hexdigest()
            manifest.append(f"{digest}  {name}")
        archive.writestr("SignBridge/SHA256SUMS.txt", "\n".join(manifest) + "\n")
    with zipfile.ZipFile(args.output) as archive:
        invalid = archive.testzip()
        if invalid:
            raise RuntimeError(f"ZIP CRC verification failed: {invalid}")
        assert archive.read("SignBridge/models/sign_language_five_words.pth") == (
            root / "models/sign_language_five_words.pth").read_bytes()
    print(f"Verified archive: {args.output.resolve()} ({args.output.stat().st_size:,} bytes)")
    print(f"Files: {len(files)} + SHA256SUMS.txt; no training videos/data included")


if __name__ == "__main__":
    main()
