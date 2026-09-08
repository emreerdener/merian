import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite(
    "Media Upload Completion",
    .serialized,
    .sharedProcessState(.offlineQueueManager)
)
@MainActor
struct MediaUploadCompletionTests {
    @Test func unsupportedAudioUploadCompletionStopsBeforeDurableStaging() throws {
        let source = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift"
        )
        let completionStart = try #require(source.range(
            of: "func processUploadCompletion("
        ))
        let helperStart = try #require(source.range(
            of: "// MARK: - Completion Helpers",
            range: completionStart.upperBound..<source.endIndex
        ))
        let completionBody = source[
            completionStart.lowerBound..<helperStart.lowerBound
        ]
        let audioFence = try #require(completionBody.range(
            of: "QueuedInferenceMediaPolicy.containsUnsupportedAudio("
        ))
        let invalidation = try #require(completionBody.range(
            of: "invalidateUploadGeneration(",
            range: audioFence.upperBound..<completionBody.endIndex
        ))
        let quarantine = try #require(completionBody.range(
            of: "quarantineInvalidQueuedMedia(scanId: scanId)",
            range: invalidation.upperBound..<completionBody.endIndex
        ))
        let stopDispatch = try #require(completionBody.range(
            of: "return",
            range: quarantine.upperBound..<completionBody.endIndex
        ))
        let durableStaging = try #require(completionBody.range(
            of: "let stagingOutcome = await queueActor.markScanAsStaged(",
            range: stopDispatch.upperBound..<completionBody.endIndex
        ))
        let inferencePreparation = try #require(completionBody.range(
            of: "self.beginInferencePreparation(scanId: scanId)",
            range: durableStaging.upperBound..<completionBody.endIndex
        ))

        #expect(audioFence.lowerBound < invalidation.lowerBound)
        #expect(invalidation.lowerBound < quarantine.lowerBound)
        #expect(quarantine.lowerBound < stopDispatch.lowerBound)
        #expect(stopDispatch.lowerBound < durableStaging.lowerBound)
        #expect(durableStaging.lowerBound < inferencePreparation.lowerBound)
    }

    @Test func testUploadGenerationRejectsDelayedReplacementCallback() {
        let manager = OfflineQueueManager.shared
        let scanId = "upload-generation-test"
        let staleGeneration = UUID()
        let currentGeneration = UUID()
        manager.uploadPreparationGenerations[scanId] = nil
        manager.latestUploadGenerations[scanId] = currentGeneration
        defer {
            manager.uploadPreparationGenerations[scanId] = nil
            manager.latestUploadGenerations[scanId] = nil
        }

        #expect(
            !manager.isUploadGenerationCurrent(
                scanId: scanId,
                generation: staleGeneration
            )
        )
        #expect(
            manager.isUploadGenerationCurrent(
                scanId: scanId,
                generation: currentGeneration
            )
        )
        #expect(
            !manager.isUploadGenerationCurrent(
                scanId: scanId,
                generation: nil
            )
        )
    }

    @Test func testUploadFailureFencesEverySiblingCallbackInGeneration() {
        let manager = OfflineQueueManager.shared
        let scanId = "upload-generation-failure-fence-test"
        let failedGeneration = UUID()
        manager.uploadPreparationGenerations[scanId] = nil
        manager.latestUploadGenerations[scanId] = failedGeneration
        defer {
            manager.uploadPreparationGenerations[scanId] = nil
            manager.latestUploadGenerations[scanId] = nil
        }

        manager.invalidateUploadGeneration(
            scanId: scanId,
            generation: failedGeneration
        )

        #expect(
            !manager.isUploadGenerationCurrent(
                scanId: scanId,
                generation: failedGeneration
            )
        )
        #expect(
            !manager.isUploadGenerationCurrent(
                scanId: scanId,
                generation: nil
            )
        )
    }

    @Test func testUploadManifestWaitsForEverySiblingCallbackOutcome() {
        let manager = OfflineQueueManager.shared
        let scanId = "upload-manifest-outcome-accumulator-test"
        let generation = UUID()
        let ownerId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let firstKey = "staging/\(ownerId)/first.webp"
        let secondKey = "staging/\(ownerId)/second.webp"
        manager.uploadCompletionStates[scanId] = nil
        defer {
            manager.uploadCompletionStates[scanId] = nil
        }

        manager.recordSuccessfulUploadMember(
            scanId: scanId,
            generation: generation,
            objectKey: firstKey
        )
        #expect(
            !manager.hasConfirmedSuccessfulUploadManifest(
                scanId: scanId,
                generation: generation,
                expectedObjectKeys: [firstKey, secondKey]
            )
        )

        manager.recordSuccessfulUploadMember(
            scanId: scanId,
            generation: generation,
            objectKey: secondKey
        )
        #expect(
            manager.hasConfirmedSuccessfulUploadManifest(
                scanId: scanId,
                generation: generation,
                expectedObjectKeys: [firstKey, secondKey]
            )
        )
        manager.recordSuccessfulUploadMember(
            scanId: scanId,
            generation: generation,
            objectKey: "staging/\(ownerId)/stale.webp"
        )
        #expect(
            !manager.hasConfirmedSuccessfulUploadManifest(
                scanId: scanId,
                generation: generation,
                expectedObjectKeys: [firstKey, secondKey]
            ),
            "A successful key outside the current queued manifest must fail closed"
        )

        let replacementGeneration = UUID()
        manager.recordSuccessfulUploadMember(
            scanId: scanId,
            generation: replacementGeneration,
            objectKey: secondKey
        )
        #expect(
            !manager.hasConfirmedSuccessfulUploadManifest(
                scanId: scanId,
                generation: generation,
                expectedObjectKeys: [firstKey, secondKey]
            )
        )

        let legacyScanId = "\(scanId)-legacy"
        manager.uploadCompletionStates[legacyScanId] = nil
        defer {
            manager.uploadCompletionStates[legacyScanId] = nil
        }
        manager.recordSuccessfulUploadMember(
            scanId: legacyScanId,
            generation: nil,
            objectKey: firstKey
        )
        #expect(
            manager.hasConfirmedSuccessfulUploadManifest(
                scanId: legacyScanId,
                generation: nil,
                expectedObjectKeys: [firstKey]
            )
        )
    }

    @Test func testCompleteUploadManifestResetsRetryOnlyWithDurableStagingCommit() async throws {
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        manager.modelContext = context
        defer {
            manager.modelContext = originalContext
        }
        let scanId = UUID().uuidString
        let generation = UUID()
        let ownerId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let firstKey = "staging/\(ownerId)/first.webp"
        let secondKey = "staging/\(ownerId)/second.webp"
        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .uploading
        )
        scan.queueAttemptCount = 3
        scan.queueLastErrorCode = "upload_transport"
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .waiting,
            lastAttemptAt: Date(),
            nextRunAt: Date().addingTimeInterval(30),
            attemptCount: 3,
            lastErrorCode: "upload_transport",
            lastErrorMessage: "Retry upload"
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        manager.uploadPreparationGenerations[scanId] = nil
        manager.latestUploadGenerations[scanId] = generation
        defer {
            manager.latestUploadGenerations[scanId] = nil
            manager.uploadCompletionStates[scanId] = nil
        }

        manager.recordSuccessfulUploadMember(
            scanId: scanId,
            generation: generation,
            objectKey: firstKey
        )
        #expect(
            !manager.hasConfirmedSuccessfulUploadManifest(
                scanId: scanId,
                generation: generation,
                expectedObjectKeys: [firstKey, secondKey]
            )
        )
        #expect(scan.queueAttemptCount == 3)
        #expect(scan.queueLastErrorCode == "upload_transport")

        manager.recordSuccessfulUploadMember(
            scanId: scanId,
            generation: generation,
            objectKey: secondKey
        )
        #expect(
            manager.hasConfirmedSuccessfulUploadManifest(
                scanId: scanId,
                generation: generation,
                expectedObjectKeys: [firstKey, secondKey]
            )
        )
        #expect(
            scan.queueAttemptCount == 3,
            "In-memory manifest completion must not clear durable retry state"
        )

        let actor = BackgroundDatabaseActor(modelContainer: context.container)
        let outcome = await actor.markScanAsStaged(
            scanId: scanId,
            r2Keys: [firstKey, secondKey]
        )
        let verificationContext = ModelContext(context.container)
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        jobDescriptor.fetchLimit = 1
        let persistedScan = try verificationContext.fetch(scanDescriptor).first
        let persistedJob = try verificationContext.fetch(jobDescriptor).first

        #expect(outcome == .staged)
        #expect(persistedScan?.queueState == .staged)
        #expect(persistedScan?.stagedR2Keys == [firstKey, secondKey])
        #expect(persistedScan?.queueAttemptCount == 0)
        #expect(persistedScan?.queueLastErrorCode == nil)
        #expect(persistedJob?.status == .running)
        #expect(persistedJob?.attemptCount == 0)
        #expect(persistedJob?.lastErrorCode == nil)
    }

    @Test func testUploadCompletionClearsOnlyTheOwningCallbackToken() {
        let manager = OfflineQueueManager.shared
        let scanId = "upload-completion-token-test"
        manager.uploadCompletionTokens[scanId] = nil
        defer {
            manager.uploadCompletionTokens[scanId] = nil
        }

        let firstToken = manager.beginUploadCompletion(scanId: scanId)
        let replacementToken = manager.beginUploadCompletion(scanId: scanId)

        #expect(
            manager.finishUploadCompletion(
                scanId: scanId,
                token: firstToken
            )
        )
        #expect(manager.uploadCompletionScanIds.contains(scanId))
        #expect(manager.uploadCompletionTokens[scanId] == [replacementToken])

        #expect(
            manager.finishUploadCompletion(
                scanId: scanId,
                token: replacementToken
            )
        )
        #expect(!manager.uploadCompletionScanIds.contains(scanId))
    }

    @Test func testStaleUploadGenerationCannotFinishReplacementSync() {
        let manager = OfflineQueueManager.shared
        let staleGeneration = UUID()
        let currentGeneration = UUID()

        manager.syncTask?.cancel()
        manager.syncTask = nil
        manager.syncGeneration = currentGeneration
        manager.isSyncing = true
        SyncStateManager.shared.forceIdle()
        SyncStateManager.shared.beginSync(
            itemCount: 4,
            generation: currentGeneration
        )
        defer {
            manager.syncTask?.cancel()
            manager.syncTask = nil
            manager.syncGeneration = nil
            manager.isSyncing = false
            SyncStateManager.shared.forceIdle()
        }

        #expect(!manager.finishUploadSync(generation: staleGeneration))
        #expect(manager.syncGeneration == currentGeneration)
        #expect(manager.isSyncing)
        #expect(SyncStateManager.shared.pendingUploadCount == 4)

        #expect(manager.finishUploadSync(generation: currentGeneration))
        #expect(manager.syncGeneration == nil)
        #expect(!manager.isSyncing)
        #expect(SyncStateManager.shared.pendingUploadCount == 0)
    }
}
