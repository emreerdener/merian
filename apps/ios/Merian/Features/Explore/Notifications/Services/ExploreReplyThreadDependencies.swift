import Foundation

struct ExploreReplyThreadDependencies {
    let loadComments: @MainActor (
        _ postId: String,
        _ limit: Int,
        _ afterCreatedAt: String?,
        _ afterCommentId: String?
    ) async throws -> [ExploreComment]
    let loadReplies: @MainActor (
        _ parentCommentId: String,
        _ limit: Int,
        _ afterCreatedAt: String?,
        _ afterCommentId: String?
    ) async throws -> [ExploreComment]
    let currentViewer: @MainActor () -> ExploreCommentViewerContext
    let errorMessage: @MainActor (Error) -> String

    let commentsPageSize: Int
    let repliesPageSize: Int
    let maximumPageCount: Int
}

extension ExploreNotificationReplyThreadViewModel {
    typealias Dependencies = ExploreReplyThreadDependencies
}

extension ExploreReplyThreadDependencies {
    static let live = Self(
        loadComments: { postId, limit, afterCreatedAt, afterCommentId in
            try await MerianNetworkClient.shared.getExploreComments(
                postId: postId,
                limit: limit,
                afterCreatedAt: afterCreatedAt,
                afterCommentId: afterCommentId
            )
        },
        loadReplies: { parentCommentId, limit, afterCreatedAt, afterCommentId in
            try await MerianNetworkClient.shared.getExploreCommentReplies(
                parentCommentId: parentCommentId,
                limit: limit,
                afterCreatedAt: afterCreatedAt,
                afterCommentId: afterCommentId
            )
        },
        currentViewer: {
            ExploreCommentViewerContext(
                userID: SupabaseManager.shared.currentUser?.id.uuidString,
                avatarURL: SupabaseManager.shared.currentUserAvatarUrl
            )
        },
        errorMessage: ExploreErrorFormatter.message(for:),
        commentsPageSize: 100,
        repliesPageSize: 100,
        maximumPageCount: 20
    )
}
