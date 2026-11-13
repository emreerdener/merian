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


class FailedDisposalTests(unittest.TestCase):
    def fixture(self):
        from contextlib import contextmanager

        @contextmanager
        def owned():
            with tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                with patch.object(runner, 'STATE', root / 'state.json'), \
                        patch.object(runner, 'temporary_root', return_value=root):
                    work = root / 'merian-handoff-runtime-abcdefgh'
                    (work / 'supabase/migrations').mkdir(parents=True)
                    config = work / 'supabase/config.toml'
                    config.write_text('fixture')
                    name = sorted((runner.ROOT / 'services/supabase/migrations').glob('*.sql'))[0].name
                    migration = work / 'supabase/migrations' / name
                    migration.write_text('SELECT 1;')
                    record = dict(state='ready', suite='io_readers', project=work.name,
                                  container='supabase_db_' + work.name, workdir=str(work),
                                  docker_host='unix:///tmp/docker.sock', runner_sources=runner.source_manifest(),
                                  migration_hashes={name: runner.digest(migration)},
                                  temporary_config_sha256=runner.digest(config))
                    original = root / 'original'
                    original.mkdir()
                    runner.save(runner.STATE, record)
                    runner.save(original / 'replay.json', record)
                    runner.save(original / 'failure.json', dict(passed=False, phase='ready', suite='io_readers',
                                original_ownership_retained=True, migration_hashes=record['migration_hashes'],
                                runner_sources=record['runner_sources']))
                    observed = dict(activation_enabled=False, invocations=0, private_receipts=1,
                                    preparation_intents=1, copy_progress=1, cancellation_staging=0, admission_staging=0,
                                    handoff_staging=0, other_client_sessions=0)
                    proof = dict(version=1, qualificationPassed=False, failure_directory=str(original),
                                 identity={k: record[k] for k in ('suite', 'project', 'container', 'workdir', 'docker_host')},
                                 original_state_sha256=runner.digest(runner.STATE),
                                 failure_sha256=runner.digest(original / 'failure.json'),
                                 replay_sha256=runner.digest(original / 'replay.json'), observed=observed.copy())
                    proof_path = root / 'reconciliation.json'
                    runner.save(proof_path, proof)
                    yield SimpleNamespace(root=root, work=work, original=original, proof=proof,
                                          proof_path=proof_path, observed=observed, output=root / 'disposition',
                                          original_bytes={p.name: p.read_bytes() for p in original.iterdir()})
        return owned()

    def invoke(self, fixture):
        runner.dispose_reconciled_failure(fixture.proof_path, fixture.output, 'unix:///tmp/docker.sock', {})

    def test_failed_disposal_preserves_failure_and_is_never_a_pass(self):
        with self.fixture() as f, patch.object(runner, 'inspect_owned'), \
                patch.object(runner, 'sql', return_value=json.dumps(f.observed)), \
                patch.object(runner.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as stop, \
                patch.object(runner, 'run', return_value=''):
            self.invoke(f)
            stop.assert_called_once()
            self.assertFalse(runner.STATE.exists())
            self.assertFalse(f.work.exists())
            self.assertFalse((f.output / 'result.json').exists())
            result = json.loads((f.output / 'failed-disposition.json').read_text())
            self.assertFalse(result['qualificationPassed'])
            self.assertEqual(result['state'], 'disposed')
            self.assertEqual(result['observedResiduals']['private_receipts'], 1)
            self.assertTrue(result['containerAbsent'])
            self.assertTrue(result['temporaryWorkdirRemoved'])
            self.assertEqual({p.name: p.read_bytes() for p in f.original.iterdir()}, f.original_bytes)

    def test_missing_wrong_changed_or_live_evidence_cannot_stop(self):
        for case in ('missing', 'identity', 'failure_hash', 'replay_hash', 'state_hash',
                     'counts', 'active', 'invocation', 'session', 'staging', 'admission_stage', 'project_bytes', 'output_inside'):
            with self.subTest(case=case), self.fixture() as f, patch.object(runner, 'inspect_owned'), \
                    patch.object(runner, 'sql', return_value=json.dumps(f.observed)), \
                    patch.object(runner.subprocess, 'run') as stop:
                original_state = runner.STATE.read_bytes()
                if case == 'missing':
                    (f.original / 'failure.json').unlink()
                elif case == 'identity':
                    f.proof['identity']['project'] = 'merian-handoff-runtime-wrong000'
                elif case.endswith('_hash'):
                    key = {'failure_hash': 'failure_sha256', 'replay_hash': 'replay_sha256',
                           'state_hash': 'original_state_sha256'}[case]
                    f.proof[key] = '0' * 64
                elif case == 'counts':
                    f.proof['observed']['private_receipts'] = 2
                elif case == 'project_bytes':
                    (f.work / 'supabase/config.toml').write_text('changed')
                elif case == 'output_inside':
                    f.output = f.work / 'evidence'
                else:
                    key = {'active': 'activation_enabled', 'invocation': 'invocations',
                           'session': 'other_client_sessions', 'staging': 'handoff_staging',
                           'admission_stage': 'admission_staging'}[case]
                    f.proof['observed'][key] = True if case == 'active' else 1
                runner.save(f.proof_path, f.proof)
                with self.assertRaises((runner.Stopped, FileNotFoundError)):
                    self.invoke(f)
                stop.assert_not_called()
                self.assertEqual(runner.STATE.read_bytes(), original_state)
                self.assertTrue(f.work.exists())

    def test_live_state_changes_after_reconciliation_cannot_stop(self):
        with self.fixture() as f, patch.object(runner, 'inspect_owned'), \
                patch.object(runner, 'sql', return_value=json.dumps({**f.observed, 'other_client_sessions': 1})), \
                patch.object(runner.subprocess, 'run') as stop, self.assertRaises(runner.Stopped):
            self.invoke(f)
        stop.assert_not_called()

    def test_interruption_retains_owner_and_failed_disposition(self):
        with self.fixture() as f, patch.object(runner, 'inspect_owned'), \
                patch.object(runner, 'sql', return_value=json.dumps(f.observed)), \
                patch.object(runner.subprocess, 'run', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.invoke(f)
            self.assertEqual(json.loads(runner.STATE.read_text())['state'], 'disposing')
            self.assertFalse(json.loads((f.output / 'failed-disposition.json').read_text())['qualificationPassed'])
            self.assertTrue(f.work.exists())
            self.assertEqual({p.name: p.read_bytes() for p in f.original.iterdir()}, f.original_bytes)

    def test_competing_process_denied_before_reading_proof_and_lock_is_reusable(self):
        child = """import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import run_initial_media_handoff_qualification as r
r.STATE = Path(sys.argv[2])
try:
 r.dispose_reconciled_failure(Path(sys.argv[2] + '.missing'), Path(sys.argv[2] + '.output'), 'unix:///tmp/docker.sock', {})
except r.Stopped as error:
 print(str(error))
 sys.exit(0 if str(error) == sys.argv[3] else 1)
raise SystemExit(2)
"""
        with self.fixture():
            path = runner.STATE.with_suffix('.recovery.lock')
            with runner.failed_disposal_lock():
                identity = path.stat().st_ino
                result = runner.subprocess.run([runner.sys.executable, '-c', child, str(runner.SCRIPTS),
                                                str(runner.STATE), 'recovery_busy'], capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), 'recovery_busy')
            result = runner.subprocess.run([runner.sys.executable, '-c', child, str(runner.SCRIPTS),
                                            str(runner.STATE), 'reconciliation_file_invalid'], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(path.stat().st_ino, identity)

    def test_process_death_releases_lock_without_replacing_inode(self):
        child = """import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import run_initial_media_handoff_qualification as r
r.STATE = Path(sys.argv[2])
with r.failed_disposal_lock():
 print('locked', flush=True)
 sys.stdin.readline()
"""
        with self.fixture():
            process = runner.subprocess.Popen([runner.sys.executable, '-c', child, str(runner.SCRIPTS), str(runner.STATE)],
                                              stdin=runner.subprocess.PIPE, stdout=runner.subprocess.PIPE, text=True)
            try:
                import select
                ready, _, _ = select.select([process.stdout], [], [], 10)
                self.assertTrue(ready)
                self.assertEqual(process.stdout.readline().strip(), 'locked')
                identity = runner.STATE.with_suffix('.recovery.lock').stat().st_ino
                with self.assertRaisesRegex(runner.Stopped, 'recovery_busy'), runner.failed_disposal_lock():
                    self.fail('competing owner admitted')
                process.terminate()
                process.wait(timeout=10)
                with runner.failed_disposal_lock():
                    self.assertEqual(runner.STATE.with_suffix('.recovery.lock').stat().st_ino, identity)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=10)
                process.stdin.close()
                process.stdout.close()

    def test_interrupted_disposal_cannot_repeat_stop_after_lock_release(self):
        with self.fixture() as f, patch.object(runner, 'inspect_owned'), \
                patch.object(runner, 'sql', return_value=json.dumps(f.observed)), \
                patch.object(runner.subprocess, 'run', side_effect=KeyboardInterrupt) as stop:
            with self.assertRaises(KeyboardInterrupt):
                self.invoke(f)
            with self.assertRaisesRegex(runner.Stopped, 'failed_disposal_owner_not_ready'):
                self.invoke(f)
            self.assertEqual(stop.call_count, 1)
            self.assertEqual(json.loads(runner.STATE.read_text())['state'], 'disposing')

    def test_post_stop_failure_keeps_owner_without_retry_or_path_removal(self):
        with self.fixture() as f, patch.object(runner, 'inspect_owned'), \
                patch.object(runner, 'sql', return_value=json.dumps(f.observed)), \
                patch.object(runner.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as stop, \
                patch.object(runner, 'run', side_effect=runner.Stopped('failed_disposal_container_list_failed')):
            with self.assertRaises(runner.Stopped):
                self.invoke(f)
            stop.assert_called_once()
            self.assertEqual(json.loads(runner.STATE.read_text())['state'], 'stopped')
            self.assertEqual(json.loads(runner.STATE.read_text())['stop_exit'], 0)
            self.assertTrue(f.work.exists())
            self.assertFalse((f.output / 'result.json').exists())

    def test_failed_stop_retains_owner_and_original_evidence(self):
        with self.fixture() as f, patch.object(runner, 'inspect_owned'), \
                patch.object(runner, 'sql', return_value=json.dumps(f.observed)), \
                patch.object(runner.subprocess, 'run', return_value=SimpleNamespace(returncode=1)), \
                patch.object(runner, 'run') as after:
            with self.assertRaises(runner.Stopped):
                self.invoke(f)
            after.assert_not_called()
            self.assertEqual(json.loads(runner.STATE.read_text())['state'], 'disposal_failed')
            self.assertTrue(f.work.exists())
            self.assertEqual({p.name: p.read_bytes() for p in f.original.iterdir()}, f.original_bytes)

if __name__ == '__main__':
    unittest.main()
