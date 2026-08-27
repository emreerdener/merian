import Foundation

enum ScanSortOption: String, CaseIterable, Identifiable, Sendable {
    case newest = "Newest"
    case oldest = "Oldest"
    case aToZ = "A to Z"
    case zToA = "Z to A"

    var id: String { rawValue }
}

enum ScanDateFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case today = "Today"
    case thisWeek = "This week"
    case thisMonth = "This month"
    case thisYear = "This year"
    case custom = "Custom range"

    var id: String { rawValue }
}

enum ScanLocationFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case hasLocation = "Has location"
    case noLocation = "No location"

    var id: String { rawValue }
}

enum ScanMediaFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case image = "Image"
    case video = "Video"
    case audio = "Audio"

    var id: String { rawValue }
}

enum ScanEcologyFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case wild = "Wild"
    case captive = "Captive"
    case domesticated = "Domesticated"
    case pet = "Pet"

    var id: String { rawValue }
}

enum ScanQualityFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case highQuality = "High quality"
    case mediumQuality = "Medium quality"
    case lowQuality = "Low quality"
    case noScore = "No quality score"

    var id: String { rawValue }
}

enum ScanIdentificationFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case confirmed = "Confirmed ID"
    case corrected = "Corrected ID"
    case aiOnly = "AI-only ID"

    var id: String { rawValue }
}

enum ScanSeasonFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case spring = "Spring"
    case summer = "Summer"
    case fall = "Fall"
    case winter = "Winter"

    var id: String { rawValue }
}

enum ScanExplorePostFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case shared = "Shared to Explore"
    case unavailableMedia = "Unavailable media"

    var id: String { rawValue }
}

struct ScanLibraryFilterOptions: Equatable, Sendable {
    var customTags: [String] = []
    var hazardTypes: [String] = []
    var conservationStatuses: [String] = []
    var lifeStages: [String] = []
    var weatherConditions: [String] = []
    var taxonomyClasses: [String] = []
    var taxonomyOrders: [String] = []
    var taxonomyFamilies: [String] = []
    var taxonomyGenera: [String] = []
}

struct ScanLibraryFilters: Equatable, Sendable {
    var dateFilters: Set<ScanDateFilter> = []
    var customStartDate: Date?
    var customEndDate: Date?
    var locationFilters: Set<ScanLocationFilter> = []
    var mediaFilters: Set<ScanMediaFilter> = []
    var customTags: Set<String> = []
    var isInvasive = false
    var hazardTypes: Set<String> = []
    var conservationStatuses: Set<String> = []
    var lifeStages: Set<String> = []
    var ecologyFilters: Set<ScanEcologyFilter> = []
    var qualityFilters: Set<ScanQualityFilter> = []
    var identificationFilters: Set<ScanIdentificationFilter> = []
    var weatherConditions: Set<String> = []
    var seasons: Set<ScanSeasonFilter> = []
    var taxonomyClasses: Set<String> = []
    var taxonomyOrders: Set<String> = []
    var taxonomyFamilies: Set<String> = []
    var taxonomyGenera: Set<String> = []
    var explorePostFilters: Set<ScanExplorePostFilter> = []

    var hasAdvancedFilters: Bool {
        activeAdvancedFilterCount > 0
    }

    var activeAdvancedFilterCount: Int {
        dateFilters.count
            + locationFilters.count
            + mediaFilters.count
            + customTags.count
            + (isInvasive ? 1 : 0)
            + hazardTypes.count
            + conservationStatuses.count
            + lifeStages.count
            + ecologyFilters.count
            + qualityFilters.count
            + identificationFilters.count
            + weatherConditions.count
            + seasons.count
            + taxonomyClasses.count
            + taxonomyOrders.count
            + taxonomyFamilies.count
            + taxonomyGenera.count
            + explorePostFilters.count
    }

    mutating func clear() {
        self = ScanLibraryFilters()
    }
}
