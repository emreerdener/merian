import Foundation

struct IdentificationReviewSubject: Sendable, Equatable {
    let scanId: String
    let presentationGeneration: UInt64

    func matches(
        scanId candidateScanId: String?,
        presentationGeneration candidateGeneration: UInt64
    ) -> Bool {
        presentationGeneration == candidateGeneration &&
            candidateScanId?.caseInsensitiveCompare(scanId) == .orderedSame
    }

    func matches(_ other: IdentificationReviewSubject?) -> Bool {
        guard let other else { return false }
        return matches(
            scanId: other.scanId,
            presentationGeneration: other.presentationGeneration
        )
    }
}

struct IdentificationReviewRefinementSnapshot: Sendable, Equatable {
    let scanId: String
    let initialDescription: String?
}
