import Testing

@testable import Merian

@Suite("Model tier badge presentation")
struct ModelTierBadgePresentationTests {
    @Test("Complimentary access reports its remaining scan count")
    func complimentaryAccessReportsRemainingCount() {
        #expect(resolve(remaining: 2)?.text == "2 Pro scans remain")
        #expect(resolve(remaining: 1)?.text == "1 Pro scan remains")
    }

    @Test("Exhausted complimentary access offers an upgrade")
    func exhaustedAccessOffersUpgrade() {
        #expect(
            resolve(
                remaining: 0,
                isExhausted: true
            )?.text == "Upgrade for advanced analysis"
        )
    }

    @Test("Free analysis offers an upgrade only in the eligible band")
    func freeAnalysisUsesConfidenceBand() {
        let bands = MerianConfig.confidenceBands(
            forInferenceTier: "free"
        )
        let eligibleScore = (bands.possible + bands.strong) / 2

        #expect(resolve(confidenceScore: eligibleScore)?.text != nil)
        #expect(resolve(confidenceScore: bands.strong) == nil)
        #expect(resolve(confidenceScore: bands.possible - 0.001) == nil)
    }

    @Test("Active Pro access suppresses the badge")
    func activeProAccessSuppressesBadge() {
        #expect(resolve(
            confidenceScore: 0,
            isSubscribed: true,
            isProActive: true
        ) == nil)
    }

    private func resolve(
        confidenceScore: Double? = nil,
        remaining: Int = 0,
        isExhausted: Bool = false,
        isSubscribed: Bool = false,
        isProActive: Bool = false
    ) -> ModelTierBadgePresentation? {
        ModelTierBadgePresentation.resolve(
            confidenceScore: confidenceScore,
            inferenceTier: "free",
            isSubscribed: isSubscribed,
            isProActive: isProActive,
            hasComplimentaryAccess: remaining > 0,
            complimentaryScansRemaining: remaining,
            isComplimentaryExhausted: isExhausted
        )
    }
}
