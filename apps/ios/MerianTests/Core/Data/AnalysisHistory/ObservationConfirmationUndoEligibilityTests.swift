import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ConfirmationUndoEligibilityTests {
    struct Fixture {
        let container: ModelContainer
        let ticket: ObservationAnalysisReviewTicket
        let operation: UUID
    }
    func seed(named: Bool = false) async throws -> Fixture {
        let support = ObservationAnalysisReviewAdmissionTests(), source = support.source
        let (container, _) = try await support.seed()
        let operation = UUID()
        try source.update(container) { scan, _ in
            let state = try #require(scan.analysisRecords?.first?.state)
            var authority = try #require(JSONSerialization.jsonObject(with: state.reviewSnapshotData) as? [String: Any])
            authority["user_review_state"] = named ? "user_overridden" : "ai_confirmed"
            authority["user_confirmed_identification"] = !named
            authority["user_identification_override"] = named ? "Synthetic correction" : NSNull()
            // Nested counter intentionally differs from the outer target revision.
            authority["ai_identification_review"] = ["version": 1, "revision": 7, "state": "clear",
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
    func recovered(_ ticket: ObservationAnalysisReviewTicket, operation: UUID, named: Bool) throws -> ObservationConfirmationUndoEligibility {
        let lookup = ObservationConfirmationUndoEligibility.lookup(ticket)
        var row = try lookup.object()
        row["status"] = "available"; row["confirmation_operation_id"] = operation.uuidString.lowercased()
        row["confirmation_action"] = named ? "confirm_name" : "confirm_primary"
        let reply = try ObservationConfirmationUndoReply(data: JSONSerialization.data(withJSONObject: row), request: lookup)
        guard case let .available(value) = try ObservationConfirmationUndoEligibility.recovered(reply, ticket: ticket) else {
            throw ObservationHistoryError.unavailable
        }
        return value
    }
    @Test(arguments: [false, true])
    func secondDeviceStagesWithoutOriginalReceipt(named: Bool) async throws {
        let fixture = try await seed(named: named)
        let container = fixture.container, ticket = fixture.ticket, operation = fixture.operation
        let eligibility = try recovered(ticket, operation: operation, named: named)
        #expect(try ObservationConfirmationUndoEligibility.local(ticket, context: ModelContext(container)) == nil)
        #expect(eligibility.source == .recovered && ticket.reviewRevision == 2)
        let request = try ticket.request(.undoConfirmation(confirmationOperationID: operation), operationID: UUID())
        let intent = try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: container,
            isCurrent: { true }, confirmationUndo: eligibility)
        #expect(intent.request == request)
        let scan = try ObservationHistorySyncService.enrolledScan(ticket.observationID.uuidString, context: ModelContext(container))
        #expect(scan.selectedAnalysisID == ticket.selectedAnalysisID.uuidString.lowercased())
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }
    @Test func noEligibilityOrSubstitutedAssociationCannotStage() async throws {
        let fixture = try await seed()
        let container = fixture.container, ticket = fixture.ticket, operation = fixture.operation
        let request = try ticket.request(.undoConfirmation(confirmationOperationID: operation), operationID: UUID())
        #expect(throws: (any Error).self) {
            try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: container, isCurrent: { true })
        }
        #expect(throws: (any Error).self) { try recovered(ticket, operation: UUID(), named: false) }
        #expect(throws: (any Error).self) { try recovered(ticket, operation: operation, named: true) }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }
    @Test(arguments: [false, true])
    func localReceiptMatchesOuterRevisionDespiteOlderParentAndDifferentNestedCounter(candidate: Bool) async throws {
        let fixture = try await seed(named: candidate), ticket = fixture.ticket
        let decision: ObservationAnalysisReviewRequest.Decision = candidate
            ? .confirmCandidate(try .init(analysisID: ticket.analysisID, ordinal: 1, scientificName: "Synthetic correction")) : .confirmPrimary
        let request = try ObservationAnalysisReviewRequest(observationID: ticket.observationID, analysisID: ticket.analysisID,
            operationID: fixture.operation, expectedObservationRevision: 1, expectedReviewRevision: 1, decision: decision)
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
        let eligibility = try #require(try ObservationConfirmationUndoEligibility.local(ticket, context: ModelContext(fixture.container)))
        #expect(eligibility.source == .local && ticket.observationRevision == 11 && ticket.reviewRevision == 2)
        try eligibility.validate(ticket: ticket, context: ModelContext(fixture.container))
    }

}
