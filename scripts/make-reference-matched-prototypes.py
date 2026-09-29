#!/usr/bin/env python3
"""Private audition of source cues and processed reference variants.

Outputs under build/.sound-reference, never into the packaged app.
"""

from html import escape
from pathlib import Path
import array
import math
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / ".sound-reference" / "audition"
OUT.mkdir(parents=True, exist_ok=True)
FLOW = Path("/Applications/Wispr Flow.app/Contents/Resources/assets/sounds")
DISCORD = ROOT / "build" / ".sound-reference"

SOURCES = [
    ("Discord mute", DISCORD / "discord-mute.mp3", "discord-mute"),
    ("Discord unmute", DISCORD / "discord-unmute.mp3", "discord-unmute"),
    ("Flow start", FLOW / "dictation-start.wav", "flow-start"),
    ("Flow stop", FLOW / "dictation-stop.wav", "flow-stop"),
]


def original_cue(direction, shade):
    """Two overlapping note clusters; pitches differ from source references."""
    rate = 44100
    length = 0.36
    lower = (286.0, 419.0) if shade == "A" else (302.0, 447.0)
    upper = tuple(f * 1.94 for f in lower)
    clusters = [(0.008, upper), (0.092, lower)] if direction == "mute" else [
        (0.010, lower), (0.095, upper)]
    if shade == "B":
        clusters[1] = (0.110, clusters[1][1])
    samples = array.array("f")
    phases = [0.0] * 4
    for n in range(round(length * rate)):
        t = n / rate
        value = 0.0
        for group, (onset, frequencies) in enumerate(clusters):
            local = t - onset
            if local < 0:
                continue
            attack = min(1.0, local / (0.006 if shade == "A" else 0.012))
            envelope = attack * math.exp(-local / (0.055 if group == 0 else 0.070))
            for part, frequency in enumerate(frequencies):
                index = group * 2 + part
                glide = 1 + 0.025 * math.exp(-local / 0.025)
                phases[index] += 2 * math.pi * frequency * glide / rate
                fundamental = math.sin(phases[index])
                harmonic = 0.13 * math.sin(2 * phases[index] + 0.3)
                value += envelope * (fundamental + harmonic) * (0.56 if part else 0.72)
        # A soft limiter avoids hard clipping without adding a sharp click.
        value = math.tanh(value * 0.75) * 0.12
        value *= min(1.0, max(0.0, (length - t) / 0.05))
        samples.append(value)
    path = OUT / f"original-{direction}-{shade.lower()}.mp3"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", "1", "-ar", str(rate),
                    "-i", "-", "-af", "lowpass=f=4200", "-codec:a", "libmp3lame", "-q:a", "2",
                    str(path)], input=samples.tobytes(), check=True)
    return path.name


def encode(source, output, filters):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(source), "-af", filters,
                    "-ac", "2", "-ar", "44100", "-codec:a", "libmp3lame", "-q:a", "2",
                    str(output)], check=True)


def main():
    sections = []
    for name, source, stem in SOURCES:
        if not source.is_file():
            raise SystemExit(f"Missing reference: {source}")
        original = OUT / f"{stem}-original{source.suffix}"
        shutil.copyfile(source, original)
        variants = [
            ("Reference", original.name),
            ("Softer", f"{stem}-soft.mp3"),
            ("Darker", f"{stem}-dark.mp3"),
        ]
        encode(source, OUT / variants[1][1],
               "highpass=f=110,lowpass=f=5800,acompressor=threshold=0.09:ratio=1.5:attack=5:release=65,volume=0.38")
        encode(source, OUT / variants[2][1],
               "highpass=f=110,lowpass=f=2900,acompressor=threshold=0.075:ratio=1.8:attack=7:release=75,volume=0.40")
        rows = "".join(f'<div class="row"><span>{escape(label)}</span>'
                       f'<audio controls preload="none" src="{escape(filename)}" '
                       f'aria-label="{escape(name + " " + label)}"></audio></div>'
                       for label, filename in variants)
        sections.append(f"<section><h2>{escape(name)}</h2>{rows}</section>")
    rows = "".join(f'<div class="row"><span>{escape(label)}</span>'
                   f'<audio controls preload="none" src="{filename}" aria-label="{escape(label)}"></audio></div>'
                   for label, filename in [
                       (f"Mute {shade}", original_cue("mute", shade)) for shade in ("A", "B")
                   ] + [
                       (f"Unmute {shade}", original_cue("unmute", shade)) for shade in ("A", "B")
                   ])
    sections.append(f"<section><h2>New S2T sketches</h2><p>Fresh tones with the same two-cluster up/down gesture, plus a soft attack.</p>{rows}</section>")
    html = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>S2T sound references</title><style>
body{background:#151515;color:#f2f2f2;font:15px -apple-system,BlinkMacSystemFont,sans-serif;max-width:820px;margin:40px auto;padding:0 24px}
h1{font-size:29px;letter-spacing:-.035em}h2{font-size:19px}p{color:#aaa;line-height:1.5}section{margin:34px 0}
.row{display:grid;grid-template-columns:110px 1fr;align-items:center;gap:16px;padding:9px 0;border-top:1px solid #303030}
audio{height:32px;width:min(100%,360px)}@media(max-width:560px){.row{grid-template-columns:1fr}.row audio{width:100%}}
</style><h1>Sound reference comparison</h1><p>Hear the actual Discord and Wispr Flow cues beside softened edits and new S2T sketches. The source clips and edits are private references, not S2T release assets.</p>
''' + "\n".join(sections) + "</html>"
    (OUT / "index.html").write_text(html)
    print(OUT / "index.html")


if __name__ == "__main__":
    main()
