import argparse
import csv
import hashlib
import json
import os
import re
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

from .features import build_temporal_features, extract_keypoints
from .utils import MockResults


VIDEO_EXTENSIONS = {".mp4", ".avi", ".mov", ".mkv", ".webm"}
EXPECTED_PER_CLASS = {"expert": 50, "team": 9}
DOMAINS = ("expert", "team", "external")


def create_landmarkers(project_dir):
    project_dir = Path(project_dir)
    base_options = mp.tasks.BaseOptions
    running_mode = mp.tasks.vision.RunningMode
    hand_options = mp.tasks.vision.HandLandmarkerOptions(
        base_options=base_options(model_asset_path=str(project_dir / "hand_landmarker.task")),
        running_mode=running_mode.IMAGE,
        num_hands=2,
        min_hand_detection_confidence=0.5,
        min_hand_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    pose_options = mp.tasks.vision.PoseLandmarkerOptions(
        base_options=base_options(model_asset_path=str(project_dir / "pose_landmarker_lite.task")),
        running_mode=running_mode.IMAGE,
        min_pose_detection_confidence=0.5,
        min_pose_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    return (
        mp.tasks.vision.HandLandmarker.create_from_options(hand_options),
        mp.tasks.vision.PoseLandmarker.create_from_options(pose_options),
    )


def process_video(video_path, hand_landmarker, pose_landmarker):
    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise ValueError(f"Cannot open video: {video_path}")

    frame_features, hand_masks = [], []
    try:
        while True:
            success, frame = capture.read()
            if not success:
                break
            height, width = frame.shape[:2]
            image = mp.Image(
                image_format=mp.ImageFormat.SRGB,
                data=cv2.cvtColor(frame, cv2.COLOR_BGR2RGB),
            )
            results = MockResults(pose_landmarker.detect(image), hand_landmarker.detect(image))
            features, mask = extract_keypoints(results, width, height, return_mask=True)
            frame_features.append(features)
            hand_masks.append(mask)
    finally:
        capture.release()

    if not frame_features:
        raise ValueError(f"No frames decoded: {video_path}")
    return build_temporal_features(frame_features, hand_masks)


def find_class_key(path, label_map):
    matches = re.findall(r"WORD\d{4}", str(path).upper())
    return next((match for match in matches if match in label_map), None)


def find_signer_id(video_path, domain, domain_root):
    relative = video_path.relative_to(domain_root)
    if domain in {"team", "external"}:
        if len(relative.parts) < 3:
            raise ValueError(
                f"{domain} videos must use {domain}/<signer_id>/<class_key>/<video>"
            )
        return relative.parts[0]
    match = re.search(r"(REAL\d+)", str(relative).upper())
    return match.group(1) if match else "expert_unknown"


def discover_videos(raw_root, domains):
    for domain in domains:
        domain_root = raw_root / domain
        if not domain_root.exists():
            continue
        for path in domain_root.rglob("*"):
            if path.is_file() and path.suffix.lower() in VIDEO_EXTENSIONS:
                yield domain, domain_root, path


def _output_path(processed_root, domain, class_key, signer_id, video_path):
    digest = hashlib.sha1(str(video_path.resolve()).encode("utf-8")).hexdigest()[:12]
    return processed_root / "sequences" / domain / class_key / signer_id / f"{digest}.npz"


def load_manifest(manifest_path):
    if not manifest_path.exists():
        return []
    with manifest_path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def write_manifest(manifest_path, rows):
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    fields = ["path", "label", "class_key", "domain", "signer_id", "source_video"]
    with manifest_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(sorted(rows, key=lambda row: (row["domain"], int(row["label"]), row["path"])))


def validate_counts(rows, label_map, domains):
    failures = []
    for domain, required in EXPECTED_PER_CLASS.items():
        if domain not in domains:
            continue
        for class_key in label_map:
            count = sum(
                row["domain"] == domain and row["class_key"] == class_key for row in rows
            )
            if count < required:
                failures.append(f"{domain}/{class_key}: {count} found, {required} required")
    if failures:
        preview = "\n".join(failures[:20])
        raise ValueError(f"Dataset count validation failed:\n{preview}")


def run_preprocessing(project_dir, raw_root, processed_root, domains, overwrite=False):
    label_map_path = processed_root / "core_label_map.json"
    with label_map_path.open("r", encoding="utf-8") as handle:
        label_map = json.load(handle)
    if len(label_map) != 73:
        raise ValueError(f"Expected 73 classes, found {len(label_map)}")

    manifest_path = processed_root / "manifest.csv"
    retained = [row for row in load_manifest(manifest_path) if row["domain"] not in domains]
    rows, failures = [], []
    hands, pose = create_landmarkers(project_dir)
    try:
        for domain, domain_root, video_path in discover_videos(raw_root, domains):
            class_key = find_class_key(video_path, label_map)
            if class_key is None:
                failures.append(f"No class key: {video_path}")
                continue
            try:
                signer_id = find_signer_id(video_path, domain, domain_root)
                output_path = _output_path(
                    processed_root, domain, class_key, signer_id, video_path
                )
                if overwrite or not output_path.exists():
                    sequence = process_video(video_path, hands, pose)
                    output_path.parent.mkdir(parents=True, exist_ok=True)
                    np.savez_compressed(output_path, x=sequence)
                rows.append(
                    {
                        "path": os.path.relpath(output_path, processed_root),
                        "label": label_map[class_key],
                        "class_key": class_key,
                        "domain": domain,
                        "signer_id": signer_id,
                        "source_video": str(video_path.resolve()),
                    }
                )
            except (OSError, ValueError) as error:
                failures.append(str(error))
    finally:
        hands.close()
        pose.close()

    all_rows = retained + rows
    write_manifest(manifest_path, all_rows)
    if failures:
        failure_path = processed_root / "preprocessing_failures.txt"
        failure_path.write_text("\n".join(failures), encoding="utf-8")
    validate_counts(all_rows, label_map, set(domains))
    return len(rows), len(failures)


def main():
    parser = argparse.ArgumentParser(description="Preprocess all videos with one MediaPipe pipeline")
    parser.add_argument("--project-dir", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--raw-root", type=Path, default=Path("data/raw_videos"))
    parser.add_argument("--processed-root", type=Path, default=Path("data/processed"))
    parser.add_argument("--domain", choices=DOMAINS, action="append")
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()
    domains = tuple(args.domain or DOMAINS)
    processed, failed = run_preprocessing(
        args.project_dir.resolve(),
        args.raw_root.resolve(),
        args.processed_root.resolve(),
        domains,
        args.overwrite,
    )
    print(f"Processed {processed} videos. Failed {failed}.")


if __name__ == "__main__":
    main()
