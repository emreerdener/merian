"""Portable synthetic protocol tests; these do not qualify an archived artifact."""
import base64
import json
import pathlib
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent


class BootstrapTests(unittest.TestCase):
    def execute(self, value):
        with tempfile.TemporaryDirectory(prefix="merian-bootstrap-test-") as temporary:
            return subprocess.run(
                [shutil.which("deno"), "run", "--no-config", "--no-lock",
                 "--no-remote", "--no-npm", "--no-prompt", "--deny-read",
                 "--deny-write", "--deny-net", "--deny-env", "--deny-run",
                 "--deny-ffi", "--deny-import", str(ROOT / "bootstrap.ts")],
                input=json.dumps(value).encode(), capture_output=True, timeout=10,
                cwd=temporary,
                env={"DENO_DIR": temporary, "DENO_NO_UPDATE_CHECK": "1"},
            )

    def test_identity(self):
        result = self.execute({"version": 1, "operation": "identity", "base64": "YWJj"})
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(base64.b64decode(value["base64"]), b"abc")
        self.assertEqual(value["output_bytes"], 3)
        self.assertIs(value["complete"], True)

    def test_real_resampling(self):
        def wave(rate):
            data = struct.pack("<h", 8192) * rate
            return (b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt " +
                    struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16) +
                    b"data" + struct.pack("<I", len(data)) + data)
        result = self.execute({"version": 1, "operation": "wav16k",
                               "base64": base64.b64encode(wave(32000)).decode()})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(base64.b64decode(json.loads(result.stdout)["base64"]), wave(16000))

    def test_closed_protocol(self):
        for value in [None, [], {},
                      {"version": 2, "operation": "identity", "base64": ""},
                      {"version": 1, "operation": "future", "base64": ""},
                      {"version": 1, "operation": "wav16k", "base64": ""},
                      {"version": 1, "operation": "identity", "base64": "", "extra": 1},
                      {"version": 1, "operation": "identity", "base64": "A" * 270000}]:
            with self.subTest(value_type=type(value).__name__):
                result = self.execute(value)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b"")


if __name__ == "__main__":
    unittest.main()
