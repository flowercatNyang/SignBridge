import unittest

import numpy as np

from modules.realtime import RecognitionGate


class RecognitionGateTest(unittest.TestCase):
    def test_no_hands_at_start_never_produces_a_model_input(self):
        gate = RecognitionGate()
        for _ in range(40):
            self.assertIsNone(gate.add_frame(np.zeros(150), np.zeros(2)))
        self.assertEqual(gate.state, gate.NO_SIGN)

    def test_five_consecutive_missing_frames_clear_the_window(self):
        gate = RecognitionGate()
        for _ in range(30):
            sequence = gate.add_frame(np.ones(150), np.ones(2))
        self.assertIsNotNone(sequence)
        for _ in range(4):
            self.assertIsNotNone(gate.add_frame(np.zeros(150), np.zeros(2)))
        self.assertIsNone(gate.add_frame(np.zeros(150), np.zeros(2)))
        self.assertEqual(gate.state, gate.NO_SIGN)
        self.assertEqual(len(gate.features), 0)

    def test_visible_stationary_hands_can_still_produce_a_model_input(self):
        gate = RecognitionGate()
        for _ in range(30):
            sequence = gate.add_frame(np.zeros(150), np.ones(2))
        self.assertIsNotNone(sequence)
        self.assertEqual(sequence.shape, (30, 452))


if __name__ == "__main__":
    unittest.main()
