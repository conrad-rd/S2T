#!/usr/bin/env python3
"""Small digital UI sound study, with ElevenLabs takes and exact synth controls.

Reads an ElevenLabs key from stdin only when a source take is missing.
"""

import array
from concurrent.futures import ThreadPoolExecutor, as_completed
from html import escape
import json
import math
from pathlib import Path
import random
import ssl
import subprocess
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1] / "Resources" / "Sounds" / "Calibration-Digital"
ROOT.mkdir(parents=True, exist_ok=True)
GROUPS = {
    "fm": ("Sliding signal", "A band-limited FM tone bending through an irregular three-step gesture."),
    "grain": ("Soft digital scatter", "A few tiny synthetic grains that skitter, then disappear."),
    "coupled": ("Elastic circuit", "Two rounded oscillators moving against each other, with a restrained stagger."),
    "synth": ("Exact synth sketches", "Hand-built electronic cues for comparison with the generated takes."),
}
RHYTHMS = [
    "Two close, soft pulses and one delayed longer pitch curl.",
    "A quiet first pulse, a short pause, then two overlapping pitch bends.",
    "Three uneven micro-pulses that speed up slightly and fade.",
]
PROMPT_BASES = {
    "fm": "Purely synthesized digital interface cue. Rounded frequency-modulated oscillator with a narrow filtered noise edge. A sliding pitch curls gently sideways. Dark treble, smooth attack, dry fade. Quiet and intimate, with no acoustic foley, music, or voice.",
    "grain": "Purely electronic interface cue. A small cloud of smooth granular synth particles follows a curved pitch glide. Short grains overlap in an uneven rhythm but never click sharply. Soft, dark, dry, quiet. No acoustic foley, ambience, music, or voice.",
    "coupled": "Purely synthesized interface cue. Two softly coupled oscillators beat and bend against each other, making a rounded elastic digital motion. A faint filtered noise breath sits behind the tone. Staggered, restrained, dry, quiet. No acoustic foley, music, or voice.",
}
PILOTS = [
    dict(id=f"{group}-{number:02d}", group=group,
         prompt=f"{PROMPT_BASES[group]} {rhythm}", duration=0.95 if group == "fm" else 1.05)
    for group in ("fm", "grain", "coupled") for number, rhythm in enumerate(RHYTHMS, 1)
]


def request_sound(key, pilot):
    source = ROOT / f"{pilot['id']}.source.mp3"
    if source.is_file() and source.stat().st_size > 1000:
        return source
    body = json.dumps({"text": pilot["prompt"], "duration_seconds": pilot["duration"],
                       "prompt_influence": 0.78, "model_id": "eleven_text_to_sound_v2", "loop": False}).encode()
    request = Request("https://api.elevenlabs.io/v1/sound-generation", data=body,
                      headers={"xi-api-key": key, "Content-Type": "application/json"}, method="POST")
    for attempt in range(5):
        try:
            with urlopen(request, timeout=90, context=ssl.create_default_context(cafile="/etc/ssl/cert.pem")) as response:
                data = response.read()
                if not response.headers.get("Content-Type", "").startswith("audio/"):
                    raise RuntimeError("ElevenLabs did not return audio")
                break
        except HTTPError as error:
            detail = error.read().decode(errors="replace")[:500]
            if error.code not in (429, 500, 502, 503, 504) or attempt == 4:
                raise RuntimeError(f"ElevenLabs HTTP {error.code}: {detail}") from None
            time.sleep(min(20, 2 ** attempt + 1))
    if len(data) < 1000:
        raise RuntimeError("Empty ElevenLabs sound")
    temporary = source.with_suffix(".partial")
    temporary.write_bytes(data)
    temporary.replace(source)
    return source


def encode(samples, path):
    rms = math.sqrt(sum(x * x for x in samples) / len(samples))
    if rms < 1e-6:
        raise RuntimeError(f"Silent cue: {path}")
    gain = max(-48, min(36, -39 - 20 * math.log10(rms)))
    temporary = path.with_suffix(".partial.mp3")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", "2", "-ar", "44100",
                    "-i", "-", "-af", f"volume={gain:.2f}dB,alimiter=limit=0.085:attack=2:release=20:level=disabled",
                    "-codec:a", "libmp3lame", "-q:a", "3", str(temporary)],
                   input=samples.tobytes(), capture_output=True, check=True)
    temporary.replace(path)


def prepare_generated(source):
    output = source.with_name(source.name.replace(".source.mp3", ".mp3"))
    if output.is_file() and output.stat().st_size > 1000:
        return output
    data = subprocess.run(["ffmpeg", "-v", "error", "-i", str(source), "-af",
                           "highpass=f=110,lowpass=f=4800,afade=t=in:st=0:d=0.015,afade=t=out:st=0.75:d=0.25",
                           "-ac", "2", "-ar", "44100", "-f", "f32le", "-"],
                          capture_output=True, check=True).stdout
    samples = array.array("f")
    samples.frombytes(data)
    encode(samples, output)
    return output


def synthesize(number):
    path = ROOT / f"synth-{number:02d}-soft.mp3"
    if path.is_file() and path.stat().st_size > 1000:
        return path
    duration = 0.95
    sample_rate = 44100
    seeds = [(570, (.085, .205, .385), (0.048, 0.057, 0.086), 1.4),
             (710, (.070, .235, .335), (0.045, 0.070, 0.055), 1.1),
             (480, (.085, .185, .365), (0.065, 0.045, 0.075), 1.7),
             (630, (.100, .275, .400), (0.060, 0.055, 0.065), 1.25)]
    base, centers, widths, fm_index = seeds[number - 1]
    rng = random.Random(7200 + number)
    samples = array.array("f")
    carrier = modulator = noise = 0.0
    for i in range(round(duration * sample_rate)):
        t = i / sample_rate
        envelope = sum(level * math.exp(-0.5 * ((t - center) / width) ** 2)
                       for level, center, width in zip((1.0, 0.72, 0.48), centers, widths))
        pitch = base * (1 + 0.09 * math.sin(2 * math.pi * (1.15 * t + 0.14 * t * t)))
        carrier += 2 * math.pi * pitch / sample_rate
        modulator += 2 * math.pi * pitch * (1.73 + number * 0.045) / sample_rate
        noise = 0.92 * noise + 0.08 * rng.uniform(-1, 1)
        tone = math.sin(carrier + fm_index * math.sin(modulator)) + 0.08 * noise
        sample = envelope * tone
        pan = 0.08 * math.sin(2 * math.pi * 2.3 * t)
        samples.extend((sample * (1 - pan), sample * (1 + pan)))
    encode(samples, path)
    return path


def make_page(entries):
    sections = []
    for group, (title, description) in GROUPS.items():
        rows = []
        for entry in entries:
            if entry["group"] != group:
                continue
            rows.append(f'<div class="row"><label><input type="radio" name="direction" value="{entry["id"]}">'
                        f'{escape(entry["id"])}</label><audio controls preload="none" src="{entry["file"]}" '
                        f'aria-label="{escape(entry["id"])}"></audio></div>')
        sections.append(f'<section><h2>{title}</h2><p>{description}</p>{"".join(rows)}</section>')
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Digital sound direction for S2T</title><style>
body{background:#151515;color:#f2f2f2;font:15px -apple-system,BlinkMacSystemFont,sans-serif;max-width:820px;margin:42px auto;padding:0 24px}
h1{font-size:30px;letter-spacing:-.04em}h2{font-size:19px}p{color:#aaa;line-height:1.5}section{margin:38px 0}
.row{display:grid;grid-template-columns:130px 1fr;align-items:center;gap:16px;padding:9px 0;border-top:1px solid #303030}
.row label{font-variant-numeric:tabular-nums;cursor:pointer}.row input{accent-color:#b7b3ff;margin-right:9px}audio{height:32px;width:min(100%,360px)}
@media(max-width:560px){.row{grid-template-columns:1fr}.row audio{width:100%}}
</style><h1>Digital sound study</h1><p>These test the sound character before another large batch. They use electronic tones and uneven motion, with no water or acoustic foley in the prompts. Pick the closest one, even if it still needs work.</p>
''' + "\n".join(sections) + "</html>"
    (ROOT / "index.html").write_text(page)
    (ROOT / "manifest.json").write_text(json.dumps(entries, indent=2) + "\n")


def main():
    if max(len(pilot["prompt"]) for pilot in PILOTS) > 450:
        raise RuntimeError("ElevenLabs prompt exceeds 450 characters")
    missing = [pilot for pilot in PILOTS if not (ROOT / f"{pilot['id']}.source.mp3").is_file()]
    key = sys.stdin.readline().strip() if missing else ""
    if missing and not key:
        raise SystemExit("Pass the ElevenLabs API key on stdin")
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = {pool.submit(request_sound, key, pilot): pilot for pilot in PILOTS}
        for future in as_completed(futures):
            source = future.result()
            print("Ready:", prepare_generated(source).name, flush=True)
    entries = [dict(id=pilot["id"], group=pilot["group"], file=f"{pilot['id']}.mp3",
                    prompt=pilot["prompt"], source=f"{pilot['id']}.source.mp3") for pilot in PILOTS]
    for number in range(1, 5):
        output = synthesize(number)
        print("Ready:", output.name, flush=True)
        entries.append(dict(id=f"synth-{number:02d}", group="synth", file=output.name,
                            prompt="Deterministic FM synth with three uneven filtered pulses"))
    make_page(entries)
    print("Audition page:", ROOT / "index.html")


if __name__ == "__main__":
    main()
