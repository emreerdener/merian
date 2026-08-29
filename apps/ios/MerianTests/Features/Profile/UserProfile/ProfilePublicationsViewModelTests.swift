import Combine
import SwiftData
import UIKit
import XCTest

@testable import Merian

@MainActor
final class ProfilePublicationsViewModelTests: XCTestCase {
    private enum StubError: Error {
        case failed
        case unexpected
    }

    func testPreviewLoadNormalizesOwnerAndPublishesFirstPage() async {
        let first = ExploreAuthorProfileTestFixtures.post(id: "first")
        let second = ExploreAuthorProfileTestFixtures.post(id: "second")
        var receivedOwnerID: String?
        var receivedLimit: Int?
        var receivedCursor: ExploreAuthorPostCursor?
        let viewModel = ProfilePublicScansPreviewViewModel(
            previewLimit: 2,
            dependencies: makeDependencies { ownerID, limit, cursor in
                receivedOwnerID = ownerID
                receivedLimit = limit
                receivedCursor = cursor
                return ExploreAuthorPostsResponse(
                    data: [first, second],
                    nextCursor: nil
                )
            }
        )

        let loaded = await viewModel.load(authorUserID: "  AUTHOR-1  ")

        XCTAssertEqual(receivedOwnerID, "author-1")
        XCTAssertEqual(receivedLimit, 2)
        XCTAssertNil(receivedCursor)
        XCTAssertEqual(loaded.map(\.id), ["first", "second"])
        XCTAssertEqual(viewModel.posts.map(\.id), ["first", "second"])
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.didFail)
    }

    func testLatePreviewLoadCannotOverwriteNewOwner() async {
        let stalePost = ExploreAuthorProfileTestFixtures.post(id: "stale")
        let currentPost = ExploreAuthorProfileTestFixtures.post(id: "current")
        var pendingFirstLoad:
            CheckedContinuation<ExploreAuthorPostsResponse, any Error>?
        let viewModel = ProfilePublicScansPreviewViewModel(
            dependencies: makeDependencies { ownerID, _, _ in
                if ownerID == "author-1" {
                    return try await withCheckedThrowingContinuation {
                        pendingFirstLoad = $0
                    }
                }
                return ExploreAuthorPostsResponse(
                    data: [currentPost],
                    nextCursor: nil
                )
            }
        )

        let staleTask = Task {
            await viewModel.load(authorUserID: "author-1")
        }
        while pendingFirstLoad == nil {
            await Task.yield()
        }

        _ = await viewModel.load(authorUserID: "author-2")
        pendingFirstLoad?.resume(
            returning: ExploreAuthorPostsResponse(
                data: [stalePost],
                nextCursor: nil
            )
        )
        _ = await staleTask.value

        XCTAssertEqual(viewModel.posts.map(\.id), ["current"])
        XCTAssertFalse(viewModel.didFail)
    }

    func testPreviewFailureIsIndependentFromSignedOutReset() async {
        let viewModel = ProfilePublicScansPreviewViewModel(
            dependencies: makeDependencies { _, _, _ in
                throw StubError.failed
            }
        )

        _ = await viewModel.load(authorUserID: "author-1")
        XCTAssertTrue(viewModel.didFail)
        XCTAssertTrue(viewModel.hasLoaded)

        _ = await viewModel.load(authorUserID: nil)
        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertFalse(viewModel.didFail)
        XCTAssertFalse(viewModel.hasLoaded)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLibraryPaginationUsesCursorAndDeduplicatesPages() async {
        let first = ExploreAuthorProfileTestFixtures.post(id: "first")
        let second = ExploreAuthorProfileTestFixtures.post(id: "second")
        let third = ExploreAuthorProfileTestFixtures.post(id: "third")
        let nextCursor = ExploreAuthorPostCursor(
            beforeSharedAt: "2026-08-01T12:00:00Z",
            beforePostId: "second"
        )
        var receivedCursors: [ExploreAuthorPostCursor?] = []
        let viewModel = ProfilePublishedScansViewModel(
            pageSize: 2,
            dependencies: makeDependencies { _, _, cursor in
                receivedCursors.append(cursor)
                if cursor == nil {
                    return ExploreAuthorPostsResponse(
                        data: [first, second],
                        nextCursor: nextCursor
                    )
                }
                return ExploreAuthorPostsResponse(
                    data: [second, third],
                    nextCursor: nil
                )
            }
        )

        _ = await viewModel.reload(authorUserID: "author-1")
        _ = await viewModel.loadMore(authorUserID: "author-1")

        XCTAssertEqual(receivedCursors, [nil, nextCursor])
        XCTAssertEqual(viewModel.posts.map(\.id), ["first", "second", "third"])
        XCTAssertTrue(viewModel.hasReachedEnd)
        XCTAssertFalse(viewModel.didFail)
    }

    func testLibraryRefreshSupersedesPaginationAndDiscardsStalePage() async {
        let initial = ExploreAuthorProfileTestFixtures.post(id: "initial")
        let stale = ExploreAuthorProfileTestFixtures.post(id: "stale")
        let refreshed = ExploreAuthorProfileTestFixtures.post(id: "refreshed")
        let nextCursor = ExploreAuthorPostCursor(
            beforeSharedAt: "2026-08-01T12:00:00Z",
            beforePostId: "initial"
        )
        var callCount = 0
        var pendingPagination:
            CheckedContinuation<ExploreAuthorPostsResponse, any Error>?
        let viewModel = ProfilePublishedScansViewModel(
            dependencies: makeDependencies { _, _, _ in
                callCount += 1
                switch callCount {
                case 1:
                    return ExploreAuthorPostsResponse(
                        data: [initial],
                        nextCursor: nextCursor
                    )
                case 2:
                    return try await withCheckedThrowingContinuation {
                        pendingPagination = $0
                    }
                case 3:
                    return ExploreAuthorPostsResponse(
                        data: [refreshed],
                        nextCursor: nil
                    )
                default:
                    throw StubError.unexpected
                }
            }
        )

        _ = await viewModel.reload(authorUserID: "author-1")
        let paginationTask = Task {
            await viewModel.loadMore(authorUserID: "author-1")
        }
        while pendingPagination == nil {
            await Task.yield()
        }

        _ = await viewModel.reload(authorUserID: "author-1")
        pendingPagination?.resume(
            returning: ExploreAuthorPostsResponse(
                data: [stale],
                nextCursor: nil
            )
        )
        _ = await paginationTask.value

        XCTAssertEqual(callCount, 3)
        XCTAssertEqual(viewModel.posts.map(\.id), ["refreshed"])
        XCTAssertTrue(viewModel.hasReachedEnd)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testCanceledPaginationClearsLoadingAndAllowsRetry() async {
        let initial = ExploreAuthorProfileTestFixtures.post(id: "initial")
        let retried = ExploreAuthorProfileTestFixtures.post(id: "retried")
        let nextCursor = ExploreAuthorPostCursor(
            beforeSharedAt: "2026-08-01T12:00:00Z",
            beforePostId: "initial"
        )
        var callCount = 0
        let viewModel = ProfilePublishedScansViewModel(
            dependencies: makeDependencies { _, _, _ in
                callCount += 1
                switch callCount {
                case 1:
                    return ExploreAuthorPostsResponse(
                        data: [initial],
                        nextCursor: nextCursor
                    )
                case 2:
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                    throw StubError.unexpected
                case 3:
                    return ExploreAuthorPostsResponse(
                        data: [retried],
                        nextCursor: nil
                    )
                default:
                    throw StubError.unexpected
                }
            }
        )

        _ = await viewModel.reload(authorUserID: "author-1")
        let paginationTask = Task {
            await viewModel.loadMore(authorUserID: "author-1")
        }
        while callCount < 2 {
            await Task.yield()
        }
        paginationTask.cancel()
        _ = await paginationTask.value

        XCTAssertFalse(viewModel.isLoading)

        _ = await viewModel.loadMore(authorUserID: "author-1")

        XCTAssertEqual(callCount, 3)
        XCTAssertEqual(viewModel.posts.map(\.id), ["initial", "retried"])
        XCTAssertTrue(viewModel.hasReachedEnd)
    }

    private func makeDependencies(
        loadPosts: @escaping @MainActor (
            String,
            Int,
            ExploreAuthorPostCursor?
        ) async throws -> ExploreAuthorPostsResponse
    ) -> ProfilePublicationsDependencies {
        ProfilePublicationsDependencies(
            loadPosts: loadPosts,
            loadPost: { _ in throw StubError.unexpected },
            appEvents: Empty<AppEvent, Never>(
                completeImmediately: false
            ).eraseToAnyPublisher(),
            reviewRecovery: { _ in },
            selectionFeedback: {},
            resolveScanRoute: { _, _ in nil }
        )
    }
}
