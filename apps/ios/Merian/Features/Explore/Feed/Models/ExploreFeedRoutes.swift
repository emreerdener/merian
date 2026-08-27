enum ExplorePostDetailOrigin: Hashable {
    case feed
    case map
    case other

    var allowsObservationMapNavigation: Bool {
        self == .feed
    }
}

struct ExplorePostRoute: Hashable {
    let postId: String
    let shouldFocusCommentComposer: Bool
    let shouldOpenInsight: Bool
    let targetCommentId: String?
    let targetReplyParentCommentId: String?
    let notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget?
    let authorProfileDepth: Int
    let origin: ExplorePostDetailOrigin

    var allowsObservationMapNavigation: Bool {
        origin.allowsObservationMapNavigation
    }

    init(
        postId: String,
        shouldFocusCommentComposer: Bool,
        shouldOpenInsight: Bool,
        targetCommentId: String?,
        targetReplyParentCommentId: String?,
        notificationReplyThreadTarget: ExploreNotificationReplyThreadTarget? = nil,
        authorProfileDepth: Int = 0,
        origin: ExplorePostDetailOrigin = .other
    ) {
        self.postId = postId
        self.shouldFocusCommentComposer = shouldFocusCommentComposer
        self.shouldOpenInsight = shouldOpenInsight
        self.targetCommentId = targetCommentId
        self.targetReplyParentCommentId = targetReplyParentCommentId
        self.notificationReplyThreadTarget = notificationReplyThreadTarget
        self.authorProfileDepth = authorProfileDepth
        self.origin = origin
    }
}

struct ExploreNotificationReplyThreadTarget: Hashable {
    let parentCommentId: String?
    let targetReplyId: String
    let fallbackReply: ExploreNotificationReplyFallback
}

struct ExploreHashtagRoute: Hashable {
    let hashtag: String
}
