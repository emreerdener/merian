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

    def test_original_completion_owners_keep_exact_existing_limits(self):
        actual = preflight.load_policy(ROOT)
        expected = {'apps/ios/Merian/Core/Network/MerianNetworkClient.swift': {'counter': 'physical', 'ceiling': 600}, 'apps/ios/Merian/Core/AI/Inference/Request/InferenceLiveRequestService.swift': {'counter': 'segments', 'ceiling': 600}, 'apps/ios/Merian/Core/AI/Inference/Result/InferenceLiveResultService.swift': {'counter': 'segments', 'ceiling': 600}, 'apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePipelineCoordinator.swift': {'counter': 'segments', 'ceiling': 600}, 'apps/ios/Merian/Core/AI/InferenceProcessingActor.swift': {'counter': 'physical', 'ceiling': 180}, 'apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+Inference.swift': {'counter': 'physical', 'ceiling': 600}, 'apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+ScanRecordSupport.swift': {'counter': 'physical', 'ceiling': 220}, 'apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+LiveScanPersistence.swift': {'counter': 'physical', 'ceiling': 350}, 'apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+OfflineFinalization.swift': {'counter': 'physical', 'ceiling': 250}, 'apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundInference/BackgroundInferenceFinalizationService.swift': {'counter': 'physical', 'ceiling': 200}, 'apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceCompletion.swift': {'counter': 'segments', 'ceiling': 600}, 'apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundTransfer/OfflineQueueManager+BackgroundTerminalRouting.swift': {'counter': 'segments', 'ceiling': 600}}
        expected.update({
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationAnalysisReviewTicket.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Transport/ObservationHistoryMutationTransport.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Hardware/EnvironmentContext/Services/EnvironmentLocationController.swift': dict(counter='segments', ceiling=375),
            'apps/ios/Merian/Core/Data/Database/FileIOActor.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/AppDIContainer.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/OfflineSync/Persistence/LibraryMutationInventory.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Features/Profile/Settings/Components/LibraryTransitionPresentation.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationReanalysisFileStore.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationReanalysisFileStore+Input.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationReanalysisFileStore+InputBootstrap.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationReanalysisInputReceipt.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationReanalysisInputLedger.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationReanalysisInputPersistence.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationReanalysisErasureOwner.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/StoreRecovery/Services/ModelContainerBootstrapper.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Coordinators/AuthSessionRecoveryCoordinator.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Models/LibraryTransitionIssue.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Coordinators/AuthSessionBootstrapCoordinator.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Coordinators/AuthSessionBootstrapCoordinationDependencies.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Coordinators/LibrarySignOutRecoveryCoordinator.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Coordinators/AuthLocalSignOutCoordinator.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Security/LibrarySignOutJournal.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/App/MerianApp.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Coordinators/AccountDeletionCoordinationDependencies.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Coordinators/AuthRuntimeState.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Coordinators/AuthSessionLifecycleCoordinationDependencies.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Coordinators/AuthSessionLifecycleCoordinator.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Services/AuthSessionLifecycleLiveProvider.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Services/AuthSessionLifecycleLiveProvider+Live.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Security/AccountDeletion/Stores/AccountDeletionLocalCleanupStore.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Features/Profile/Settings/Services/AccountSettingsDependencies.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Features/Profile/Settings/ViewModels/DeleteAccountViewModel.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Features/Profile/Settings/Views/DeleteAccountSheet.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Coordinators/AccountDeletionCoordinator.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Coordinators/AccountDeletionRecoveryCoordinator.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Network/Auth/Coordinators/AccountDeletionWorkflow.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Security/AccountDeletion/Stores/AccountDeletionRecoveryCapabilityStore.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Core/Data/Database/ScanLibraryPurgeService.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationReanalysisLocalVideoInput.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationVideoSubmissionService.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationVideoResumeStore.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationVideoResumeSubmission.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/App/Composition/PreparedHistoryReanalysisComposition+Audio.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/App/Composition/PreparedHistoryReanalysisComposition+Video.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationVideoSavedStatus.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationAudioStatusIndex.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationAudioStatusOwner.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Core/Data/OfflineSync/Services/OfflineQueueManager+VideoSubmission.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Core/Data/OfflineSync/Services/ObservationVideoUploadOwner.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Core/Data/Database/LocalScanRecordFactory.swift': dict(counter='physical', ceiling=150),
            'apps/ios/Merian/Core/Data/Database/LocalScanRecordFactory+InitialCompletion.swift': dict(counter='physical', ceiling=150),
        })
        root, policy, _ = self.fixture()
        for path, rule in expected.items():
            self.assertEqual(actual['fileRules'][path], rule)
            policy['fileRules'][path] = dict(counter=rule['counter'], ceiling=2)
            file = root / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('a\nb')
            self.assertEqual(preflight.size_failures(root, policy, [path]), [])
            file.write_text('a\nb\nc\n')
            self.assertTrue(preflight.size_failures(root, policy, [path]))
            file.write_text('a\nb')
        self.assertNotIn('apps/ios/Merian/Core/AI/Inference/Unrelated.swift', actual['globalOnlyFiles'])

    def test_observation_owners_keep_existing_domain_limits(self):
        actual = preflight.load_policy(ROOT)
        expected = {
            'apps/ios/Merian/Core/Data/OfflineSync/Persistence/OfflineQueueDurableAuthorityReader+Observation.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Core/Data/OfflineSync/Policies/OfflineScanJobMetadataContract.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Core/Network/Transport/ScanObservationResponse.swift': dict(counter='physical', ceiling=600),
            'apps/ios/Merian/Features/Insights/Content/Components/Queued/QueuedObservationStatusView.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Features/Insights/Content/Components/Queued/QueuedRetryStatusView.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Features/Insights/Content/Models/QueuedRetryPresentation.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Features/Insights/Content/Services/QueuedContentDependencies+Observation.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Features/Insights/Content/Services/QueuedContentDependencies.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Features/Insights/Content/ViewModels/QueuedContentViewModel.swift': dict(counter='segments', ceiling=600),
            'apps/ios/Merian/Features/Insights/Content/Views/QueuedContentView.swift': dict(counter='segments', ceiling=600),
        }
        for path, rule in expected.items():
            self.assertEqual(actual['fileRules'][path], rule)

    def test_retained_display_owners_keep_exact_existing_limits(self):
        actual = preflight.load_policy(ROOT)
        paths = [
            'apps/ios/Merian/Features/Insights/IdentificationReview/Candidates/Views/CandidateSwipeModal.swift',
            'apps/ios/Merian/Features/Insights/Media/Carousel/Builders/CarouselPageBuilder.swift',
            'apps/ios/Merian/Core/AI/InferenceEngine.swift',
            'apps/ios/Merian/Core/AI/Inference/Hydration/InferenceHistoricalLoadCoordinator.swift',
            'apps/ios/Merian/Features/Insights/Toolbars/BottomToolbar/InsightBottomToolbar.swift',
            'apps/ios/Merian/Features/Insights/Shell/Models/InsightFieldChatMedia.swift',
            'apps/ios/Merian/Features/Insights/Media/Carousel/Builders/InsightImageGalleryBuilder.swift',
            'apps/ios/Merian/Features/Insights/Shell/ViewModels/InsightSheetViewModel+Capabilities.swift',
            'apps/ios/Merian/Features/Insights/Media/Utilities/InsightSheetViewModel+MediaExport.swift',
            'apps/ios/Merian/Features/Insights/Shell/ViewModels/InsightSheetViewModel+MediaPresentation.swift',
            'apps/ios/Merian/Features/Insights/Shell/Views/LocalScanInsightLoader.swift',
            'apps/ios/Merian/Features/Insights/Shell/Services/NativeInitialInsightMedia.swift',
            'apps/ios/Merian/Features/Insights/IdentificationReview/Candidates/Views/OriginalCaptureExpandedView.swift',
            'apps/ios/Merian/Features/Insights/IdentificationReview/Candidates/Components/Card/OriginalCapturePiPView.swift',
        ]
        root, policy, _ = self.fixture()
        for path in paths:
            self.assertEqual(actual['fileRules'][path], dict(counter='segments', ceiling=600))
            policy['fileRules'][path] = dict(counter='segments', ceiling=2)
            file = root / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('a\nb')
            self.assertEqual(preflight.size_failures(root, policy, [path]), [])
            file.write_text('a\nb\n')
            self.assertTrue(any('segments > 2' in message for message in preflight.size_failures(root, policy, [path])))
            file.write_text('a\nb')
        self.assertIn('apps/ios/Merian/Core/Models/ActiveScanMedia.swift', actual['globalOnlyFiles'])
        self.assertNotIn('apps/ios/Merian/Core/Models/Unrelated.swift', actual['globalOnlyFiles'])

    def test_retained_video_producer_keeps_global_ceiling(self):
        path = 'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationRetainedVideoClipProducer.swift'
        actual = preflight.load_policy(ROOT)
        self.assertIn(path, actual['globalOnlyFiles'])
        self.assertEqual(actual['globalCeiling'], 600)
        root, policy, _ = self.fixture()
        policy['globalOnlyFiles'].append(path)
        file = root / path
        file.parent.mkdir(parents=True)
        file.write_text('a\nb\nc\n')
        self.assertEqual(preflight.size_failures(root, policy, [path]), [])
        file.write_text('a\nb\nc\nd\n')
        self.assertTrue(preflight.size_failures(root, policy, [path]))

    def test_native_photo_preflight_coverage_has_exact_bounded_network_and_image_owners(self):
        root, policy, _ = self.fixture()
        for path in [
            'apps/ios/Merian/Core/Data/AnalysisHistory/AnalysisRecoveryPresentation.swift',
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationReanalysisRecoveryPresentationStore.swift',
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationReanalysisRecoveredResult.swift',
            'apps/ios/Merian/Core/Data/OfflineSync/Services/ObservationAudioExecutionOwner.swift',
            'apps/ios/Merian/Core/Data/OfflineSync/Services/ObservationVideoExecutionOwner.swift',
            'apps/ios/Merian/Features/Insights/History/ViewModels/AnalysisRecoveryCheckingModel.swift',
            'apps/ios/Merian/Features/Insights/History/Services/AnalysisRecoveryCheckingAccess.swift',
            'apps/ios/Merian/Features/Insights/History/Services/ReanalysisStatusDependencies.swift',
            'apps/ios/Merian/Features/Insights/History/Services/ReanalysisSavedPhotoAccess.swift',
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationReanalysisAdmissionStore.swift',
            'apps/ios/Merian/Features/Insights/History/ViewModels/ReanalysisStatusViewModel.swift',
            'apps/ios/Merian/Features/Insights/History/Views/ReanalysisStatusSheet.swift',
            'apps/ios/Merian/App/UITesting/UITestSeedCoordinator+AudioReanalysisSheet.swift',
            'apps/ios/Merian/App/UITesting/UITestSeedCoordinator+QueuedObservation.swift',
            'apps/ios/Merian/App/UITesting/UITestSeedCoordinator+NativeRecovery.swift',
            'apps/ios/Merian/App/UITesting/NativeRecoveryUITestPresentation.swift',
            'apps/ios/Merian/App/UITesting/NativeRecoveryUIHistoryFixture.swift',
            'apps/ios/Merian/App/UITesting/ReanalysisRecoveryUIFixture.swift',
            'apps/ios/Merian/App/UITesting/ReanalysisRecoveryUISeed.swift',
            'apps/ios/Merian/App/UITesting/ReanalysisRecoveryUIResult.swift',
            'apps/ios/Merian/App/UITesting/ReanalysisRecoveryUIHistory.swift',
            'apps/ios/Merian/App/UITesting/InitialMediaHistoryUIInput.swift',
            'apps/ios/Merian/App/UITesting/InitialMediaHistoryUISubmission.swift',
            'apps/ios/Merian/App/UITesting/InitialMediaHistoryUIFixture.swift',
            'apps/ios/Merian/App/UITesting/InitialMediaHistoryUITestPresentation.swift',
            'apps/ios/Merian/App/UITesting/ReanalysisRecoveryUITestPresentation.swift',
            'apps/ios/Merian/Core/Media/AudioPlaybackFilePlayer.swift',
            'apps/ios/Merian/Core/Media/MemoryVideoAsset.swift',
            'apps/ios/Merian/Core/Data/AnalysisHistory/ObservationHistoryEnrollmentOwner.swift',
            'apps/ios/Merian/Core/Data/Database/ScanRepository.swift',
            'apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+NonBiologicalRetention.swift',
            'apps/ios/Merian/Features/Scans/Shared/Services/ScanDeletionService.swift',
            'apps/ios/Merian/Models/Species/SpeciesObservationModels.swift',
            'apps/ios/Merian/Models/ActiveSchema/OfflineQueuedScan.swift',
            'apps/ios/Merian/Models/Schema/SchemaV68.swift',
            'apps/ios/Merian/Core/Data/Images/Policies/ImagePreparationPolicy.swift',
            'apps/ios/Merian/Core/Data/Images/MediaPreparationActor.swift',
            'apps/ios/Merian/Core/Media/ImageCropProcessor.swift',
            'apps/ios/Merian/Core/Network/Inference/IdentificationPreflight.swift',
            'apps/ios/Merian/Core/Network/Inference/InitialAnalysisCanonical.swift',
            'apps/ios/Merian/Core/Network/Inference/InitialCompletionDocuments.swift',
            'apps/ios/Merian/Core/Network/Inference/InitialCompletionSchema.swift',
            'apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+IdentificationPreflight.swift',
            'apps/ios/Merian/Core/Network/Models/ObservationAnalysis/InitialPhotoAllocationRequest.swift',
            'apps/ios/Merian/Core/Network/Models/ObservationAnalysis/InitialPhotoTransferRequest.swift',
            'apps/ios/Merian/Core/Network/Models/ObservationAnalysis/InitialPhotoAllocationRoleReply.swift',
            'apps/ios/Merian/Core/Network/Models/ObservationAnalysis/InitialPhotoUploadStatus.swift',
            'apps/ios/Merian/Core/Network/Models/ObservationAnalysis/InitialPhotoUploadDestination.swift',
            'apps/ios/Merian/Core/Network/Models/ObservationAnalysis/InitialPhotoUploadTicket.swift',
            'apps/ios/Merian/Core/Network/Transport/InitialPhotoAllocationTransport.swift',
            'apps/ios/Merian/Core/Network/Transport/PinnedNetworkDataTaskState.swift',
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

    def test_test_detector_preserves_configuration_segment_ceiling(self):
        path = 'apps/ios/Merian/Configuration/TestExecutionCoordinator.swift'
        actual = preflight.load_policy(ROOT)
        self.assertEqual(actual['fileRules'][path], dict(counter='segments', ceiling=600))
        root, policy, _ = self.fixture()
        policy['fileRules'][path] = dict(counter='segments', ceiling=2)
        source = root / path
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text('a\nb')
        self.assertEqual(preflight.size_failures(root, policy, [path]), [])
        source.write_text('a\nb\n')
        self.assertTrue(any('segments > 2' in error for error in
                            preflight.size_failures(root, policy, [path])))
        source.write_text('a\nb')
        sibling = source.with_name('UncoveredConfiguration.swift')
        sibling.write_text('x')
        self.assertTrue(any('Unsupported domain' in error for error in
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
