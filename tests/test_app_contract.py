"""Verify that the mobile assets and reference fixtures match the shared Python code."""

import hashlib
import json
import re
import unittest
from types import SimpleNamespace

import numpy as np

from modules.features import INPUT_DIM, SEQUENCE_LENGTH, build_temporal_features, extract_keypoints
from modules.paths import MEDIAPIPE_DIR, PROJECT_ROOT
from modules.vocabulary import LABEL_MAP, WORDS


APP = PROJECT_ROOT / "apps" / "mobile"


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def landmarks(points):
    if points is None:
        return None
    return SimpleNamespace(landmark=[SimpleNamespace(**point) for point in points])


class AppContractTest(unittest.TestCase):
    def test_all_declared_flutter_assets_exist(self):
        manifest = (APP / "pubspec.yaml").read_text(encoding="utf-8-sig")
        assets = re.findall(r"^\s+- (assets/\S+)\s*$", manifest, re.MULTILINE)
        self.assertTrue(assets)
        for asset in assets:
            self.assertTrue((APP / asset).is_file(), asset)

    def test_model_config_labels_and_artifact_hashes(self):
        assets = APP / "assets"
        config = read_json(assets / "models/sign_model.json")
        self.assertEqual(config["features"], INPUT_DIM)
        self.assertEqual(config["frames"], SEQUENCE_LENGTH)
        self.assertEqual(config["featureSchema"], "ksl-temporal-452-v2")
        self.assertEqual(read_json(assets / config["labels"]), LABEL_MAP)
        self.assertEqual(read_json(assets / config["dictionary"]), WORDS)
        model = assets / config["model"]
        report = read_json(model.with_suffix(".json"))
        self.assertEqual(report["input_shape"], [1, SEQUENCE_LENGTH, INPUT_DIM])
        self.assertEqual(report["class_order"], [WORDS[key] for key in sorted(LABEL_MAP, key=LABEL_MAP.get)])
        self.assertEqual(hashlib.sha256(model.read_bytes()).hexdigest(), report["onnx_sha256"])
        checkpoint = PROJECT_ROOT / "models/sign_language_five_words.pth"
        self.assertEqual(hashlib.sha256(checkpoint.read_bytes()).hexdigest(), report["source_sha256"])

    def test_landmark_fixtures_match_shared_extractor(self):
        for case in read_json(APP / "test/fixtures/sign_features.json"):
            with self.subTest(case=case["name"]):
                result = SimpleNamespace(
                    right_hand_landmarks=landmarks(case["right"]),
                    left_hand_landmarks=landmarks(case["left"]),
                    pose_landmarks=landmarks(case["pose"]),
                )
                actual = extract_keypoints(result, case["width"], case["height"])
                np.testing.assert_allclose(actual, case["expected"], atol=1e-4, rtol=1e-5)

    def test_temporal_fixtures_match_shared_extractor(self):
        for case in read_json(APP / "test/fixtures/sign_temporal.json"):
            with self.subTest(case=case["name"]):
                actual = build_temporal_features(
                    np.asarray(case["frames"], dtype=np.float32),
                    np.asarray(case["masks"], dtype=np.float32),
                )
                np.testing.assert_allclose(actual.reshape(-1), case["expected"], atol=1e-5, rtol=1e-5)

    def test_mediapipe_assets_match(self):
        for name in ("hand_landmarker.task", "pose_landmarker_lite.task"):
            self.assertEqual(
                hashlib.sha256((APP / "assets" / name).read_bytes()).hexdigest(),
                hashlib.sha256((MEDIAPIPE_DIR / name).read_bytes()).hexdigest(),
            )


if __name__ == "__main__":
    unittest.main()
