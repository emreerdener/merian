import Foundation
@testable import Merian
import Testing

@MainActor
struct IdentificationHistoryReviewModelTests {
    @MainActor final class Fixture {
        let ticket: ObservationAnalysisReviewTicket
        var current = true, failSave = false, failRead = false
        var saved: [ObservationAnalysisReviewRequest] = []
        var wakes = 0
        var receipt: ObservationAnalysisReviewStatus?
        var pending: ObservationAnalysisReviewStatus?
        var undo: UUID?
        init(ticket: ObservationAnalysisReviewTicket? = nil) throws {
            self.ticket = try ticket ?? ObservationAnalysisReviewTicketTests().ticket()
        }
        var access: IdentificationHistoryReviewAccess {
            .init(stage: { request, ticket in
                #expect(ticket == self.ticket)
                self.saved.append(request)
                if self.failSave { throw ObservationHistoryError.unavailable }
                self.receipt = .init(operationID: request.operationID, analysisID: request.analysisID, phase: .pending)
                self.pending = self.receipt
            }, status: { ticket, operation in
                #expect(ticket == self.ticket)
                if self.failRead { throw ObservationHistoryError.unavailable }
                #expect(self.receipt == nil || self.receipt?.operationID == operation)
                return self.receipt
            }, pending: {
                if self.failRead { throw ObservationHistoryError.unavailable }
                return self.pending
            }, undo: { _ in self.undo }, wake: { self.wakes += 1 }, generation: { 0 })
        }
        func model() -> IdentificationHistoryReviewModel { .init(ticket: ticket, access: access, isCurrent: { self.current }) }
    }

    @Test func synchronousTapPersistsExactRequestBeforeWakeAndDisallowsAnotherDecision() throws {
        let fixture = try Fixture(), model = fixture.model()
        model.submit(.reject)
        let request = try #require(model.request)
        #expect(fixture.saved == [request] && fixture.wakes == 1)
        #expect(request.expectedObservationRevision == fixture.ticket.observationRevision)
        #expect(request.expectedReviewRevision == fixture.ticket.reviewRevision)
        model.submit(.reject); model.retrySave()
        #expect(fixture.saved.count == 1 && !model.canSubmit)
    }

    @Test func nilStatusAfterAmbiguousSaveRetainsExactRequest() throws {
        let fixture = try Fixture(), model = fixture.model()
        fixture.failSave = true
        model.submit(.reject)
        let request = try #require(model.request)
        #expect(model.canRetrySave && model.status == nil && model.hasUnresolvedRequest)
        model.refresh(); model.submit(.reject)
        #expect(model.request == request && fixture.saved == [request])
        fixture.failSave = false
        model.retrySave()
        #expect(fixture.saved == [request, request] && fixture.wakes == 1 && !model.canRetrySave)
    }

    @Test func readFailureAfterAmbiguousSaveCannotMintReplacement() throws {
        let fixture = try Fixture(), model = fixture.model()
        fixture.failSave = true; model.submit(.reject)
        let request = model.request
        fixture.failRead = true; model.refresh(); model.submit(.reject)
        #expect(model.request == request && fixture.saved.count == 1 && !model.canSubmit)
        fixture.current = false; model.retrySave()
        #expect(model.isClosed && model.request == nil && fixture.saved.count == 1)
    }

    @Test func reopenedPendingReviewObservesReceiptAndHeldWorkNeverRearms() throws {
        let fixture = try Fixture()
        let operation = UUID()
        fixture.pending = .init(operationID: operation, analysisID: fixture.ticket.analysisID, phase: .needsAttention)
        fixture.receipt = fixture.pending
        let model = fixture.model()
        #expect(model.status?.phase == .needsAttention && !model.canSubmit && !model.canRetrySave)
        model.submit(.reject); model.retrySave()
        #expect(fixture.saved.isEmpty && fixture.wakes == 0)
        fixture.pending = nil
        fixture.receipt = .init(operationID: operation, analysisID: fixture.ticket.analysisID, phase: .complete(.revisionConflict))
        model.refresh()
        #expect(model.terminalMessage?.contains("fresh preview") == true && !model.canSubmit)
    }

    @Test func anotherTargetAndStatusFailuresBlockNewReview() throws {
        let fixture = try Fixture()
        fixture.pending = .init(operationID: UUID(), analysisID: UUID(), phase: .pending)
        let model = fixture.model()
        model.submit(.reject)
        #expect(fixture.saved.isEmpty && !model.canSubmit)
        fixture.pending = nil; fixture.failRead = true; model.refresh(); model.submit(.reject)
        #expect(fixture.saved.isEmpty && model.message != nil)
    }

    @Test func undoRechecksReceiptAtActualTap() throws {
        let operation = UUID(), base = try ObservationAnalysisReviewTicketTests().ticket()
        let ai = AIIdentificationReview(revision: 1, state: .aiRejected, originScanID: base.observationID.uuidString.lowercased(),
            originIdentification: nil, operationID: operation.uuidString.lowercased())
        let ticket = try ObservationAnalysisReviewTicketTests().ticket(authorityPatch: ["ai_identification_review": JSONSerialization.jsonObject(with: ai.storedData())])
        let fixture = try Fixture(ticket: ticket); fixture.undo = operation
        let model = fixture.model()
        #expect(model.undoOperation == operation)
        fixture.undo = nil
        model.submit(.undo(rejectionOperationID: operation))
        #expect(fixture.saved.isEmpty && model.request == nil)
    }

    @Test func closedPreviewCannotAdmitOrRefresh() throws {
        let fixture = try Fixture(), model = fixture.model()
        model.close(); model.refresh(); model.submit(.reject)
        #expect(model.isClosed && model.status == nil && fixture.saved.isEmpty && fixture.wakes == 0)
    }

    @Test func primaryLabelRemainsImmutableDespiteManualAuthority() throws {
        let primary = try PrimaryIdentification.Snapshot(resolution: .species, scientificName: "Synthetic original", commonName: nil)
        let ticket = try ObservationAnalysisReviewTicketTests().ticket(primary: primary, authorityPatch: ["user_review_state": "user_overridden"])
        #expect(ticket.primaryScientificName == "Synthetic original" && ticket.canConfirmPrimary && ticket.canConfirmName)
    }
}
