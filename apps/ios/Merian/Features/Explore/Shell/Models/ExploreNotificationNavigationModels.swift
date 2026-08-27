import Foundation

enum ExploreNotificationDismissalDestination: Equatable {
    case scansLibrary
    case communityRequest(String)
    case fieldTripPublication(String)
    case post(
        postId: String,
        focusCommentComposer: Bool,
        targetCommentId: String?,
        targetReplyParentCommentId: String?,
        replyThreadTarget: ExploreNotificationReplyThreadTarget?
    )
}

struct ExploreNotificationOpenToken: Equatable {
    private let id: UUID

    init() {
        id = UUID()
    }
}

enum ExploreNotificationOpenOutcome {
    case staged(ExploreNotificationOpenToken)
    case failed(ExploreNotificationOpenToken, Error)
    case ignored
}
