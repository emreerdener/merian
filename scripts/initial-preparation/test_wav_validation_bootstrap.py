"""Portable v2 protocol tests; no artifact registration or execution claim."""
import base64
import hashlib
import json
import pathlib
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent


def request(source, fallback=False):
    return dict(version=2, operation='validated_wav16k',
                base64=base64.b64encode(source).decode(),
                preserve_source_when_trimmed_too_short=fallback)


def encoded(value):
    return json.dumps(value, separators=(',', ':')).encode()


def wave(rate=16000, value=8192, frames=None):
    data = struct.pack('<h', value) * (frames if frames is not None else rate)
    return (b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVEfmt ' +
            struct.pack('<IHHIIHH', 16, 1, 1, rate, rate * 2, 2, 16) +
            b'data' + struct.pack('<I', len(data)) + data)


class WavBootstrapTests(unittest.TestCase):
    def execute(self, data):
        with tempfile.TemporaryDirectory(prefix='merian-wav-bootstrap-test-') as temporary:
            return subprocess.run(
                [shutil.which('deno'), 'run', '--no-config', '--no-lock',
                 '--no-remote', '--no-npm', '--no-prompt', '--deny-read',
                 '--deny-write', '--deny-net', '--deny-env', '--deny-run',
                 '--deny-ffi', '--deny-import', str(ROOT / 'wav-validation-bootstrap.ts')],
                input=data, capture_output=True, timeout=10, cwd=temporary,
                env={'DENO_DIR': temporary, 'DENO_NO_UPDATE_CHECK': '1'})

    def test_exact_success_envelope_and_resampling(self):
        source = wave(32000)
        result = self.execute(encoded(request(source, True)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, b'')
        expected = wave()
        answer = dict(version=2, operation='validated_wav16k',
                      preserve_source_when_trimmed_too_short=True,
                      input_bytes=len(source), input_sha256=hashlib.sha256(source).hexdigest(),
                      output_bytes=len(expected), output_sha256=hashlib.sha256(expected).hexdigest(),
                      base64=base64.b64encode(expected).decode(), complete=True)
        self.assertEqual(result.stdout, encoded(answer) + b'\n')

    def test_exact_validation_and_transform_rejections(self):
        malformed = bytearray(wave())
        struct.pack_into('<I', malformed, 4, 0)
        for source, fallback, stage, code in [
            (malformed, False, 'validation', 2),
            (wave(frames=100), True, 'transform', 3),
        ]:
            with self.subTest(stage=stage):
                result = self.execute(encoded(request(source, fallback)))
                self.assertEqual(result.returncode, code)
                self.assertEqual(result.stdout, b'')
                self.assertEqual(result.stderr, encoded(dict(
                    version=2, status='rejected', stage=stage,
                    transform_started=stage == 'transform')) + b'\n')

    def test_rejects_ambiguous_json_base64_and_invalid_utf8_without_diagnostics(self):
        valid = request(wave())
        raw = encoded(valid)
        values = [None, [], {}, dict(valid, version=1), dict(valid, extra=True),
                  dict(valid, __proto__={}), dict(valid, preserve_source_when_trimmed_too_short=1)]
        payloads = [encoded(v) for v in values]
        payloads += [b'\xff', b'\xef\xbb\xbf' + raw, raw + b'\n',
                     raw.replace(b'"version":2', b'"version":2.0'),
                     raw.replace(b'"operation":', b'"operation":"identity","operation":'),
                     raw.replace(b'"base64":', b'"base64":"","base64":'),
                     encoded(dict(reversed(list(valid.items())))), b' ' * 262145]
        for spelling in ['Zg', 'Zh==', 'Zg===', 'Z g==', '-g==', 'Zg==\n', 'A' * 256004]:
            payloads.append(encoded(dict(valid, base64=spelling)))
        for i, payload in enumerate(payloads):
            with self.subTest(case=i):
                result = self.execute(payload)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, b'')
                self.assertEqual(result.stderr, b'')


if __name__ == '__main__':
    unittest.main()
