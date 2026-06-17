import Foundation

enum CandidateReviewVisibilityPolicy {
    static let minimumCompetitiveCandidateConfidence = 0.80
    static let competitiveCandidateMargin = 0.15

    /// Collection-level review eligibility shares the candidate review thresholds,
    /// but below-Strong scans still qualify even when no alternatives were stored.
    static func shouldSurfaceForReviewCollection(
        primaryConfidence: Double?,
        inferenceTier: String?,
        candidates: [IdentificationCandidate],
        isBiological: Bool = true,
        isUnknownSubject: Bool = false,
        isHumanSubject: Bool = false,
        userIdentificationOverride: String? = nil,
        userConfirmedIdentification: Bool = false,
        isFlagged: Bool = false,
        alternativesExhausted: Bool = false
    ) -> Bool {
        guard isBiological,
              !isUnknownSubject,
              !isHumanSubject,
              userIdentificationOverride == nil,
              !userConfirmedIdentification,
              !isFlagged,
              !alternativesExhausted,
              let primaryConfidence
        else {
            return false
        }

        let bands = MerianConfig.confidenceBands(forInferenceTier: inferenceTier)
        guard primaryConfidence < bands.diagnosticTrigger else { return false }
        if primaryConfidence < bands.strong { return true }

        return hasCompetitiveCandidate(
            primaryConfidence: primaryConfidence,
            candidates: candidates
        )
    }

    static func visibleCandidates(for speciesData: SpeciesData?) -> [IdentificationCandidate] {
        guard let speciesData else { return [] }

        return visibleCandidates(
            primaryConfidence: speciesData.confidenceScore,
            inferenceTier: speciesData.inferenceTier,
            candidates: speciesData.candidates ?? [],
            isBiological: speciesData.isBiological,
            isUnknownSubject: speciesData.scientificName == "Taxonomy Unavailable",
            isHumanSubject: speciesData.isHumanSubject,
            userIdentificationOverride: speciesData.userIdentificationOverride,
            userConfirmedIdentification: speciesData.userConfirmedIdentification,
            isFlagged: speciesData.isFlagged,
            alternativesExhausted: speciesData.alternativesExhausted
        )
    }

    static func visibleCandidates(
        primaryConfidence: Double?,
        inferenceTier: String?,
        candidates: [IdentificationCandidate],
        isBiological: Bool = true,
        isUnknownSubject: Bool = false,
        isHumanSubject: Bool = false,
        userIdentificationOverride: String? = nil,
        userConfirmedIdentification: Bool = false,
        isFlagged: Bool = false,
        alternativesExhausted: Bool = false
    ) -> [IdentificationCandidate] {
        guard shouldShowCandidates(
            primaryConfidence: primaryConfidence,
            inferenceTier: inferenceTier,
            candidates: candidates,
            isBiological: isBiological,
            isUnknownSubject: isUnknownSubject,
            isHumanSubject: isHumanSubject,
            userIdentificationOverride: userIdentificationOverride,
            userConfirmedIdentification: userConfirmedIdentification,
            isFlagged: isFlagged,
            alternativesExhausted: alternativesExhausted
        ) else {
            return []
        }

        return candidates
    }

    static func shouldShowCandidates(
        primaryConfidence: Double?,
        inferenceTier: String?,
        candidates: [IdentificationCandidate],
        isBiological: Bool = true,
        isUnknownSubject: Bool = false,
        isHumanSubject: Bool = false,
        userIdentificationOverride: String? = nil,
        userConfirmedIdentification: Bool = false,
        isFlagged: Bool = false,
        alternativesExhausted: Bool = false
    ) -> Bool {
        guard isBiological,
              !isUnknownSubject,
              !isHumanSubject,
              !candidates.isEmpty,
              userIdentificationOverride == nil,
              !userConfirmedIdentification,
              !isFlagged,
              !alternativesExhausted,
              let primaryConfidence
        else {
            return false
        }

        let bands = MerianConfig.confidenceBands(forInferenceTier: inferenceTier)
        guard primaryConfidence < bands.diagnosticTrigger else { return false }
        if primaryConfidence < bands.strong { return true }

        return hasCompetitiveCandidate(
            primaryConfidence: primaryConfidence,
            candidates: candidates
        )
    }

    private static func hasCompetitiveCandidate(
        primaryConfidence: Double,
        candidates: [IdentificationCandidate]
    ) -> Bool {
        guard let topCandidateConfidence = candidates.map(\.confidenceScore).max() else {
            return false
        }

        return topCandidateConfidence >= minimumCompetitiveCandidateConfidence &&
            abs(primaryConfidence - topCandidateConfidence) <= competitiveCandidateMargin
    }
}
