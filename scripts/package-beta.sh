#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

S2T_UNIVERSAL=1 bash scripts/build-app.sh
S2T_APP="$PWD/build/S2T.app"
S2T_EXEC="$S2T_APP/Contents/MacOS/S2T"
S2T_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$S2T_APP/Contents/Info.plist")
S2T_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$S2T_APP/Contents/Info.plist")
S2T_NAME="S2T-$S2T_VERSION-beta-build-$S2T_BUILD-universal"
S2T_RELEASE="$PWD/build/releases/$S2T_NAME"
mkdir -p "$S2T_RELEASE"
[[ "$(lipo -archs "$S2T_EXEC")" == "x86_64 arm64" || "$(lipo -archs "$S2T_EXEC")" == "arm64 x86_64" ]]
for S2T_CHECK in build onboarding models api-keys clipboard menu-highlights notch input-outline; do
    "$S2T_EXEC" "--verify-$S2T_CHECK"
done
"$S2T_EXEC" --verify-glow "$PWD/build/verification/beta-glow-$S2T_BUILD"
ditto --norsrc --noextattr --noqtn "$S2T_APP" "$S2T_RELEASE/S2T.app"
cp docs/BETA-READ-ME.txt "$S2T_RELEASE/READ ME.txt"
printf 'S2T %s early beta, build %s\n' "$S2T_VERSION" "$S2T_BUILD" > "$S2T_RELEASE/VERSION.txt"
codesign --verify --deep --strict "$S2T_RELEASE/S2T.app"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$S2T_RELEASE" "$S2T_RELEASE.zip"
shasum -a 256 "$S2T_RELEASE.zip" > "$S2T_RELEASE.zip.sha256"
bash scripts/build-dmg.sh "$S2T_RELEASE/S2T.app" "$S2T_RELEASE.dmg"
echo "Share $S2T_RELEASE.dmg"
