"""Exercise the shipped HTTP worker with deterministic model doubles, never downloads/GPU."""
import http.client
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


class WorkerLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="s2t-worker-test-")
        self.root = Path(self.temporary.name)
        resources = Path(os.environ.get("S2T_TEST_WORKER_RESOURCES", Path(__file__).resolve().parents[2] / "Resources/LocalModels"))
        for name in ("worker.py", "response_text.py"):
            shutil.copyfile(resources / name, self.root / name)
        self.item = {"id": "fixture", "category": "text", "revision": "fixture-revision", "repository": "fixture/model"}
        (self.root / "catalog.json").write_text(json.dumps([self.item]))
        model = self.root / "models/fixture"
        model.mkdir(parents=True)
        (model / "installed.json").write_text(json.dumps({"revision": self.item["revision"]}))
        (model / "weights.safetensors").write_text("original weights")
        (self.root / "mlx").mkdir()
        (self.root / "mlx/__init__.py").write_text("")
        (self.root / "mlx/core.py").write_text("def set_cache_limit(x): pass\ndef clear_cache(): pass\ndef get_active_memory(): return 0\n")
        (self.root / "mlx_lm.py").write_text('''
import time
from types import SimpleNamespace
class Tokenizer:
    def apply_chat_template(self, messages, **kwargs): return messages[0]["content"]
    def encode(self, text): return list(text)
def load(path): return object(), Tokenizer()
def stream_generate(model, tokenizer, prompt, max_tokens):
    for index in range(max_tokens):
        if prompt == "SLOW": time.sleep(0.02)
        yield SimpleNamespace(text="x", token=120, finish_reason="stop" if index == max_tokens - 1 else None)
''')
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=5)
        self.temporary.cleanup()

    def start(self):
        self.process = subprocess.Popen([os.sys.executable, str(self.root / "worker.py"), "serve", "--root", str(self.root)],
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        from urllib.parse import urlparse
        self.url = json.loads(self.process.stdout.readline())["endpoint"]
        self.endpoint = urlparse(self.url)

    def request(self, **changes):
        connection = http.client.HTTPConnection(self.endpoint.hostname, self.endpoint.port, timeout=5)
        body = {"model": "fixture", "messages": [{"role": "user", "content": "fast"}], "max_tokens": 3, **changes}
        connection.request("POST", self.endpoint.path + "/chat/completions", json.dumps(body), {"Content-Type": "application/json"})
        response = connection.getresponse()
        result = response.status, json.loads(response.read())
        connection.close()
        return result

    def test_requested_budget_and_invalid_budgets(self):
        self.start()
        for limit in (1, 7, 2050):
            status, response = self.request(max_tokens=limit)
            self.assertEqual(status, 200)
            self.assertEqual(len(response["choices"][0]["message"]["content"]), limit)
        for limit in (0, -1, 8193, True, "3", 1.5):
            self.assertEqual(self.request(max_tokens=limit)[0], 400)
        self.assertEqual(self.request()[0], 200)

    def test_urlsession_cancellation_releases_worker(self):
        self.start()
        client = self.root / "cancel.swift"
        client.write_text('''
import Foundation
@main struct Check {
 static func main() async throws {
  let url = URL(string: CommandLine.arguments[1] + "/chat/completions")!
  func request(_ content: String, _ tokens: Int) throws -> URLRequest {
   var r = URLRequest(url: url); r.httpMethod = "POST"
   r.setValue("application/json", forHTTPHeaderField: "Content-Type")
   r.httpBody = try JSONSerialization.data(withJSONObject: ["model":"fixture", "messages":[["role":"user", "content":content]], "max_tokens":tokens])
   return r
  }
  let slow = Task { try await URLSession.shared.data(for: request("SLOW", 200)) }
  try await Task.sleep(nanoseconds: 150_000_000)
  slow.cancel()
  do { _ = try await slow.value; fatalError("cancel ignored") } catch { }
  let start = Date()
  let (data, response) = try await URLSession.shared.data(for: request("fast", 3))
  guard (response as? HTTPURLResponse)?.statusCode == 200,
        Date().timeIntervalSince(start) < 1.5, data.count > 0 else { fatalError("cancelled generation still blocked the worker") }
  print("URLSession cancellation stopped generation; next request completed in", Date().timeIntervalSince(start))
 }
}
''')
        executable = self.root / "cancel"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(client), "-o", str(executable)], check=True, capture_output=True)
        result = subprocess.run([str(executable), self.url], check=True, capture_output=True, text=True, timeout=8)
        print(result.stdout.strip())

    def test_failed_install_preserves_previous_model_and_success_replaces_it(self):
        (self.root / "huggingface_hub.py").write_text('''
import os
def snapshot_download(repository, revision, local_dir, **kwargs):
    local_dir.mkdir(parents=True, exist_ok=True)
    (local_dir / "weights.safetensors").write_text("replacement weights")
    if os.environ.get("FAIL_INSTALL"): raise RuntimeError("synthetic interrupted download")
''')
        command = [os.sys.executable, str(self.root / "worker.py"), "install", "--root", str(self.root), "--model", "fixture"]
        failed = subprocess.run(command, env={**os.environ, "FAIL_INSTALL": "1"}, capture_output=True)
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual((self.root / "models/fixture/weights.safetensors").read_text(), "original weights")
        self.assertTrue((self.root / "models/fixture/installed.json").exists())
        subprocess.run(command, check=True, capture_output=True)
        self.assertEqual((self.root / "models/fixture/weights.safetensors").read_text(), "replacement weights")
        self.assertEqual(json.loads((self.root / "models/fixture/installed.json").read_text())["revision"], self.item["revision"])
        self.assertFalse((self.root / "models/fixture.previous").exists())

    def test_stale_model_marker_is_rejected(self):
        (self.root / "models/fixture/installed.json").write_text('{"revision":"old"}')
        self.start()
        self.assertEqual(self.request()[0], 400)


if __name__ == "__main__":
    unittest.main()
