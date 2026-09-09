import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Background Account Work Persistence")
struct BackgroundAccountWorkPersistenceTests {
    private func createIsolatedContainer() throws -> ModelContainer {
        try DatabaseActorTestSupport.makeIsolatedContainer()
    }

    @Test func accountBoundBackgroundWorkRetiresBeforeTransportCancellation() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "background_auth_owner_\(UUID().uuidString.lowercased())"
        let ownerUserID = UUID()
        let generation = UUID()
        let scan = OfflineQueuedScan(
            id: scanId,
            scanState: .uploading,
            stagedR2Keys: ["staging/\(ownerUserID.uuidString.lowercased())/queued.webp"]
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        let ownership = BackgroundAccountWorkOwnership(
            ownerUserID: ownerUserID,
            generation: generation,
            phase: .upload
        )
        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await actor.activateBackgroundAccountWork(
                scanId: scanId,
                ownership: ownership
            )
        )
        #expect(
            await actor.backgroundAccountWorkIsCurrent(
                scanId: scanId,
                ownership: ownership
            )
        )
        #expect(
            await actor.backgroundAccountWorkCandidates(
                ownerUserID: ownerUserID
            ) == [
                BackgroundAccountWorkCandidate(
                    scanId: scanId,
                    ownership: ownership
                )
            ]
        )
        #expect(
            await actor.retireBackgroundAccountWork(
                scanId: scanId,
                expectedOwnerUserID: ownerUserID,
                expectedGeneration: UUID(),
                phase: .upload
            )
        )
        #expect(
            await actor.backgroundAccountWorkIsCurrent(
                scanId: scanId,
                ownership: ownership
            )
        )
        #expect(
            await actor.retireBackgroundAccountWork(
                scanId: scanId,
                expectedOwnerUserID: ownerUserID,
                expectedGeneration: generation,
                phase: .upload
            )
        )

        let verificationContext = ModelContext(container)
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let persistedScan = try #require(
            verificationContext.fetch(scanDescriptor).first
        )
        let expectedJobId = OfflineQueueManager.scanIngestionJobId(
            scanId: scanId
        )
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == expectedJobId }
        )
        jobDescriptor.fetchLimit = 1
        let persistedJob = try #require(
            verificationContext.fetch(jobDescriptor).first
        )
        #expect(persistedScan.queueState == .pending)
        #expect(persistedScan.stagedR2Keys == nil)
        #expect(persistedJob.status == .pending)
        #expect(
            OfflineScanJobMetadataContract.backgroundAccountWork(
                in: persistedJob.metadataJSON
            ) == nil
        )
        #expect(
            await actor.backgroundAccountWorkCandidates(
                ownerUserID: ownerUserID
            )?.isEmpty == true
        )
        #expect(
            !(await actor.backgroundAccountWorkIsCurrent(
                scanId: scanId,
                ownership: ownership
            ))
        )
    }

    @Test func rejectedInferenceDispatchDurablyRequeuesBeforeCancellation() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "rejected_inference_dispatch_\(UUID().uuidString.lowercased())"
        let ownerUserID = UUID()
        let generation = UUID()
        let scan = OfflineQueuedScan(
            id: scanId,
            scanState: .inferencing,
            stagedR2Keys: [
                "staging/\(ownerUserID.uuidString.lowercased())/queued.webp"
            ]
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON: InferenceGenerationMetadataContract.json(
                for: generation
            )
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        let ownership = BackgroundAccountWorkOwnership(
            ownerUserID: ownerUserID,
            generation: generation,
            phase: .inference
        )
        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await actor.activateBackgroundAccountWork(
                scanId: scanId,
                ownership: ownership
            )
        )
        #expect(
            await actor.backgroundAccountWorkCandidates(
                ownerUserID: ownerUserID
            ) == [
                BackgroundAccountWorkCandidate(
                    scanId: scanId,
                    ownership: ownership
                )
            ]
        )
        #expect(
            await actor.retireBackgroundAccountWork(
                scanId: scanId,
                expectedOwnerUserID: ownerUserID,
                expectedGeneration: generation,
                phase: .inference
            )
        )

        let verificationContext = ModelContext(container)
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let persistedScan = try #require(
            verificationContext.fetch(scanDescriptor).first
        )
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        jobDescriptor.fetchLimit = 1
        let persistedJob = try #require(
            verificationContext.fetch(jobDescriptor).first
        )
        #expect(persistedScan.queueState == .pending)
        #expect(persistedScan.stagedR2Keys == nil)
        #expect(persistedJob.status == .pending)
        #expect(
            OfflineScanJobMetadataContract.backgroundAccountWork(
                in: persistedJob.metadataJSON
            ) == nil
        )
        #expect(
            await actor.backgroundAccountWorkCandidates(
                ownerUserID: ownerUserID
            )?.isEmpty == true
        )
        #expect(
            !(await actor.backgroundAccountWorkIsCurrent(
                scanId: scanId,
                ownership: ownership
            ))
        )
    }

    @Test func exactUploadOwnerRetiresStagedCallbackRace() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "staged_upload_retirement_\(UUID().uuidString.lowercased())"
        let ownerUserID = UUID()
        let generation = UUID()
        let sourceObjectKey =
            "staging/\(ownerUserID.uuidString.lowercased())/queued.webp"
        let scan = OfflineQueuedScan(
            id: scanId,
            scanState: .uploading,
            stagedR2Keys: [sourceObjectKey]
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        let ownership = BackgroundAccountWorkOwnership(
            ownerUserID: ownerUserID,
            generation: generation,
            phase: .upload
        )
        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await actor.activateBackgroundAccountWork(
                scanId: scanId,
                ownership: ownership
            )
        )

        // Model the upload callback winning the actor immediately before the
        // Auth-transition quiescer. Its exact durable owner must still reset
        // the advanced row instead of merely clearing the ownership marker.
        #expect(
            await actor.markScanAsStaged(
                scanId: scanId,
                r2Keys: [sourceObjectKey]
            ) == .staged
        )

        #expect(
            await actor.retireBackgroundAccountWork(
                scanId: scanId,
                expectedOwnerUserID: ownerUserID,
                expectedGeneration: generation,
                phase: .upload
            )
        )

        let verificationContext = ModelContext(container)
        var verificationDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        verificationDescriptor.fetchLimit = 1
        let persistedScan = try #require(
            verificationContext.fetch(verificationDescriptor).first
        )
        #expect(persistedScan.queueState == .pending)
        #expect(persistedScan.stagedR2Keys == nil)
        #expect(
            await actor.backgroundAccountWorkCandidates(
                ownerUserID: ownerUserID
            )?.isEmpty == true
        )
    }

    @Test func activationCreatesAJobForALegacyScanWithoutOne() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "legacy_background_owner_\(UUID().uuidString.lowercased())"
        let ownership = BackgroundAccountWorkOwnership(
            ownerUserID: UUID(),
            generation: UUID(),
            phase: .upload
        )
        context.insert(OfflineQueuedScan(
            id: scanId,
            scanState: .uploading
        ))
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await actor.activateBackgroundAccountWork(
                scanId: scanId,
                ownership: ownership
            )
        )
        #expect(
            await actor.backgroundAccountWorkIsCurrent(
                scanId: scanId,
                ownership: ownership
            )
        )

        let verificationContext = ModelContext(container)
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        let persistedJob = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(persistedJob.kind == .scanIngestion)
        #expect(persistedJob.subjectId == scanId)
        #expect(persistedJob.status == .running)
        #expect(
            OfflineScanJobMetadataContract.backgroundAccountWork(
                in: persistedJob.metadataJSON
            ) == ownership
        )
    }
}
