import Foundation

struct FieldTripChallengesCatalogResponse: Decodable {
    let data: [FieldTripChallenge]
}

struct FieldTripChallengeDetailResponse: Decodable {
    let data: FieldTripChallenge
}

struct FieldTripChallengePublicationsResponse: Decodable {
    let data: [FieldTripChallengeEntry]
}

struct FieldTripChallengeEntryDetailResponse: Decodable {
    let data: FieldTripChallengeEntryDetail
}

struct FieldTripChallengeEntryLikeResponse: Decodable, Equatable {
    let entryId: String
    let viewerHasLiked: Bool
    let likeCount: Int
    let commentCount: Int?
}

struct FieldTripChallengeHashtagsResponse: Decodable {
    let data: [String]
}

struct FieldTripChallenge: Decodable, Identifiable, Equatable {
    let challengeId: String
    let templateId: String
    let templateSlug: String
    let templateTitle: String
    let slug: String
    let title: String
    let subtitle: String?
    let description: String?
    let coverImageUrl: String?
    let startsAt: String
    let endsAt: String
    let status: String
    let regionTags: [String]
    let seasonTags: [String]
    let habitatTags: [String]
    let suggestedHashtags: [String]
    let isProOnly: Bool
    let isTemporarilyFree: Bool
    let viewerHasAccess: Bool
    let accessKind: String
    let participantCount: Int
    let completionCount: Int
    let publishedEntryCount: Int
    let viewerParticipation: FieldTripChallengeParticipation?
    let template: FieldTripTemplate?
    let entries: [FieldTripChallengeEntry]

    var id: String { challengeId }

    private enum CodingKeys: String, CodingKey {
        case challengeId
        case templateId
        case templateSlug
        case templateTitle
        case slug
        case title
        case subtitle
        case description
        case coverImageUrl
        case startsAt
        case endsAt
        case status
        case regionTags
        case seasonTags
        case habitatTags
        case suggestedHashtags
        case isProOnly
        case isTemporarilyFree
        case viewerHasAccess
        case accessKind
        case participantCount
        case completionCount
        case publishedEntryCount
        case viewerParticipation
        case template
        case entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        challengeId = try container.decode(String.self, forKey: .challengeId)
        templateId = try container.decode(String.self, forKey: .templateId)
        templateSlug = try container.decodeIfPresent(String.self, forKey: .templateSlug) ?? ""
        templateTitle = try container.decodeIfPresent(String.self, forKey: .templateTitle) ?? ""
        slug = try container.decode(String.self, forKey: .slug)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        coverImageUrl = try container.decodeIfPresent(String.self, forKey: .coverImageUrl)
        startsAt = try container.decode(String.self, forKey: .startsAt)
        endsAt = try container.decode(String.self, forKey: .endsAt)
        status = try container.decode(String.self, forKey: .status)
        regionTags = try container.decodeIfPresent([String].self, forKey: .regionTags) ?? []
        seasonTags = try container.decodeIfPresent([String].self, forKey: .seasonTags) ?? []
        habitatTags = try container.decodeIfPresent([String].self, forKey: .habitatTags) ?? []
        suggestedHashtags = try container.decodeIfPresent([String].self, forKey: .suggestedHashtags) ?? []
        isProOnly = try container.decodeIfPresent(Bool.self, forKey: .isProOnly) ?? false
        isTemporarilyFree = try container.decodeIfPresent(Bool.self, forKey: .isTemporarilyFree) ?? false
        viewerHasAccess = try container.decodeIfPresent(Bool.self, forKey: .viewerHasAccess) ?? true
        accessKind = try container.decodeIfPresent(String.self, forKey: .accessKind) ?? "free"
        participantCount = try container.decodeIfPresent(Int.self, forKey: .participantCount) ?? 0
        completionCount = try container.decodeIfPresent(Int.self, forKey: .completionCount) ?? 0
        publishedEntryCount = try container.decodeIfPresent(Int.self, forKey: .publishedEntryCount) ?? 0
        viewerParticipation = try container.decodeIfPresent(FieldTripChallengeParticipation.self, forKey: .viewerParticipation)
        template = try container.decodeIfPresent(FieldTripTemplate.self, forKey: .template)
        entries = try container.decodeIfPresent([FieldTripChallengeEntry].self, forKey: .entries) ?? []
    }
}

struct FieldTripChallengeParticipation: Decodable, Equatable {
    let participationId: String
    let userFieldTripId: String
    let joinedAt: String
    let currentLevelNumber: Int
    let completedAt: String?
    let badgeAwardedAt: String?
    let completedCount: Int
    let targetCount: Int
}

struct FieldTripChallengeEntry: Decodable, Identifiable, Equatable {
    let entryId: String
    let challengeId: String
    let challengeSlug: String
    let challengeTitle: String
    let templateId: String
    let templateSlug: String
    let templateTitle: String
    let title: String
    let description: String?
    let publishedAt: String
    let likeCount: Int
    let commentCount: Int
    let regionTags: [String]
    let seasonTags: [String]
    let habitatTags: [String]
    let coverImageUrl: String?
    let itemCount: Int
    let viewerHasLiked: Bool
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?

    var id: String { entryId }
}

struct FieldTripChallengeEntryDetail: Decodable, Identifiable, Equatable {
    let entryId: String
    let participationId: String
    let challengeId: String
    let challengeSlug: String
    let challengeTitle: String
    let templateId: String
    let templateSlug: String
    let templateTitle: String
    let title: String
    let description: String?
    let publishedAt: String
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    var likeCount: Int
    var commentCount: Int
    var viewerHasLiked: Bool
    let isOwnedByViewer: Bool
    let items: [FieldTripChallengeEntryItem]

    var id: String { entryId }
}

struct FieldTripChallengeEntryItem: Decodable, Identifiable, Equatable {
    let entryItemId: String
    let itemId: String
    let prompt: String
    let commonName: String?
    let scientificName: String?
    let heroImageUrl: String?
    let referenceImageUrl: String?
    let taxonomy: [String: String?]?

    var id: String { entryItemId }
}
