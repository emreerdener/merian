import Foundation

struct FieldTripsCatalogResponse: Decodable {
    let data: [FieldTripTemplate]
}

struct FieldTripProgressUpdatesResponse: Decodable {
    let data: [FieldTripProgressUpdate]
}

struct FieldTripProfileSummariesResponse: Decodable {
    let data: FieldTripProfileSummaries
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

struct FieldTripTemplate: Decodable, Identifiable, Equatable {
    let templateId: String
    let slug: String
    let title: String
    let subtitle: String?
    let description: String?
    let regionTags: [String]
    let seasonTags: [String]
    let habitatTags: [String]
    let difficulty: String
    let isProOnly: Bool
    let isRotatingFree: Bool
    let viewerHasAccess: Bool
    let accessKind: String
    let activeProgress: FieldTripProgress?
    let levels: [FieldTripLevel]

    var id: String { templateId }
}

struct FieldTripLevel: Decodable, Identifiable, Equatable {
    let levelId: String
    let levelNumber: Int
    let title: String
    let description: String?
    let items: [FieldTripChecklistItem]

    var id: String { levelId }
}

struct FieldTripChecklistItem: Decodable, Identifiable, Equatable {
    let itemId: String
    let prompt: String
    let matchType: String
    let isCompleted: Bool
    let completedAt: String?
    let completedCommonName: String?
    let completedScientificName: String?

    var id: String { itemId }
}

struct FieldTripProgress: Decodable, Equatable {
    let userFieldTripId: String
    let startedAt: String
    let currentLevelNumber: Int
    let completedAt: String?
    let isProfileVisible: Bool
    let completedCount: Int
    let targetCount: Int

    var isComplete: Bool { completedAt != nil }
    var fractionComplete: Double {
        guard targetCount > 0 else { return 0 }
        return min(1, max(0, Double(completedCount) / Double(targetCount)))
    }
}

struct FieldTripProgressUpdate: Decodable, Identifiable, Equatable {
    let userFieldTripId: String
    let templateId: String
    let slug: String
    let title: String
    let currentLevelNumber: Int
    let currentLevelTitle: String?
    let completedCount: Int
    let targetCount: Int
    let isComplete: Bool
    let newlyCompletedItems: [FieldTripProgressCompletedItem]

    var id: String { userFieldTripId }
}

struct FieldTripProgressCompletedItem: Decodable, Identifiable, Equatable {
    let itemId: String
    let prompt: String
    let commonName: String?
    let scientificName: String?
    let completedAt: String?

    var id: String { itemId }
}

struct FieldTripProfileSummaries: Decodable, Equatable {
    let active: [FieldTripProfileActiveSummary]
    let published: [FieldTripProfilePublishedSummary]

    var isEmpty: Bool {
        active.isEmpty && published.isEmpty
    }
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

    var id: String { publicationId }
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

    var publicAuthorDisplayName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }
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

    var displayName: String {
        commonName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? scientificName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? prompt
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
