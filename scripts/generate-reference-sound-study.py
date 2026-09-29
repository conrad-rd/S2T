#!/usr/bin/env python3
"""Create original, short UI cues informed by installed app cue timing.

These are synthesized from oscillators. No third-party audio is copied.
"""

import array
from html import escape
import json
import math
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1] / "Resources" / "Sounds" / "Reference-Study"
ROOT.mkdir(parents=True, exist_ok=True)
RATE = 48000


def smoothstep(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


def voice(t, start, length, frequency, bend, weight, texture):
    u = (t - start) / length
    if u <= 0 or u >= 1:
        return 0.0
    envelope = smoothstep(u / 0.11) * (1 - smoothstep((u - 0.31) / 0.69))
    envelope *= math.exp(-0.65 * u)
    phase = 2 * math.pi * frequency * length * (u + bend * (u * u / 2 - u * u * u / 3))
    fundamental = math.sin(phase)
    overtone = math.sin(2.01 * phase + 0.35 * math.sin(2 * math.pi * 5 * u))
    partial = math.sin(3.07 * phase + 0.8)
    return weight * envelope * ((1 - texture) * fundamental + texture * (0.7 * overtone + 0.22 * partial))


def render(family, event, variant):
    base = 620 if family == "flow" else 740
    texture = 0.11 if family == "flow" else 0.19
    if variant == 2:
        base *= 0.84
        texture *= 1.12
    if event == "start":
        duration = 0.26
        notes = [(0.012, 0.105, base, 0.19, 0.72), (0.060, 0.145, base * 1.29, -0.11, 0.48)]
    elif event == "processing":
        duration = 0.42
        notes = [(0.018, 0.11, base * 0.90, -0.09, 0.40),
                 (0.135, 0.13, base, 0.13, 0.48),
                 (0.254, 0.13, base * 1.08, -0.08, 0.33)]
    else:
        duration = 0.34
        notes = [(0.012, 0.14, base * 1.12, -0.13, 0.56),
                 (0.083, 0.19, base * 0.93, -0.18, 0.62)]
    if family == "discord":
        notes = [(s, l * 1.06, f, b * 0.78, w) for s, l, f, b, w in notes]
        duration += 0.035
    if variant == 2:
        notes = [(s + (0.010 if i else 0), l * 1.12, f, b * 1.45, w)
                 for i, (s, l, f, b, w) in enumerate(notes)]
    samples = array.array("f")
    for n in range(round(duration * RATE)):
        t = n / RATE
        v = sum(voice(t, *note, texture) for note in notes)
        # Tiny detuned shadow gives body without an acoustic or watery layer.
        shadow = sum(voice(t, s + 0.003, l, f * 0.997, b, w * 0.15, texture)
                     for s, l, f, b, w in notes)
        fade = min(1.0, (duration - t) / 0.045)
        samples.append((v + shadow) * fade * 0.065)
    return samples


def encode(samples, path):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", "1", "-ar", str(RATE),
         "-i", "-", "-af", "lowpass=f=4200,alimiter=limit=0.12:attack=2:release=20:level=disabled",
         "-codec:a", "libmp3lame", "-q:a", "3", str(path)],
        input=samples.tobytes(), capture_output=True, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr.decode())


def page(entries):
    sections = []
    for family, title, detail in [
        ("flow", "Soft and close", "Short, rounded gestures based on the timing of Flow's dictation cues."),
        ("discord", "Compact double swell", "A brighter pair of rounded peaks, informed by Discord's mute and unmute cues."),
    ]:
        rows = []
        for e in entries:
            if e["family"] != family:
                continue
            rows.append(f'<div class="row"><span>{escape(e["label"])}</span><audio controls preload="none" '
                        f'src="{e["file"]}" aria-label="{escape(e["label"])}"></audio></div>')
        sections.append(f"<section><h2>{title}</h2><p>{detail}</p>{''.join(rows)}</section>")
    html = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>S2T reference sound study</title><style>
body{background:#151515;color:#f2f2f2;font:15px -apple-system,BlinkMacSystemFont,sans-serif;max-width:840px;margin:40px auto;padding:0 24px}
h1{font-size:29px;letter-spacing:-.035em}h2{font-size:19px}p{color:#aaa;line-height:1.5}section{margin:34px 0}
.row{display:grid;grid-template-columns:170px 1fr;align-items:center;gap:16px;padding:9px 0;border-top:1px solid #303030}
.row span{font-variant-numeric:tabular-nums}audio{height:32px;width:min(100%,360px)}
@media(max-width:560px){.row{grid-template-columns:1fr}.row audio{width:100%}}
</style><h1>S2T sound direction</h1><p>Original synthetic cues. Short, soft, and electronic. Start, processing, and finish each have two variations. Tell me which family or specific cues come closest.</p>
''' + "\n".join(sections) + "</html>"
    (ROOT / "index.html").write_text(html)


def main():
    entries = []
    for family in ("flow", "discord"):
        for event in ("start", "processing", "finish"):
            for variant in (1, 2):
                name = f"{family}-{event}-{variant:02d}.mp3"
                encode(render(family, event, variant), ROOT / name)
                entries.append(dict(family=family, event=event, variant=variant,
                                    label=f"{event.title()} {variant}", file=name))
    (ROOT / "manifest.json").write_text(json.dumps(entries, indent=2) + "\n")
    page(entries)
    print(ROOT / "index.html")


if __name__ == "__main__":
    main()
