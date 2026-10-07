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
    case protectedChat(token: UUID, scanId: String, generation: UInt64)
    case reviewCandidates(formID: UUID, scanId: String, generation: UInt64)
    case reviewName(formID: UUID, scanId: String, generation: UInt64)
    case publicationConsent(scanId: String, generation: UInt64)
    case identificationHistory(scanId: String, generation: UInt64)
    case reanalysisStatus(scanId: String, generation: UInt64)
    case fieldTripAuthor(ExploreAuthorProfileRoute)
    case chat(scanId: String, generation: UInt64)
    case exploreOnboarding(scanId: String, generation: UInt64)
    case explore(scanId: String, generation: UInt64)

    var id: String {
        switch self {
        case .reviewCandidates(let formID, let scanId, let generation):
            "review-candidates-\(formID)-\(scanId)-\(generation)"
        case .reviewName(let formID, let scanId, let generation):
            "review-name-\(formID)-\(scanId)-\(generation)"
        case .publicationConsent(let scanId, let generation):
            "publication-consent-\(scanId)-\(generation)"
        case .reanalysisStatus(let scanId, let generation):
            "reanalysis-status-\(scanId)-\(generation)"
        case .identificationHistory(let scanId, let generation):
            "identification-history-\(scanId)-\(generation)"
        case .protectedChat(let token, let scanId, let generation):
            "protected-chat-\(token)-\(scanId)-\(generation)"
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
