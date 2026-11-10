import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get("NATIVE_SOURCE_ROOT", ROOT)).resolve()


@unittest.skipUnless(sys.platform == "darwin", "requires the macOS SDK and frameworks")
class NativeOwnershipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="raw-keydown-ownership-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.binary = Path(cls.temp.name) / "native-ownership"
        api = SOURCE / "4D Plugin API"
        sources = [api / "4DPluginAPI.c", *sorted((api / "Classes").glob("*.cpp"))]
        command = [
            "clang++", "-std=c++17", "-x", "objective-c++",
            "-include", "Carbon/Carbon.h",
            "-Wno-deprecated-declarations", "-Wno-return-type-c-linkage",
            "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-g",
            "-I", str(SOURCE), "-I", str(api), "-I", str(api / "Classes"),
            str(ROOT / ".github/tests/native_ownership.mm"),
            *map(str, sources), "-framework", "Carbon", "-framework", "Cocoa",
            "-o", str(cls.binary),
        ]
        result = subprocess.run(command, text=True, capture_output=True)
        if result.returncode:
            raise AssertionError(f"Native harness compilation failed:\n{result.stdout}\n{result.stderr}")

    def test_native_ownership(self):
        environment = dict(os.environ, ASAN_OPTIONS="detect_leaks=0",
                           UBSAN_OPTIONS="halt_on_error=1")
        for scenario in ("callback-id", "callback-name", "path", "copy", "array"):
            for empty in ("allocated", "null"):
                for returned in ("undefined", "text", "error"):
                    for copied in ("independent", "copy"):
                        with self.subTest(scenario=scenario, empty=empty,
                                          returned=returned, copied=copied):
                            result = subprocess.run(
                                [str(self.binary), scenario, empty, returned, copied],
                                text=True, capture_output=True, env=environment,
                            )
                            self.assertEqual(
                                result.returncode, 0,
                                f"{result.stdout}\n{result.stderr}",
                            )
                            self.assertIn("native ownership: PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()
