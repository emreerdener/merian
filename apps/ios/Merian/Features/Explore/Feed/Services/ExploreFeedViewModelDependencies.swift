import Foundation

struct ExploreFeedDependencies {
    struct Feed {
        let loadPosts: @MainActor (
            _ limit: Int,
            _ filter: ExploreFeedFilter,
            _ latitude: Double?,
            _ longitude: Double?,
            _ cursor: ExploreFeedCursor?,
            _ advancedFilters: ExploreFeedAdvancedFilters,
            _ sharedSince: Date?
        ) async throws -> [ExplorePost]
        let loadFieldTripPublications: @MainActor (
            _ mode: FieldTripCommunityMode,
            _ limit: Int
        ) async throws -> [FieldTripRecentPublication]
        let now: @MainActor () -> Date
    }

    struct Interactions {
        let setLike: @MainActor (
            _ postId: String,
            _ liked: Bool
        ) async throws -> ExploreLikeResponse
        let unsharePost: @MainActor (_ postId: String) async throws -> Void
        let reportPost: @MainActor (_ postId: String) async throws -> Void
        let blockAuthor: @MainActor (_ authorUserId: String) async -> Bool
        let loadPost: @MainActor (_ postId: String) async throws -> ExplorePost
        let sendShareStateChanged: @MainActor (
            _ scanId: String,
            _ postId: String?
        ) -> Void
    }

    struct Comments {
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
        let createComment: @MainActor (
            _ postId: String,
            _ body: String,
            _ parentCommentId: String?
        ) async throws -> ExploreCreateCommentResponse
        let deleteComment: @MainActor (
            _ commentId: String
        ) async throws -> ExploreDeleteCommentResponse
        let reportComment: @MainActor (_ commentId: String) async throws -> Void
        let toggleReaction: @MainActor (
            _ commentId: String,
            _ emoji: String
        ) async throws -> Void
        let loadMentionSuggestions: @MainActor (
            _ postId: String,
            _ parentCommentId: String?,
            _ query: String,
            _ limit: Int
        ) async throws -> [ExploreMentionSuggestion]
        let currentViewer: @MainActor () -> ExploreCommentViewerContext
    }

    struct Feedback {
        let selection: @MainActor () -> Void
        let success: @MainActor () -> Void
        let error: @MainActor () -> Void
        let sheet: @MainActor () -> Void
        let medium: @MainActor () -> Void
    }

    struct Notifications {
        let refreshUnreadCount: @MainActor (_ force: Bool) async -> Int?
        let startUpdates: @MainActor (
            _ onCountChanged: @escaping @MainActor (Int) -> Void
        ) async -> Void
        let stopUpdates: @MainActor () -> Void
    }

    let feed: Feed
    let interactions: Interactions
    let comments: Comments
    let feedback: Feedback
    let notifications: Notifications
    let errorMessage: @MainActor (Error) -> String
}

extension ExploreFeedViewModel {
    typealias Dependencies = ExploreFeedDependencies
}

extension ExploreFeedDependencies {
    static var live: Self {
        let notificationService = ExploreUnreadNotificationService()
        return Self(
            feed: .init(
                loadPosts: { limit, filter, latitude, longitude, cursor, advancedFilters, sharedSince in
                    try await MerianNetworkClient.shared.getExploreFeed(
                        limit: limit,
                        filter: filter,
                        latitude: latitude,
                        longitude: longitude,
                        cursor: cursor,
                        advancedFilters: advancedFilters,
                        sharedSince: sharedSince
                    )
                },
                loadFieldTripPublications: { mode, limit in
                    try await MerianNetworkClient.shared.getFieldTripCommunityPublications(
                        mode: mode,
                        limit: limit
                    )
                },
                now: Date.init
            ),
            interactions: .init(
                setLike: { postId, liked in
                    try await MerianNetworkClient.shared.setExplorePostLike(
                        postId: postId,
                        liked: liked
                    )
                },
                unsharePost: { postId in
                    try await MerianNetworkClient.shared.unshareExplorePost(postId: postId)
                },
                reportPost: { postId in
                    try await MerianNetworkClient.shared.reportExplorePost(postId: postId)
                },
                blockAuthor: { authorUserId in
                    await SocialGuardManager.shared.blockUser(targetUserId: authorUserId)
                    return SocialGuardManager.shared.blockedUserIds.contains(authorUserId)
                },
                loadPost: { postId in
                    try await MerianNetworkClient.shared.getExplorePost(postId: postId)
                },
                sendShareStateChanged: { scanId, postId in
                    AppDIContainer.shared.appEventPublisher.send(
                        .exploreShareStateChanged(scanId: scanId, postId: postId)
                    )
                }
            ),
            comments: .init(
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
                createComment: { postId, body, parentCommentId in
                    try await MerianNetworkClient.shared.createExploreComment(
                        postId: postId,
                        body: body,
                        parentCommentId: parentCommentId
                    )
                },
                deleteComment: { commentId in
                    try await MerianNetworkClient.shared.deleteExploreComment(commentId: commentId)
                },
                reportComment: { commentId in
                    try await MerianNetworkClient.shared.reportExploreComment(commentId: commentId)
                },
                toggleReaction: { commentId, emoji in
                    try await MerianNetworkClient.shared.toggleExploreCommentReaction(
                        commentId: commentId,
                        emoji: emoji
                    )
                },
                loadMentionSuggestions: { postId, parentCommentId, query, limit in
                    try await MerianNetworkClient.shared.getExploreMentionSuggestions(
                        postId: postId,
                        parentCommentId: parentCommentId,
                        query: query,
                        limit: limit
                    )
                },
                currentViewer: {
                    guard SupabaseManager.shared.isAuthenticated else {
                        return ExploreCommentViewerContext(userID: nil, avatarURL: nil)
                    }
                    return ExploreCommentViewerContext(
                        userID: SupabaseManager.shared.currentUser?.id.uuidString,
                        avatarURL: SupabaseManager.shared.currentUserAvatarUrl
                    )
                }
            ),
            feedback: .init(
                selection: { HapticManager.shared.triggerSelectionPulse() },
                success: { HapticManager.shared.triggerSuccessPulse() },
                error: { HapticManager.shared.triggerErrorThump() },
                sheet: { HapticManager.shared.triggerSheetSpring() },
                medium: { HapticManager.shared.triggerMediumPulse() }
            ),
            notifications: .init(
                refreshUnreadCount: { force in
                    await notificationService.refreshUnreadCount(force: force)
                },
                startUpdates: { onCountChanged in
                    await notificationService.startUpdates(onCountChanged: onCountChanged)
                },
                stopUpdates: {
                    notificationService.stopUpdates()
                }
            ),
            errorMessage: ExploreErrorFormatter.message(for:)
        )
    }
}
