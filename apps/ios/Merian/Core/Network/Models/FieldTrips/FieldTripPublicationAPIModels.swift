import Foundation

struct FieldTripRecentPublicationsResponse: Decodable {
    let data: [FieldTripRecentPublication]
}

struct FieldTripCommunityPublicationsResponse: Decodable {
    let data: [FieldTripRecentPublication]
}

struct FieldTripPublicationDetailResponse: Decodable {
    let data: FieldTripPublicationDetail
}

struct FieldTripCommentsResponse: Decodable {
    let data: [ExploreComment]
}

struct FieldTripCreateCommentResponse: Decodable {
    let comment: ExploreComment
    let commentCount: Int
}

struct FieldTripLikeResponse: Decodable, Equatable {
    let publicationId: String
    let viewerHasLiked: Bool
    let likeCount: Int
    let commentCount: Int?
}

struct FieldTripRecentPublication: Decodable, Identifiable, Equatable {
    let publicationId: String
    let templateId: String
    let title: String
    let description: String?
    let publishedAt: String
    let likeCount: Int
    let commentCount: Int
    let slug: String
    let templateTitle: String
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
    let isPinned: Bool
    let pinPosition: Int?
    let rankBucket: Int?
    let communityReason: String?
    let viewerIsFollowingAuthor: Bool

    var id: String { publicationId }

    private enum CodingKeys: String, CodingKey {
        case publicationId
        case templateId
        case title
        case description
        case publishedAt
        case likeCount
        case commentCount
        case slug
        case templateTitle
        case regionTags
        case seasonTags
        case habitatTags
        case coverImageUrl
        case itemCount
        case viewerHasLiked
        case authorUserId
        case authorName
        case authorUsername
        case authorAvatarUrl
        case isPinned
        case pinPosition
        case rankBucket
        case communityReason
        case viewerIsFollowingAuthor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publicationId = try container.decode(String.self, forKey: .publicationId)
        templateId = try container.decode(String.self, forKey: .templateId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        publishedAt = try container.decode(String.self, forKey: .publishedAt)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        slug = try container.decode(String.self, forKey: .slug)
        templateTitle = try container.decode(String.self, forKey: .templateTitle)
        regionTags = try container.decodeIfPresent([String].self, forKey: .regionTags) ?? []
        seasonTags = try container.decodeIfPresent([String].self, forKey: .seasonTags) ?? []
        habitatTags = try container.decodeIfPresent([String].self, forKey: .habitatTags) ?? []
        coverImageUrl = try container.decodeIfPresent(String.self, forKey: .coverImageUrl)
        itemCount = try container.decode(Int.self, forKey: .itemCount)
        viewerHasLiked = try container.decode(Bool.self, forKey: .viewerHasLiked)
        authorUserId = try container.decode(String.self, forKey: .authorUserId)
        authorName = try container.decode(String.self, forKey: .authorName)
        authorUsername = try container.decodeIfPresent(String.self, forKey: .authorUsername)
        authorAvatarUrl = try container.decodeIfPresent(String.self, forKey: .authorAvatarUrl)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinPosition = try container.decodeIfPresent(Int.self, forKey: .pinPosition)
        rankBucket = try container.decodeIfPresent(Int.self, forKey: .rankBucket)
        communityReason = try container.decodeIfPresent(String.self, forKey: .communityReason)
        viewerIsFollowingAuthor = try container.decodeIfPresent(Bool.self, forKey: .viewerIsFollowingAuthor) ?? false
    }
}

struct FieldTripPublicationDetail: Decodable, Identifiable, Equatable {
    let publicationId: String
    let userFieldTripId: String
    let templateId: String
    let templateSlug: String
    let templateTitle: String
    let title: String
    let description: String?
    let aiSummary: String?
    let publishedAt: String
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    var likeCount: Int
    var commentCount: Int
    var viewerHasLiked: Bool
    let items: [FieldTripPublicationItem]

    var id: String { publicationId }
}

struct FieldTripPublicationItem: Decodable, Identifiable, Equatable {
    let publicationItemId: String
    let itemId: String
    let prompt: String
    let commonName: String?
    let scientificName: String?
    let heroImageUrl: String?
    let referenceImageUrl: String?
    let taxonomy: [String: String?]?

    var id: String { publicationItemId }
}
