import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Inference Retry Persistence")
struct InferenceRetryPersistenceTests {
    private func createIsolatedContainer() throws -> ModelContainer {
        try DatabaseActorTestSupport.makeIsolatedContainer()
    }

    // MARK: - Retry persistence

    @Test func testScheduleInferenceRetryRejectsOlderPersistedGeneration() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("retry-generation-race.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let firstGeneration = UUID()
        let secondGeneration = UUID()
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: firstGeneration
            )
        )
        #expect(
            await actor.transitionScanToStaged(
                id: scan.id,
                expectedGeneration: firstGeneration
            )
        )
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: secondGeneration
            )
        )

        let staleAttempt = await actor.scheduleInferenceRetry(
            id: scan.id,
            expectedGeneration: firstGeneration,
            code: "stale_retry",
            message: "late callback",
            delay: 30
        )
        #expect(staleAttempt == nil)

        let currentAttempt = await actor.scheduleInferenceRetry(
            id: scan.id,
            expectedGeneration: secondGeneration,
            code: "current_retry",
            message: "current callback",
            delay: 30
        )
        #expect(currentAttempt == 1)

        let verificationContext = ModelContext(container)
        let expectedScanId = scan.id
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == expectedScanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try verificationContext.fetch(descriptor).first
        #expect(persisted?.scanStateRaw == ScanQueueState.staged.rawValue)
        #expect(persisted?.queueAttemptCount == 1)
        #expect(persisted?.queueLastErrorCode == "current_retry")
    }

    @Test func testPersistenceRetryRestagesLocalMediaInsteadOfDeadObjectKeys() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let staleKey = "staging/owner/queued.webp"
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("queued.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged,
            stagedR2Keys: [staleKey]
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let generation = UUID()
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: generation
            )
        )
        #expect(
            await actor.scheduleInferenceRetry(
                id: scan.id,
                expectedGeneration: generation,
                code: "scan_persistence_failed",
                message: "Scan insert failed.",
                delay: 5,
                resetMediaUploads: true
            ) == 1
        )

        let verificationContext = ModelContext(container)
        let expectedScanId = scan.id
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == expectedScanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try verificationContext.fetch(descriptor).first
        #expect(persisted?.queueState == .pending)
        #expect(persisted?.stagedR2Keys == nil)
    }

    @Test func testScheduleInferenceRetryUsesMonotonicMirroredAttempt() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .inferencing,
            queueAttemptCount: 0
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id),
            kind: .scanIngestion,
            subjectId: scan.id,
            status: .running,
            attemptCount: 4,
            lastErrorCode:
                OfflineQueueManager.serverRetryableFailureCode
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await actor.scheduleInferenceRetry(
                id: scan.id,
                expectedGeneration: nil,
                code: OfflineQueueManager.serverRetryableFailureCode,
                message: "Advance the surviving durable retry counter.",
                delay: 1
            ) == 5
        )

        let verificationContext = ModelContext(container)
        let scanId = scan.id
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let persistedScan = try #require(
            verificationContext.fetch(scanDescriptor).first
        )
        let jobId =
            OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        jobDescriptor.fetchLimit = 1
        let persistedJob = try #require(
            verificationContext.fetch(jobDescriptor).first
        )
        #expect(persistedScan.queueAttemptCount == 5)
        #expect(persistedJob.attemptCount == 5)
        #expect(
            persistedScan.queueLastErrorCode
                == OfflineQueueManager.serverRetryableFailureCode
        )
    }

    @Test func testInferenceRetryCannotOverrideCompletedCloudOwnership() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .inferencing
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id),
            kind: .scanIngestion,
            subjectId: scan.id,
            status: .running,
            attemptCount: 2,
            lastErrorCode:
                OfflineQueueManager.completedServerResultRecoveryCode
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await actor.scheduleInferenceRetry(
                id: scan.id,
                expectedGeneration: nil,
                code: OfflineQueueManager.serverRetryableFailureCode,
                message: "This must not replace cloud-complete ownership.",
                delay: 1
            ) == nil
        )

        let verificationContext = ModelContext(container)
        let scanId = scan.id
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(persisted.queueState == .inferencing)
        #expect(
            persisted.queueLastErrorCode
                == OfflineQueueManager.completedServerResultRecoveryCode
        )
    }

    @Test func testServerResultRecoveryRetryPreservesCloudOwnershipEvidence() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("server-result.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged
        )
        let retryAfter = Date().addingTimeInterval(30)
        scan.queueLastServerStatus = "complete"
        scan.queueLastServerStage = "media_finalization_complete"
        scan.queueLastServerRetryAfter = retryAfter
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id),
            kind: .scanIngestion,
            subjectId: scan.id,
            status: .running
        )
        job.serverStatus = "complete"
        job.serverStage = "media_finalization_complete"
        job.serverRetryAfter = retryAfter
        context.insert(scan)
        context.insert(job)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let generation = UUID()
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: generation
            )
        )
        #expect(
            await actor.scheduleServerResultRecoveryRetry(
                id: scan.id,
                expectedGeneration: generation,
                code: "server_result_local_recovery_pending",
                message: "Local hydration failed.",
                delay: 30
            ) == 1
        )

        let verificationContext = ModelContext(container)
        let expectedScanId = scan.id
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == expectedScanId }
        )
        scanDescriptor.fetchLimit = 1
        let persistedScan = try verificationContext.fetch(scanDescriptor).first
        let expectedJobId =
            OfflineQueueManager.scanIngestionJobId(scanId: scan.id)
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == expectedJobId }
        )
        jobDescriptor.fetchLimit = 1
        let persistedJob = try verificationContext.fetch(jobDescriptor).first

        #expect(persistedScan?.queueState == .inferencing)
        #expect(persistedScan?.queueAttemptCount == 1)
        #expect(
            persistedScan?.queueLastErrorCode ==
                "server_result_local_recovery_pending"
        )
        #expect(persistedScan?.queueLastServerStatus == "complete")
        #expect(
            persistedScan?.queueLastServerStage ==
                "media_finalization_complete"
        )
        #expect(persistedScan?.queueLastServerRetryAfter == retryAfter)
        #expect(persistedJob?.serverStatus == "complete")
        #expect(persistedJob?.serverStage == "media_finalization_complete")
        #expect(persistedJob?.serverRetryAfter == retryAfter)
        #expect(
            persistedJob?.lastErrorCode ==
                "server_result_local_recovery_pending"
        )
    }

    @Test func testScheduleInferenceRetryCreatesMissingLegacyJob() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .inferencing
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let attempt = await actor.scheduleInferenceRetry(
            id: scan.id,
            expectedGeneration: nil,
            code: "legacy_retry",
            message: "Rebuild the legacy retry mirror.",
            delay: 1
        )
        #expect(attempt == 1)

        let verificationContext = ModelContext(container)
        let scanId = scan.id
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let persistedScan = try #require(
            verificationContext.fetch(scanDescriptor).first
        )
        let persistedJob = try verificationContext.fetchOfflineJob(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        )
        let job = try #require(persistedJob)
        #expect(persistedScan.queueState == .staged)
        #expect(job.status == .waiting)
        #expect(job.attemptCount == 1)
        #expect(job.lastErrorCode == "legacy_retry")
    }

    @Test func testServerResultRecoveryRetryCreatesMissingLegacyJob() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .inferencing
        )
        scan.queueLastServerStatus = "complete"
        scan.queueLastServerStage = "media_finalization_complete"
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let attempt = await actor.scheduleServerResultRecoveryRetry(
            id: scan.id,
            expectedGeneration: nil,
            code: "legacy_server_result_retry",
            message: "Rebuild the legacy server-result mirror.",
            delay: 1
        )
        #expect(attempt == 1)

        let verificationContext = ModelContext(container)
        let scanId = scan.id
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let persistedScan = try #require(
            verificationContext.fetch(scanDescriptor).first
        )
        let persistedJob = try verificationContext.fetchOfflineJob(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        )
        let job = try #require(persistedJob)
        #expect(persistedScan.queueState == .inferencing)
        #expect(persistedScan.queueLastServerStatus == "complete")
        #expect(job.status == .waiting)
        #expect(job.attemptCount == 1)
        #expect(job.lastErrorCode == "legacy_server_result_retry")
    }

    @Test func cancelledRetryReleasesPersistenceFence() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .inferencing
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let cancelledAttempt = await Task { () -> Int? in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return await actor.scheduleInferenceRetry(
                id: scan.id,
                expectedGeneration: nil,
                code: "cancelled_retry",
                message: nil,
                delay: 1
            )
        }.value

        #expect(cancelledAttempt == nil)
        #expect(
            await actor.scheduleInferenceRetry(
                id: scan.id,
                expectedGeneration: nil,
                code: "current_retry",
                message: nil,
                delay: 1
            ) == 1,
            "A cancelled waiter must release the per-scan persistence fence"
        )
    }

}
