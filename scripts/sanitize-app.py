"""Remove local build paths without changing Mach-O offsets, before signing."""
import pathlib
import re
import subprocess
import sys

app = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2]).resolve()
binary = app / "Contents/MacOS/S2T"
subprocess.run(["/usr/bin/strip", "-S", str(binary)], check=True)
original = str(root).encode()
neutral = b"/private/tmp/S2T-build"
if len(neutral) > len(original):
    raise SystemExit("Build directory is too short for neutral path replacement")
neutral += b"/" * (len(original) - len(neutral))
data = binary.read_bytes()
count = data.count(original)
binary.write_bytes(data.replace(original, neutral))

# SwiftPM embeds development resource fallbacks as string literals. The app's
# bundled resource lookup takes precedence; preserve string lengths and offsets.
blocked_names = {"dictionary.md", "system-prompt.txt", ".env", "credentials-v1"}
personal = root.parts[2].encode() if root.parts[:2] == ("/", "Users") else None
for path in app.rglob("*"):
    if path.is_symlink():
        raise SystemExit(f"Unexpected app symlink: {path.relative_to(app)}")
    if not path.is_file() or "_CodeSignature" in path.parts:
        continue
    payload = path.read_bytes()
    if path.name in blocked_names:
        raise SystemExit(f"Private-state file in app: {path.relative_to(app)}")
    if (personal and personal.lower() in payload.lower()) or re.search(rb"/(?:Users|home)/[^/\x00\s]+/", payload):
        raise SystemExit(f"Personal build path in app: {path.relative_to(app)}")
    if re.search(rb"sk-(?:or-v1|proj)-[A-Za-z0-9_-]{20,}", payload):
        raise SystemExit(f"Potential embedded API key: {path.relative_to(app)}")
print(f"Privacy check passed; neutralized {count} build paths. No bundled private state or personal home paths.")
