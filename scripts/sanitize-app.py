"""Remove local build paths without changing Mach-O offsets, before signing."""
import pathlib
import plistlib
import re
import subprocess
import sys

def neutral_path(length: int) -> bytes:
    """Return a non-personal absolute placeholder with exactly `length` bytes."""
    if length < 1:
        raise ValueError("A build path cannot be empty")
    stem = b"/s2t-build"
    return stem[:length] if length <= len(stem) else stem + b"/" * (length - len(stem))

# SwiftPM embeds development resource fallbacks as string literals. The app's
# bundled resource lookup takes precedence; preserve string lengths and offsets.
def main(app: pathlib.Path, root: pathlib.Path) -> None:
    with (app / "Contents/Info.plist").open("rb") as metadata:
        executable = plistlib.load(metadata)["CFBundleExecutable"]
    binary = app / "Contents/MacOS" / executable
    subprocess.run(["/usr/bin/strip", "-S", str(binary)], check=True)
    original = str(root).encode()
    data = binary.read_bytes()
    count = data.count(original)
    binary.write_bytes(data.replace(original, neutral_path(len(original))))

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


if __name__ == "__main__":
    main(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]).resolve())
