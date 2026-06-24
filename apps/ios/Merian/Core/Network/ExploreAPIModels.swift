import CoreLocation
import Foundation
import UIKit

struct ExploreFeedResponse: Decodable {
    let data: [ExplorePost]
}

struct ExplorePostResponse: Decodable {
    let data: ExplorePost
}

struct ExploreAuthorProfileResponse: Decodable {
    let data: ExploreAuthorProfile
}

struct ExploreAuthorPostsResponse: Decodable {
    let data: [ExplorePost]
}

struct ExploreHashtagPostsResponse: Decodable {
    let data: [ExplorePost]
}

struct ExploreFollowState: Decodable, Equatable {
    let success: Bool
    let authorUserId: String
    let followerCount: Int
    let followingCount: Int
    let viewerIsFollowing: Bool
}

struct ExplorePost: Decodable, Identifiable, Equatable {
    let postId: String
    let scanId: String
    let heroImageUrl: String
    let sharedAt: String
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    let authorIsPro: Bool?
    let hashtags: [String]?
    let speciesCommonName: String
    let speciesScientificName: String
    let petIdentification: PetIdentification?
    let publicLocationLabel: String?
    let locationSharing: ExplorePostLocationSharing?
    let timeOfDay: String?
    let currentMonth: Int?
    let weatherCondition: String?
    let weatherTemperatureF: Double?
    var likeCount: Int
    var commentCount: Int
    var viewerHasLiked: Bool
    let isOwnedByViewer: Bool
    let rankingValue: Int?

    var id: String { postId }

    var publicDisplayLocationLabel: String? {
        ExploreLocationPrivacy.displayLabel(from: publicLocationLabel)
    }

    var sharedAtDate: Date? {
        DateUtilities.iso8601FractionalFormatter.date(from: sharedAt)
            ?? DateUtilities.iso8601Formatter.date(from: sharedAt)
    }
}

enum ExploreLocationPrivacy {
    private static let stateCodeToName: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
        "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
        "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii",
        "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
        "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine",
        "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
        "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska",
        "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
        "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
        "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island",
        "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas",
        "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
        "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming"
    ]

    private static let stateNameToCode = Dictionary(
        uniqueKeysWithValues: stateCodeToName.map { ($0.value.lowercased(), $0.key) }
    )

    private static let countryNames: Set<String> = [
        "united states", "united states of america", "usa", "us", "canada"
    ]

    static func displayLabel(from rawLocation: String?) -> String? {
        guard let rawLocation else { return nil }
        let cleaned = rawLocation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        guard !cleaned.isEmpty, !containsCoordinatePair(cleaned) else { return nil }

        var parts = cleaned
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }

        parts.removeAll(where: isCountry)

        guard !parts.isEmpty else { return nil }

        if let stateIndex = parts.lastIndex(where: { normalizedState(from: $0) != nil }),
           let state = normalizedState(from: parts[stateIndex]) {
            if let city = parts[..<stateIndex].reversed().first(where: isSafeCityPart) {
                return "\(city), \(state.code)"
            }

            return state.name
        }

        guard let lastPart = parts.last, !isPrivateLocationPart(lastPart) else { return nil }

        if parts.count >= 2 {
            let region = lastPart
            if let city = parts.dropLast().reversed().first(where: isSafeCityPart) {
                return "\(city), \(region)"
            }

            return nil
        }

        return isSafeCityPart(lastPart) ? lastPart : nil
    }

    private static func containsCoordinatePair(_ value: String) -> Bool {
        let commaSeparated = value
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        if commaSeparated.count == 2,
           let latitude = Double(commaSeparated[0]),
           let longitude = Double(commaSeparated[1]),
           abs(latitude) <= 90,
           abs(longitude) <= 180 {
            return true
        }

        let pattern = #"[-+]?\d{1,3}\.\d{3,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: range)
        let numbers = matches.compactMap { match -> Double? in
            guard let numberRange = Range(match.range, in: value) else { return nil }
            return Double(value[numberRange])
        }

        guard numbers.count >= 2 else { return false }

        for index in numbers.indices.dropLast() {
            let latitude = numbers[index]
            let longitude = numbers[index + 1]
            if abs(latitude) <= 90, abs(longitude) <= 180 {
                return true
            }
        }

        return false
    }

    private static func isPrivateLocationPart(_ part: String) -> Bool {
        let lowercased = part
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !lowercased.isEmpty else { return true }
        if isCountry(lowercased) || containsCoordinatePair(lowercased) { return true }

        let privatePatterns = [
            #"^\d+"#,
            #"(street|avenue|road|boulevard|drive|lane|court|terrace|highway|route|suite|unit|apartment)"#,
            #"\b(st|ave|rd|blvd|dr|ln|ct|pl)\.?$"#,
            #"(gps|latitude|longitude|coordinate)"#,
            #"\b(park|trail|preserve|garden|campus|building|museum|hotel|restaurant|cafe|creek|beach|woods|forest|campground|bay|harbor|harbour|marina|island|lake|pond|river|canal|inlet|lagoon|wetland|swamp|sound|cove|estuary)\.?$"#
        ]

        return privatePatterns.contains { pattern in
            lowercased.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func isSafeCityPart(_ part: String) -> Bool {
        guard !isPrivateLocationPart(part) else { return false }

        let lowercased = part
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let administrativePatterns = [
            #"\b(county|parish|borough|district|municipality|prefecture)\b"#,
            #"\b(province|region)\b$"#
        ]

        return administrativePatterns.contains { pattern in
            lowercased.range(of: pattern, options: .regularExpression) != nil
        } == false
    }

    private static func isCountry(_ value: String) -> Bool {
        countryNames.contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func normalizedState(from value: String) -> (code: String, name: String)? {
        let trimmed = removingTrailingCountry(from: value)
        let uppercased = trimmed.uppercased()
        if let zipRange = trimmed.range(of: #"\s+\d{5}(?:-\d{4})?$"#, options: .regularExpression) {
            let stateCandidate = String(trimmed[..<zipRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stateCodeCandidate = stateCandidate.uppercased()
            if let stateName = stateCodeToName[stateCodeCandidate] {
                return (code: stateCodeCandidate, name: stateName)
            }
            if let stateCode = stateNameToCode[stateCandidate.lowercased()],
               let stateName = stateCodeToName[stateCode] {
                return (code: stateCode, name: stateName)
            }
        }

        if let stateName = stateCodeToName[uppercased] {
            return (code: uppercased, name: stateName)
        }

        if let stateCode = stateNameToCode[trimmed.lowercased()],
           let stateName = stateCodeToName[stateCode] {
            return (code: stateCode, name: stateName)
        }

        return nil
    }

    private static func removingTrailingCountry(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        for country in countryNames.sorted(by: { $0.count > $1.count }) {
            if lowercased == country {
                return ""
            }

            let suffix = " \(country)"
            if lowercased.hasSuffix(suffix) {
                return String(trimmed.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmed
    }
}

enum ExploreFeedFilter: String, CaseIterable, Hashable, Identifiable {
    case recent
    case following
    case trending
    case nearby

    static let nearbyRadiusMiles = 50

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
        }
    }

    var requiresLocation: Bool {
        self == .nearby
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

struct ExploreAuthorPostCursor: Equatable {
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

struct CommunityIdentificationFeedResponse: Decodable {
    let data: [CommunityIdentificationFeedItem]
}

enum CommunityIdentificationFeedScope: String, CaseIterable, Hashable {
    case all
    case mine

    var title: String {
        switch self {
        case .all:
            "All"
        case .mine:
            "Yours"
        }
    }
}

enum CommunityIdentificationRequestGroup: String, CaseIterable, Codable, Hashable {
    case all
    case plants
    case birds
    case insects
    case fungi
    case mammals
    case reptilesAmphibians = "reptiles_amphibians"

    var title: String {
        switch self {
        case .all:
            "All"
        case .plants:
            "Plants"
        case .birds:
            "Birds"
        case .insects:
            "Insects"
        case .fungi:
            "Fungi"
        case .mammals:
            "Mammals"
        case .reptilesAmphibians:
            "Herps"
        }
    }
}

struct CommunityIdentificationDetailResponse: Decodable {
    let data: CommunityIdentificationDetail
}

struct CommunityTaxonSearchResponse: Decodable {
    let data: [CommunityTaxonSearchResult]
}

struct CommunityIdentificationRequestResponse: Decodable {
    let success: Bool
    let data: CommunityIdentificationRequest
}

struct CommunityIdentificationMutationResponse: Decodable {
    let success: Bool
    let data: CommunityIdentificationMutation
}

struct CommunityIdentificationCursor: Equatable {
    let beforeRequestedAt: String?
    let beforeRequestId: String?

    static let empty = CommunityIdentificationCursor(
        beforeRequestedAt: nil,
        beforeRequestId: nil
    )

    var isEmpty: Bool {
        beforeRequestedAt == nil && beforeRequestId == nil
    }
}

enum CommunityIdentificationRequestStatus: String, Decodable, Equatable {
    case needsId = "needs_id"
    case resolved
    case withdrawn
}

enum CommunityIdentificationDisagreementMode: String, Codable, Equatable {
    case implicitSupport = "implicit_support"
    case explicitDisagreement = "explicit_disagreement"
    case maverick
}

enum CommunityTaxonPathRelationship: Equatable {
    case exact
    case descendant
    case ancestor
    case conflict
}

struct CommunityIdentificationFeedItem: Decodable, Identifiable, Equatable {
    let requestId: String
    let postId: String
    let scanId: String
    let heroImageUrl: String
    let requestedAt: String
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    let authorIsPro: Bool?
    let taxonomyVersionId: String?
    let projectionState: String?
    let consensusProcessingState: String?
    let currentTaxonId: String?
    let currentCommonName: String?
    let currentScientificName: String?
    let currentRank: String?
    let currentPath: String?
    let initialTaxonId: String?
    let initialCommonName: String?
    let initialScientificName: String?
    let initialRank: String?
    let initialPath: String?
    let requestGroup: CommunityIdentificationRequestGroup?
    let consensusScore: Double?
    let identificationCount: Int
    let viewerHasIdentified: Bool
    let publicLocationLabel: String?
    let locationSharing: ExplorePostLocationSharing?

    var id: String { requestId }

    var displayName: String {
        CommunityTaxonDisplay.name(commonName: currentCommonName, scientificName: currentScientificName)
    }

    var displayRank: String {
        CommunityTaxonDisplay.rankTitle(currentRank)
    }

    var publicDisplayLocationLabel: String? {
        ExploreLocationPrivacy.displayLabel(from: publicLocationLabel)
    }
}

struct CommunityIdentificationDetail: Decodable, Identifiable, Equatable {
    let requestId: String
    let postId: String
    let scanId: String
    let heroImageUrl: String
    let requestedAt: String
    let status: CommunityIdentificationRequestStatus
    let note: String?
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    let authorIsPro: Bool?
    let taxonomyVersionId: String?
    let projectionState: String?
    let consensusProcessingState: String?
    let currentTaxonId: String?
    let currentCommonName: String?
    let currentScientificName: String?
    let currentRank: String?
    let currentPath: String?
    let initialTaxonId: String?
    let initialCommonName: String?
    let initialScientificName: String?
    let initialRank: String?
    let initialPath: String?
    let resolvedTaxonId: String?
    let consensusScore: Double?
    let identificationCount: Int
    let viewerIdentificationId: String?
    let publicLocationLabel: String?
    let locationSharing: ExplorePostLocationSharing?
    let inferenceTier: String?
    let suggestedTaxa: [CommunityTaxonSearchResult]?
    let identifications: [CommunityIdentification]

    var id: String { requestId }

    var displayName: String {
        CommunityTaxonDisplay.name(commonName: currentCommonName, scientificName: currentScientificName)
    }

    var displayRank: String {
        CommunityTaxonDisplay.rankTitle(currentRank)
    }

    var publicDisplayLocationLabel: String? {
        ExploreLocationPrivacy.displayLabel(from: publicLocationLabel)
    }

    var isConsensusUpdating: Bool {
        consensusProcessingState == "queued" || consensusProcessingState == "processing"
    }

    var activeIdentificationCount: Int {
        identifications.filter { $0.withdrawnAt == nil }.count
    }
}

struct CommunityIdentification: Decodable, Identifiable, Equatable {
    let id: String
    let userId: String
    let authorName: String
    let authorAvatarUrl: String?
    let taxonId: String
    let taxonomyVersionId: String?
    let commonName: String?
    let scientificName: String
    let rank: String
    let disagreementMode: CommunityIdentificationDisagreementMode
    let roleLabel: String?
    let isGenusBestPossible: Bool
    let reasoning: String?
    let createdAt: String
    let withdrawnAt: String?
    let isViewer: Bool

    var displayName: String {
        CommunityTaxonDisplay.name(commonName: commonName, scientificName: scientificName)
    }

    var displayRank: String {
        CommunityTaxonDisplay.rankTitle(rank)
    }
}

struct CommunityTaxonSearchResult: Decodable, Identifiable, Equatable {
    let taxonId: String
    let taxonomyVersionId: String?
    let commonName: String?
    let scientificName: String
    let rank: String
    let path: String
    let speciesId: String?
    let gbifTaxonKey: Int?
    let source: String?
    let isInDictionary: Bool?
    let acceptedGbifTaxonKey: Int?
    let taxonomicStatus: String?
    let suggestionSource: CommunityTaxonSuggestionSource?
    let confidenceScore: Double?
    let distinguishingFeature: String?

    init(
        taxonId: String,
        taxonomyVersionId: String?,
        commonName: String?,
        scientificName: String,
        rank: String,
        path: String,
        speciesId: String?,
        gbifTaxonKey: Int? = nil,
        source: String? = nil,
        isInDictionary: Bool? = nil,
        acceptedGbifTaxonKey: Int? = nil,
        taxonomicStatus: String? = nil,
        suggestionSource: CommunityTaxonSuggestionSource? = nil,
        confidenceScore: Double? = nil,
        distinguishingFeature: String? = nil
    ) {
        self.taxonId = taxonId
        self.taxonomyVersionId = taxonomyVersionId
        self.commonName = commonName
        self.scientificName = scientificName
        self.rank = rank
        self.path = path
        self.speciesId = speciesId
        self.gbifTaxonKey = gbifTaxonKey
        self.source = source
        self.isInDictionary = isInDictionary
        self.acceptedGbifTaxonKey = acceptedGbifTaxonKey
        self.taxonomicStatus = taxonomicStatus
        self.suggestionSource = suggestionSource
        self.confidenceScore = confidenceScore
        self.distinguishingFeature = distinguishingFeature
    }

    var id: String { taxonId }

    var displayName: String {
        CommunityTaxonDisplay.name(commonName: commonName, scientificName: scientificName)
    }

    var displayRank: String {
        CommunityTaxonDisplay.rankTitle(rank)
    }

    func relationship(to currentPath: String?) -> CommunityTaxonPathRelationship {
        guard let currentPath, !currentPath.isEmpty else { return .conflict }
        if path == currentPath { return .exact }
        if path.hasPrefix(currentPath + ".") { return .descendant }
        if currentPath.hasPrefix(path + ".") { return .ancestor }
        return .conflict
    }
}

enum CommunityTaxonSuggestionSource: String, Decodable, Equatable {
    case aiInitial = "ai_initial"
    case aiCandidate = "ai_candidate"

    var displayLabel: String {
        switch self {
        case .aiInitial:
            "AI suggestion"
        case .aiCandidate:
            "Alternative from scan analysis"
        }
    }
}

struct CommunityIdentificationRequest: Decodable, Equatable {
    let id: String
    let postId: String
    let scanId: String
    let requestedBy: String
    let requestedAt: String
    let status: CommunityIdentificationRequestStatus
    let note: String?
    let initialTaxonNodeId: String?
    let taxonomyVersionId: String?
    let currentCommunityTaxonNodeId: String?
    let resolvedTaxonNodeId: String?
    let consensusScore: Double?
    let consensusIdentificationCount: Int
    let consensusRank: String?
    let consensusProcessingState: String?
}

struct CommunityIdentificationMutation: Decodable, Equatable {
    let id: String
    let requestId: String
    let postId: String
    let userId: String
    let taxonNodeId: String
    let disagreementMode: CommunityIdentificationDisagreementMode
    let isGenusBestPossible: Bool
    let reasoning: String?
    let createdAt: String
    let withdrawnAt: String?
    let restoredAt: String?
}

struct CommunityRequestUpdateResponse: Decodable, Equatable {
    let success: Bool
    let data: CommunityRequestUpdate
}

struct CommunityRequestUpdate: Decodable, Equatable {
    let id: String
    let postId: String
    let note: String?
    let locationSharing: ExplorePostLocationSharing
    let updatedAt: String
}

enum CommunityTaxonDisplay {
    static func name(commonName: String?, scientificName: String?) -> String {
        if let commonName = commonName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !commonName.isEmpty {
            return commonName
        }
        if let scientificName = scientificName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !scientificName.isEmpty {
            return scientificName
        }
        return "Unknown taxon"
    }

    static func rankTitle(_ rank: String?) -> String {
        guard let rank else { return "Taxon" }
        switch rank.lowercased() {
        case "kingdom": return "Kingdom"
        case "phylum": return "Phylum"
        case "class": return "Class"
        case "order": return "Order"
        case "family": return "Family"
        case "genus": return "Genus"
        case "species": return "Species"
        default: return "Taxon"
        }
    }
}

struct ExploreAuthorProfile: Decodable, Equatable {
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorIsPro: Bool?
    let authorAvatarUrl: String?
    let speciesCount: Int
    let currentStreak: Int
    let heatmap: ExploreAuthorProfileHeatmap
    let awards: [ExploreAuthorProfileAward]
    let publishedPostCount: Int
    var followerCount: Int
    var followingCount: Int
    var viewerIsFollowing: Bool
    let previewPosts: [ExplorePost]

    var authorAvatarURL: URL? {
        guard let authorAvatarUrl else { return nil }
        return URL(string: authorAvatarUrl)
    }

    var publicAuthorDisplayName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }

    var publicUsernameDisplayName: String? {
        ExplorePost.publicUsernameDisplayValue(authorUsername)
    }

    var profileHeatmapData: ProfileHeatmapData {
        heatmap.profileHeatmapData
    }

    var awardPayloads: [AwardPayload] {
        awards.compactMap(\.awardPayload)
    }
}

struct ExploreAuthorProfileAward: Decodable, Equatable {
    let type: String
    let currentCount: Int
    let lastInteractionAt: String?

    var awardPayload: AwardPayload? {
        guard let achievementType = AchievementType(rawValue: type) else {
            return nil
        }

        return AwardPayload(
            type: achievementType,
            currentCount: currentCount,
            lastInteractionDate: parsedLastInteractionDate
        )
    }

    private var parsedLastInteractionDate: Date? {
        guard let lastInteractionAt else { return nil }
        return DateUtilities.iso8601FractionalFormatter.date(from: lastInteractionAt)
            ?? DateUtilities.iso8601Formatter.date(from: lastInteractionAt)
    }
}

struct ExploreAuthorProfileHeatmap: Decodable, Equatable {
    let totalCaptures: Int
    let currentMonthCaptures: Int
    let yearString: String
    let weeks: [ExploreAuthorProfileHeatmapWeek]

    var profileHeatmapData: ProfileHeatmapData {
        ProfileHeatmapData(
            totalCaptures: totalCaptures,
            currentMonthCaptures: currentMonthCaptures,
            yearString: yearString,
            weeks: weeks.map(\.profileHeatmapWeek)
        )
    }
}

struct ExploreAuthorProfileHeatmapWeek: Decodable, Equatable {
    let monthLabel: String?
    let days: [ExploreAuthorProfileHeatmapDay]

    var profileHeatmapWeek: HeatmapWeek {
        HeatmapWeek(
            days: days.map(\.profileHeatmapDay),
            monthLabel: monthLabel
        )
    }
}

struct ExploreAuthorProfileHeatmapDay: Decodable, Equatable {
    let count: Int
    let date: String

    var profileHeatmapDay: HeatmapDay {
        HeatmapDay(
            count: count,
            date: DateUtilities.iso8601Formatter.date(from: date) ?? Date(timeIntervalSince1970: 0)
        )
    }
}

enum ExploreMapMode: String, Decodable {
    case clusters
    case posts
}

enum ExploreCoordinateVisibility: String, Decodable {
    case exact
    case obscured
}

struct ExploreMapPointsResponse: Decodable {
    let mode: ExploreMapMode
    let visibleCount: Int
    let categoryCounts: [ExploreMapCategoryCount]
    let clusters: [ExploreMapCluster]
    let posts: [ExploreMapPost]

    private enum CodingKeys: String, CodingKey {
        case mode
        case visibleCount
        case categoryCounts
        case clusters
        case posts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(ExploreMapMode.self, forKey: .mode)
        visibleCount = try container.decode(Int.self, forKey: .visibleCount)
        categoryCounts = try container.decodeIfPresent([ExploreMapCategoryCount].self, forKey: .categoryCounts) ?? []
        clusters = try container.decode([ExploreMapCluster].self, forKey: .clusters)
        posts = try container.decode([ExploreMapPost].self, forKey: .posts)
    }
}

enum ExploreMapSpeciesCategory: String, Codable, CaseIterable, Identifiable {
    case plants
    case fungi
    case birds
    case mammals
    case reptiles
    case amphibians
    case fish
    case insects
    case arachnids
    case other

    static let defaultFilters: [ExploreMapSpeciesCategory] = [
        .birds,
        .insects,
        .plants,
        .fungi,
        .mammals,
        .reptiles,
        .amphibians,
        .fish,
        .arachnids,
        .other
    ]

    var id: String { rawValue }

    var sortPriority: Int {
        Self.defaultFilters.firstIndex(of: self) ?? Self.defaultFilters.count
    }

    var title: String {
        switch self {
        case .plants: return "Plants"
        case .fungi: return "Fungi"
        case .birds: return "Birds"
        case .mammals: return "Mammals"
        case .reptiles: return "Reptiles"
        case .amphibians: return "Amphibians"
        case .fish: return "Fish"
        case .insects: return "Insects"
        case .arachnids: return "Arachnids"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .plants: return "leaf"
        case .fungi: return "circle.hexagongrid"
        case .birds: return "bird"
        case .mammals: return "pawprint"
        case .reptiles: return "lizard"
        case .amphibians: return "drop"
        case .fish: return "fish"
        case .insects: return "ladybug"
        case .arachnids: return "ant"
        case .other: return "sparkle"
        }
    }
}

struct ExploreMapCategoryCount: Decodable, Identifiable, Equatable {
    let category: ExploreMapSpeciesCategory
    let count: Int

    var id: ExploreMapSpeciesCategory { category }
}

struct ExploreMapCluster: Decodable, Identifiable, Equatable {
    let id: String
    let latitude: Double
    let longitude: Double
    let postCount: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ExploreMapPost: Decodable, Identifiable, Equatable {
    let postId: String
    let scanId: String
    let latitude: Double
    let longitude: Double
    let coordinateVisibility: ExploreCoordinateVisibility
    let heroImageUrl: String
    let sharedAt: String
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    let authorIsPro: Bool?
    let speciesCommonName: String
    let speciesScientificName: String
    let petIdentification: PetIdentification?
    let taxonomyKingdom: String?
    let taxonomyClass: String?
    let publicLocationLabel: String?
    let locationSharing: ExplorePostLocationSharing?
    let timeOfDay: String?
    let currentMonth: Int?
    let weatherCondition: String?
    let weatherTemperatureF: Double?
    var likeCount: Int
    var commentCount: Int
    var viewerHasLiked: Bool
    let isOwnedByViewer: Bool

    var id: String { postId }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var publicDisplayLocationLabel: String? {
        ExploreLocationPrivacy.displayLabel(from: publicLocationLabel)
    }

    var asExplorePost: ExplorePost {
        ExplorePost(
            postId: postId,
            scanId: scanId,
            heroImageUrl: heroImageUrl,
            sharedAt: sharedAt,
            authorUserId: authorUserId,
            authorName: authorName,
            authorUsername: authorUsername,
            authorAvatarUrl: authorAvatarUrl,
            authorIsPro: authorIsPro,
            hashtags: nil,
            speciesCommonName: speciesCommonName,
            speciesScientificName: speciesScientificName,
            petIdentification: petIdentification,
            publicLocationLabel: publicLocationLabel,
            locationSharing: locationSharing,
            timeOfDay: timeOfDay,
            currentMonth: currentMonth,
            weatherCondition: weatherCondition,
            weatherTemperatureF: weatherTemperatureF,
            likeCount: likeCount,
            commentCount: commentCount,
            viewerHasLiked: viewerHasLiked,
            isOwnedByViewer: isOwnedByViewer,
            rankingValue: nil
        )
    }
}

struct ExploreCommentsResponse: Decodable {
    let data: [ExploreComment]
}

struct ExploreMentionSuggestionsResponse: Decodable {
    let data: [ExploreMentionSuggestion]
}

struct ExploreScanShareStateResponse: Decodable {
    let data: ExploreScanShareState
}

struct ExplorePostDetailResponse: Decodable {
    let schemaVersion: Int?
    let data: ExplorePostDetail

    var effectiveSchemaVersion: Int { schemaVersion ?? 0 }
}

struct ExploreNotificationsResponse: Decodable {
    let data: [ExploreNotification]
}

struct ExploreUnreadNotificationCountResponse: Decodable {
    let unreadCount: Int
}

struct ExploreMarkNotificationsReadResponse: Decodable {
    let success: Bool
    let markedCount: Int
}

struct PublicUsernameUpdateResponse: Decodable {
    let username: String
}

struct PublicAvatarUpdateResponse: Decodable {
    let avatarUrl: String
}

struct PublicUsernameAvailabilityResponse: Decodable {
    let available: Bool
    let username: String
    let error: String?
}

struct ExplorePostDetail: Decodable {
    let postId: String
    var fieldNotes: String?
    var locationSharing: ExplorePostLocationSharing?
    let hashtags: [String]?
    let speciesDictionaryId: String?
    let alternativeCommonNames: [String]?
    let petIdentification: PetIdentification?
    let taxonomyKingdom: String?
    let taxonomyPhylum: String?
    let taxonomyClass: String?
    let taxonomyOrder: String?
    let taxonomyFamily: String?
    let taxonomyGenus: String?
    let aiReasoning: String?
    let habitatDescription: String?
    let gbifTaxonKey: Int?
    let iucnRedListStatus: String?
    let hazardType: String?
    let wikipediaUrl: String?
    let referenceImageUrl: String?
    let wikipediaOverview: String?
    let similarSpecies: [SimilarSpeciesEntry]?

    var taxonomyData: TaxonomyData? {
        let taxonomy = TaxonomyData(
            kingdom: taxonomyKingdom,
            phylum: taxonomyPhylum,
            className: taxonomyClass,
            order: taxonomyOrder,
            family: taxonomyFamily,
            genus: taxonomyGenus
        )

        let values = [
            taxonomy.kingdom,
            taxonomy.phylum,
            taxonomy.className,
            taxonomy.order,
            taxonomy.family,
            taxonomy.genus
        ]

        return values.contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ? taxonomy : nil
    }

    var hasHabitatDistributionContent: Bool {
        if let habitatDescription,
           !habitatDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        return gbifTaxonKey != nil
    }

    var hasOverviewContent: Bool {
        if let iucnRedListStatus,
           !iucnRedListStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if let wikipediaOverview,
           wikipediaOverview.trimmingCharacters(in: .whitespacesAndNewlines).count >= 60 {
            return true
        }

        return false
    }

    var referenceGalleryImages: [ExploreReferenceGalleryImage] {
        let rawUrls = referenceImageUrl?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? []

        var seen = Set<String>()

        return rawUrls.enumerated().compactMap { index, rawUrl in
            guard !rawUrl.isEmpty, seen.insert(rawUrl).inserted else { return nil }

            return ExploreReferenceGalleryImage(
                id: rawUrl,
                url: rawUrl,
                source: referenceImageSource(for: rawUrl, index: index)
            )
        }
    }

    var similarSpeciesData: SimilarSpecies? {
        let entries = (similarSpecies ?? []).filter { entry in
            !entry.scientificName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return entries.isEmpty ? nil : SimilarSpecies(entries: entries)
    }

    var trimmedAiReasoning: String? {
        guard let aiReasoning else { return nil }
        let trimmed = aiReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedFieldNotes: String? {
        guard let fieldNotes else { return nil }
        let trimmed = fieldNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func referenceImageSource(for urlString: String, index: Int) -> ExploreReferenceGalleryImage.Source {
        let host = URL(string: urlString)?.host?.lowercased() ?? ""
        if host == "media.merian.app" || host.hasSuffix(".merian.app") {
            return .merian
        }

        if host.contains("wikipedia") || host.contains("wikimedia") {
            return .wikipedia
        }

        if let wikipediaUrl,
           !wikipediaUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           index == 0 {
            return .wikipedia
        }

        return .gbif
    }
}

struct ExploreReferenceGalleryImage: Identifiable, Equatable {
    enum Source: Equatable {
        case wikipedia
        case gbif
        case merian

        var label: String {
            switch self {
            case .wikipedia:
                return "Wikipedia"
            case .gbif:
                return "GBIF"
            case .merian:
                return "Merian"
            }
        }

        var iconName: String {
            switch self {
            case .wikipedia:
                return "book.closed"
            case .gbif:
                return "globe.americas"
            case .merian:
                return "camera"
            }
        }

        var caption: String {
            switch self {
            case .wikipedia:
                return "Reference image"
            case .gbif:
                return "Field observation"
            case .merian:
                return "Merian observation"
            }
        }
    }

    let id: String
    let url: String
    let source: Source
}

struct ExploreComment: Decodable, Identifiable, Equatable {
    let commentId: String
    let postId: String
    let parentCommentId: String?
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    let body: String
    let createdAt: String
    let viewerCanDelete: Bool
    let viewerCanModerate: Bool
    let viewerCanReport: Bool
    var replyCount: Int?
    var reactions: [ExploreCommentReaction]?
    var mentions: [ExploreCommentMention]?

    var id: String { commentId }

    var createdAtDate: Date? {
        DateUtilities.iso8601FractionalFormatter.date(from: createdAt)
            ?? DateUtilities.iso8601Formatter.date(from: createdAt)
    }

    var hasOverflowActions: Bool {
        viewerCanDelete || viewerCanModerate || viewerCanReport
    }

    var removalActionTitle: String {
        viewerCanModerate ? "Remove from post" : "Delete comment"
    }

    var removalSuccessMessage: String {
        viewerCanModerate ? "Comment removed from post" : "Comment deleted"
    }

    var isReply: Bool {
        parentCommentId != nil
    }
}

struct ExploreCommentReaction: Decodable, Identifiable, Equatable {
    let emoji: String
    var count: Int
    var viewerHasReacted: Bool
    
    var id: String { emoji }
}

struct ExploreCommentMention: Decodable, Identifiable, Equatable {
    let userId: String
    let username: String
    let displayName: String
    let avatarUrl: String?

    var id: String { userId }
    var displayUsername: String { "@\(username)" }
}

struct ExploreMentionSuggestion: Decodable, Identifiable, Equatable {
    enum Source: String, Decodable {
        case postAuthor = "post_author"
        case thread
        case following
    }

    let userId: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let source: Source

    var id: String { userId }
    var displayUsername: String { "@\(username)" }
}

struct ExploreShareResponse: Decodable {
    let success: Bool
    let postId: String
    let scanId: String
    let sharedAt: String
    let locationSharing: ExplorePostLocationSharing?
}

struct ExploreScanShareState: Decodable, Equatable {
    let scanId: String
    let postId: String?
    let sharedAt: String?
    let communityRequestId: String?
    let communityRequestStatus: CommunityIdentificationRequestStatus?
    let isExploreFeedVisible: Bool
    let locationSharing: ExplorePostLocationSharing?

    private enum CodingKeys: String, CodingKey {
        case scanId
        case postId
        case sharedAt
        case communityRequestId
        case communityRequestStatus
        case isExploreFeedVisible
        case locationSharing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scanId = try container.decode(String.self, forKey: .scanId)
        postId = try container.decodeIfPresent(String.self, forKey: .postId)
        sharedAt = try container.decodeIfPresent(String.self, forKey: .sharedAt)
        communityRequestId = try container.decodeIfPresent(String.self, forKey: .communityRequestId)
        communityRequestStatus = try container.decodeIfPresent(
            CommunityIdentificationRequestStatus.self,
            forKey: .communityRequestStatus
        )
        isExploreFeedVisible = try container.decodeIfPresent(Bool.self, forKey: .isExploreFeedVisible)
            ?? (postId != nil && communityRequestId == nil)
        locationSharing = try container.decodeIfPresent(ExplorePostLocationSharing.self, forKey: .locationSharing)
    }
}

struct ExploreLikeResponse: Decodable {
    let success: Bool
    let postId: String
    let viewerHasLiked: Bool
    let likeCount: Int
}

struct ExploreCreateCommentResponse: Decodable {
    let success: Bool
    let comment: ExploreComment
    let commentCount: Int
}

struct ExploreDeleteCommentResponse: Decodable {
    let success: Bool
    let commentId: String
    let commentCount: Int
    let action: String
}

struct ExploreUpdateFieldNotesResponse: Decodable {
    let success: Bool
    let postId: String
    let fieldNotes: String?
    let hashtags: [String]?
    let speciesCommonName: String?
    let locationSharing: ExplorePostLocationSharing?
}

struct CommunityFeedbackSubmission: Encodable {
    let feedback: String
    let appVersion: String
    let buildNumber: String
    let platform: String
    let osVersion: String

    enum CodingKeys: String, CodingKey {
        case feedback
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case platform
        case osVersion = "os_version"
    }

    init(feedback: String) {
        self.feedback = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        self.platform = "ios"
        self.osVersion = UIDevice.current.systemVersion
    }
}
