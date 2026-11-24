import unittest
from itertools import permutations

from backend.assistant import AssistantError, Settings, interpret


class GuidedConversationTest(unittest.TestCase):
    def start(self, text):
        self.source = text
        self.history = []
        return self.turn(text, "gloss")

    def turn(self, text, kind):
        reply = interpret(dict(text=text, input_type=kind, guided=True, history=self.history),
                          Settings(mode="mock"))
        entry = {"role": "assistant", "content": reply["question"] or reply["translation"]}
        if "step" in reply:
            entry["step"] = reply["step"]
        label = {"confirmation": "그렇다", "rejection": "틀리다"}.get(kind, "[수어 인식 라벨] " + text)
        self.history.extend(({"role": "user", "content": label}, entry))
        return reply

    def answer(self, yes):
        return self.turn(self.source, "confirmation" if yes else "rejection")

    def test_mother_sick_then_clinic(self):
        self.assertEqual(self.start("엄마 아프다")["step"], "subject")
        self.assertEqual(self.answer(True)["step"], "body")
        self.assertEqual(self.turn("위(내장)", "gloss")["action"]["name"], "emergency")
        hospital = self.answer(False)
        self.assertIn("휴대폰 위치", hospital["translation"])
        self.assertEqual(hospital["action"]["arguments"], {"department": "내과"})
        self.assertIsNone(self.answer(False)["action"])

    def test_alternative_meaning_preserves_source(self):
        self.start("엄마 아프다")
        self.assertEqual(self.answer(False)["step"], "notify")
        self.assertEqual(self.answer(True)["action"]["arguments"], {"recipient": "엄마", "body": "나 아파."})

    def test_known_body_and_optional_body(self):
        self.assertEqual(self.start("나 위(내장) 아프다")["step"], "emergency")
        self.assertEqual(self.start("아프다")["step"], "body")
        self.assertEqual(self.answer(True)["step"], "emergency")
        self.assertEqual(self.answer(False)["action"]["arguments"]["department"], "병원")

    def test_mother_contact_alternatives(self):
        self.assertEqual(self.start("엄마")["action"]["name"], "mother")
        self.assertEqual(self.answer(False)["step"], "message")
        self.assertEqual(self.answer(True)["step"], "message_body")
        self.assertEqual(self.turn("나 아파", "text")["action"]["arguments"]["body"], "나 아파")

    def test_individual_words(self):
        self.assertEqual(self.start("회사")["action"]["name"], "company")
        self.assertIsNone(self.answer(False)["action"])
        for word, direction in (("위(방향)", "up"), ("아래", "down")):
            self.assertEqual(self.start(word)["action"]["arguments"], {"direction": direction})

    def test_rejection_requires_matching_source(self):
        self.start("엄마")
        with self.assertRaises(AssistantError):
            self.turn("틀리다", "rejection")

    def test_wake_alarm_in_every_word_order(self):
        for words, days in [(("일어나다", "8"), []),
                            (("매일매일", "일어나다", "8"), list(range(1, 8)))]:
            for order in permutations(words):
                with self.subTest(order=order):
                    reply = self.start(" ".join(order))
                    self.assertEqual(reply["action"], {"name": "set_alarm", "arguments": {
                        "hour": 8, "minute": 0, "label": "기상", "days": days}})
                    self.assertEqual(reply["step"], "done_on_decline")
                    self.assertIsNone(self.answer(False)["action"])

    def test_wake_alarm_requires_complete_unambiguous_labels(self):
        for text in ("매일매일 8", "일어나다", "일어나다 8 8", "엄마 일어나다 8"):
            with self.subTest(text=text):
                self.assertIsNone(self.start(text)["action"])
