import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAnalysisReviewPersistenceTests {
    typealias Store = ObservationAnalysisReviewPersistence
    let owner = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let observation = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
    let analysis = UUID(uuidString: "10000000-0000-4000-8000-000000000003")!
    let operation = UUID(uuidString: "10000000-0000-4000-8000-000000000004")!
    let now = Date(timeIntervalSince1970: 1_780_000_000)

    func request(_ decision: ObservationAnalysisReviewRequest.Decision = .reject, operationID: UUID? = nil,
                 observationRevision: Int = 3, reviewRevision: Int = 1) throws -> ObservationAnalysisReviewRequest {
        try .init(observationID: observation, analysisID: analysis, operationID: operationID ?? operation,
                  expectedObservationRevision: observationRevision, expectedReviewRevision: reviewRevision, decision: decision)
    }
    func container(url: URL? = nil, seed: Bool = true) throws -> ModelContainer {
        let schema = Schema(CurrentSchema.models)
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        if seed {
            let context = ModelContext(container)
            let scan = LocalScanRecord(id: observation.uuidString, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
            scan.analysisOwnerAccountID = owner.uuidString.lowercased(); scan.analysisSelectionInitialized = true
            scan.selectedAnalysisID = analysis.uuidString.lowercased(); scan.observationStateRevision = 3
            scan.isBiological = false
            context.insert(scan)
            let child = try LocalAnalysisRecord(analysisID: analysis, observationID: scan.id, ownerAccountID: owner,
                completedAt: now, resultSnapshotData: Data("{\"synthetic\":true}".utf8))
            let state = try LocalAnalysisStateRecord(analysisID: analysis, observationID: scan.id, ownerAccountID: owner,
                observationStateRevision: 3, reviewRevision: 1, reviewSnapshotData: Data("{}".utf8))
            context.insert(child); context.insert(state); child.state = state; scan.analysisRecords = [child]; try context.save()
        }
        return container
    }
    func stage(_ container: ModelContainer, request: ObservationAnalysisReviewRequest? = nil) throws -> ObservationAnalysisReviewIntent {
        try Store.stage(request ?? self.request(), ownerID: owner, container: container, isCurrent: { true }, validateNew: { _ in })
    }
    func receipt(_ request: ObservationAnalysisReviewRequest, outcome: String = "applied") throws -> ObservationAnalysisReviewReceipt {
        var row = try #require(JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any])
        row["outcome"] = outcome
        if outcome == "applied" {
            row["observation_revision"] = request.expectedObservationRevision + 1
            row["review_revision"] = request.expectedReviewRevision + 1
        }
        return try .decode(JSONSerialization.data(withJSONObject: row), request: request)
    }
    func claim(_ intent: ObservationAnalysisReviewIntent, in container: ModelContainer, at date: Date? = nil) throws -> Store.Claim {
        try #require(try Store.claim(intent, at: date ?? now, container: container, isCurrent: { true }))
    }
    func acknowledge(_ intent: ObservationAnalysisReviewIntent, in container: ModelContainer,
                     outcome: String = "applied") throws -> ObservationAnalysisReviewIntent {
        try Store.acknowledge(receipt(intent.request, outcome: outcome), claim: claim(intent, in: container), at: now,
                              container: container, isCurrent: { true })
    }

    /// Fixture for the future atomic paired-state settlement, not a production completion API.
    func advanceCache(_ container: ModelContainer, observationRevision: Int = 4, reviewRevision: Int = 2) throws {
        let context = ModelContext(container)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let state = try #require(context.fetch(FetchDescriptor<LocalAnalysisStateRecord>()).first)
        scan.observationStateRevision = observationRevision
        try state.update(observationStateRevision: observationRevision, reviewRevision: reviewRevision, reviewSnapshotData: Data("{}".utf8), displaySnapshotData: nil)
        let job = try #require(try context.fetchOfflineJob(id: Store.jobID(operation, observationID: observation)))
        let saved = try Store.restore(job)
        try #require(saved.hasReceipt)
        var row = try #require(JSONSerialization.jsonObject(with: saved.storedData()) as? [String: Any])
        row["reconciled_at"] = now.timeIntervalSince1970
        let data = try JSONSerialization.data(withJSONObject: row)
        job.metadataJSON = try #require(String(bytes: data, encoding: .utf8)); job.status = .complete; job.nextRunAt = nil
        try context.save()
    }

    @Test(arguments: ["applied", "revision_conflict", "not_verified"])
    func receiptsPersistBeforeReconciliationWithoutChangingProjection(outcome: String) throws {
        let container = try container(), pending = try stage(container, request: request(.confirmPrimary))
        let received = try acknowledge(pending, in: container, outcome: outcome)
        let reopened = try ObservationAnalysisReviewIntent.decode(received.storedData())
        #expect(reopened.hasReceipt && !reopened.isComplete && reopened.request == pending.request)
        #expect(reopened.requestSHA256 == pending.requestSHA256 && reopened.observedAt == now)
        let context = ModelContext(container)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(scan.selectedAnalysisID == analysis.uuidString.lowercased() && scan.observationStateRevision == 3)
        let job = try #require(try context.fetchOfflineJob(id: Store.jobID(operation, observationID: observation)))
        #expect(job.status == .waiting && job.nextRunAt == nil)
        let recovery = try claim(reopened, in: container)
        #expect(throws: (any Error).self) { try Store.requireDispatch(recovery, at: now, container: container, isCurrent: { true }) }
    }

    @Test func exactReplayPrecedesNewPreflightAndNeverReopensReceipt() throws {
        let container = try container(), pending = try stage(container), received = try acknowledge(pending, in: container)
        let context = ModelContext(container), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        scan.observationStateRevision = 8; try context.save()
        let replay = try Store.stage(request(), ownerID: owner, container: container, isCurrent: { true },
                                    validateNew: { _ in throw Store.IntegrityError.conflict })
        #expect(try replay.storedData() == received.storedData())
        #expect(throws: (any Error).self) { try stage(container, request: request(.confirmPrimary)) }
        #expect(throws: (any Error).self) { try stage(container, request: request(operationID: UUID())) }
    }

    @Test func newDecisionWaitsForPreviousReceiptReconciliation() throws {
        let container = try container(), pending = try stage(container)
        let next = try request(.confirmPrimary, operationID: UUID())
        #expect(throws: (any Error).self) { try stage(container, request: next) }
        _ = try acknowledge(pending, in: container)
        #expect(throws: (any Error).self) { try stage(container, request: next) }
        try advanceCache(container)
        let after = try request(.confirmPrimary, operationID: UUID(), observationRevision: 4, reviewRevision: 2)
        #expect(try stage(container, request: after).request == after)
    }

    @Test func fingerprintPreservesEveryDecisionAndByteExactName() throws {
        let first = try ObservationAnalysisReviewIntent(request: request(.confirmName("é")), ownerID: owner)
        let normalized = try ObservationAnalysisReviewIntent(request: request(.confirmName("e\u{301}")), ownerID: owner)
        #expect(first.requestSHA256 != normalized.requestSHA256)
        #expect(try ObservationAnalysisReviewIntent.decode(first.storedData()).request == first.request)
        for changed in [try request(.confirmPrimary), try request(.reject), try request(.undo(rejectionOperationID: UUID())),
                        try request(.confirmName("é"), observationRevision: 4), try request(.confirmName("é"), reviewRevision: 2)] {
            #expect(try ObservationAnalysisReviewIntent.fingerprint(changed) != first.requestSHA256)
        }
    }

    @Test func corruptEnvelopesAndReceiptRebindingFailClosed() throws {
        let original = try ObservationAnalysisReviewIntent(request: request(), ownerID: owner)
        let received = try original.accepting(receipt(original.request), at: now)
        let row = try #require(JSONSerialization.jsonObject(with: received.storedData()) as? [String: Any])
        for key in row.keys {
            var damaged = row; damaged.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try ObservationAnalysisReviewIntent.decode(JSONSerialization.data(withJSONObject: damaged)) }
        }
        for (key, value) in [("version", true), ("request_sha256", "wrong"), ("observed_at", true),
                             ("reconciled_at", -1), ("reconciled_at", now.addingTimeInterval(-1).timeIntervalSince1970), ("receipt", NSNull()), ("extra", "unrecognized")] as [(String, Any)] {
            var damaged = row; damaged[key] = value
            #expect(throws: (any Error).self) { try ObservationAnalysisReviewIntent.decode(JSONSerialization.data(withJSONObject: damaged)) }
        }
        #expect(throws: (any Error).self) { try original.accepting(receipt(request(.confirmPrimary)), at: now) }
        #expect(throws: (any Error).self) { try received.accepting(receipt(original.request, outcome: "revision_conflict"), at: now) }
        #expect(try received.accepting(receipt(original.request), at: now.addingTimeInterval(50)).observedAt == now)
    }

    @Test func undoRequiresAnAppliedSameTargetRejectAssociation() throws {
        let container = try container(), reject = try stage(container)
        let undo = try request(.undo(rejectionOperationID: operation), operationID: UUID(), observationRevision: 4, reviewRevision: 2)
        #expect(throws: (any Error).self) { try stage(container, request: undo) }
        _ = try acknowledge(reject, in: container)
        #expect(throws: (any Error).self) { try stage(container, request: undo) }
        try advanceCache(container)
        #expect(try stage(container, request: undo).request == undo)
        let unknown = try request(.undo(rejectionOperationID: UUID()), operationID: UUID())
        #expect(throws: (any Error).self) { try stage(container, request: unknown) }
    }

    @Test(arguments: [2, 3])
    func undoAllowsOtherObservationChangesButNeverLaterTargetReview(reviewRevision: Int) throws {
        let container = try container(), rejected = try stage(container)
        _ = try acknowledge(rejected, in: container)
        try advanceCache(container, observationRevision: 5, reviewRevision: reviewRevision)
        let undo = try request(.undo(rejectionOperationID: operation), operationID: UUID(),
                               observationRevision: 5, reviewRevision: reviewRevision)
        if reviewRevision == 2 {
            #expect(try stage(container, request: undo).request == undo)
        } else {
            #expect(throws: (any Error).self) { try stage(container, request: undo) }
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
        }
    }

    @Test(arguments: ["revision_conflict", "not_verified"])
    func negativeReceiptCannotAuthorizeUndo(outcome: String) throws {
        let container = try container(), pending = try stage(container, request: request(outcome == "not_verified" ? .confirmPrimary : .reject))
        _ = try acknowledge(pending, in: container, outcome: outcome)
        try advanceCache(container, observationRevision: 3, reviewRevision: 1)
        #expect(throws: (any Error).self) {
            try stage(container, request: request(.undo(rejectionOperationID: operation), operationID: UUID()))
        }
    }

    @Test func claimGenerationFencesLateWritersAndNeverChangesRequest() throws {
        let container = try container(), pending = try stage(container), first = try claim(pending, in: container)
        #expect(try Store.claim(pending, at: now, container: container, isCurrent: { true }) == nil)
        try Store.requireDispatch(first, at: now, container: container, isCurrent: { true })
        let second = try claim(pending, in: container, at: first.expiresAt)
        #expect(second.attempt == first.attempt + 1 && second.intent.request == first.intent.request)
        #expect(throws: (any Error).self) { try Store.retry(first, at: now, needsAttention: false, container: container, isCurrent: { true }) }
        #expect(throws: (any Error).self) {
            try Store.acknowledge(receipt(pending.request), claim: first, at: now, container: container, isCurrent: { true })
        }
        #expect(throws: (any Error).self) { try Store.requireDispatch(second, at: second.expiresAt, container: container, isCurrent: { true }) }
        let received = try Store.acknowledge(receipt(pending.request), claim: second, at: second.expiresAt.addingTimeInterval(1),
                                             container: container, isCurrent: { true })
        #expect(received.hasReceipt)
    }

    @Test func needsAttentionNeverAutomaticallyRearmsAndFailedSavesRollback() throws {
        let container = try container(), pending = try stage(container), claimed = try claim(pending, in: container)
        #expect(throws: (any Error).self) {
            try Store.acknowledge(receipt(pending.request), claim: claimed, at: now, container: container, isCurrent: { true },
                                  save: { _ in throw Store.IntegrityError.unavailable })
        }
        try Store.requireDispatch(claimed, at: now, container: container, isCurrent: { true })
        try Store.retry(claimed, at: now, needsAttention: true, container: container, isCurrent: { true })
        #expect(try Store.candidates(container: container, ownerID: owner).isEmpty)
        #expect(try Store.claim(pending, at: now.addingTimeInterval(600), container: container, isCurrent: { true }) == nil)
        #expect(try stage(container).request == pending.request)
    }

    @Test(arguments: [false, true])
    func malformedNamespaceBlocksOnlyItsObservation(sameObservation: Bool) throws {
        let container = try container(), context = ModelContext(container)
        let scope = sameObservation ? observation : UUID()
        context.insert(OfflineJobRecord(id: Store.jobID(UUID(), observationID: scope), kind: .future,
                                        subjectId: nil, metadataJSON: "damaged"))
        try context.save()
        if sameObservation {
            #expect(throws: (any Error).self) { try stage(container) }
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
        } else {
            #expect(try stage(container).request == request())
        }
    }

    @Test func accountChangeAndFreshRevisionMismatchNeverCommit() throws {
        let container = try container()
        var checks = 0
        #expect(throws: (any Error).self) {
            try Store.stage(request(), ownerID: owner, container: container, isCurrent: { checks += 1; return checks == 1 }, validateNew: { _ in })
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        #expect(throws: (any Error).self) { try stage(container, request: request(reviewRevision: 0)) }
        #expect(throws: (any Error).self) {
            try Store.stage(request(), ownerID: UUID(), container: container, isCurrent: { true }, validateNew: { _ in })
        }
        let pending = try stage(container), claimed = try claim(pending, in: container); checks = 0
        #expect(throws: (any Error).self) {
            try Store.acknowledge(receipt(pending.request), claim: claimed, at: now, container: container,
                                  isCurrent: { checks += 1; return checks == 1 })
        }
        try Store.requireDispatch(claimed, at: now, container: container, isCurrent: { true })
    }

    @Test func candidateReferenceAndReceiptSurviveDiskReopenWithoutRebinding() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("candidate.store")
        let reference = try ObservationAnalysisCandidateReference(analysisID: analysis, ordinal: 1, scientificName: "Synthetic candidate")
        let original = try request(.confirmCandidate(reference))
        func write() throws {
            let container = try container(url: url), pending = try stage(container, request: original)
            _ = try acknowledge(pending, in: container)
        }
        try write()
        let reopened = try container(url: url, seed: false)
        let saved = try stage(reopened, request: original)
        #expect(saved.hasReceipt && saved.request == original)
        #expect(saved.requestSHA256 == (try ObservationAnalysisReviewIntent.fingerprint(original)))
        let different = try ObservationAnalysisCandidateReference(analysisID: analysis, ordinal: 0, scientificName: reference.scientificName)
        #expect(throws: (any Error).self) { try stage(reopened, request: request(.confirmCandidate(different))) }
        #expect(throws: (any Error).self) { try stage(reopened, request: request(.confirmName(reference.scientificName))) }
        let receiptClaim = try claim(saved, in: reopened)
        #expect(throws: (any Error).self) { try Store.requireDispatch(receiptClaim, at: now, container: reopened, isCurrent: { true }) }
    }

    @Test func receiptAndRejectAssociationSurviveDiskReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("review.store")
        func write() throws {
            let container = try container(url: url), pending = try stage(container)
            _ = try acknowledge(pending, in: container)
        }
        try write()
        let reopened = try container(url: url, seed: false), saved = try stage(reopened)
        #expect(saved.hasReceipt && !saved.isComplete && saved.observedAt == now)
        try advanceCache(reopened)
        #expect(try stage(reopened).isComplete)
        #expect(try stage(reopened, request: request(.undo(rejectionOperationID: operation), operationID: UUID(), observationRevision: 4, reviewRevision: 2)).request.decision == .undo(rejectionOperationID: operation))
    }
}
