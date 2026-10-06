import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
struct SelectedAnalysisReviewHostTests {
    @MainActor final class Fixture {
        let review: IdentificationHistoryReviewModelTests.Fixture
        let container: ModelContainer
        let host = SelectedAnalysisReviewHost()
        var presentation = true, fresh = true, opens = 0, closes = 0
        init() throws {
            review = try .init()
            container = try InsightSheetTestSupport.createIsolatedContext().container
        }
        func key(_ generation: UInt64 = 1) throws -> SelectedAnalysisReviewHost.Key {
            let ticket = review.ticket
            return .init(baseline: try #require(.init(scanID: ticket.observationID.uuidString,
                ownerID: ticket.ownerID.uuidString, analysisID: ticket.analysisID.uuidString,
                revision: ticket.observationRevision)), generation: generation, container: ObjectIdentifier(container))
        }
        func bind(_ generation: UInt64 = 1) throws {
            host.bind(try key(generation), access: .init(open: { _, _ in
                self.opens += 1
                return .init(ticket: self.review.ticket, access: self.review.access,
                    isScopeCurrent: { self.review.current }, matchesDisplayedTicket: { self.fresh },
                    close: { self.closes += 1 })
            }), container: container, isCurrent: { self.presentation })
        }
        func finish(_ outcome: ObservationAnalysisReviewReceipt.Outcome) throws {
            let operation = try #require(host.model?.request?.operationID)
            review.pending = nil
            review.receipt = .init(operationID: operation, analysisID: review.ticket.analysisID, phase: .complete(outcome))
        }
    }

    @Test func rerenderAndMissingReceiptPreserveUncertainRequestForExactRetry() throws {
        let f = try Fixture(); try f.bind()
        let token = try #require(f.host.token)
        f.review.failSave = true
        f.host.submit(.reject, token: token)
        let request = try #require(f.host.model?.request)
        try f.bind()
        f.host.refresh { _ in Issue.record("An uncertain save cannot refresh the parent") }
        #expect(f.opens == 1 && f.host.model?.request == request)
        f.review.failSave = false
        f.host.retrySave(token: token)
        #expect(f.review.saved == [request, request] && f.review.wakes == 1)
    }

    @Test func oldAlertCannotActAfterSameBaselineReopens() throws {
        let f = try Fixture(); try f.bind()
        let token = try #require(f.host.token)
        f.host.close(); try f.bind()
        f.host.submit(.reject, token: token)
        #expect(f.review.saved.isEmpty && f.host.model?.canSubmit == true)
        #expect(f.closes == 1 && f.opens == 2)
    }

    @Test func newDecisionRequiresDisplayedAuthorityButReceiptRefreshDoesNot() throws {
        let f = try Fixture(); try f.bind()
        let token = try #require(f.host.token)
        f.fresh = false
        f.host.submit(.reject, token: token)
        #expect(f.review.saved.isEmpty && f.host.model?.request == nil)
        f.host.close(); f.fresh = true; try f.bind(2)
        f.host.submit(.reject, token: try #require(f.host.token))
        try f.finish(.applied(observationRevision: 11, reviewRevision: 1))
        f.fresh = false
        var refreshes = 0
        f.host.refresh { _ in refreshes += 1 }
        f.host.refresh { _ in refreshes += 1 }
        #expect(refreshes == 1 && f.host.model == nil && f.host.message != nil)
    }

    @Test func conflictCannotAutomaticallyReopenAtTheSameRevision() throws {
        let f = try Fixture(); try f.bind()
        f.host.submit(.reject, token: try #require(f.host.token))
        try f.finish(.revisionConflict)
        f.host.refresh { _ in Issue.record("Conflict must not project any child") }
        try f.bind()
        #expect(f.opens == 1 && f.host.model == nil && f.host.message?.contains("fresh preview") == true)
        f.review.receipt = nil
        try f.bind(2)
        #expect(f.opens == 2 && f.host.model != nil)
    }

    @Test(arguments: [true, false])
    func accountOrPresentationLossCannotApplyAReceipt(_ account: Bool) throws {
        let f = try Fixture(); try f.bind()
        f.host.submit(.reject, token: try #require(f.host.token))
        try f.finish(.applied(observationRevision: 11, reviewRevision: 1))
        if account { f.review.current = false } else { f.presentation = false }
        f.host.refresh { _ in Issue.record("Stale scope must not update presentation") }
        #expect(f.host.model == nil && f.closes == 1 && f.review.saved.count == 1)
    }

    @Test func receiptOnlyReopeningAndHeldWorkNeverDispatch() throws {
        let f = try Fixture()
        f.review.pending = .init(operationID: UUID(), analysisID: f.review.ticket.analysisID, phase: .needsAttention)
        f.review.receipt = f.review.pending
        try f.bind()
        let token = try #require(f.host.token)
        f.host.submit(.reject, token: token); f.host.retrySave(token: token)
        f.host.refresh { _ in Issue.record("Held review cannot apply") }
        #expect(f.review.saved.isEmpty && f.review.wakes == 0 && f.host.model?.status?.phase == .needsAttention)
    }
}
