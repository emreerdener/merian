#!/usr/bin/env python3
"""Portable executable tests for runtime evidence and baseline reporting."""

import copy
import importlib.util
import json
import re
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('audit', ROOT / 'scripts/ios-runtime-audit.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class RuntimeAuditTests(unittest.TestCase):
    def summary(self):
        return dict(result='Passed', totalTestCount=1, passedTests=1, failedTests=0, skippedTests=0)

    def tree(self):
        return dict(nodeType='Test Suite', name='Example', result='Passed', children=[
            dict(nodeType='Test Case', name='testFlow()', result='Passed')])

    def selections(self):
        return [dict(selector='target/Example/testFlow', suite_names=['Example'])]

    def payload(self, values):
        return [dict(testIdentifier='Example/testFlow()', testRuns=[dict(
            device=dict(deviceName='iPhone'), testPlanConfiguration=dict(configurationName='Debug'),
            metrics=[dict(identifier='clock', displayName='Clock', unitOfMeasurement='s', measurements=values)])])]

    def evidence(self, values):
        return dict(environment={'runner': 'fixed'}, metrics=audit.summarize_metrics(self.payload(values)),
                    phases=[dict(name=name, status='passed') for name in ('build', 'acceptance', 'ui', 'performance')])

    def test_exact_case_is_required(self):
        audit.validate_execution(self.summary(), self.tree(), self.selections())
        wrong = self.tree()
        wrong['children'][0]['name'] = 'testUnrelated()'
        with self.assertRaises(ValueError):
            audit.validate_execution(self.summary(), wrong, self.selections())

    def test_empty_skipped_failed_and_missing_suite_fail_closed(self):
        for key, value in [('result', 'Failed'), ('totalTestCount', 0), ('skippedTests', 1),
                           ('failedTests', 1), ('passedTests', 0)]:
            summary = self.summary()
            summary[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                audit.validate_execution(summary, self.tree(), self.selections())
        for tree in ({}, dict(nodeType='Test Suite', name='Other', result='Passed'),
                     dict(nodeType='Test Suite', name='Example', result='Passed', children=[
                         dict(nodeType='Test Case', name='testFlow()', result='Skipped')])):
            with self.assertRaises(ValueError):
                audit.validate_execution(self.summary(), tree, self.selections())

    def test_repeated_samples_and_variance_are_preserved(self):
        payload = self.payload([1, 2, 3])
        payload[0]['testRuns'].append(copy.deepcopy(payload[0]['testRuns'][0]))
        metric = next(iter(audit.summarize_metrics(payload).values()))
        self.assertEqual(metric['samples'], [1, 2, 3, 1, 2, 3])
        self.assertEqual(metric['mean'], 2)
        self.assertEqual(metric['count'], 6)
        self.assertGreater(metric['stdev'], 0)

    def test_device_and_configuration_samples_are_not_pooled(self):
        payload = self.payload([1])
        other = copy.deepcopy(payload[0]['testRuns'][0])
        other['device']['deviceName'] = 'iPad'
        payload[0]['testRuns'].append(other)
        self.assertEqual(len(audit.summarize_metrics(payload)), 2)

    def test_missing_nonfinite_and_boolean_measurements_are_rejected(self):
        for values in ([], [float('nan')], [float('inf')], [True], ['12']):
            with self.subTest(values=values), self.assertRaises(ValueError):
                audit.summarize_metrics(self.payload(values))
        with self.assertRaises(ValueError):
            audit.summarize_metrics([])
        # Physical-memory deltas may be negative after temporary allocations drain.
        audit.summarize_metrics(self.payload([-1, 0, 1]))

    def test_comparison_requires_same_environment_and_sufficient_samples(self):
        baseline = self.evidence([1] * 30)
        candidate = self.evidence([2] * 10)
        self.assertIn('INSUFFICIENT', audit.compare(candidate, baseline)[0])
        candidate['environment'] = {'runner': 'different'}
        with self.assertRaises(ValueError):
            audit.compare(candidate, baseline)

    def test_regressions_are_report_only_and_noise_is_not_hidden(self):
        baseline = self.evidence([1] * 30)
        candidate = self.evidence([1.5] * 30)
        self.assertIn('REVIEW increase', audit.compare(candidate, baseline)[0])
        self.assertEqual(audit.compare(self.evidence([1.1] * 30), baseline), [])
        noisy = audit.compare(self.evidence([0, 3] * 15), baseline)
        self.assertTrue(any('HIGH VARIANCE' in item for item in noisy))

    def test_missing_baseline_metric_is_visible(self):
        baseline = self.evidence([1] * 30)
        candidate = self.evidence([1] * 30)
        candidate['metrics'] = {}
        self.assertIn('MISSING', audit.compare(candidate, baseline)[0])

    def test_report_retains_failure_and_no_invented_baseline(self):
        evidence = self.evidence([1, 2, 3])
        evidence.update(source_sha='fixture', phases=[dict(name='acceptance', status='failed', detail='fixture failure')])
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            audit.write_report(output, evidence)
            self.assertIn('acceptance: failed', (output / 'summary.md').read_text())
            self.assertIn('baseline pending', (output / 'summary.md').read_text())
            self.assertEqual(json.loads((output / 'audit.json').read_text())['source_sha'], 'fixture')

    def test_malformed_baseline_and_inconsistent_statistics_are_rejected(self):
        for baseline in ({}, {'environment': {}, 'metrics': {}},
                         {'environment': {}, 'metrics': {'clock': {}}}):
            with self.assertRaises(ValueError):
                audit.validate_baseline(baseline)
        baseline = self.evidence([1] * 30)
        audit.validate_baseline(baseline)
        next(iter(baseline['metrics'].values()))['mean'] = 2
        with self.assertRaises(ValueError):
            audit.validate_baseline(baseline)

    def test_duplicate_suite_is_rejected(self):
        with self.assertRaises(ValueError):
            audit.validate_execution(self.summary(), [self.tree(), self.tree()], self.selections())

    def test_foundation_acceptance_requires_all_three_suites(self):
        config = json.loads((ROOT / 'scripts/config/ios-runtime-audit.json').read_text())
        selections = {item['selector']: item for item in config['acceptance']}
        for suite, display in [
                ('AppleFoundationVisualCueProviderTests', 'Apple Foundation Visual Cue Mapping'),
                ('LocalVisualAnalysisTests', 'Local Visual Analysis Tests'),
                ('FeatureFlagsTests', 'Feature Flag Tests')]:
            with self.subTest(suite=suite):
                selection = selections['merianTests/' + suite]
                self.assertIn(display, selection['suite_names'])
                tree = self.tree()
                tree['name'] = display
                audit.validate_execution(self.summary(), tree, [selection])
                tree['children'][0]['result'] = 'Skipped'
                with self.assertRaises(ValueError):
                    audit.validate_execution(self.summary(), tree, [selection])

    def test_manifest_selectors_have_source_owners_and_no_duplicates(self):
        config = json.loads((ROOT / 'scripts/config/ios-runtime-audit.json').read_text())
        for phase, selections in config.items():
            selectors = [item['selector'] for item in selections]
            self.assertEqual(len(selectors), len(set(selectors)), phase)
            for item in selections:
                target, suite, *case = item['selector'].split('/')
                directory = {'merianTests': 'MerianTests', 'merianUITests': 'MerianUITests',
                             'merianPerformanceTests': 'MerianPerformanceTests'}[target]
                files = [ROOT / item['owner']] if 'owner' in item else list((ROOT / 'apps/ios' / directory).rglob(suite + '.swift'))
                self.assertEqual(len(files), 1, item['selector'])
                source = files[0].read_text()
                self.assertRegex(source, rf'\b(?:class|struct|extension)\s+{re.escape(suite)}\b', item['selector'])
                if case:
                    self.assertIn('func ' + case[0] + '(', source)


if __name__ == '__main__':
    unittest.main()
