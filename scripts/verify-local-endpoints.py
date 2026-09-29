#!/usr/bin/env python3
"""Exercise the packaged app against an ephemeral loopback fixture, without user data."""
import json
from email.parser import BytesParser
from email.policy import default
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import subprocess
import threading

seen = []
failures = []

class Fixture(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        try:
            assert self.headers.get("Authorization") is None
            assert self.headers.get("xi-api-key") is None
            body = self.rfile.read(int(self.headers["Content-Length"]))
            assert b"never-send-fixture" not in body
            if self.path == "/v1/audio/transcriptions":
                message = BytesParser(policy=default).parsebytes(
                    b"Content-Type: " + self.headers["Content-Type"].encode() + b"\r\n\r\n" + body)
                fields = {part.get_param("name", header="content-disposition"): part.get_payload(decode=True)
                          for part in message.iter_parts()}
                assert fields["model"] == b"fixture/whisper:latest"
                assert fields["response_format"] == b"json"
                assert fields["file"][:4] == b"RIFF" and fields["file"][8:12] == b"WAVE"
                result = {"text": "Fixture speech."}
            else:
                assert self.path == "/v1/chat/completions"
                payload = json.loads(body)
                assert payload["model"] == "fixture/cleanup:latest"
                assert payload["messages"][-1]["role"] == "user"
                assert json.loads(payload["messages"][-1]["content"]) == {"dictated_text": "Fixture speech."}
                assert "provider" not in payload
                assert payload["stream"] is False
                result = {"model": payload["model"], "choices": [{"finish_reason": "stop", "message": {"content": "Fixture cleaned."}}]}
            seen.append(self.path)
            data = json.dumps(result).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as error:
            failures.append(repr(error))
            self.send_error(500)

server = HTTPServer(("127.0.0.1", 0), Fixture)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    app = Path(__file__).resolve().parent.parent / "build/S2T.app/Contents/MacOS/S2T"
    subprocess.run([str(app), "--verify-local-endpoints", "--local-fixture-url",
                    f"http://127.0.0.1:{server.server_port}"], check=True, timeout=30)
    assert not failures, failures
    assert seen == ["/v1/audio/transcriptions", "/v1/chat/completions"], seen
    print("PASS: loopback server verified models, multipart audio, image data, JSON and absent cloud credentials/routing.")
finally:
    server.shutdown()
    server.server_close()
    thread.join()
