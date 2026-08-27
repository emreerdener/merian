import Foundation

struct ExploreCommentViewerContext: Equatable {
    let userID: String?
    let avatarURL: URL?
}

enum ExploreCommentAuthorPresentation {
    static func avatarURL(
        for comment: ExploreComment,
        post: ExplorePost,
        viewer: ExploreCommentViewerContext
    ) -> URL? {
        if let remoteAvatarURL = SecureTransportPolicy.httpsURL(
            from: comment.authorAvatarUrl
        ) {
            return remoteAvatarURL
        }

        if viewer.userID?.caseInsensitiveCompare(comment.authorUserId) == .orderedSame {
            return viewer.avatarURL
        }

        if post.authorUserId.caseInsensitiveCompare(comment.authorUserId) == .orderedSame {
            return SecureTransportPolicy.httpsURL(from: post.authorAvatarUrl)
        }

        return nil
    }
}
