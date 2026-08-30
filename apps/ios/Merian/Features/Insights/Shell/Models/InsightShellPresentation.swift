import Foundation

struct InsightFieldTripContributionLoadKey: Equatable {
    let scanId: String?
    let isAuthenticated: Bool
    let accountId: String?
}

enum InsightChatDismissalAction: Equatable {
    case reviewAlternatives(scanId: String, generation: UInt64)
    case reanalyze(scanId: String, generation: UInt64)
    case showPaywall(scanId: String, generation: UInt64)

    var context: (scanId: String, generation: UInt64) {
        switch self {
        case .reviewAlternatives(let scanId, let generation),
             .reanalyze(let scanId, let generation),
             .showPaywall(let scanId, let generation):
            (scanId, generation)
        }
    }
}

enum InsightShellPresentation: Identifiable, Equatable {
    case paywall
    case fieldTripAuthor(ExploreAuthorProfileRoute)
    case chat(scanId: String, generation: UInt64)
    case exploreOnboarding(scanId: String, generation: UInt64)
    case explore(scanId: String, generation: UInt64)

    var id: String {
        switch self {
        case .paywall:
            "paywall"
        case .fieldTripAuthor(let route):
            "field-trip-author-\(route.id)"
        case .chat(let scanId, let generation):
            "chat-\(scanId)-\(generation)"
        case .exploreOnboarding(let scanId, let generation):
            "explore-onboarding-\(scanId)-\(generation)"
        case .explore(let scanId, let generation):
            "explore-\(scanId)-\(generation)"
        }
    }
}
