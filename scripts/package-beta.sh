#!/bin/bash
set -euo pipefail
if [[ "${S2T_PACKAGE_LOCK_HELD:-0}" != "1" ]]; then
    exec python3 - "$0" "$@" <<'PYLOCK'
import fcntl
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1]).resolve().parent.parent
(root / "build").mkdir(exist_ok=True)
with (root / "build/.package.lock").open("a") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    env = dict(os.environ, S2T_PACKAGE_LOCK_HELD="1")
    raise SystemExit(subprocess.call(["bash", str(root / "scripts/package-beta.sh"), *sys.argv[2:]], env=env))
PYLOCK
fi
cd "$(dirname "$0")/.."

S2T_UNIVERSAL=1 bash scripts/build-app.sh
S2T_SOURCE_APP="$PWD/build/S2T.app"
S2T_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$S2T_SOURCE_APP/Contents/Info.plist")
S2T_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$S2T_SOURCE_APP/Contents/Info.plist")
S2T_NAME="S2T-$S2T_VERSION-beta-build-$S2T_BUILD-universal"
mkdir -p "$PWD/build/releases"
S2T_STAGE_ROOT=$(mktemp -d "$PWD/build/releases/.beta-stage-XXXXXXXX")
S2T_RELEASE="$S2T_STAGE_ROOT/$S2T_NAME"
cleanup() {
    local status=$?
    case "$S2T_STAGE_ROOT" in "$PWD"/build/releases/.beta-stage-*) rm -rf "$S2T_STAGE_ROOT" ;; esac
    return "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$S2T_RELEASE"
ditto --norsrc --noextattr --noqtn "$S2T_SOURCE_APP" "$S2T_RELEASE/S2T.app"
S2T_APP="$S2T_RELEASE/S2T.app"
S2T_EXEC="$S2T_APP/Contents/MacOS/S2T"
for S2T_ARCH in x86_64 arm64; do
    lipo "$S2T_EXEC" -verify_arch "$S2T_ARCH"
done
for S2T_CHECK in build onboarding models api-keys clipboard menu-highlights notch input-outline; do
    "$S2T_EXEC" "--verify-$S2T_CHECK"
done
"$S2T_EXEC" --verify-glow "$S2T_STAGE_ROOT/glow"
cp docs/BETA-READ-ME.txt "$S2T_RELEASE/READ ME.txt"
printf 'S2T %s early beta, build %s\n' "$S2T_VERSION" "$S2T_BUILD" > "$S2T_RELEASE/VERSION.txt"
codesign --verify --deep --strict "$S2T_APP"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$S2T_RELEASE" "$S2T_STAGE_ROOT/$S2T_NAME.zip"
(cd "$S2T_STAGE_ROOT" && shasum -a 256 "$S2T_NAME.zip" > "$S2T_NAME.zip.sha256")
bash scripts/build-dmg.sh "$S2T_APP" "$S2T_STAGE_ROOT/$S2T_NAME.dmg"

for S2T_SUFFIX in "" .zip .zip.sha256 .dmg .dmg.sha256; do
    S2T_FINAL="$PWD/build/releases/$S2T_NAME$S2T_SUFFIX"
    if [[ -d "$S2T_FINAL" ]]; then rm -rf "$S2T_FINAL"; else rm -f "$S2T_FINAL"; fi
    mv "$S2T_STAGE_ROOT/$S2T_NAME$S2T_SUFFIX" "$S2T_FINAL"
done
echo "Share $PWD/build/releases/$S2T_NAME.dmg"
