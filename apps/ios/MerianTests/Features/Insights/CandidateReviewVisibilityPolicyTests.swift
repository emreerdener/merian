import Testing
@testable import Merian

struct CandidateReviewVisibilityPolicyTests {
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
        #expect(!isVisible(primaryConfidence: 0.84, tier: "pro", candidateConfidence: 0.82, isFlagged: true))
        #expect(!isVisible(primaryConfidence: 0.84, tier: "pro", candidateConfidence: 0.82, alternativesExhausted: true))
        #expect(!isVisible(primaryConfidence: 0.84, tier: "pro", candidateConfidence: 0.82, userIdentificationOverride: "Danaus plexippus"))
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
