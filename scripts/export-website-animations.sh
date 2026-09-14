#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-app.sh
build/S2T.app/Contents/MacOS/S2T --verify-build
build/S2T.app/Contents/MacOS/S2T --export-website-animations website-reference-assets/sequoia-original.png website/public/native-hires
python3 - <<'PY'
import hashlib, json
from pathlib import Path
files = sorted(Path('Sources').rglob('*.swift'))
manifest = {'files': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
Path('website/public/native-hires/source-hashes.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY

python3 website/scripts/encode-previews.py
S2T_WEBSITE_TRANSITIONS=1 build/S2T.app/Contents/MacOS/S2T --export-website-animations website-reference-assets/sequoia-original.png build/native-transitions
python3 website/scripts/encode-previews.py --source build/native-transitions --phase appearing
python3 website/scripts/encode-previews.py --source build/native-transitions --phase disappearing
python3 website/scripts/encode-preview-cycles.py
