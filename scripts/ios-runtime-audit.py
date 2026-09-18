#!/usr/bin/env python3
"""XCResult acceptance validation and report-only performance comparison."""

import argparse
import json
import math
from pathlib import Path
import statistics
import subprocess


def nodes(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from nodes(child)


def validate_execution(summary, tree, selections):
    count = summary.get('totalTestCount', 0)
    if (summary.get('result') != 'Passed' or not isinstance(count, int) or count < 1
            or summary.get('passedTests') != count or summary.get('failedTests') != 0
            or summary.get('skippedTests') != 0):
        failures = ', '.join(str(item.get('testName', 'unknown case')) for item in summary.get('testFailures', []))
        raise ValueError('Expected a nonempty, completely passed, unskipped test run. Failed: ' + (failures or 'see XCResult'))
    suites = [node for node in nodes(tree) if node.get('nodeType') == 'Test Suite']
    cases = [node for node in nodes(tree) if node.get('nodeType') == 'Test Case']
    if not cases or any(case.get('result') != 'Passed' for case in cases):
        raise ValueError('Missing or unsuccessful test cases in XCResult tree.')
    for selection in selections:
        parts = selection['selector'].split('/')
        matches = [suite for suite in suites if suite.get('name') in selection['suite_names']]
        owned = [case for suite in matches for case in nodes(suite)
                 if case.get('nodeType') == 'Test Case']
        if len(matches) != 1 or not owned or any(suite.get('result') != 'Passed' for suite in matches):
            raise ValueError(f'Missing passed suite: {parts[1]}')
        if len(parts) == 3 and not any(
                case.get('name', '').removesuffix('()') == parts[2] for case in owned):
            raise ValueError(f'Missing required case: {selection["selector"]}')


def summarize_metrics(payload):
    if not isinstance(payload, list):
        raise ValueError('Expected xcresulttool metrics array.')
    samples = {}
    for test in payload:
        for run in test['testRuns']:
            for metric in run['metrics']:
                key = ' | '.join((test['testIdentifier'], run['device']['deviceName'],
                                  run['testPlanConfiguration']['configurationName'],
                                  metric.get('identifier', metric['displayName']),
                                  metric['unitOfMeasurement']))
                values = metric['measurements']
                if not values or any(isinstance(value, bool) or not isinstance(value, (int, float))
                                     or not math.isfinite(value) for value in values):
                    raise ValueError(f'Invalid measurements: {key}')
                samples.setdefault(key, []).extend(values)
    if not samples:
        raise ValueError('Performance run produced no measurements.')
    result = {}
    for key, values in sorted(samples.items()):
        mean = statistics.mean(values)
        deviation = statistics.stdev(values) if len(values) > 1 else 0
        result[key] = dict(samples=values, count=len(values), mean=mean,
                           median=statistics.median(values), stdev=deviation,
                           cv_percent=coefficient_of_variation(mean, deviation),
                           minimum=min(values), maximum=max(values))
    return result


def coefficient_of_variation(mean, deviation):
    # Zero-mean signed deltas (including all-zero samples) have no defined CV.
    return 100 * deviation / abs(mean) if mean else None


def variance_observations(metrics):
    observations = []
    for key, metric in metrics.items():
        # Recompute so historical reports with a numeric zero placeholder remain readable.
        cv = coefficient_of_variation(metric['mean'], metric['stdev'])
        if cv is None:
            observations.append(f'UNDEFINED CV (zero mean; inspect raw samples and SD): {key}')
        elif cv > 15:
            observations.append(f'HIGH VARIANCE {cv:.1f}%: {key}')
    return observations


def metric_coverage_observations(metrics, expectations):
    observations = []
    for selection in expectations:
        expected_test = '/'.join(selection['selector'].split('/')[1:])
        identifiers = [key.split(' | ')[3].lower() for key in metrics
                       if key.split(' | ')[0].removesuffix('()').split('/')[-2:]
                       == expected_test.split('/')[-2:]]
        for family in selection.get('report_metric_families', []):
            if not any(family.lower() in identifier for identifier in identifiers):
                observations.append(f'UNMEASURED {family}: {expected_test}; no exported samples, not qualified.')
    return observations


def validate_baseline(baseline):
    if not isinstance(baseline, dict) or not isinstance(baseline.get('environment'), dict) \
            or not isinstance(baseline.get('metrics'), dict) or not baseline['metrics']:
        raise ValueError('Baseline must contain environment and nonempty metrics objects.')
    phases = baseline.get('phases', [])
    if not isinstance(phases, list) or len(phases) != 4 or {phase.get('name') for phase in phases if isinstance(phase, dict)
                                      and phase.get('status') == 'passed'} != {'build', 'acceptance', 'ui', 'performance'}:
        raise ValueError('Baseline must come from a successful complete audit.')
    for key, metric in baseline['metrics'].items():
        if not isinstance(metric, dict) or not isinstance(metric.get('samples'), list) or len(metric['samples']) < 30:
            raise ValueError(f'Baseline requires at least 30 raw samples: {key}')
        values = metric['samples']
        if any(isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value)
               for value in values):
            raise ValueError(f'Invalid baseline samples: {key}')
        # Never trust hand-edited summaries over the retained raw measurements.
        if metric.get('count') != len(values) or metric.get('mean') != statistics.mean(values) \
                or metric.get('stdev') != statistics.stdev(values):
            raise ValueError(f'Baseline statistics disagree with raw samples: {key}')


def compare(current, baseline):
    if current['environment'] != baseline['environment']:
        raise ValueError('Baseline environment differs; collect a separate baseline.')
    observations = []
    for key, measured in current['metrics'].items():
        previous = baseline['metrics'].get(key)
        if previous is None:
            observations.append(f'NEW metric: {key}')
            continue
        if min(measured['count'], previous['count']) < 30:
            observations.append(f'INSUFFICIENT samples (need 30 per candidate): {key}')
            continue
        delta = measured['mean'] - previous['mean']
        noise = 3 * math.sqrt(measured['stdev'] ** 2 / measured['count']
                              + previous['stdev'] ** 2 / previous['count'])
        if delta > max(abs(previous['mean']) * 0.20, noise):
            observations.append(f'REVIEW increase {delta:.6g} ({key}); report-only')
    for missing in baseline['metrics'].keys() - current['metrics'].keys():
        observations.append(f'MISSING baseline metric: {missing}')
    return observations + variance_observations(current['metrics'])


def extract(bundle, output, selections, performance=False):
    output.mkdir(parents=True, exist_ok=True)
    results = {}
    for kind in ('summary', 'tests', 'metrics') if performance else ('summary', 'tests'):
        command = ['xcrun', 'xcresulttool', 'get', 'test-results', kind, '--path', str(bundle)]
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        (output / f'{kind}.json').write_text(result.stdout)
        results[kind] = json.loads(result.stdout)
    validate_execution(results['summary'], results['tests'], selections)
    if performance:
        metrics = summarize_metrics(results['metrics'])
        for selection in selections:
            # XCTest's identifier excludes the bundle target; accept an optional target prefix.
            expected = '/'.join(selection['selector'].split('/')[1:])
            if not any(key.split(' | ')[0].removesuffix('()').endswith(expected)
                       for key in metrics):
                raise ValueError(f'No metrics for {expected}')
        return metrics
    return {}


def write_report(output, evidence, baseline=None):
    if baseline is not None:
        validate_baseline(baseline)
    observations = (compare(evidence, baseline) if baseline is not None else
                    ['No baseline supplied; baseline pending.'] + variance_observations(evidence['metrics']))
    observations += metric_coverage_observations(evidence['metrics'], evidence.get('metric_expectations', []))
    for metric in evidence['metrics'].values():
        metric['cv_percent'] = coefficient_of_variation(metric['mean'], metric['stdev'])
    evidence['observations'] = observations
    (output / 'audit.json').write_text(json.dumps(evidence, indent=2) + '\n')
    lines = ['# iOS runtime audit', '', f'Source commit: `{evidence["source_sha"]}`',
             f'Working tree dirty: `{evidence.get("source_dirty", "unknown")}`',
             f'Source fingerprint: `{evidence.get("source_fingerprint", "unavailable")}`', '',
             'Hardware-dependent measurements are report-only. Behavioral failures fail the run.', '']
    for phase in evidence['phases']:
        lines.append(f'- {phase["name"]}: {phase["status"]}; {phase.get("detail", "")}')
    lines += ['', '## Measurements', '', '| Metric | n | Mean | SD | CV % | Min | Max |',
              '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for key, metric in evidence['metrics'].items():
        label = key.replace('|', '/')
        cv = 'undefined' if metric['cv_percent'] is None else f'{metric["cv_percent"]:.2f}'
        lines.append(f'| {label} | {metric["count"]} | {metric["mean"]:.6g} | '
                     f'{metric["stdev"]:.6g} | {cv} | '
                     f'{metric["minimum"]:.6g} | {metric["maximum"]:.6g} |')
    lines += ['', '## Baseline comparison', '', *[f'- {item}' for item in observations], '']
    (output / 'summary.md').write_text('\n'.join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--phase', choices=['acceptance', 'ui', 'performance'], required=True)
    args = parser.parse_args()
    config = json.loads((Path(__file__).parent / 'config/ios-runtime-audit.json').read_text())
    extract(args.bundle, args.output, config[args.phase], args.phase == 'performance')


if __name__ == '__main__':
    main()
