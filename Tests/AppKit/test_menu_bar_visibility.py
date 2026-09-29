import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import uuid


class MenuBarVisibilityTests(unittest.TestCase):
    def test_preview_visibility_cannot_hide_the_real_item_after_restart(self):
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(prefix="s2t-menu-visibility-") as temporary:
            folder = Path(temporary)
            contents = folder / "VisibilityFixture.app/Contents"
            executable = contents / "MacOS/VisibilityFixture"
            executable.parent.mkdir(parents=True)
            (contents / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "com.s2t.visibility-fixture." + uuid.uuid4().hex,
                "CFBundleExecutable": executable.name,
                "CFBundlePackageType": "APPL",
                "LSUIElement": True,
            }))
            environment = dict(os.environ)
            environment.setdefault("CLANG_MODULE_CACHE_PATH", str(folder / "module-cache"))
            subprocess.run([
                "xcrun", "swiftc", "-parse-as-library",
                str(root / "Sources/S2TApp/MenuBarStatusItem.swift"),
                str(root / "Tests/AppKit/MenuBarVisibilityFixture.swift"),
                "-o", str(executable),
            ], check=True, env=environment, capture_output=True, text=True)
            try:
                for phase in ["seed-old-hidden-state", "launch", "hide-preview", "launch"]:
                    result = subprocess.run([str(executable), phase], capture_output=True,
                                            text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, phase + ": " + result.stdout + result.stderr)
            finally:
                subprocess.run([str(executable), "cleanup"], capture_output=True,
                               text=True, timeout=10)


if __name__ == "__main__":
    unittest.main()
