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
