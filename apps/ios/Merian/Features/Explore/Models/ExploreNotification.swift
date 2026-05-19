import Foundation

enum ExploreNotificationType: String, Decodable {
    case likeAggregated = "like_aggregated"
    case comment
    case commentReaction = "comment_reaction"
    case commentReply = "comment_reply"
    case follow
}

struct ExploreNotification: Decodable, Identifiable, Equatable {
    let notificationId: String
    let postId: String?
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
