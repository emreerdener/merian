import XCTest

@testable import Merian

@MainActor
final class ExploreAuthorProfileViewModelTests: XCTestCase {
    private enum StubError: Error {
        case failed
        case unexpected
    }

    func testProfileLoadSeedsLibraryAndPrefetchesResolvedPreviewImages() async {
        let audio = ExploreMediaItem(
            kind: .audio,
            url: "https://example.com/audio.m4a",
            thumbnailUrl: nil,
            orderIndex: 0,
            durationSeconds: 4,
            hasAudio: true
        )
        let first = ExploreAuthorProfileTestFixtures.post(
            id: "first",
            sharedAt: "2026-08-02T12:00:00Z"
        )
        let second = ExploreAuthorProfileTestFixtures.post(
            id: "second",
            sharedAt: "2026-08-01T12:00:00Z",
            mediaItems: [audio]
        )
        let profile = ExploreAuthorProfileTestFixtures.profile(previewPosts: [first, second])
        var requestedAuthorUserId: String?
        var requestedPreviewLimit: Int?
        var prefetchedImageUrls: [String] = []

        let viewModel = ExploreAuthorProfileViewModel(dependencies: .init(
            loadProfile: { authorUserId, previewLimit in
                requestedAuthorUserId = authorUserId
                requestedPreviewLimit = previewLimit
                return profile
            },
            loadPosts: { _, _, _ in throw StubError.unexpected },
            setFollowing: { _, _ in throw StubError.unexpected },
            prefetchImages: { prefetchedImageUrls = $0 },
            successFeedback: {},
            errorFeedback: {},
            errorMessage: { _ in "stub error" }
        ))

        let loadedPosts = await viewModel.loadProfile(
            authorUserId: "author-1",
            localReferenceUrlsByScanId: ["scan-second": "file:///reference.jpg"]
        )

        XCTAssertEqual(requestedAuthorUserId, "author-1")
        XCTAssertEqual(requestedPreviewLimit, ExploreAuthorProfilePresentation.previewLimit)
        XCTAssertEqual(loadedPosts.map(\.id), ["first", "second"])
        XCTAssertEqual(viewModel.profile, profile)
        XCTAssertEqual(viewModel.libraryPosts.map(\.id), ["first", "second"])
        XCTAssertEqual(viewModel.libraryCursor.beforePostId, "second")
        XCTAssertEqual(prefetchedImageUrls, [
            "https://example.com/first.jpg",
            "file:///reference.jpg"
        ])
        XCTAssertFalse(viewModel.isLoadingProfile)
    }

    func testProfileFailureSurfacesErrorAndForceRetryRecovers() async {
        let recoveredProfile = ExploreAuthorProfileTestFixtures.profile()
        var loadCount = 0
        let viewModel = ExploreAuthorProfileViewModel(dependencies: .init(
            loadProfile: { _, _ in
                loadCount += 1
                if loadCount == 1 { throw StubError.failed }
                return recoveredProfile
            },
            loadPosts: { _, _, _ in throw StubError.unexpected },
            setFollowing: { _, _ in throw StubError.unexpected },
            prefetchImages: { _ in },
            successFeedback: {},
            errorFeedback: {},
            errorMessage: { _ in "Profile failed" }
        ))

        await viewModel.loadProfile(authorUserId: "author-1")
        guard case .error(let message) = viewModel.profileState else {
            return XCTFail("Expected profile error state")
        }
        XCTAssertEqual(message, "Profile failed")

        await viewModel.loadProfile(authorUserId: "author-1", force: true)
        XCTAssertEqual(viewModel.profile, recoveredProfile)
        XCTAssertEqual(loadCount, 2)
    }

    func testLateProfileLoadCannotOverwriteNewAuthor() async {
        let firstProfile = ExploreAuthorProfileTestFixtures.profile(authorUserId: "author-1")
        let secondProfile = ExploreAuthorProfileTestFixtures.profile(authorUserId: "author-2")
        var pendingFirstLoad: CheckedContinuation<ExploreAuthorProfile, any Error>?
        let viewModel = ExploreAuthorProfileViewModel(dependencies: .init(
            loadProfile: { authorUserId, _ in
                if authorUserId == "author-1" {
                    return try await withCheckedThrowingContinuation { continuation in
                        pendingFirstLoad = continuation
                    }
                }
                return secondProfile
            },
            loadPosts: { _, _, _ in throw StubError.unexpected },
            setFollowing: { _, _ in throw StubError.unexpected },
            prefetchImages: { _ in },
            successFeedback: {},
            errorFeedback: {},
            errorMessage: { _ in "stub error" }
        ))

        let firstLoad = Task {
            await viewModel.loadProfile(authorUserId: "author-1")
        }
        await Task.yield()
        XCTAssertNotNil(pendingFirstLoad)

        await viewModel.loadProfile(authorUserId: "author-2")
        pendingFirstLoad?.resume(returning: firstProfile)
        _ = await firstLoad.value

        XCTAssertEqual(viewModel.profile, secondProfile)
    }

    func testLibraryPaginationUsesServerCursorAndDeduplicatesPages() async {
        let first = ExploreAuthorProfileTestFixtures.post(id: "first")
        let second = ExploreAuthorProfileTestFixtures.post(id: "second")
        let third = ExploreAuthorProfileTestFixtures.post(id: "third")
        let profile = ExploreAuthorProfileTestFixtures.profile(previewPosts: [first])
        let nextCursor = ExploreAuthorPostCursor(
            beforeSharedAt: "2026-07-01T00:00:00Z",
            beforePostId: "second"
        )
        var receivedCursors: [ExploreAuthorPostCursor?] = []

        let viewModel = ExploreAuthorProfileViewModel(dependencies: .init(
            loadProfile: { _, _ in profile },
            loadPosts: { _, limit, cursor in
                XCTAssertEqual(limit, ExploreAuthorProfilePresentation.libraryPageSize)
                receivedCursors.append(cursor)
                if receivedCursors.count == 1 {
                    return ExploreAuthorPostsResponse(data: [first, second], nextCursor: nextCursor)
                }
                return ExploreAuthorPostsResponse(data: [third], nextCursor: nil)
            },
            setFollowing: { _, _ in throw StubError.unexpected },
            prefetchImages: { _ in },
            successFeedback: {},
            errorFeedback: {},
            errorMessage: { _ in "stub error" }
        ))

        await viewModel.loadProfile(authorUserId: "author-1")
        await viewModel.loadMoreLibraryPosts(authorUserId: "author-1")
        XCTAssertEqual(viewModel.libraryPosts.map(\.id), ["first", "second"])
        XCTAssertEqual(viewModel.libraryCursor, nextCursor)
        XCTAssertFalse(viewModel.hasReachedEndOfLibrary)

        await viewModel.loadMoreLibraryPosts(authorUserId: "author-1")
        XCTAssertEqual(viewModel.libraryPosts.map(\.id), ["first", "second", "third"])
        XCTAssertTrue(viewModel.hasReachedEndOfLibrary)
        XCTAssertEqual(receivedCursors[0]?.beforePostId, "first")
        XCTAssertEqual(receivedCursors[1]?.beforePostId, "second")
    }

    func testLibraryRefreshFailureRestoresPreviewAndExposesError() async {
        let preview = ExploreAuthorProfileTestFixtures.post(id: "preview")
        let profile = ExploreAuthorProfileTestFixtures.profile(previewPosts: [preview])
        var errorFeedbackCount = 0
        let viewModel = ExploreAuthorProfileViewModel(dependencies: .init(
            loadProfile: { _, _ in profile },
            loadPosts: { _, _, _ in throw StubError.failed },
            setFollowing: { _, _ in throw StubError.unexpected },
            prefetchImages: { _ in },
            successFeedback: {},
            errorFeedback: { errorFeedbackCount += 1 },
            errorMessage: { _ in "Library failed" }
        ))

        await viewModel.loadProfile(authorUserId: "author-1")
        await viewModel.reloadLibrary(
            authorUserId: "author-1",
            fallbackProfile: profile
        )

        XCTAssertEqual(viewModel.libraryPosts.map(\.id), ["preview"])
        XCTAssertEqual(viewModel.takeInteractionErrorMessage(), "Library failed")
        XCTAssertEqual(errorFeedbackCount, 1)
        XCTAssertFalse(viewModel.isLoadingLibrary)
    }

    func testLibraryRefreshSupersedesInFlightPaginationAndDiscardsStalePage() async {
        let preview = ExploreAuthorProfileTestFixtures.post(id: "preview")
        let stalePagePost = ExploreAuthorProfileTestFixtures.post(id: "stale-page")
        let refreshedPost = ExploreAuthorProfileTestFixtures.post(id: "refreshed")
        let profile = ExploreAuthorProfileTestFixtures.profile(previewPosts: [preview])
        let paginationStarted = expectation(description: "Pagination request started")
        let refreshStarted = expectation(description: "Refresh request started")
        var receivedCursors: [ExploreAuthorPostCursor?] = []
        var pendingPagination: CheckedContinuation<ExploreAuthorPostsResponse, any Error>?
        var pendingRefresh: CheckedContinuation<ExploreAuthorPostsResponse, any Error>?

        let viewModel = ExploreAuthorProfileViewModel(dependencies: .init(
            loadProfile: { _, _ in profile },
            loadPosts: { _, _, cursor in
                receivedCursors.append(cursor)
                if receivedCursors.count == 1 {
                    return try await withCheckedThrowingContinuation { continuation in
                        pendingPagination = continuation
                        paginationStarted.fulfill()
                    }
                }
                return try await withCheckedThrowingContinuation { continuation in
                    pendingRefresh = continuation
                    refreshStarted.fulfill()
                }
            },
            setFollowing: { _, _ in throw StubError.unexpected },
            prefetchImages: { _ in },
            successFeedback: {},
            errorFeedback: {},
            errorMessage: { _ in "stub error" }
        ))

        await viewModel.loadProfile(authorUserId: "author-1")
        let paginationTask = Task {
            await viewModel.loadMoreLibraryPosts(authorUserId: "author-1")
        }
        await fulfillment(of: [paginationStarted], timeout: 1)
        XCTAssertNotNil(pendingPagination)

        let refreshTask = Task {
            await viewModel.reloadLibrary(
                authorUserId: "author-1",
                fallbackProfile: profile
            )
        }
        await fulfillment(of: [refreshStarted], timeout: 1)
        XCTAssertNotNil(pendingRefresh)
        XCTAssertEqual(receivedCursors.count, 2)
        guard receivedCursors.count == 2 else {
            pendingPagination?.resume(returning: ExploreAuthorPostsResponse(
                data: [stalePagePost],
                nextCursor: nil
            ))
            pendingRefresh?.resume(returning: ExploreAuthorPostsResponse(
                data: [refreshedPost],
                nextCursor: nil
            ))
            _ = await paginationTask.value
            _ = await refreshTask.value
            return
        }
        XCTAssertEqual(receivedCursors[0]?.beforePostId, "preview")
        XCTAssertNil(receivedCursors[1])

        pendingPagination?.resume(returning: ExploreAuthorPostsResponse(
            data: [stalePagePost],
            nextCursor: nil
        ))
        _ = await paginationTask.value

        XCTAssertTrue(viewModel.isLoadingLibrary)
        XCTAssertTrue(viewModel.libraryPosts.isEmpty)

        pendingRefresh?.resume(returning: ExploreAuthorPostsResponse(
            data: [refreshedPost],
            nextCursor: nil
        ))
        let refreshedPosts = await refreshTask.value

        XCTAssertEqual(refreshedPosts.map(\.id), ["refreshed"])
        XCTAssertEqual(viewModel.libraryPosts.map(\.id), ["refreshed"])
        XCTAssertTrue(viewModel.hasReachedEndOfLibrary)
        XCTAssertFalse(viewModel.isLoadingLibrary)
    }

    func testFollowSuccessUsesServerAuthoritativeCounts() async {
        let profile = ExploreAuthorProfileTestFixtures.profile(
            followerCount: 4,
            followingCount: 7,
            viewerIsFollowing: false
        )
        var requestedFollowingState: Bool?
        var successFeedbackCount = 0
        let viewModel = ExploreAuthorProfileViewModel(dependencies: .init(
            loadProfile: { _, _ in profile },
            loadPosts: { _, _, _ in throw StubError.unexpected },
            setFollowing: { _, isFollowing in
                requestedFollowingState = isFollowing
                return ExploreFollowState(
                    success: true,
                    authorUserId: "author-1",
                    followerCount: 12,
                    followingCount: 8,
                    viewerIsFollowing: true
                )
            },
            prefetchImages: { _ in },
            successFeedback: { successFeedbackCount += 1 },
            errorFeedback: {},
            errorMessage: { _ in "stub error" }
        ))

        await viewModel.loadProfile(authorUserId: "author-1")
        await viewModel.toggleFollow(currentUserId: "viewer-1")

        XCTAssertEqual(requestedFollowingState, true)
        XCTAssertEqual(viewModel.profile?.followerCount, 12)
        XCTAssertEqual(viewModel.profile?.followingCount, 8)
        XCTAssertEqual(viewModel.profile?.viewerIsFollowing, true)
        XCTAssertEqual(successFeedbackCount, 1)
    }

    func testFollowFailureRollsBackOptimisticStateAndSurfacesError() async {
        let profile = ExploreAuthorProfileTestFixtures.profile(
            followerCount: 4,
            followingCount: 7,
            viewerIsFollowing: false
        )
        var errorFeedbackCount = 0
        let viewModel = ExploreAuthorProfileViewModel(dependencies: .init(
            loadProfile: { _, _ in profile },
            loadPosts: { _, _, _ in throw StubError.unexpected },
            setFollowing: { _, _ in throw StubError.failed },
            prefetchImages: { _ in },
            successFeedback: {},
            errorFeedback: { errorFeedbackCount += 1 },
            errorMessage: { _ in "Follow failed" }
        ))

        await viewModel.loadProfile(authorUserId: "author-1")
        await viewModel.toggleFollow(currentUserId: "viewer-1")

        XCTAssertEqual(viewModel.profile, profile)
        XCTAssertEqual(viewModel.takeInteractionErrorMessage(), "Follow failed")
        XCTAssertNil(viewModel.takeInteractionErrorMessage())
        XCTAssertEqual(errorFeedbackCount, 1)
        XCTAssertFalse(viewModel.isUpdatingFollow)
    }
}
