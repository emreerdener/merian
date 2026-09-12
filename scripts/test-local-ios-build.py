#!/usr/bin/env python3
"""Exercise local build retention and cleanup against disposable fixtures."""

import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

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


if __name__ == '__main__':
    unittest.main()
