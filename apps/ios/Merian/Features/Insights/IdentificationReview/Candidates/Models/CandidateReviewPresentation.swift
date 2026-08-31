enum CandidateSwipeDismissalAction: Sendable, Equatable {
    case applyOverride(scientificName: String)
    case confirmOriginal
    case askCommunity
    case refineScan
}

struct CandidateSwipeDismissalRequest: Sendable, Equatable {
    let action: CandidateSwipeDismissalAction
    let scanId: String
    let presentationGeneration: UInt64

    var subject: IdentificationReviewSubject {
        IdentificationReviewSubject(
            scanId: scanId,
            presentationGeneration: presentationGeneration
        )
    }
}

enum CandidateCardPresentation: String, Identifiable {
    case originalImage
    case candidateImages
    case distinguishingFeature

    var id: String { rawValue }
}

enum CandidateSwipeDirection: Sendable {
    case left
    case right
}
