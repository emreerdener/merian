import Foundation
@testable import Merian
import Testing

@Suite(
    "Background Inference Completion",
    .serialized,
    .sharedProcessState(.offlineQueueManager)
)
@MainActor
struct BackgroundInferenceCompletionTests {
    @Test func cancelledTaskRetiresExactGenerationAndProbe() async {
        let manager = OfflineQueueManager.shared
        let scanId = "cancelled-inference-task-\(UUID().uuidString)"
        let generation = UUID()
        reset(manager, scanId: scanId, generations: [generation])
        defer {
            reset(manager, scanId: scanId, generations: [generation])
        }

        manager.activeInferenceGenerations[scanId] = generation
        manager.inferenceDispatchDates[scanId] = Date()
        SyncStateManager.shared.beginInferencing(generation: generation)
        manager.inferenceStatusProbeTasks.replace(
            for: scanId,
            ownerGeneration: generation
        ) { _ in
            Task {
                try? await Task.sleep(for: .seconds(30))
            }
        }

        await manager.handleInferenceTaskNetworkFailure(
            scanId: scanId,
            generation: generation,
            error: URLError(.cancelled)
        )

        #expect(manager.activeInferenceGenerations[scanId] == nil)
        #expect(manager.inferenceDispatchDates[scanId] == nil)
        #expect(!manager.inferenceStatusProbeTasks.isOwned(
            scanId,
            by: generation
        ))
        #expect(manager.retiredInferenceGenerations.contains(generation))
        #expect(SyncStateManager.shared.phase == .idle)
    }

    @Test func staleNetworkFailureCannotClearReplacementGeneration() async {
        let manager = OfflineQueueManager.shared
        let scanId = "stale-inference-failure-\(UUID().uuidString)"
        let staleGeneration = UUID()
        let replacementGeneration = UUID()
        let dispatchDate = Date(timeIntervalSince1970: 1_700_000_000)
        reset(
            manager,
            scanId: scanId,
            generations: [staleGeneration, replacementGeneration]
        )
        defer {
            reset(
                manager,
                scanId: scanId,
                generations: [staleGeneration, replacementGeneration]
            )
        }

        manager.activeInferenceGenerations[scanId] = replacementGeneration
        manager.inferenceDispatchDates[scanId] = dispatchDate
        SyncStateManager.shared.beginInferencing(
            generation: replacementGeneration
        )
        manager.inferenceStatusProbeTasks.replace(
            for: scanId,
            ownerGeneration: replacementGeneration
        ) { _ in
            Task {
                try? await Task.sleep(for: .seconds(30))
            }
        }

        await manager.handleInferenceTaskNetworkFailure(
            scanId: scanId,
            generation: staleGeneration,
            error: URLError(.networkConnectionLost)
        )

        #expect(
            manager.activeInferenceGenerations[scanId]
                == replacementGeneration
        )
        #expect(manager.inferenceDispatchDates[scanId] == dispatchDate)
        #expect(manager.inferenceStatusProbeTasks.isOwned(
            scanId,
            by: replacementGeneration
        ))
        #expect(!manager.retiredInferenceGenerations.contains(staleGeneration))
        #expect(SyncStateManager.shared.phase == .inferencing)
    }

    @Test func staleResultCleansFileWithoutTouchingReplacement() async throws {
        let manager = OfflineQueueManager.shared
        let scanId = "stale-inference-result-\(UUID().uuidString)"
        let staleGeneration = UUID()
        let replacementGeneration = UUID()
        let dispatchDate = Date(timeIntervalSince1970: 1_700_000_000)
        let resultURL = URL.temporaryDirectory.appendingPathComponent(
            "\(UUID().uuidString).json"
        )
        try Data("{}".utf8).write(to: resultURL)
        reset(
            manager,
            scanId: scanId,
            generations: [staleGeneration, replacementGeneration]
        )
        defer {
            try? FileManager.default.removeItem(at: resultURL)
            reset(
                manager,
                scanId: scanId,
                generations: [staleGeneration, replacementGeneration]
            )
        }

        manager.activeInferenceGenerations[scanId] = replacementGeneration
        manager.inferenceCompletionGenerations[scanId] = replacementGeneration
        manager.inferenceDispatchDates[scanId] = dispatchDate
        SyncStateManager.shared.beginInferencing(
            generation: replacementGeneration
        )
        manager.inferenceStatusProbeTasks.replace(
            for: scanId,
            ownerGeneration: replacementGeneration
        ) { _ in
            Task {
                try? await Task.sleep(for: .seconds(30))
            }
        }

        await manager.processInferenceDownloadResult(
            scanId: scanId,
            generation: staleGeneration,
            resultFileURL: resultURL,
            statusCode: 200
        )

        #expect(!FileManager.default.fileExists(atPath: resultURL.path))
        #expect(
            manager.activeInferenceGenerations[scanId]
                == replacementGeneration
        )
        #expect(manager.inferenceDispatchDates[scanId] == dispatchDate)
        #expect(manager.inferenceStatusProbeTasks.isOwned(
            scanId,
            by: replacementGeneration
        ))
        #expect(
            manager.inferenceCompletionGenerations[scanId]
                == replacementGeneration
        )
        #expect(SyncStateManager.shared.phase == .inferencing)
    }

    private func reset(
        _ manager: OfflineQueueManager,
        scanId: String,
        generations: [UUID]
    ) {
        manager.inferenceStatusProbeTasks.cancel(scanId)
        manager.inferenceRetryTasks.cancel(scanId)
        manager.serverIngestionPollTasks.cancel(scanId)
        manager.inferenceCompletionGenerations[scanId] = nil
        manager.activeInferenceGenerations[scanId] = nil
        manager.inferenceDispatchDates[scanId] = nil
        for generation in generations {
            manager.retiredInferenceGenerations.remove(generation)
        }
        SyncStateManager.shared.forceIdle()
    }
}
