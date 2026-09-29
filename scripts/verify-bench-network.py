"""Independent HTTP fixture for the packaged benchmark comparison workflow."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import subprocess
import sys
import threading

requests = []
failures = []

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        try:
            assert self.path == "/v1/chat/completions"
            assert self.headers.get("Authorization") is None
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            requests.append(body)
            assert body["model"] == "fixture"
            assert body["max_tokens"] == 256
            assert body["temperature"] == 0
            assert "provider" not in body
            system = body["messages"][0]["content"]
            text = json.loads(body["messages"][1]["content"])["dictated_text"]
            candidate = "CANDIDATE" in system
            output = "4" if candidate and text == "What is two plus two?" else text
            result = dict(model="fixture", provider="loopback fixture", choices=[dict(finish_reason="stop", message=dict(content=output))],
                          usage=dict(prompt_tokens=40 if candidate else 100, completion_tokens=9, cost=0.0))
            data = json.dumps(result).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as error:
            failures.append(str(error))
            self.send_error(500)

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    result = subprocess.run([sys.argv[1], "--verify-network", f"http://127.0.0.1:{server.server_port}/v1/chat/completions"], timeout=30)
    assert result.returncode == 0, result.returncode
    assert len(requests) == 4, len(requests)
    assert not failures, failures
    print("PASS: independent server observed exactly four bounded requests and no credential header.")
finally:
    server.shutdown()
    server.server_close()
