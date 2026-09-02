import Foundation

/// Explore comments, social actions, and moderation requests. Feature state and
/// optimistic updates stay with callers; authenticated transport remains shared.
extension MerianNetworkClient {
    func getExploreComments(
        postId: String,
        limit: Int = 100,
        afterCreatedAt: String? = nil,
        afterCommentId: String? = nil
    ) async throws -> [ExploreComment] {
        var payload: [String: Any] = [
            "post_id": postId,
            "limit": limit
        ]

        if let afterCreatedAt, let afterCommentId {
            payload["after_created_at"] = afterCreatedAt
            payload["after_comment_id"] = afterCommentId
        }

        return try await performAuthenticatedJSONPost(
            function: "get-explore-comments", payload: payload, responseType: ExploreCommentsResponse.self
        ).data
    }

    func getExploreCommentReplies(
        parentCommentId: String,
        limit: Int = 25,
        afterCreatedAt: String? = nil,
        afterCommentId: String? = nil
    ) async throws -> [ExploreComment] {
        var payload: [String: Any] = [
            "parent_comment_id": parentCommentId,
            "limit": limit
        ]

        if let afterCreatedAt, let afterCommentId {
            payload["after_created_at"] = afterCreatedAt
            payload["after_comment_id"] = afterCommentId
        }

        return try await performAuthenticatedJSONPost(
            function: "get-explore-comment-replies", payload: payload, responseType: ExploreCommentsResponse.self
        ).data
    }

    func getExploreMentionSuggestions(
        postId: String,
        parentCommentId: String? = nil,
        query: String,
        limit: Int = 8
    ) async throws -> [ExploreMentionSuggestion] {
        var payload: [String: Any] = [
            "post_id": postId,
            "query": query,
            "limit": limit
        ]
        if let parentCommentId {
            payload["parent_comment_id"] = parentCommentId
        }

        return try await performAuthenticatedJSONPost(
            function: "get-explore-mention-suggestions", payload: payload, responseType: ExploreMentionSuggestionsResponse.self
        ).data
    }

    func setExplorePostLike(postId: String, liked: Bool) async throws -> ExploreLikeResponse {
        let payload: [String: Any] = [
            "post_id": postId,
            "liked": liked
        ]
        return try await performAuthenticatedJSONPost(
            function: "set-explore-post-like", payload: payload, responseType: ExploreLikeResponse.self
        )
    }

    func setUserFollow(authorUserId: String, isFollowing: Bool) async throws -> ExploreFollowState {
        let payload: [String: Any] = [
            "author_user_id": authorUserId,
            "is_following": isFollowing
        ]
        return try await performAuthenticatedJSONPost(
            function: "set-user-follow", payload: payload, responseType: ExploreFollowState.self
        )
    }

    func createExploreComment(postId: String, body: String, parentCommentId: String? = nil) async throws -> ExploreCreateCommentResponse {
        var payload: [String: Any] = [
            "post_id": postId,
            "body": body
        ]
        if let parentCommentId {
            payload["parent_comment_id"] = parentCommentId
        }
        return try await performAuthenticatedJSONPost(
            function: "create-explore-comment", payload: payload, responseType: ExploreCreateCommentResponse.self
        )
    }

    func deleteExploreComment(commentId: String) async throws -> ExploreDeleteCommentResponse {
        let payload: [String: Any] = ["comment_id": commentId]
        return try await performAuthenticatedJSONPost(
            function: "delete-explore-comment", payload: payload, responseType: ExploreDeleteCommentResponse.self
        )
    }

    func toggleExploreCommentReaction(commentId: String, emoji: String) async throws {
        let payload: [String: Any] = [
            "comment_id": commentId,
            "emoji": emoji
        ]
        try await performAuthenticatedJSONPost(
            function: "toggle-explore-comment-reaction", payload: payload
        )
    }

    func reportExploreComment(
        commentId: String,
        reason: String = "Inappropriate content",
        details: String = "Reported from Explore comments"
    ) async throws {
        let payload: [String: Any] = [
            "comment_id": commentId,
            "reason": reason,
            "details": details
        ]
        try await performAuthenticatedJSONPost(
            function: "report-explore-comment", payload: payload
        )
    }

    func reportExplorePost(
        postId: String,
        reason: String = "Inappropriate content",
        details: String = "Reported from Explore feed"
    ) async throws {
        let payload: [String: Any] = [
            "post_id": postId,
            "reason": reason,
            "details": details
        ]
        try await performAuthenticatedJSONPost(
            function: "report-explore-post", payload: payload
        )
    }

    func reportUser(
        reportedUserId: String,
        reason: ExploreUserReportReason,
        details: String?
    ) async throws {
        var payload: [String: Any] = [
            "reported_user_id": reportedUserId,
            "reason": reason.rawValue
        ]
        if let details = details?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
            payload["details"] = details
        }
        try await performAuthenticatedJSONPost(
            function: "report-user", payload: payload
        )
    }

    func blockUser(targetUserId: String) async throws {
        let payload: [String: Any] = ["blocked_id": targetUserId]
        try await performAuthenticatedJSONPost(
            function: "block-user", payload: payload
        )
    }
}
