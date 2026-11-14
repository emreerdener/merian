"""No-build checks for the saved selector and fail-closed integrity boundaries."""
import base64
import copy
import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('artifact', ROOT / 'artifact.py')
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.entry = a.select_version('wav-feasibility-darwin-arm64-v1')
        self.archive_entry = copy.deepcopy(self.entry)
        files = []
        for index, item in enumerate(self.archive_entry['inputs']):
            content = ('synthetic module ' + str(index)).encode()
            item.update(sha256=a.sha(content), byte_count=len(content))
            files.append(dict(item, base64=base64.b64encode(content).decode()))
        extra = b'synthetic prompt outside preparation closure'
        files.append(dict(path=a.PREFIX + 'prompts/probe.txt', sha256=a.sha(extra),
                          byte_count=len(extra), base64=base64.b64encode(extra).decode()))
        self.archive = json.dumps(dict(catalog=dict(
            digest=self.entry['configuration_digest'], manifest=dict(
                repository_revision=self.entry['archive_revision'])), files=files)).encode()
        self.archive_entry['archive_sha256'] = a.sha(self.archive)

    def test_unknown_version_has_no_fallback(self):
        with self.assertRaisesRegex(ValueError, 'unknown_version'):
            a.select_version('latest')

    def test_source_anchor_is_committed_blob(self):
        from types import SimpleNamespace
        content = b'synthetic bootstrap'
        entry = dict(self.entry, bootstrap_sha256=a.sha(content))
        tree = ('100644 blob ' + entry['bootstrap_blob_sha1'] + '\t' + a.BOOTSTRAP + '\0').encode()
        def reply(command, **kwargs):
            args = command[4:]
            if args[:2] == ['cat-file', '-t']:
                output = b'commit\n'
            elif args[0] == 'ls-tree':
                output = tree
            elif args[:2] == ['cat-file', '-s']:
                output = str(len(content)).encode()
            else:
                output = content
            return SimpleNamespace(returncode=0, stdout=output)
        with patch.object(a.subprocess, 'run', side_effect=reply):
            self.assertEqual(a.read_bootstrap(entry), content)
            with self.assertRaisesRegex(ValueError, 'bootstrap_digest'):
                a.read_bootstrap(dict(entry, bootstrap_sha256='0' * 64))
        with patch.object(a.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout=b'tree\n')):
            with self.assertRaisesRegex(ValueError, 'bootstrap_commit'):
                a.read_bootstrap(entry)

    def test_registry_rejects_unbound_or_malformed_provenance(self):
        for changes in [{'toolchain_provenance_sha256': '0' * 64}, {'extra': True}, {'bootstrap_blob_sha1': '--help'}, {'artifact_bytes': None}, {'inputs': []}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                a.validate_entry(dict(self.entry, **changes))

    def test_output_root_rejects_public_modes_and_link_ancestors(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary).resolve()
            (root / 'private').mkdir(mode=0o700)
            self.assertEqual(a.private_output_directory(root / 'private'), root / 'private')
            (root / 'alias').symlink_to(root / 'private', target_is_directory=True)
            (root / 'private' / 'child').mkdir(mode=0o700)
            for directory in [root / 'alias', root / 'alias' / 'child']:
                with self.assertRaises(ValueError):
                    a.publish(directory, 'artifact', b'no')
            (root / 'private').chmod(0o755)
            with self.assertRaisesRegex(ValueError, 'output_privacy'):
                a.private_output_directory(root / 'private')

    def test_archive_and_each_recorded_input(self):
        files = a.verify_archive(self.archive, self.archive_entry)
        for member in self.archive_entry['inputs']:
            self.assertEqual(a.sha(files[member['path']]), member['sha256'])
        with self.assertRaisesRegex(ValueError, 'archive_digest'):
            a.verify_archive(self.archive + b' ', self.archive_entry)
        for name in ['configuration_digest', 'archive_revision']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                a.verify_archive(self.archive, dict(self.archive_entry, **{name: 'changed'}))
        for index in range(len(self.entry['inputs'])):
            changed = copy.deepcopy(self.archive_entry)
            changed['inputs'][index]['sha256'] = '0' * 64
            with self.subTest(index=index), self.assertRaisesRegex(ValueError, 'input_digest'):
                a.verify_archive(self.archive, changed)
        changed = copy.deepcopy(self.archive_entry)
        changed['inputs'].append(changed['inputs'][0])
        with self.assertRaisesRegex(ValueError, 'input_closure'):
            a.verify_archive(self.archive, changed)

    def test_prompt_tamper_even_outside_wav_closure_is_rejected(self):
        changed = json.loads(self.archive)
        changed['files'][-1]['base64'] = ''
        with self.assertRaisesRegex(ValueError, 'archive_digest'):
            a.verify_archive(json.dumps(changed).encode(), self.archive_entry)

    def test_unregistered_or_tampered_artifact_is_held(self):
        with self.assertRaisesRegex(ValueError, 'unregistered_artifact'):
            a.verify_artifact(b'export const different = true;', self.entry)

    def test_output_requires_completion_identity_and_exact_bytes(self):
        good = dict(version=1, operation='identity', input_bytes=1,
                    input_sha256=a.sha(b'a'), output_bytes=1,
                    output_sha256=a.sha(b'a'), base64='YQ==', complete=True)
        self.assertEqual(a.validate_answer(good, 'identity', b'a'), b'a')
        for key, value in [('complete', False), ('output_bytes', True),
                           ('output_sha256', '0' * 64), ('operation', 'wav16k'),
                           ('extra', 1), ('input_bytes', 4)]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                a.validate_answer(dict(good, **{key: value}), 'identity', b'a')

    def test_no_replace_publication_and_link_rejection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary).resolve()
            a.publish(root, 'one', b'abc')
            a.publish(root, 'one', b'abc')
            with self.assertRaises(ValueError):
                a.publish(root, 'one', b'def')
            (root / 'link').symlink_to(root / 'one')
            with self.assertRaises(OSError):
                a.read_regular(root / 'link', 10)
            self.assertEqual((root / 'one').read_bytes(), b'abc')
            self.assertEqual(len(list(root.glob('.pending-*'))), 0)

    def test_reported_toolchain_version_and_target_are_exact(self):
        raw = b'deno 2.9.4 (stable, release, aarch64-apple-darwin)\nv8 15.0.245.2-rusty\ntypescript 6.0.3\n'
        self.assertEqual(a.verify_toolchain_report(raw)['deno_target'], 'aarch64-apple-darwin')
        for changed in [raw.replace(b'2.9.4', b'2.9.5'), raw.replace(b'aarch64', b'x86_64'), raw + b'extra']:
            with self.assertRaisesRegex(ValueError, 'toolchain_version'):
                a.verify_toolchain_report(changed)

    def test_expected_negative_exit_never_accepts_parent_failure(self):
        result = dict(exit=1, failure=None, reaped=True, process_group_gone=True, rss_samples=1)
        self.assertTrue(a.expected_exit(result, 1))
        for changed in [dict(exit=None, failure='timeout'), dict(failure='output_limit'),
                        dict(reaped=False), dict(process_group_gone=False), dict(rss_samples=0)]:
            with self.subTest(changed=changed):
                self.assertFalse(a.expected_exit(dict(result, **changed), 1))

    def test_null_registration_holds_before_any_build(self):
        from types import SimpleNamespace
        entry = dict(self.entry, artifact_sha256=None, artifact_bytes=None)
        with patch.object(a, 'select_version', return_value=entry), \
                patch.object(a.subprocess, 'Popen') as spawn:
            with self.assertRaisesRegex(ValueError, 'unregistered_artifact'):
                a.qualify(SimpleNamespace(version=entry['id'], build_only=False))
            spawn.assert_not_called()

    def test_input_bounds_reject_before_spawn(self):
        with patch.object(a.subprocess, 'Popen') as spawn:
            for values in [dict(data=b'x' * 300001), dict(limit=0), dict(timeout=16)]:
                with self.subTest(values=list(values)), self.assertRaisesRegex(ValueError, 'process_bounds'):
                    a.run(['not-invoked', 'run'], ROOT, ROOT, **values)
            spawn.assert_not_called()

    def test_deadline_rejects_late_sampling_or_completion(self):
        with patch.object(a.time, 'monotonic', return_value=10.2):
            self.assertAlmostEqual(a.remaining_time(10, 0.3), 0.1)
        for now in [10.3, 12]:
            with patch.object(a.time, 'monotonic', return_value=now):
                with self.assertRaisesRegex(RuntimeError, 'timeout'):
                    a.remaining_time(10, 0.3)

    def test_one_checkout_execution_and_lock_survives(self):
        with tempfile.TemporaryDirectory() as temporary:
            lock = pathlib.Path(temporary).resolve() / 'lock'
            with patch.object(a, 'LOCK', lock):
                with a.execution_lock():
                    with self.assertRaisesRegex(ValueError, 'execution_busy'):
                        with a.execution_lock():
                            self.fail('concurrent harness admitted')
                self.assertTrue(lock.exists())
                with a.execution_lock():
                    pass

    def test_source_tree_modes_restore_after_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary).resolve()
            (root / 'nested').mkdir()
            with self.assertRaisesRegex(RuntimeError, 'fixture'):
                with a.locked_tree(root):
                    for directory in [root, root / 'nested']:
                        self.assertEqual(directory.stat().st_mode & 0o777, 0o500)
                    raise RuntimeError('fixture')
            self.assertEqual(root.stat().st_mode & 0o777, 0o700)

    def test_setup_failure_kills_and_reaps_spawned_child(self):
        from unittest.mock import MagicMock
        child = MagicMock(pid=987654)
        child.stdin.closed = child.stdout.closed = child.stderr.closed = False
        with patch.object(a, 'verify_regular'), \
                patch.object(a.subprocess, 'Popen', return_value=child), \
                patch.object(a.os, 'set_blocking', side_effect=OSError('setup')), \
                patch.object(a.os, 'killpg', side_effect=lambda pid, sig: (_ for _ in ()).throw(ProcessLookupError()) if sig == 0 else None) as kill:
            with self.assertRaisesRegex(OSError, 'setup'):
                a.run(['not-invoked', 'run'], ROOT, ROOT)
            self.assertEqual(kill.call_args_list, [unittest.mock.call(child.pid, a.signal.SIGKILL), unittest.mock.call(child.pid, 0)])
            child.wait.assert_called_once_with(timeout=5)
            for stream in [child.stdin, child.stdout, child.stderr]:
                stream.close.assert_called_once()

    def test_disk_floor_stops_before_provision_or_spawn(self):
        from types import SimpleNamespace
        options = SimpleNamespace(version=self.entry['id'], toolchain=ROOT,
                                  output=ROOT, build_only=True)
        with patch.object(a, 'private_output_directory', return_value=ROOT), \
                patch.object(a.platform, 'system', return_value='Darwin'), \
                patch.object(a.platform, 'machine', return_value='arm64'), \
                patch.object(a.shutil, 'disk_usage', return_value=SimpleNamespace(free=20 * 1024**3)), \
                patch.object(a.subprocess, 'Popen') as spawn:
            with self.assertRaisesRegex(ValueError, 'disk_floor'):
                a.qualify(options)
            spawn.assert_not_called()


    def test_validated_profile_has_closed_independent_source_bindings(self):
        entry = a.select_version(a.VALIDATED)
        self.assertEqual(entry['inputs'], self.entry['inputs'])
        self.assertEqual(entry['archive_sha256'], self.entry['archive_sha256'])
        self.assertNotEqual(entry['bootstrap_path'], self.entry['bootstrap_path'])
        self.assertEqual(a.profile_paths(a.VALIDATED), (a.VALIDATED_BOOTSTRAP, a.CLOSURE + [a.VALIDATOR]))
        for changes in [dict(id='future'), dict(bootstrap_path=a.BOOTSTRAP),
                        dict(bootstrap_bytes=True), dict(validator={}), dict(extra=True)]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                a.validate_entry(dict(entry, **changes))
        for changes in [dict(path='../escape.ts'), dict(commit='HEAD'),
                        dict(blob_sha1='--help'), dict(sha256='0'), dict(byte_count=True), dict(extra=1)]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                a.validate_entry(dict(entry, validator=dict(entry['validator'], **changes)))

    def test_validated_committed_sources_are_separately_checked(self):
        entry = a.select_version(a.VALIDATED)
        with patch.object(a, 'read_committed', return_value=b'checked') as read:
            candidate = copy.deepcopy(entry)
            candidate['bootstrap_bytes'] = len(b'checked')
            self.assertEqual(a.read_bootstrap(candidate), b'checked')
            self.assertEqual(read.call_args.args[0], a.VALIDATED_BOOTSTRAP)
            candidate['validator']['byte_count'] = len(b'checked')
            self.assertEqual(a.read_validator(candidate), b'checked')
            self.assertEqual(read.call_args.args[0], a.VALIDATOR)
            with self.assertRaisesRegex(ValueError, 'validator_bytes'):
                a.read_validator(entry)
            with self.assertRaisesRegex(ValueError, 'bootstrap_bytes'):
                a.read_bootstrap(entry)

    def test_profile_cache_allowlist_does_not_expand_historical_profile(self):
        cwd = pathlib.Path('/private/synthetic')
        item = dict(path='gen/file/' + str(cwd / a.VALIDATOR).lstrip('/') + '.js', type='file', bytes=1)
        with self.assertRaises(ValueError):
            a.validate_cache([item], cwd / 'cache', cwd, cwd / 'deno', 'build')
        a.validate_cache([item], cwd / 'cache', cwd, cwd / 'deno', 'build', a.VALIDATED)
        with patch.object(a.subprocess, 'Popen') as spawn:
            with self.assertRaisesRegex(ValueError, 'unknown_version'):
                a.run(['unused', 'run'], cwd, cwd, profile='future')
            spawn.assert_not_called()

    def test_validated_output_requires_exact_wire_types_bytes_and_option(self):
        source, output = b'synthetic input', b'synthetic output'
        answer = dict(version=2, operation='validated_wav16k',
                      preserve_source_when_trimmed_too_short=True,
                      input_bytes=len(source), input_sha256=a.sha(source),
                      output_bytes=len(output), output_sha256=a.sha(output),
                      base64=base64.b64encode(output).decode(), complete=True)
        raw = a.compact(answer) + b'\n'
        self.assertEqual(a.validate_validated_answer(raw, source, True), output)
        for altered in [raw.replace(b'"version":2', b'"version":2,"version":2'), raw + b' ',
                        raw.replace(b':true', b':1'), a.compact(dict(answer, extra=1)) + b'\n']:
            with self.assertRaises(ValueError):
                a.validate_validated_answer(altered, source, True)
        for changes in [dict(input_sha256='0'*64), dict(output_sha256='0'*64),
                        dict(output_bytes=True), dict(preserve_source_when_trimmed_too_short=False)]:
            with self.assertRaises(ValueError):
                a.validate_validated_answer(a.compact(dict(answer, **changes)) + b'\n', source, True)


if __name__ == '__main__':
    unittest.main()
