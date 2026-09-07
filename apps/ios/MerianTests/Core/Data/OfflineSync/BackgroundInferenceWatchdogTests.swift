import Foundation
@testable import Merian
import Testing

@Suite(
    "Background Inference Watchdog",
    .serialized,
    .sharedProcessState(.offlineQueueManager)
)
@MainActor
struct BackgroundInferenceWatchdogTests {
    @Test func probeReplacementPreservesExactGenerationOwnership() {
        let manager = OfflineQueueManager.shared
        let scanId = "inference-watchdog-replacement-\(UUID().uuidString)"
        let originalGeneration = UUID()
        let replacementGeneration = UUID()
        let dispatchDate = Date(timeIntervalSince1970: 1_700_000_000)
        reset(
            manager,
            scanId: scanId,
            generations: [originalGeneration, replacementGeneration]
        )
        defer {
            reset(
                manager,
                scanId: scanId,
                generations: [originalGeneration, replacementGeneration]
            )
        }

        manager.activeInferenceGenerations[scanId] = originalGeneration
        manager.inferenceDispatchDates[scanId] = dispatchDate
        SyncStateManager.shared.beginInferencing(
            generation: originalGeneration
        )
        manager.scheduleInferenceStatusProbe(
            scanId: scanId,
            generation: originalGeneration
        )

        #expect(manager.inferenceStatusProbeTasks.isOwned(
            scanId,
            by: originalGeneration
        ))

        manager.activeInferenceGenerations[scanId] = replacementGeneration
        SyncStateManager.shared.beginInferencing(
            generation: replacementGeneration
        )
        manager.scheduleInferenceStatusProbe(
            scanId: scanId,
            generation: replacementGeneration
        )

        #expect(!manager.inferenceStatusProbeTasks.isOwned(
            scanId,
            by: originalGeneration
        ))
        #expect(manager.inferenceStatusProbeTasks.isOwned(
            scanId,
            by: replacementGeneration
        ))
        #expect(
            manager.activeInferenceGenerations[scanId]
                == replacementGeneration
        )
        #expect(manager.inferenceDispatchDates[scanId] == dispatchDate)
        #expect(SyncStateManager.shared.phase == .inferencing)
    }

    @Test func liveTaskMatchingUsesParsedScanIdentityAndOpenState() throws {
        let manager = OfflineQueueManager.shared
        let scanId = "watchdog_task_\(UUID().uuidString)"
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let url = try #require(URL(
            string: "https://example.invalid/inference"
        ))

        let currentTask = session.downloadTask(with: url)
        currentTask.taskDescription =
            InferenceURLSessionTaskContract.taskDescription(
                scanId: scanId,
                generation: UUID(),
                ownerUserID: UUID()
            )
        let legacyTask = session.downloadTask(with: url)
        legacyTask.taskDescription = "inference_\(scanId)"
        let otherScanTask = session.downloadTask(with: url)
        otherScanTask.taskDescription =
            InferenceURLSessionTaskContract.taskDescription(
                scanId: "other-\(scanId)",
                generation: UUID(),
                ownerUserID: UUID()
            )
        let malformedTask = session.downloadTask(with: url)
        malformedTask.taskDescription = "inference_v3|invalid"

        #expect(manager.isLiveInferenceTask(currentTask, scanId: scanId))
        #expect(manager.isLiveInferenceTask(legacyTask, scanId: scanId))
        #expect(!manager.isLiveInferenceTask(otherScanTask, scanId: scanId))
        #expect(!manager.isLiveInferenceTask(malformedTask, scanId: scanId))

        currentTask.cancel()

        #expect(!manager.isLiveInferenceTask(currentTask, scanId: scanId))
    }

    @Test func watchdogRevalidatesBeforeRetirementAndRetry() throws {
        let source = OfflineSyncTestSupport.normalizedSource(
            try OfflineSyncTestSupport.loadRepositorySource(
                at: Self.watchdogPath
            )
        )
        let schedule = try #require(source.range(
            of: "func scheduleInferenceStatusProbe("
        ))
        let recovery = try #require(source.range(
            of: "let recovered = await self.recoverCompletedInferenceFromServer(",
            range: schedule.upperBound..<source.endIndex
        ))
        let recoveredCancellation = try #require(source.range(
            of: "let cancelledCount = await self.cancelActiveInferenceTasks(",
            range: recovery.upperBound..<source.endIndex
        ))
        let recoveredProbeRevalidation = try #require(source.range(
            of: "guard self.inferenceStatusProbeTasks.isCurrent(",
            range: recoveredCancellation.upperBound..<source.endIndex
        ))
        let recoveredGenerationRevalidation = try #require(source.range(
            of: "self.activeInferenceGenerations[scanId] == generation else",
            range: recoveredProbeRevalidation.upperBound..<source.endIndex
        ))
        let recoveredClear = try #require(source.range(
            of: "guard self.inferenceStatusProbeTasks.clearIfCurrent(",
            range: recoveredGenerationRevalidation.upperBound..<source.endIndex
        ))
        let recoveredFinish = try #require(source.range(
            of: "self.finishInferenceGeneration(",
            range: recoveredClear.upperBound..<source.endIndex
        ))
        let watchdogDeadline = try #require(source.range(
            of: "scheduleInferenceStatusProbe: watchdog firing",
            range: recoveredFinish.upperBound..<source.endIndex
        ))
        let watchdogCancellation = try #require(source.range(
            of: "let cancelledCount = await self.cancelActiveInferenceTasks(",
            range: watchdogDeadline.upperBound..<source.endIndex
        ))
        let watchdogProbeRevalidation = try #require(source.range(
            of: "guard self.inferenceStatusProbeTasks.isCurrent(",
            range: watchdogCancellation.upperBound..<source.endIndex
        ))
        let watchdogGenerationRevalidation = try #require(source.range(
            of: "self.activeInferenceGenerations[scanId] == generation else",
            range: watchdogProbeRevalidation.upperBound..<source.endIndex
        ))
        let watchdogClear = try #require(source.range(
            of: "guard self.inferenceStatusProbeTasks.clearIfCurrent(",
            range: watchdogGenerationRevalidation.upperBound..<source.endIndex
        ))
        let watchdogFinish = try #require(source.range(
            of: "self.finishInferenceGeneration(",
            range: watchdogClear.upperBound..<source.endIndex
        ))
        let ownerRelease = try #require(source.range(
            of: "guard self.activeInferenceGenerations[scanId] == nil",
            range: watchdogFinish.upperBound..<source.endIndex
        ))
        let retry = try #require(source.range(
            of: "await self.handleInferenceRetry(",
            range: ownerRelease.upperBound..<source.endIndex
        ))

        #expect(recovery.lowerBound < recoveredCancellation.lowerBound)
        #expect(
            recoveredCancellation.lowerBound
                < recoveredProbeRevalidation.lowerBound
        )
        #expect(
            recoveredProbeRevalidation.lowerBound
                < recoveredGenerationRevalidation.lowerBound
        )
        #expect(
            recoveredGenerationRevalidation.lowerBound
                < recoveredClear.lowerBound
        )
        #expect(recoveredClear.lowerBound < recoveredFinish.lowerBound)
        #expect(recoveredFinish.lowerBound < watchdogDeadline.lowerBound)
        #expect(watchdogDeadline.lowerBound < watchdogCancellation.lowerBound)
        #expect(
            watchdogCancellation.lowerBound
                < watchdogProbeRevalidation.lowerBound
        )
        #expect(
            watchdogProbeRevalidation.lowerBound
                < watchdogGenerationRevalidation.lowerBound
        )
        #expect(
            watchdogGenerationRevalidation.lowerBound
                < watchdogClear.lowerBound
        )
        #expect(watchdogClear.lowerBound < watchdogFinish.lowerBound)
        #expect(watchdogFinish.lowerBound < ownerRelease.lowerBound)
        #expect(ownerRelease.lowerBound < retry.lowerBound)
    }

    private func reset(
        _ manager: OfflineQueueManager,
        scanId: String,
        generations: [UUID]
    ) {
        manager.inferenceStatusProbeTasks.cancel(scanId)
        manager.activeInferenceGenerations[scanId] = nil
        manager.inferenceDispatchDates[scanId] = nil
        for generation in generations {
            manager.retiredInferenceGenerations.remove(generation)
        }
        SyncStateManager.shared.forceIdle()
    }

    private static let watchdogPath =
        "apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceWatchdog.swift"
}
