"""S2T's private, loopback-only MLX worker. No request content is logged."""
import argparse
import base64
import gc
import io
import json
import os
from pathlib import Path
import sys
sys.dont_write_bytecode = True
from response_text import final_text
import secrets
import select
import socket
import shutil
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from email.parser import BytesParser
from email.policy import default

parser = argparse.ArgumentParser()
parser.add_argument("action", choices=["install", "serve"])
parser.add_argument("--root", required=True)
parser.add_argument("--model")
parser.add_argument("--idle-seconds", type=int, default=120, choices=range(5, 121))
args = parser.parse_args()
root = Path(args.root)
catalog = {item["id"]: item for item in json.loads(Path(__file__).with_name("catalog.json").read_text())}
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
os.environ["HF_HOME"] = str(root / "cache")
os.environ["TOKENIZERS_PARALLELISM"] = "false"

if args.action == "install":
    from huggingface_hub import snapshot_download
    item = catalog[args.model]
    destination = root / "models" / item["id"]
    staging = root / "downloads" / item["id"]
    snapshot_download(item["repository"], revision=item["revision"], local_dir=staging,
                      allow_patterns=["*.json", "*.safetensors", "*.txt", "*.model", "*.tiktoken", "*.jinja"],
                      max_workers=2)
    marker = staging / "installed.json"
    pending = staging / "installed.next"
    pending.write_text(json.dumps({"revision": item["revision"]}))
    pending.replace(marker)
    destination.parent.mkdir(parents=True, exist_ok=True)
    backup = destination.with_name(destination.name + ".previous")
    if backup.exists():
        if not destination.exists():
            backup.replace(destination)
        else:
            shutil.rmtree(backup)
    if destination.exists():
        destination.replace(backup)
    try:
        staging.replace(destination)
    except BaseException:
        if backup.exists():
            backup.replace(destination)
        raise
    if backup.exists():
        shutil.rmtree(backup)
    print("Installed", flush=True)
    raise SystemExit(0)

os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
import mlx.core as mx
mx.set_cache_limit(128 * 1024 * 1024)
lock = threading.Lock()
loaded = None
loaded_id = None
last_used = time.monotonic()
parent = os.getppid()
token = secrets.token_urlsafe(32)


class ClientDisconnected(Exception):
    pass


def unload():
    global loaded, loaded_id
    loaded = None
    loaded_id = None
    gc.collect()
    mx.clear_cache()


def model_for(identifier, category):
    global loaded, loaded_id, last_used
    item = catalog.get(identifier)
    if item is None or item["category"] != category:
        raise ValueError("Choose an installed model for this task.")
    directory = root / "models" / identifier
    marker = directory / "installed.json"
    if not marker.exists() or json.loads(marker.read_text()).get("revision") != item["revision"]:
        raise ValueError("Install this model in Settings first.")
    if loaded_id != identifier:
        unload()
        if category == "text":
            from mlx_lm import load
        elif category == "speech":
            from mlx_audio.stt.utils import load
        else:
            raise ValueError("Unsupported model category.")
        loaded = load(str(directory))
        loaded_id = identifier
    last_used = time.monotonic()
    return loaded


def supervise():
    while True:
        time.sleep(5)
        if os.getppid() != parent:
            os._exit(0)
        if lock.acquire(blocking=False):
            try:
                if loaded is not None and time.monotonic() - last_used > args.idle_seconds:
                    unload()
            finally:
                lock.release()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *unused):
        pass

    def check_connected(self):
        # Requests use HTTP/1.0. Cancelling URLSession closes this connection.
        if select.select([self.connection], [], [], 0)[0]:
            if not self.connection.recv(1, socket.MSG_PEEK):
                raise ClientDisconnected()

    def reply(self, status, body, content_type="application/json"):
        data = json.dumps(body).encode() if isinstance(body, dict) else body
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path != "/" + token + "/v1/status":
            self.reply(404, {"error": "Not found"})
            return
        with lock:
            self.reply(200, {"loaded_model": loaded_id, "active_memory_bytes": mx.get_active_memory()})

    def do_POST(self):
        if not self.path.startswith("/" + token + "/"):
            self.reply(404, {"error": "Not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 64 * 1024 * 1024:
                raise ValueError("Request exceeds the local processing limit.")
            body = self.rfile.read(length)
            if len(body) != length:
                raise ClientDisconnected()
            with lock:
                self.check_connected()
                self.process(body)
        except (ClientDisconnected, BrokenPipeError, ConnectionResetError):
            pass
        except ValueError as error:
            self.reply(400, {"error": {"message": str(error)}})
        except Exception:
            self.reply(500, {"error": {"message": "Local inference failed. Check the model installation and available memory."}})

    def process(self, body):
        global last_used
        if self.path.endswith("/audio/transcriptions"):
            mime = BytesParser(policy=default).parsebytes(
                b"Content-Type: " + self.headers["Content-Type"].encode() + b"\r\nMIME-Version: 1.0\r\n\r\n" + body)
            fields = {part.get_param("name", header="content-disposition"): part.get_payload(decode=True)
                      for part in mime.iter_parts()}
            identifier = fields["model"].decode()
            model = model_for(identifier, "speech")
            import soundfile as sf
            import numpy as np
            audio, rate = sf.read(io.BytesIO(fields["file"]), dtype="float32")
            if audio.ndim > 1:
                audio = audio.mean(axis=1)
            if rate != 16000:
                from scipy.signal import resample_poly
                import math
                divisor = math.gcd(rate, 16000)
                audio = resample_poly(audio, 16000 // divisor, rate // divisor)
            result = model.generate(mx.array(np.asarray(audio)))
            self.reply(200, {"text": result.text})
        elif self.path.endswith("/chat/completions"):
            data = json.loads(body)
            limit = data.get("max_tokens", 2048)
            if type(limit) is not int or not 1 <= limit <= 8192:
                raise ValueError("max_tokens must be an integer between 1 and 8192.")
            model, tokenizer = model_for(data["model"], "text")
            self.check_connected()
            prompt = tokenizer.apply_chat_template(data["messages"], tokenize=False,
                                                   add_generation_prompt=True, enable_thinking=False, reasoning_effort="low")
            if len(tokenizer.encode(prompt)) > 8192:
                raise ValueError("Text exceeds the local context limit.")
            from mlx_lm import stream_generate
            chunks = []
            tokens = []
            finish = "length"
            for chunk in stream_generate(model, tokenizer, prompt=prompt, max_tokens=limit):
                self.check_connected()
                chunks.append(chunk.text)
                tokens.append(chunk.token)
                finish = chunk.finish_reason or finish
            output_format = catalog[data["model"]].get("outputFormat", "text")
            raw = tokenizer.decode(tokens, skip_special_tokens=False) if output_format == "harmony" else "".join(chunks)
            result = final_text(raw, output_format)
            self.reply(200, {"model": data["model"], "provider": "On this Mac",
                             "choices": [{"finish_reason": finish, "message": {"content": result}}]})
        else:
            self.reply(404, {"error": "Not found"})
        last_used = time.monotonic()

threading.Thread(target=supervise, daemon=True).start()
server = HTTPServer(("127.0.0.1", 0), Handler)
server.timeout = 1
print(json.dumps({"endpoint": f"http://127.0.0.1:{server.server_port}/{token}/v1"}), flush=True)
import sys
sys.stdout = open(os.devnull, "w")
server.serve_forever()
