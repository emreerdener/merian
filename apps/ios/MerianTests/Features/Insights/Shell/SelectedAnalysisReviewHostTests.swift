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
        var presentation = true, fresh = true, opens = 0, closes = 0, reads = 0
        init(ticket: ObservationAnalysisReviewTicket? = nil) throws {
            review = try .init(ticket: ticket)
            container = try InsightSheetTestSupport.createIsolatedContext().container
        }
        func key(_ generation: UInt64 = 1) throws -> SelectedAnalysisReviewHost.Key {
            let ticket = review.ticket
            return .init(baseline: try #require(.init(scanID: ticket.observationID.uuidString,
                ownerID: ticket.ownerID.uuidString, analysisID: ticket.analysisID.uuidString,
                revision: ticket.observationRevision)), generation: generation, container: ObjectIdentifier(container))
        }
        var adapter: SelectedAnalysisReviewAccess {
            .init(open: { _, _ in
                self.opens += 1
                var access = self.review.access
                let pending = access.pending
                access.pending = { self.reads += 1; return try pending() }
                return .init(ticket: self.review.ticket, access: access,
                    isScopeCurrent: { self.review.current }, matchesDisplayedTicket: { self.fresh },
                    close: { self.closes += 1 })
            })
        }
        func bind(_ generation: UInt64 = 1) throws {
            host.bind(try key(generation), access: adapter, container: container, isCurrent: { self.presentation })
        }
        func finish(_ outcome: ObservationAnalysisReviewReceipt.Outcome) throws {
            let operation = try #require(host.model?.request?.operationID)
            review.pending = nil
            review.receipt = .init(operationID: operation, analysisID: review.ticket.analysisID, phase: .complete(outcome))
        }
    }

    @Test func cancelledPresentationCanBindAndRefreshRealPreparedSession() async throws {
        let support = SelectedAnalysisReviewTests()
        let (container, ticket) = try await support.fixture.seed()
        let key = SelectedAnalysisReviewHost.Key(baseline: try support.baseline(ticket), generation: 1,
            container: ObjectIdentifier(container))
        let control = SelectedAnalysisReviewHost(), host = SelectedAnalysisReviewHost()
        var wakes = 0
        let adapter = support.access(wake: { wakes += 1 })
        defer { control.close(); host.close() }
        let caller = Task { @MainActor in
            #expect(Task.isCancelled)
            control.bind(key, access: support.access(), container: container, isCurrent: { true })
            #expect(control.model?.canSubmit != true && control.message != nil)
            await host.requestBind(key, access: adapter, container: container, isCurrent: { true })?.value
            #expect(host.model?.canSubmit == true && host.message == nil)
            // The raw read must still reject cancelled callers. The owned
            // refresh recovers presentation without staging or rearming work.
            host.model?.refresh()
            #expect(host.model?.canSubmit == false && host.model?.message != nil)
            await host.requestRefresh { _ in Issue.record("No receipt was applied") }?.value
            #expect(host.model?.canSubmit == true && host.message == nil)
        }
        caller.cancel()
        await caller.value
        #expect(wakes == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test(arguments: ["close", "replace", "presentation", "account"])
    func queuedBindingCannotOutliveItsPresentation(_ change: String) async throws {
        let f = try Fixture()
        let first = f.host.requestBind(try f.key(), access: f.adapter, container: f.container, isCurrent: { f.presentation })
        var replacement: Task<Void, Never>?
        switch change {
        case "close": f.host.close()
        case "replace":
            replacement = f.host.requestBind(try f.key(2), access: f.adapter, container: f.container, isCurrent: { f.presentation })
        case "presentation": f.presentation = false
        default: f.review.current = false
        }
        await first?.value; await replacement?.value
        #expect(f.opens == ((change == "replace" || change == "account") ? 1 : 0))
        #expect(f.host.model?.canSubmit == (change == "replace" ? true : nil))
        #expect(f.review.wakes == (change == "replace" ? 1 : 0) && f.review.saved.isEmpty)
        f.host.close()
    }

    @Test(arguments: ["close", "replace", "invalidate", "account"])
    func queuedRefreshCannotReadOrApplyAStaleScope(_ change: String) async throws {
        let f = try Fixture(); try f.bind()
        let queued = f.host.requestRefresh { _ in Issue.record("Stale delivery must not reach parent") }
        switch change {
        case "close": f.host.close()
        case "replace": try f.bind(2)
        case "invalidate": f.host.invalidateScope()
        default: f.review.current = false
        }
        let reads = f.reads
        await queued?.value
        #expect(f.reads == reads && f.review.saved.isEmpty)
        #expect(f.host.model?.canSubmit == (change == "replace" ? true : nil))
        f.host.close()
    }

    @Test func repeatedDeliveryCoalescesAndAppliesReceiptOnlyOnce() async throws {
        let f = try Fixture(); try f.bind()
        var applied = 0
        let reads = f.reads
        let first = f.host.requestRefresh { _ in applied += 1 }
        let duplicate = f.host.requestRefresh { _ in applied += 1 }
        await first?.value; await duplicate?.value
        #expect(f.reads == reads + 1 && applied == 0 && f.review.wakes == 1)
        f.host.submit(.reject, token: try #require(f.host.token))
        try f.finish(.applied(observationRevision: 11, reviewRevision: 1))
        let receipt = f.host.requestRefresh { _ in applied += 1 }
        let repeated = f.host.requestRefresh { _ in applied += 1 }
        await receipt?.value; await repeated?.value
        #expect(applied == 1 && f.host.model == nil && f.review.saved.count == 1)
        #expect(f.review.wakes == 2)
    }

    @Test func rerenderAndMissingReceiptPreserveUncertainRequestForExactRetry() throws {
        let f = try Fixture(); try f.bind()
        #expect(f.review.wakes == 1)
        let token = try #require(f.host.token)
        f.review.failSave = true
        f.host.submit(.reject, token: token)
        #expect(f.review.wakes == 2)
        let request = try #require(f.host.model?.request)
        try f.bind()
        #expect(f.host.requestBind(try f.key(), access: f.adapter, container: f.container, isCurrent: { f.presentation }) == nil)
        #expect(f.host.model?.request == request && f.host.token == token)
        f.host.refresh { _ in Issue.record("An uncertain save cannot refresh the parent") }
        #expect(f.opens == 1 && f.host.model?.request == request && f.review.wakes == 2)
        f.review.failSave = false
        f.host.retrySave(token: token)
        #expect(f.review.saved == [request, request] && f.review.wakes == 3)
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

    @Test func heldReopeningDiscoversWithoutRestagingOrRearming() throws {
        let f = try Fixture()
        f.review.pending = .init(operationID: UUID(), analysisID: f.review.ticket.analysisID, phase: .needsAttention)
        f.review.receipt = f.review.pending
        try f.bind()
        #expect(f.review.wakes == 1)
        let token = try #require(f.host.token)
        f.host.submit(.reject, token: token); f.host.retrySave(token: token)
        f.host.refresh { _ in Issue.record("Held review cannot apply") }
        #expect(f.review.saved.isEmpty && f.review.wakes == 1 && f.host.model?.status?.phase == .needsAttention)
    }
    @Test func selectedHostRecoversRejectionWithoutLocalReceiptAndStagesExactUndo() async throws {
        let support = RejectionUndoEligibilityTests(), fixture = try await support.seed()
        let ticket = fixture.ticket, container = fixture.container
        let owner = ObservationRejectionUndoOwner()
        let resolved = AsyncStream<Void>.makeStream()
        defer { resolved.continuation.finish(); owner.cancelAll() }
        var reads = 0, wakes = 0
        let cloud = ObservationHistorySyncTests().client(fetch: { _ in Data() })
        let service = ObservationRejectionUndoService(cloud: cloud, fetch: { lookup, _, validate in
            try validate(); reads += 1
            var row = try lookup.object()
            row["status"] = "available"; row["rejection_operation_id"] = fixture.operation.uuidString.lowercased()
            return try .init(data: JSONSerialization.data(withJSONObject: row), request: lookup)
        })
        let testAccess = IdentificationHistoryReviewAccess(stage: { _, _ in Issue.record("Recovered Undo must use explicit admission") },
            status: { _, operation in try ObservationAnalysisReviewStatus.read(operationID: operation, ownerID: ticket.ownerID,
                observationID: ticket.observationID, analysisID: ticket.analysisID, container: container, isCurrent: { true }) },
            pending: { try ObservationAnalysisReviewStatus.pending(ownerID: ticket.ownerID, observationID: ticket.observationID,
                container: container, isCurrent: { true }) },
            undo: { try ObservationAnalysisReviewStatus.undoOperation($0, container: container, isCurrent: { true }) },
            wake: { wakes += 1 }, generation: { 0 }, prepareRejectionUndo: { displayed in
                defer { resolved.continuation.yield() }
                return try await owner.prepare(ticket: displayed, session: .init(userID: ticket.ownerID, isAnonymous: false),
                    generation: 1, container: container, service: service, isCurrent: { true })
            }, stageRejectionUndo: { request, displayed, eligibility in
                _ = try ObservationAnalysisReviewAdmission.stage(request, ticket: displayed, container: container,
                    isCurrent: { true }, rejectionUndo: eligibility)
            })
        let host = SelectedAnalysisReviewHost()
        let key = SelectedAnalysisReviewHost.Key(baseline: try #require(.init(scanID: ticket.observationID.uuidString,
            ownerID: ticket.ownerID.uuidString, analysisID: ticket.analysisID.uuidString, revision: ticket.observationRevision)),
            generation: 1, container: ObjectIdentifier(container))
        host.bind(key, access: .init(open: { _, _ in
            .init(ticket: ticket, access: testAccess, isScopeCurrent: { true }, matchesDisplayedTicket: { true }, close: {})
        }), container: container, isCurrent: { true })
        for await _ in resolved.stream { break }
        #expect(reads == 1 && host.model?.undoOperation == fixture.operation)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        host.submit(.undo(rejectionOperationID: fixture.operation), token: try #require(host.token))
        let request = try #require(host.model?.request)
        #expect(request.decision == .undo(rejectionOperationID: fixture.operation))
        #expect(request.expectedObservationRevision == ticket.observationRevision && wakes == 2)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
        host.close()
    }

}
