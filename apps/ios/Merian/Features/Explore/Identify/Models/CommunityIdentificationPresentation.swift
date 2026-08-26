struct ExploreCommunityRequestRoute: Hashable {
    let requestId: String
}

struct ExploreCommunityRequestsFeedRoute: Hashable {
    let filter: CommunityIdentificationRequestFilter
}

struct ExploreCommunityActivityFeedRoute: Hashable {
    let filter: CommunityIdentificationRequestFilter
}

enum ExploreIdentifyMode: Hashable, CaseIterable {
    case requests
    case index

    var title: String {
        switch self {
        case .requests:
            "Requests"
        case .index:
            "Index"
        }
    }
}

enum CommunityIdentificationRequestFilter: Hashable, CaseIterable {
    case all
    case mine
    case plants
    case birds
    case insects
    case fungi
    case mammals
    case reptilesAmphibians

    var title: String {
        switch self {
        case .all:
            "All"
        case .mine:
            "Yours"
        case .plants:
            CommunityIdentificationRequestGroup.plants.title
        case .birds:
            CommunityIdentificationRequestGroup.birds.title
        case .insects:
            CommunityIdentificationRequestGroup.insects.title
        case .fungi:
            CommunityIdentificationRequestGroup.fungi.title
        case .mammals:
            CommunityIdentificationRequestGroup.mammals.title
        case .reptilesAmphibians:
            CommunityIdentificationRequestGroup.reptilesAmphibians.title
        }
    }

    var scope: CommunityIdentificationFeedScope {
        switch self {
        case .mine:
            .mine
        default:
            .all
        }
    }

    var group: CommunityIdentificationRequestGroup {
        switch self {
        case .all, .mine:
            .all
        case .plants:
            .plants
        case .birds:
            .birds
        case .insects:
            .insects
        case .fungi:
            .fungi
        case .mammals:
            .mammals
        case .reptilesAmphibians:
            .reptilesAmphibians
        }
    }

    var emptyRequestTitle: String {
        switch self {
        case .all:
            "No requests yet"
        case .mine:
            "No requests from you yet"
        case .plants:
            "No plant requests yet"
        case .birds:
            "No bird requests yet"
        case .insects:
            "No insect requests yet"
        case .fungi:
            "No fungus requests yet"
        case .mammals:
            "No mammal requests yet"
        case .reptilesAmphibians:
            "No herp requests yet"
        }
    }
}

enum CommunityIdentificationDashboardPolicy {
    static let requestPreviewLimit = 12
    static let activityPreviewLimit = 10
    static let fullPageSize = 30
}

enum CommunityIdentificationDashboardSection {
    case requests
    case activity
}

struct IdentifyDashboardLoadState: Equatable {
    private(set) var isLoadingRequests = true
    private(set) var isLoadingActivity = true
    private(set) var requestErrorMessage: String?
    private(set) var activityErrorMessage: String?

    mutating func begin(_ section: CommunityIdentificationDashboardSection) {
        switch section {
        case .requests:
            isLoadingRequests = true
            requestErrorMessage = nil
        case .activity:
            isLoadingActivity = true
            activityErrorMessage = nil
        }
    }

    mutating func beginBoth() {
        begin(.requests)
        begin(.activity)
    }

    mutating func succeed(_ section: CommunityIdentificationDashboardSection) {
        switch section {
        case .requests:
            isLoadingRequests = false
            requestErrorMessage = nil
        case .activity:
            isLoadingActivity = false
            activityErrorMessage = nil
        }
    }

    mutating func fail(
        _ section: CommunityIdentificationDashboardSection,
        message: String
    ) {
        switch section {
        case .requests:
            isLoadingRequests = false
            requestErrorMessage = message
        case .activity:
            isLoadingActivity = false
            activityErrorMessage = message
        }
    }
}

struct IdentifyRequestPageRequest: Equatable {
    let limit: Int
    let filter: CommunityIdentificationRequestFilter
    let latitude: Double?
    let longitude: Double?
    let cursor: CommunityIdentificationCursor
}

struct IdentifyActivityPageRequest: Equatable {
    let limit: Int
    let filter: CommunityIdentificationRequestFilter
    let cursor: CommunityIdentificationActivityCursor
}

struct CommunityIdentificationUpdateRequest {
    let requestId: String
    let note: String?
    let locationSharing: ExplorePostLocationSharing
}

struct CommunityIdentificationSubmissionRequest {
    let requestId: String
    let taxonId: String
    let disagreementMode: CommunityIdentificationDisagreementMode
    let reasoning: String?
    let isGenusBestPossible: Bool
}

struct CommunityIdentificationReportRequest {
    let scanId: String
    let userId: String
}
