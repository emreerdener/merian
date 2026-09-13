import Foundation

struct FieldTripProfileSummariesResponse: Decodable {
    let data: FieldTripProfileSummaries
}

struct FieldTripSetPinnedPublicationsResponse: Decodable {
    let data: FieldTripProfileSummaries
}

struct FieldTripProfileSummaries: Decodable, Equatable {
    let active: [FieldTripProfileActiveSummary]
    let pinned: [FieldTripProfilePublishedSummary]
    let published: [FieldTripProfilePublishedSummary]
    let challengeBadges: [FieldTripChallengeBadge]

    private enum CodingKeys: String, CodingKey {
        case active
        case pinned
        case published
        case challengeBadges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        active = try container.decodeIfPresent([FieldTripProfileActiveSummary].self, forKey: .active) ?? []
        pinned = try container.decodeIfPresent([FieldTripProfilePublishedSummary].self, forKey: .pinned) ?? []
        published = try container.decodeIfPresent([FieldTripProfilePublishedSummary].self, forKey: .published) ?? []
        challengeBadges = try container.decodeIfPresent([FieldTripChallengeBadge].self, forKey: .challengeBadges) ?? []
    }
}

struct FieldTripChallengeBadge: Decodable, Identifiable, Equatable {
    let badgeId: String
    let challengeId: String
    let badgeKey: String
    let title: String
    let awardedAt: String
    let challengeSlug: String
    let challengeTitle: String
    let coverImageUrl: String?
    let regionTags: [String]
    let seasonTags: [String]
    let habitatTags: [String]

    var id: String { badgeId }
}

struct FieldTripProfileActiveSummary: Decodable, Identifiable, Equatable {
    let userFieldTripId: String
    let templateId: String
    let slug: String
    let title: String
    let startedAt: String?
    let currentLevelNumber: Int
    let currentLevelTitle: String?
    let completedCount: Int
    let targetCount: Int
    let isComplete: Bool

    var id: String { userFieldTripId }
}

struct FieldTripProfilePublishedSummary: Decodable, Identifiable, Equatable {
    let publicationId: String
    let title: String
    let description: String?
    let publishedAt: String
    let likeCount: Int
    let commentCount: Int
    let slug: String
    let templateTitle: String
    let coverImageUrl: String?
    let itemCount: Int
    let viewerHasLiked: Bool
    let isPinned: Bool
    let pinPosition: Int?

    var id: String { publicationId }

    private enum CodingKeys: String, CodingKey {
        case publicationId
        case title
        case description
        case publishedAt
        case likeCount
        case commentCount
        case slug
        case templateTitle
        case coverImageUrl
        case itemCount
        case viewerHasLiked
        case isPinned
        case pinPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publicationId = try container.decode(String.self, forKey: .publicationId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        publishedAt = try container.decode(String.self, forKey: .publishedAt)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        slug = try container.decode(String.self, forKey: .slug)
        templateTitle = try container.decode(String.self, forKey: .templateTitle)
        coverImageUrl = try container.decodeIfPresent(String.self, forKey: .coverImageUrl)
        itemCount = try container.decode(Int.self, forKey: .itemCount)
        viewerHasLiked = try container.decode(Bool.self, forKey: .viewerHasLiked)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinPosition = try container.decodeIfPresent(Int.self, forKey: .pinPosition)
    }
}
