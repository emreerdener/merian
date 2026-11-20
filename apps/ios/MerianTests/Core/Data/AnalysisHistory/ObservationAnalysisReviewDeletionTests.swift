import Foundation
@testable import Merian
import SwiftData
import Testing

extension ObservationAnalysisReviewPersistenceTests {
    @Test(arguments: [false, true])
    func directAndBulkDeletionEraseReceiptsAndRejectLateAcknowledgements(bulk: Bool) async throws {
        let container = try container(), original = try stage(container)
        _ = try acknowledge(original, in: container)
        // The primary key must retain erasure reachability after metadata damage.
        let damage = ModelContext(container)
        let job = try #require(try damage.fetchOfflineJob(id: Store.jobID(operation, observationID: observation)))
        job.subjectId = nil; job.metadataJSON = "damaged"; job.kindRaw = "future-corruption"
        try damage.save()
        if bulk {
            _ = try await BackgroundDatabaseActor(modelContainer: container).bulkDeleteNonBiologicalScans(
                payloads: [.init(id: observation.uuidString, mediaPaths: [])], requestingAccountID: owner)
        } else {
            let manager = OfflineQueueManager.shared, previous = manager.modelContext, online = manager.isOnline
            manager.modelContext = ModelContext(container); manager.isOnline = false
            defer { manager.modelContext = previous; manager.isOnline = online }
            let context = ModelContext(container), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
            await ScanRepository.shared.eradicateScan(record: scan, modelContext: context, allowsMutation: { true })?.value
        }
        #expect(try ModelContext(container).fetchOfflineJob(id: Store.jobID(operation, observationID: observation)) == nil)
        #expect(throws: (any Error).self) { try stage(container) }
        #expect(throws: (any Error).self) {
            try Store.claim(original, at: now, container: container, isCurrent: { true })
        }
    }

    @Test func sameOperationOnAnotherObservationConflictsAndDeletionDoesNotCrossNamespaces() throws {
        let container = try container(); _ = try stage(container)
        let context = ModelContext(container), other = UUID(), otherAnalysis = UUID()
        let scan = LocalScanRecord(id: other.uuidString, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        scan.analysisOwnerAccountID = owner.uuidString.lowercased(); scan.analysisSelectionInitialized = true
        scan.selectedAnalysisID = otherAnalysis.uuidString.lowercased(); scan.observationStateRevision = 3
        let child = try LocalAnalysisRecord(analysisID: otherAnalysis, observationID: scan.id, ownerAccountID: owner,
            completedAt: now, resultSnapshotData: Data("{\"synthetic\":true}".utf8))
        let state = try LocalAnalysisStateRecord(analysisID: otherAnalysis, observationID: scan.id, ownerAccountID: owner,
            observationStateRevision: 3, reviewRevision: 1, reviewSnapshotData: Data("{}".utf8))
        context.insert(scan); context.insert(child); context.insert(state); child.state = state
        scan.analysisRecords = [child]; try context.save()
        let reused = try ObservationAnalysisReviewRequest(observationID: other, analysisID: otherAnalysis, operationID: operation,
            expectedObservationRevision: 3, expectedReviewRevision: 1, decision: .reject)
        #expect(throws: (any Error).self) {
            try Store.stage(reused, ownerID: owner, container: container, isCurrent: { true }, validateNew: { _ in })
        }
        let job = try #require(try context.fetchOfflineJob(id: Store.jobID(operation, observationID: observation)))
        job.subjectId = other.uuidString.lowercased(); try context.save()
        try Store.removeForDeletion(other.uuidString, context: context)
        try context.save()
        #expect(try context.fetchOfflineJob(id: job.id) != nil)
    }

    @Test func cloudCleanupUsesOwnerAndPrimaryKeyWhenSubjectIsMissing() throws {
        let container = try container(); _ = try stage(container)
        let context = ModelContext(container), id = Store.jobID(operation, observationID: observation)
        let job = try #require(try context.fetchOfflineJob(id: id)); job.subjectId = nil; try context.save()
        try Store.removeForDeletion(observation.uuidString, context: context, ownerID: owner)
        try context.save(); #expect(try context.fetchOfflineJob(id: id) == nil)
        _ = try stage(container)
        let damaged = try #require(try context.fetchOfflineJob(id: id)); damaged.metadataJSON = "damaged"; try context.save()
        #expect(throws: (any Error).self) {
            try Store.removeForDeletion(observation.uuidString, context: context, ownerID: owner)
        }
        #expect(try context.fetchOfflineJob(id: id) != nil)
    }

    @Test func cloudCleanupScopesOwnerAndExplicitDeletionErasesDamagedNamespace() throws {
        let container = try container(); _ = try stage(container)
        let context = ModelContext(container), id = Store.jobID(operation, observationID: observation)
        try Store.removeForDeletion(observation.uuidString, context: context, ownerID: UUID())
        try context.save(); #expect(try context.fetchOfflineJob(id: id) != nil)
        try Store.removeForDeletion(observation.uuidString, context: context, ownerID: owner)
        context.rollback(); #expect(try ModelContext(container).fetchOfflineJob(id: id) != nil)
        let job = try #require(try context.fetchOfflineJob(id: id))
        job.kindRaw = "unknown-future"; job.subjectId = nil; job.metadataJSON = "damaged"; try context.save()
        try Store.removeForDeletion(observation.uuidString, context: context)
        try context.save(); #expect(try ModelContext(container).fetchOfflineJob(id: id) == nil)
    }
}
