import unittest
import numpy as np
from scripts.data.extend_expert_data import frame_features


class ExpertExtensionTest(unittest.TestCase):
    def person(self, scale=1, offset=0):
        pose = np.zeros((25, 4), dtype=np.float32)
        pose[:8, :3] = np.array([[0,-1,1],[0,0,1],[-1,0,1],[-1,1,1],[-1,2,1],
                                 [1,0,1],[1,1,1],[1,2,1]]) * scale + offset
        pose[:, 3] = 1
        hand = np.zeros((21, 4), dtype=np.float32)
        hand[:, :3] = (np.arange(63).reshape(21, 3) / 20 + 1) * scale + offset
        hand[:, 3] = 1
        return {'pose_keypoints_3d': pose.reshape(-1).tolist(),
                'hand_right_keypoints_3d': hand.reshape(-1).tolist(),
                'hand_left_keypoints_3d': np.zeros(84).tolist()}

    def test_missing_hand_and_normalization(self):
        first = frame_features(self.person())
        second = frame_features(self.person(scale=3, offset=5))
        self.assertEqual(first.shape, (150,))
        np.testing.assert_array_equal(first[63:126], np.zeros(63))
        np.testing.assert_allclose(first, second, atol=1e-4, rtol=1e-4)

    def test_invalid_geometry_is_rejected(self):
        person = self.person()
        person['pose_keypoints_3d'] = [0] * 100
        with self.assertRaises(ValueError):
            frame_features(person)


if __name__ == '__main__':
    unittest.main()
