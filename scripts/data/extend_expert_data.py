"""Keep existing expert sequences and fill absent classes from OpenPose 3D JSON.

Uses the original 150D expert feature convention. This maps the representation;
it does not claim OpenPose and MediaPipe have identical coordinate distributions.
"""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import numpy as np
from modules.features import compute_25d_features, H_PARENTS, H_CHILDREN, UB_PARENTS, UB_CHILDREN
from modules.vocabulary import WORDS, LABEL_MAP


def coordinates(value, count):
    points = np.asarray(value, dtype=np.float32)
    if points.size == 0:
        return np.zeros((count, 3), dtype=np.float32)
    if points.size != count * 4 or not np.isfinite(points).all():
        raise ValueError(f"Expected {count} OpenPose xyz/confidence points")
    return points.reshape(count, 4)[:, :3].copy()


def frame_features(person):
    pose = coordinates(person.get("pose_keypoints_3d", []), 25)[:8]
    hands = [coordinates(person.get(name, []), 21)
             for name in ("hand_right_keypoints_3d", "hand_left_keypoints_3d")]
    neck = pose[1].copy()
    scale = float(np.linalg.norm(pose[5] - pose[2]))
    if scale < 1e-6:
        raise ValueError("Expert frame has no usable shoulder width")
    pose = (pose - neck) / scale
    features = []
    for hand in hands:
        if not np.any(hand):
            features.append(np.zeros(63, dtype=np.float32))
        else:
            hand = (hand - neck) / scale
            features.append(compute_25d_features(hand, H_PARENTS, H_CHILDREN, [0, 4, 8], [1, 5, 9]))
    features.append(compute_25d_features(pose, UB_PARENTS, UB_CHILDREN, [2, 5, 1], [3, 6, 4]))
    return np.concatenate(features).astype(np.float32)


def read_sequence(directory):
    frames = []
    for path in sorted(directory.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        person = data.get("people", {})
        if isinstance(person, list):
            person = person[0] if person else {}
        frames.append(frame_features(person))
    if not frames:
        raise ValueError(f"No expert frames: {directory}")
    array = np.asarray(frames, dtype=np.float32)
    # Match the existing expert NPY's original frame selection/padding rule.
    if len(array) < 30:
        array = np.concatenate([array, np.repeat(array[-1:], 30 - len(array), axis=0)])
    elif len(array) > 30:
        array = array[np.linspace(0, len(array) - 1, 30, dtype=int)]
    return array


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-data", type=Path, default=Path("data/processed"))
    parser.add_argument("--json-root", type=Path, default=Path("data/raw_json/train/extracted"))
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    source_map = json.loads((args.source_data / "core_label_map.json").read_text(encoding="utf-8-sig"))
    x = np.load(args.source_data / "X_train.npy", mmap_mode="r")
    y = np.load(args.source_data / "y_train.npy", mmap_mode="r")
    if x.shape[1:] != (30, 150) or y.shape != (len(x),):
        raise ValueError("Expected source expert arrays [N,30,150] and [N]")
    if args.output_root.resolve() == args.source_data.resolve():
        raise ValueError("Use a separate output directory; original expert arrays are preserved")
    if (args.output_root / "X_train.npy").exists():
        raise FileExistsError("Output already exists; choose a new --output-root")
    arrays, labels, provenance = [], [], []
    for key, label in LABEL_MAP.items():
        if key in source_map:
            indices = np.flatnonzero(y == source_map[key])
            if len(indices) < 50:
                raise ValueError(f"Expert {key} only has {len(indices)} samples; 50 required")
            arrays.extend(x[indices])
            labels.extend([label] * len(indices))
            provenance.append({"class_key": key, "word": WORDS[key], "source": "existing_npy", "samples": len(indices)})
        else:
            candidates = sorted(directory for signer in args.json_root.iterdir() if signer.is_dir()
                                for directory in signer.glob(f"*_{key}_*") if directory.is_dir())
            if len(candidates) < 50:
                raise ValueError(f"Expert JSON {key} has {len(candidates)} clips; 50 required")
            selected = candidates[:50]
            for index, directory in enumerate(selected, 1):
                arrays.append(read_sequence(directory))
                labels.append(label)
                print(f"Expert {key}: {index}/50", flush=True)
            provenance.append({"class_key": key, "word": WORDS[key], "source": "openpose_3d_json",
                               "samples": 50, "clips": [str(p.resolve()) for p in selected]})
    output = np.asarray(arrays, dtype=np.float32)
    if not np.isfinite(output).all():
        raise ValueError("Expert features contain NaN or infinity")
    args.output_root.mkdir(parents=True, exist_ok=True)
    np.save(args.output_root / "X_train.npy", output)
    np.save(args.output_root / "y_train.npy", np.asarray(labels, dtype=np.int64))
    for name, data in [("core_label_map.json", LABEL_MAP), ("core_ksl_word_dictionary.json", WORDS),
                       ("expert_provenance.json", provenance)]:
        (args.output_root / name).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Saved {len(output)} expert sequences to {args.output_root}", flush=True)


if __name__ == "__main__":
    main()
