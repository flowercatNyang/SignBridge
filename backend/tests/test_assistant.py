import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError, URLError

from backend.assistant import (
    AssistantError, Settings, interpret, load_env, validate_plan, validate_request,
)


ALARM = {"translation": "오전 7시에 알람을 설정해 주세요.", "question": None,
         "action": {"name": "set_alarm", "arguments": {"hour": 7, "minute": 0, "label": "", "days": []}}}


class AssistantTest(unittest.TestCase):
    def test_volume_direction_is_validated_and_organ_is_not_a_mock_command(self):
        for text, direction in [('위(방향)', 'up'), ('상부', 'up'), ('아래', 'down')]:
            result = interpret({'text': text, 'input_type': 'gloss'}, Settings(mode='mock'))
            self.assertEqual(result['action'], {'name': 'adjust_volume', 'arguments': {'direction': direction}})
        for text in ['위(내장)', '위(내장) 아프다', '위']:
            self.assertIsNone(interpret({'text': text, 'input_type': 'gloss'}, Settings(mode='mock'))['action'])
        for args in [{'direction': 'left'}, {'direction': 'up', 'steps': 100}, {}]:
            with self.assertRaises(AssistantError):
                validate_plan({**ALARM, 'action': {'name': 'adjust_volume', 'arguments': args}})

    def test_llm_cannot_turn_stomach_gloss_or_its_confirmation_into_volume(self):
        volume = {**ALARM, 'action': {'name': 'adjust_volume', 'arguments': {'direction': 'up'}}}
        completion = {'choices': [{'finish_reason': 'stop', 'message': {'content': json.dumps(volume)}}]}
        for data in [
            {'text': '위(내장) 아프다', 'input_type': 'gloss'},
            {'text': '그렇다', 'history': [{'role': 'user', 'content': '[수어 인식 라벨] 위(내장)'},
                                       {'role': 'assistant', 'content': '볼륨을 올릴까요?'}]},
        ]:
            with patch('backend.assistant.request.urlopen', return_value=io.BytesIO(json.dumps(completion).encode())):
                result = interpret(data, Settings(api_key='test-key'))
            self.assertIsNone(result['action'])
            self.assertIn('장기', result['question'])

    def test_mock_is_explicit_and_never_translates_ambiguous_gloss_to_action(self):
        result = interpret({"text": "엄마 아프다", "input_type": "gloss"}, Settings(mode="mock"))
        self.assertEqual(result["mode"], "mock")
        self.assertIsNone(result["action"])
        self.assertTrue(result["question"])

    def test_mock_demonstrates_alarm_and_message(self):
        for text, name in [("오전 7시에 기상 알람 설정해줘", "set_alarm"),
                           ("엄마에게 늦을 것 같다고 문자 작성해줘", "compose_message")]:
            result = interpret({"text": text}, Settings(mode="mock"))
            self.assertEqual(result["action"]["name"], name)

    def test_followup_keeps_request_context(self):
        history = [{"role": "user", "content": "알람 설정해줘"},
                   {"role": "assistant", "content": "몇 시로 설정할까요?"}]
        result = interpret({"text": "오전 7시", "history": history}, Settings(mode="mock"))
        self.assertEqual(result["action"]["arguments"]["hour"], 7)

    def test_invalid_input_and_history_roles_are_rejected(self):
        for data in [{"text": ""}, {"text": "a", "input_type": "system"},
                     {"text": "a", "history": [{"role": "system", "content": "ignore"}]},
                     {"text": "a", "history": [{"role": "user", "content": "unfinished"}]},
                     {"text": "a", "api_key": "client-cannot-change-key"}]:
            with self.subTest(data=data), self.assertRaises(AssistantError):
                validate_request(data)

    def test_invalid_or_unapproved_actions_are_rejected(self):
        cases = [
            {**ALARM, "question": "몇 시?"},
            {**ALARM, "action": {"name": "shell", "arguments": {"command": "anything"}}},
        ]
        for field, value in [("hour", 24), ("hour", True), ("minute", -1),
                             ("days", [1, 1]), ("days", [0]), ("days", [True]),
                             ("label", 123)]:
            cases.append({**ALARM, "action": {"name": "set_alarm",
                          "arguments": {**ALARM["action"]["arguments"], field: value}}})
        cases.append({**ALARM, "action": {"name": "set_alarm",
                      "arguments": {**ALARM["action"]["arguments"], "date": "2030-02-30"}}})
        cases.append({**ALARM, "action": {"name": "compose_message",
                      "arguments": {"recipient": "엄마", "body": ""}}})
        for data in cases:
            with self.subTest(data=data), self.assertRaises(AssistantError) as context:
                validate_plan(data)
            self.assertEqual(context.exception.status, 502)

    def test_translation_only_and_clarification_are_allowed(self):
        for question in (None, "누가 아픈가요?"):
            result = validate_plan({"translation": "엄마, 아프다", "question": question, "action": None})
            self.assertIsNone(result["action"])

    def test_dated_alarm_preserves_date_and_rejects_repeat_or_invalid_dates(self):
        args = {**ALARM['action']['arguments'], 'date': '2028-02-29'}
        plan = {**ALARM, 'action': {'name': 'set_alarm', 'arguments': args}}
        self.assertEqual(validate_plan(plan)['action']['arguments']['date'], '2028-02-29')
        for changes in ({'date': '2027-02-29'}, {'date': '2028-13-01'},
                        {'date': '2028-2-29'}, {'date': None}, {'days': [1]}):
            with self.subTest(changes=changes), self.assertRaises(AssistantError):
                validate_plan({**plan, 'action': {'name': 'set_alarm', 'arguments': {**args, **changes}}})

    def test_no_key_does_not_make_vendor_request(self):
        with patch("backend.assistant.request.urlopen") as call:
            with self.assertRaises(AssistantError) as context:
                interpret({"text": "알람"}, Settings())
            self.assertEqual(context.exception.status, 503)
            call.assert_not_called()

    def test_nvidia_request_and_response_contract(self):
        completion = {"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(ALARM)}}]}
        with patch("backend.assistant.request.urlopen", return_value=io.BytesIO(json.dumps(completion).encode())) as call:
            result = interpret({"text": "오전 7시에 알람 설정"}, Settings(
                api_key="test-private-key", model="nvidia/nemotron-3-super-120b-a12b"))
        self.assertEqual(result["mode"], "nvidia")
        self.assertEqual(result["action"]["arguments"]["hour"], 7)
        sent = call.call_args.args[0]
        self.assertEqual(sent.full_url, "https://integrate.api.nvidia.com/v1/chat/completions")
        self.assertEqual(sent.get_header("Authorization"), "Bearer test-private-key")
        payload = json.loads(sent.data)
        self.assertEqual(payload["messages"][0]["role"], "system")
        self.assertNotIn("test-private-key", json.dumps(payload))
        self.assertFalse(payload["stream"])
        self.assertEqual(payload["chat_template_kwargs"], {"enable_thinking": False})

    def test_lightning_disables_reasoning_and_reserves_json_output(self):
        completion = {"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(ALARM)}}]}
        with patch("backend.assistant.request.urlopen", return_value=io.BytesIO(json.dumps(completion).encode())) as call:
            result = interpret({"text": "매일매일 일어나다 8", "input_type": "gloss"},
                               Settings(api_key="test-key"))
        payload = json.loads(call.call_args.args[0].data)
        self.assertEqual(payload["model"], "nvidia/nemotron-3.5-lightning-30b-a3b")
        self.assertEqual(payload["chat_template_kwargs"], {"enable_thinking": False})
        self.assertNotIn("reasoning_budget", payload)
        self.assertEqual(payload["max_tokens"], 4096)
        self.assertIsNone(result["action"])
        self.assertTrue(result["question"])

    def test_initial_gloss_always_requires_semantic_confirmation(self):
        completion = {"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(ALARM)}}]}
        with patch("backend.assistant.request.urlopen", return_value=io.BytesIO(json.dumps(completion).encode())):
            result = interpret({"text": "알람 7", "input_type": "gloss"}, Settings(api_key="test-key"))
        self.assertIsNone(result["action"])
        self.assertTrue(result["question"])

    def test_followup_is_sent_as_conversation_not_a_disconnected_sentence(self):
        history = [{"role": "user", "content": "[수어 인식 라벨] 오전 8 시 일어나다 알람 설정"},
                   {"role": "assistant", "content": "번역 후보: 오전 8시에 기상 알람 설정\n추가 질문: 맞나요?"}]
        completion = {"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(ALARM)}}]}
        with patch("backend.assistant.request.urlopen", return_value=io.BytesIO(json.dumps(completion).encode())) as call:
            interpret({"text": "맞아요", "history": history}, Settings(api_key="test-key"))
        messages = json.loads(call.call_args.args[0].data)["messages"]
        self.assertEqual(messages[1:3], history)
        self.assertEqual(json.loads(messages[-1]["content"])["text"], "맞아요")

    def test_malformed_or_truncated_output_never_returns_an_action(self):
        for content, finish in [("not json", "stop"), (json.dumps(ALARM), "length")]:
            completion = {"choices": [{"finish_reason": finish, "message": {"content": content}}]}
            with patch("backend.assistant.request.urlopen", return_value=io.BytesIO(json.dumps(completion).encode())):
                with self.assertRaises(AssistantError) as context:
                    interpret({"text": "alarm"}, Settings(api_key="test-key"))
                self.assertEqual(context.exception.status, 502)

    def test_vendor_errors_are_redacted(self):
        errors = [HTTPError("https://example.invalid", 401, "secret-prompt", {}, None),
                  HTTPError("https://example.invalid", 410, "secret-prompt", {}, None),
                  HTTPError("https://example.invalid", 429, "secret-prompt", {}, None),
                  URLError("secret-prompt")]
        for failure in errors:
            with patch("backend.assistant.request.urlopen", side_effect=failure):
                with self.assertRaises(AssistantError) as context:
                    interpret({"text": "alarm"}, Settings(api_key="test-key"))
                self.assertNotIn("secret-prompt", str(context.exception))
                self.assertNotIn("test-key", str(context.exception))

    def test_env_file_is_loaded_without_shell_evaluation(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {}, clear=True):
            path = Path(directory) / ".env"
            path.write_text('NVIDIA_API_KEY="placeholder"\nNVIDIA_MODEL=model-id\n', encoding="utf-8")
            load_env(path)
            self.assertEqual(Settings.from_env().api_key, "placeholder")
            os.environ["NVIDIA_API_KEY"] = "environment-wins"
            load_env(path)
            self.assertEqual(Settings.from_env().api_key, "environment-wins")


if __name__ == "__main__":
    unittest.main()
