import Foundation

struct ExploreNotificationReplyThreadRoute: Identifiable, Equatable {
    let post: ExplorePost
    let parentCommentId: String?
    let targetReplyId: String
    let fallbackReply: ExploreNotificationReplyFallback

    var id: String {
        "\(post.id)-\(parentCommentId ?? "unknown-parent")-\(targetReplyId)"
    }

    init(
        post: ExplorePost,
        parentCommentId: String?,
        targetReplyId: String,
        fallbackReply: ExploreNotificationReplyFallback
    ) {
        self.post = post
        self.parentCommentId = parentCommentId
        self.targetReplyId = targetReplyId
        self.fallbackReply = fallbackReply
    }
}

struct ExploreNotificationReplyFallback: Hashable {
    let commentId: String
    let body: String?
    let authorUserId: String?
    let authorName: String?
    let createdAt: String
}
