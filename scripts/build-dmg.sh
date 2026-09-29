#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
S2T_APP="${1:?Pass the packaged S2T.app path}"
S2T_DMG="${2:?Pass the output DMG path}"
S2T_HDIUTIL="${S2T_HDIUTIL:-hdiutil}"
S2T_MOUNT_TABLE="${S2T_MOUNT_TABLE:-/sbin/mount}"
[[ ! -e "$S2T_DMG" ]] || { echo "Output already exists: $S2T_DMG" >&2; exit 1; }
mkdir -p "$PWD/build"
S2T_WORK=$(mktemp -d "$PWD/build/.dmg-XXXXXXXX")
S2T_STAGE="$S2T_WORK/content"
S2T_MOUNT="$S2T_WORK/mount"
S2T_MOUNTED=0
S2T_COMPLETE=0
cleanup() {
    local status=$?
    if [[ "$S2T_MOUNTED" == "1" ]]; then
        if "$S2T_HDIUTIL" detach -quiet "$S2T_MOUNT" 2>/dev/null; then
            S2T_MOUNTED=0
        elif ! "$S2T_MOUNT_TABLE" | /usr/bin/grep -Fq " on $S2T_MOUNT ("; then
            S2T_MOUNTED=0
        else
            echo "Could not detach $S2T_MOUNT; preserving the mounted DMG workspace at $S2T_WORK." >&2
        fi
    fi
    if [[ "$S2T_MOUNTED" == "0" ]]; then
        if [[ "$S2T_COMPLETE" != "1" ]]; then rm -f "$S2T_DMG" "$S2T_DMG.sha256"; fi
        if [[ "${S2T_PRESERVE_DMG_WORK:-0}" == "1" ]]; then
            echo "Preserved DMG workspace at $S2T_WORK." >&2
        else
            case "$S2T_WORK" in "$PWD"/build/.dmg-*) rm -rf "$S2T_WORK" ;; esac
        fi
    fi
    return "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$S2T_STAGE/.background" "$S2T_MOUNT"
ditto --norsrc --noextattr --noqtn "$S2T_APP" "$S2T_STAGE/S2T.app"
swift scripts/dmg-applications.swift "$S2T_STAGE/Applications"
swift scripts/dmg-artwork.swift "$S2T_STAGE/.background/install.tiff"
if [[ ! -x build/dmg-tools/bin/python ]]; then python3 -m venv build/dmg-tools; fi
build/dmg-tools/bin/python -c 'import ds_store, mac_alias' 2>/dev/null || build/dmg-tools/bin/pip install 'ds-store==1.3.1'
S2T_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$S2T_APP/Contents/Info.plist")
S2T_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$S2T_APP/Contents/Info.plist")
"$S2T_HDIUTIL" create -quiet -srcfolder "$S2T_STAGE" -volname "S2T $S2T_VERSION Build $S2T_BUILD Layout 7" -fs HFS+ -format UDRW "$S2T_WORK/writable.dmg"
S2T_MOUNTED=1
"$S2T_HDIUTIL" attach -quiet -nobrowse -noautoopen -mountpoint "$S2T_MOUNT" "$S2T_WORK/writable.dmg"
build/dmg-tools/bin/python scripts/dmg-layout.py "$S2T_MOUNT"
codesign --verify --deep --strict "$S2T_MOUNT/S2T.app"
if ! "$S2T_HDIUTIL" detach -quiet "$S2T_MOUNT"; then
    echo "Could not detach writable DMG; cleanup will retry and preserve it if it remains mounted." >&2
    exit 1
fi
S2T_MOUNTED=0
"$S2T_HDIUTIL" convert -quiet "$S2T_WORK/writable.dmg" -format UDZO -imagekey zlib-level=9 -o "$S2T_DMG"
"$S2T_HDIUTIL" verify "$S2T_DMG"
S2T_MOUNT="$S2T_WORK/remounted"
mkdir -p "$S2T_MOUNT"
S2T_MOUNTED=1
"$S2T_HDIUTIL" attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$S2T_MOUNT" "$S2T_DMG"
build/dmg-tools/bin/python scripts/dmg-layout.py "$S2T_MOUNT" --verify
ditto "$S2T_MOUNT/S2T.app" "$S2T_WORK/installation-check/S2T.app"
codesign --verify --deep --strict "$S2T_WORK/installation-check/S2T.app"
"$S2T_WORK/installation-check/S2T.app/Contents/MacOS/S2T" --verify-build
if ! "$S2T_HDIUTIL" detach -quiet "$S2T_MOUNT"; then
    echo "Could not detach verification DMG; cleanup will retry and preserve it if it remains mounted." >&2
    exit 1
fi
S2T_MOUNTED=0
shasum -a 256 "$S2T_DMG" > "$S2T_DMG.sha256"
S2T_COMPLETE=1
echo "Built $S2T_DMG"
