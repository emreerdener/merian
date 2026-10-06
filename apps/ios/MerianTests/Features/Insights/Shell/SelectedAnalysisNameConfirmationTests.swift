import Foundation
import SwiftData
@testable import Merian
import Testing

@MainActor
struct SelectedAnalysisNameConfirmationTests {
    func fixture() throws -> SelectedAnalysisReviewHostTests.Fixture {
        let primary = try PrimaryIdentification.Snapshot(resolution: .genus, scientificName: "Synthetic", commonName: nil)
        let f = try SelectedAnalysisReviewHostTests.Fixture(ticket: ObservationAnalysisReviewTicketTests().ticket(primary: primary))
        try f.bind()
        return f
    }
    func form(_ f: SelectedAnalysisReviewHostTests.Fixture,
              current: @escaping () -> Bool = { true }) throws -> SelectedAnalysisNameConfirmation {
        let token = try #require(f.host.token)
        return try #require(f.host.prepareNameConfirmation(token: token, isCurrent: current))
    }

    @Test func debugGenusFixtureUsesValidPersistedAuthorityAndProductionReviewAdmission() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let fixture = try PublicationConsentUIFixture(container: context.container, namedReview: true)
        try fixture.seed(context: context); try context.save()
        let baseline = try #require(SelectedAnalysisReviewBaseline(scanID: PublicationConsentUIFixture.observation,
            ownerID: PublicationConsentUIFixture.owner.uuidString, analysisID: PublicationConsentUIFixture.selected, revision: 1))
        let access = SelectedAnalysisReviewAccess.prepared(cloud: fixture.cloud, session: fixture.session)
        let session = try access.open(baseline, context.container)
        defer { session.close() }
        #expect(session.ticket.canConfirmName && !session.ticket.canConfirmPrimary && session.ticket.primaryScientificName == "Danaus")
        let model = session.reviewModel(presentationIsCurrent: { true })
        model.submit(.confirmName("Danaus plexippus"))
        #expect(model.status?.phase == .pending && model.canRetrySave == false)
        let jobs = try ModelContext(context.container).fetch(FetchDescriptor<OfflineJobRecord>())
        #expect(jobs.count == 1 && jobs.first?.kind == .observationAnalysisReviewSync)
    }

    @Test func openingAndEditingDoNotCreateOperationAndFinalTapFreezesExactName() throws {
        let f = try fixture(), form = try form(f)
        #expect(!f.review.ticket.canConfirmPrimary && f.review.ticket.canConfirmName)
        #expect(!form.canSubmit && f.host.model?.request == nil && f.review.saved.isEmpty)
        form.scientificName = "Synthetic species"
        #expect(form.canSubmit && f.host.model?.request == nil)
        form.submit(); form.submit()
        let request = try #require(f.host.model?.request)
        #expect(request.decision == .confirmName("Synthetic species") && f.review.saved == [request] && f.review.wakes == 1)
        #expect(request.analysisID == f.review.ticket.analysisID)
        #expect(request.expectedObservationRevision == f.review.ticket.observationRevision)
        #expect(request.expectedReviewRevision == f.review.ticket.reviewRevision)
    }

    @Test(arguments: ["", " padded", "trailing ", String(repeating: "e\u{301}", count: 100)])
    func invalidNameNeverMintsOperation(_ name: String) throws {
        let f = try fixture(), form = try form(f)
        form.scientificName = name; form.submit()
        #expect(!form.canSubmit && f.host.model?.request == nil && f.review.saved.isEmpty)
    }

    @Test(arguments: ["root", "account", "presentation", "authority", "reopen", "pending", "read"])
    func scopeAndAuthorityChangesNeverRetarget(_ change: String) throws {
        let f = try fixture()
        var current = true
        let form = try form(f, current: { current })
        form.scientificName = "Synthetic species"
        switch change {
        case "root": current = false
        case "account": f.review.current = false
        case "presentation": f.presentation = false
        case "authority": f.fresh = false
        case "reopen": f.host.close(); try f.bind()
        case "pending": f.review.pending = .init(operationID: UUID(), analysisID: UUID(), phase: .pending)
        default: f.review.failRead = true
        }
        form.submit()
        #expect(f.review.saved.isEmpty && f.review.wakes == 0 && f.host.model?.request == nil)
    }

    @Test func uncertainSaveAndDismissalRetainHostRequestForExactRetry() throws {
        let f = try fixture(), form = try form(f), token = try #require(f.host.token)
        f.review.failSave = true; form.scientificName = "Synthetic species"; form.submit()
        let request = try #require(f.host.model?.request)
        form.close(); form.submit()
        #expect(form.scientificName.isEmpty && !form.canSubmit && f.host.model?.request == request)
        #expect(f.host.model?.canRetrySave == true && f.closes == 0)
        #expect(f.host.prepareNameConfirmation(token: token, isCurrent: { true }) == nil)
        f.review.failSave = false; f.host.retrySave(token: token)
        #expect(f.review.saved == [request, request] && f.review.wakes == 1)
    }

    @Test func closedUnsubmittedFormCannotActButHostRemainsAvailable() throws {
        let f = try fixture(), form = try form(f)
        form.scientificName = "Synthetic species"; form.close(); form.submit()
        #expect(f.review.saved.isEmpty && f.host.model?.canSubmit == true && f.closes == 0)
        let replacement = try self.form(f)
        #expect(replacement.id != form.id && replacement.review === form.review)
    }

    @Test func openingFailsClosedForMissingCapabilityPendingWorkAndReadFailure() throws {
        let noPrimary = try SelectedAnalysisReviewHostTests.Fixture(); try noPrimary.bind()
        #expect(noPrimary.host.prepareNameConfirmation(token: try #require(noPrimary.host.token), isCurrent: { true }) == nil)
        let f = try fixture(), token = try #require(f.host.token)
        f.review.pending = .init(operationID: UUID(), analysisID: UUID(), phase: .needsAttention)
        #expect(f.host.prepareNameConfirmation(token: token, isCurrent: { true }) == nil)
        f.review.pending = nil; f.review.failRead = true
        #expect(f.host.prepareNameConfirmation(token: token, isCurrent: { true }) == nil)
    }
}
