import Testing
@testable import Merian

struct CandidateReviewVisibilityPolicyTests {
    @Test func incorrectGuidanceTracksDecisionAndAvailableActionsIndependentlyOfCandidates() {
        var species = SpeciesData(scanId: "guidance-fixture", commonName: "Fixture",
            scientificName: "Fixtureus species",
            insightData: InsightData(aiReasoning: "Synthetic observation", hazardType: "none"),
            confidenceScore: 0.99, isBiological: true)
        func visible(_ species: SpeciesData, reanalyze: Bool = true, community: Bool = true) -> Bool {
            CandidateReviewVisibilityPolicy.showsIncorrectGuidance(
                for: species, canReanalyze: reanalyze, canAskCommunity: community)
        }
        #expect(!visible(species))
        species.aiReview.optimisticState = .aiRejected
        #expect(visible(species))
        species.alternativesExhausted = true
        #expect(visible(species))
        #expect(visible(species, reanalyze: false))
        #expect(visible(species, community: false))
        #expect(!visible(species, reanalyze: false, community: false))
        species.aiReview.optimisticState = .clear
        #expect(!visible(species))
        species.aiReview.optimisticState = nil
        species.userConfirmedIdentification = true
        #expect(!visible(species))
    }

    @Test func testFlashWeakPrimaryShowsCandidates() {
        #expect(isVisible(primaryConfidence: 0.74, tier: "flash", candidateConfidence: 0.62))
    }

    @Test func testFlashPossiblePrimaryShowsCandidatesAtHigherConfidence() {
        #expect(isVisible(primaryConfidence: 0.90, tier: "flash", candidateConfidence: 0.70))
    }

    @Test func testFlashStrongPrimaryWithWeakCandidateHidesCandidates() {
        #expect(!isVisible(primaryConfidence: 0.96, tier: "flash", candidateConfidence: 0.70))
    }

    @Test func testFlashStrongPrimaryWithCompetitiveCandidateShowsCandidates() {
        #expect(isVisible(primaryConfidence: 0.96, tier: "flash", candidateConfidence: 0.82))
    }

    @Test func testProBelowStrongPrimaryShowsCandidates() {
        #expect(isVisible(primaryConfidence: 0.84, tier: "pro", candidateConfidence: 0.62))
    }

    @Test func testProStrongPrimaryWithWeakCandidateHidesCandidates() {
        #expect(!isVisible(primaryConfidence: 0.90, tier: "pro", candidateConfidence: 0.70))
    }

    @Test func testReviewStatesSuppressVisibleCandidates() {
        #expect(!isVisible(primaryConfidence: 0.84, tier: "pro", candidateConfidence: 0.82, userConfirmedIdentification: true))
        #expect(!isVisible(primaryConfidence: 0.84, tier: "pro", candidateConfidence: 0.82, alternativesExhausted: true))
        #expect(!isVisible(primaryConfidence: 0.84, tier: "pro", candidateConfidence: 0.82, userIdentificationOverride: "Danaus plexippus"))
    }

    @Test func testLegacyFlagDoesNotSuppressVisibleCandidates() {
        #expect(isVisible(primaryConfidence: 0.84, tier: "pro", candidateConfidence: 0.82, isFlagged: true))
    }

    @Test func testSubjectGuardsSuppressVisibleCandidates() {
        #expect(!isVisible(primaryConfidence: 0.70, tier: "flash", candidateConfidence: 0.62, isBiological: false))
        #expect(!isVisible(primaryConfidence: 0.70, tier: "flash", candidateConfidence: 0.62, isUnknownSubject: true))
        #expect(!isVisible(primaryConfidence: 0.70, tier: "flash", candidateConfidence: 0.62, isHumanSubject: true))
        #expect(!CandidateReviewVisibilityPolicy.shouldShowCandidates(
            primaryConfidence: 0.70,
            inferenceTier: "flash",
            candidates: []
        ))
    }

    @Test func testDiagnosticTriggerSuppressesCertainPrimaryConfidence() {
        #expect(!isVisible(primaryConfidence: 0.99, tier: "flash", candidateConfidence: 0.91))
    }

    private func isVisible(
        primaryConfidence: Double,
        tier: String?,
        candidateConfidence: Double,
        isBiological: Bool = true,
        isUnknownSubject: Bool = false,
        isHumanSubject: Bool = false,
        userIdentificationOverride: String? = nil,
        userConfirmedIdentification: Bool = false,
        isFlagged: Bool = false,
        alternativesExhausted: Bool = false
    ) -> Bool {
        CandidateReviewVisibilityPolicy.shouldShowCandidates(
            primaryConfidence: primaryConfidence,
            inferenceTier: tier,
            candidates: [
                IdentificationCandidate(
                    scientificName: "Limenitis archippus",
                    commonName: "Viceroy",
                    confidenceScore: candidateConfidence
                )
            ],
            isBiological: isBiological,
            isUnknownSubject: isUnknownSubject,
            isHumanSubject: isHumanSubject,
            userIdentificationOverride: userIdentificationOverride,
            userConfirmedIdentification: userConfirmedIdentification,
            isFlagged: isFlagged,
            alternativesExhausted: alternativesExhausted
        )
    }
}
