#!/usr/bin/env python3
"""Cheap, bounded source checks; never a native build or runtime qualification."""

import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time


def load_build_tools():
    spec = importlib.util.spec_from_file_location(
        'local_ios_build', Path(__file__).with_name('local-ios-build.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'Duplicate policy key: {key}')
        result[key] = value
    return result


def repository_path(root, relative):
    path = Path(relative)
    if (path.is_absolute() or '..' in path.parts or not path.parts
            or path.as_posix() != relative):
        raise ValueError(f'Expected canonical repository-relative path: {relative}')
    result = root / path
    # Do not silently follow a policy/candidate redirect out of the checkout.
    result.resolve().relative_to(root.resolve())
    return result


def candidate_path(root, relative):
    result = repository_path(root, relative)
    if result.exists() and not result.is_file():
        raise ValueError(f'Candidate must be a file: {relative}')
    current = root
    for part in Path(relative).parts:
        # Also reject symlink aliases and case aliases on case-insensitive
        # volumes: domain coverage must see the same path that syntax sees.
        if current.is_dir() and (current / part).exists():
            if part not in {entry.name for entry in current.iterdir()}:
                raise ValueError(f'Noncanonical candidate spelling: {relative}')
        current = current / part
        if current.is_symlink():
            raise ValueError(f'Symlink candidate is unsupported: {relative}')
    return result


def load_policy(root):
    policy = json.loads((root / 'scripts/config/ios-source-size-policy.json').read_text(),
                        object_pairs_hook=unique_object)
    expected = {'version', 'productionRoot', 'globalCeiling', 'oversizedOwners',
                'sealedOwnerCeilings', 'directoryRules', 'fileRules', 'globalOnlyDirectories', 'globalOnlyFiles'}
    if set(policy) != expected or policy['version'] != 1:
        raise ValueError('Unsupported source-size policy shape/version')
    if policy['productionRoot'] != 'apps/ios/Merian':
        raise ValueError('Unexpected production source root')
    limits = [policy['globalCeiling'], *policy['sealedOwnerCeilings'].values()]
    for rule in [*policy['directoryRules'].values(), *policy['fileRules'].values()]:
        if set(rule) != {'counter', 'ceiling'} or rule['counter'] not in ('physical', 'segments'):
            raise ValueError('Unsupported line-count rule')
        limits.append(rule['ceiling'])
    if any(type(n) is not int or n <= 0 for n in limits):
        raise ValueError('Source ceilings must be positive integers')
    for group in ('oversizedOwners', 'globalOnlyDirectories', 'globalOnlyFiles'):
        if len(set(policy[group])) != len(policy[group]):
            raise ValueError(f'Duplicate policy entries: {group}')
    for path in [policy['productionRoot'], *policy['directoryRules'], *policy['fileRules'],
                 *policy['globalOnlyDirectories'], *policy['globalOnlyFiles'], *policy['oversizedOwners'],
                 *policy['sealedOwnerCeilings']]:
        repository_path(root, path)
    return policy


def count_lines(source, counter):
    # Swift splits Character values. CRLF is one Character, so its LF is NOT
    # the Character "\n". Do not use splitlines(), universal-newline reads or
    # count every LF byte. The host Swift parity fixtures lock this distinction.
    separators = sum(ch == '\n' and (i == 0 or source[i - 1] != '\r')
                     for i, ch in enumerate(source))
    segments = separators + 1
    if counter == 'segments':
        return segments
    if counter != 'physical':
        raise ValueError(f'Unsupported line counter: {counter}')
    if not source:
        return 0
    return segments - int(source.endswith('\n') and not source.endswith('\r\n'))


def within(path, directory):
    return path.startswith(directory + '/')


def size_failures(root, policy, candidates):
    failures = []
    production = policy['productionRoot']
    sources = {}
    # Inspect the complete global inventory: an allowed owner shrinking below
    # the threshold is also a policy change, not an automatic pass.
    for path in sorted((root / production).rglob('*.swift')):
        relative = path.relative_to(root).as_posix()
        repository_path(root, relative)
        sources[relative] = path.read_bytes().decode('utf-8')
    if not sources:
        raise ValueError('No production Swift sources found')
    oversized = {path[len(production) + 1:] for path, source in sources.items()
                 if count_lines(source, 'physical') > policy['globalCeiling']}
    expected = set(policy['oversizedOwners'])
    if oversized != expected:
        failures.append(f'Oversized inventory added={sorted(oversized - expected)} '
                        f'missing={sorted(expected - oversized)}')
    for relative, ceiling in policy['sealedOwnerCeilings'].items():
        path = production + '/' + relative
        if path not in sources:
            failures.append(f'Missing sealed owner: {path}')
        elif count_lines(sources[path], 'physical') > ceiling:
            failures.append(f'{path}: exceeds sealed ceiling {ceiling}')
    for directory in policy['directoryRules']:
        if not any(within(path, directory) for path in sources):
            failures.append(f'Empty or missing policy directory: {directory}')
    for path in policy['fileRules']:
        if path not in sources:
            failures.append(f'Missing bounded owner: {path}')
    for path in policy['globalOnlyFiles']:
        if path not in sources:
            failures.append(f'Missing global owner: {path}')
    for path, source in sources.items():
        rules = [rule for directory, rule in policy['directoryRules'].items()
                 if within(path, directory)]
        if path in policy['fileRules']:
            rules.append(policy['fileRules'][path])
        for rule in rules:
            count = count_lines(source, rule['counter'])
            if count > rule['ceiling']:
                failures.append(f"{path}: {count} {rule['counter']} > {rule['ceiling']}")
    for path in candidates:
        if path.endswith('.swift') and within(path, production):
            covered = path in policy['fileRules'] or path in policy['globalOnlyFiles'] or any(
                within(path, directory) for directory in
                [*policy['directoryRules'], *policy['globalOnlyDirectories']])
            if not covered:
                failures.append(f'Unsupported domain source-size policy: {path}; '
                                'run its owning architecture checks and extend shared coverage')
    return failures


def check_storage(root, before_build, build):
    build.check_space(root)
    free = shutil.disk_usage(root).free
    if before_build and free < 25 * build.GIB:
        raise RuntimeError('Before-build preflight requires at least 25 GiB free.')
    return free


def run(root, candidates, before_build, receipt):
    build = load_build_tools()

    def phase(name, action):
        started = time.monotonic()
        entry = {'phase': name, 'status': 'failed'}
        receipt['phases'].append(entry)
        try:
            action()
            entry['status'] = 'passed'
        finally:
            entry['seconds'] = round(time.monotonic() - started, 3)

    def command(args):
        subprocess.run(args, cwd=root, check=True)

    with build.Workspace(root).lock():
        phase('conflicting-build', build.ensure_no_xcodebuild)

        def sizes():
            failures = size_failures(root, load_policy(root), candidates)
            if failures:
                raise RuntimeError('\n'.join(failures))
        phase('source-size', sizes)
        phase('swift-syntax', lambda: [command(['xcrun', 'swiftc', '-frontend', '-parse', path])
                                      for path in candidates
                                      if path.endswith('.swift') and (root / path).is_file()])
        phase('source-membership', lambda: command(['bash', 'scripts/check-ios-project-source-membership.sh']))
        phase('project-resources', lambda: command(['make', 'validate-ios-project']))
        markdown = [p for p in candidates if p.endswith('.md') and (root / p).is_file()]
        if markdown:
            phase('markdown-format', lambda: command(['deno', 'fmt', '--check', *markdown]))
        phase('working-diff', lambda: command(['git', 'diff', '--check']))
        phase('staged-diff', lambda: command(['git', 'diff', '--cached', '--check']))
        # Recheck immediately before returning; this is still advisory. The
        # managed build must acquire its lock and check again at actual launch.
        phase('storage', lambda: receipt.update(
            freeBytes=check_storage(root, before_build, build)))
    receipt['passed'] = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before-build', action='store_true', help='also enforce the 25 GiB launch floor')
    parser.add_argument('--report', required=True, help='new receipt path under .artifacts/')
    parser.add_argument('paths', nargs='+', help='explicit candidate files, not unrelated working edits')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    receipt = {'passed': False, 'scope': 'bounded static preflight; no native/runtime qualification',
               'candidatePaths': args.paths, 'beforeBuild': args.before_build, 'phases': []}
    report = repository_path(root, args.report)
    if not within(args.report, '.artifacts') or report.exists():
        parser.error('Report must be a new path under .artifacts/')
    try:
        for path in args.paths:
            candidate_path(root, path)
            if not (root / path).exists():
                tracked = subprocess.run(['git', 'ls-files', '--error-unmatch', '--', path],
                                         cwd=root, capture_output=True)
                if tracked.returncode:
                    raise ValueError(f'Missing candidate file: {path}')
        run(root, args.paths, args.before_build, receipt)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        receipt['error'] = str(error)
        print(error, file=sys.stderr)
    finally:
        report.parent.mkdir(parents=True, exist_ok=True)
        with report.open('x') as output:
            json.dump(receipt, output, indent=2)
            output.write('\n')
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
