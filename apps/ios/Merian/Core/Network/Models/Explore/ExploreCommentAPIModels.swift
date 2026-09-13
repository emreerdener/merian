import Foundation

struct ExploreCommentsResponse: Decodable {
    let data: [ExploreComment]
}

struct ExploreMentionSuggestionsResponse: Decodable {
    let data: [ExploreMentionSuggestion]
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
