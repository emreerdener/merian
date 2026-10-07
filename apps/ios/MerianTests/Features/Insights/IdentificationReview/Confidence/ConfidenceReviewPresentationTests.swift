import Foundation
import Testing

@testable import Merian

struct ConfidenceReviewPresentationTests {
    @Test func badgePresentationPreservesEveryVisibleState() throws {
        let bands = try #require(InferenceConfidencePolicy.bands(forInferenceTier: "pro"))

        #expect(badge(score: nil).isVisible == false)
        #expect(badge(score: bands.strong).label == "Strong match")
        #expect(badge(score: bands.possible).label == "Possible match")
        #expect(badge(score: bands.possible - 0.01).label == "Weak match")

        let confirmed = ConfidenceBadgePresentation.resolve(
            confidenceScore: nil,
            inferenceTier: "pro",
            hasUserOverride: true,
            isUserConfirmed: false,
            analyzingPhrase: nil
        )
        #expect(confirmed.label == "Confirmed")
        #expect(confirmed.style == .confirmed)
        #expect(confirmed.isVisible)

        let analyzing = ConfidenceBadgePresentation.resolve(
            confidenceScore: nil,
            inferenceTier: nil,
            hasUserOverride: false,
            isUserConfirmed: false,
            analyzingPhrase: "Checking taxonomy"
        )
        #expect(analyzing.label == "Checking taxonomy...")
        #expect(analyzing.style == .analyzing)
        #expect(analyzing.isVisible)
    }

    @Test func analyzingEllipsisIsNotDuplicated() {
        let analyzing = ConfidenceBadgePresentation.resolve(
            confidenceScore: nil,
            inferenceTier: nil,
            hasUserOverride: false,
            isUserConfirmed: false,
            analyzingPhrase: "Checking taxonomy..."
        )

        #expect(analyzing.label == "Checking taxonomy...")
    }

    @Test func explanationTitlesPreserveFallbackOrder() {
        #expect(ConfidenceExplanationPresentation.headerTitle(
            confidenceScore: 0.876,
            hasUserOverride: false,
            isUserConfirmed: false
        ) == "88% confident")
        #expect(ConfidenceExplanationPresentation.headerTitle(
            confidenceScore: nil,
            hasUserOverride: false,
            isUserConfirmed: false
        ) == "Analysis")
        #expect(ConfidenceExplanationPresentation.headerTitle(
            confidenceScore: 0.5,
            hasUserOverride: false,
            isUserConfirmed: true
        ) == "Confirmed")

        #expect(ConfidenceExplanationPresentation.confirmButtonTitle(
            commonName: " monarch ",
            aiScientificName: "Danaus plexippus"
        ) == "Confirm Monarch")
        #expect(ConfidenceExplanationPresentation.confirmButtonTitle(
            commonName: "Unknown subject",
            aiScientificName: "Danaus plexippus"
        ) == "Confirm Danaus plexippus")
        #expect(ConfidenceExplanationPresentation.confirmButtonTitle(
            commonName: " ",
            aiScientificName: "unknown subject"
        ) == "Confirm initial match")
    }

    @Test func overrideDisplayUsesValidCommonNameOnly() {
        #expect(ConfidenceExplanationPresentation.overrideDisplayName(
            overrideScientificName: "Danaus plexippus",
            commonName: "monarch"
        ) == "Monarch (Danaus plexippus)")
        #expect(ConfidenceExplanationPresentation.overrideDisplayName(
            overrideScientificName: "Danaus plexippus",
            commonName: "Unknown subject"
        ) == "Danaus plexippus")
    }

    @Test func proposalAndRejectedPresentationRemainDistinctAfterRestoration() throws {
        for state in [AIIdentificationReview.State.aiRejected, .awaitingAcceptance] {
            let original = LocalAIIdentificationReview(authority: .init(
                revision: 2, state: state, originScanID: "00000000-0000-4000-8000-000000000001", originIdentification: nil
            ))
            let restored = LocalAIIdentificationReview.restoring(try original.storedData())
            let presentation = ConfidenceBadgePresentation.resolve(
                confidenceScore: 0.99, inferenceTier: "pro", hasUserOverride: false,
                isUserConfirmed: false, analyzingPhrase: nil, review: restored
            )
            #expect(restored == original)
            #expect(presentation.label == (state == .aiRejected ? "Incorrect" : "Review new result"))
            #expect(presentation.style == (state == .aiRejected ? .incorrect : .awaitingReview))
            #expect(IdentificationReviewNotice.explanation(restored).contains("You marked") == (state == .aiRejected))
        }
    }

    @Test func damagedReviewExplainsUnavailabilityInsteadOfClaimingRejection() {
        let review = LocalAIIdentificationReview.restoring(Data("invalid".utf8))
        let presentation = ConfidenceBadgePresentation.resolve(
            confidenceScore: 0.99, inferenceTier: "pro", hasUserOverride: false,
            isUserConfirmed: false, analyzingPhrase: nil, review: review
        )
        #expect(presentation.label == "Review needs attention")
        #expect(IdentificationReviewNotice.unavailableReason(review)?.contains("needs attention") == true)
        #expect(!IdentificationReviewNotice.explanation(review).contains("You marked"))
    }

    @Test func forwardedControlsRejectDelayedSubjectAndPreserveExactUndo() {
        var generation = 1, confirms = 0, undoes = 0
        let proposal = ConfidenceReviewControls(confirmProposal: { confirms += 1 }).checking { generation == 1 }
        #expect(proposal.undo == nil)
        proposal.confirmProposal?(); #expect(confirms == 1)
        generation = 2
        proposal.confirmProposal?(); #expect(confirms == 1)
        let rejected = ConfidenceReviewControls(undo: { undoes += 1 }).checking { generation == 2 }
        #expect(rejected.confirmProposal == nil)
        rejected.undo?(); #expect(undoes == 1 && confirms == 1)
        generation = 3
        rejected.undo?(); #expect(undoes == 1)
    }

    @MainActor @Test func protectedConfirmationPresentationDoesNotDependOnLegacyBadgeInputs() throws {
        let fixture = ObservationAnalysisReviewTicketTests()
        let primary = try PrimaryIdentification.Snapshot(resolution: .species, scientificName: "Synthetic original", commonName: nil)
        let confirmed = try fixture.ticket(primary: primary, authorityPatch: ["user_review_state": "ai_confirmed"])
        let corrected = try fixture.ticket(primary: primary, authorityPatch: ["user_review_state": "user_overridden",
            "user_identification_override": "Synthetic correction"])
        #expect(ConfidenceReviewControls.ConfirmationState.resolve(confirmed) == .primary)
        #expect(ConfidenceReviewControls.ConfirmationState.resolve(corrected) == .named("Synthetic correction"))
        var current = true, calls = 0
        let controls = ConfidenceReviewControls(confirmationState: .named("Synthetic correction"), undoConfirmation: { calls += 1 },
            undoConfirmationRequiresPrompt: true).checking { current }
        controls.undoConfirmation?(); current = false; controls.undoConfirmation?()
        #expect(calls == 1 && controls.confirmationState == .named("Synthetic correction") && controls.undoConfirmationRequiresPrompt)
        let unavailable = ConfidenceReviewControls(confirmationState: .primary, confirmationUndoReason: "Original receipt unavailable")
        #expect(unavailable.undoConfirmation == nil && unavailable.confirmationState == .primary && unavailable.confirmationUndoReason != nil)
    }

    @MainActor @Test func communityConfirmationNeverAppearsAsOwnersReversibleConfirmation() throws {
        let fixture = ObservationAnalysisReviewTicketTests()
        let ai: [String: Any] = ["version": 1, "revision": 1, "state": "clear", "origin_scan_id": NSNull(),
            "origin_identification": NSNull(), "operation_id": NSNull(), "operation_digest": NSNull(),
            "community": ["request_id": UUID().uuidString.lowercased(), "rank": "genus", "scientific_name": "Synthetic",
                          "common_name": NSNull(), "species_id": NSNull()]]
        let ticket = try fixture.ticket(authorityPatch: ["user_review_state": "ai_confirmed", "ai_identification_review": ai])
        #expect(ticket.confirmationAction == nil && ConfidenceReviewControls.ConfirmationState.resolve(ticket) == nil)
    }

    private func badge(score: Double?) -> ConfidenceBadgePresentation {
        ConfidenceBadgePresentation.resolve(
            confidenceScore: score,
            inferenceTier: "pro",
            hasUserOverride: false,
            isUserConfirmed: false,
            analyzingPhrase: nil
        )
    }
}
