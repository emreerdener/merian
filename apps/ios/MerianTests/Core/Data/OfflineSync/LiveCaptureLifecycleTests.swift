import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite(
    "Live Capture Lifecycle Tests",
    .serialized,
    .sharedProcessState(.offlineQueueManager)
)
@MainActor
struct LiveCaptureLifecycleTests {
    @Test func testForegroundInferenceOwnershipOutlivesBodyUploadHandoff() {
        let manager = OfflineQueueManager.shared
        let scanId = UUID().uuidString
        let staleGeneration = UUID()
        let currentGeneration = UUID()
        let originalIsOnline = manager.isOnline
        manager.isOnline = false
        defer {
            manager.isOnline = originalIsOnline
            manager.deferredLiveUploadScanIds.remove(scanId)
            manager.foregroundInferenceGenerations.removeValue(forKey: scanId)
        }
        manager.deferredLiveUploadScanIds.insert(scanId)
        manager.foregroundInferenceGenerations[scanId] = currentGeneration

        manager.releaseDeferredLiveUpload(
            scanId: scanId,
            foregroundInferenceGeneration: staleGeneration,
            reason: "unit_test_stale_body_sent"
        )
        #expect(
            manager.deferredLiveUploadScanIds.contains(scanId),
            "A delayed callback must not release replacement upload work"
        )

        manager.releaseDeferredLiveUpload(
            scanId: scanId,
            foregroundInferenceGeneration: currentGeneration,
            reason: "unit_test_body_sent"
        )
        #expect(!manager.deferredLiveUploadScanIds.contains(scanId))
        #expect(
            manager.foregroundInferenceScanIds.contains(scanId),
            "Foreground inference must retain sole model-call ownership"
        )
    }

    @Test func staleForegroundGenerationCannotClearReplacementQueueWork() async throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let originalIsOnline = manager.isOnline
        let originalUnsyncedItemsCount = manager.unsyncedItemsCount
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let scanId = UUID().uuidString.lowercased()
        let staleGeneration = UUID()
        let replacementGeneration = UUID()
        manager.isOnline = false
        manager.modelContext = context
        defer {
            manager.isOnline = originalIsOnline
            manager.foregroundInferenceGenerations.removeValue(forKey: scanId)
            manager.inferenceRetryTasks.cancel(scanId)
            manager.modelContext = originalContext
            manager.unsyncedItemsCount = originalUnsyncedItemsCount
        }

        context.insert(OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .pending
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON: InferenceGenerationMetadataContract.json(
                for: replacementGeneration
            )
        ))
        try context.save()
        manager.foregroundInferenceGenerations[scanId] = replacementGeneration
        let replacementRetryToken = manager.inferenceRetryTasks.replace(
            for: scanId,
            ownerGeneration: replacementGeneration
        ) { _ in
            Task {
                try? await Task.sleep(for: .seconds(30))
            }
        }

        let staleDidRelease = await manager.endForegroundInference(
            scanId: scanId,
            generation: staleGeneration,
            resumeBackground: false,
            reason: "unit_test_stale_release"
        )

        // Reproduce the stale process-local view that motivated the durable
        // fence: A appears current in memory after the job advances to B.
        manager.foregroundInferenceGenerations[scanId] = staleGeneration
        let staleCacheDidRelease = await manager.endForegroundInference(
            scanId: scanId,
            generation: staleGeneration,
            resumeBackground: false,
            reason: "unit_test_stale_cache_release"
        )
        let staleDidDelete = await manager.deleteQueuedScan(
            scanId: scanId,
            foregroundInferenceExpectation:
                ForegroundInferenceGenerationExpectation(
                    generation: staleGeneration
                )
        )
        manager.foregroundInferenceGenerations[scanId] = replacementGeneration

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        #expect(!staleDidRelease)
        #expect(!staleCacheDidRelease)
        #expect(!staleDidDelete)
        #expect(try context.fetch(descriptor).first != nil)
        #expect(
            try context.fetch(jobDescriptor).first?.metadataJSON
                == InferenceGenerationMetadataContract.json(
                    for: replacementGeneration
                )
        )
        #expect(
            manager.foregroundInferenceGenerations[scanId]
                == replacementGeneration
        )
        #expect(
            manager.inferenceRetryTasks.isCurrent(
                scanId,
                token: replacementRetryToken,
                ownerGeneration: replacementGeneration
            ),
            "Stale foreground cleanup must preserve replacement retry work"
        )

        _ = await manager.deleteQueuedScan(scanId: scanId)
    }
}
