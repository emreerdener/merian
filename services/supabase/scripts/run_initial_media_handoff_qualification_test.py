"""Offline ownership/dispatch/failure tests; never invokes Docker or a provider."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

import run_initial_media_handoff_qualification as runner


class QualificationRunnerTests(unittest.TestCase):
    def test_closed_platform_roots(self):
        self.assertEqual(runner.temporary_root('darwin'), Path('/private/tmp'))
        self.assertEqual(runner.temporary_root('linux'), Path('/tmp'))
        with self.assertRaises(runner.Stopped):
            runner.temporary_root('win32')

    def test_local_endpoint_pinned_and_overrides_rejected(self):
        context = [{'Name': 'local', 'Endpoints': {'docker': {'Host': 'unix:///tmp/docker.sock'}}}]
        host, env = runner.pinned_environment({'DOCKER_CONTEXT': 'local'}, context)
        self.assertEqual(host, env['DOCKER_HOST'])
        self.assertNotIn('DOCKER_CONTEXT', env)
        for ambient in [{'DOCKER_HOST': 'unix:///tmp/other.sock'}, {'DOCKER_CONTEXT': 'other'},
                        {'DOCKER_TLS_VERIFY': '1'}, {'DOCKER_CERT_PATH': '/tmp/cert'}]:
            with self.subTest(ambient=next(iter(ambient))), self.assertRaises(runner.Stopped):
                runner.pinned_environment(ambient, context)
        context[0]['Endpoints']['docker']['Host'] = 'tcp://remote.invalid:2376'
        with self.assertRaises(runner.Stopped):
            runner.pinned_environment({}, context)

    def test_exclusive_reservation_precedes_any_provisioning(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner, 'STATE', Path(temp) / 'state.json'):
            runner.reserve_state({'state': 'reserving', 'suite': 'bridge',
                                  'docker_host': 'unix:///tmp/docker.sock', 'runner_sources': runner.source_manifest()}, Path(temp))
            self.assertEqual(json.loads(runner.STATE.read_text())['state'], 'reserving')
            original = runner.STATE.read_bytes()
            with patch.object(runner, 'provision') as provision, self.assertRaises(FileExistsError):
                runner.qualify('owners', Path(temp) / 'new', 'unix:///tmp/docker.sock', {})
            provision.assert_not_called()
            self.assertEqual(original, runner.STATE.read_bytes())
            self.assertEqual(list((Path(temp) / 'new').iterdir()), [])

    def test_failure_retains_exclusive_owner_and_never_disposes_or_retries(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner, 'STATE', Path(temp) / 'state.json'):
            directory = Path(temp) / 'suite'
            with patch.object(runner, 'provision', side_effect=runner.Stopped('fresh_replay_failed')) as provision, \
                    patch.object(runner, 'dispose') as dispose, self.assertRaises(runner.Stopped):
                runner.qualify('owners', directory, 'unix:///tmp/docker.sock', {})
            self.assertEqual(provision.call_count, 1)
            dispose.assert_not_called()
            self.assertTrue(runner.STATE.exists())
            receipt = json.loads((directory / 'failure.json').read_text())
            self.assertEqual(receipt['category'], 'fresh_replay_failed')
            self.assertTrue(receipt['original_ownership_retained'])

    def test_untrusted_exception_text_never_persisted(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner, 'STATE', Path(temp) / 'state.json'):
            directory = Path(temp) / 'suite'
            with patch.object(runner, 'provision', side_effect=ValueError('synthetic-private-diagnostic')), self.assertRaises(runner.Stopped):
                runner.qualify('owners', directory, 'unix:///tmp/docker.sock', {})
            self.assertNotIn('synthetic-private-diagnostic', (directory / 'failure.json').read_text())

    def test_dispatch_is_literal_and_scripts_exist(self):
        self.assertEqual(len(runner.SUITES), 22)
        self.assertEqual(runner.SUITES['legacy_quota'], ('test_initial_media_handoff_legacy_quota.py', ()))
        for name, (script, args) in runner.SUITES.items():
            with self.subTest(suite=name):
                self.assertTrue((runner.SCRIPTS / script).is_file())
                self.assertNotIn('/', script)
                self.assertTrue(not args or args[0] in ('--shape', '--root'))

    def test_post_stop_failure_keeps_disposal_phase_and_exit_without_retry(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner, 'STATE', Path(temp) / 'state.json'), \
                patch.object(runner, 'temporary_root', return_value=Path(temp)):
            work = Path(temp) / 'merian-handoff-runtime-abcdefgh'
            work.mkdir()
            record = {'state': 'ready', 'suite': 'bridge', 'workdir': str(work), 'project': work.name,
                      'container': 'supabase_db_' + work.name, 'docker_host': 'unix:///tmp/docker.sock',
                      'runner_sources': runner.source_manifest()}
            runner.reserve_state(record, Path(temp))
            with patch.object(runner, 'inspect_owned'), patch.object(runner, 'sql', return_value=json.dumps({
                    'activation_enabled': False, 'invocations': 0, 'private_receipts': 0, 'preparation_intents': 0})), \
                    patch.object(runner.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as stop, \
                    patch.object(runner, 'run', side_effect=runner.Stopped('container_list_failed')), \
                    self.assertRaises(runner.Stopped):
                runner.dispose(record, {}, Path(temp))
            self.assertEqual(stop.call_count, 1)
            self.assertEqual(record['state'], 'stopped')
            self.assertEqual(json.loads(runner.STATE.read_text())['stop_exit'], 0)
            mirror = json.loads((Path(temp) / 'ownership.json').read_text())
            self.assertEqual(mirror['state'], 'stopped')
            self.assertEqual(mirror['stop_exit'], 0)
            self.assertEqual(mirror['project'], work.name)
            self.assertTrue(work.exists())

    def test_residual_contract_is_closed_and_unexpected_roots_prevent_stop(self):
        self.assertEqual(set(runner.EXPECTED_RESIDUALS), set(runner.SUITES))
        self.assertEqual({k: v for k, v in runner.EXPECTED_RESIDUALS.items() if v != (0, 0)},
                         {'state': (1, 1), 'pruning': (1, 1), 'expiry': (1, 0), 'public_deletion': (1, 0)})
        for suite, expected in runner.EXPECTED_RESIDUALS.items():
            with self.subTest(suite=suite), patch.object(runner, 'inspect_owned'), \
                    patch.object(runner, 'sql', return_value=json.dumps({
                        'activation_enabled': False, 'invocations': 0,
                        'private_receipts': expected[0] + 1, 'preparation_intents': expected[1]})), \
                    patch.object(runner.subprocess, 'run') as stop, self.assertRaisesRegex(runner.Stopped, 'unexpected_disposal_residuals'):
                runner.dispose({'suite': suite}, {}, Path('/unused'))
            stop.assert_not_called()

    def test_reservation_and_before_ready_failure_retain_sanitized_identity(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner, 'STATE', Path(temp) / 'state.json'):
            directory = Path(temp) / 'suite'

            def failed_start(record, _env, output):
                first = json.loads((output / 'ownership.json').read_text())
                self.assertEqual(first['state'], 'reserving')
                self.assertEqual(first['suite'], 'bridge')
                self.assertEqual(first['docker_host'], 'unix:///tmp/docker.sock')
                self.assertTrue(first['runner_sources'])
                project = 'merian-handoff-runtime-abcdefgh'
                record.update(state='starting', project=project, container='supabase_db_' + project,
                              workdir=str(runner.temporary_root(runner.sys.platform) / project), start_exit=1,
                              raw_sql='synthetic-private-diagnostic')
                runner.checkpoint(record, output)
                raise runner.Stopped('fresh_replay_failed')

            with patch.object(runner, 'provision', side_effect=failed_start), \
                    patch.object(runner, 'dispose') as dispose, self.assertRaises(runner.Stopped):
                runner.qualify('bridge', directory, 'unix:///tmp/docker.sock', {})
            dispose.assert_not_called()
            mirror = json.loads((directory / 'ownership.json').read_text())
            self.assertEqual(mirror['state'], 'starting')
            self.assertEqual(mirror['start_exit'], 1)
            self.assertEqual(mirror['project'], 'merian-handoff-runtime-abcdefgh')
            self.assertNotIn('raw_sql', mirror)
            with patch.object(runner.subprocess, 'run') as child:
                runner.snapshot_ownership(directory)
            child.assert_not_called()
            self.assertEqual(json.loads((directory / 'ownership-at-end.json').read_text()), mirror)

    def test_snapshot_without_owner_never_calls_docker_or_provisions(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner, 'STATE', Path(temp) / 'missing.json'), \
                patch.object(runner.subprocess, 'run') as child:
            runner.snapshot_ownership(Path(temp) / 'output')
            self.assertEqual(json.loads((Path(temp) / 'output/ownership-at-end.json').read_text())['state'], 'absent')
            self.assertFalse(runner.STATE.exists())
            child.assert_not_called()

    def test_snapshot_rejects_truncated_identity_without_docker(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner, 'STATE', Path(temp) / 'state.json'), \
                patch.object(runner.subprocess, 'run') as child:
            runner.STATE.write_text('{"state":"starting"}\n')
            with self.assertRaisesRegex(runner.Stopped, 'ownership_identity_invalid'):
                runner.snapshot_ownership(Path(temp) / 'output')
            self.assertFalse((Path(temp) / 'output/ownership-at-end.json').exists())
            self.assertEqual(runner.STATE.read_text(), '{"state":"starting"}\n')
            child.assert_not_called()


if __name__ == '__main__':
    unittest.main()
