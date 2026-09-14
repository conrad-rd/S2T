#!/usr/bin/env python3
"""Check real blur spread in --verify-glow's owned line fixtures."""
import argparse
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=Path)
parser.add_argument("--state", choices=["soft-speech", "speaking", "loud"], default="speaking")
parser.add_argument("--heights", nargs=4, type=float, default=[220, 115, 100, 85],
                    help="Reference and three sample heights above the bottom, in points")
args = parser.parse_args()
root = args.directory
frames = sorted(root.glob(f'display-*/dark-{args.state}.png'))
assert frames, 'Run --verify-glow first.'
for path in frames:
    image = Image.open(path).convert('RGB')
    scale = image.height / 240
    width = image.width / scale
    center = round(width / 2 / 96) * 96
    measured = []
    for above_bottom in args.heights:
        row = round((240 - above_bottom) * scale)
        samples = [sum(image.getpixel((round((center + offset / scale) * scale), row))) / 3
                   for offset in range(-round(40 * scale), round(40 * scale) + 1)]
        # Remove the slowly varying tint. Half-maximum width measures spread,
        # so reducing a fixed blur's opacity alone cannot satisfy this check.
        left, right = samples[0], samples[-1]
        contrast = [max(0, value - (left + (right - left) * i / (len(samples) - 1)))
                    for i, value in enumerate(samples)]
        peak = max(contrast)
        assert peak > 2, f'{path}: insufficient line contrast for measurement'
        inside = [i for i, value in enumerate(contrast) if value >= peak / 2]
        measured.append((inside[-1] - inside[0] + 1) / scale)
    sharp, outer, middle, inner = measured
    assert 2 <= sharp <= 4, f'{path}: fixture is not sharp above the overlay'
    assert middle >= outer + 2 and inner >= middle + 3, (path, measured)
    print(f'{path.parent.name}: line widths at ' + '/'.join(f'{h:g}' for h in args.heights) + ' pt above bottom: '
          + ', '.join(f'{value:g} pt' for value in measured) + ' PASS')
