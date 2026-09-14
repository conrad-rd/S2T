#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
S2T_APP="${1:?Pass the packaged S2T.app path}"
S2T_DMG="${2:?Pass the output DMG path}"
[[ ! -e "$S2T_DMG" ]] || { echo "Output already exists: $S2T_DMG" >&2; exit 1; }
S2T_WORK=$(mktemp -d "$PWD/build/dmg-XXXXXXXX")
S2T_STAGE="$S2T_WORK/content"
S2T_MOUNT="$S2T_WORK/mount"
mkdir -p "$S2T_STAGE/.background" "$S2T_MOUNT"
ditto --norsrc --noextattr --noqtn "$S2T_APP" "$S2T_STAGE/S2T.app"
ln -s /Applications "$S2T_STAGE/Applications"
swift scripts/dmg-artwork.swift "$S2T_STAGE/.background/install.tiff"
if [[ ! -x build/dmg-tools/bin/python ]]; then python3 -m venv build/dmg-tools; fi
build/dmg-tools/bin/python -c 'import ds_store, mac_alias' 2>/dev/null || build/dmg-tools/bin/pip install 'ds-store==1.3.1'
hdiutil create -quiet -srcfolder "$S2T_STAGE" -volname S2T -fs HFS+ -format UDRW "$S2T_WORK/writable.dmg"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$S2T_MOUNT" "$S2T_WORK/writable.dmg"
trap 'hdiutil detach -quiet "$S2T_MOUNT" 2>/dev/null || true' EXIT
build/dmg-tools/bin/python scripts/dmg-layout.py "$S2T_MOUNT"
codesign --verify --deep --strict "$S2T_MOUNT/S2T.app"
hdiutil detach -quiet "$S2T_MOUNT"
trap - EXIT
hdiutil convert -quiet "$S2T_WORK/writable.dmg" -format UDZO -imagekey zlib-level=9 -o "$S2T_DMG"
hdiutil verify "$S2T_DMG"
shasum -a 256 "$S2T_DMG" > "$S2T_DMG.sha256"
echo "Built $S2T_DMG"
