#!/usr/bin/env python3
"""Blend fresh ElevenLabs takes with the two S2T sounds the user selected."""

import argparse
import array
import json
import math
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1] / "Resources" / "Sounds"
NEW = ROOT / "Candidates-Refined"
REFERENCES = {
    "open": ROOT / "Candidates-Liquid" / "glow" / "open" / "03.mp3",
    "processing": ROOT / "Candidates-Liquid" / "glow" / "processing" / "01.mp3",
    "complete": ROOT / "Candidates-Liquid" / "glow" / "processing" / "01.mp3",
}
ANCHOR_AMOUNT = {"glow": 0.64, "input": 0.59, "classic": 0.57}


def decode(path):
    result = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le",
                             "-ac", "2", "-ar", "44100", "-"], capture_output=True, check=True)
    samples = array.array("f")
    samples.frombytes(result.stdout)
    if not samples:
        raise RuntimeError(f"Empty sound: {path}")
    return samples


def guide(entry, anchors):
    fresh = decode(NEW / entry["file"])
    anchor = anchors[entry["event"]]
    amount = ANCHOR_AMOUNT[entry["family"]]
    mixed = array.array("f", [0.0]) * len(fresh)
    for i in range(len(fresh)):
        mixed[i] = (1 - amount) * fresh[i] + amount * (anchor[i] if i < len(anchor) else 0)
    rms = math.sqrt(sum(value * value for value in mixed) / len(mixed))
    gain = max(-15, min(15, -39.5 - 20 * math.log10(rms)))
    output = (NEW / entry["file"]).with_suffix(".guided.mp3")
    temporary = output.with_suffix(".partial.mp3")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", "2", "-ar", "44100",
                    "-i", "-", "-af", f"volume={gain:.2f}dB,alimiter=limit=0.075:attack=2:release=20:level=disabled",
                    "-codec:a", "libmp3lame", "-q:a", "3", str(temporary)],
                   input=mixed.tobytes(), capture_output=True, check=True)
    temporary.replace(output)
    return output


def make_page(entries):
    html = (NEW / "index.html").read_text()
    html = html.replace("<title>S2T liquid sound candidates</title>", "<title>S2T sounds based on your picks</title>")
    html = html.replace("<h1>Liquid sound candidates</h1>", "<h1>Sounds based on your picks</h1>")
    html = html.replace("Soft, damp liquid cues with small staggered movements.",
                        "Fresh ElevenLabs takes guided by the two sounds you liked. Each keeps their soft liquid character and staggered movement.")
    html = html.replace("Select one per section and send back the list below.",
                        'Select one per section and send back the list below. <a href="index.html">Hear the fresh takes without the reference blend</a>.')
    pattern = re.compile(r'src="((?:glow|input|classic)/(?:open|processing|complete)/\d\d)\.mp3"')
    html, count = pattern.subn(lambda match: f'src="{match.group(1)}.guided.mp3"', html)
    if count != len(entries):
        raise RuntimeError(f"Expected {len(entries)} audio players, found {count}")
    download = re.compile(r'href="((?:glow|input|classic)/(?:open|processing|complete)/\d\d)\.mp3"')
    html, count = download.subn(lambda match: f'href="{match.group(1)}.guided.mp3"', html)
    if count != len(entries):
        raise RuntimeError(f"Expected {len(entries)} download links, found {count}")
    (NEW / "guided.html").write_text(html)
    (NEW / "guided-manifest.json").write_text(json.dumps([
        dict(entry, guided_file=entry["file"].replace(".mp3", ".guided.mp3")) for entry in entries
    ], indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int)
    args = parser.parse_args()
    entries = json.loads((NEW / "manifest.json").read_text())
    anchors = {event: decode(path) for event, path in REFERENCES.items()}
    for entry in entries[:args.limit]:
        output = guide(entry, anchors)
        print(output.relative_to(NEW), flush=True)
    if args.limit is None:
        make_page(entries)
        print(NEW / "guided.html")


if __name__ == "__main__":
    main()
