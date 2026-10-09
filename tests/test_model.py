import unittest

import torch

from modules.features import INPUT_DIM
from modules.models import SignLanguageModel


class SignLanguageModelTest(unittest.TestCase):
    def test_attention_covers_all_thirty_frames(self):
        model = SignLanguageModel()
        inputs = torch.zeros(2, 30, INPUT_DIM)

        logits, attention = model(inputs, return_attention=True)

        # self.assertEqual(logits.shape, (2, 73))
        self.assertEqual(logits.shape, (2, 5))
        self.assertEqual(attention.shape, (2, 30))
        torch.testing.assert_close(attention.sum(dim=1), torch.ones(2))


if __name__ == "__main__":
    unittest.main()
