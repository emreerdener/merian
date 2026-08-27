import XCTest

@testable import Merian

@MainActor
final class ExploreHashtagPostsViewModelTests: XCTestCase {
    func testInitialLoadForwardsNormalizedRequestAndPublishesPage() async {
        let post = ExploreFeedTestFixtures.post(id: "hashtag-post")
        var receivedHashtag: String?
        var receivedLimit: Int?
        var receivedCursor: ExploreHashtagPostCursor?
        let viewModel = ExploreHashtagPostsViewModel(
            hashtag: "birding",
            pageSize: 2,
            dependencies: .init(
                loadPage: { hashtag, limit, cursor in
                    receivedHashtag = hashtag
                    receivedLimit = limit
                    receivedCursor = cursor
                    return [post]
                },
                errorMessage: { _ in "Stub error" }
            )
        )

        await viewModel.reload()

        XCTAssertEqual(receivedHashtag, "birding")
        XCTAssertEqual(receivedLimit, 2)
        XCTAssertNil(receivedCursor)
        XCTAssertEqual(viewModel.posts, [post])
        XCTAssertTrue(viewModel.hasReachedEnd)
        XCTAssertFalse(viewModel.isLoadingInitialPage)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testReloadSupersedesPaginationAndDiscardsStalePage() async {
        let initialPosts = [
            ExploreFeedTestFixtures.post(
                id: "initial-1",
                sharedAt: "2026-08-02T12:00:00Z"
            ),
            ExploreFeedTestFixtures.post(
                id: "initial-2",
                sharedAt: "2026-08-01T12:00:00Z"
            )
        ]
        let stalePost = ExploreFeedTestFixtures.post(id: "stale")
        let refreshedPost = ExploreFeedTestFixtures.post(id: "refreshed")
        let paginationStarted = expectation(description: "Hashtag pagination started")
        var pendingPagination: CheckedContinuation<[ExplorePost], any Error>?
        var receivedCursors: [ExploreHashtagPostCursor?] = []
        let viewModel = ExploreHashtagPostsViewModel(
            hashtag: "birding",
            pageSize: 2,
            dependencies: .init(
                loadPage: { _, _, cursor in
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
                },
                errorMessage: { _ in "Stub error" }
            )
        )

        await viewModel.reload()
        let paginationTask = Task {
            await viewModel.loadMoreIfNeeded()
        }
        await fulfillment(of: [paginationStarted], timeout: 1)

        await viewModel.reload()
        pendingPagination?.resume(returning: [stalePost])
        _ = await paginationTask.value

        XCTAssertEqual(receivedCursors.count, 3)
        XCTAssertEqual(receivedCursors[1]?.beforePostId, "initial-2")
        XCTAssertNil(receivedCursors[2])
        XCTAssertEqual(viewModel.posts, [refreshedPost])
        XCTAssertFalse(viewModel.posts.contains(stalePost))
        XCTAssertFalse(viewModel.isLoadingInitialPage)
        XCTAssertFalse(viewModel.isLoadingMore)
    }

    func testPaginationFailureLeavesInitialContentAndReturnsTransientMessage() async {
        let initialPosts = [
            ExploreFeedTestFixtures.post(id: "first"),
            ExploreFeedTestFixtures.post(id: "second")
        ]
        var callCount = 0
        let viewModel = ExploreHashtagPostsViewModel(
            hashtag: "birding",
            pageSize: 2,
            dependencies: .init(
                loadPage: { _, _, _ in
                    callCount += 1
                    if callCount == 1 { return initialPosts }
                    throw ExploreFeedTestFixtures.StubError.failed
                },
                errorMessage: { _ in "Hashtag failed" }
            )
        )

        await viewModel.reload()
        let message = await viewModel.loadMoreIfNeeded()

        XCTAssertEqual(message, "Hashtag failed")
        XCTAssertEqual(viewModel.posts, initialPosts)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoadingMore)
    }
}
