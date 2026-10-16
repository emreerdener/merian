import Foundation
@testable import Merian
import Testing
import UIKit

@MainActor
struct AnalysisCandidateReviewModelTests {
    func fixture() throws -> SelectedAnalysisReviewHostTests.Fixture {
        let primary = try PrimaryIdentification.Snapshot(resolution: .species, scientificName: "Synthetic primary", commonName: nil)
        let candidates: [[String: Any]] = [0.4, 0.2].map {
            ["scientific_name": "Synthetic same", "taxon_rank": "species", "confidence_score": $0]
        }
        let ticket = try ObservationAnalysisReviewTicketTests().ticket(primary: primary, resultPatch: ["candidates": candidates], version: 2)
        let fixture = try SelectedAnalysisReviewHostTests.Fixture(ticket: ticket)
        try fixture.bind()
        return fixture
    }
    func model(_ fixture: SelectedAnalysisReviewHostTests.Fixture, current: @escaping () -> Bool = { true }) throws -> AnalysisCandidateReviewModel {
        let token = try #require(fixture.host.token)
        return try #require(fixture.host.prepareCandidateConfirmation(token: token, isCurrent: current))
    }

    @Test(arguments: ["complete", "close", "scope"])
    func exactPhotoLoadWithholdsLatePrivateEvidence(_ outcome: String) async throws {
        let photo = ObservationHistoryPhotoReference(mediaID: UUID(), contentType: "image/jpeg", byteCount: 7, sha256: String(repeating: "a", count: 64))
        let ticket = try ObservationAnalysisReviewTicketTests().ticket(version: 2, photos: [photo])
        let fixture = try SelectedAnalysisReviewHostTests.Fixture(ticket: ticket)
        try fixture.bind()
        let review = try #require(fixture.host.model)
        var current = true, calls = 0
        var continuation: CheckedContinuation<UIImage, Never>?
        let image = UIImage()
        let model = AnalysisCandidateReviewModel(review: review, isCurrent: { current }, loadPhoto: { analysis, media in
            #expect(analysis == ticket.analysisID && media == photo.mediaID)
            calls += 1
            return await withCheckedContinuation { continuation = $0 }
        }, confirm: { _ in Issue.record("Photo loading cannot review a candidate") })
        let first = Task { await model.loadEvidence() }
        while continuation == nil { await Task.yield() }
        let joined = Task { await model.loadEvidence() }
        if outcome == "close" { model.close() }
        if outcome == "scope" { current = false }
        continuation?.resume(returning: image)
        await first.value; await joined.value
        #expect(calls == 1)
        if outcome == "scope" { current = true } // Prove the late image was never installed.
        #expect((model.evidencePhoto === image) == (outcome == "complete"))
        #expect(model.photoMessage == nil && review.request == nil)
    }

    @Test func missingImmutablePhotoNeverCallsLoader() async throws {
        let fixture = try fixture(), review = try #require(fixture.host.model)
        let model = AnalysisCandidateReviewModel(review: review, isCurrent: { true }, loadPhoto: { _, _ in
            Issue.record("Missing immutable evidence must not load another result's photo")
            return UIImage()
        }, confirm: { _ in })
        await model.loadEvidence()
        #expect(model.evidencePhoto == nil && model.photoMessage != nil)
    }

    @Test func duplicateNamesKeepTheirOriginalReferenceThroughNavigationAndSubmission() throws {
        let fixture = try fixture(), model = try model(fixture)
        let original = model.remaining
        #expect(original.count == 2 && original[0].display.scientificName == original[1].display.scientificName)
        model.skip()
        #expect(model.remaining.map(\.reference.ordinal) == [1, 0])
        model.dismissChoice(original[0].reference)
        #expect(model.remaining.map(\.reference.ordinal) == [1])
        model.submit(original[0].reference)
        #expect(fixture.review.saved.isEmpty)
        model.restart()
        #expect(model.remaining == original && fixture.host.model?.request == nil)
        model.submit(original[1].reference); model.submit(original[0].reference)
        let request = try #require(fixture.host.model?.request)
        #expect(request.decision == .confirmCandidate(original[1].reference))
        #expect(fixture.review.saved == [request] && !model.canReview)
    }

    @Test(arguments: ["scope", "account", "presentation", "authority", "reopen", "pending", "read", "close"])
    func delayedSelectionNeverRebasesOrFallsBack(_ change: String) throws {
        let fixture = try fixture()
        var current = true
        let model = try model(fixture, current: { current }), reference = try #require(model.remaining.first?.reference)
        switch change {
        case "scope": current = false
        case "account": fixture.review.current = false
        case "presentation": fixture.presentation = false
        case "authority": fixture.fresh = false
        case "reopen": fixture.host.close(); try fixture.bind()
        case "pending": fixture.review.pending = .init(operationID: UUID(), analysisID: UUID(), phase: .pending)
        case "read": fixture.review.failRead = true
        default: model.close()
        }
        model.submit(reference)
        #expect(fixture.review.saved.isEmpty && fixture.host.model?.request == nil)
    }

    @Test func uncertainSaveSurvivesDeckDismissalAndRetriesExactCandidate() throws {
        let fixture = try fixture(), model = try model(fixture)
        let reference = model.remaining[1].reference, token = try #require(fixture.host.token)
        fixture.review.failSave = true
        model.submit(reference)
        let request = try #require(fixture.host.model?.request)
        model.close(); model.submit(reference)
        #expect(fixture.host.model?.request == request && fixture.host.model?.canRetrySave == true && fixture.closes == 0)
        #expect(fixture.host.prepareCandidateConfirmation(token: token, isCurrent: { true }) == nil)
        fixture.review.failSave = false; fixture.host.retrySave(token: token)
        #expect(fixture.review.saved == [request, request] && request.decision == .confirmCandidate(reference))
    }

    @Test func forgedReferenceAndOpeningWithoutEligibleEvidenceDoNotCreateWork() throws {
        let fixture = try fixture(), model = try model(fixture)
        let forged = try ObservationAnalysisCandidateReference(analysisID: fixture.review.ticket.analysisID, ordinal: 1, scientificName: "Synthetic forged")
        model.submit(forged)
        #expect(fixture.review.saved.isEmpty)
        let unsupported = try SelectedAnalysisReviewHostTests.Fixture(); try unsupported.bind()
        #expect(unsupported.host.prepareCandidateConfirmation(token: try #require(unsupported.host.token), isCurrent: { true }) == nil)
        fixture.review.failRead = true
        #expect(fixture.host.prepareCandidateConfirmation(token: try #require(fixture.host.token), isCurrent: { true }) == nil)
    }
}
