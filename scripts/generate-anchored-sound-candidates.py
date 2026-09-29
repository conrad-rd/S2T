#!/usr/bin/env python3
"""Regenerate S2T sounds around the two user-selected liquid references."""

import importlib.util
from pathlib import Path


source = Path(__file__).with_name("generate-sound-candidates.py")
spec = importlib.util.spec_from_file_location("s2t_sound_generator", source)
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)

generator.OUTPUT = generator.ROOT / "Resources" / "Sounds" / "Candidates-Refined"
generator.FAMILIES = {
    "glow": ("Bottom / Around Notch", "wide hazy fluid ribbon"),
    "input": ("Around Input / Within Input", "wide hazy fluid ribbon, nearer and narrower"),
    "classic": ("Classic / Liquid Glass", "wide hazy fluid ribbon, slightly rounder and darker"),
}
generator.EVENTS = {
    "open": ("Start listening", "unfurls upward"),
    "processing": ("Start processing", "turns in place, unresolved"),
    "complete": ("Successful delivery", "curves inward and settles"),
}
generator.VARIATIONS = [
    "Two short low swells followed by a delayed longer slip.",
    "A delayed first pulse and two overlapping soft swirls, curving slightly lower.",
    "A delayed first pulse and two overlapping soft swirls, slightly rising.",
    "Two short low swells followed by a softer, longer delayed slip.",
    "A delayed first pulse and two close, overlapping swirls with a small downward curl.",
    "Two low swells close together, then one longer slipping motion after a small pause.",
    "A delayed first pulse and two overlapping swirls, with the second one softer.",
    "A short low swell, a quieter second swell, then a delayed fluid slip.",
    "Two short low swells with a slightly wider gap, followed by a longer slip.",
    "A soft delayed pulse and two overlapping liquid swirls with a very small rise.",
]
generator.STAGGERS = [(.085, .235), (.095, .180), (.095, .180), (.090, .230),
                      (.090, .190), (.100, .240), (.095, .195), (.085, .225),
                      (.100, .240), (.090, .185)]
generator.REFERENCE_SECTION = '''<section aria-label="Your reference sounds" style="margin:22px 0 30px;padding:16px 18px;background:#202020;border-radius:12px">
<h2 style="margin:0 0 12px">Your two reference sounds</h2>
<div class="option"><span>Start 03</span><audio controls preload="none" aria-label="Reference start 03" src="../Candidates-Liquid/glow/open/03.mp3"></audio><small>Bottom / Around Notch</small></div>
<div class="option"><span>Processing 01</span><audio controls preload="none" aria-label="Reference processing 01" src="../Candidates-Liquid/glow/processing/01.mp3"></audio><small>Bottom / Around Notch</small></div>
</section>\n'''

if __name__ == "__main__":
    generator.main()
