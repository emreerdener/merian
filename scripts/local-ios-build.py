#!/usr/bin/env python3
"""Bound local validation caches without touching archives or legacy artifacts."""

import argparse
import importlib.util
import json
import platform as host_platform
from contextlib import contextmanager
import fcntl
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import uuid

GIB = 1024 ** 3
OWNED_FLAGS = {
    '-derivedDataPath', '-clonedSourcePackagesDirPath', '-packageCachePath',
    '-resultBundlePath', '-project', '-workspace', '-archivePath', '-exportPath',
    '-exportArchive', '-exportOptionsPlist', '-allowProvisioningUpdates',
    '-allowProvisioningDeviceRegistration',
}
OWNED_SETTINGS = {
    'SYMROOT', 'OBJROOT', 'DSTROOT', 'CONFIGURATION_BUILD_DIR',
    'CONFIGURATION_TEMP_DIR', 'BUILD_DIR', 'BUILD_ROOT', 'PROJECT_TEMP_DIR',
    'SHARED_PRECOMPS_DIR', 'CLANG_MODULE_CACHE_PATH', 'SWIFT_MODULE_CACHE_PATH',
    'CODE_SIGNING_ALLOWED',
}
ACTIONS = {'build', 'build-for-testing', 'test', 'test-without-building'}


def check_space(root):
    free = shutil.disk_usage(root).free / GIB
    print(f'Available disk space: {free:.1f} GiB', flush=True)
    if free < 20:
        raise RuntimeError('Less than 20 GiB free; reclaim space before building.')
    if free < 50:
        print('Warning: less than 50 GiB free. Review local build caches.', file=sys.stderr)


def validate_args(args):
    if not args or args[0] not in ACTIONS:
        raise RuntimeError('Start with build, build-for-testing, test, or test-without-building.')
    for arg in args:
        key = arg.split('=', 1)[0]
        if key in OWNED_FLAGS or key in OWNED_SETTINGS or arg == 'archive':
            raise RuntimeError(f'The local validation wrapper does not accept {key}.')


def ensure_no_xcodebuild():
    # Never infer inactivity when process inspection is denied by the host.
    result = subprocess.run(['pgrep', '-x', 'xcodebuild'], capture_output=True)
    if result.returncode == 0:
        raise RuntimeError('An xcodebuild process is active; stop builds and quit Xcode first.')
    if result.returncode != 1:
        raise RuntimeError('Cannot verify whether xcodebuild is active; operation refused.')


def run_child(command, root):
    child = subprocess.Popen(command, cwd=root, start_new_session=True)
    try:
        return child.wait()
    except BaseException:
        # Drain the process group before releasing the cache lock or removing scratch data.
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            child.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
        # xcodebuild can exit before its compiler descendants finish handling SIGTERM.
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        raise


class Workspace:
    def __init__(self, root):
        self.root = root.resolve()
        self.build = self.root / '.build'
        self.cache = self.build / 'local-ios'
        self.reports = self.root / '.artifacts' / 'local-ios'

    def checked(self, path):
        # No managed ancestor may redirect cleanup or writes outside this checkout.
        current = self.root
        for part in path.relative_to(self.root).parts:
            current = current / part
            if current.is_symlink():
                raise RuntimeError(f'Refusing symlink in managed path: {current}')
        return path

    @contextmanager
    def lock(self):
        self.checked(self.build).mkdir(exist_ok=True)
        lock_path = self.checked(self.build / '.local-ios.lock')
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError('Another local build or cleanup owns this checkout cache.') from None
            yield fd
        finally:
            os.close(fd)

    def run(self, platform, isolated, args):
        validate_args(args)
        with self.lock():
            return self.run_locked(platform, isolated, args)

    def run_locked(self, platform, isolated, args):
        check_space(self.root)
        ensure_no_xcodebuild()
        for path in (self.cache, self.reports):
            self.checked(path).mkdir(parents=True, exist_ok=True)
        for name in ('packages', 'package-cache'):
            self.checked(self.cache / name).mkdir(exist_ok=True)
        scratch = None
        if isolated:
            parent = self.checked(self.cache / 'temporary')
            parent.mkdir(exist_ok=True)
            scratch = Path(tempfile.mkdtemp(prefix=f'{platform}-', dir=parent))
        derived = scratch or self.checked(self.cache / platform)
        report = self.reports / f'{uuid.uuid4().hex}.xcresult'
        self.last_report = report
        command = [
            'xcodebuild', '-project', str(self.root / 'Merian.xcodeproj'),
            '-scheme', 'Merian', '-sdk', 'iphonesimulator' if platform == 'simulator' else 'iphoneos',
            '-derivedDataPath', str(derived),
            '-clonedSourcePackagesDirPath', str(self.cache / 'packages'),
            '-packageCachePath', str(self.cache / 'package-cache'),
            '-disablePackageRepositoryCache',
            '-onlyUsePackageVersionsFromResolvedFile', '-disableAutomaticPackageResolution',
            '-resultBundlePath', str(report),
            *args, 'CODE_SIGNING_ALLOWED=NO',
        ]
        print(f'Build cache: {derived}\nResult bundle: {report}', flush=True)
        try:
            return run_child(command, self.root)
        finally:
            if scratch is not None:
                shutil.rmtree(self.checked(scratch))

    def resolve_audit_packages(self):
        check_space(self.root)
        ensure_no_xcodebuild()
        for name in ('packages', 'package-cache'):
            self.checked(self.cache / name).mkdir(parents=True, exist_ok=True)
        lockfile = self.root / 'Merian.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        locked = lockfile.read_bytes()
        if not json.loads(locked).get('pins'):
            raise RuntimeError('A populated Package.resolved is required.')
        status = run_child([
            'xcodebuild', '-resolvePackageDependencies', '-project', str(self.root / 'Merian.xcodeproj'),
            '-scheme', 'Merian', '-clonedSourcePackagesDirPath', str(self.cache / 'packages'),
            '-packageCachePath', str(self.cache / 'package-cache'), '-disablePackageRepositoryCache',
            '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates',
        ], self.root)
        if status or lockfile.read_bytes() != locked:
            raise RuntimeError('Locked package resolution failed or changed Package.resolved.')

    def audit_environment(self, destination, label):
        devices = json.loads(subprocess.check_output(
            ['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], text=True))['devices']
        device_id = next((part[3:] for part in destination.split(',') if part.startswith('id=')), None)
        for runtime, candidates in devices.items():
            for device in candidates:
                if device['udid'] == device_id and device.get('isAvailable'):
                    return dict(label=label, simulator_model=device['name'], runtime=runtime,
                                xcode=subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
                                host=host_platform.platform(),
                                hardware=subprocess.check_output(['sysctl', '-n', 'hw.model'], text=True).strip(),
                                configuration='Debug', iterations=3)
        raise RuntimeError('Audit requires an available concrete Simulator id destination.')

    def audit(self, destination, environment_label, baseline_path=None):
        # Hold the existing cache lock across compilation AND all test phases.
        # This prevents another build replacing the products under test.
        baseline = None
        with self.lock():
            output = self.checked(self.reports / f'audit-{uuid.uuid4().hex}')
            output.mkdir(parents=True)
            evidence = dict(source_sha='unavailable', environment={}, phases=[], metrics={})
            failed = False
            reporter = None
            try:
                spec = importlib.util.spec_from_file_location(
                    'ios_runtime_audit', self.root / 'scripts/ios-runtime-audit.py')
                loaded_reporter = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(loaded_reporter)
                reporter = loaded_reporter
                config = json.loads((self.root / 'scripts/config/ios-runtime-audit.json').read_text())
                for name in ('acceptance', 'ui', 'performance'):
                    selections = config.get(name) if isinstance(config, dict) else None
                    if not isinstance(selections, list) or not selections or any(
                            not isinstance(item, dict) or not isinstance(item.get('selector'), str)
                            or not item['selector'] or not isinstance(item.get('suite_names'), list)
                            or not item['suite_names'] for item in selections):
                        raise ValueError(f'Invalid runtime audit selector group: {name}')
                def read(command):
                    return subprocess.check_output(command, cwd=self.root, text=True).strip()
                evidence['source_sha'] = read(['git', 'rev-parse', 'HEAD'])
                evidence['source_fingerprint'] = read(['bash', 'scripts/ios-release-source-fingerprint.sh'])
                evidence['source_dirty'] = bool(read(['git', 'status', '--porcelain']))
                evidence['destination'] = destination
                evidence['environment'] = self.audit_environment(destination, environment_label)
                if baseline_path:
                    baseline = json.loads(baseline_path.read_text())
                    reporter.validate_baseline(baseline)
                self.resolve_audit_packages()
                phases = [('build', ['build-for-testing', '-configuration', 'Debug',
                                     '-destination', 'generic/platform=iOS Simulator'])]
                for name in ('acceptance', 'ui', 'performance'):
                    selectors = ['-only-testing:' + item['selector'] for item in config[name]]
                    phases.append((name, ['test-without-building', '-configuration', 'Debug',
                                          '-destination', destination, '-parallel-testing-enabled', 'NO',
                                          *(['-test-iterations', '3'] if name == 'performance' else []),
                                          *selectors]))
                for name, args in phases:
                    phase = dict(name=name, status='failed', command=args)
                    evidence['phases'].append(phase)
                    try:
                        status = self.run_locked('simulator', False, args)
                        phase['bundle'] = str(self.last_report)
                        if status:
                            if name != 'build' and self.last_report.exists():
                                reporter.extract(self.last_report, output / name, config[name])
                            raise RuntimeError(f'xcodebuild exited {status}; inspect {self.last_report}')
                        if name != 'build':
                            metrics = reporter.extract(self.last_report, output / name,
                                                       config[name], name == 'performance')
                            evidence['metrics'].update(metrics)
                        phase['status'] = 'passed'
                    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
                        failed = True
                        phase['detail'] = str(error)
                        if name == 'build':
                            for blocked in ('acceptance', 'ui', 'performance'):
                                evidence['phases'].append(dict(name=blocked, status='blocked',
                                                              detail='Current-source build failed.'))
                            break
            except (OSError, RuntimeError, ValueError, ImportError, SyntaxError, subprocess.SubprocessError) as error:
                failed = True
                evidence['phases'].append(dict(name='preflight', status='failed', detail=str(error)))
                baseline = None
                for blocked in ('build', 'acceptance', 'ui', 'performance'):
                    evidence['phases'].append(dict(name=blocked, status='blocked', detail='Preflight failed.'))
            finally:
                try:
                    if reporter is None:
                        (output / 'audit.json').write_text(json.dumps(evidence, indent=2) + '\n')
                        (output / 'summary.md').write_text('# iOS runtime audit\n\nReporter preflight failed; see audit.json.\n')
                    else:
                        reporter.write_report(output, evidence, baseline)
                except ValueError as error:
                    failed = True
                    evidence['phases'].append(dict(name='baseline', status='failed', detail=str(error)))
                    reporter.write_report(output, evidence)
                print(f'Runtime audit summary: {output / "summary.md"}', flush=True)
            return 1 if failed else 0

    def clean(self, apply):
        with self.lock():
            self.checked(self.cache)
            targets = [self.checked(self.cache / name) for name in ('simulator', 'device', 'temporary')]
            targets = [path for path in targets if path.exists()]
            for path in targets:
                print(f'{"Remove" if apply else "Would remove"}: {path}')
            if apply:
                ensure_no_xcodebuild()
                for path in targets:
                    shutil.rmtree(self.checked(path))
            elif targets:
                print('Preview only. Use clean --apply after stopping builds and quitting Xcode.')
            else:
                print('No managed build outputs to remove.')
            print('Preserved: dependencies, .artifacts, archives, and all legacy .build folders.')

    def report(self):
        free = shutil.disk_usage(self.root).free / GIB
        print(f'Available disk space: {free:.1f} GiB')
        for path in (self.build, self.reports):
            self.checked(path)
            if not path.exists():
                continue
            result = subprocess.run(['du', '-k', '-d', '1', str(path)], capture_output=True, text=True)
            if result.returncode:
                raise RuntimeError(f'Could not completely measure {path}.')
            rows = [line.split('\t', 1) for line in result.stdout.splitlines()]
            for size, name in sorted(rows, key=lambda row: int(row[0]), reverse=True)[:16]:
                print(f'{int(size) / 1024 ** 2:7.2f} GiB  {name}')
        print('Report only. Legacy folders and historical result bundles require individual review.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    run = commands.add_parser('run', help='Run an unsigned local Xcode validation action')
    run.add_argument('platform', choices=['simulator', 'device'])
    run.add_argument('--isolated', action='store_true')
    run.add_argument('xcode_args', nargs=argparse.REMAINDER)
    audit = commands.add_parser('audit', help='Build once, run acceptance and separate measurements')
    audit.add_argument('--destination', required=True)
    audit.add_argument('--environment-label', required=True, help='Runner hardware, simulator model and runtime')
    audit.add_argument('--baseline', type=Path)
    clean = commands.add_parser('clean', help='Preview removal of managed build outputs')
    clean.add_argument('--apply', action='store_true')
    commands.add_parser('report', help='Show free space and the largest build/report folders')
    args = parser.parse_args()
    workspace = Workspace(Path(__file__).resolve().parents[1])
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    try:
        if args.command == 'run':
            xcode_args = args.xcode_args
            if xcode_args[:1] == ['--']:
                xcode_args = xcode_args[1:]
            return workspace.run(args.platform, args.isolated, xcode_args)
        if args.command == 'audit':
            return workspace.audit(args.destination, args.environment_label, args.baseline)
        if args.command == 'clean':
            workspace.clean(args.apply)
        else:
            workspace.report()
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print('Operation interrupted. Inspect storage and rerun cleanup if needed.', file=sys.stderr)
        return 130


if __name__ == '__main__':
    sys.exit(main())
