#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
fixture="$(pwd)/build/verification/PasteEditor.app"
mkdir -p "$fixture/Contents/MacOS"
swiftc Tests/Fixtures/PasteEditor.swift -o "$fixture/Contents/MacOS/PasteEditor"
cat > "$fixture/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.s2t.paste-verification</string><key>CFBundleExecutable</key><string>PasteEditor</string><key>CFBundleName</key><string>S2T paste verification</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
codesign --force --sign - "$fixture"
