import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct RejectionUndoEligibilityTests {
    struct Fixture {
        let container: ModelContainer
        let ticket: ObservationAnalysisReviewTicket
        let operation: UUID
    }
    func seed(audio: Bool = false) async throws -> Fixture {
        let support = ObservationAnalysisReviewAdmissionTests(), source = support.source
        let (container, _) = try await support.seed(audio: audio)
        let operation = UUID()
        try source.update(container) { scan, _ in
            let state = try #require(scan.analysisRecords?.first?.state)
            var authority = try #require(JSONSerialization.jsonObject(with: state.reviewSnapshotData) as? [String: Any])
            authority["user_review_state"] = "unreviewed"
            authority["user_confirmed_identification"] = false
            authority["user_identification_override"] = NSNull()
            // Nested counter intentionally differs from the outer target revision.
            authority["ai_identification_review"] = ["version": 1, "revision": 7, "state": "ai_rejected",
                "origin_scan_id": scan.id.lowercased(), "origin_identification": NSNull(),
                "operation_id": operation.uuidString.lowercased(), "operation_digest": String(repeating: "a", count: 32), "community": NSNull()]
            scan.observationStateRevision = 11
            try state.update(observationStateRevision: 11, reviewRevision: 2,
                reviewSnapshotData: JSONSerialization.data(withJSONObject: authority), displaySnapshotData: state.displaySnapshotData)
        }
        let context = ModelContext(container)
        let scan = try ObservationHistorySyncService.enrolledScan(source.support.observation, context: context)
        let entry = try ObservationHistoryListingService.entry(UUID(uuidString: source.analysisID)!, scan: scan, context: context)
        let ticket = try ObservationAnalysisReviewTicket(entry: entry,
            context: .init(owner: source.support.owner, selected: entry.result.analysisID, revision: 11, pendingOperation: nil, undoOperation: nil),
            observationID: UUID(uuidString: scan.id)!)
        return Fixture(container: container, ticket: ticket, operation: operation)
    }
    func recovered(_ ticket: ObservationAnalysisReviewTicket, operation: UUID) throws -> ObservationRejectionUndoEligibility {
        let lookup = ObservationRejectionUndoEligibility.lookup(ticket)
        var row = try lookup.object()
        row["status"] = "available"; row["rejection_operation_id"] = operation.uuidString.lowercased()
        let reply = try ObservationRejectionUndoReply(data: JSONSerialization.data(withJSONObject: row), request: lookup)
        guard case let .available(value) = try ObservationRejectionUndoEligibility.recovered(reply, ticket: ticket) else {
            throw ObservationHistoryError.unavailable
        }
        return value
    }
    @Test func lookupRejectsSubstitutionPrivateFieldsAndUnsupportedBounds() throws {
        let lookup = ObservationRejectionUndoLookup(observationID: UUID(), analysisID: UUID(), observationRevision: 9, reviewRevision: 2)
        var row = try lookup.object()
        row["status"] = "available"; row["rejection_operation_id"] = UUID().uuidString.lowercased()
        _ = try ObservationRejectionUndoReply(data: JSONSerialization.data(withJSONObject: row), request: lookup)
        for patch: [String: Any] in [["expected_review_revision": 3], ["expected_review_revision": true],
            ["analysis_id": UUID().uuidString.lowercased()], ["receipt": [:]], ["confirmation_action": "confirm_name"]] {
            #expect(throws: (any Error).self) {
                try ObservationRejectionUndoReply(data: JSONSerialization.data(withJSONObject: row.merging(patch) { _, new in new }), request: lookup)
            }
        }
        #expect(throws: (any Error).self) { try ObservationRejectionUndoReply(data: Data(repeating: 32, count: 4097), request: lookup) }
        let unsupported = ObservationRejectionUndoLookup(observationID: lookup.observationID, analysisID: lookup.analysisID,
            observationRevision: 2_147_483_647, reviewRevision: 2)
        #expect(throws: (any Error).self) { try unsupported.object() }
    }
    @Test(arguments: [false, true]) func secondDeviceStagesWithoutOriginalReceipt(audio: Bool) async throws {
        let fixture = try await seed(audio: audio)
        let container = fixture.container, ticket = fixture.ticket, operation = fixture.operation
        let eligibility = try recovered(ticket, operation: operation)
        #expect(try ObservationRejectionUndoEligibility.local(ticket, context: ModelContext(container)) == nil)
        #expect(eligibility.source == .recovered && ticket.reviewRevision == 2)
        let request = try ticket.request(.undo(rejectionOperationID: operation), operationID: UUID())
        let intent = try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: container,
            isCurrent: { true }, rejectionUndo: eligibility)
        #expect(intent.request == request)
        let scan = try ObservationHistorySyncService.enrolledScan(ticket.observationID.uuidString, context: ModelContext(container))
        #expect(scan.selectedAnalysisID == ticket.selectedAnalysisID.uuidString.lowercased())
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
        try advance(fixture)
        // Persisted identity recovers before fresh eligibility, even after authority advances.
        let replay = try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: container, isCurrent: { true })
        #expect(replay.request == request)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }
    private func advance(_ fixture: Fixture) throws {
        try ObservationAnalysisReviewAdmissionTests().source.update(fixture.container) { scan, _ in
            let state = try #require(scan.analysisRecords?.first?.state)
            scan.observationStateRevision = 12
            try state.update(observationStateRevision: 12, reviewRevision: 3,
                reviewSnapshotData: state.reviewSnapshotData, displaySnapshotData: state.displaySnapshotData)
        }
    }
    @Test func recoveredEligibilityCannotCrossRevisionOrAccountLoss() async throws {
        let fixture = try await seed(), ticket = fixture.ticket
        let eligibility = try recovered(ticket, operation: fixture.operation)
        let request = try ticket.request(.undo(rejectionOperationID: fixture.operation), operationID: UUID())
        #expect(throws: (any Error).self) {
            try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: fixture.container,
                isCurrent: { false }, rejectionUndo: eligibility)
        }
        try advance(fixture)
        #expect(throws: (any Error).self) {
            try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: fixture.container,
                isCurrent: { true }, rejectionUndo: eligibility)
        }
        #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }
    @Test func noEligibilityOrSubstitutedAssociationCannotStage() async throws {
        let fixture = try await seed()
        let container = fixture.container, ticket = fixture.ticket, operation = fixture.operation
        let request = try ticket.request(.undo(rejectionOperationID: operation), operationID: UUID())
        #expect(throws: (any Error).self) {
            try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: container, isCurrent: { true })
        }
        #expect(throws: (any Error).self) { try recovered(ticket, operation: UUID()) }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }
    @Test func localReceiptMatchesOuterRevisionDespiteOlderParentAndDifferentNestedCounter() async throws {
        let fixture = try await seed(), ticket = fixture.ticket
        let request = try ObservationAnalysisReviewRequest(observationID: ticket.observationID, analysisID: ticket.analysisID,
            operationID: fixture.operation, expectedObservationRevision: 1, expectedReviewRevision: 1, decision: .reject)
        var row = try #require(JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any])
        row["outcome"] = "applied"; row["observation_revision"] = 2; row["review_revision"] = 2
        let receipt = try ObservationAnalysisReviewReceipt.decode(JSONSerialization.data(withJSONObject: row), request: request)
        let now = Date()
        let accepted = try ObservationAnalysisReviewIntent(request: request, ownerID: ticket.ownerID).accepting(receipt, at: now)
        var metadata = try #require(JSONSerialization.jsonObject(with: accepted.storedData()) as? [String: Any])
        metadata["reconciled_at"] = now.timeIntervalSince1970
        let job = OfflineJobRecord(id: ObservationAnalysisReviewPersistence.jobID(fixture.operation, observationID: ticket.observationID),
            kind: .observationAnalysisReviewSync, subjectId: ticket.observationID.uuidString.lowercased(),
            metadataJSON: try #require(String(bytes: JSONSerialization.data(withJSONObject: metadata), encoding: .utf8)))
        job.status = .complete
        let context = ModelContext(fixture.container); context.insert(job); try context.save()
        let eligibility = try #require(try ObservationRejectionUndoEligibility.local(ticket, context: ModelContext(fixture.container)))
        #expect(eligibility.source == .local && ticket.observationRevision == 11 && ticket.reviewRevision == 2)
        try eligibility.validate(ticket: ticket, context: ModelContext(fixture.container))
    }

    @Test(arguments: ["selection", "legacy", "delete", "owner"])
    func recoveredAdmissionRechecksDurableFences(change: String) async throws {
        let fixture = try await seed(), ticket = fixture.ticket
        let eligibility = try recovered(ticket, operation: fixture.operation)
        let request = try ticket.request(.undo(rejectionOperationID: fixture.operation), operationID: UUID())
        try ObservationAnalysisReviewAdmissionTests().source.update(fixture.container) { scan, context in
            switch change {
            case "selection":
                let selection = ObservationHistorySelectionRequest(observation: ticket.observationID,
                    analysis: UUID(), revision: ticket.observationRevision, review: 0)
                try ObservationHistorySelectionIntent.store(.init(version: 1,
                    owner: ticket.ownerID.uuidString.lowercased(), previous: ticket.selectedAnalysisID.uuidString.lowercased(),
                    previousReview: ticket.reviewRevision, request: selection), context: context)
            case "legacy": context.insert(OfflineJobRecord(id: "synthetic-review", kind: .identificationReviewSync, subjectId: scan.id.lowercased()))
            case "owner": scan.analysisOwnerAccountID = UUID().uuidString.lowercased()
            default: context.delete(scan)
            }
        }
        #expect(throws: (any Error).self) {
            try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: fixture.container,
                isCurrent: { true }, rejectionUndo: eligibility)
        }
        #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<OfflineJobRecord>()).allSatisfy {
            !$0.id.hasPrefix(ObservationAnalysisReviewPersistence.prefix)
        })
    }

}
