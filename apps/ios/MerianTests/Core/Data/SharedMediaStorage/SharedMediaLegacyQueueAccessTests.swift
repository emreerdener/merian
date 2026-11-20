import Foundation
import SwiftData
import Testing
@testable import Merian

@MainActor
@Suite(.sharedProcessState(.offlineQueueManager))
struct SharedMediaLegacyQueueAccessTests {
    private func context() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    @Test func missingLegacyCompletionDoesNotAuthorizeJobCreation() throws {
        let c = try context(), id = UUID().uuidString.lowercased()
        #expect(try SharedMediaLegacyQueueAccess.permits(c, scanID: id))
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try c.ensureOfflineJobRecord(id: "scan-ingestion:" + id, kind: .scanIngestion, subjectId: id)
        }
        let queue = OfflineQueuedScan(id: id)
        c.insert(queue)
        // Admission must see the unsaved queue in the same transaction.
        let job = try c.ensureOfflineJobRecord(id: "scan-ingestion:" + id, kind: .scanIngestion, subjectId: id)
        try c.save()
        #expect(job.status == .pending)
        #expect(SharedMediaLegacyQueueAccess.permitsFresh(c.container, scanID: id))
    }

    @Test(arguments: ["native_receiving_v1", "native_receiving_v2"])
    func durabilityBridgeRequiresQueueAndRefusesNativeRetryMutations(_ key: String) throws {
        let c = try context(), id = UUID().uuidString.lowercased()
        let manager = OfflineQueueManager.shared, previous = manager.modelContext
        manager.modelContext = c
        defer { manager.modelContext = previous }
        #expect(manager.ensureScanIngestionJob(scanId: id) == nil)
        #expect(try c.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        let row = OfflineQueuedScan(id: id)
        c.insert(row); try c.save()
        let job = try #require(manager.ensureScanIngestionJob(scanId: id))
        let marker = "{\"\(key)\":null}"
        job.metadataJSON = marker; try c.save()
        #expect(manager.ensureScanIngestionJob(scanId: id) == nil)
        #expect(manager.updateQueuedScanForRetry(scanId: id, code: "fixture", message: nil,
            delay: 1, resetTo: .staged) == nil)
        #expect(!manager.retryQueuedScanNow(scanId: id))
        #expect(!manager.markQueuedScanNeedsAttention(scanId: id, code: "fixture", message: nil))
        manager.persistServerStatus(scanId: id, response: .init(scanId: id, status: .found,
            jobStatus: nil, jobStage: "fixture", jobAttemptCount: 4, retryAfter: nil, lastError: "fixture"))
        #expect(row.queueLastServerStatus == nil && row.queueLastServerStage == nil)
        #expect(job.serverStatus == nil && job.serverStage == nil && job.lastErrorCode == nil)
        #expect(job.status == .pending && row.queueAttemptCount == 0)
        #expect(job.metadataJSON == marker)
        #expect(row.queueState == .pending && row.queueLastErrorCode == nil)
        #expect(!c.hasChanges)
        #expect(try c.fetchCount(FetchDescriptor<OfflineQueueEvent>()) == 0)
    }

    @Test(arguments: ["{\"native_receiving_v1\":null}", "{\"native_receiving_v1\":{}}",
                     "{\"native_receiving_v2\":null}", "{\"native_receiving_v2\":{}}",
                     "{\"native_receiving_v1\":null,\"native_receiving_v2\":null}", "broken", "[]"])
    func damagedOrReservedJobCannotResetOrDowngrade(_ metadata: String) throws {
        let c = try context(), id = UUID().uuidString.lowercased()
        c.insert(OfflineQueuedScan(id: id))
        let job = OfflineJobRecord(id: "scan-ingestion:" + id, kind: .scanIngestion,
            subjectId: id, status: .complete, metadataJSON: metadata)
        c.insert(job); try c.save()
        #expect(!SharedMediaLegacyQueueAccess.permitsFresh(c.container, scanID: id))
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try c.ensureOfflineJobRecord(id: job.id, kind: .scanIngestion, subjectId: id)
        }
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try c.ensureOfflineJobRecord(id: job.id, kind: .future)
        }
        #expect(job.status == .complete && job.metadataJSON == metadata && job.kind == .scanIngestion)
        #expect(!c.hasChanges)
    }

    @Test(arguments: ["sharedDirectV1", "sharedDirectNativeReceivingV1", "sharedDirectNativeReceivingV2", "unknown"])
    func queueAuthorityBlocksLegacyHelpers(_ authority: String) throws {
        let c = try context(), id = UUID().uuidString.lowercased()
        let queue = OfflineQueuedScan(id: id)
        queue.mediaAuthorityRaw = authority
        c.insert(queue); try c.save()
        #expect(!SharedMediaLegacyQueueAccess.permitsFresh(c.container, scanID: id))
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try c.ensureOfflineJobRecord(id: "scan-ingestion:" + id, kind: .scanIngestion, subjectId: id)
        }
    }

    @Test func survivingConsumerAndAnalysisPreventMissingQueueDowngrade() throws {
        let c = try context(), id = UUID().uuidString.lowercased()
        let row = Self.consumer(id)
        c.insert(row); try c.save()
        #expect(!SharedMediaLegacyQueueAccess.permitsFresh(c.container, scanID: id.uppercased()))
        let analysis = try LocalAnalysisRecord(analysisID: UUID(), observationID: id,
            ownerAccountID: UUID(), completedAt: Date(), resultSnapshotData: Data("{}".utf8))
        analysis.mediaAuthorityRaw = "sharedDirectNativeReceivingV1"
        c.insert(analysis); c.delete(row); try c.save()
        #expect(!SharedMediaLegacyQueueAccess.permitsFresh(c.container, scanID: id))
    }

    @Test func queueDeletionRejectsBeforeClearingProcessOwners() async throws {
        let c = try context(), id = UUID().uuidString.lowercased()
        c.insert(Self.consumer(id)); try c.save()
        let manager = OfflineQueueManager.shared, old = manager.modelContext
        defer { manager.modelContext = old; manager.latestUploadGenerations[id] = nil }
        manager.modelContext = c
        let generation = UUID()
        manager.latestUploadGenerations[id] = generation
        #expect(await manager.deleteQueuedScan(scanId: id) == false)
        #expect(manager.latestUploadGenerations[id] == generation)
        #expect(try c.fetchCount(FetchDescriptor<SharedMediaConsumerRecord>()) == 1)
        #expect(!c.hasChanges)
    }

    @Test func ownershipTransferDuringTaskEnumerationPreservesQueueAndProcessOwner() async throws {
        let c = try context(), id = UUID().uuidString.lowercased()
        c.insert(OfflineQueuedScan(id: id))
        let job = try c.ensureOfflineJobRecord(id: "scan-ingestion:" + id, kind: .scanIngestion, subjectId: id)
        try c.save()
        let manager = OfflineQueueManager.shared, old = manager.modelContext
        defer { manager.modelContext = old; manager.latestUploadGenerations[id] = nil }
        manager.modelContext = c
        let generation = UUID()
        manager.latestUploadGenerations[id] = generation
        var mutationError: Error?
        let result = await manager.deleteQueuedScan(scanId: id, enumerateBackgroundTasks: {
            await Task.yield()
            job.metadataJSON = "{\"native_receiving_v1\":{}}"
            do { try c.save() } catch { mutationError = error }
            return []
        })
        #expect(mutationError == nil)
        #expect(!result && manager.latestUploadGenerations[id] == generation)
        #expect(try c.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try c.fetchCount(FetchDescriptor<OfflineQueueEvent>()) == 0)
        #expect(job.status == .pending)
    }

    @Test func sharedFailedQueueCannotDeleteRetainedMedia() async throws {
        let c = try context(), id = UUID().uuidString.lowercased()
        let name = "native-guard-" + id + ".webp"
        let url = URL.documentsDirectory.appendingPathComponent(name)
        let bytes = Data("synthetic retained original".utf8)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let json = try #require(String(data: try JSONEncoder().encode([SerializedMediaItem.image(.documents(name))]), encoding: .utf8))
        let queue = OfflineQueuedScan(id: id, capturedMediaJSON: json)
        queue.mediaAuthorityRaw = "sharedDirectNativeReceivingV1"
        queue.scanStateRaw = ScanQueueState.failed.rawValue
        c.insert(queue); try c.save()
        let manager = OfflineQueueManager.shared, old = manager.modelContext
        defer { manager.modelContext = old }
        manager.modelContext = c
        #expect(await manager.deleteQueuedScan(scanId: id) == false)
        manager.purgeSoftDeletedRecords()
        #expect(try c.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func fundingProofChangesWithGenerationAndRejectsOwnershipTransfer() throws {
        let c = try context(), id = UUID().uuidString.lowercased()
        let reservation = ScanFundingReservation(accountId: UUID(), scanId: id, source: .deferredFlash)
        let job = OfflineJobRecord(id: "scan-ingestion:" + id, kind: .scanIngestion,
            subjectId: id, metadataJSON: OfflineScanJobMetadataContract.settingFunding(reservation, in: nil))
        c.insert(job); try c.save()
        let before = try #require(try SharedMediaLegacyQueueAccess.fundingIdentity(ModelContext(c.container),
            scanID: id, reservation: reservation))
        job.metadataJSON = InferenceGenerationMetadataContract.setting(UUID(), in: job.metadataJSON)
        try c.save()
        #expect(try SharedMediaLegacyQueueAccess.fundingIdentity(ModelContext(c.container),
            scanID: id, reservation: reservation) != before)
        c.insert(Self.consumer(id)); try c.save()
        #expect(try SharedMediaLegacyQueueAccess.fundingIdentity(ModelContext(c.container),
            scanID: id, reservation: reservation) == nil)
        let manager = OfflineQueueManager.shared, old = manager.modelContext
        defer { manager.modelContext = old }
        manager.modelContext = c
        let metadata = job.metadataJSON
        #expect(!manager.releaseFundingForProvenPredispatchFailure(scanId: id))
        #expect(job.metadataJSON == metadata && !c.hasChanges)
    }

    @Test func unrelatedJobKindsKeepExistingBehavior() throws {
        let c = try context()
        let job = try c.ensureOfflineJobRecord(id: "collection-sync:fixture", kind: .collectionSync,
            metadataJSON: "legacy-opaque")
        job.status = .complete
        _ = try c.ensureOfflineJobRecord(id: job.id, kind: .collectionSync)
        #expect(job.status == .pending)
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try c.ensureOfflineJobRecord(id: "unrelated", kind: .future,
                metadataJSON: "{\"native_receiving_v1\":null}")
        }
    }

    @Test(arguments: ["queue", "consumer", "marker", "cached"])
    func flushSoftDeleteAndQuarantinePreserveNativeOwnership(_ kind: String) throws {
        let c = try context(), id = UUID().uuidString.lowercased()
        let queue = OfflineQueuedScan(id: id)
        if kind != "consumer" { c.insert(queue) }
        let funding = ScanFundingReservation(accountId: UUID(), scanId: id, source: .deferredFlash)
        let metadata = OfflineScanJobMetadataContract.settingFunding(funding, in: nil)
        let job = OfflineJobRecord(id: "scan-ingestion:" + id, kind: .scanIngestion,
            subjectId: id, status: .waiting, metadataJSON: metadata)
        c.insert(job)
        if kind == "queue" { queue.mediaAuthorityRaw = "sharedDirectNativeReceivingV1" }
        if kind == "consumer" { c.insert(Self.consumer(id)) }
        if kind == "marker" { job.metadataJSON = "{\"native_receiving_v1\":null}" }
        c.insert(ActiveOfflineQueuedScanGoalHint(scanId: id, userFieldTripId: "synthetic-trip", itemId: "synthetic-goal"))
        try c.save()
        if kind == "cached" {
            let fresh = ModelContext(c.container); fresh.autosaveEnabled = false
            let saved = try #require(try fresh.fetch(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == id })).first)
            saved.mediaAuthorityRaw = "sharedDirectNativeReceivingV1"; try fresh.save()
        }
        let savedMetadata = job.metadataJSON, savedUpdated = job.updatedAt
        let manager = OfflineQueueManager.shared, old = manager.modelContext, oldCount = manager.unsyncedItemsCount
        manager.modelContext = c; manager.unsyncedItemsCount = 19
        defer { manager.modelContext = old; manager.unsyncedItemsCount = oldCount }
        #expect(!manager.flushOfflineQueuedScan(scanId: id))
        #expect(!manager.softDeleteQueuedScan(scanId: id, reason: "synthetic", errorCode: "synthetic"))
        #expect(!manager.quarantineInvalidQueuedMedia(scanId: id))
        #expect(job.metadataJSON == savedMetadata && job.updatedAt == savedUpdated && job.status == .waiting)
        #expect(manager.unsyncedItemsCount == 19)
        #expect(try c.fetchCount(FetchDescriptor<ActiveOfflineQueuedScanGoalHint>()) == 1)
        #expect(try c.fetchCount(FetchDescriptor<OfflineQueueEvent>()) == 0)
        #expect(try c.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == (kind == "consumer" ? 0 : 1))
        #expect(!c.hasChanges)
    }

    @Test(arguments: ["consumer", "queue", "orphanMarker", "changedKindMarker"])
    func fixtureResetRefusesNativeRowsAndLeavesUnsavedDrafts(_ kind: String) throws {
        let c = try context(), id = UUID().uuidString.lowercased()
        switch kind {
        case "consumer": c.insert(Self.consumer(id))
        case "queue":
            let queue = OfflineQueuedScan(id: id); queue.mediaAuthorityRaw = "sharedDirectNativeReceivingV1"; c.insert(queue)
        default:
            c.insert(OfflineJobRecord(id: kind == "orphanMarker" ? "scan-ingestion:" + id : "unrelated",
                kind: kind == "orphanMarker" ? .scanIngestion : .future,
                subjectId: id, metadataJSON: "{\"native_receiving_v1\":null}"))
        }
        try c.save()
        #expect(!UITestSeedCoordinator.canResetFixtureState(container: c.container))
        let main = c.container.mainContext; main.autosaveEnabled = false
        let draftID = UUID().uuidString.lowercased(), draft = OfflineQueuedScan(id: draftID)
        main.insert(draft)
        #expect(!UITestSeedCoordinator.canResetFixtureState(container: c.container))
        #expect(main.hasChanges && draft.modelContext === main)
        #expect(try ModelContext(c.container).fetchCount(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == draftID })) == 0)
    }

    @Test func fixtureResetAllowsCleanOrdinaryRowsButPreservesDirtyContext() throws {
        let c = try context(), id = UUID().uuidString.lowercased()
        c.insert(OfflineQueuedScan(id: id))
        c.insert(OfflineJobRecord(id: "scan-ingestion:" + id, kind: .scanIngestion, subjectId: id))
        try c.save()
        #expect(UITestSeedCoordinator.canResetFixtureState(container: c.container))
        let main = c.container.mainContext; main.autosaveEnabled = false
        let draft = OfflineQueuedScan(id: UUID().uuidString.lowercased()); main.insert(draft)
        #expect(!UITestSeedCoordinator.canResetFixtureState(container: c.container))
        #expect(main.hasChanges && draft.modelContext === main)
        #expect(try c.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
    }

    private static func consumer(_ id: String) -> SharedMediaConsumerRecord {
        SharedMediaConsumerRecord(id: UUID(), kindRaw: "analysis", consumerID: UUID().uuidString.lowercased(),
            originQueueID: id, observationID: id, inventoryID: UUID(), inventoryGeneration: UUID(),
            ownerID: UUID(), packageID: UUID(), draftGeneration: UUID(), frozenPackageRevision: 1,
            contractVersion: "nativeReceivingV1", digestVersion: 1, cohortSHA256: String(repeating: "0", count: 64),
            executionKindRaw: "ordinaryV1", inferenceGeneration: UUID())
    }
}
