import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisPreparationTests {
    let fixture = ObservationReanalysisSourceTests()

    func pending(_ seed: ObservationReanalysisSourceTests.Seed) throws -> (ObservationReanalysisPreparationIntent, ObservationReanalysisSource) {
        let source = try ObservationReanalysisSource.capture(observationID: seed.observationID, ownerID: fixture.fixture.owner, container: seed.container)
        let photo = try ObservationReanalysisPersistenceTests().intent().request.evidence
        let draft = try ObservationReanalysisDraft(identity: .init(observationID: source.observationID, sourceAnalysisID: source.analysisID,
            analysisID: UUID(), ownerID: source.ownerID), evidence: photo)
        return (try .init(draft: draft, source: source), source)
    }

    func begin(_ pending: ObservationReanalysisPreparationIntent, source: ObservationReanalysisSource, container: ModelContainer) throws {
        let ready = try ObservationReanalysisPersistence.beginPreparation(pending.verified(source: source), container: container,
            isCurrent: { true })
        #expect(ready == nil)
    }

    @Test func pendingIsDurableButCannotBindOrMasqueradeAsReady() throws {
        let seed = try fixture.seed(), (pending, source) = try pending(seed)
        try begin(pending, source: source, container: seed.container)
        try begin(pending, source: source, container: seed.container)
        let context = ModelContext(seed.container)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let bytes = Data(try #require(job.metadataJSON).utf8)
        #expect(try ObservationReanalysisPreparationIntent.decode(bytes) == pending)
        #expect(row.work == .reanalysis(pending.draft.identity) && row.queueNeedsAttention && job.nextRunAt == nil)
        #expect(throws: (any Error).self) { try ObservationReanalysisDraft.decode(bytes) }
        #expect(throws: (any Error).self) { try ObservationReanalysisPersistence.restore(row: row, job: job) }
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.bindDraft(pending.draft, processor: .gemini, container: seed.container, isCurrent: { true })
        }
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.stageDraft(pending.draft, container: seed.container, isCurrent: { true })
        }
    }

    @Test func failedReadySaveRetainsExactPendingThenOneCASBecomesReady() throws {
        let seed = try fixture.seed(), (pending, source) = try pending(seed)
        try begin(pending, source: source, container: seed.container)
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.validatePreparation(pending.verified(source: source), container: seed.container, isCurrent: { true }, makeReady: true, save: { _ in throw CocoaError(.fileWriteUnknown) })
        }
        try ObservationReanalysisPersistence.validatePreparation(pending.verified(source: source), container: seed.container, isCurrent: { true }, makeReady: true)
        let ready = try ObservationReanalysisPersistence.beginPreparation(pending.verified(source: source), container: seed.container, isCurrent: { true })
        guard case let .draft(draft) = ready else { Issue.record("Expected ready replay"); return }
        #expect(draft == pending.draft)
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.validatePreparation(pending.verified(source: source), container: seed.container, isCurrent: { true }, makeReady: true)
        }
    }

    @Test func parentErasureRetainsReceiptAndBlocksLateWritesAndReinsertion() async throws {
        let seed = try fixture.seed(), (pending, source) = try pending(seed)
        try begin(pending, source: source, container: seed.container)
        let context = ModelContext(seed.container)
        _ = try ObservationReanalysisErasure.removeChildren(of: source.observationID.uuidString, context: context)
        try context.save() // Keep parent deliberately: the durable receipt alone must prevent reuse.
        let receipt = try #require(try ModelContext(seed.container).fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(pending.draft.identity.analysisID)))
        #expect(try ObservationReanalysisErasureReceipt.restore(receipt).parentID == source.observationID)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: (any Error).self) {
            try await ObservationReanalysisFileStore(documents: root).persist(draft: pending.draft, photos: [Data([1, 2, 3])], validateBeforeWrite: {
                try ObservationReanalysisPersistence.validatePreparation(pending.verified(source: source), container: seed.container, isCurrent: { true })
            }) { Issue.record("Deleted preparation committed"); return false }
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(pending.draft.photoPaths[0]).path))
        #expect(throws: (any Error).self) { try begin(pending, source: source, container: seed.container) }
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.stageDraft(pending.draft, container: seed.container, isCurrent: { true })
        }
    }

    @Test func deletionDuringFileWriteCannotRecreateChild() async throws {
        let seed = try fixture.seed(), (pending, source) = try pending(seed)
        try begin(pending, source: source, container: seed.container)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: (any Error).self) {
            try await ObservationReanalysisFileStore(documents: root).persist(draft: pending.draft, photos: [Data([1, 2, 3])]) {
                let context = ModelContext(seed.container)
                _ = try ObservationReanalysisErasure.removeChildren(of: source.observationID.uuidString, context: context)
                try context.save()
                try ObservationReanalysisPersistence.validatePreparation(pending.verified(source: source), container: seed.container, isCurrent: { true }, makeReady: true)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(pending.draft.photoPaths[0]).path))
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

    @Test func malformedAndChangedSourceDigestNeverAdoptExistingPending() throws {
        let seed = try fixture.seed(), (pending, source) = try pending(seed)
        try begin(pending, source: source, container: seed.container)
        let bytes = try pending.storedData()
        for key in ["version", "phase", "source_snapshot_sha256", "extra"] {
            var body = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            body[key] = key == "version" ? true : "invalid"
            #expect(throws: (any Error).self) { try ObservationReanalysisPreparationIntent.decode(JSONSerialization.data(withJSONObject: body)) }
        }
        var body = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        body["source_snapshot_sha256"] = String(repeating: "0", count: 64)
        let changed = try ObservationReanalysisPreparationIntent.decode(JSONSerialization.data(withJSONObject: body))
        #expect(throws: (any Error).self) { try begin(changed, source: source, container: seed.container) }
    }

    @Test func forgedDigestCannotAdmitFreshPreparation() throws {
        let seed = try fixture.seed(), (pending, source) = try pending(seed)
        var body = try #require(JSONSerialization.jsonObject(with: pending.storedData()) as? [String: Any])
        body["source_snapshot_sha256"] = String(repeating: "0", count: 64)
        let changed = try ObservationReanalysisPreparationIntent.decode(JSONSerialization.data(withJSONObject: body))
        #expect(throws: (any Error).self) { try changed.verified(source: source) }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test(arguments: ["begin", "prewrite", "ready"])
    func replacedSourceBytesInvalidateAlreadyVerifiedProof(phase: String) throws {
        let seed = try fixture.seed(), (pending, source) = try pending(seed)
        let proof = try pending.verified(source: source)
        if phase != "begin" { try begin(pending, source: source, container: seed.container) }
        let context = ModelContext(seed.container)
        let record = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let object = try JSONSerialization.jsonObject(with: record.resultSnapshotData)
        let replacement = try LocalAnalysisRecord(analysisID: source.analysisID, observationID: parent.id, ownerAccountID: source.ownerID,
            completedAt: record.completedAt, snapshotVersion: record.snapshotVersion,
            resultSnapshotData: JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]))
        context.delete(record); try context.save()
        context.insert(replacement); parent.analysisRecords = [replacement]; try context.save()
        #expect(throws: (any Error).self) {
            if phase == "begin" {
                _ = try ObservationReanalysisPersistence.beginPreparation(proof, container: seed.container, isCurrent: { true })
            } else {
                try ObservationReanalysisPersistence.validatePreparation(proof, container: seed.container, isCurrent: { true }, makeReady: phase == "ready")
            }
        }
    }
}
