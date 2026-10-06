import Foundation
@testable import Merian
import Testing

@MainActor
struct IdentificationHistoryReviewLifecycleTests {
    @MainActor final class Fixture {
        let base = IdentificationHistoryViewModelTests.Fixture()
        let review: IdentificationHistoryReviewModelTests.Fixture
        var revision: Int
        init() throws { review = try .init(); revision = review.ticket.observationRevision }
        var dependencies: IdentificationHistoryDependencies {
            var result = base.dependencies
            let ticket = review.ticket
            let context = { ObservationHistoryListingService.Context(owner: ticket.ownerID, selected: ticket.selectedAnalysisID,
                revision: self.revision, pendingOperation: nil, undoOperation: nil) }
            result.context = context
            result.page = { _ in .init(rows: [self.base.row(ticket.analysisID)], nextBeforeOrdinal: nil, context: context()) }
            result.preview = { _ in .init(row: self.base.row(ticket.analysisID), reasoning: nil, alternatives: [], evidenceDescription: nil,
                photoIDs: [], canRestore: true, isCached: false, reviewTicket: ticket) }
            result.review = review.access
            result.pendingReview = review.access.pending
            return result
        }
        func open() async -> IdentificationHistoryViewModel {
            let model = IdentificationHistoryViewModel(dependencies: dependencies)
            await model.perform(.newest); await model.perform(.preview(review.ticket.analysisID))
            return model
        }
    }
    @Test(arguments: ["back", "close", "page", "revision", "account"])
    func teardownInvalidatesRetainedNestedReview(action: String) async throws {
        let fixture = try Fixture(), model = await fixture.open()
        let nested = try #require(model.review)
        switch action {
        case "back": model.back()
        case "close": model.close()
        case "page": await model.perform(.newest)
        case "revision": fixture.revision += 1; model.validate()
        default: fixture.base.current = false; model.validate()
        }
        nested.submit(.reject); nested.refresh()
        #expect(nested.isClosed && model.review == nil && fixture.review.saved.isEmpty)
    }
    @Test func suspendedPageClosesReviewBeforeItsReply() async throws {
        let fixture = try Fixture()
        var dependencies = fixture.dependencies
        let page = dependencies.page
        var suspend = false
        var resume: CheckedContinuation<Void, Never>?
        dependencies.page = { before in
            if suspend { await withCheckedContinuation { resume = $0 } }
            return try await page(before)
        }
        let model = IdentificationHistoryViewModel(dependencies: dependencies)
        await model.perform(.newest); await model.perform(.preview(fixture.review.ticket.analysisID))
        let nested = try #require(model.review)
        suspend = true
        let work = Task { await model.perform(.newest) }
        while resume == nil { await Task.yield() }
        #expect(nested.isClosed && model.review == nil)
        nested.submit(.reject)
        #expect(fixture.review.saved.isEmpty)
        resume?.resume(); await work.value
    }

    @Test func appliedReceiptNeverSelectsItsTarget() async throws {
        let fixture = try Fixture(), model = await fixture.open()
        let selected = model.selected
        let nested = try #require(model.review)
        nested.submit(.reject)
        let request = try #require(nested.request)
        fixture.review.pending = nil
        fixture.review.receipt = .init(operationID: request.operationID, analysisID: request.analysisID,
            phase: .complete(.applied(observationRevision: request.expectedObservationRevision + 1, reviewRevision: request.expectedReviewRevision + 1)))
        model.refreshReview()
        #expect(model.detail == nil && model.selected == selected && fixture.base.prepares == 0)
    }

    @Test func negativeReceiptInvalidatesEvenWithUnchangedRevision() async throws {
        let fixture = try Fixture(), model = await fixture.open()
        let nested = try #require(model.review)
        nested.submit(.reject)
        let request = try #require(nested.request)
        fixture.review.pending = nil
        fixture.review.receipt = .init(operationID: request.operationID, analysisID: request.analysisID, phase: .complete(.revisionConflict))
        model.refreshReview()
        #expect(model.detail == nil && model.rows.isEmpty && model.review == nil && nested.isClosed)
        #expect(model.message?.contains("fresh preview") == true)
        #expect(fixture.revision == fixture.review.ticket.observationRevision)
    }
    @Test func freshPendingAndUnavailableReadsFenceSelectionAndReanalysis() async throws {
        let fixture = try Fixture(), model = await fixture.open()
        fixture.review.pending = .init(operationID: UUID(), analysisID: UUID(), phase: .pending)
        for command in [IdentificationHistoryViewModel.Command.restore, .undo, .reanalyze] {
            await model.perform(command)
            #expect(model.message?.contains("unresolved") == true)
        }
        fixture.review.pending = nil; fixture.review.failRead = true
        await model.perform(.restore)
        #expect(model.message?.contains("unavailable") == true && fixture.base.prepares == 0 && fixture.base.sends == 0)
    }
    @Test func uncertainSaveBlocksSelectionEvenWhenStatusIsNil() async throws {
        let fixture = try Fixture(), model = await fixture.open()
        fixture.review.failSave = true; model.review?.submit(.reject)
        await model.perform(.restore)
        #expect(model.message?.contains("unresolved") == true && fixture.base.prepares == 0)
        #expect(model.review?.request != nil)
    }
}
