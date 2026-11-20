"""Portable one-shot protocol tests; never spawn a process."""
import copy
import json
import pathlib
import tempfile
import unittest
from artifact import compact, sha, wav
from owner_protocol import OwnerExchange

ROOT = pathlib.Path(__file__).resolve().parent


class OwnerProtocolTests(unittest.TestCase):
    def exchange(self, fixture=None):
        return OwnerExchange(('not-spawned', 'run'), ROOT, ROOT, {}, fixture or ROOT / 'owner-fixture.json')

    def answer(self, ex):
        output = wav(16000, [8192] * 16000)
        return compact(dict(version=2, operation='validated_wav16k', preserve_source_when_trimmed_too_short=False,
                            input_bytes=len(ex.source), input_sha256=sha(ex.source), output_bytes=len(output),
                            output_sha256=sha(output), base64=__import__('base64').b64encode(output).decode(), complete=True)) + b'\n'

    def test_one_exact_request_then_independently_bound_outcome_summary(self):
        ex = self.exchange()
        self.assertEqual(ex.accept(ex.expected), ex.inner)
        response = json.loads(ex.answer(0, self.answer(ex), b''))
        self.assertEqual(response['source_digest'], ex.source_digest)
        self.assertEqual(response['grant_id'], ex.grant['grant_id'])
        summary = compact(dict(version=1, kind='summary', outcome='outcome_ready', replay='outcome_ready',
                               runtime=1, issues=1, reads=1, retains=1, outcome_digest=ex.outcome_digest)) + b'\n'
        self.assertIsNone(ex.accept(summary))
        self.assertTrue(ex.finished)
        with self.assertRaises(ValueError):
            ex.accept(ex.expected)

    def test_consumed_request_never_reopens_even_after_process_failure(self):
        ex = self.exchange()
        ex.accept(ex.expected)
        with self.assertRaises(ValueError):
            ex.answer(1, b'', b'')
        self.assertTrue(ex.consumed)
        with self.assertRaises(ValueError):
            ex.accept(ex.expected)

    def test_frame_aliases_and_wrong_correlation_cannot_consume(self):
        for mutate in [lambda b: b + b' ', lambda b: b.replace(b'"version":1', b'"version":1,"version":1'),
                       lambda b: b.replace(b'"ordinal":0', b'"ordinal":1'),
                       lambda b: b.replace(b'"preserve_source_when_trimmed_too_short":false', b'"preserve_source_when_trimmed_too_short":true')]:
            ex = self.exchange()
            with self.assertRaises(ValueError):
                ex.accept(mutate(ex.expected))
            self.assertFalse(ex.consumed)

    def test_output_stage_and_exit_are_exact(self):
        for code, stage in [(2, 'validation'), (3, 'transform')]:
            ex = self.exchange()
            ex.accept(ex.expected)
            diagnostic = compact(dict(version=2, status='rejected', stage=stage, transform_started=code == 3)) + b'\n'
            self.assertEqual(json.loads(ex.answer(code, b'', diagnostic))['stage'], stage)
            with self.assertRaises(ValueError):
                ex.answer(code, b'', diagnostic)
            ex = self.exchange()
            ex.accept(ex.expected)
            with self.assertRaises(ValueError):
                ex.answer(code, b'', diagnostic + b' ')

    def test_nonzero_or_stderr_never_accepts_complete_output(self):
        for code, stderr in [(1, b''), (0, b'extra')]:
            ex = self.exchange()
            ex.accept(ex.expected)
            with self.assertRaises(ValueError):
                ex.answer(code, self.answer(ex), stderr)

    def test_wrong_source_output_digest_or_count_is_rejected(self):
        for field in ['input_sha256', 'output_sha256', 'input_bytes', 'output_bytes', 'complete']:
            ex = self.exchange()
            ex.accept(ex.expected)
            answer = json.loads(self.answer(ex))
            answer[field] = '0' * 64 if field.endswith('sha256') else 0
            with self.assertRaises(ValueError):
                ex.answer(0, compact(answer) + b'\n', b'')

    def test_ordinary_or_altered_profile_is_rejected_at_preflight(self):
        original = json.loads((ROOT / 'owner-fixture.json').read_text())
        with tempfile.TemporaryDirectory() as tmp:
            fixture = pathlib.Path(tmp) / 'fixture.json'
            for key, value in [('edge_eligible', True), ('synthetic_only', False), ('resource_status', 'qualified')]:
                item = copy.deepcopy(original)
                item[key] = value
                fixture.write_text(json.dumps(item))
                with self.assertRaises(ValueError):
                    self.exchange(fixture)
            item = copy.deepcopy(original)
            item['profile']['spec']['artifact']['sha256'] = '0' * 64
            fixture.write_text(json.dumps(item))
            with self.assertRaises(ValueError):
                self.exchange(fixture)


if __name__ == '__main__':
    unittest.main()
