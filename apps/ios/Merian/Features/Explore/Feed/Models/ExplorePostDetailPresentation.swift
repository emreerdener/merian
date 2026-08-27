enum ExplorePostDetailPresentation: Identifiable, Equatable {
    case insight(ScanInsightRoute)
    case author(ExploreAuthorProfileRoute)
    case notificationReply(ExploreNotificationReplyThreadRoute)
    case fieldNotes(postId: String)
    case postComposer(postId: String)
    case fieldChat(postId: String)
    case paywall

    var id: String {
        switch self {
        case .insight(let route):
            "insight-\(route.id)"
        case .author(let route):
            "author-\(route.id)"
        case .notificationReply(let route):
            "notification-reply-\(route.id)"
        case .fieldNotes(let postId):
            "field-notes-\(postId)"
        case .postComposer(let postId):
            "post-composer-\(postId)"
        case .fieldChat(let postId):
            "field-chat-\(postId)"
        case .paywall:
            "paywall"
        }
    }
}

enum ExplorePostDetailPresentationPolicy {
    static func canCommitAsyncPresentation(
        requestedPostId: String,
        currentPostId: String?,
        hasPresentationConflict: Bool,
        isCancelled: Bool
    ) -> Bool {
        guard !isCancelled, !hasPresentationConflict, let currentPostId else {
            return false
        }
        return currentPostId.caseInsensitiveCompare(requestedPostId) == .orderedSame
    }
}
