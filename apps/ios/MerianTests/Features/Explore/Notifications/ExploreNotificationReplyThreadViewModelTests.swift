import XCTest

@testable import Merian

@MainActor
final class ExploreReplyThreadViewModelTests: XCTestCase {
    func testLoadFindsParentAndTargetAcrossCursorPages() async {
        let route = ExploreNotificationsTestFixtures.replyRoute()
        let otherParent = ExploreNotificationsTestFixtures.comment(id: "other-parent")
        let cursorParent = ExploreNotificationsTestFixtures.comment(
            id: "cursor-parent",
            createdAt: "2026-08-01T11:00:00Z"
        )
        let parent = ExploreNotificationsTestFixtures.comment(id: "parent")
        let firstReply = ExploreNotificationsTestFixtures.comment(
            id: "first-reply",
            parentCommentId: "parent"
        )
        let cursorReply = ExploreNotificationsTestFixtures.comment(
            id: "cursor-reply",
            parentCommentId: "parent",
            createdAt: "2026-08-01T11:00:00Z"
        )
        let target = ExploreNotificationsTestFixtures.comment(
            id: "target",
            parentCommentId: "parent",
            createdAt: "2026-08-01T10:00:00Z"
        )
        var commentCursors: [String?] = []
        var replyCursors: [String?] = []
        let viewModel = ExploreNotificationReplyThreadViewModel(
            dependencies: ExploreNotificationsTestFixtures.replyDependencies(
                loadComments: { _, limit, _, afterCommentId in
                    XCTAssertEqual(limit, 2)
                    commentCursors.append(afterCommentId)
                    return afterCommentId == nil ? [otherParent, cursorParent] : [parent]
                },
                loadReplies: { _, limit, _, afterCommentId in
                    XCTAssertEqual(limit, 2)
                    replyCursors.append(afterCommentId)
                    return afterCommentId == nil ? [firstReply, cursorReply] : [target]
                }
            )
        )

        await viewModel.load(route: route)

        XCTAssertEqual(viewModel.parentComment?.id, "parent")
        XCTAssertEqual(viewModel.replies.map(\.id), ["first-reply", "cursor-reply", "target"])
        XCTAssertEqual(commentCursors, [nil, "cursor-parent"])
        XCTAssertEqual(replyCursors, [nil, "cursor-reply"])
        XCTAssertTrue(viewModel.hasReachedEndOfReplies)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testMissingTargetUsesNotificationFallbackWithoutNetworkParent() async {
        let route = ExploreNotificationsTestFixtures.replyRoute(
            parentCommentId: nil,
            fallbackBody: "  Fallback reply  "
        )
        var loadCommentCount = 0
        var loadReplyCount = 0
        let viewModel = ExploreNotificationReplyThreadViewModel(
            dependencies: ExploreNotificationsTestFixtures.replyDependencies(
                loadComments: { _, _, _, _ in
                    loadCommentCount += 1
                    return []
                },
                loadReplies: { _, _, _, _ in
                    loadReplyCount += 1
                    return []
                }
            )
        )

        await viewModel.load(route: route)

        XCTAssertNil(viewModel.parentComment)
        XCTAssertEqual(viewModel.replies.map(\.id), ["target"])
        XCTAssertEqual(viewModel.replies[0].body, "Fallback reply")
        XCTAssertEqual(viewModel.replies[0].authorName, "Fallback Author")
        XCTAssertEqual(loadCommentCount, 0)
        XCTAssertEqual(loadReplyCount, 0)
        XCTAssertTrue(viewModel.hasReachedEndOfReplies)
    }

    func testLaterPageReplacesNotificationFallbackWithAuthoritativeReply() async {
        let route = ExploreNotificationsTestFixtures.replyRoute(
            fallbackBody: "Fallback reply"
        )
        let firstReply = ExploreNotificationsTestFixtures.comment(
            id: "first-reply",
            parentCommentId: "parent"
        )
        let cursorReply = ExploreNotificationsTestFixtures.comment(
            id: "cursor-reply",
            parentCommentId: "parent",
            createdAt: "2026-08-01T11:00:00Z"
        )
        let authoritativeTarget = ExploreNotificationsTestFixtures.comment(
            id: "target",
            parentCommentId: "parent",
            body: "Authoritative reply"
        )
        let viewModel = ExploreNotificationReplyThreadViewModel(
            dependencies: ExploreNotificationsTestFixtures.replyDependencies(
                loadReplies: { _, _, _, afterCommentId in
                    afterCommentId == nil
                        ? [firstReply, cursorReply]
                        : [authoritativeTarget]
                },
                maximumPageCount: 1
            )
        )

        await viewModel.load(route: route)

        XCTAssertEqual(viewModel.replies.first?.id, "target")
        XCTAssertEqual(viewModel.replies.first?.body, "Fallback reply")
        XCTAssertFalse(viewModel.hasReachedEndOfReplies)

        await viewModel.loadMoreReplies()

        XCTAssertEqual(viewModel.replies.map(\.id), ["target", "first-reply", "cursor-reply"])
        XCTAssertEqual(viewModel.replies.first?.body, "Authoritative reply")
        XCTAssertEqual(viewModel.replies.first?.authorName, "Avery Explorer")
        XCTAssertEqual(viewModel.replies.first?.viewerCanReport, true)
        XCTAssertTrue(viewModel.hasReachedEndOfReplies)
    }

    func testRefreshSupersedesPaginationAndDiscardsItsStalePage() async {
        let route = ExploreNotificationsTestFixtures.replyRoute()
        let parent = ExploreNotificationsTestFixtures.comment(id: "parent")
        let target = ExploreNotificationsTestFixtures.comment(
            id: "target",
            parentCommentId: "parent"
        )
        let cursorReply = ExploreNotificationsTestFixtures.comment(
            id: "cursor-reply",
            parentCommentId: "parent",
            createdAt: "2026-08-01T11:00:00Z"
        )
        let stale = ExploreNotificationsTestFixtures.comment(
            id: "stale",
            parentCommentId: "parent"
        )
        let refreshed = ExploreNotificationsTestFixtures.comment(
            id: "refreshed",
            parentCommentId: "parent"
        )
        let paginationStarted = expectation(description: "Reply pagination started")
        var firstPageLoadCount = 0
        var pendingPagination: CheckedContinuation<[ExploreComment], any Error>?
        let viewModel = ExploreNotificationReplyThreadViewModel(
            dependencies: ExploreNotificationsTestFixtures.replyDependencies(
                loadComments: { _, _, _, _ in [parent] },
                loadReplies: { _, _, _, afterCommentId in
                    if afterCommentId != nil {
                        return try await withCheckedThrowingContinuation { continuation in
                            pendingPagination = continuation
                            paginationStarted.fulfill()
                        }
                    }

                    firstPageLoadCount += 1
                    return firstPageLoadCount == 1 ? [target, cursorReply] : [refreshed]
                }
            )
        )

        await viewModel.load(route: route)
        let paginationTask = Task { await viewModel.loadMoreReplies() }
        await fulfillment(of: [paginationStarted], timeout: 1)

        await viewModel.load(route: route)
        pendingPagination?.resume(returning: [stale])
        _ = await paginationTask.value

        XCTAssertEqual(firstPageLoadCount, 2)
        XCTAssertEqual(viewModel.replies.map(\.id), ["refreshed"])
        XCTAssertTrue(viewModel.hasReachedEndOfReplies)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isLoadingMoreReplies)
    }

    func testNewRouteDiscardsLatePreviousRouteResult() async {
        let firstRoute = ExploreNotificationsTestFixtures.replyRoute(
            post: ExploreNotificationsTestFixtures.post(id: "first-post"),
            parentCommentId: "first-parent",
            targetReplyId: "first-target"
        )
        let secondRoute = ExploreNotificationsTestFixtures.replyRoute(
            post: ExploreNotificationsTestFixtures.post(id: "second-post"),
            parentCommentId: "second-parent",
            targetReplyId: "second-target"
        )
        let firstStarted = expectation(description: "First route started")
        let firstReply = ExploreNotificationsTestFixtures.comment(
            id: "first-target",
            postId: "first-post",
            parentCommentId: "first-parent"
        )
        let secondReply = ExploreNotificationsTestFixtures.comment(
            id: "second-target",
            postId: "second-post",
            parentCommentId: "second-parent"
        )
        var pendingFirst: CheckedContinuation<[ExploreComment], any Error>?
        let viewModel = ExploreNotificationReplyThreadViewModel(
            dependencies: ExploreNotificationsTestFixtures.replyDependencies(
                loadComments: { _, _, _, _ in [] },
                loadReplies: { parentCommentId, _, _, _ in
                    if parentCommentId == "first-parent" {
                        return try await withCheckedThrowingContinuation { continuation in
                            pendingFirst = continuation
                            firstStarted.fulfill()
                        }
                    }
                    return [secondReply]
                }
            )
        )

        let firstTask = Task { await viewModel.load(route: firstRoute) }
        await fulfillment(of: [firstStarted], timeout: 1)
        await viewModel.load(route: secondRoute)
        pendingFirst?.resume(returning: [firstReply])
        _ = await firstTask.value

        XCTAssertEqual(viewModel.replies.map(\.id), ["second-target"])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testReactionToggleUpdatesLocalThreadAndForwardsOriginalComment() async {
        let route = ExploreNotificationsTestFixtures.replyRoute()
        let target = ExploreNotificationsTestFixtures.comment(
            id: "target",
            parentCommentId: "parent",
            reactions: [
                ExploreCommentReaction(
                    emoji: "👍",
                    count: 2,
                    viewerHasReacted: false
                )
            ]
        )
        var forwardedCommentId: String?
        var forwardedEmoji: String?
        let viewModel = ExploreNotificationReplyThreadViewModel(
            dependencies: ExploreNotificationsTestFixtures.replyDependencies(
                loadReplies: { _, _, _, _ in [target] }
            ),
            onToggleReaction: { comment, emoji in
                forwardedCommentId = comment.id
                forwardedEmoji = emoji
            }
        )
        await viewModel.load(route: route)

        viewModel.toggleReaction(for: target, emoji: "👍")

        XCTAssertEqual(forwardedCommentId, "target")
        XCTAssertEqual(forwardedEmoji, "👍")
        XCTAssertEqual(viewModel.replies[0].reactions?[0].count, 3)
        XCTAssertEqual(viewModel.replies[0].reactions?[0].viewerHasReacted, true)
    }

    func testLoadFailureUsesInjectedErrorMessage() async {
        let route = ExploreNotificationsTestFixtures.replyRoute()
        let viewModel = ExploreNotificationReplyThreadViewModel(
            dependencies: ExploreNotificationsTestFixtures.replyDependencies(
                loadComments: { _, _, _, _ in
                    throw ExploreNotificationsTestFixtures.StubError.failed
                },
                errorMessage: { _ in "Reply failed" }
            )
        )

        await viewModel.load(route: route)

        XCTAssertEqual(viewModel.errorMessage, "Reply failed")
        XCTAssertTrue(viewModel.replies.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }
}
