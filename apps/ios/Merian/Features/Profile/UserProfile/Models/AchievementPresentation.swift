enum AchievementDetailNavigationPolicy {
    static func showsFieldTripsLink(
        for award: AwardPayload,
        fieldTripsEnabled: Bool
    ) -> Bool {
        fieldTripsEnabled && award.type == .firstFieldTrip && !award.isCompleted
    }
}

enum AchievementDetailPresentation: Identifiable, Equatable {
    case insight(ScanInsightRoute)
    case fieldTripAuthor(ExploreAuthorProfileRoute)

    var id: String {
        switch self {
        case .insight(let route):
            "insight-\(route.id)"
        case .fieldTripAuthor(let route):
            "field-trip-author-\(route.id)"
        }
    }

    var isInsight: Bool {
        if case .insight = self { return true }
        return false
    }
}

struct AchievementFieldTripsRoute: Hashable {}
