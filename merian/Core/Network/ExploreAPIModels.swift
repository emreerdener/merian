import CoreLocation
import Foundation

struct ExploreFeedResponse: Decodable {
    let data: [ExplorePost]
}

struct ExplorePostResponse: Decodable {
    let data: ExplorePost
}

struct ExplorePost: Decodable, Identifiable, Equatable {
    let postId: String
    let scanId: String
    let heroImageUrl: String
    let sharedAt: String
    let authorUserId: String
    let authorName: String
    let authorAvatarUrl: String?
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

    var sharedAtDate: Date? {
        DateUtilities.iso8601FractionalFormatter.date(from: sharedAt)
            ?? DateUtilities.iso8601Formatter.date(from: sharedAt)
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
    let authorAvatarUrl: String?
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

    var asExplorePost: ExplorePost {
        ExplorePost(
            postId: postId,
            scanId: scanId,
            heroImageUrl: heroImageUrl,
            sharedAt: sharedAt,
            authorUserId: authorUserId,
            authorName: authorName,
            authorAvatarUrl: authorAvatarUrl,
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
            isOwnedByViewer: isOwnedByViewer
        )
    }
}

struct ExploreCommentsResponse: Decodable {
    let data: [ExploreComment]
}

struct ExplorePostDetailResponse: Decodable {
    let data: ExplorePostDetail
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

struct ExplorePostDetail: Decodable {
    let postId: String
    let speciesDictionaryId: String?
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
    let wikipediaOverview: String?

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

    var trimmedAiReasoning: String? {
        guard let aiReasoning else { return nil }
        let trimmed = aiReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ExploreComment: Decodable, Identifiable, Equatable {
    let commentId: String
    let postId: String
    let authorUserId: String
    let authorName: String
    let body: String
    let createdAt: String
    let viewerCanDelete: Bool
    let viewerCanModerate: Bool
    let viewerCanReport: Bool

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
}

struct ExploreShareResponse: Decodable {
    let success: Bool
    let postId: String
    let scanId: String
    let sharedAt: String
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
