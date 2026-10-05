import Foundation
import SwiftData
import Testing
@testable import Merian

@MainActor
@Suite("Reanalysis Parent Erasure", .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisErasureTests {
    private let parent = "00000000-0000-4000-8000-000000000801"
    private let other = "00000000-0000-4000-8000-000000000802"

    private func context() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container); context.autosaveEnabled = false
        return context
    }

    private func child(_ context: ModelContext, kind: String = "reanalysis", parentID: String? = nil) -> OfflineQueuedScan {
        let row = OfflineQueuedScan(id: UUID().uuidString.lowercased(), capturedMediaJSON: "[]")
        row.workKindRaw = kind
        row.parentObservationID = parentID ?? parent
        // Deliberately absent source/owner and damaged job JSON: erasure must
        // not use dispatch eligibility or optional metadata as its index.
        context.insert(row)
        context.insert(OfflineJobRecord(id: OfflineQueueManager.scanIngestionJobId(scanId: row.id),
            kind: .scanIngestion, subjectId: "damaged", metadataJSON: "not-json"))
        return row
    }

    @Test func exactParentErasesDamagedChildrenWithoutTouchingOtherParents() throws {
        let context = try context()
        let targets = [child(context), child(context, kind: "ordinary"), child(context, kind: "unknown")]
        let sibling = child(context, parentID: other)
        let malformed = child(context, parentID: "not-a-uuid")
        let detached = child(context); detached.parentObservationID = nil
        try context.save()
        let ids = Set(targets.map(\.id))
        let cleanup = try ObservationReanalysisErasure.removeChildren(of: parent.uppercased(), context: context)
        #expect(Set(cleanup.childIDs) == ids)
        try context.save()
        #expect(Set(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.id)) == Set([sibling.id, malformed.id, detached.id]))
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 3)
        #expect(try ObservationReanalysisErasure.removeChildren(of: parent, context: context).childIDs.isEmpty)
    }

    @Test func rollbackPreservesParentChildAndJob() throws {
        let context = try context()
        let record = LocalScanRecord(id: parent, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        context.insert(record)
        let row = child(context)
        let childID = row.id
        try context.save()
        _ = try ObservationReanalysisErasure.removeChildren(of: parent, context: context)
        context.delete(record)
        context.rollback()
        let read = ModelContext(context.container)
        #expect(try read.fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
        #expect(try read.fetch(FetchDescriptor<OfflineQueuedScan>()).first?.id == childID)
        #expect(try read.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

    @Test func onlyExactPrivateChildFilesAreReturnedForPostCommitCleanup() throws {
        let context = try context()
        let row = child(context)
        let owned = "ReanalysisQueue/\(row.id)/photo.webp"
        row.inferenceImagePaths = [owned, "parent.webp", "ReanalysisQueue/\(other)/photo.webp",
            "ReanalysisQueue/\(row.id)/../parent.webp", "/private/parent.webp", "https://example.invalid/photo.webp"]
        try context.save()
        let cleanup = try ObservationReanalysisErasure.removeChildren(of: parent, context: context)
        #expect(cleanup.mediaPaths == [URL.documentsDirectory.appendingPathComponent(owned).path])
        #expect(ObservationReanalysisErasure.ownedFile("ReanalysisQueue/\(row.id)//", childID: row.id) == nil)
        context.rollback()
    }

    @Test func nonBiologicalDeletionCommitsChildrenWithParentAndOnlyOneCloudIntent() async throws {
        let context = try context()
        let record = LocalScanRecord(id: parent, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture", isBiological: false)
        context.insert(record)
        let row = child(context, kind: "unknown"); let id = row.id
        try context.save()
        let actor = BackgroundDatabaseActor(modelContainer: context.container)
        let result = try await actor.bulkDeleteNonBiologicalScansWithQueueCleanup(payloads: [.init(id: parent, mediaPaths: [])])
        #expect(result.childIDs == [id])
        let read = ModelContext(context.container)
        #expect(try read.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try read.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: id)) == nil)
        #expect(try read.fetch(FetchDescriptor<PendingCloudDeletionTask>()).map(\.scanId) == [parent])
    }

    @Test func automaticLegacyPurgeAndPermissionRecoveryLeaveHeldChildrenAlone() throws {
        let context = try context()
        let row = child(context)
        row.scanStateRaw = ScanQueueState.failed.rawValue
        let owner = UUID()
        let job = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: row.id)))
        job.status = .needsAttention
        job.lastErrorCode = "ai_openai_consent_required"
        job.subjectId = row.id
        job.metadataJSON = OfflineScanJobMetadataContract.json(generation: nil,
            funding: ScanFundingReservation(accountId: owner, scanId: row.id, source: .complimentaryPro))
        try context.save()
        let queue = OfflineQueueManager.shared; let previous = queue.modelContext
        defer { queue.modelContext = previous }
        queue.modelContext = context
        #expect(!queue.ownsOpenAIConsentPausedScan(scanId: row.id, accountId: owner))
        queue.purgeSoftDeletedRecords()
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(job.status == .needsAttention)
    }

    @Test func directDeletionCommitsChildrenAndCancelsOnlyRemovedRuntimeOwners() async throws {
        let context = try context()
        let record = LocalScanRecord(id: parent, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        context.insert(record)
        let row = child(context); let id = row.id
        let retained = child(context, parentID: other); let retainedID = retained.id
        try context.save()
        let queue = OfflineQueueManager.shared
        let previousContext = queue.modelContext; let previousOnline = queue.isOnline
        defer { queue.modelContext = previousContext; queue.isOnline = previousOnline; queue.latestUploadGenerations[id] = nil; queue.latestUploadGenerations[retainedID] = nil }
        queue.modelContext = context; queue.isOnline = false
        let generation = UUID(); queue.latestUploadGenerations[id] = generation
        let retainedGeneration = UUID(); queue.latestUploadGenerations[retainedID] = retainedGeneration
        await ScanRepository.shared.eradicateScan(record: record, modelContext: context, allowsMutation: { true })?.value
        #expect(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.id) == [retainedID])
        #expect(queue.latestUploadGenerations[id] != generation)
        await queue.finishReanalysisErasure([retainedID], in: context.container)
        #expect(queue.latestUploadGenerations[retainedID] == retainedGeneration)
    }
}
