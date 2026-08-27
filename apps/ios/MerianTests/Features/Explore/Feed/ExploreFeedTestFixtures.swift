import Foundation

@testable import Merian

@MainActor
enum ExploreFeedTestFixtures {
    enum StubError: Error {
        case failed
        case unexpected
    }

    typealias LoadPosts = @MainActor (
        _ limit: Int,
        _ filter: ExploreFeedFilter,
        _ latitude: Double?,
        _ longitude: Double?,
        _ cursor: ExploreFeedCursor?,
        _ advancedFilters: ExploreFeedAdvancedFilters,
        _ sharedSince: Date?
    ) async throws -> [ExplorePost]
    typealias SetLike = @MainActor (
        _ postId: String,
        _ liked: Bool
    ) async throws -> ExploreLikeResponse
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
    typealias CreateComment = @MainActor (
        _ postId: String,
        _ body: String,
        _ parentCommentId: String?
    ) async throws -> ExploreCreateCommentResponse

    static func post(
        id: String,
        sharedAt: String = "2026-08-01T12:00:00Z",
        likeCount: Int = 0,
        viewerHasLiked: Bool = false,
        commentCount: Int = 0,
        authorUserId: String = "author-1",
        authorAvatarUrl: String? = nil,
        mediaItems: [ExploreMediaItem]? = nil
    ) -> ExplorePost {
        ExplorePost(
            postId: id,
            scanId: "scan-\(id)",
            heroImageUrl: "https://example.com/\(id).jpg",
            sharedAt: sharedAt,
            authorUserId: authorUserId,
            authorName: "Avery Explorer",
            authorUsername: "avery",
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
            likeCount: likeCount,
            commentCount: commentCount,
            viewerHasLiked: viewerHasLiked,
            isOwnedByViewer: false,
            rankingValue: nil,
            mediaItems: mediaItems
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
        replyCount: Int? = nil
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
            replyCount: replyCount,
            reactions: nil,
            mentions: nil
        )
    }

    static func detail(
        postId: String,
        fieldNotes: String? = "Original notes",
        locationSharing: ExplorePostLocationSharing? = .obscured
    ) -> ExplorePostDetail {
        ExplorePostDetail(
            postId: postId,
            fieldNotes: fieldNotes,
            locationSharing: locationSharing,
            mapPoint: nil,
            hashtags: ["birding"],
            speciesDictionaryId: nil,
            alternativeCommonNames: nil,
            petIdentification: nil,
            taxonomyKingdom: "Animalia",
            taxonomyPhylum: nil,
            taxonomyClass: nil,
            taxonomyOrder: nil,
            taxonomyFamily: nil,
            taxonomyGenus: nil,
            aiReasoning: nil,
            habitatDescription: nil,
            gbifTaxonKey: nil,
            iucnRedListStatus: nil,
            hazardType: nil,
            wikipediaUrl: nil,
            referenceImageUrl: nil,
            wikipediaOverview: nil,
            similarSpecies: nil
        )
    }

    static func appSettings() -> AppSettings {
        let suiteName = "ExploreFeedViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        return AppSettings(userDefaults: defaults, observeExternalChanges: false)
    }

    static func dependencies(
        loadPosts: @escaping LoadPosts = { _, _, _, _, _, _, _ in [] },
        setLike: @escaping SetLike = { postId, liked in
            ExploreLikeResponse(
                success: true,
                postId: postId,
                viewerHasLiked: liked,
                likeCount: liked ? 1 : 0
            )
        },
        loadComments: @escaping LoadComments = { _, _, _, _ in [] },
        loadReplies: @escaping LoadReplies = { _, _, _, _ in [] },
        createComment: @escaping CreateComment = { _, _, _ in
            throw StubError.unexpected
        },
        currentViewer: @escaping @MainActor () -> ExploreCommentViewerContext = {
            ExploreCommentViewerContext(userID: nil, avatarURL: nil)
        },
        selectionFeedback: @escaping @MainActor () -> Void = {},
        successFeedback: @escaping @MainActor () -> Void = {},
        errorFeedback: @escaping @MainActor () -> Void = {}
    ) -> ExploreFeedViewModel.Dependencies {
        ExploreFeedViewModel.Dependencies(
            feed: .init(
                loadPosts: loadPosts,
                loadFieldTripPublications: { _, _ in [] },
                now: { Date(timeIntervalSince1970: 1_786_000_000) }
            ),
            interactions: .init(
                setLike: setLike,
                unsharePost: { _ in throw StubError.unexpected },
                reportPost: { _ in throw StubError.unexpected },
                blockAuthor: { _ in false },
                loadPost: { _ in throw StubError.unexpected },
                sendShareStateChanged: { _, _ in }
            ),
            comments: .init(
                loadComments: loadComments,
                loadReplies: loadReplies,
                createComment: createComment,
                deleteComment: { _ in throw StubError.unexpected },
                reportComment: { _ in throw StubError.unexpected },
                toggleReaction: { _, _ in throw StubError.unexpected },
                loadMentionSuggestions: { _, _, _, _ in [] },
                currentViewer: currentViewer
            ),
            feedback: .init(
                selection: selectionFeedback,
                success: successFeedback,
                error: errorFeedback,
                sheet: {},
                medium: {}
            ),
            notifications: .init(
                refreshUnreadCount: { _ in nil },
                startUpdates: { _ in },
                stopUpdates: {}
            ),
            errorMessage: { _ in "Stub error" }
        )
    }
}
