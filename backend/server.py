"""Run: python -m backend.server. Defaults to loopback; LAN requires an access token."""

import argparse
import hmac
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

from .assistant import AssistantError, Settings, interpret, load_env


def make_server(host, port, settings):
    slots = threading.BoundedSemaphore(4)

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(15)

        def log_message(self, format, *args):
            # Do not log request bodies, contact names, messages or authentication headers.
            pass

        def reply(self, status, body):
            raw = json.dumps(body, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            origin = self.headers.get("Origin")
            if origin in settings.origins:
                self.send_header("Access-Control-Allow-Origin", origin)
                self.send_header("Vary", "Origin")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
            self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def allowed_origin(self):
            origin = self.headers.get("Origin")
            if origin is not None and origin not in settings.origins:
                self.reply(403, {"error": "허용되지 않은 웹 앱 주소입니다."})
                return False
            return True

        def do_OPTIONS(self):
            if self.allowed_origin():
                self.reply(200, {})

        def do_GET(self):
            if not self.allowed_origin():
                return
            if urlsplit(self.path).path != "/health":
                self.reply(404, {"error": "경로를 찾지 못했습니다."})
                return
            self.reply(200, {"status": "ok", "mode": settings.mode,
                             "configured": settings.mode == "mock" or bool(settings.api_key)})

        def do_POST(self):
            if not self.allowed_origin():
                return
            if urlsplit(self.path).path != "/v1/interpret":
                self.reply(404, {"error": "경로를 찾지 못했습니다."})
                return
            if settings.access_token and not hmac.compare_digest(
                    self.headers.get("Authorization", "").encode("utf-8"),
                    ("Bearer " + settings.access_token).encode("utf-8")):
                self.reply(401, {"error": "서버 연결 토큰을 확인해 주세요."})
                return
            if self.headers.get("Content-Type", "").split(";")[0].strip() != "application/json":
                self.reply(415, {"error": "JSON 요청이 필요합니다."})
                return
            try:
                if self.headers.get("Transfer-Encoding"):
                    raise AssistantError("지원하지 않는 전송 형식입니다.")
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 32768:
                    raise AssistantError("요청 크기는 1~32768바이트여야 합니다.", 413)
                data = json.loads(self.rfile.read(length))
            except AssistantError as exc:
                self.reply(exc.status, {"error": str(exc)})
                return
            except (ValueError, UnicodeError, TimeoutError, OSError, RecursionError):
                self.reply(400, {"error": "요청 데이터를 읽지 못했습니다."})
                return
            if not slots.acquire(blocking=False):
                self.reply(429, {"error": "서버가 다른 요청을 처리 중입니다. 잠시 후 다시 시도해 주세요."})
                return
            try:
                self.reply(200, interpret(data, settings))
            except AssistantError as exc:
                self.reply(exc.status, {"error": str(exc)})
            finally:
                slots.release()

    return ThreadingHTTPServer((host, port), Handler)


def main():
    import os

    load_env(Path(__file__).with_name(".env"))
    parser = argparse.ArgumentParser(description="SignBridge LLM backend")
    parser.add_argument("--host", default=os.getenv("HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.getenv("PORT", "8000")))
    args = parser.parse_args()
    settings = Settings.from_env()
    if args.host not in ("127.0.0.1", "localhost", "::1") and not settings.access_token:
        parser.error("LAN으로 열려면 backend/.env에 ASSISTANT_ACCESS_TOKEN을 설정하세요.")
    server = make_server(args.host, args.port, settings)
    print(f"SignBridge backend: http://{args.host}:{server.server_port} (mode={settings.mode})", flush=True)
    if settings.mode == "nvidia" and not settings.api_key:
        print("NVIDIA_API_KEY가 없습니다. backend/.env에 설정한 뒤 다시 시작하세요.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
