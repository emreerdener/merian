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
    @Test(arguments: ["ai_openai_consent_required", "client_update_required"])
    func consentPauseRetriesOnlyLocalPersistenceBeforeRetiring(code: String) async throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let originalIsOnline = manager.isOnline
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let scanId = UUID().uuidString.lowercased(), generation = UUID()
        let funding = ScanFundingReservation(accountId: UUID(), scanId: scanId, source: .complimentaryPro)
        let scan = OfflineQueuedScan(
            id: scanId, scanState: .staged, inferenceImagePaths: ["synthetic-pause.webp"]
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion, subjectId: scanId, status: .running,
            metadataJSON: OfflineScanJobMetadataContract.json(generation: generation, funding: funding)
        )
        context.insert(scan)
        context.insert(job)
        try context.save()
        manager.isOnline = false
        manager.modelContext = nil // Force local persistence failure, not a network failure.
        manager.foregroundInferenceGenerations[scanId] = generation
        manager.startedForegroundInferenceGenerations[scanId] = generation
        manager.deferredLiveUploadScanIds.insert(scanId)
        defer {
            manager.foregroundInferenceRetirementTasks.cancel(scanId)
            manager.foregroundInferenceGenerations[scanId] = nil
            manager.startedForegroundInferenceGenerations[scanId] = nil
            manager.deferredLiveUploadScanIds.remove(scanId)
            manager.modelContext = originalContext
            manager.isOnline = originalIsOnline
        }
        #expect(InferenceLiveQueueService.live.pauseQueuedScan(
            scanId: scanId, generation: generation,
            reason: BackgroundInferencePolicy.openAIConsentAttentionMessage,
            errorCode: code
        ))
        // A later generic defer cannot change the pause owner's recovery policy.
        manager.retireForegroundInference(
            scanId: scanId, generation: generation, resumeBackground: true, reason: "late_defer"
        )
        manager.releaseDeferredLiveUpload(
            scanId: scanId, foregroundInferenceGeneration: generation, reason: "late_body_sent"
        )
        manager.releaseAllDeferredLiveUploads(reason: "scene_background_or_disconnect")
        try await Task.sleep(for: .milliseconds(300))
        #expect(manager.foregroundInferenceRetirementTasks.isOwned(scanId, by: generation))
        #expect(manager.foregroundInferenceGenerations[scanId] == generation)
        #expect(manager.deferredLiveUploadScanIds.contains(scanId))
        #expect(!manager.isForegroundInferenceAttemptCurrent(scanId: scanId, generation: generation))
        #expect(!manager.canStartForegroundInference(scanId: scanId, generation: generation))
        #expect(scan.queueState == .staged)
        manager.modelContext = context
        for _ in 0..<40 {
            if manager.foregroundInferenceGenerations[scanId] == nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(scan.queueState == .failed)
        #expect(scan.queueNeedsAttention)
        #expect(scan.queueLastErrorCode == code)
        #expect(scan.queueLastHTTPStatus == (code == "client_update_required" ? 426 : 403))
        #expect(job.lastHTTPStatus == scan.queueLastHTTPStatus)
        #expect(scan.inferenceImagePaths == ["synthetic-pause.webp"])
        #expect(scan.queueNextRetryAt == nil)
        #expect(job.status == .needsAttention)
        #expect(job.nextRunAt == nil)
        #expect(OfflineScanJobMetadataContract.funding(in: job.metadataJSON) == funding)
        #expect(manager.foregroundInferenceGenerations[scanId] == nil)
        #expect(!manager.deferredLiveUploadScanIds.contains(scanId))
    }

    @Test func consentPauseCannotOverwriteDurableReplacement() async throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let scanId = UUID().uuidString.lowercased(), stale = UUID(), replacement = UUID()
        let scan = OfflineQueuedScan(id: scanId, scanState: .staged)
        let metadata = InferenceGenerationMetadataContract.json(for: replacement)
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId), kind: .scanIngestion,
            subjectId: scanId, status: .running, metadataJSON: metadata
        )
        context.insert(scan)
        context.insert(job)
        try context.save()
        manager.modelContext = context
        manager.foregroundInferenceGenerations[scanId] = stale
        defer {
            manager.foregroundInferenceGenerations[scanId] = nil
            manager.modelContext = originalContext
        }
        let didEnd = await manager.endForegroundInference(
            scanId: scanId, generation: stale, resumeBackground: false,
            reason: BackgroundInferencePolicy.openAIConsentAttentionMessage,
            consentPauseErrorCode: "ai_openai_consent_required"
        )
        #expect(!didEnd)
        #expect(scan.queueState == .staged)
        #expect(!scan.queueNeedsAttention)
        #expect(job.status == .running)
        #expect(job.metadataJSON == metadata)
    }

    @Test(arguments: [ScanFundingSource.paidPro, .complimentaryPro, .immediateFlash, .deferredFlash])
    func proTimeoutRequiresExactDurableFunding(source: ScanFundingSource) throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let scanId = UUID().uuidString.lowercased()
        let generation = UUID()
        manager.modelContext = context
        manager.foregroundInferenceGenerations[scanId] = generation
        manager.startedForegroundInferenceGenerations[scanId] = generation
        defer {
            manager.modelContext = originalContext
            manager.foregroundInferenceGenerations.removeValue(forKey: scanId)
            manager.startedForegroundInferenceGenerations.removeValue(forKey: scanId)
        }
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON: OfflineScanJobMetadataContract.json(
                generation: generation,
                funding: ScanFundingReservation(accountId: UUID(), scanId: scanId, source: source)
            )
        )
        context.insert(job)
        try context.save()
        #expect(manager.isForegroundInferenceProFunded(scanId: scanId, generation: generation)
            == (source == .paidPro || source == .complimentaryPro))
        #expect(!manager.isForegroundInferenceProFunded(scanId: scanId, generation: UUID()))
        job.metadataJSON = InferenceGenerationMetadataContract.json(for: UUID())
        #expect(!manager.isForegroundInferenceProFunded(scanId: scanId, generation: generation))
        job.metadataJSON = InferenceGenerationMetadataContract.json(for: generation)
        #expect(!manager.isForegroundInferenceProFunded(scanId: scanId, generation: generation))
    }

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
