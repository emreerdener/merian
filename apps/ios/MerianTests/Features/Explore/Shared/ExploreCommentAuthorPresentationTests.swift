import XCTest

@testable import Merian

@MainActor
final class ExploreCommentAuthorPresentationTests: XCTestCase {
    func testCommentAvatarTakesPriorityWhenTransportIsSecure() {
        let post = makePost(
            authorUserId: "post-author",
            authorAvatarURL: "https://example.com/post-author.jpg"
        )
        let comment = makeComment(
            authorUserId: "viewer-1",
            authorAvatarURL: "https://example.com/comment-author.jpg"
        )
        let viewer = ExploreCommentViewerContext(
            userID: "viewer-1",
            avatarURL: URL(string: "https://example.com/viewer.jpg")
        )

        XCTAssertEqual(
            ExploreCommentAuthorPresentation.avatarURL(
                for: comment,
                post: post,
                viewer: viewer
            )?.absoluteString,
            "https://example.com/comment-author.jpg"
        )
    }

    func testViewerFallbackUsesCaseInsensitiveIdentityWhenPayloadAvatarIsUnsafe() {
        let post = makePost()
        let comment = makeComment(
            authorUserId: "VIEWER-1",
            authorAvatarURL: "http://example.com/unsafe.jpg"
        )
        let viewer = ExploreCommentViewerContext(
            userID: "viewer-1",
            avatarURL: URL(string: "https://example.com/viewer.jpg")
        )

        XCTAssertEqual(
            ExploreCommentAuthorPresentation.avatarURL(
                for: comment,
                post: post,
                viewer: viewer
            )?.absoluteString,
            "https://example.com/viewer.jpg"
        )
    }

    func testPostAuthorFallbackUsesPreparedPostAvatar() {
        let post = makePost(
            authorUserId: "post-author",
            authorAvatarURL: "https://example.com/post-author.jpg"
        )
        let comment = makeComment(authorUserId: "POST-AUTHOR")

        XCTAssertEqual(
            ExploreCommentAuthorPresentation.avatarURL(
                for: comment,
                post: post,
                viewer: ExploreCommentViewerContext(userID: nil, avatarURL: nil)
            )?.absoluteString,
            "https://example.com/post-author.jpg"
        )
    }

    func testUnknownAuthorWithoutSecureAvatarHasNoFallback() {
        let post = makePost()
        let comment = makeComment(authorUserId: "another-user")

        XCTAssertNil(ExploreCommentAuthorPresentation.avatarURL(
            for: comment,
            post: post,
            viewer: ExploreCommentViewerContext(userID: nil, avatarURL: nil)
        ))
    }

    private func makePost(
        authorUserId: String = "post-author",
        authorAvatarURL: String? = nil
    ) -> ExplorePost {
        ExplorePost(
            postId: "post-1",
            scanId: "scan-1",
            heroImageUrl: "https://example.com/post.jpg",
            sharedAt: "2026-08-01T12:00:00Z",
            authorUserId: authorUserId,
            authorName: "Post Author",
            authorUsername: "post_author",
            authorAvatarUrl: authorAvatarURL,
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

    private func makeComment(
        authorUserId: String,
        authorAvatarURL: String? = nil
    ) -> ExploreComment {
        ExploreComment(
            commentId: "comment-1",
            postId: "post-1",
            parentCommentId: nil,
            authorUserId: authorUserId,
            authorName: "Comment Author",
            authorUsername: "comment_author",
            authorAvatarUrl: authorAvatarURL,
            body: "A field note",
            createdAt: "2026-08-01T12:00:00Z",
            viewerCanDelete: false,
            viewerCanModerate: false,
            viewerCanReport: true,
            replyCount: nil,
            reactions: nil,
            mentions: nil
        )
    }
}
