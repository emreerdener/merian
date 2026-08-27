import Foundation
import XCTest

@testable import Merian

@MainActor
final class ExploreReplyLoadingStateTests: XCTestCase {
    func testLoadRepliesMarksLoadedAndClearsLoadingState() async {
        let parentComment = makeParentComment()
        let reply = ExploreFeedTestFixtures.comment(
            id: "reply-123",
            postId: parentComment.postId,
            parentCommentId: parentComment.id
        )
        let viewModel = makeViewModel(loadReplies: { _, _, _, _ in [reply] })

        await viewModel.loadReplies(for: parentComment)

        XCTAssertFalse(viewModel.loadingReplyCommentIds.contains(parentComment.id))
        XCTAssertTrue(viewModel.hasLoadedRepliesByCommentId.contains(parentComment.id))
        XCTAssertFalse(viewModel.failedReplyCommentIds.contains(parentComment.id))
        XCTAssertEqual(viewModel.repliesByCommentId[parentComment.id]?.first?.id, "reply-123")

        let replyState = viewModel.replyThreadRenderState(for: parentComment.id)
        XCTAssertFalse(replyState.isLoading)
        XCTAssertTrue(replyState.hasLoadedReplies)
        XCTAssertEqual(replyState.replies.first?.id, "reply-123")
    }

    func testCancelledLoadRepliesClearsLoadingWithoutFailureOrLoadedState() async {
        let parentComment = makeParentComment()
        let viewModel = makeViewModel(loadReplies: { _, _, _, _ in
            throw URLError(.cancelled)
        })

        await viewModel.loadReplies(for: parentComment)

        XCTAssertFalse(viewModel.loadingReplyCommentIds.contains(parentComment.id))
        XCTAssertFalse(viewModel.hasLoadedRepliesByCommentId.contains(parentComment.id))
        XCTAssertFalse(viewModel.failedReplyCommentIds.contains(parentComment.id))

        let replyState = viewModel.replyThreadRenderState(for: parentComment.id)
        XCTAssertFalse(replyState.isLoading)
        XCTAssertFalse(replyState.hasLoadedReplies)
        XCTAssertFalse(replyState.didFail)
    }

    func testFailedLoadRepliesClearsLoadingAndSetsRetryState() async {
        let parentComment = makeParentComment()
        let viewModel = makeViewModel(loadReplies: { _, _, _, _ in
            throw ExploreFeedTestFixtures.StubError.failed
        })

        await viewModel.loadReplies(for: parentComment)

        XCTAssertFalse(viewModel.loadingReplyCommentIds.contains(parentComment.id))
        XCTAssertFalse(viewModel.hasLoadedRepliesByCommentId.contains(parentComment.id))
        XCTAssertTrue(viewModel.failedReplyCommentIds.contains(parentComment.id))

        let replyState = viewModel.replyThreadRenderState(for: parentComment.id)
        XCTAssertFalse(replyState.isLoading)
        XCTAssertFalse(replyState.hasLoadedReplies)
        XCTAssertTrue(replyState.didFail)
    }

    func testReplyPaginationUsesCursorDeduplicatesAndMarksEnd() async {
        let parentComment = makeParentComment()
        let firstPage = (0..<25).map { index in
            ExploreFeedTestFixtures.comment(
                id: "reply-\(index)",
                postId: parentComment.postId,
                parentCommentId: parentComment.id,
                createdAt: String(format: "2026-08-01T12:%02d:00Z", index)
            )
        }
        let finalReply = ExploreFeedTestFixtures.comment(
            id: "reply-final",
            postId: parentComment.postId,
            parentCommentId: parentComment.id,
            createdAt: "2026-08-01T13:00:00Z"
        )
        var requests: [(createdAt: String?, commentId: String?)] = []
        let viewModel = makeViewModel(loadReplies: { _, _, createdAt, commentId in
            requests.append((createdAt, commentId))
            return requests.count == 1 ? firstPage : [firstPage.last!, finalReply]
        })

        await viewModel.loadReplies(for: parentComment)
        await viewModel.loadMoreRepliesIfNeeded(
            parentComment: parentComment,
            currentReply: firstPage.last!
        )

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].createdAt, firstPage.last?.createdAt)
        XCTAssertEqual(requests[1].commentId, firstPage.last?.id)
        XCTAssertEqual(viewModel.repliesByCommentId[parentComment.id]?.count, 26)
        XCTAssertEqual(viewModel.repliesByCommentId[parentComment.id]?.last?.id, "reply-final")
        XCTAssertTrue(viewModel.hasReachedEndOfRepliesByCommentId.contains(parentComment.id))
        XCTAssertFalse(viewModel.loadingMoreReplyCommentIds.contains(parentComment.id))
    }

    private func makeParentComment() -> ExploreComment {
        ExploreFeedTestFixtures.comment(
            id: "parent-comment-123",
            postId: "post-123",
            replyCount: 1
        )
    }

    private func makeViewModel(
        loadReplies: @escaping ExploreFeedTestFixtures.LoadReplies
    ) -> ExploreFeedViewModel {
        ExploreFeedViewModel(
            appSettings: ExploreFeedTestFixtures.appSettings(),
            dependencies: ExploreFeedTestFixtures.dependencies(loadReplies: loadReplies)
        )
    }
}
