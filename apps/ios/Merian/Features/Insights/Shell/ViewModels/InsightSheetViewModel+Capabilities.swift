import Foundation

extension InsightSheetViewModel {
    var isReviewLocked: Bool {
        guard queuedContext == nil else { return false }
        guard let speciesData = inferenceEngine?.speciesData else { return false }
        return speciesData.userConfirmedIdentification || speciesData.userIdentificationOverride != nil
    }

    var canReanalyze: Bool {
        guard queuedContext == nil else { return false }
        return presentedLocalRecordScanId != nil
    }

    var canReviewAlternatives: Bool {
        guard queuedContext == nil else { return false }
        return !reviewAlternativeCandidates.isEmpty
    }

    var canReviewIdentificationConcernCandidates: Bool {
        !identificationConcernCandidates.isEmpty
    }

    var reviewAlternativeCandidates: [IdentificationCandidate] {
        guard queuedContext == nil else { return [] }
        return CandidateReviewVisibilityPolicy.visibleCandidates(for: inferenceEngine?.speciesData)
    }

    var identificationConcernCandidates: [IdentificationCandidate] {
        guard queuedContext == nil,
              let speciesData = inferenceEngine?.speciesData,
              speciesData.isBiological,
              speciesData.hasResolvedBiologicalIdentification,
              !speciesData.isHumanSubject,
              speciesData.userIdentificationOverride == nil,
              !speciesData.userConfirmedIdentification else {
            return []
        }

        return speciesData.candidates ?? []
    }

    var candidateSwipeCandidates: [IdentificationCandidate] {
        switch state.candidateSwipePresentationSource {
        case .standard:
            return reviewAlternativeCandidates
        case .identificationConcern:
            return identificationConcernCandidates
        }
    }

    var canConfirm: Bool {
        guard queuedContext == nil,
              presentedLocalRecordScanId != nil else { return false }
        return !reviewAlternativeCandidates.isEmpty
    }

    var canShareToExplore: Bool {
        guard queuedContext == nil,
              let speciesData = inferenceEngine?.speciesData,
              presentedLocalRecordScanId != nil,
              let snapshot = toolbarRecordSnapshot,
              speciesData.hasResolvedBiologicalIdentification,
              !speciesData.isHumanSubject,
              !snapshot.isHumanSubject else {
            return false
        }

        return snapshot.isExploreShareEligible && speciesData.isBiological
    }

    var canRequestCommunityIdentification: Bool {
        canShareToExplore && hasUserMedia
    }

    var shareRecommendation: InsightShareRecommendation {
        let hasPresentedRecord = presentedLocalRecordScanId != nil
        if hasPresentedRecord,
           state.sharedExplorePostId != nil,
           state.isExploreFeedVisible {
            return .publishToExplore
        }

        switch hasPresentedRecord ? state.sharedCommunityIdentificationStatus : nil {
        case .needsId:
            return .communityPending
        case .resolved:
            return .communityResolvedNeedsPublish
        case .withdrawn, nil:
            break
        }

        guard canRequestCommunityIdentification else {
            return .publishToExplore
        }

        if hasUserReviewedIdentification || hasStrongAIIdentification {
            return .publishToExplore
        }

        return .askCommunity
    }

    var requiresExplorePublishConfirmation: Bool {
        switch shareRecommendation {
        case .askCommunity, .communityPending:
            return true
        case .publishToExplore, .communityResolvedNeedsPublish:
            return false
        }
    }

    private var hasUserReviewedIdentification: Bool {
        guard let speciesData = inferenceEngine?.speciesData else { return false }
        return speciesData.userConfirmedIdentification
            || speciesData.userIdentificationOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var hasStrongAIIdentification: Bool {
        guard let speciesData = inferenceEngine?.speciesData,
              speciesData.hasResolvedBiologicalIdentification,
              !speciesData.isHumanSubject else {
            return false
        }
        let bands = MerianConfig.confidenceBands(forInferenceTier: speciesData.inferenceTier)
        return speciesData.confidenceScore >= bands.strong
    }
}
