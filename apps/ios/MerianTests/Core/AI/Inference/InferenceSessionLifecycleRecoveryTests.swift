import Foundation
import Testing

@testable import Merian

private struct QueuedResultRecoveryCase {
    let retainedScanId: String
    let callbackScanId: String
    let resultScanId: String
    let activeScanId: String?
}

private struct QueuedRecordRecoveryCase {
    let retainedScanId: String
    let callbackScanId: String
    let recordScanId: String
    let activeScanId: String?
}

@MainActor
@Suite(
    "Inference Session Lifecycle Recovery",
    .timeLimit(.minutes(1))
)
struct InferenceLifecycleRecoveryTests {
    @Test func recoveredBackgroundTransfersExactOwnerBeforePublication() async {
        let harness = InferenceSessionLifecycleHarness()
        let scanId = "scan-a"
        let releasedAttempt = UUID()
        let releasedForeground = UUID()
        let displacedTask = Task<Void, Error> {
            try await Task.sleep(for: .seconds(60))
        }
        harness.attempt.replaceTask(displacedTask)
        harness.attempt.activate(
            scanId: scanId,
            attemptGeneration: releasedAttempt,
            foregroundGeneration: releasedForeground
        )
        harness.attempt.setRecoverablePresentationScanId(scanId)
        harness.presentation.activate(
            scanId: scanId,
            attemptGeneration: releasedAttempt,
            modality: .visual
        )
        harness.state.setProcessing(true)
        harness.state.replaceSpeciesData(
            inferenceSessionLifecycleSpeciesData(
                scanId: scanId,
                commonName: "Waiting"
            )
        )
        let recovered = inferenceSessionLifecycleSpeciesData(
            scanId: scanId,
            commonName: "Recovered"
        )

        let didCommit = harness.coordinator.commitRecoveredBackgroundResult(
            for: scanId,
            replacingAttemptGeneration: releasedAttempt,
            expectedForegroundGeneration: releasedForeground,
            speciesData: recovered
        )

        #expect(didCommit)
        #expect(harness.attempt.activeScanId == nil)
        #expect(harness.attempt.activeAttemptGeneration == nil)
        #expect(harness.attempt.activeForegroundGeneration == nil)
        #expect(harness.attempt.recoverablePresentationScanId == nil)
        #expect(harness.attempt.task == nil)
        #expect(displacedTask.isCancelled)
        #expect(harness.state.speciesData?.commonName == "Recovered")
        #expect(!harness.state.isProcessing)

        let replacementAttempt = UUID()
        let replacementForeground = UUID()
        let replacementTask = Task<Void, Error> {
            try await Task.sleep(for: .seconds(60))
        }
        let replacement = inferenceSessionLifecycleSpeciesData(
            scanId: scanId,
            commonName: "Replacement"
        )
        harness.attempt.replaceTask(replacementTask)
        harness.attempt.activate(
            scanId: scanId,
            attemptGeneration: replacementAttempt,
            foregroundGeneration: replacementForeground
        )
        harness.state.replaceSpeciesData(replacement)

        let staleDidCommit =
            harness.coordinator.commitRecoveredBackgroundResult(
                for: scanId,
                replacingAttemptGeneration: releasedAttempt,
                expectedForegroundGeneration: releasedForeground,
                speciesData: recovered
            )

        #expect(!staleDidCommit)
        #expect(harness.attempt.activeAttemptGeneration == replacementAttempt)
        #expect(
            harness.attempt.activeForegroundGeneration == replacementForeground
        )
        #expect(harness.attempt.task != nil)
        #expect(!replacementTask.isCancelled)
        #expect(harness.state.speciesData?.commonName == "Replacement")
        replacementTask.cancel()
        _ = await displacedTask.result
        _ = await replacementTask.result
    }

    @Test func recoveredQueuedResultRequiresEveryPresentationIdentity() {
        let cases = [
            QueuedResultRecoveryCase(
                retainedScanId: "retained",
                callbackScanId: "stale",
                resultScanId: "stale",
                activeScanId: nil
            ),
            QueuedResultRecoveryCase(
                retainedScanId: "retained",
                callbackScanId: "retained",
                resultScanId: "other",
                activeScanId: nil
            ),
            QueuedResultRecoveryCase(
                retainedScanId: "retained",
                callbackScanId: "retained",
                resultScanId: "retained",
                activeScanId: "replacement"
            )
        ]

        for testCase in cases {
            let harness = InferenceSessionLifecycleHarness()
            harness.attempt.setRecoverablePresentationScanId(
                testCase.retainedScanId
            )
            if let activeScanId = testCase.activeScanId {
                harness.attempt.activate(
                    scanId: activeScanId,
                    attemptGeneration: UUID(),
                    foregroundGeneration: UUID()
                )
            }
            harness.state.replaceSpeciesData(
                inferenceSessionLifecycleSpeciesData(
                    scanId: "existing",
                    commonName: "Existing"
                )
            )

            let didCommit = harness.coordinator.commitRecoveredQueuedResult(
                for: testCase.callbackScanId,
                speciesData: inferenceSessionLifecycleSpeciesData(
                    scanId: testCase.resultScanId,
                    commonName: "Stale"
                )
            )

            #expect(!didCommit)
            #expect(
                harness.attempt.recoverablePresentationScanId
                    == testCase.retainedScanId
            )
            #expect(harness.attempt.activeScanId == testCase.activeScanId)
            #expect(harness.state.speciesData?.commonName == "Existing")
        }
    }

    @Test func recoveredQueuedResultClearsMatchingActivePresentation() async {
        let harness = InferenceSessionLifecycleHarness()
        let scanId = "scan-a"
        let displacedTask = Task<Void, Error> {
            try await Task.sleep(for: .seconds(60))
        }
        harness.attempt.replaceTask(displacedTask)
        harness.attempt.setRecoverablePresentationScanId(scanId)
        harness.attempt.activate(
            scanId: scanId,
            attemptGeneration: UUID(),
            foregroundGeneration: UUID()
        )
        harness.state.setProcessing(true)
        let recovered = inferenceSessionLifecycleSpeciesData(
            scanId: "SCAN-A",
            commonName: "Recovered"
        )

        let didCommit = harness.coordinator.commitRecoveredQueuedResult(
            for: scanId,
            speciesData: recovered
        )

        #expect(didCommit)
        #expect(harness.attempt.activeScanId == nil)
        #expect(harness.attempt.activeAttemptGeneration == nil)
        #expect(harness.attempt.activeForegroundGeneration == nil)
        #expect(harness.attempt.recoverablePresentationScanId == nil)
        #expect(harness.attempt.task == nil)
        #expect(displacedTask.isCancelled)
        #expect(harness.state.speciesData?.commonName == "Recovered")
        #expect(!harness.state.isProcessing)
        _ = await displacedTask.result
    }

    @Test func recoveredQueuedRecordLoadsOnlyExactRetainedPresentation() {
        let harness = InferenceSessionLifecycleHarness()
        let scanId = "scan-a"
        harness.attempt.setRecoverablePresentationScanId(scanId)
        var loadCount = 0
        var recoverableIdAtLoad: String? = "not-loaded"

        let didCommit = harness.coordinator.commitRecoveredQueuedRecord(
            for: scanId,
            recordScanId: scanId
        ) {
            loadCount += 1
            recoverableIdAtLoad =
                harness.attempt.recoverablePresentationScanId
            harness.attempt.setRecoverablePresentationScanId("replacement")
        }

        #expect(didCommit)
        #expect(loadCount == 1)
        #expect(recoverableIdAtLoad == nil)
        #expect(
            harness.attempt.recoverablePresentationScanId == "replacement"
        )
    }

    @Test func recoveredQueuedRecordRequiresEveryPresentationIdentity() {
        let cases = [
            QueuedRecordRecoveryCase(
                retainedScanId: "retained",
                callbackScanId: "stale",
                recordScanId: "stale",
                activeScanId: nil
            ),
            QueuedRecordRecoveryCase(
                retainedScanId: "retained",
                callbackScanId: "retained",
                recordScanId: "other",
                activeScanId: nil
            ),
            QueuedRecordRecoveryCase(
                retainedScanId: "retained",
                callbackScanId: "retained",
                recordScanId: "retained",
                activeScanId: "replacement"
            )
        ]

        for testCase in cases {
            let harness = InferenceSessionLifecycleHarness()
            harness.attempt.setRecoverablePresentationScanId(
                testCase.retainedScanId
            )
            if let activeScanId = testCase.activeScanId {
                harness.attempt.activate(
                    scanId: activeScanId,
                    attemptGeneration: UUID(),
                    foregroundGeneration: UUID()
                )
            }
            var loadCount = 0

            let didCommit = harness.coordinator.commitRecoveredQueuedRecord(
                for: testCase.callbackScanId,
                recordScanId: testCase.recordScanId
            ) {
                loadCount += 1
            }

            #expect(!didCommit)
            #expect(loadCount == 0)
            #expect(
                harness.attempt.recoverablePresentationScanId
                    == testCase.retainedScanId
            )
            #expect(harness.attempt.activeScanId == testCase.activeScanId)
        }
    }
}
