import Foundation

struct ProfileStatsRefreshKey: Equatable {
    let refreshToken: UUID
    let isAuthenticated: Bool
    let accountId: String?
}

enum ProfileTabPresentation: Identifiable, Equatable {
    case paywall
    case insight(ScanInsightRoute)
    case fieldTripAuthor(ExploreAuthorProfileRoute)

    var id: String {
        switch self {
        case .paywall:
            "paywall"
        case .insight(let route):
            "insight-\(route.id)"
        case .fieldTripAuthor(let route):
            "field-trip-author-\(route.id)"
        }
    }
}
