#!/usr/bin/env python3
"""Verify retained November 26 follow-ups without rewriting earlier acceptance."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.parse

spec = importlib.util.spec_from_file_location('acceptance', Path(__file__).with_name('ios-consolidation-acceptance.py'))
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)
require = a.require
POLICY = 'scripts/config/ios-consolidation-acceptance.json'
PHOTO_OVERRIDES = frozenset(('.github/workflows/ios-build-and-test.yml', 'apps/ios/Merian/App/README.md',
    'docs/features-and-hardware/29-staged-capture-review.md', 'docs/product/capture-review-plan.md'))
RECONSTRUCTED_KIND = 'dirty_manifest_equivalent_with_reviewed_post_native_nonruntime_delta'
LEGACY_MODULES = ('ios-focused-recovery.py', 'ios-consolidation-acceptance.py', 'ios-evidence-recovery.py',
                  'ios-unit-shards.py', 'ios-runtime-audit.py')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_at(root, relative):
    path = Path(relative)
    require(not path.is_absolute() and '..' not in path.parts and str(path) not in ('', '.'), 'Unsafe evidence path')
    result = root / path
    require(result.resolve() == result.absolute() and result.is_file(), 'Missing or linked evidence')
    return result


def git_snapshot(revision):
    entries = a.tree_entries(revision)
    ids = list(dict.fromkeys(e['object'] for e in entries.values() if e['type'] == 'blob'))
    raw = subprocess.check_output(['git', 'cat-file', '--batch'], input=('\n'.join(ids) + '\n').encode(), cwd=a.ROOT)
    blobs, offset = {}, 0
    for oid in ids:
        end = raw.index(b'\n', offset)
        found, kind, size = raw[offset:end].decode().split()
        require(found == oid and kind == 'blob', 'Invalid Git source object')
        size = int(size)
        blobs[oid] = raw[end + 1:end + 1 + size]
        offset = end + size + 2
    return entries, blobs


def fingerprint(entries):
    lines = []
    for path, entry in entries.items():
        mode, oid = entry['mode'], entry['object']
        require(entry['type'] == ('commit' if mode == '160000' else 'blob'), 'Invalid source object type')
        require(mode in ('100644', '100755', '120000', '160000') and not any(c in path for c in '\n\r\t'), 'Invalid source entry')
        lines.append((f'{mode}\t{oid}\t{path}\n' if mode in ('120000', '160000') else f'{mode}\t{path}\t{oid}\n').encode())
    return sha(b''.join(sorted(lines)))


def verify_snapshot(pin, record, root, log):
    overrides = pin['compiled_overrides']
    if pin['source_kind'] == RECONSTRUCTED_KIND:
        require(len(overrides) == 4 and {o['path'] for o in overrides} == PHOTO_OVERRIDES, 'Unexpected reconstructed source scope')
        require([o['path'] for o in overrides if o.get('reconstructed_file')] == ['docs/product/capture-review-plan.md'], 'Missing exact reconstructed document witness')
    else:
        require(not overrides, 'Ordinary source equivalence cannot hide post-native changes')
    entries, blobs = git_snapshot(pin['canonical_source'])
    for override in pin['compiled_overrides']:
        path = override['path']
        require(entries.get(path) == override['committed_entry'], 'Post-native source entry changed')
        value = (file_at(root, override['reconstructed_file']).read_bytes() if override.get('reconstructed_file')
                 else a.recovery.git('cat-file', 'blob', override['compiled_entry']['object']))
        oid = hashlib.sha1(b'blob ' + str(len(value)).encode() + b'\0' + value).hexdigest()
        require(sha(value) == override['compiled_sha256'] and oid == override['compiled_entry']['object'], 'Compiled reconstruction changed')
        require(override['review'].strip(), 'Missing post-native impact review')
        require(override['compiled_entry']['type'] == 'blob' and override['compiled_entry']['mode'] == '100644'
                and override['committed_entry']['type'] == 'blob' and override['committed_entry']['mode'] == '100644', 'Unsafe reconstructed entry')
        entries[path], blobs[oid] = override['compiled_entry'], value
    require(fingerprint(entries) == pin['compiled_fingerprint'], 'Complete source fingerprint mismatch')
    regular = {p: sha(blobs[e['object']]) for p, e in entries.items() if e['mode'] in ('100644', '100755')}
    if pin['source_kind'] in ('dirty_manifest_equivalent', RECONSTRUCTED_KIND):
        require(record['before'] == record['after'] == regular, 'Complete source map changed or incomplete')
        head, state = record['head'], 'dirty'
    else:
        require(pin['source_kind'] == 'clean_commit' and not pin['compiled_overrides'], 'Unknown source provenance kind')
        require(record['source'] == record['source_after'] == pin['canonical_source'], 'Clean execution revision changed')
        require(record['files'] == record['files_after'] and all(regular.get(p) == h for p, h in record['files'].items()), 'Clean execution files changed')
        head, state = record['source'], 'clean'
    marker = f'Embedded iOS build provenance: revision={head} fingerprint={pin["compiled_fingerprint"]} state={state}'
    require(marker in log, 'Compiled provenance missing from original command log')
    return {'canonical_source': pin['canonical_source'], 'compiled_fingerprint': pin['compiled_fingerprint'],
            'execution_head': head, 'execution_state': state, 'source_kind': pin['source_kind'], 'regular_files': len(regular),
            'symlinks': sum(e['mode'] == '120000' for e in entries.values()), 'post_native_delta': pin['compiled_overrides']}


def inventory(summary, tree, selectors):
    require(selectors and len(set(selectors)) == len(selectors), 'Invalid selector plan')
    cases, leaves = {}, {}
    for node in a.audit.nodes(tree):
        if node.get('nodeType') != 'Test Case':
            continue
        url = urllib.parse.urlsplit(node.get('nodeIdentifierURL', ''))
        parts = url.path.strip('/').split('/')
        require(url.scheme == 'test' and url.netloc == 'com.apple.xcode' and not url.query and not url.fragment
                and '%' not in url.path and len(parts) == 4 and parts[0] in ('Merian', 'merian')
                and parts[1] in ('merianTests', 'merianUITests'), 'Ambiguous method identity')
        method = '/'.join(parts[1:]).removesuffix('()')
        require(method not in cases and any(method == s or method.startswith(s + '/') for s in selectors), 'Duplicate or extra method')
        require(node.get('result') in ('Passed', 'Failed'), 'Skipped or unfinished method')
        cases[method] = node['result']
        arguments = [n for n in a.audit.nodes(node) if n.get('nodeType') == 'Arguments']
        require(bool(arguments) == (':' in parts[-1]), 'Parameterized inventory missing or unexpected')
        parameter_results = {}
        for item in arguments:
            leaf = urllib.parse.urlsplit(item.get('nodeIdentifierURL', ''))
            require(leaf.scheme == url.scheme and leaf.netloc == url.netloc and leaf.path == url.path and not leaf.fragment
                    and re.fullmatch(r'args=[a-fA-F0-9]+', leaf.query), 'Ambiguous parameter identity')
            require(leaf.query not in parameter_results and item.get('result') in ('Passed', 'Failed'), 'Duplicate/skipped parameter')
            parameter_results[leaf.query] = item['result']
        if arguments:
            require((node['result'] == 'Passed') == all(v == 'Passed' for v in parameter_results.values()), 'Method/parameter result disagreement')
        leaves[method] = parameter_results
    require(all(any(m == s or m.startswith(s + '/') for m in cases) for s in selectors), 'Selected suite/method absent')
    failed = sum(v == 'Failed' for v in cases.values())
    for key, value in {'totalTestCount': len(cases), 'passedTests': len(cases) - failed, 'failedTests': failed, 'skippedTests': 0}.items():
        require(type(summary.get(key)) is int and summary[key] == value, 'Summary coverage mismatch')
    require(summary.get('expectedFailures', 0) == 0 and summary.get('result') == ('Failed' if failed else 'Passed'), 'Invalid result disposition')
    devices = tree.get('devices', [])
    configs = summary.get('devicesAndConfigurations', [])
    require(len(devices) == len(configs) == 1 and configs[0]['device'] == devices[0], 'Missing or changed runtime')
    require(all(devices[0].get(k) for k in ('deviceId', 'osVersion', 'osBuildNumber', 'architecture', 'platform')), 'Incomplete runtime identity')
    expanded = [v for m in cases for v in (list(leaves[m].values()) or [cases[m]])]
    require(configs[0]['passedTests'] == expanded.count('Passed') and configs[0]['failedTests'] == expanded.count('Failed')
            and configs[0]['skippedTests'] == 0 and configs[0].get('expectedFailures', 0) == 0, 'Expanded coverage mismatch')
    return {'methods': cases, 'parameters': leaves, 'device': devices[0], 'expanded_cases': len(expanded)}


def validate_applicability(before, after, records):
    changed = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
    require(len(records) == len({r['path'] for r in records}) and {r['path'] for r in records} == changed, 'Unreviewed follow-up delta')
    for r in records:
        require(r['before'] == before.get(r['path']) and r['after'] == after.get(r['path']) and r['review'].strip(), 'Follow-up source object changed')


def verify_run(pin, root):
    for name, digest in pin['files'].items():
        require(a.shards.digest(file_at(root, name)) == digest, 'Pinned follow-up evidence changed: ' + name)
    record = a.shards.read_json(file_at(root, pin['execution']))
    log = file_at(root, pin['log']).read_text()
    require(record['selectors'] == pin['selectors'] and record['command'] == pin['command'], 'Native plan/command/deadline changed')
    canonical = a.focused_command({'required_focused_selectors': pin['selectors']}, pin['destination'])
    require(record['command'] in (canonical, ['caffeinate', '-i'] + canonical), 'Noncanonical managed command')
    require(record['exit_code'] == pin['exit_code'], 'Original failure disposition changed')
    require(pin['sdk_marker'] in log and '/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild' in log, 'Compiled SDK/toolchain path missing')
    source = verify_snapshot(pin, record, root, log)
    bundle = root / pin['bundle']
    require(bundle.resolve() == bundle.absolute() and bundle.parent == root / 'local-ios', 'Bundle outside retained evidence')
    require(('Result bundle: ' + str(bundle) + '\n') in log and ('-resultBundlePath ' + str(bundle) + ' ') in log, 'XCResult is not bound to the original build log')
    require(a.bundle_digest(bundle) == pin['bundle_sha256'], 'Original XCResult changed')
    with tempfile.TemporaryDirectory() as tmp:
        raw = a.extract(bundle, Path(tmp))
    for kind in ('summary', 'tests'):
        require(raw[kind] == a.shards.read_json(file_at(root, pin[kind])), 'Original XCResult/export mismatch')
    actual = inventory(raw['summary'], raw['tests'], pin['selectors'])
    require(actual == pin['inventory'], 'Compiled method/parameter inventory changed')
    require(actual['device']['deviceId'].lower() == pin['destination'].split('id=')[1].lower(), 'Destination mismatch')
    failures = [m for m, v in actual['methods'].items() if v == 'Failed']
    require(bool(failures) == (record['exit_code'] != 0), 'Process/test result mismatch')
    require(pin['accepted_methods'] and len(set(pin['accepted_methods'])) == len(pin['accepted_methods'])
            and all(actual['methods'].get(m) == 'Passed' for m in pin['accepted_methods']), 'Failed/missing method counted as accepted')
    require(pin['review'].strip(), 'Missing affected-method applicability review')
    return {'id': pin['id'], 'source': source, 'accepted_methods': pin['accepted_methods'],
            'original_failed_methods': failures, 'inventory': actual}


def verify(policy, directory, candidate):
    follow = policy['successor_followups']
    base = follow['base_source']
    raw_policy = a.recovery.git('show', base + ':' + POLICY)
    require(sha(raw_policy) == follow['base_policy_sha256'], 'Legacy policy changed')
    legacy_policy = json.loads(raw_policy)
    require(not policy.get('focused_evidence') and policy['focused_recovery'] == legacy_policy['focused_recovery']
            and policy['required_focused_selectors'] == legacy_policy['required_focused_selectors'], 'Legacy route or selector plan changed')
    # Old bundles remain in their original retained worktree. This admits only
    # the policy-pinned checkout in this same Git repository; no imported code.
    retained = Path(follow['legacy_checkout'])
    common = lambda p: subprocess.check_output(['git', '-C', str(p), 'rev-parse', '--path-format=absolute', '--git-common-dir'], text=True).strip()
    require(retained.resolve() == retained.absolute() and common(retained) == common(a.ROOT), 'Foreign legacy checkout')
    require(subprocess.check_output(['git', '-C', str(retained), 'rev-parse', 'HEAD'], text=True).strip() == base, 'Legacy checkout moved')
    for name in LEGACY_MODULES:
        path = file_at(retained, 'scripts/' + name)
        require(path.read_bytes() == a.recovery.git('show', base + ':scripts/' + name), 'Legacy verifier/helper changed')
    spec = importlib.util.spec_from_file_location('legacy_focused', retained / 'scripts/ios-focused-recovery.py')
    legacy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(legacy)
    old = legacy.verify(legacy_policy, directory, {'source_sha': base})
    target = follow['product_source']
    validate_applicability(a.tree_entries(base), a.tree_entries(target), follow['reviewed_delta'])
    require(a.product_tree(policy, target) == a.product_tree(policy, candidate['source_sha']), 'Unvalidated product changes after follow-ups')
    root = Path(follow['evidence_root'])
    require(root.resolve() == root.absolute() and root.name == '.artifacts' and common(root.parent) == common(a.ROOT), 'Foreign follow-up evidence root')
    for pin in follow['runs']:
        validate_applicability(a.tree_entries(pin['canonical_source']), a.tree_entries(target), pin['later_delta'])
    records = [verify_run(pin, root) for pin in follow['runs']]
    require(len({r['id'] for r in records}) == len(records), 'Duplicate follow-up execution')
    union = sorted({m for r in records for m in r['accepted_methods']})
    require(union == follow['required_methods'], 'Follow-up coverage incomplete')
    require(all(m in union for r in records for m in r['original_failed_methods']), 'Unrecovered follow-up failure')
    critical = verify_critical_reuse(policy, candidate['source_sha'])
    return {'legacy': old, 'critical_smoke_reuse': critical, 'followups': records, 'methods': sorted(set(old['methods']) | set(union)),
            'followup_methods': union, 'product_source': target, 'verifier_source': candidate['source_sha'],
            'original_failures_preserved': True, 'clean_execution_claimed_for_dirty_receipts': False}


def journey_applicability(policy, record, candidate):
    follow = policy['successor_followups']
    review = follow['journey_applicability'].get(record['requirement'])
    require(review and review['source_sha'] == record['source_sha'] and review['review'].strip(), 'Missing journey impact review')
    target = follow['product_source']
    require(a.product_tree(policy, target) == a.product_tree(policy, candidate), 'Journey successor product changed')
    before, after = a.tree_entries(record['source_sha']), a.tree_entries(target)
    owned = record['owned_paths']
    def selected(entries):
        return {p: e for p, e in entries.items() if any(p == o or p.startswith(o.rstrip('/') + '/') for o in owned)}
    validate_applicability(selected(before), selected(after), review['reviewed_delta'])
    available = {r['id']: set(r['accepted_methods']) for r in follow['runs']}
    available['legacy'] = set(policy['required_focused_selectors'])
    changed = {r['path'] for r in review['reviewed_delta']}
    mapping = review['change_coverage']
    require(set(mapping) == changed, 'Missing exact journey path coverage')
    covered = set()
    for path, refs in mapping.items():
        require(refs and len(refs) == len({(r['run'], r['method']) for r in refs}), 'Missing/duplicate journey regression mapping')
        for ref in refs:
            require(ref['method'] in available.get(ref['run'], set()), 'Journey regression method not accepted')
            covered.add(ref['method'])
    required = review['required_methods']
    require(required and len(required) == len(set(required)) and set(required) <= covered, 'Journey essential-method coverage missing')


def method_bytes(source, method):
    matches = re.findall(r"(?ms)^    func " + re.escape(method) + r"\b.*?^    }", source)
    require(len(matches) == 1, "Missing or ambiguous critical method body")
    return matches[0].encode()


def verify_critical_reuse(policy, candidate):
    follow = policy['successor_followups']
    pins = follow['critical_smoke_reuse']
    require(len(pins) == 6 and len({p['selector'] for p in pins}) == 6, 'Incomplete critical UI reuse review')
    for pin in pins:
        require(pin['selector'] in policy['required_focused_selectors'] and pin['review'].strip(), 'Critical selector not in legacy evidence')
        for revision in (follow['base_source'], candidate):
            source = a.recovery.git('show', revision + ':' + pin['test_file']).decode()
            require(sha(method_bytes(source, pin['selector'].rsplit('/', 1)[1])) == pin['method_sha256'], 'Critical assertion changed')
        require(pin['dependencies'] and not a.recovery.git('diff', '--name-only', follow['base_source'], candidate, '--', *pin['dependencies']).strip(), 'Critical fixture/runtime dependency changed')
    return pins


def validate_archive_report(report, candidate):
    expected = {'source_sha': candidate['source_sha'], 'source_fingerprint': candidate['release_source_fingerprint'],
        'source_state': 'clean', 'configuration': 'Release', 'signing': 'disabled-validation-only',
        'application_path': 'Applications/Merian.app', 'xcode': 'Xcode 27.0 Build version 27A266a',
        'dsym_uuid_match': True, 'privacy_manifest_valid': True, 'transport_security': 'ats-default',
        'history_enabled_normal_oauth': True, 'local_history_diagnostics_absent': True, 'ui_test_seed_markers_absent': True,
        'verified_embedded_products': ['MerianExploreWidget.appex', 'MerianMessagesExtension.appex', 'MerianWatch.app']}
    require(all(report.get(k) == v and type(report.get(k)) is type(v) for k, v in expected.items()), 'Archive source/configuration/safety mismatch')
    require(type(report.get('archive_bytes')) is int and report['archive_bytes'] > 0
            and re.fullmatch(r'[a-f0-9]{64}', report.get('main_binary_sha256', '')), 'Missing archive binary identity')
    project = a.recovery.git('show', candidate['source_sha'] + ':project.yml').decode()
    for key, setting in (('version', 'MARKETING_VERSION'), ('build', 'CURRENT_PROJECT_VERSION')):
        match = re.search(r'^\s+' + setting + r':\s*([0-9.]+)\s*$', project, re.M)
        require(match and report.get(key) == match[1], 'Archive version differs from tracked source')


def verify_archive(client, run_id, candidate, output):
    require(type(run_id) is int and run_id > 0, 'Missing exact-source archive workflow')
    run = client.json(f'/actions/runs/{run_id}')
    require(run['head_sha'] == candidate['source_sha'] and run['path'] == '.github/workflows/ios-consolidation-release-archive.yml'
            and run['status'] == 'completed' and run['conclusion'] == 'success' and run['event'] in ('push', 'workflow_dispatch'),
            'Archive workflow not a qualifying exact-source pass')
    jobs = client.listing(f'/actions/runs/{run_id}/attempts/{run["run_attempt"]}/jobs', 'jobs')['jobs']
    require(len(jobs) == 2 and {j['name'] for j in jobs} == {'Archive contract', 'Current-SHA Release archive'}
            and all(j['conclusion'] == 'success' and j['head_sha'] == candidate['source_sha'] for j in jobs), 'Missing archive/parity job')
    job = next(j for j in jobs if j['name'] == 'Current-SHA Release archive')
    for step in ('Checkout exact workflow SHA', 'Archive unsigned Release from current SHA', 'Verify Release archive structure and dSYM', 'Upload Release archive evidence', 'Upload current-SHA validation archive'):
        found = [s for s in job['steps'] if s['name'] == step]
        require(len(found) == 1 and found[0]['conclusion'] == 'success', 'Required archive step did not pass')
    artifacts = client.listing(f'/actions/runs/{run_id}/artifacts', 'artifacts')['artifacts']
    archive_name = f'ios-unsigned-release-archive-{candidate["source_sha"]}-attempt-{run["run_attempt"]}'
    archives = [artifact for artifact in artifacts if artifact['name'] == archive_name]
    require(len(archives) == 1, 'Missing or duplicate actual validation archive')
    archive = archives[0]
    require(not archive['expired'] and archive['workflow_run']['head_sha'] == candidate['source_sha']
            and archive['workflow_run']['id'] == run_id and type(archive['size_in_bytes']) is int and archive['size_in_bytes'] > 0
            and re.fullmatch(r'sha256:[a-f0-9]{64}', archive.get('digest', '')), 'Invalid validation archive identity')
    name = f'ios-release-archive-evidence-{run["run_number"]}-attempt-{run["run_attempt"]}'
    found = [artifact for artifact in artifacts if artifact['name'] == name]
    require(len(found) == 1 and not found[0]['expired'] and found[0]['workflow_run']['head_sha'] == candidate['source_sha'] and found[0]['workflow_run']['id'] == run_id, 'Archive evidence missing or foreign')
    artifact = found[0]
    raw = client.bytes(f'/actions/artifacts/{artifact["id"]}/zip')
    require(artifact.get('digest') == 'sha256:' + sha(raw), 'Archive artifact digest mismatch')
    a.recovery.safe_unzip(raw, output)
    report = a.shards.read_json(file_at(output, 'ios-release-archive-evidence.json'))
    validate_archive_report(report, candidate)
    return {'run_id': run_id, 'attempt': run['run_attempt'], 'artifact_id': artifact['id'],
            'artifact_sha256': sha(raw), 'validation_archive': {k: archive[k] for k in ('id', 'name', 'digest', 'size_in_bytes')}, 'report': report, 'signing_or_distribution_authorized': False}
