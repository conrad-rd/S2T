#!/usr/bin/env python3
"""Generate and prepare S2T UI sound candidates with ElevenLabs.

Reads the API key from stdin. It never writes the key to disk or prints it.
Existing source clips are reused, so interrupted runs can be resumed.
"""

import argparse
import array
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import math
from pathlib import Path
import ssl
import subprocess
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Resources" / "Sounds" / "Candidates-Liquid"
REFERENCE_SECTION = ""
FAMILIES = {
    "glow": ("Bottom / Around Notch", "wide hazy fluid ribbon"),
    "input": ("Around Input / Within Input", "close liquid thread tracing a padded rim"),
    "classic": ("Classic / Liquid Glass", "round elastic gel ripple in soft glass"),
}
EVENTS = {
    "open": ("Start listening", "unfurls upward"),
    "processing": ("Start processing", "turns in place, unresolved"),
    "complete": ("Successful delivery", "folds inward and settles"),
}
VARIATIONS = [
    "Two short low swells followed by a delayed longer slip.",
    "Three lopsided pulses, long then short then short, with a downward curl.",
    "A delayed first pulse and two overlapping soft swirls, slightly rising.",
    "A nearly silent double catch, then one smooth downward slide.",
    "An uneven tiny triplet with a faint reverse-suction texture.",
    "One quiet rise, a small pause, then two pulses closer together.",
    "A gentle wobble that splits into two soft ripples and fades.",
    "Two interleaved left-right liquid strands, spatial movement barely audible.",
    "Three restrained stutters that accelerate gently into a soft tail.",
    "A longer curling slide followed by two quieter staggered after-movements.",
]
STAGGERS = [(.085, .235), (.135, .260), (.095, .180), (.070, .225),
            (.115, .195), (.175, .285), (.140, .300), (.105, .245),
            (.065, .160), (.155, .315)]


def prompt(family, event, variation):
    return (
        f"Soft synthetic liquid UI sound: {FAMILIES[family][1]}; {EVENTS[event][1]}. "
        f"{variation} "
        "A fluid filament makes two or three uneven micro-surges, a small serpentine pitch bend, "
        "and faint friction beneath a rounded hollow tone. Very damp, quiet, close and dry. "
        "No beep, chime, melody, splash, hard click, sharp hiss, voice, music or reverb."
    )


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True)


def source_clip(key, family, event, number):
    directory = OUTPUT / family / event
    directory.mkdir(parents=True, exist_ok=True)
    source = directory / f"{number:02d}.source.mp3"
    if source.is_file() and source.stat().st_size > 1000:
        return source
    body = json.dumps({
        "text": prompt(family, event, VARIATIONS[number - 1]),
        "duration_seconds": {"open": 1.6, "processing": 1.75, "complete": 1.5}[event],
        "prompt_influence": 0.7,
        "model_id": "eleven_text_to_sound_v2",
        "loop": False,
    }).encode()
    request = Request("https://api.elevenlabs.io/v1/sound-generation", data=body,
                      headers={"xi-api-key": key, "Content-Type": "application/json"}, method="POST")
    for attempt in range(5):
        try:
            with urlopen(request, timeout=90, context=ssl.create_default_context(cafile="/etc/ssl/cert.pem")) as response:
                data = response.read()
                if not response.headers.get("Content-Type", "").startswith("audio/"):
                    raise RuntimeError(f"Unexpected ElevenLabs response type: {response.headers.get('Content-Type')}")
                break
        except HTTPError as error:
            detail = error.read().decode(errors="replace")[:500]
            if error.code not in (429, 500, 502, 503, 504) or attempt == 4:
                raise RuntimeError(f"ElevenLabs HTTP {error.code}: {detail}") from None
            time.sleep(min(20, 2 ** attempt + 1))
    if len(data) < 1000:
        raise RuntimeError("ElevenLabs returned an empty sound")
    temporary = source.with_suffix(".partial")
    temporary.write_bytes(data)
    temporary.replace(source)
    return source


def soften(source, reprocess=False):
    output = source.with_name(source.name.replace(".source.mp3", ".mp3"))
    if not reprocess and output.is_file() and output.stat().st_size > 1000:
        return output
    duration = float(run("ffprobe", "-v", "error", "-show_entries", "format=duration",
                         "-of", "default=noprint_wrappers=1:nokey=1", str(source)).stdout.strip())
    base_filters = "highpass=f=120,lowpass=f=3200"
    decoded = subprocess.run(["ffmpeg", "-v", "error", "-i", str(source), "-af", base_filters,
                              "-ac", "2", "-ar", "44100", "-f", "f32le", "-"], capture_output=True, check=True).stdout
    samples = array.array("f")
    samples.frombytes(decoded)
    if not samples:
        raise RuntimeError(f"No decoded audio: {source}")
    delay_one, delay_two = STAGGERS[int(source.name[:2]) - 1]
    first = round(delay_one * 44100)
    second = round(delay_two * 44100)
    frames = len(samples) // 2
    shaped = array.array("f", [0.0]) * len(samples)
    for frame in range(frames):
        time_at_frame = frame / 44100
        fade = min(1.0, time_at_frame / 0.025, (duration - time_at_frame) / 0.24)
        fade = max(0.0, fade)
        dry = frame * 2
        echo_one = max(0, frame - first) * 2
        echo_two = max(0, frame - second) * 2
        for channel in (0, 1):
            a = samples[echo_one + channel] if frame >= first else 0.0
            b = samples[echo_two + channel] if frame >= second else 0.0
            shaped[dry + channel] = fade * (0.68 * samples[dry + channel]
                + (0.25 if channel == 0 else 0.16) * a
                + (0.14 if channel == 0 else 0.23) * b)
    rms = math.sqrt(sum(sample * sample for sample in shaped) / len(shaped))
    if rms < 1e-6:
        raise RuntimeError(f"Silent generated audio: {source}")
    gain = max(-24.0, min(40.0, -38.0 - 20 * math.log10(rms)))
    filters = f"volume={gain:.2f}dB,alimiter=limit=0.075:attack=2:release=20:level=disabled"
    temporary = output.with_suffix(".partial.mp3")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", "2", "-ar", "44100",
                    "-i", "-", "-af", filters, "-codec:a", "libmp3lame", "-q:a", "3", str(temporary)],
                   input=shaped.tobytes(), capture_output=True, check=True)
    temporary.replace(output)
    return output


def make_index(entries):
    from html import escape
    sections = []
    for family, (title, _) in FAMILIES.items():
        for event, (event_title, _) in EVENTS.items():
            rows = []
            for entry in entries:
                if entry["family"] != family or entry["event"] != event:
                    continue
                rows.append(
                    f'<div class="option"><label><input type="radio" name="{family}-{event}" value="{entry["number"]:02d}">'
                    f'{entry["number"]:02d}</label>'
                    f'<audio controls preload="none" aria-label="{title} {event_title} option {entry["number"]:02d}" src="{entry["file"]}"></audio>'
                    f'<small>{escape(VARIATIONS[entry["number"] - 1])} · <a href="{entry["file"]}" download>MP3</a></small></div>'
                )
            sections.append(f'<section><h2>{title} · {event_title}</h2>\n' + "\n".join(rows) + "\n</section>")
    html = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>S2T liquid sound candidates</title><style>
body{background:#151515;color:#f3f3f3;font:15px -apple-system,BlinkMacSystemFont,sans-serif;max-width:900px;margin:42px auto;padding:0 24px}
h1{font-size:30px;letter-spacing:-.04em}p{color:#aaa;line-height:1.5}section{margin:48px 0}h2{font-size:18px;font-weight:600}
.option{display:grid;grid-template-columns:58px 260px 1fr;align-items:center;gap:18px;padding:8px 0;border-top:1px solid #292929}
.option label{font-variant-numeric:tabular-nums;color:#aaa;cursor:pointer}.option input{accent-color:#c6b6ff;margin-right:8px}.option small{color:#999}audio{width:260px;height:32px}a{color:#c6b6ff}
textarea{box-sizing:border-box;width:100%;min-height:100px;background:#202020;color:#eee;border:1px solid #444;border-radius:8px;padding:12px;font:13px ui-monospace,monospace}
@media(max-width:700px){.option{grid-template-columns:28px 1fr}.option small{grid-column:2}audio{width:100%}}
</style><h1>Liquid sound candidates</h1><p>Soft, damp liquid cues with small staggered movements. Start is for listening, processing is for the moment recording ends, and completion follows successful delivery. Each ElevenLabs original is saved beside its softened copy. Select one per section and send back the list below.</p>
<textarea id="choices" readonly aria-label="Selected sounds"></textarea>
''' + "\n".join(sections) + '''<script>
const choices = document.getElementById('choices');
document.addEventListener('change', () => {
  choices.value = [...document.querySelectorAll('input[type="radio"]:checked')]
    .map(input => `${input.name}: ${input.value}`).join('\\n');
});
document.addEventListener('play', event => {
  if (event.target.tagName === 'AUDIO') document.querySelectorAll('audio').forEach(audio => {
    if (audio !== event.target) audio.pause();
  });
}, true);
</script></html>'''
    if REFERENCE_SECTION:
        html = html.replace('<textarea id="choices"', REFERENCE_SECTION + '<textarea id="choices"', 1)
    (OUTPUT / "index.html").write_text(html)
    (OUTPUT / "manifest.json").write_text(json.dumps(entries, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, help="Generate only the first N missing candidates")
    parser.add_argument("--family", choices=FAMILIES)
    parser.add_argument("--event", choices=EVENTS)
    parser.add_argument("--number", type=int, choices=range(1, 11))
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--reprocess", action="store_true", help="Rebuild listening copies from saved ElevenLabs originals")
    args = parser.parse_args()
    jobs = [(family, event, number) for family in FAMILIES for event in EVENTS for number in range(1, 11)]
    jobs = [job for job in jobs if (args.family is None or job[0] == args.family)
            and (args.event is None or job[1] == args.event)
            and (args.number is None or job[2] == args.number)]
    if args.limit is not None:
        jobs = jobs[:args.limit]
    if all((OUTPUT / family / event / f"{number:02d}.source.mp3").is_file() for family, event, number in jobs):
        key = ""
    else:
        key = sys.stdin.readline().strip()
        if not key:
            raise SystemExit("Pass the ElevenLabs API key on stdin")
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(source_clip, key, *job): job for job in jobs}
        for future in as_completed(futures):
            job = futures[future]
            source = future.result()
            output = soften(source, reprocess=args.reprocess)
            print(f"Ready: {job[0]}/{job[1]}/{job[2]:02d} ({output.stat().st_size} bytes)", flush=True)
    entries = [dict(family=family, event=event, number=number,
                    file=f"{family}/{event}/{number:02d}.mp3",
                    source=f"{family}/{event}/{number:02d}.source.mp3",
                    prompt=prompt(family, event, VARIATIONS[number - 1]))
               for family, event, number in [(family, event, number) for family in FAMILIES for event in EVENTS for number in range(1, 11)]
               if (OUTPUT / family / event / f"{number:02d}.mp3").is_file()]
    make_index(entries)
    print(f"Audition page: {OUTPUT / 'index.html'} ({len(entries)} sounds)")


if __name__ == "__main__":
    main()
