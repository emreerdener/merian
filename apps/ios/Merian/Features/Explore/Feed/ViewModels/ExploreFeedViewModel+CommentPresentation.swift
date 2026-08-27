import Foundation

extension ExploreFeedViewModel {
    var currentUserCommentAvatarURL: URL? {
        dependencies.comments.currentViewer().avatarURL
    }

    func commentAuthorAvatarURL(
        for comment: ExploreComment,
        post: ExplorePost
    ) -> URL? {
        ExploreCommentAuthorPresentation.avatarURL(
            for: comment,
            post: post,
            viewer: dependencies.comments.currentViewer()
        )
    }

    func loadMentionSuggestions(
        postId: String,
        parentCommentId: String?,
        query: String,
        limit: Int
    ) async throws -> [ExploreMentionSuggestion] {
        try await dependencies.comments.loadMentionSuggestions(
            postId,
            parentCommentId,
            query,
            limit
        )
    }
}
