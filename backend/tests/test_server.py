import http.client
import json
import threading
import unittest

from backend.assistant import Settings
from backend.server import make_server


class ServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = make_server("127.0.0.1", 0,
            Settings(mode="mock", access_token="local-test-token", origins=("http://localhost:5300",)))
        cls.worker = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.worker.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.worker.join(timeout=3)

    def call(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        try:
            connection.request(method, path, body=body, headers=headers or {})
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), json.loads(response.read())
        finally:
            connection.close()

    def test_health_does_not_expose_credentials(self):
        status, _, body = self.call("GET", "/health")
        self.assertEqual(status, 200)
        self.assertEqual(body["mode"], "mock")
        self.assertNotIn("local-test-token", json.dumps(body))

    def test_authentication_and_request_validation(self):
        body = json.dumps({"text": "오전 7시에 기상 알람 설정해줘"}).encode()
        headers = {"Content-Type": "application/json"}
        self.assertEqual(self.call("POST", "/v1/interpret", body, headers)[0], 401)
        headers["Authorization"] = "Bearer local-test-token"
        self.assertEqual(self.call("POST", "/v1/interpret", b"broken", headers)[0], 400)
        status, _, result = self.call("POST", "/v1/interpret", body, headers)
        self.assertEqual(status, 200)
        self.assertEqual(result["action"]["name"], "set_alarm")
        self.assertEqual(result["mode"], "mock")

    def test_cors_does_not_allow_arbitrary_websites(self):
        self.assertEqual(self.call("OPTIONS", "/v1/interpret",
            headers={"Origin": "https://not-allowed.invalid"})[0], 403)
        status, headers, _ = self.call("OPTIONS", "/v1/interpret",
            headers={"Origin": "http://localhost:5300"})
        self.assertEqual(status, 200)
        self.assertEqual(headers["Access-Control-Allow-Origin"], "http://localhost:5300")

    def test_oversized_and_non_json_requests_are_rejected(self):
        auth = {"Authorization": "Bearer local-test-token", "Content-Type": "application/json"}
        self.assertEqual(self.call("POST", "/v1/interpret", b"x" * 32769, auth)[0], 413)
        auth["Content-Type"] = "text/plain"
        self.assertEqual(self.call("POST", "/v1/interpret", b"x", auth)[0], 415)


if __name__ == "__main__":
    unittest.main()
