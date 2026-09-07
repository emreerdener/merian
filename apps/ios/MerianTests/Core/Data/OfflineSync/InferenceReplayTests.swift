@testable import Merian
import Testing

@Suite(
    "Inference Replay Tests",
    .serialized,
    .sharedProcessState(.offlineQueueManager)
)
@MainActor
struct InferenceReplayTests {
    @Test func inferenceReplayReconciliationCoalescesConcurrentWakeSources() {
        let manager = OfflineQueueManager.shared
        let originalIsReconciling = manager.isInferenceReplayReconciling
        let originalNeedsTrailingPass =
            manager.inferenceReplayRequestedWhileReconciling
        defer {
            manager.isInferenceReplayReconciling = originalIsReconciling
            manager.inferenceReplayRequestedWhileReconciling =
                originalNeedsTrailingPass
        }

        manager.isInferenceReplayReconciling = false
        manager.inferenceReplayRequestedWhileReconciling = false

        #expect(manager.beginInferenceReplayReconciliation())
        #expect(!manager.beginInferenceReplayReconciliation())
        #expect(!manager.beginInferenceReplayReconciliation())
        #expect(manager.isInferenceReplayReconciling)
        #expect(manager.inferenceReplayRequestedWhileReconciling)

        #expect(manager.finishInferenceReplayReconciliation())
        #expect(!manager.isInferenceReplayReconciling)
        #expect(!manager.inferenceReplayRequestedWhileReconciling)
        #expect(!manager.finishInferenceReplayReconciliation())

        // The single trailing caller can claim a fresh pass immediately.
        #expect(manager.beginInferenceReplayReconciliation())
        #expect(!manager.finishInferenceReplayReconciliation())
    }
}
