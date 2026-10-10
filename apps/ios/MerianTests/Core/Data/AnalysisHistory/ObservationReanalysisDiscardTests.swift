import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisDiscardTests {
    let fixture = ObservationReanalysisPreparationTests()

    @Test(arguments: [false, true])
    func discardsExactlyOnePreparationAndKeepsParentSelectionAndSibling(ready: Bool) throws {
        let seed = try fixture.fixture.seed(), (pending, source) = try fixture.pending(seed)
        let (sibling, _) = try fixture.pending(seed)
        try fixture.begin(pending, source: source, container: seed.container)
        try fixture.begin(sibling, source: source, container: seed.container)
        if ready {
            try ObservationReanalysisPersistence.validatePreparation(pending.verified(source: source), container: seed.container, isCurrent: { true }, makeReady: true)
        }
        let receipt = try discard(pending, source: source, container: seed.container)
        #expect(receipt.childID == pending.draft.identity.analysisID)
        let context = ModelContext(seed.container)
        let rows = try context.fetch(FetchDescriptor<OfflineQueuedScan>())
        #expect(rows.count == 1 && rows[0].work == .reanalysis(sibling.draft.identity))
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == source.analysisID.uuidString.lowercased() && parent.observationStateRevision == 10)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 2)
        #expect(try discard(pending, source: source, container: seed.container) == receipt)
        #expect(throws: (any Error).self) { try fixture.begin(pending, source: source, container: seed.container) }
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.stageDraft(pending.draft, container: seed.container, isCurrent: { true })
        }
    }

    @Test func discardBeforeFirstWriteRetiresIdentityAndReplaySurvivesParentDeletion() throws {
        let seed = try fixture.fixture.seed(), (pending, source) = try fixture.pending(seed)
        let receipt = try discard(pending, source: source, container: seed.container)
        #expect(throws: (any Error).self) { try fixture.begin(pending, source: source, container: seed.container) }
        let context = ModelContext(seed.container)
        context.delete(try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)); try context.save()
        #expect(try discard(pending, source: source, container: seed.container) == receipt)
    }

    @Test(arguments: ["attempt", "row-attempt", "last-attempt", "row-inferencing", "row-last-attempt", "staged-keys", "server-stage", "row-error-code", "row-error-message", "job-error-code", "job-error-message", "job-http", "job-status", "job-stage", "job-retry", "receipt-alias", "damaged-receipt", "deadline", "metadata", "missing-job", "bound", "complete", "owner", "source", "result"])
    func ambiguousAttemptedBoundOrForeignWorkCannotBeDiscarded(reason: String) throws {
        let seed = try fixture.fixture.seed(), (pending, source) = try fixture.pending(seed)
        try fixture.begin(pending, source: source, container: seed.container)
        let context = ModelContext(seed.container)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        switch reason {
        case "attempt": job.attemptCount = 1
        case "row-attempt": row.queueAttemptCount = 1
        case "last-attempt": job.lastAttemptAt = Date()
        case "row-inferencing": row.queueState = .inferencing
        case "row-last-attempt": row.queueLastAttemptAt = Date()
        case "staged-keys": row.stagedR2Keys = ["synthetic-key"]
        case "server-stage": row.queueLastServerStage = "synthetic-attempt"
        case "row-error-code": row.queueLastErrorCode = "synthetic-error"
        case "row-error-message": row.queueLastErrorMessage = "synthetic-error"
        case "job-error-code": job.lastErrorCode = "synthetic-error"
        case "job-error-message": job.lastErrorMessage = "synthetic-error"
        case "job-http": job.lastHTTPStatus = 503
        case "job-status": job.serverStatus = "synthetic-status"
        case "job-stage": job.serverStage = "synthetic-stage"
        case "job-retry": job.serverRetryAfter = Date()
        case "receipt-alias", "damaged-receipt":
            let child = pending.draft.identity.analysisID
            let key = reason == "receipt-alias" ? "reanalysis-erasure:" + child.uuidString : ObservationReanalysisErasureReceipt.jobID(child)
            context.insert(OfflineJobRecord(id: key, kind: .observationReanalysisErasure, subjectId: child.uuidString.lowercased(),
                status: .pending, metadataJSON: "{}"))
        case "deadline": job.nextRunAt = Date()
        case "metadata": job.metadataJSON = "{}"
        case "missing-job": context.delete(job)
        case "bound": job.metadataJSON = String(bytes: try pending.draft.binding(processor: .gemini).storedData(), encoding: .utf8)
        case "complete": job.status = .complete
        case "owner": row.reanalysisOwnerAccountID = UUID().uuidString.lowercased()
        case "source": row.sourceAnalysisID = UUID().uuidString.lowercased()
        default:
            context.insert(try LocalAnalysisRecord(analysisID: pending.draft.identity.analysisID, observationID: source.observationID.uuidString.lowercased(),
                ownerAccountID: source.ownerID, completedAt: seed.result.completedAt, snapshotVersion: seed.result.version, resultSnapshotData: seed.result.bytes))
        }
        try context.save()
        #expect(throws: (any Error).self) { try discard(pending, source: source, container: seed.container) }
        let fresh = ModelContext(seed.container)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        if reason != "damaged-receipt" {
            #expect(try fresh.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(pending.draft.identity.analysisID)) == nil)
        }
    }

    @Test func numericOnlyChildIdentityDoesNotCollideWithItsOwnCanonicalKeys() throws {
        let seed = try fixture.fixture.seed(), (original, source) = try fixture.pending(seed)
        let child = try #require(UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        let draft = try ObservationReanalysisDraft(identity: .init(observationID: source.observationID,
            sourceAnalysisID: source.analysisID, analysisID: child, ownerID: source.ownerID), evidence: original.draft.evidence)
        let pending = try ObservationReanalysisPreparationIntent(draft: draft, source: source)
        try fixture.begin(pending, source: source, container: seed.container)
        let receipt = try discard(pending, source: source, container: seed.container)
        #expect(try discard(pending, source: source, container: seed.container) == receipt)
    }

    @Test func saveFailureAndLateAccountLossRollBackBothRemovalAndReceipt() throws {
        for accountLoss in [false, true] {
            let seed = try fixture.fixture.seed(), (pending, source) = try fixture.pending(seed)
            try fixture.begin(pending, source: source, container: seed.container)
            var checks = 0
            #expect(throws: (any Error).self) {
                try ObservationReanalysisPersistence.discardPreparation(source: source, analysisID: pending.draft.identity.analysisID,
                    container: seed.container, isCurrent: { checks += 1; return !accountLoss || checks == 1 },
                    save: { _ in throw CocoaError(.fileWriteUnknown) })
            }
            let context = ModelContext(seed.container)
            #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
            #expect(try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(pending.draft.identity.analysisID)) == nil)
        }
    }

    @Test func discardDuringWritePreventsLateReadyCommitAndOnlyOwnedCleanupRuns() async throws {
        let seed = try fixture.fixture.seed(), (pending, source) = try fixture.pending(seed)
        try fixture.begin(pending, source: source, container: seed.container)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ObservationReanalysisFileStore(documents: root)
        await #expect(throws: (any Error).self) {
            try await files.persist(draft: pending.draft, photos: [Data([1, 2, 3])]) {
                _ = try discard(pending, source: source, container: seed.container)
                try ObservationReanalysisPersistence.validatePreparation(pending.verified(source: source), container: seed.container,
                    isCurrent: { true }, makeReady: true)
            }
        }
        let receipt = try discard(pending, source: source, container: seed.container)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        await ObservationReanalysisErasureOwner(files: files).drain(container: seed.container, isCurrent: { true })
        let job = try #require(try ModelContext(seed.container).fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(receipt.childID)))
        #expect(job.status == .complete)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(pending.draft.photoPaths[0]).path))
    }

    private func discard(_ pending: ObservationReanalysisPreparationIntent, source: ObservationReanalysisSource,
                         container: ModelContainer) throws -> ObservationReanalysisErasureReceipt {
        try ObservationReanalysisPersistence.discardPreparation(source: source, analysisID: pending.draft.identity.analysisID,
            container: container, isCurrent: { true })
    }
}
