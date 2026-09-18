#!/usr/bin/env python3
"""Exercise local build retention and cleanup against disposable fixtures."""

import importlib.util
import json
from types import SimpleNamespace
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('local_ios_build', Path(__file__).with_name('local-ios-build.py'))
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class LocalBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.workspace = build.Workspace(self.root)
        probe = patch.object(build.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1))
        probe.start()
        self.addCleanup(probe.stop)

    def seed(self, relative):
        path = self.root / relative
        path.mkdir(parents=True, exist_ok=True)
        (path / 'keep.txt').write_text('fixture')
        return path

    def test_cleanup_preview_preserves_everything(self):
        target = self.seed('.build/local-ios/simulator')
        with patch.object(build, 'ensure_no_xcodebuild') as check:
            self.workspace.clean(False)
        check.assert_not_called()
        self.assertTrue(target.exists())

    def test_cleanup_removes_only_managed_outputs(self):
        outputs = [self.seed(f'.build/local-ios/{name}') for name in ('simulator', 'device', 'temporary')]
        retained = [self.seed(name) for name in (
            '.build/local-ios/packages', '.build/local-ios/package-cache',
            '.build/old-review', '.build/codex-release-proof',
            '.artifacts/local-ios/run.xcresult', 'Archives/release.xcarchive',
        )]
        with patch.object(build, 'ensure_no_xcodebuild'):
            self.workspace.clean(True)
        self.assertTrue(all(not path.exists() for path in outputs))
        self.assertTrue(all((path / 'keep.txt').exists() for path in retained))

    def test_active_build_and_unknown_process_state_prevent_cleanup(self):
        target = self.seed('.build/local-ios/simulator')
        for status in (0, 2):
            with self.subTest(status=status), patch.object(build.subprocess, 'run', return_value=subprocess.CompletedProcess([], status)):
                with self.assertRaises(RuntimeError):
                    self.workspace.clean(True)
            self.assertTrue(target.exists())

    def test_inactive_process_check_accepts_only_no_matches(self):
        with patch.object(build.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)):
            build.ensure_no_xcodebuild()

    def test_shared_lock_prevents_build_and_cleanup_overlap(self):
        self.seed('.build/local-ios/simulator')
        with self.workspace.lock():
            with self.assertRaises(RuntimeError):
                self.workspace.clean(True)
            with self.assertRaises(RuntimeError):
                self.workspace.run('simulator', False, ['build'])
        # A finished operation releases the lock; no stale PID/manual lock removal needed.
        with self.workspace.lock():
            pass

    def test_symlinked_managed_paths_are_rejected(self):
        for relative in ('.build', '.build/local-ios', '.build/local-ios/simulator', '.build/.local-ios.lock'):
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as root:
                workspace = build.Workspace(Path(root))
                outside = self.seed('outside')
                link = workspace.root / relative
                link.parent.mkdir(parents=True, exist_ok=True)
                link.symlink_to(outside)
                with self.assertRaises(RuntimeError):
                    workspace.clean(True)
                self.assertTrue((outside / 'keep.txt').exists())

    def test_nested_symlink_does_not_delete_external_data(self):
        target = self.seed('.build/local-ios/simulator')
        outside = self.seed('outside')
        (target / 'link').symlink_to(outside)
        with patch.object(build, 'ensure_no_xcodebuild'):
            self.workspace.clean(True)
        self.assertTrue((outside / 'keep.txt').exists())

    def test_low_space_prevents_build(self):
        with patch.object(build.shutil, 'disk_usage', return_value=shutil._ntuple_diskusage(100, 90, 19 * build.GIB)), patch.object(build, 'run_child') as child:
            with self.assertRaises(RuntimeError):
                self.workspace.run('simulator', False, ['build'])
            child.assert_not_called()

    def test_warning_threshold_still_allows_build(self):
        with patch.object(build.shutil, 'disk_usage', return_value=shutil._ntuple_diskusage(100, 60, 40 * build.GIB)):
            build.check_space(self.root)

    def test_repeated_builds_reuse_caches_and_separate_reports(self):
        with patch.object(build, 'check_space'), patch.object(build, 'run_child', return_value=0) as child:
            for _ in range(2):
                self.assertEqual(self.workspace.run('simulator', False, ['build']), 0)
        commands = [call.args[0] for call in child.call_args_list]
        for flag in ('-derivedDataPath', '-clonedSourcePackagesDirPath', '-packageCachePath'):
            self.assertEqual(commands[0][commands[0].index(flag) + 1], commands[1][commands[1].index(flag) + 1])
        reports = [Path(command[command.index('-resultBundlePath') + 1]) for command in commands]
        self.assertNotEqual(*reports)
        self.assertTrue(all(path.parent == self.workspace.reports for path in reports))
        self.assertEqual(commands[0][-1], 'CODE_SIGNING_ALLOWED=NO')
        self.assertIn('-onlyUsePackageVersionsFromResolvedFile', commands[0])
        self.assertIn('-disableAutomaticPackageResolution', commands[0])
        self.assertIn('-disablePackageRepositoryCache', commands[0])

    def test_isolated_output_removed_after_success_failure_and_exception(self):
        for outcome in (0, 65, OSError('fixture launch failed')):
            with self.subTest(outcome=outcome):
                seen = []

                def child(command, root):
                    derived = Path(command[command.index('-derivedDataPath') + 1])
                    report = Path(command[command.index('-resultBundlePath') + 1])
                    self.assertTrue(derived.exists())
                    report.mkdir()
                    seen.append((derived, report))
                    if isinstance(outcome, Exception):
                        raise outcome
                    return outcome

                with patch.object(build, 'check_space'), patch.object(build, 'run_child', side_effect=child):
                    if isinstance(outcome, Exception):
                        with self.assertRaises(OSError):
                            self.workspace.run('device', True, ['build'])
                    else:
                        self.assertEqual(self.workspace.run('device', True, ['build']), outcome)
                self.assertFalse(seen[0][0].exists())
                self.assertTrue(seen[0][1].exists())

    def test_output_overrides_and_release_actions_are_rejected(self):
        for args in (['archive'], ['build', '-derivedDataPath', '/tmp/other'],
                     ['build', '-resultBundlePath=/tmp/report'], ['build', 'SYMROOT=/tmp/other'],
                     ['build', 'CODE_SIGNING_ALLOWED=YES'], ['build', '-allowProvisioningUpdates']):
            with self.subTest(args=args), self.assertRaises(RuntimeError):
                build.validate_args(args)

    def test_report_symlink_prevents_build(self):
        outside = self.seed('outside')
        (self.root / '.artifacts').symlink_to(outside)
        with patch.object(build, 'check_space'), patch.object(build, 'run_child') as child:
            with self.assertRaises(RuntimeError):
                self.workspace.run('simulator', False, ['build'])
            child.assert_not_called()

    def test_cli_isolation_and_passthrough(self):
        args = ['local-ios-build.py', 'run', '--isolated', 'simulator', '--',
                'test', '-destination', 'platform=iOS Simulator,id=fixture',
                '-only-testing:merianTests']
        with patch.object(build.sys, 'argv', args), patch.object(build, 'Workspace', return_value=self.workspace), patch.object(build, 'check_space'), patch.object(build, 'run_child', return_value=65) as child, patch.object(build.signal, 'signal'):
            self.assertEqual(build.main(), 65)
        command = child.call_args.args[0]
        self.assertIn('-only-testing:merianTests', command)
        derived = Path(command[command.index('-derivedDataPath') + 1])
        self.assertEqual(derived.parent, self.workspace.cache / 'temporary')
        self.assertFalse(derived.exists())

    def test_child_does_not_inherit_lock_and_interrupt_drains_group(self):
        with patch.object(build.subprocess, 'Popen') as launch, patch.object(build.os, 'killpg') as kill:
            launch.return_value.wait.side_effect = [KeyboardInterrupt(), 0]
            launch.return_value.pid = 1234
            with self.assertRaises(KeyboardInterrupt):
                build.run_child(['xcodebuild'], self.root)
        self.assertNotIn('pass_fds', launch.call_args.kwargs)
        self.assertTrue(launch.call_args.kwargs['start_new_session'])
        self.assertEqual(kill.call_count, 2)


class AuditBuildTests(unittest.TestCase):
    def test_environment_uses_stable_model_runtime_and_hardware_not_udid(self):
        workspace = build.Workspace(Path('/tmp'))
        devices = {'devices': {'iOS-fixture': [
            {'udid': 'one', 'name': 'iPhone fixture', 'isAvailable': True},
            {'udid': 'two', 'name': 'iPhone fixture', 'isAvailable': True}]}}
        def read(command, **kwargs):
            if command[0] == 'xcrun':
                return json.dumps(devices)
            return 'fixture'
        with patch.object(build.subprocess, 'check_output', side_effect=read), \
             patch.object(workspace, 'audit_workload_fingerprint', return_value='workload'), \
             patch.object(build.host_platform, 'platform', return_value='fixture'):
            first = workspace.audit_environment('platform=iOS Simulator,id=one', 'pool')
            second = workspace.audit_environment('platform=iOS Simulator,id=two', 'pool')
        self.assertEqual(first, second)
        self.assertEqual(first['runtime'], 'iOS-fixture')
        self.assertNotIn('destination', first)

    def test_workload_fingerprint_tracks_selectors_and_shared_fixtures(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            workspace = build.Workspace(root)
            inputs = ['project.yml', 'scripts/config/ios-runtime-audit.json',
                      'apps/ios/TestSupport/Fixture.swift',
                      'apps/ios/TestSupport/fixture.wav',
                      'apps/ios/Merian/App/UITesting/Seed.swift',
                      'apps/ios/Merian/App/UITesting/fixture.wav',
                      'apps/ios/Merian/Configuration/TestExecutionCoordinator.swift',
                      'apps/ios/MerianUITests/Launcher.swift',
                      'apps/ios/MerianPerformanceTests/Measurement.swift']
            for name in inputs:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('initial')
            original = workspace.audit_workload_fingerprint()
            self.assertEqual(original, workspace.audit_workload_fingerprint())
            for name in inputs:
                (root / name).write_text('changed')
                self.assertNotEqual(original, workspace.audit_workload_fingerprint())
                (root / name).write_text('initial')

    def test_source_identity_detects_untracked_edits_and_head_changes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            workspace = build.Workspace(root)
            path = root / 'NewTest.swift'
            path.write_text('initial')
            head = 'first'
            def read(command, **kwargs):
                if command[1] == 'ls-files':
                    return 'NewTest.swift\0'
                if command[1] == 'rev-parse':
                    return head
                return 'fixture'
            with patch.object(build.subprocess, 'check_output', side_effect=read):
                original = workspace.audit_source_identity()
                path.write_text('changed')
                self.assertNotEqual(original, workspace.audit_source_identity())
                path.write_text('initial')
                self.assertEqual(original, workspace.audit_source_identity())
                head = 'second'
                self.assertNotEqual(original, workspace.audit_source_identity())

    def exercise(self, fail_at=None, config_text=None, source_change_after=None, identity_failure_after=None):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            workspace = build.Workspace(root)
            config = root / 'scripts/config/ios-runtime-audit.json'
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({name: [dict(selector='target/Suite/testCase', suite_names=['Suite'])]
                                          for name in ('acceptance', 'ui', 'performance')}))
            if config_text is not None:
                config.write_text(config_text)
            calls = []
            reports = []

            def run(platform, isolated, args):
                # The full build/test chain must retain one uninterrupted cache lease.
                with self.assertRaises(RuntimeError):
                    with workspace.lock():
                        pass
                self.assertEqual(platform, 'simulator')
                self.assertFalse(isolated)
                calls.append(args)
                workspace.last_report = workspace.reports / f'{len(calls)}.xcresult'
                return 65 if len(calls) == fail_at else 0

            reporter = SimpleNamespace(extract=Mock(return_value={}),
                                       write_report=lambda output, evidence, baseline=None: reports.append(evidence))
            module_spec = SimpleNamespace(loader=SimpleNamespace(exec_module=lambda module: None))
            def source_identity():
                if identity_failure_after is not None and len(calls) >= identity_failure_after:
                    raise OSError('Cannot inspect source')
                changed = source_change_after is not None and len(calls) >= source_change_after
                return dict(source_sha='fixture', source_fingerprint='changed' if changed else 'fixture', source_dirty=False)
            with patch.object(build.importlib.util, 'spec_from_file_location', return_value=module_spec), \
                 patch.object(build.importlib.util, 'module_from_spec', return_value=reporter), \
                 patch.object(workspace, 'audit_source_identity', side_effect=source_identity), \
                 patch.object(workspace, 'audit_environment', return_value={'runner': 'fixture'}), \
                 patch.object(workspace, 'resolve_audit_packages'), \
                 patch.object(workspace, 'run_locked', side_effect=run):
                status = workspace.audit('platform=iOS Simulator,id=fixture', 'fixture')
            return status, calls, reports[0], reporter

    def test_malformed_manifest_retains_preflight_failure_without_building(self):
        for malformed in ('{broken', '{}', '[]'):
            with self.subTest(malformed=malformed):
                status, calls, evidence, reporter = self.exercise(config_text=malformed)
                self.assertEqual(status, 1)
                self.assertEqual(calls, [])
                self.assertEqual(evidence['phases'][0]['name'], 'preflight')
                self.assertEqual(evidence['phases'][0]['status'], 'failed')
                reporter.extract.assert_not_called()

    def test_builds_once_and_measurements_are_separate(self):
        status, calls, evidence, reporter = self.exercise()
        self.assertEqual(status, 0)
        self.assertEqual([args[0] for args in calls],
                         ['build-for-testing'] + ['test-without-building'] * 3)
        self.assertNotIn('-test-iterations', calls[1])
        self.assertIn('-test-iterations', calls[3])
        self.assertEqual(len(evidence['phases']), 4)
        self.assertEqual(reporter.extract.call_count, 3)
        self.assertEqual(evidence['metric_expectations'][0]['selector'], 'target/Suite/testCase')

    def test_malformed_metric_expectations_fail_before_build(self):
        for families in ('Hitch', None, [1], [''], ['  ']):
            config = {name: [dict(selector='target/Suite/testCase', suite_names=['Suite'])]
                      for name in ('acceptance', 'ui', 'performance')}
            config['performance'][0]['report_metric_families'] = families
            with self.subTest(families=families):
                status, calls, evidence, reporter = self.exercise(config_text=json.dumps(config))
                self.assertEqual(status, 1)
                self.assertEqual(calls, [])
                self.assertEqual(evidence['phases'][0]['name'], 'preflight')
                reporter.extract.assert_not_called()

    def test_compile_failure_never_runs_stale_products(self):
        status, calls, evidence, reporter = self.exercise(fail_at=1)
        self.assertEqual(status, 1)
        self.assertEqual(len(calls), 1)
        self.assertEqual([phase['status'] for phase in evidence['phases']],
                         ['failed', 'blocked', 'blocked', 'blocked'])
        reporter.extract.assert_not_called()

    def test_source_changes_block_candidate_evidence_and_remaining_phases(self):
        for phase in range(1, 5):
            with self.subTest(phase=phase):
                status, calls, evidence, reporter = self.exercise(source_change_after=phase)
                self.assertEqual(status, 1)
                self.assertEqual(len(calls), phase)
                self.assertEqual(evidence['phases'][phase - 1]['status'], 'failed')
                self.assertIn('Source changed', evidence['phases'][phase - 1]['detail'])
                self.assertTrue(all(item['status'] == 'blocked' for item in evidence['phases'][phase:]))

    def test_unreadable_source_identity_blocks_remaining_phases(self):
        for phase in range(1, 5):
            with self.subTest(phase=phase):
                status, calls, evidence, reporter = self.exercise(identity_failure_after=phase)
                self.assertEqual(status, 1)
                self.assertEqual(len(calls), phase)
                self.assertEqual(evidence['phases'][phase - 1]['status'], 'failed')
                self.assertTrue(all(item['status'] == 'blocked' for item in evidence['phases'][phase:]))

    def test_acceptance_failure_is_preserved_while_other_phases_collect_evidence(self):
        status, calls, evidence, reporter = self.exercise(fail_at=2)
        self.assertEqual(status, 1)
        self.assertEqual(len(calls), 4)
        self.assertEqual(evidence['phases'][1]['status'], 'failed')
        self.assertEqual(evidence['phases'][3]['status'], 'passed')
        self.assertEqual(reporter.extract.call_count, 2)


if __name__ == '__main__':
    unittest.main()
