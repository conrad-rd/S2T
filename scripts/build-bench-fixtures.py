"""Generate local speech fixtures, never microphone or screen recordings."""
import array
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import subprocess
import wave

parser = argparse.ArgumentParser()
parser.add_argument("destination", type=Path)
parser.add_argument("--voice", default=os.environ.get("S2T_BENCH_VOICE", "Samantha"))
parser.add_argument("--say-executable", type=Path, default=Path("/usr/bin/say"))
arguments = parser.parse_args()
destination = arguments.destination
destination.mkdir(parents=True, exist_ok=True)
text = "Do not ship the blue circle before Tuesday. Keep the red square above the green triangle. Maya has not approved the release."
for name, rate in [("clean", 170), ("fast", 270)]:
    subprocess.run([str(arguments.say_executable), "-v", arguments.voice, "--file-format=WAVE", "--data-format=LEI16@16000", "--channels=1", "-r", str(rate), "-o", str(destination / (name + ".wav")), text], check=True)
with wave.open(str(destination / "clean.wav"), "rb") as source:
    params = source.getparams()
    original = array.array("h", source.readframes(source.getnframes()))
if params.nchannels != 1 or params.sampwidth != 2 or params.framerate != 16000 or not original:
    raise RuntimeError(f"Voice {arguments.voice!r} did not produce nonempty mono 16-bit 16 kHz audio")
with wave.open(str(destination / "fast.wav"), "rb") as source:
    if source.getnchannels() != 1 or source.getsampwidth() != 2 or source.getframerate() != 16000 or source.getnframes() == 0:
        raise RuntimeError(f"Voice {arguments.voice!r} did not produce the fast speech fixture")
rng = random.Random(42)
rms = math.sqrt(sum(value * value for value in original) / max(1, len(original)))
for name in ["noise-10db", "quiet"]:
    if name == "noise-10db":
        samples = [max(-32768, min(32767, round(value + rng.gauss(0, rms / math.sqrt(10))))) for value in original]
    else:
        samples = [round(value * 0.05) for value in original]
    with wave.open(str(destination / (name + ".wav")), "wb") as output:
        output.setparams(params)
        output.writeframes(array.array("h", samples).tobytes())
cases = []
for name in ["clean", "fast", "noise-10db", "quiet"]:
    audio_path = destination / (name + ".wav")
    with wave.open(str(audio_path), "rb") as audio:
        duration = audio.getnframes() / audio.getframerate()
    payload = audio_path.read_bytes()
    cases.append(dict(name=name, text=text, seconds=duration, file=name + ".wav",
        maxWER=0.05 if name == "clean" else 0.10, bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest()))
manifest = dict(schema=2, generator={"tool": str(arguments.say_executable), "voice": arguments.voice,
    "sampleRate": "16000", "channels": "1", "sourceTextSHA256": hashlib.sha256(text.encode()).hexdigest()}, cases=cases)
(destination / "speech.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
