import CoreLocation
import Foundation

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
    let publicLocationLabel: String?
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
    let clusters: [ExploreMapCluster]
    let posts: [ExploreMapPost]
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
    let publicLocationLabel: String?
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
            publicLocationLabel: publicLocationLabel,
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
    let hashtags: [String]?
    let speciesDictionaryId: String?
    let alternativeCommonNames: [String]?
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
}

struct ExploreScanShareState: Decodable, Equatable {
    let scanId: String
    let postId: String?
    let sharedAt: String?
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
}
