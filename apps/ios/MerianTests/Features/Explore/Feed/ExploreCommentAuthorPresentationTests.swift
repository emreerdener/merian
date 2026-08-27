import XCTest

@testable import Merian

@MainActor
final class ExploreCommentAuthorPresentationTests: XCTestCase {
    func testCommentAvatarTakesPriorityWhenTransportIsSecure() {
        let post = ExploreFeedTestFixtures.post(
            id: "post-1",
            authorUserId: "post-author",
            authorAvatarUrl: "https://example.com/post-author.jpg"
        )
        let comment = ExploreFeedTestFixtures.comment(
            id: "comment-1",
            authorUserId: "viewer-1",
            authorAvatarUrl: "https://example.com/comment-author.jpg"
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
        let post = ExploreFeedTestFixtures.post(id: "post-1")
        let comment = ExploreFeedTestFixtures.comment(
            id: "comment-1",
            authorUserId: "VIEWER-1",
            authorAvatarUrl: "http://example.com/unsafe.jpg"
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
        let post = ExploreFeedTestFixtures.post(
            id: "post-1",
            authorUserId: "post-author",
            authorAvatarUrl: "https://example.com/post-author.jpg"
        )
        let comment = ExploreFeedTestFixtures.comment(
            id: "comment-1",
            authorUserId: "POST-AUTHOR"
        )

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
        let post = ExploreFeedTestFixtures.post(id: "post-1")
        let comment = ExploreFeedTestFixtures.comment(
            id: "comment-1",
            authorUserId: "another-user"
        )

        XCTAssertNil(ExploreCommentAuthorPresentation.avatarURL(
            for: comment,
            post: post,
            viewer: ExploreCommentViewerContext(userID: nil, avatarURL: nil)
        ))
    }
}
