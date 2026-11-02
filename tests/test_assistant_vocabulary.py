import json
import os
from pathlib import Path
import subprocess
import sys
import unittest


class AssistantVocabularyTest(unittest.TestCase):
    def test_separate_profile_uses_only_dictionary_ids(self):
        root = Path(__file__).resolve().parents[1]
        dictionary = json.loads((root / 'data/processed/ksl_word_dictionary.json').read_text(encoding='utf-8'))
        demo_ids = {'WORD1152', 'WORD2100', 'WORD2577', 'WORD1592', 'WORD1528',
                    'WORD1157', 'WORD0948', 'WORD0932', 'WORD1273', 'WORD2639',
                    'WORD2268', 'WORD1359', 'WORD2576'}
        for profile, count in [('five', 5), ('assistant_demo', 13), ('assistant23', 13)]:
            result = subprocess.run([sys.executable, '-c',
                'import json; from modules.vocabulary import WORDS, EXPECTED_PER_CLASS, DISPLAY_LABELS; '
                'print(json.dumps([WORDS, EXPECTED_PER_CLASS, DISPLAY_LABELS]))'], cwd=root,
                env={**os.environ, 'SIGNBRIDGE_VOCABULARY': profile},
                check=True, text=True, capture_output=True)
            words, counts, displays = json.loads(result.stdout)
            self.assertEqual(len(words), count)
            self.assertTrue(all(dictionary[key] == word for key, word in words.items()))
            self.assertEqual(counts['expert'], 50)
            if profile != 'five':
                self.assertEqual(counts['team'], 3)
                self.assertEqual(set(words), demo_ids)
                self.assertEqual(words['WORD2639'], '팔')
                self.assertEqual(words['WORD2268'], '그렇다')
                self.assertEqual(words['WORD1359'], '틀리다')
                self.assertEqual(words['WORD2576'], '상부')
                self.assertEqual(displays['WORD2100'], '위(내장)')
                self.assertEqual(displays['WORD2576'], '위(방향)')


if __name__ == '__main__':
    unittest.main()
