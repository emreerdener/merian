import XCTest

@testable import Merian

@MainActor
final class ExploreAuthorDisplayNameTests: XCTestCase {
    func testDisplayNameRemovesTrailingLastInitialOnly() {
        XCTAssertEqual(ExplorePost.publicAuthorDisplayName(from: "River W."), "River")
        XCTAssertEqual(ExplorePost.publicAuthorDisplayName(from: "Mary Jane W."), "Mary Jane")
        XCTAssertEqual(ExplorePost.publicAuthorDisplayName(from: "Moss Walker"), "Moss Walker")
    }

    func testPreferUsernameUsesHandleWhenAvailable() {
        XCTAssertEqual(
            ExplorePost.publicAuthorDisplayName(
                from: "River W.",
                username: "river_w",
                preferUsername: true
            ),
            "@river_w"
        )
    }

    func testDefaultDisplayNameStillPrefersPublicName() {
        XCTAssertEqual(
            ExplorePost.publicAuthorDisplayName(from: "River W.", username: "river_w"),
            "River"
        )
    }

    func testPreferUsernameFallsBackToPublicNameWhenMissingOrBlank() {
        XCTAssertEqual(
            ExplorePost.publicAuthorDisplayName(
                from: "River W.",
                username: nil,
                preferUsername: true
            ),
            "River"
        )
        XCTAssertEqual(
            ExplorePost.publicAuthorDisplayName(
                from: "River W.",
                username: "   ",
                preferUsername: true
            ),
            "River"
        )
    }

    func testUsernameDisplayTrimsWhitespaceAndAddsAtPrefixOnce() {
        XCTAssertEqual(ExplorePost.publicUsernameDisplayValue(" river_w "), "@river_w")
        XCTAssertEqual(ExplorePost.publicUsernameDisplayValue("@river_w"), "@river_w")
    }

    func testCommentDisplayNamePrefersUsernameWhenAvailable() {
        let comment = ExploreComment(
            commentId: "comment-123",
            postId: "post-123",
            parentCommentId: nil,
            authorUserId: "author-123",
            authorName: "River W.",
            authorUsername: "river_w",
            authorAvatarUrl: nil,
            body: "Beautiful find.",
            createdAt: "2026-06-15T10:00:00.000Z",
            viewerCanDelete: false,
            viewerCanModerate: false,
            viewerCanReport: true,
            replyCount: nil,
            reactions: nil,
            mentions: nil
        )

        XCTAssertEqual(comment.displayAuthorName, "@river_w")
    }

    func testReactionToggleAddsNewViewerReaction() {
        let updatedComment = makeComment(reactions: nil)
            .applyingReactionToggle(emoji: "\u{1F44D}")

        XCTAssertEqual(updatedComment.reactions?.count, 1)
        XCTAssertEqual(updatedComment.reactions?.first?.emoji, "\u{1F44D}")
        XCTAssertEqual(updatedComment.reactions?.first?.count, 1)
        XCTAssertEqual(updatedComment.reactions?.first?.viewerHasReacted, true)
    }

    func testReactionToggleIncrementsInactiveReaction() {
        let updatedComment = makeComment(
            reactions: [
                ExploreCommentReaction(emoji: "\u{1F44D}", count: 2, viewerHasReacted: false)
            ]
        )
        .applyingReactionToggle(emoji: "\u{1F44D}")

        XCTAssertEqual(updatedComment.reactions?.first?.count, 3)
        XCTAssertEqual(updatedComment.reactions?.first?.viewerHasReacted, true)
    }

    func testReactionToggleRemovesLastActiveReaction() {
        let updatedComment = makeComment(
            reactions: [
                ExploreCommentReaction(emoji: "\u{1F44D}", count: 1, viewerHasReacted: true)
            ]
        )
        .applyingReactionToggle(emoji: "\u{1F44D}")

        XCTAssertEqual(updatedComment.reactions?.isEmpty, true)
    }

    func testReactionToggleDecrementsActiveMultiCountReaction() {
        let updatedComment = makeComment(
            reactions: [
                ExploreCommentReaction(emoji: "\u{1F44D}", count: 3, viewerHasReacted: true)
            ]
        )
        .applyingReactionToggle(emoji: "\u{1F44D}")

        XCTAssertEqual(updatedComment.reactions?.first?.count, 2)
        XCTAssertEqual(updatedComment.reactions?.first?.viewerHasReacted, false)
    }

    private func makeComment(reactions: [ExploreCommentReaction]?) -> ExploreComment {
        ExploreComment(
            commentId: "comment-123",
            postId: "post-123",
            parentCommentId: nil,
            authorUserId: "author-123",
            authorName: "River W.",
            authorUsername: "river_w",
            authorAvatarUrl: nil,
            body: "Beautiful find.",
            createdAt: "2026-06-15T10:00:00.000Z",
            viewerCanDelete: false,
            viewerCanModerate: false,
            viewerCanReport: true,
            replyCount: nil,
            reactions: reactions,
            mentions: nil
        )
    }
}
