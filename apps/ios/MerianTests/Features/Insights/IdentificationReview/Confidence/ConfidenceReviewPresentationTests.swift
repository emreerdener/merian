import Testing

@testable import Merian

struct ConfidenceReviewPresentationTests {
    @Test func badgePresentationPreservesEveryVisibleState() {
        let bands = MerianConfig.confidenceBands(forInferenceTier: "pro")

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
