import Foundation

enum ExploreFeedFilter: String, CaseIterable, Hashable, Identifiable {
    case recent
    case following
    case trending
    case nearby
    case liked

    static let nearbyRadiusMiles = ExploreFeedNearbyRadius.default.rawValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return "Recent"
        case .following:
            return "Following"
        case .trending:
            return "Trending"
        case .nearby:
            return "Nearby"
        case .liked:
            return "Liked"
        }
    }

    var requiresLocation: Bool {
        self == .nearby
    }
}

enum ExploreFeedDateRange: String, CaseIterable, Hashable, Identifiable {
    case anyTime = "any_time"
    case today
    case pastWeek = "past_week"
    case pastMonth = "past_month"

    var id: Self { self }

    var title: String {
        switch self {
        case .anyTime: "Any time"
        case .today: "Today"
        case .pastWeek: "Past 7 days"
        case .pastMonth: "Past 30 days"
        }
    }

    var subtitle: String {
        switch self {
        case .anyTime: "Show discoveries regardless of when they were shared"
        case .today: "Shared since the start of today"
        case .pastWeek: "Shared during the past seven days"
        case .pastMonth: "Shared during the past thirty days"
        }
    }

    func sharedSince(referenceDate: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .anyTime:
            nil
        case .today:
            calendar.startOfDay(for: referenceDate)
        case .pastWeek:
            calendar.date(byAdding: .day, value: -7, to: referenceDate)
        case .pastMonth:
            calendar.date(byAdding: .day, value: -30, to: referenceDate)
        }
    }
}

enum ExploreFeedNearbyRadius: Int, CaseIterable, Hashable, Identifiable {
    case ten = 10
    case twentyFive = 25
    case fifty = 50
    case oneHundred = 100

    static let `default`: Self = .fifty

    var id: Int { rawValue }

    var title: String {
        "\(rawValue) miles"
    }
}

struct ExploreFeedAdvancedFilters: Equatable {
    var speciesCategories: Set<ExploreMapSpeciesCategory> = []
    var mediaTypes: Set<ExploreMediaKind> = []
    var dateRange: ExploreFeedDateRange = .anyTime
    var nearbyRadius: ExploreFeedNearbyRadius = .default

    func activeFilterCount(for feedFilter: ExploreFeedFilter) -> Int {
        speciesCategories.count
            + mediaTypes.count
            + (dateRange == .anyTime ? 0 : 1)
            + (feedFilter == .nearby && nearbyRadius != .default ? 1 : 0)
    }

    func hasActiveFilters(for feedFilter: ExploreFeedFilter) -> Bool {
        activeFilterCount(for: feedFilter) > 0
    }

    var hasStoredSelections: Bool {
        hasObservationFilters || nearbyRadius != .default
    }

    var hasObservationFilters: Bool {
        !speciesCategories.isEmpty || !mediaTypes.isEmpty || dateRange != .anyTime
    }
}

struct ExploreFeedCursor: Equatable {
    let beforeSharedAt: String?
    let beforePostId: String?
    let beforeRankingValue: Int?

    static let empty = ExploreFeedCursor(
        beforeSharedAt: nil,
        beforePostId: nil,
        beforeRankingValue: nil
    )

    var isEmpty: Bool {
        beforeSharedAt == nil && beforePostId == nil && beforeRankingValue == nil
    }
}

struct ExploreAuthorPostCursor: Decodable, Equatable {
    let beforeSharedAt: String?
    let beforePostId: String?

    static let empty = ExploreAuthorPostCursor(
        beforeSharedAt: nil,
        beforePostId: nil
    )

    var isEmpty: Bool {
        beforeSharedAt == nil && beforePostId == nil
    }
}

struct ExploreHashtagPostCursor: Equatable {
    let beforeSharedAt: String?
    let beforePostId: String?

    static let empty = ExploreHashtagPostCursor(
        beforeSharedAt: nil,
        beforePostId: nil
    )

    var isEmpty: Bool {
        beforeSharedAt == nil && beforePostId == nil
    }
}

struct ExploreSpeciesPostCursor: Decodable, Equatable {
    let imageQualityScore: Int?
    let sharedAt: String
    let postId: String
}
