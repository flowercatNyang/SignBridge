import unittest
from pathlib import Path

from modules.paths import MEDIAPIPE_DIR, PROJECT_ROOT


class ProjectLayoutTest(unittest.TestCase):
    def test_assets_and_cli_entry_points_exist(self):
        for name in ("hand_landmarker.task", "pose_landmarker_lite.task"):
            self.assertTrue((MEDIAPIPE_DIR / name).is_file())
        for relative in (
            "notebooks/Data_Preprocessing.ipynb",
            "scripts/data/preprocess_videos.py",
            "scripts/data/migrate_expert_npy.py",
            "notebooks/GRU_Model_Training.ipynb",
            "notebooks/Model_Evaluation.ipynb",
        ):
            self.assertTrue((PROJECT_ROOT / relative).is_file(), relative)

    def test_root_does_not_depend_on_current_directory(self):
        self.assertEqual(PROJECT_ROOT, Path(__file__).resolve().parents[1])


if __name__ == "__main__":
    unittest.main()
