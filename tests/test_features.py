import unittest

import numpy as np

from modules.features import INPUT_DIM, build_temporal_features


class TemporalFeaturesTest(unittest.TestCase):
    def test_interpolates_hands_and_adds_motion_and_masks(self):
        frames = np.zeros((3, 150), dtype=np.float32)
        frames[0, :63] = 1.0
        frames[2, :63] = 3.0
        masks = np.array([[1, 0], [0, 0], [1, 0]], dtype=np.float32)

        result = build_temporal_features(frames, masks, sequence_length=3)

        self.assertEqual(result.shape, (3, INPUT_DIM))
        np.testing.assert_allclose(result[1, :63], 2.0)
        np.testing.assert_array_equal(result[:, -2:], masks)


if __name__ == "__main__":
    unittest.main()
