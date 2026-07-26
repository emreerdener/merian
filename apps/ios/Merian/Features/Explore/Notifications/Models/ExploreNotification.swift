import Foundation

enum ExploreNotificationType: String, Decodable {
    case likeAggregated = "like_aggregated"
    case comment
    case commentReaction = "comment_reaction"
    case commentReply = "comment_reply"
    case commentMention = "comment_mention"
    case follow
    case communityIdentificationAdded = "community_identification_added"
    case communityRequestResolved = "community_request_resolved"
    case communityIdentificationHelped = "community_identification_helped"
    case mediaMissing = "media_missing"
    case mediaRestored = "media_restored"
    case fieldTripComment = "field_trip_comment"
    case fieldTripReply = "field_trip_reply"
    case fieldTripFollowedPublication = "field_trip_followed_publication"

    var isCommunityNotification: Bool {
        switch self {
        case .communityIdentificationAdded, .communityRequestResolved, .communityIdentificationHelped:
            return true
        case .likeAggregated,
             .comment,
             .commentReaction,
             .commentReply,
             .commentMention,
             .follow,
             .mediaMissing,
             .mediaRestored,
             .fieldTripComment,
             .fieldTripReply,
             .fieldTripFollowedPublication:
            return false
        }
    }

    var isFieldTripNotification: Bool {
        switch self {
        case .fieldTripComment, .fieldTripReply, .fieldTripFollowedPublication:
            return true
        case .likeAggregated,
             .comment,
             .commentReaction,
             .commentReply,
             .commentMention,
             .follow,
             .communityIdentificationAdded,
             .communityRequestResolved,
             .communityIdentificationHelped,
             .mediaMissing,
             .mediaRestored:
            return false
        }
    }

}

struct ExploreNotification: Decodable, Identifiable, Equatable {
    let notificationId: String
    let postId: String?
    let communityRequestId: String?
    let fieldTripPublicationId: String?
    let type: ExploreNotificationType
    let commentId: String?
    let parentCommentId: String?
    let reactionEmoji: String?
    let triggeringUserId: String?
    let triggeringUserName: String?
    let commentBody: String?
    let recentActorNames: [String]
    let actionCount: Int
    var isRead: Bool
    let isReplyToViewerComment: Bool?
    let communityTaxonCommonName: String?
    let communityTaxonScientificName: String?
    let communityRequestDisplayName: String?
    let createdAt: String
    let updatedAt: String

    var id: String { notificationId }

    var createdAtDate: Date? {
        DateUtilities.iso8601FractionalFormatter.date(from: createdAt)
            ?? DateUtilities.iso8601Formatter.date(from: createdAt)
    }

    var updatedAtDate: Date? {
        DateUtilities.iso8601FractionalFormatter.date(from: updatedAt)
            ?? DateUtilities.iso8601Formatter.date(from: updatedAt)
    }
}
