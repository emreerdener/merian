#!/usr/bin/env python3
"""Positive and adversarial successor evidence contracts; no native invocation."""
import copy
import hashlib
import io
import json
import zipfile
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock

spec = importlib.util.spec_from_file_location('followups', Path(__file__).with_name('ios-consolidation-followups.py'))
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)


def fixture(parameterized=False, failed=False):
    name = 'merianTests/Example/check(value:)' if parameterized else 'merianTests/Example/check'
    url = 'test://com.apple.xcode/Merian/' + name
    result = 'Failed' if failed else 'Passed'
    node = {'nodeType': 'Test Case', 'nodeIdentifierURL': url, 'result': result}
    if parameterized:
        node['children'] = [{'nodeType': 'Arguments', 'nodeIdentifierURL': url + '?args=' + i, 'result': result} for i in ('01', '02')]
    device = {'deviceId': 'ABC', 'osVersion': '26.5', 'osBuildNumber': '23F77', 'architecture': 'arm64', 'platform': 'iOS Simulator'}
    total = 2 if parameterized else 1
    summary = dict(totalTestCount=1, passedTests=0 if failed else 1, failedTests=int(failed), skippedTests=0,
                   expectedFailures=0, result=result, devicesAndConfigurations=[dict(device=device, passedTests=0 if failed else total,
                   failedTests=total if failed else 0, skippedTests=0, expectedFailures=0)])
    return summary, {'devices': [device], 'testNodes': [node]}, [name]


class FollowupTests(unittest.TestCase):
    def test_swift_testing_empty_parentheses_are_exact_alias(self):
        summary, tree, selectors = fixture()
        result = f.inventory(summary, tree, [selectors[0] + '()'])
        self.assertEqual(result['methods'], {selectors[0]: 'Passed'})
        with self.assertRaises(ValueError):
            f.inventory(summary, tree, [selectors[0], selectors[0] + '()'])
        with self.assertRaises(ValueError):
            f.inventory(summary, tree, [selectors[0] + '(other:)'])

    def test_per_run_evidence_root_is_canonical_same_repository(self):
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp).resolve()
            root = parent / '.artifacts'
            root.mkdir()
            with patch.object(f.subprocess, 'check_output', return_value='/repository/.git\n'):
                self.assertEqual(f.evidence_root(str(root)), root)
                link = parent / 'linked'
                link.symlink_to(root, target_is_directory=True)
                for bad in (str(link), str(parent), '.artifacts', str(root / 'missing')):
                    with self.subTest(path=bad), self.assertRaises(ValueError):
                        f.evidence_root(bad)
            with patch.object(f.subprocess, 'check_output', side_effect=['/foreign/.git\n', '/repository/.git\n']):
                with self.assertRaises(ValueError):
                    f.evidence_root(str(root))

    def test_exact_ordinary_and_parameter_methods(self):
        for parameterized in (False, True):
            summary, tree, selectors = fixture(parameterized)
            result = f.inventory(summary, tree, selectors)
            self.assertEqual(result['expanded_cases'], 2 if parameterized else 1)

    def test_failed_original_is_retained(self):
        s, t, selectors = fixture(failed=True)
        self.assertEqual(f.inventory(s, t, selectors)['methods'][selectors[0]], 'Failed')

    def test_skipped_incomplete_expected_failure_and_wrong_counts(self):
        s, t, selectors = fixture(True)
        for key, value in [('skippedTests', 1), ('passedTests', 0), ('totalTestCount', 2), ('expectedFailures', 1), ('result', 'Failed'), ('passedTests', True)]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                f.inventory({**s, key: value}, t, selectors)
        for value in ('Skipped', 'Expected Failure', 'Not Run'):
            bad = copy.deepcopy(t); bad['testNodes'][0]['result'] = value
            with self.subTest(value=value), self.assertRaises(ValueError): f.inventory(s, bad, selectors)

    def test_parameter_coverage_loss_duplicate_and_failure(self):
        s, t, selectors = fixture(True)
        for operation in ('missing', 'duplicate', 'failed', 'skipped', 'foreign', 'invalid'):
            bad = copy.deepcopy(t); node = bad['testNodes'][0]; children = node['children']
            if operation == 'missing': children.pop()
            if operation == 'duplicate': children.append(copy.deepcopy(children[0]))
            if operation == 'failed': children[0]['result'] = 'Failed'
            if operation == 'skipped': children[0]['result'] = 'Skipped'
            if operation == 'foreign': children[0]['nodeIdentifierURL'] += '#foreign'
            if operation == 'invalid': children[0]['nodeIdentifierURL'] = children[0]['nodeIdentifierURL'].replace('args=01', 'args=other')
            with self.subTest(operation=operation), self.assertRaises(ValueError): f.inventory(s, bad, selectors)

    def test_parameter_method_requires_leaves(self):
        s, t, selectors = fixture(True); t['testNodes'][0]['children'] = []
        with self.assertRaises(ValueError): f.inventory(s, t, selectors)

    def test_missing_duplicate_extra_and_ambiguous_methods(self):
        s, t, selectors = fixture()
        for url in ('', 'test://foreign/Merian/merianTests/Example/check', 'test://com.apple.xcode/Merian/other/Example/check',
                    'test://com.apple.xcode/Merian/merianTests/Example/%63heck', 'test://com.apple.xcode/Merian/merianTests/Example/check?args=01'):
            bad = copy.deepcopy(t); bad['testNodes'][0]['nodeIdentifierURL'] = url
            with self.subTest(url=url), self.assertRaises(ValueError): f.inventory(s, bad, selectors)
        for nodes in ([], t['testNodes'] * 2):
            with self.assertRaises(ValueError): f.inventory(s, {**t, 'testNodes': nodes}, selectors)
        with self.assertRaises(ValueError): f.inventory(s, t, selectors + ['merianTests/Absent'])
        with self.assertRaises(ValueError): f.inventory(s, t, selectors * 2)

    def test_runtime_mismatch_and_expanded_summary(self):
        s, t, selectors = fixture(True)
        for kind in ('missing', 'changed', 'expanded', 'skipped'):
            bad = copy.deepcopy(s)
            if kind == 'missing': bad['devicesAndConfigurations'] = []
            if kind == 'changed': bad['devicesAndConfigurations'][0]['device']['osBuildNumber'] = 'other'
            if kind == 'expanded': bad['devicesAndConfigurations'][0]['passedTests'] = 1
            if kind == 'skipped': bad['devicesAndConfigurations'][0]['skippedTests'] = 1
            with self.subTest(kind=kind), self.assertRaises(ValueError): f.inventory(bad, t, selectors)

    def test_source_paths_modes_and_links_change_fingerprint(self):
        entry = dict(mode='100644', type='blob', object='a' * 40)
        source = {'a': entry, 'link': dict(mode='120000', type='blob', object='b' * 40)}
        value = f.fingerprint(source)
        for bad in ({'b': entry}, {'a': {**entry, 'mode': '100755'}}, {'a': entry}, {**source, 'link': {**source['link'], 'object': 'c' * 40}}):
            self.assertNotEqual(value, f.fingerprint(bad))
        with self.assertRaises(ValueError): f.fingerprint({'bad\nname': entry})

    def snapshot(self):
        value = b'compiled'; oid = hashlib.sha1(b'blob 8\0' + value).hexdigest()
        entries = {'source.swift': dict(mode='100644', type='blob', object=oid)}
        pin = {'canonical_source': 'a' * 40, 'compiled_overrides': [], 'compiled_fingerprint': f.fingerprint(entries), 'source_kind': 'dirty_manifest_equivalent'}
        files = {'source.swift': f.sha(value)}
        record = {'head': 'b' * 40, 'before': files, 'after': files.copy()}
        log = f'Embedded iOS build provenance: revision={record["head"]} fingerprint={pin["compiled_fingerprint"]} state=dirty'
        return entries, {oid: value}, pin, record, log

    def test_dirty_complete_manifest_matches_canonical_without_clean_claim(self):
        entries, blobs, pin, record, log = self.snapshot()
        with patch.object(f, 'git_snapshot', return_value=(entries, blobs)):
            result = f.verify_snapshot(pin, record, Path('/tmp'), log)
        self.assertEqual(result['execution_state'], 'dirty')
        self.assertNotEqual(result['execution_head'], result['canonical_source'])

    def test_missing_extra_changed_and_after_drift_manifest(self):
        entries, blobs, pin, record, log = self.snapshot()
        for kind in ('missing', 'extra', 'changed', 'after'):
            bad = copy.deepcopy(record)
            if kind == 'missing': bad['before'] = {}; bad['after'] = {}
            if kind == 'extra': bad['before']['new.swift'] = 'c' * 64; bad['after'] = bad['before'].copy()
            if kind == 'changed': bad['before']['source.swift'] = 'c' * 64; bad['after'] = bad['before'].copy()
            if kind == 'after': bad['after']['source.swift'] = 'c' * 64
            with self.subTest(kind=kind), patch.object(f, 'git_snapshot', return_value=(entries, blobs)), self.assertRaises(ValueError):
                f.verify_snapshot(pin, bad, Path('/tmp'), log)

    def test_compiled_log_identity_and_fingerprint_must_match(self):
        entries, blobs, pin, record, log = self.snapshot()
        for badlog in ('', log.replace('state=dirty', 'state=clean'), log.replace('b' * 40, 'c' * 40)):
            with patch.object(f, 'git_snapshot', return_value=(entries, blobs)), self.assertRaises(ValueError):
                f.verify_snapshot(pin, record, Path('/tmp'), badlog)
        with patch.object(f, 'git_snapshot', return_value=(entries, blobs)), self.assertRaises(ValueError):
            f.verify_snapshot({**pin, 'compiled_fingerprint': 'c' * 64}, record, Path('/tmp'), log)

    def test_reconstructed_file_requires_exact_independent_hash_and_oid(self):
        entries, blobs, pin, record, log = self.snapshot()
        compiled = entries['source.swift']; current = {**compiled, 'object': 'f' * 40}
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); (root/'reconstructed').write_bytes(b'compiled')
            pin['source_kind'] = f.RECONSTRUCTED_KIND
            pin['compiled_overrides'] = [dict(path=path, compiled_entry=compiled, committed_entry=current,
                compiled_sha256=f.sha(b'compiled'), review='Exact retained hash witness',
                **({'reconstructed_file': 'reconstructed'} if path.endswith('capture-review-plan.md') else {})) for path in sorted(f.PHOTO_OVERRIDES)]
            snapshot = {path: current for path in f.PHOTO_OVERRIDES}
            expected = {path: compiled for path in f.PHOTO_OVERRIDES}
            pin['compiled_fingerprint'] = f.fingerprint(expected)
            record['before'] = record['after'] = {path: f.sha(b'compiled') for path in f.PHOTO_OVERRIDES}
            log = f'Embedded iOS build provenance: revision={record["head"]} fingerprint={pin["compiled_fingerprint"]} state=dirty'
            with patch.object(f, 'git_snapshot', return_value=(snapshot.copy(), {})), patch.object(f.a.recovery, 'git', return_value=b'compiled'):
                self.assertEqual(f.verify_snapshot(pin, record, root, log)['source_kind'], f.RECONSTRUCTED_KIND)
            for change in ('bytes', 'kind', 'missing', 'duplicate', 'mode', 'type'):
                bad = copy.deepcopy(pin)
                if change == 'bytes': (root/'reconstructed').write_bytes(b'altered')
                if change == 'kind': bad['source_kind'] = 'dirty_manifest_equivalent'
                if change == 'missing': bad['compiled_overrides'].pop()
                if change == 'duplicate': bad['compiled_overrides'].append(bad['compiled_overrides'][0])
                if change == 'mode': bad['compiled_overrides'][0]['compiled_entry']['mode'] = '100755'
                if change == 'type': bad['compiled_overrides'][0]['compiled_entry']['type'] = 'commit'
                with self.subTest(change=change), patch.object(f, 'git_snapshot', return_value=(snapshot.copy(), {})), patch.object(f.a.recovery, 'git', return_value=b'compiled'), self.assertRaises(ValueError):
                    f.verify_snapshot(bad, record, root, log)
                (root/'reconstructed').write_bytes(b'compiled')

    def test_exact_reviewed_delta_and_no_extra_paths(self):
        before = {'a': {'object': 'a'}}; after = {'a': {'object': 'b'}}
        rows = [dict(path='a', before=before['a'], after=after['a'], review='Scoped change')]
        f.validate_applicability(before, after, rows)
        for bad in ([], rows * 2, [{**rows[0], 'review': ''}], [{**rows[0], 'after': {'object': 'c'}}]):
            with self.assertRaises(ValueError): f.validate_applicability(before, after, bad)
        with self.assertRaises(ValueError): f.validate_applicability(before, {**after, 'new': {}}, rows)

    def test_unsafe_missing_or_symlinked_evidence_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); (root/'good').write_text('evidence'); (root/'linked').symlink_to(root/'good')
            self.assertEqual(f.file_at(root, 'good'), root/'good')
            for name in ('../escape', '/absolute', 'missing', 'linked', '.'):
                with self.subTest(name=name), self.assertRaises(ValueError): f.file_at(root, name)

    def test_modified_pinned_receipt_fails_before_native_export(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp).resolve(); (root/'execution.json').write_text('{}')
            with self.assertRaises(ValueError): f.verify_run({'files': {'execution.json': 'f' * 64}}, root)

    def test_critical_method_assertion_is_part_of_fingerprint(self):
        source = '    func testOne() {\n        XCTAssertTrue(true)\n    }\n    func testOther() {}'
        self.assertIn(b'XCTAssertTrue', f.method_bytes(source, 'testOne'))
        with self.assertRaises(ValueError): f.method_bytes(source, 'missing')
        with self.assertRaises(ValueError): f.method_bytes(source + '\n' + source, 'testOne')

    def test_archive_lane_exactly_matches_standard_without_units(self):
        spec = importlib.util.spec_from_file_location('workflow', Path(__file__).with_name('check-ios-release-archive-workflow.py'))
        workflow = importlib.util.module_from_spec(spec); spec.loader.exec_module(workflow)
        root = Path(__file__).resolve().parent.parent
        standard = (root/'.github/workflows/ios-build-and-test.yml').read_text()
        actual = (root/'.github/workflows/ios-consolidation-release-archive.yml').read_text()
        self.assertEqual(actual, workflow.expected(standard))
        self.assertNotIn('ios-unit-shards:', actual)
        self.assertIn('-seedPhotoSelectionReview', actual)
        self.assertNotEqual(actual.replace('timeout-minutes: 90', 'timeout-minutes: 900'), workflow.expected(standard))

    def test_exact_unsigned_archive_report_and_changed_identity_safety(self):
        candidate = dict(source_sha='a'*40, release_source_fingerprint='b'*64)
        report = dict(source_sha='a'*40, source_fingerprint='b'*64, source_state='clean', configuration='Release',
            signing='disabled-validation-only', application_path='Applications/Merian.app', xcode='Xcode 27.0 Build version 27A266a',
            dsym_uuid_match=True, privacy_manifest_valid=True, transport_security='ats-default', history_enabled_normal_oauth=True,
            local_history_diagnostics_absent=True, ui_test_seed_markers_absent=True,
            verified_embedded_products=['MerianExploreWidget.appex','MerianMessagesExtension.appex','MerianWatch.app'],
            archive_bytes=123, main_binary_sha256='c'*64, version='1.1.0', build='275')
        project=b'  MARKETING_VERSION: 1.1.0\n  CURRENT_PROJECT_VERSION: 275\n'
        with patch.object(f.a.recovery, 'git', return_value=project):
            f.validate_archive_report(report,candidate)
            for key,value in [('source_sha','d'*40),('source_fingerprint','d'*64),('source_state','dirty'),('signing','signed'),
                              ('ui_test_seed_markers_absent',False),('privacy_manifest_valid',False),('dsym_uuid_match',1),
                              ('build','276'),('verified_embedded_products',[]),('archive_bytes',0)]:
                with self.subTest(key=key), self.assertRaises(ValueError): f.validate_archive_report({**report,key:value},candidate)

    def test_journey_mapping_rejects_missing_path_run_and_method(self):
        before={'apps/ios/a': {'object':'a'}};after={'apps/ios/a': {'object':'b'}}
        row=dict(path='apps/ios/a',before=before['apps/ios/a'],after=after['apps/ios/a'],review='Scoped')
        review=dict(source_sha='old',review='Scoped',reviewed_delta=[row],required_methods=['method'],
                    change_coverage={'apps/ios/a':[dict(run='photo',method='method')]})
        policy=dict(required_focused_selectors=['oldmethod'],successor_followups=dict(product_source='new',
            journey_applicability={'photo':review},runs=[dict(id='photo',accepted_methods=['method'])]))
        rec=dict(requirement='photo',source_sha='old',owned_paths=['apps/ios'])
        with patch.object(f.a,'tree_entries',side_effect=lambda rev:before if rev=='old' else after), patch.object(f.a,'product_tree',return_value='same'):
            f.journey_applicability(policy,rec,'candidate')
            for kind in ('path','run','method','required'):
                bad=copy.deepcopy(policy);r=bad['successor_followups']['journey_applicability']['photo']
                if kind=='path': r['change_coverage']={}
                if kind=='run': r['change_coverage']['apps/ios/a'][0]['run']='unknown'
                if kind=='method': r['change_coverage']['apps/ios/a'][0]['method']='unrun'
                if kind=='required': r['required_methods']=['unrun']
                with self.subTest(kind=kind),self.assertRaises(ValueError): f.journey_applicability(bad,rec,'candidate')

    def test_archive_run_steps_both_artifacts_and_digest_are_bound(self):
        candidate=dict(source_sha='a'*40,release_source_fingerprint='b'*64)
        run=dict(head_sha='a'*40,path='.github/workflows/ios-consolidation-release-archive.yml',status='completed',
                 conclusion='success',event='push',run_attempt=1,run_number=22)
        names=('Checkout exact workflow SHA','Archive unsigned Release from current SHA','Verify Release archive structure and dSYM',
               'Upload Release archive evidence','Upload current-SHA validation archive')
        jobs=[dict(name='Archive contract',conclusion='success',head_sha='a'*40),dict(name='Current-SHA Release archive',
            conclusion='success',head_sha='a'*40,steps=[dict(name=n,conclusion='success') for n in names])]
        stream=io.BytesIO()
        with zipfile.ZipFile(stream,'w') as z: z.writestr('ios-release-archive-evidence.json','{}')
        raw=stream.getvalue()
        artifacts=[dict(id=7,name='ios-release-archive-evidence-22-attempt-1',expired=False,workflow_run=dict(id=123,head_sha='a'*40),digest='sha256:'+f.sha(raw)),
          dict(id=8,name='ios-unsigned-release-archive-'+'a'*40+'-attempt-1',expired=False,workflow_run=dict(id=123,head_sha='a'*40),
               digest='sha256:'+'c'*64,size_in_bytes=100)]
        for mutation in ('none','run','skip','archive_missing','archive_expired','archive_head','archive_size','archive_digest','archive_duplicate','zip_digest'):
            client=Mock();r=copy.deepcopy(run);j=copy.deepcopy(jobs);arts=copy.deepcopy(artifacts)
            if mutation=='run':r['head_sha']='d'*40
            if mutation=='skip':j[1]['steps'][1]['conclusion']='skipped'
            if mutation=='archive_missing':arts.pop()
            if mutation=='archive_expired':arts[1]['expired']=True
            if mutation=='archive_head':arts[1]['workflow_run']['head_sha']='d'*40
            if mutation=='archive_size':arts[1]['size_in_bytes']=0
            if mutation=='archive_digest':arts[1]['digest']='unknown'
            if mutation=='archive_duplicate':arts.append(copy.deepcopy(arts[1]))
            if mutation=='zip_digest':arts[0]['digest']='sha256:'+'d'*64
            client.json.return_value=r
            client.listing.side_effect=lambda path,key: {key:j if key=='jobs' else arts}
            client.bytes.return_value=raw
            with tempfile.TemporaryDirectory() as tmp, patch.object(f,'validate_archive_report') as validate:
                out=Path(tmp).resolve()/'new'
                if mutation=='none':
                    result=f.verify_archive(client,123,candidate,out)
                    self.assertEqual(result['validation_archive']['id'],8)
                    validate.assert_called_once()
                else:
                    with self.subTest(mutation=mutation),self.assertRaises(ValueError):f.verify_archive(client,123,candidate,out)


if __name__ == '__main__':
    unittest.main()
