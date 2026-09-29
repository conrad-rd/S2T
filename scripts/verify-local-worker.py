"""Exercise installed models with synthesized audio and text."""
import argparse
import json
from pathlib import Path
import subprocess
import time
import urllib.request

root = Path(__file__).resolve().parent.parent
fixture = root / "build/local-verification"
python = fixture / "final-runtime/bin/python3"
catalog = json.loads((root / "Resources/LocalModels/catalog.json").read_text())
parser = argparse.ArgumentParser()
parser.add_argument("--models", nargs="+", choices=[m["id"] for m in catalog])
selected = parser.parse_args().models
if selected:
    catalog = [m for m in catalog if m["id"] in selected]
worker = subprocess.Popen([str(python), str(root / "Resources/LocalModels/worker.py"),
                           "serve", "--root", str(fixture / "data"), "--idle-seconds", "5"],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
try:
    address = json.loads(worker.stdout.readline())["endpoint"]
    def request(path, payload, content_type="application/json"):
        body = json.dumps(payload).encode() if isinstance(payload, dict) else payload
        req = urllib.request.Request(address + path, data=body, headers={"Content-Type": content_type})
        with urllib.request.urlopen(req, timeout=180) as response:
            return json.load(response)

    results = []
    for model in [m for m in catalog if m["category"] == "text"]:
        payload = {"model": model["id"], "messages": [
            {"role": "system", "content": "Fix capitalization and spelling. Return only the corrected sentence."},
            {"role": "user", "content": "the cat is sleeping."}]}
        timings = []
        for attempt in range(2):
            started = time.monotonic()
            result = request("/chat/completions", payload)
            timings.append(round(time.monotonic() - started, 3))
            assert result["choices"][0]["finish_reason"] == "stop", result
            answer = result["choices"][0]["message"]["content"]
            assert "cat" in answer.lower(), result
            assert not any(marker in answer for marker in ("<|channel|>", "<|meta_sep|>", "<|message|>", "<think>")), result
            assert result["provider"] == "On this Mac"
        results.append({"model": model["id"], "cold_seconds": timings[0], "warm_seconds": timings[1]})
        print(json.dumps(results[-1]), flush=True)

    # This file is synthesized with say -o and afconvert, never recorded.
    audio = (fixture / "fixture.wav").read_bytes()
    for model in [m for m in catalog if m["category"] == "speech"]:
        boundary = "s2t-fixture-boundary"
        body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n{model['id']}\r\n"
                f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"fixture.wav\"\r\n"
                "Content-Type: audio/wav\r\n\r\n").encode() + audio + f"\r\n--{boundary}--\r\n".encode()
        started = time.monotonic()
        transcript = request("/audio/transcriptions", body, "multipart/form-data; boundary=" + boundary)["text"]
        assert "blue" in transcript.lower() and "circle" in transcript.lower(), transcript
        results.append({"model": model["id"], "cold_seconds": round(time.monotonic() - started, 3), "transcript": transcript})
        print(json.dumps(results[-1]), flush=True)

    with urllib.request.urlopen(address + "/status", timeout=5) as response:
        active = json.load(response)
    assert active["loaded_model"] == results[-1]["model"]
    time.sleep(11)
    with urllib.request.urlopen(address + "/status", timeout=5) as response:
        idle = json.load(response)
    assert idle["loaded_model"] is None and idle["active_memory_bytes"] < active["active_memory_bytes"], (active, idle)
    print(json.dumps({"passed": True, "idle_unload": True, "active_memory_bytes": active["active_memory_bytes"],
                      "idle_memory_bytes": idle["active_memory_bytes"], "models": len(results)}), flush=True)
finally:
    worker.terminate()
    try:
        worker.wait(timeout=10)
    except subprocess.TimeoutExpired:
        worker.kill()
        worker.wait()
