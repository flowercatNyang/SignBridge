import unittest

import numpy as np

from modules.features import INPUT_DIM
from modules.migration import convert_expert_sequence


class ExpertMigrationTest(unittest.TestCase):
    def test_converts_legacy_150d_sequence_to_452d(self):
        sequence = np.zeros((30, 150), dtype=np.float32)
        sequence[:, :63] = 1.0

        converted = convert_expert_sequence(sequence)

        self.assertEqual(converted.shape, (30, INPUT_DIM))
        np.testing.assert_array_equal(converted[:, -2], np.ones(30))
        np.testing.assert_array_equal(converted[:, -1], np.zeros(30))

    def test_preserves_existing_452d_sequence(self):
        sequence = np.zeros((30, INPUT_DIM), dtype=np.float32)

        converted = convert_expert_sequence(sequence)

        np.testing.assert_array_equal(converted, sequence)
        self.assertIsNot(converted, sequence)


if __name__ == "__main__":
    unittest.main()
