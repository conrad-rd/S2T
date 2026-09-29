#!/bin/bash
set -euo pipefail
if [[ "${S2T_BENCH_LOCK_HELD:-0}" != "1" ]]; then
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
    env = dict(os.environ, S2T_BENCH_LOCK_HELD="1", S2T_PACKAGE_LOCK_HELD="1")
    raise SystemExit(subprocess.call(["bash", str(root / "scripts/build-bench.sh"), *sys.argv[2:]], env=env))
PYLOCK
fi
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
bash scripts/build-app.sh
S2T_BENCH_FINAL="$PWD/build/S2T Bench.app"
S2T_BENCH_STAGE=$(mktemp -d "$PWD/build/.bench-stage-XXXXXXXX")
S2T_BENCH_APP="$S2T_BENCH_STAGE/S2T Bench.app"
S2T_BENCH_BACKUP="$S2T_BENCH_STAGE/previous.app"
cleanup() {
    local status=$?
    if [[ -e "$S2T_BENCH_BACKUP" && ! -e "$S2T_BENCH_FINAL" ]]; then
        mv "$S2T_BENCH_BACKUP" "$S2T_BENCH_FINAL" || true
    fi
    if [[ -e "$S2T_BENCH_BACKUP" && ! -e "$S2T_BENCH_FINAL" ]]; then
        echo "Could not restore the previous benchmark app; preserving it at $S2T_BENCH_BACKUP." >&2
    else
        case "$S2T_BENCH_STAGE" in "$PWD"/build/.bench-stage-*) rm -rf "$S2T_BENCH_STAGE" ;; esac
    fi
    return "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
S2T_BENCH_BIN=$(swift build --disable-sandbox --build-system native --scratch-path .build/xcode -c release --show-bin-path)
mkdir -p "$S2T_BENCH_APP/Contents/MacOS" "$S2T_BENCH_APP/Contents/Resources" "$S2T_BENCH_APP/Contents/Helpers"
cp "$S2T_BENCH_BIN/S2TBench" "$S2T_BENCH_APP/Contents/MacOS/S2TBench"
cp -R "$S2T_BENCH_BIN/S2T_S2TCore.bundle" "$S2T_BENCH_APP/Contents/Resources/"
python3 scripts/build-bench-fixtures.py "$S2T_BENCH_APP/Contents/Resources/BenchmarkFixtures"
ditto "build/S2T.app" "$S2T_BENCH_APP/Contents/Helpers/S2T.app"
if [[ -f build/S2T.app/Contents/Resources/Assets.car ]]; then
    cp build/S2T.app/Contents/Resources/Assets.car "$S2T_BENCH_APP/Contents/Resources/Assets.car"
fi
python3 - "$S2T_BENCH_APP" <<'PYINFO'
import pathlib
import plistlib
import sys

app = pathlib.Path(sys.argv[1])
with open("build/S2T.app/Contents/Info.plist", "rb") as source:
    engine = plistlib.load(source)
metadata = dict(CFBundleName="S2T Bench", CFBundleDisplayName="S2T Bench",
    CFBundleIdentifier="com.s2t.benchmark", CFBundleExecutable="S2TBench",
    CFBundlePackageType="APPL", CFBundleShortVersionString="1.0.0",
    CFBundleVersion=engine["CFBundleVersion"], LSMinimumSystemVersion="14.0",
    NSHighResolutionCapable=True, CFBundleIconName="S2T",
    S2TBenchmarkEngineBuild=engine["CFBundleVersion"],
    NSHumanReadableCopyright="S2T benchmark companion")
with (app / "Contents/Info.plist").open("wb") as target:
    plistlib.dump(metadata, target)
PYINFO
python3 scripts/sanitize-app.py "$S2T_BENCH_APP" "$PWD"
codesign --force --sign - --identifier com.s2t.benchmark "$S2T_BENCH_APP"
codesign --verify --deep --strict "$S2T_BENCH_APP"
"$S2T_BENCH_APP/Contents/MacOS/S2TBench" --verify-bench
"$PWD/build/S2T.app/Contents/MacOS/S2T" --verify-build
if [[ -e "$S2T_BENCH_FINAL" ]]; then mv "$S2T_BENCH_FINAL" "$S2T_BENCH_BACKUP"; fi
if ! mv "$S2T_BENCH_APP" "$S2T_BENCH_FINAL"; then
    if [[ -e "$S2T_BENCH_BACKUP" ]]; then mv "$S2T_BENCH_BACKUP" "$S2T_BENCH_FINAL"; fi
    exit 1
fi
rm -rf "$S2T_BENCH_BACKUP"
echo "Built $S2T_BENCH_FINAL"
