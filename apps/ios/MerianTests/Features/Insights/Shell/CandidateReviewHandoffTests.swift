import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
struct CandidateReviewHandoffTests {
    @Test func debugCandidateFixtureHasExactProductionTicket() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let fixture = try PublicationConsentUIFixture(container: context.container, namedReview: false,
            confirmationUndo: false, candidateConfirmation: true)
        try fixture.seed(context: context); try context.save()
        let baseline = try #require(SelectedAnalysisReviewBaseline(scanID: PublicationConsentUIFixture.observation,
            ownerID: PublicationConsentUIFixture.owner.uuidString, analysisID: PublicationConsentUIFixture.selected, revision: 1))
        let access = SelectedAnalysisReviewAccess.prepared(cloud: fixture.cloud, session: fixture.session)
        let session = try access.open(baseline, context.container)
        defer { session.close() }
        #expect(session.ticket.candidateChoices.map(\.reference.ordinal) == [0, 1])
        #expect(session.ticket.canConfirmName)
    }
    @Test func handoffIsOneUseAndCancellationCannotUndoPresentation() {
        var presentations = 0, discards = 0
        let ticket = CandidateReviewTicket(present: { presentations += 1; return true }, discard: { discards += 1 })
        ticket.resume(); ticket.resume(); ticket.cancel()
        #expect(presentations == 1 && discards == 0)
    }
    @Test(arguments: [true, false])
    func cancelledOrUnavailableHandoffClosesOnlyItsPreparedDeck(_ cancelFirst: Bool) {
        var presentations = 0, discards = 0
        let ticket = CandidateReviewTicket(present: { presentations += 1; return false }, discard: { discards += 1 })
        if cancelFirst { ticket.cancel() }
        ticket.resume(); ticket.cancel(); ticket.resume()
        #expect(presentations == (cancelFirst ? 0 : 1) && discards == 1)
    }
    @Test func checkedControlsCannotPrepareAfterChildScopeChanges() {
        var current = true, preparations = 0
        let controls = ConfidenceReviewControls(prepareCandidateReview: {
            preparations += 1
            return CandidateReviewTicket(present: { true }, discard: {})
        }).checking { current }
        let prepared = controls.prepareCandidateReview?()
        #expect(prepared != nil && preparations == 1)
        prepared?.cancel(); current = false
        #expect(controls.prepareCandidateReview?() == nil && preparations == 1)
    }
    @Test func delayedHandoffPreservesOriginalReferenceAndCannotReopenNewHost() throws {
        let fixture = try AnalysisCandidateReviewModelTests().fixture()
        let model = try AnalysisCandidateReviewModelTests().model(fixture)
        let reference = try #require(model.remaining.last?.reference)
        var presentations = 0
        let ticket = CandidateReviewTicket(present: {
            guard model.isScopeCurrent else { return false }
            presentations += 1; model.submit(reference); return true
        }, discard: { model.close() })
        #expect(fixture.review.saved.isEmpty)
        fixture.host.close(); try fixture.bind()
        ticket.resume()
        #expect(presentations == 0 && model.isClosed && fixture.review.saved.isEmpty)
    }
}
