import XCTest

@testable import Merian

@MainActor
final class ExploreFeedViewModelTests: XCTestCase {
    func testInitialLoadPublishesPageAndForwardsRequestState() async {
        let expectedPost = ExploreFeedTestFixtures.post(id: "first")
        var receivedLimit: Int?
        var receivedFilter: ExploreFeedFilter?
        var receivedCursor: ExploreFeedCursor?

        let viewModel = makeViewModel(loadPosts: { limit, filter, _, _, cursor, _, _ in
            receivedLimit = limit
            receivedFilter = filter
            receivedCursor = cursor
            return [expectedPost]
        })

        await viewModel.loadInitialFeed()

        XCTAssertEqual(viewModel.posts, [expectedPost])
        XCTAssertEqual(receivedLimit, viewModel.feedPageSize)
        XCTAssertEqual(receivedFilter, .recent)
        XCTAssertEqual(receivedCursor, .empty)
        XCTAssertTrue(viewModel.hasLoadedFeedOnce)
        XCTAssertTrue(viewModel.hasReachedEndOfFeed)
        XCTAssertFalse(viewModel.isLoadingInitialFeed)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRefreshSupersedesPaginationAndDiscardsStalePage() async {
        let initialPosts = (0..<20).map {
            ExploreFeedTestFixtures.post(
                id: "initial-\($0)",
                sharedAt: String(format: "2026-08-01T12:%02d:00Z", $0)
            )
        }
        let stalePost = ExploreFeedTestFixtures.post(id: "stale")
        let refreshedPost = ExploreFeedTestFixtures.post(id: "refreshed")
        let paginationStarted = expectation(description: "Pagination started")
        var pendingPagination: CheckedContinuation<[ExplorePost], any Error>?
        var receivedCursors: [ExploreFeedCursor?] = []

        let viewModel = makeViewModel(loadPosts: { _, _, _, _, cursor, _, _ in
            receivedCursors.append(cursor)
            switch receivedCursors.count {
            case 1:
                return initialPosts
            case 2:
                return try await withCheckedThrowingContinuation { continuation in
                    pendingPagination = continuation
                    paginationStarted.fulfill()
                }
            case 3:
                return [refreshedPost]
            default:
                throw ExploreFeedTestFixtures.StubError.unexpected
            }
        })

        await viewModel.loadInitialFeed()
        let paginationTask = Task {
            await viewModel.loadMoreIfNeeded(currentPost: initialPosts.last!)
        }
        await fulfillment(of: [paginationStarted], timeout: 1)

        await viewModel.refreshFeed()

        XCTAssertEqual(viewModel.posts, [refreshedPost])
        XCTAssertFalse(viewModel.isLoadingMore)

        pendingPagination?.resume(returning: [stalePost])
        _ = await paginationTask.value

        XCTAssertEqual(receivedCursors.count, 3)
        XCTAssertEqual(receivedCursors[1]?.beforePostId, initialPosts.last?.id)
        XCTAssertEqual(receivedCursors[2], .empty)
        XCTAssertEqual(viewModel.posts, [refreshedPost])
        XCTAssertFalse(viewModel.posts.contains(stalePost))
        XCTAssertFalse(viewModel.isLoadingInitialFeed)
        XCTAssertFalse(viewModel.isLoadingMore)
    }

    func testRefreshFailureKeepsLoadedPostsAndUsesTransientFeedback() async {
        let initialPosts = (0..<20).map {
            ExploreFeedTestFixtures.post(id: "post-\($0)")
        }
        var callCount = 0
        let viewModel = makeViewModel(loadPosts: { _, _, _, _, _, _, _ in
            callCount += 1
            if callCount == 1 { return initialPosts }
            throw ExploreFeedTestFixtures.StubError.failed
        })

        await viewModel.loadInitialFeed()
        await viewModel.refreshFeed()

        XCTAssertEqual(viewModel.posts, initialPosts)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.toastMessage?.title, "Stub error")
        XCTAssertEqual(viewModel.toastMessage?.severity, .error)
        XCTAssertFalse(viewModel.isLoadingInitialFeed)
    }

    func testLikeFailureRollsBackOptimisticStateAndEmitsErrorFeedback() async {
        let post = ExploreFeedTestFixtures.post(
            id: "liked-post",
            likeCount: 4,
            viewerHasLiked: false
        )
        var requestedLikeState: Bool?
        var errorFeedbackCount = 0
        let viewModel = makeViewModel(
            setLike: { _, liked in
                requestedLikeState = liked
                throw ExploreFeedTestFixtures.StubError.failed
            },
            errorFeedback: { errorFeedbackCount += 1 }
        )
        viewModel.upsertPost(post, includeInFeed: true)

        await viewModel.toggleLike(for: post)

        XCTAssertEqual(requestedLikeState, true)
        XCTAssertEqual(viewModel.post(id: post.id)?.viewerHasLiked, false)
        XCTAssertEqual(viewModel.post(id: post.id)?.likeCount, 4)
        XCTAssertEqual(errorFeedbackCount, 1)
        XCTAssertEqual(viewModel.toastMessage?.title, "Stub error")
    }

    func testFailedCommentSubmissionTrimsRequestAndRestoresOriginalDraft() async {
        let post = ExploreFeedTestFixtures.post(id: "commented-post")
        let originalDraft = "  \n" + String(repeating: "a", count: 510) + "  "
        var submittedBody: String?
        var errorFeedbackCount = 0
        let viewModel = makeViewModel(
            createComment: { _, body, _ in
                submittedBody = body
                throw ExploreFeedTestFixtures.StubError.failed
            },
            errorFeedback: { errorFeedbackCount += 1 }
        )
        viewModel.upsertPost(post, includeInFeed: true)
        _ = viewModel.beginCommentsSession(for: post)
        viewModel.commentDraft = originalDraft

        await viewModel.submitComment()

        XCTAssertEqual(submittedBody?.count, 500)
        XCTAssertEqual(submittedBody, String(repeating: "a", count: 500))
        XCTAssertEqual(viewModel.commentDraft, originalDraft)
        XCTAssertEqual(viewModel.commentErrorMessage, "Stub error")
        XCTAssertEqual(errorFeedbackCount, 1)
        XCTAssertFalse(viewModel.isSubmittingComment)
    }

    func testOverlappingCommentSubmissionsAreFencedToTheirSessions() async {
        let firstPost = ExploreFeedTestFixtures.post(id: "first-post", commentCount: 1)
        let secondPost = ExploreFeedTestFixtures.post(id: "second-post", commentCount: 2)
        let activePost = ExploreFeedTestFixtures.post(id: "active-post", commentCount: 3)
        let firstSubmissionStarted = expectation(description: "First submission started")
        let secondSubmissionStarted = expectation(description: "Second submission started")
        var firstSubmission: CheckedContinuation<ExploreCreateCommentResponse, any Error>?
        var secondSubmission: CheckedContinuation<ExploreCreateCommentResponse, any Error>?
        var successFeedbackCount = 0
        var errorFeedbackCount = 0

        let viewModel = makeViewModel(
            createComment: { postId, _, _ in
                switch postId {
                case firstPost.id:
                    return try await withCheckedThrowingContinuation { continuation in
                        firstSubmission = continuation
                        firstSubmissionStarted.fulfill()
                    }
                case secondPost.id:
                    return try await withCheckedThrowingContinuation { continuation in
                        secondSubmission = continuation
                        secondSubmissionStarted.fulfill()
                    }
                default:
                    throw ExploreFeedTestFixtures.StubError.unexpected
                }
            },
            successFeedback: { successFeedbackCount += 1 },
            errorFeedback: { errorFeedbackCount += 1 }
        )
        viewModel.upsertPost(firstPost, includeInFeed: true)
        viewModel.upsertPost(secondPost, includeInFeed: true)
        viewModel.upsertPost(activePost, includeInFeed: true)

        _ = viewModel.beginCommentsSession(for: firstPost)
        viewModel.commentDraft = "First draft"
        let firstTask = Task { await viewModel.submitComment() }
        await fulfillment(of: [firstSubmissionStarted], timeout: 1)

        _ = viewModel.beginCommentsSession(for: secondPost)
        viewModel.commentDraft = "Second draft"
        let secondTask = Task { await viewModel.submitComment() }
        await fulfillment(of: [secondSubmissionStarted], timeout: 1)

        _ = viewModel.beginCommentsSession(for: activePost)
        viewModel.commentDraft = "Active draft"

        firstSubmission?.resume(
            returning: ExploreCreateCommentResponse(
                success: true,
                comment: ExploreFeedTestFixtures.comment(
                    id: "stale-comment",
                    postId: firstPost.id
                ),
                commentCount: 4
            )
        )
        secondSubmission?.resume(throwing: ExploreFeedTestFixtures.StubError.failed)
        _ = await firstTask.value
        _ = await secondTask.value

        XCTAssertEqual(viewModel.activeCommentsPostId, activePost.id)
        XCTAssertTrue(viewModel.comments.isEmpty)
        XCTAssertEqual(viewModel.commentDraft, "Active draft")
        XCTAssertNil(viewModel.commentErrorMessage)
        XCTAssertFalse(viewModel.isSubmittingComment)
        XCTAssertEqual(viewModel.post(id: firstPost.id)?.commentCount, 1)
        XCTAssertEqual(viewModel.post(id: secondPost.id)?.commentCount, 2)
        XCTAssertEqual(successFeedbackCount, 0)
        XCTAssertEqual(errorFeedbackCount, 0)
    }

    private func makeViewModel(
        loadPosts: @escaping ExploreFeedTestFixtures.LoadPosts = { _, _, _, _, _, _, _ in [] },
        setLike: @escaping ExploreFeedTestFixtures.SetLike = { postId, liked in
            ExploreLikeResponse(
                success: true,
                postId: postId,
                viewerHasLiked: liked,
                likeCount: liked ? 1 : 0
            )
        },
        createComment: @escaping ExploreFeedTestFixtures.CreateComment = { _, _, _ in
            throw ExploreFeedTestFixtures.StubError.unexpected
        },
        successFeedback: @escaping @MainActor () -> Void = {},
        errorFeedback: @escaping @MainActor () -> Void = {}
    ) -> ExploreFeedViewModel {
        ExploreFeedViewModel(
            appSettings: ExploreFeedTestFixtures.appSettings(),
            dependencies: ExploreFeedTestFixtures.dependencies(
                loadPosts: loadPosts,
                setLike: setLike,
                createComment: createComment,
                successFeedback: successFeedback,
                errorFeedback: errorFeedback
            )
        )
    }
}
