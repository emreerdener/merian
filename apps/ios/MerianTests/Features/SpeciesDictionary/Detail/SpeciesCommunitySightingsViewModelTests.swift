import XCTest

@testable import Merian

@MainActor
final class SpeciesCommunitySightingsViewModelTests: XCTestCase {
    private enum StubError: Error {
        case failed
    }

    func testInitialLoadPaginationAndDeduplication() async {
        let cursor = ExploreSpeciesPostCursor(
            imageQualityScore: 88,
            sharedAt: "2026-07-14T12:00:00.000Z",
            postId: "post-2"
        )
        let responses = [
            Self.response(postIDs: ["post-1", "post-2"], cursor: cursor),
            Self.response(postIDs: ["post-2", "post-3"])
        ]
        var requestedCursors: [ExploreSpeciesPostCursor?] = []
        let viewModel = SpeciesCommunitySightingsViewModel { speciesId, limit, cursor in
            XCTAssertEqual(speciesId, "species-123")
            XCTAssertEqual(limit, cursor == nil ? 6 : 30)
            requestedCursors.append(cursor)
            return responses[requestedCursors.count - 1]
        }

        await viewModel.loadInitial(speciesId: " species-123 ")
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.posts.map(\.id), [
            "post-1",
            "post-2",
            "post-3"
        ])
        XCTAssertFalse(viewModel.hasMore)
        XCTAssertFalse(viewModel.didFail)
        XCTAssertEqual(requestedCursors, [nil, cursor])
    }

    func testFailedInitialLoadPublishesHiddenFailureState() async {
        let viewModel = SpeciesCommunitySightingsViewModel { _, _, _ in
            throw StubError.failed
        }

        await viewModel.loadInitial(speciesId: "species-123")

        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertFalse(viewModel.hasMore)
        XCTAssertTrue(viewModel.didFail)
        XCTAssertFalse(viewModel.isLoadingInitial)
    }

    func testRefreshInvalidatesActivePaginationAndRejectsItsLatePage() async {
        let initialCursor = ExploreSpeciesPostCursor(
            imageQualityScore: 75,
            sharedAt: "2026-07-14T12:00:00.000Z",
            postId: "initial"
        )
        let paginationStarted = expectation(
            description: "Community pagination started"
        )
        var initialLoadCount = 0
        var pendingPagination: CheckedContinuation<
            ExploreSpeciesPostsResponse,
            any Error
        >?
        let viewModel = SpeciesCommunitySightingsViewModel { _, _, cursor in
            if cursor != nil {
                return try await withCheckedThrowingContinuation {
                    pendingPagination = $0
                    paginationStarted.fulfill()
                }
            }

            initialLoadCount += 1
            if initialLoadCount == 1 {
                return Self.response(
                    postIDs: ["initial"],
                    cursor: initialCursor
                )
            }
            return Self.response(postIDs: ["fresh"])
        }

        await viewModel.loadInitial(speciesId: "species-123")
        let paginationTask = Task { await viewModel.loadMore() }
        await fulfillment(of: [paginationStarted], timeout: 1)

        await viewModel.refresh()
        pendingPagination?.resume(
            returning: Self.response(postIDs: ["stale-page"])
        )
        _ = await paginationTask.value

        XCTAssertEqual(viewModel.posts.map(\.id), ["fresh"])
        XCTAssertFalse(viewModel.hasMore)
        XCTAssertFalse(viewModel.isLoadingInitial)
        XCTAssertFalse(viewModel.isLoadingMore)
        XCTAssertFalse(viewModel.didFail)
    }

    func testSpeciesChangeRejectsLateInitialResponse() async {
        let firstLoadStarted = expectation(
            description: "First species sightings load started"
        )
        var pendingFirstLoad: CheckedContinuation<
            ExploreSpeciesPostsResponse,
            any Error
        >?
        let viewModel = SpeciesCommunitySightingsViewModel { speciesId, _, _ in
            if speciesId == "species-1" {
                return try await withCheckedThrowingContinuation {
                    pendingFirstLoad = $0
                    firstLoadStarted.fulfill()
                }
            }
            return Self.response(postIDs: ["species-2-post"])
        }

        let firstTask = Task {
            await viewModel.loadInitial(speciesId: "species-1")
        }
        await fulfillment(of: [firstLoadStarted], timeout: 1)
        await viewModel.loadInitial(speciesId: "species-2")
        pendingFirstLoad?.resume(
            returning: Self.response(postIDs: ["species-1-post"])
        )
        _ = await firstTask.value

        XCTAssertEqual(viewModel.posts.map(\.id), ["species-2-post"])
        XCTAssertFalse(viewModel.isLoadingInitial)
    }

    private static func response(
        postIDs: [String],
        cursor: ExploreSpeciesPostCursor? = nil
    ) -> ExploreSpeciesPostsResponse {
        ExploreSpeciesPostsResponse(
            data: postIDs.map(post(id:)),
            nextCursor: cursor
        )
    }

    private static func post(id: String) -> ExplorePost {
        ExplorePost(
            postId: id,
            scanId: "scan-\(id)",
            heroImageUrl: "https://example.com/\(id).jpg",
            sharedAt: "2026-07-14T12:00:00.000Z",
            authorUserId: "author-123",
            authorName: "Sightings Author",
            authorUsername: "sightings",
            authorAvatarUrl: nil,
            authorIsPro: false,
            hashtags: nil,
            speciesCommonName: "Field Test",
            speciesScientificName: "Testus floridus",
            petIdentification: nil,
            publicLocationLabel: nil,
            locationSharing: .obscured,
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
}
