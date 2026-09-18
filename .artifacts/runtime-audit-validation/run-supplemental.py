#!/usr/bin/env python3
"""Retained local evidence driver; uses the repository's managed build wrapper."""
import importlib.util
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE / 'candidate'


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def main():
    phase = sys.argv[1]
    audit_path = Path(sys.argv[2]) if len(sys.argv) > 2 else (
        ROOT / '.artifacts/local-ios/audit-1577a4d430564ef99ca0c42893659185/audit.json'
    )
    baseline = json.loads(audit_path.read_text())
    reporter = module('reporter', 'ios-runtime-audit.py')
    reporter.validate_baseline(baseline)
    wrapper = module('wrapper', 'local-ios-build.py')
    workspace = wrapper.Workspace(ROOT)
    identity = workspace.audit_source_identity()
    assert all(baseline[key] == value for key, value in identity.items()), 'Candidate differs from reviewed audit'
    environment = workspace.audit_environment(baseline['destination'], baseline['environment']['label'])
    assert environment == baseline['environment'], 'Environment differs from first run'
    config = json.loads((ROOT / 'scripts/config/ios-runtime-audit.json').read_text())
    args = ['simulator', '--', 'test-without-building', '-configuration', 'Debug', '-destination',
            baseline['destination'], '-parallel-testing-enabled', 'NO']
    if phase == 'unit':
        args += ['-only-testing:merianTests']
    elif phase == 'performance':
        args += ['-test-iterations', '3'] + ['-only-testing:' + item['selector'] for item in config['performance']]
    else:
        raise ValueError(phase)
    output = HERE / ('complete-unit' if phase == 'unit' else 'repeat-performance')
    output.mkdir(exist_ok=True)
    evidence = dict(**identity, environment=environment, command=['make', 'ios-local-build', 'ARGS=' + shlex.join(args)])
    (output / 'execution.json').write_text(json.dumps(evidence, indent=2) + '\n')
    log = output / 'execution.log'
    with log.open('w') as stream:
        status = subprocess.run(evidence['command'], cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT).returncode
    evidence['exit_code'] = status
    evidence['source_identity_after'] = workspace.audit_source_identity()
    evidence['environment_after'] = workspace.audit_environment(baseline['destination'], environment['label'])
    evidence['source_unchanged'] = evidence['source_identity_after'] == identity
    evidence['environment_unchanged'] = evidence['environment_after'] == environment
    matches = re.findall(r'^Result bundle: (.+)$', log.read_text(), re.MULTILINE)
    assert len(matches) == 1, matches
    bundle = Path(matches[0])
    evidence['bundle'] = str(bundle)
    (output / 'execution.json').write_text(json.dumps(evidence, indent=2) + '\n')
    assert status == 0 and evidence['source_unchanged'] and evidence['environment_unchanged'], evidence
    metrics = reporter.extract(bundle, output, config['performance'] if phase == 'performance' else [], phase == 'performance')
    if phase == 'performance':
        evidence['metrics'] = metrics
        evidence['phases'] = [dict(name='performance-repeat', status='passed')]
        reporter.write_report(output, evidence, baseline)
        deltas = {}
        for key, metric in metrics.items():
            previous = baseline['metrics'][key]
            delta = metric['mean'] - previous['mean']
            deltas[key] = dict(first_mean=previous['mean'], repeat_mean=metric['mean'],
                               absolute_delta=delta,
                               percent_delta=100 * delta / abs(previous['mean']) if previous['mean'] else None,
                               first_cv_percent=previous['cv_percent'], repeat_cv_percent=metric['cv_percent'],
                               first_count=previous['count'], repeat_count=metric['count'])
        (output / 'inter-run-deltas.json').write_text(json.dumps(deltas, indent=2) + '\n')
    print(str(output), flush=True)


if __name__ == '__main__':
    main()
