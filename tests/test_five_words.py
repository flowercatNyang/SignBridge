import unittest
import unicodedata
from pathlib import Path

import torch

from modules.data import Sample, make_loso_split
from modules.models import SignLanguageModel
from modules.preprocessing import parse_team_filename
from modules.vocabulary import LABEL_MAP, WORDS


class FiveWordTest(unittest.TestCase):
    def test_frontal_word_and_angle_word_are_distinct(self):
        self.assertEqual(parse_team_filename(Path("사람_위.MOV")), ("사람", "정면", "WORD2100"))
        self.assertEqual(parse_team_filename(Path("사람_위_아래.mov")), ("사람", "위", "WORD2577"))
        filename = unicodedata.normalize("NFD", "사람_아래_엄마.mp4")
        self.assertEqual(parse_team_filename(Path(filename)), ("사람", "아래", "WORD1528"))

    def test_unknown_word_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_team_filename(Path("사람_밥.mp4"))

    def test_signers_do_not_leak_between_splits(self):
        rows = []
        for key, label in LABEL_MAP.items():
            rows.extend(Sample(Path(f"e_{label}_{i}"), label, key, "expert", "expert_unknown")
                        for i in range(50))
            for signer in ("a", "b", "c", "validation", "test"):
                rows.extend(Sample(Path(f"{signer}_{label}_{i}"), label, key, "team", signer)
                            for i in range(3))
        splits = make_loso_split(rows, "test", validation_signer="validation")
        for name in ("stage0", "expert_train", "adapt_train"):
            self.assertFalse({"test", "validation"} & {row.signer_id for row in splits[name]})
        self.assertEqual(len(splits["held_out"]), 15)
        self.assertEqual(len(splits["team_validation"]), 15)
        self.assertEqual(len(splits["adapt_train"]), 270)

    def test_default_output_matches_five_word_map(self):
        model = SignLanguageModel().eval()
        with torch.no_grad():
            self.assertEqual(tuple(model(torch.zeros(2, 30, 452)).shape), (2, len(WORDS)))


if __name__ == "__main__":
    unittest.main()
