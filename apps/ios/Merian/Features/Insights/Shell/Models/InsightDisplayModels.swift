import Foundation

enum InsightShareRecommendation: Equatable {
    case publishToExplore
    case askCommunity
    case communityPending
    case communityResolvedNeedsPublish
}

struct InsightResultToolbarRevealKey: Equatable {
    let scanId: String?
    let presentationGeneration: UInt64
}
