import Foundation

@testable import Merian

@MainActor
enum ExploreNotificationsTestFixtures {
    enum StubError: Error {
        case failed
        case unexpected
    }

    typealias LoadNotifications = @MainActor (
        _ limit: Int,
        _ beforeUpdatedAt: String?,
        _ beforeNotificationId: String?
    ) async throws -> [ExploreNotification]
    typealias LoadComments = @MainActor (
        _ postId: String,
        _ limit: Int,
        _ afterCreatedAt: String?,
        _ afterCommentId: String?
    ) async throws -> [ExploreComment]
    typealias LoadReplies = @MainActor (
        _ parentCommentId: String,
        _ limit: Int,
        _ afterCreatedAt: String?,
        _ afterCommentId: String?
    ) async throws -> [ExploreComment]

    static func notification(
        id: String,
        type: ExploreNotificationType = .comment,
        postId: String? = "post-1",
        communityRequestId: String? = nil,
        fieldTripPublicationId: String? = nil,
        commentId: String? = "comment-1",
        parentCommentId: String? = nil,
        reactionEmoji: String? = nil,
        triggeringUserId: String? = "author-1",
        triggeringUserName: String? = "Avery Explorer",
        commentBody: String? = "A field note",
        recentActorNames: [String] = [],
        actionCount: Int = 1,
        isRead: Bool = false,
        isReplyToViewerComment: Bool? = nil,
        communityTaxonCommonName: String? = nil,
        communityTaxonScientificName: String? = nil,
        communityRequestDisplayName: String? = nil,
        createdAt: String = "2026-08-01T12:00:00Z",
        updatedAt: String = "2026-08-01T12:00:00Z"
    ) -> ExploreNotification {
        ExploreNotification(
            notificationId: id,
            postId: postId,
            communityRequestId: communityRequestId,
            fieldTripPublicationId: fieldTripPublicationId,
            type: type,
            commentId: commentId,
            parentCommentId: parentCommentId,
            reactionEmoji: reactionEmoji,
            triggeringUserId: triggeringUserId,
            triggeringUserName: triggeringUserName,
            commentBody: commentBody,
            recentActorNames: recentActorNames,
            actionCount: actionCount,
            isRead: isRead,
            isReplyToViewerComment: isReplyToViewerComment,
            communityTaxonCommonName: communityTaxonCommonName,
            communityTaxonScientificName: communityTaxonScientificName,
            communityRequestDisplayName: communityRequestDisplayName,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func post(
        id: String = "post-1",
        authorUserId: String = "post-author",
        authorAvatarUrl: String? = nil
    ) -> ExplorePost {
        ExplorePost(
            postId: id,
            scanId: "scan-\(id)",
            heroImageUrl: "https://example.com/\(id).jpg",
            sharedAt: "2026-08-01T12:00:00Z",
            authorUserId: authorUserId,
            authorName: "Post Author",
            authorUsername: "post_author",
            authorAvatarUrl: authorAvatarUrl,
            authorIsPro: false,
            hashtags: nil,
            speciesCommonName: "Northern Cardinal",
            speciesScientificName: "Cardinalis cardinalis",
            petIdentification: nil,
            publicLocationLabel: nil,
            locationSharing: nil,
            timeOfDay: nil,
            currentMonth: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false,
            isOwnedByViewer: false,
            rankingValue: nil,
            mediaItems: nil
        )
    }

    static func comment(
        id: String,
        postId: String = "post-1",
        parentCommentId: String? = nil,
        authorUserId: String = "author-1",
        authorAvatarUrl: String? = nil,
        body: String = "A field note",
        createdAt: String = "2026-08-01T12:00:00Z",
        reactions: [ExploreCommentReaction]? = nil
    ) -> ExploreComment {
        ExploreComment(
            commentId: id,
            postId: postId,
            parentCommentId: parentCommentId,
            authorUserId: authorUserId,
            authorName: "Avery Explorer",
            authorUsername: "avery",
            authorAvatarUrl: authorAvatarUrl,
            body: body,
            createdAt: createdAt,
            viewerCanDelete: false,
            viewerCanModerate: false,
            viewerCanReport: true,
            replyCount: nil,
            reactions: reactions,
            mentions: nil
        )
    }

    static func replyRoute(
        post: ExplorePost? = nil,
        parentCommentId: String? = "parent",
        targetReplyId: String = "target",
        fallbackBody: String? = nil
    ) -> ExploreNotificationReplyThreadRoute {
        let resolvedPost = post ?? Self.post()
        return ExploreNotificationReplyThreadRoute(
            post: resolvedPost,
            parentCommentId: parentCommentId,
            targetReplyId: targetReplyId,
            fallbackReply: ExploreNotificationReplyFallback(
                commentId: targetReplyId,
                body: fallbackBody,
                authorUserId: "fallback-author",
                authorName: "Fallback Author",
                createdAt: "2026-08-01T12:00:00Z"
            )
        )
    }

    static func catalogDependencies(
        loadNotifications: @escaping LoadNotifications = { _, _, _ in [] },
        markNotificationsRead: @escaping @MainActor () async throws -> Void = {},
        includesFieldTripNotifications: @escaping @MainActor () -> Bool = { true },
        reportFetchFailure: @escaping @MainActor (Error, String) -> Void = { _, _ in },
        errorMessage: @escaping @MainActor (Error) -> String = { _ in "Stub error" }
    ) -> ExploreNotificationsViewModel.Dependencies {
        ExploreNotificationsViewModel.Dependencies(
            loadNotifications: loadNotifications,
            markNotificationsRead: markNotificationsRead,
            includesFieldTripNotifications: includesFieldTripNotifications,
            reportFetchFailure: reportFetchFailure,
            errorMessage: errorMessage
        )
    }

    static func replyDependencies(
        loadComments: @escaping LoadComments = { _, _, _, _ in [] },
        loadReplies: @escaping LoadReplies = { _, _, _, _ in [] },
        currentViewer: @escaping @MainActor () -> ExploreCommentViewerContext = {
            ExploreCommentViewerContext(userID: nil, avatarURL: nil)
        },
        errorMessage: @escaping @MainActor (Error) -> String = { _ in "Stub error" },
        commentsPageSize: Int = 2,
        repliesPageSize: Int = 2,
        maximumPageCount: Int = 3
    ) -> ExploreNotificationReplyThreadViewModel.Dependencies {
        ExploreNotificationReplyThreadViewModel.Dependencies(
            loadComments: loadComments,
            loadReplies: loadReplies,
            currentViewer: currentViewer,
            errorMessage: errorMessage,
            commentsPageSize: commentsPageSize,
            repliesPageSize: repliesPageSize,
            maximumPageCount: maximumPageCount
        )
    }
}
