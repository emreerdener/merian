#!/usr/bin/env python3
"""Boundary fixtures and executable parity with the native Swift policy reader."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('preflight', Path(__file__).with_name('check-ios-fast-preflight.py'))
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)
ROOT = Path(__file__).resolve().parents[1]


class SwiftParityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.directory = Path(cls.temp.name)
        build = preflight.load_build_tools()
        cls.lock = build.Workspace(ROOT).lock()
        cls.lock.__enter__()
        cls.addClassCleanup(lambda: cls.lock.__exit__(None, None, None))
        build.ensure_no_xcodebuild()
        main = cls.directory / 'main.swift'
        main.write_text('''import Foundation
let input = try JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as! [String: Any]
let sources = input["sources"] as! [String]
let policy = try IOSSourceSizePolicy.load(root: URL(fileURLWithPath: CommandLine.arguments[1]))
let result: [String: Any] = [
    "counts": sources.map { [IOSSourceSizePolicy.physicalLines($0), IOSSourceSizePolicy.newlineSegments($0)] },
    "oversizedOwners": policy.oversizedOwners.sorted(),
    "globalCeiling": policy.globalCeiling,
    "globalOnlyFiles": policy.globalOnlyFiles,
    "sealedOwnerCeilings": policy.sealedOwnerCeilings,
    "directories": policy.directoryRules.mapValues { rule in sources.map { rule.count($0) <= rule.ceiling } },
    "files": policy.fileRules.mapValues { rule in sources.map { rule.count($0) <= rule.ceiling } }
]
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
''')
        cls.binary = cls.directory / 'parity'
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(cls.directory / 'modules'),
                        str(ROOT / 'apps/ios/MerianTests/IOSSourceSizePolicy.swift'), str(main),
                        '-o', str(cls.binary)], check=True)

    def test_swift_counter_and_all_rule_boundaries_match(self):
        policy = preflight.load_policy(ROOT)
        sources = ['', 'a', '\n', 'a\n', 'a\nb', 'a\nb\n', '\r\n', 'a\r\nb\r\n',
                   '\r\n\n', '\r\r\n', '\n\r', 'a\u2028b\u2029c', '👩🏽‍💻\n🇹🇷\n',
                   'e\u0301\r\n\u0301\n', '\x00\n']
        ceilings = {r['ceiling'] for r in [*policy['directoryRules'].values(), *policy['fileRules'].values()]}
        for ceiling in ceilings | {policy['globalCeiling'], *policy['sealedOwnerCeilings'].values()}:
            for count in (ceiling - 1, ceiling, ceiling + 1):
                sources.extend(['x\n' * count, '\n'.join(['x'] * count), 'x\r\n' * count])
        result = subprocess.run([str(self.binary), str(ROOT)], input=json.dumps({'sources': sources}),
                                text=True, capture_output=True, check=True)
        swift = json.loads(result.stdout)
        self.assertEqual(swift['counts'], [[preflight.count_lines(s, c) for c in ('physical', 'segments')]
                                           for s in sources])
        self.assertEqual(swift['oversizedOwners'], sorted(policy['oversizedOwners']))
        self.assertEqual(swift['sealedOwnerCeilings'], policy['sealedOwnerCeilings'])
        self.assertEqual(swift['globalCeiling'], policy['globalCeiling'])
        self.assertEqual(swift['globalOnlyFiles'], policy['globalOnlyFiles'])
        for swift_key, policy_key in [('directories', 'directoryRules'), ('files', 'fileRules')]:
            self.assertEqual(swift[swift_key], {
                path: [preflight.count_lines(s, rule['counter']) <= rule['ceiling'] for s in sources]
                for path, rule in policy[policy_key].items()})


class PolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)

    def fixture(self):
        root = Path(self.temp.name) / self.id().split('.')[-1]
        production = root / 'apps/ios/Merian'
        production.mkdir(parents=True)
        policy = dict(version=1, productionRoot='apps/ios/Merian', globalCeiling=3,
                      oversizedOwners=['Large.swift'], sealedOwnerCeilings={'Large.swift': 4},
                      directoryRules={'apps/ios/Merian/Features/Capture/Scan': dict(counter='segments', ceiling=3)},
                      fileRules={'apps/ios/Merian/Camera.swift': dict(counter='segments', ceiling=2)},
                      globalOnlyDirectories=['apps/ios/Merian/Core/Data/SharedMediaStorage'], globalOnlyFiles=[])
        (production / 'Large.swift').write_bytes(b'x\nx\nx\nx')
        (production / 'Camera.swift').write_bytes(b'x\nx')
        scan = production / 'Features/Capture/Scan/A.swift'
        scan.parent.mkdir(parents=True)
        scan.write_bytes(b'x\nx\nx')
        return root, policy, scan

    def test_inventory_is_exact_and_sealed_ceiling_intersects(self):
        root, policy, scan = self.fixture()
        self.assertEqual(preflight.size_failures(root, policy, []), [])
        large = root / 'apps/ios/Merian/Large.swift'
        for source, diagnostic in [(b'x', 'missing='), (b'x\nx\nx\nx\nx', 'sealed ceiling')]:
            large.write_bytes(source)
            self.assertTrue(any(diagnostic in f for f in preflight.size_failures(root, policy, [])))
        large.write_bytes(b'x\nx\nx\nx')
        (large.parent / 'Unapproved.swift').write_bytes(b'x\nx\nx\nx')
        self.assertTrue(any('Unapproved.swift' in f for f in preflight.size_failures(root, policy, [])))
        # A sealed ceiling does not grant membership in the oversized inventory.
        policy['sealedOwnerCeilings']['Unapproved.swift'] = 4
        self.assertTrue(any('Unapproved.swift' in f for f in preflight.size_failures(root, policy, [])))

    def test_trailing_newline_can_fail_domain_while_global_passes(self):
        root, policy, scan = self.fixture()
        scan.write_bytes(b'x\nx\nx\n')
        failures = preflight.size_failures(root, policy, [scan.relative_to(root).as_posix()])
        self.assertEqual(len(failures), 1)
        self.assertIn('4 segments > 3', failures[0])
        scan.write_bytes(b'x\r\nx\r\nx\r\n')
        self.assertEqual(preflight.size_failures(root, policy, []), [])

    def test_unknown_domain_and_missing_policy_owners_fail(self):
        root, policy, scan = self.fixture()
        failures = preflight.size_failures(root, policy, ['apps/ios/Merian/Core/Network/X.swift'])
        self.assertTrue(any('Unsupported domain' in f for f in failures))
        (root / 'apps/ios/Merian/Camera.swift').unlink()
        scan.unlink()
        failures = preflight.size_failures(root, policy, [])
        self.assertTrue(any('Missing bounded owner' in f for f in failures))
        self.assertTrue(any('Empty or missing policy directory' in f for f in failures))

    def test_native_photo_preflight_coverage_has_exact_bounded_network_and_image_owners(self):
        root, policy, _ = self.fixture()
        for path in [
            'apps/ios/Merian/Core/Data/AnalysisHistory/AnalysisRecoveryPresentation.swift',
            'apps/ios/Merian/Models/ActiveSchema/OfflineQueuedScan.swift',
            'apps/ios/Merian/Models/Schema/SchemaV68.swift',
            'apps/ios/Merian/Core/Data/Images/Policies/ImagePreparationPolicy.swift',
            'apps/ios/Merian/Core/Data/Images/MediaPreparationActor.swift',
            'apps/ios/Merian/Core/Media/ImageCropProcessor.swift',
            'apps/ios/Merian/Core/Network/Inference/IdentificationPreflight.swift',
            'apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+IdentificationPreflight.swift',
            'apps/ios/Merian/Core/Network/Models/ObservationAnalysis/InitialPhotoAllocationRequest.swift',
            'apps/ios/Merian/Core/Network/Models/ObservationAnalysis/InitialPhotoTransferRequest.swift',
            'apps/ios/Merian/Core/Network/Models/ObservationAnalysis/InitialPhotoAllocationRoleReply.swift',
            'apps/ios/Merian/Core/Network/Models/ObservationAnalysis/InitialPhotoUploadStatus.swift',
            'apps/ios/Merian/Core/Network/Models/ObservationAnalysis/InitialPhotoUploadDestination.swift',
            'apps/ios/Merian/Core/Network/Models/ObservationAnalysis/InitialPhotoUploadTicket.swift',
            'apps/ios/Merian/Core/Network/Transport/InitialPhotoAllocationTransport.swift',
            'apps/ios/Merian/Core/Network/Transport/PinnedNetworkTransport.swift',
            'apps/ios/Merian/Core/Network/Transport/PinnedBoundedJSONDataTask.swift',
            'apps/ios/Merian/Core/Network/Transport/AuthenticatedTransportDispatcher.swift',
        ]:
            actual = preflight.load_policy(ROOT)
            # Preserve the existing physical-line review ceiling for each owner.
            self.assertEqual(actual['fileRules'][path], dict(counter='physical', ceiling=600))
            self.assertFalse(any(preflight.within(path, directory) for directory in
                                 [*actual['directoryRules'], *actual['globalOnlyDirectories']]))
            source = root / path
            source.parent.mkdir(parents=True, exist_ok=True)
            policy['fileRules'][path] = dict(counter='physical', ceiling=2)
            source.write_bytes(b'x\nx\n')
            self.assertEqual(preflight.size_failures(root, policy, [path]), [])
            source.write_bytes(b'x\nx\nx\n')
            self.assertTrue(any('3 physical > 2' in failure
                                for failure in preflight.size_failures(root, policy, [path])))
            source.write_bytes(b'x\nx\n')
            sibling = source.with_name('Other.swift')
            sibling.write_bytes(b'x')
            self.assertTrue(any('Unsupported domain' in failure for failure in
                                preflight.size_failures(root, policy, [sibling.relative_to(root).as_posix()])))

    def test_auth_facade_preserves_owning_architecture_ceiling(self):
        path = 'apps/ios/Merian/Core/Network/SupabaseManager.swift'
        actual = preflight.load_policy(ROOT)
        rule = dict(counter='physical', ceiling=3792)
        self.assertEqual(actual['fileRules'][path], rule)
        root, policy, _ = self.fixture()
        source = root / path
        source.parent.mkdir(parents=True, exist_ok=True)
        policy['oversizedOwners'].append('Core/Network/SupabaseManager.swift')
        policy['fileRules'][path] = rule
        source.write_text('x\n' * 3792)
        self.assertEqual(preflight.size_failures(root, policy, [path]), [])
        source.write_text('x\n' * 3793)
        self.assertTrue(any('3793 physical > 3792' in error for error in
                            preflight.size_failures(root, policy, [path])))

    def test_outgoing_receiving_schema_has_exact_global_ceiling_coverage(self):
        path = 'apps/ios/Merian/Models/Schema/SchemaV66.swift'
        actual = preflight.load_policy(ROOT)
        self.assertEqual(actual['fileRules'][path], dict(counter='physical', ceiling=600))
        root, policy, _ = self.fixture()
        policy['fileRules'][path] = dict(counter='physical', ceiling=2)
        source = root / path
        source.parent.mkdir(parents=True)
        source.write_text('x\nx\n')
        self.assertEqual(preflight.size_failures(root, policy, [path]), [])
        source.write_text('x\nx\nx\n')
        self.assertTrue(any('3 physical > 2' in error for error in preflight.size_failures(root, policy, [path])))
        source.write_text('x\nx\n')
        sibling = source.with_name('UncoveredSchema.swift')
        sibling.write_text('x')
        self.assertTrue(any('Unsupported domain' in error for error in
                            preflight.size_failures(root, policy, [sibling.relative_to(root).as_posix()])))

    def test_exact_global_owner_does_not_cover_siblings(self):
        root, policy, source = self.fixture()
        path = source.relative_to(root).as_posix()
        policy['directoryRules'] = {}
        policy['globalOnlyDirectories'] = []
        policy['globalOnlyFiles'] = [path]
        self.assertEqual(preflight.size_failures(root, policy, [path]), [])
        sibling = source.with_name('Unsupported.swift')
        sibling.write_text('x')
        self.assertTrue(any('Unsupported domain' in failure for failure in
                            preflight.size_failures(root, policy, [sibling.relative_to(root).as_posix()])))
        source.unlink()
        self.assertTrue(any('Missing global owner' in failure for failure in
                            preflight.size_failures(root, policy, [])))

    def test_unknown_counter_and_escaping_paths_fail(self):
        with self.assertRaises(ValueError):
            preflight.count_lines('x', 'splitlines')
        for path in ('../outside', '/tmp/outside',
                     './apps/ios/Merian/Core/Network/MerianNetworkClient.swift',
                     'apps//ios/Merian/Core/Network/MerianNetworkClient.swift'):
            with self.assertRaises(ValueError):
                preflight.repository_path(ROOT, path)
        with self.assertRaises(ValueError):
            json.loads('{"version":1,"version":2}', object_pairs_hook=preflight.unique_object)

    def test_candidate_aliases_cannot_bypass_domain_coverage(self):
        root, policy, scan = self.fixture()
        alias = root / 'Alias.swift'
        alias.symlink_to(scan)
        with self.assertRaises(ValueError):
            preflight.candidate_path(root, 'Alias.swift')
        with self.assertRaises(ValueError):
            preflight.candidate_path(root, 'apps/ios/Merian')
        self.assertEqual(preflight.candidate_path(root, scan.relative_to(root).as_posix()), scan)
        case_alias = 'Apps/ios/Merian/Features/Capture/Scan/A.swift'
        if (root / case_alias).exists():
            with self.assertRaises(ValueError):
                preflight.candidate_path(root, case_alias)

    def test_lower_storage_floor_cannot_pass_before_build(self):
        build = preflight.load_build_tools()
        from types import SimpleNamespace
        with patch.object(build, 'check_space'), patch.object(preflight.shutil, 'disk_usage',
                return_value=SimpleNamespace(free=24 * build.GIB)):
            preflight.check_storage(ROOT, False, build)
            with self.assertRaises(RuntimeError):
                preflight.check_storage(ROOT, True, build)


if __name__ == '__main__':
    include_swift = sys.argv[1:] == ["--swift-parity"]
    if sys.argv[1:] and not include_swift:
        raise SystemExit("Usage: test-ios-fast-preflight.py [--swift-parity]")
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(PolicyTests)
    if include_swift:
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(SwiftParityTests))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
