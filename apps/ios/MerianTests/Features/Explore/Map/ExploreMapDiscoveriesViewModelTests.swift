import MapKit
import XCTest

@testable import Merian

@MainActor
final class ExploreMapDiscoveriesViewModelTests: XCTestCase {
    func testClusterSheetLoads120RowsForSnapshotWithoutChangingMap() async throws {
        var capturedRequest: ExploreMapPointsRequest?
        let rows = (0..<120).map { makePost(id: "post-\($0)") }
        let map = clusteredMap { request in
            capturedRequest = request
            return ExploreMapPointsResponse(mode: .posts, visibleCount: 120, posts: rows)
        }
        map.selectedSpeciesCategories = [.birds]
        map.selectedMediaTypes = [.image]
        map.appliedSpeciesCategories = [.birds]
        map.appliedMediaTypes = [.image]
        let snapshotRegion = try XCTUnwrap(map.lastCommittedRegion)
        let list = ExploreMapDiscoveriesViewModel(mapViewModel: map)
        XCTAssertEqual(list.totalCount, 120)
        XCTAssertTrue(list.posts.isEmpty)

        // The sheet must retain the tapped area and filters even if the map changes later.
        map.visibleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 2, longitude: 2),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        map.selectedSpeciesCategories = [.plants]
        await list.load()

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.region.center.latitude, snapshotRegion.center.latitude)
        XCTAssertEqual(request.region.span.longitudeDelta, snapshotRegion.span.longitudeDelta)
        XCTAssertEqual(request.speciesCategories, [.birds])
        XCTAssertEqual(request.mediaTypes, [.image])
        XCTAssertEqual(request.zoomLevel, 20)
        XCTAssertEqual(request.limit, 500)
        XCTAssertEqual(list.posts.count, 120)
        XCTAssertEqual(list.totalCount, 120)
        XCTAssertFalse(list.showsResultLimit)
        XCTAssertNil(list.errorMessage)
        XCTAssertFalse(list.isLoading)
        XCTAssertEqual(map.mode, .clusters)
        XCTAssertEqual(map.clusters.count, 1)
        XCTAssertTrue(map.posts.isEmpty)
        XCTAssertEqual(map.cameraPosition.region?.span.longitudeDelta, snapshotRegion.span.longitudeDelta)
        XCTAssertNil(map.responseCache.cachedResponse(
            for: snapshotRegion, speciesCategories: [.birds], mediaTypes: [.image], now: Date()
        ))
    }

    func testPointModeUsesExistingRowsAndMatchesPillAfterRemoval() async {
        let map = clusteredMap { _ in
            XCTFail("Already loaded individual posts should not require a request")
            return ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
        }
        map.mode = .posts
        map.visibleCount = 3
        map.posts = (0..<3).map { makePost(id: "post-\($0)") }
        map.removePost(id: "post-0")
        let list = ExploreMapDiscoveriesViewModel(mapViewModel: map)
        await list.load()
        XCTAssertEqual(list.posts.count, 2)
        XCTAssertEqual(list.totalCount, map.visibleDiscoveryCount)
        XCTAssertFalse(list.showsResultLimit)
    }

    func testClusterResponseLimitKeepsTotalAndShowsAvailableRows() async {
        let rows = (0..<160).map { makePost(id: "post-\($0)") }
        let map = clusteredMap { _ in
            ExploreMapPointsResponse(mode: .posts, visibleCount: 500, posts: rows)
        }
        let list = ExploreMapDiscoveriesViewModel(mapViewModel: map)
        await list.load()
        XCTAssertEqual(list.posts.count, 160)
        XCTAssertEqual(list.totalCount, 500)
        XCTAssertTrue(list.showsResultLimit)
    }

    func testFailureRetainsCountAndRetryCanLoadEmptyResult() async {
        var calls = 0
        let map = clusteredMap { _ in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
        }
        let list = ExploreMapDiscoveriesViewModel(mapViewModel: map)
        await list.load()
        XCTAssertNotNil(list.errorMessage)
        XCTAssertEqual(list.totalCount, 120)
        XCTAssertFalse(list.isLoading)
        await list.load()
        XCTAssertNil(list.errorMessage)
        XCTAssertEqual(list.totalCount, 0)
        XCTAssertTrue(list.posts.isEmpty)
        XCTAssertFalse(list.showsResultLimit)
    }

    func testUnexpectedClusterOrMissingRowsShowsErrorInsteadOfFalseEmptyState() async {
        for response in [
            ExploreMapPointsResponse(mode: .clusters, visibleCount: 120),
            ExploreMapPointsResponse(mode: .posts, visibleCount: 120)
        ] {
            let map = clusteredMap { _ in response }
            let list = ExploreMapDiscoveriesViewModel(mapViewModel: map)
            await list.load()
            XCTAssertNotNil(list.errorMessage)
            XCTAssertEqual(list.totalCount, 120)
        }
    }

    func testDismissedLoadCannotReplaceNewLoadOrClearItsState() async {
        var continuations: [CheckedContinuation<ExploreMapPointsResponse, Never>] = []
        let map = clusteredMap { _ in
            await withCheckedContinuation { continuations.append($0) }
        }
        let list = ExploreMapDiscoveriesViewModel(mapViewModel: map)
        let first = Task { await list.load() }
        while continuations.count < 1 { await Task.yield() }
        list.cancelLoading()
        let second = Task { await list.load() }
        while continuations.count < 2 { await Task.yield() }
        continuations[0].resume(returning: ExploreMapPointsResponse(mode: .posts, visibleCount: 0))
        await first.value
        XCTAssertTrue(list.isLoading)
        XCTAssertEqual(list.totalCount, 120)
        continuations[1].resume(returning: ExploreMapPointsResponse(
            mode: .posts, visibleCount: 1, posts: [makePost(id: "current")]
        ))
        await second.value
        XCTAssertEqual(list.posts.map(\.id), ["current"])
        XCTAssertFalse(list.isLoading)
    }

    func testCancelledTaskDoesNotPublishAndCanBeRetried() async {
        var completion: CheckedContinuation<ExploreMapPointsResponse, Never>?
        let map = clusteredMap { _ in
            await withCheckedContinuation { completion = $0 }
        }
        let list = ExploreMapDiscoveriesViewModel(mapViewModel: map)
        let task = Task { await list.load() }
        while completion == nil { await Task.yield() }
        task.cancel()
        completion?.resume(returning: ExploreMapPointsResponse(mode: .posts, visibleCount: 0))
        await task.value
        XCTAssertEqual(list.totalCount, 120)
        XCTAssertNil(list.errorMessage)
        XCTAssertFalse(list.isLoading)

        completion = nil
        let retry = Task { await list.load() }
        while completion == nil { await Task.yield() }
        completion?.resume(returning: ExploreMapPointsResponse(
            mode: .posts, visibleCount: 1, posts: [makePost(id: "retried")]
        ))
        await retry.value
        XCTAssertEqual(list.posts.map(\.id), ["retried"])
        XCTAssertEqual(list.totalCount, 1)
    }

    func testRemovalAndPrivacyChangesDoNotLeaveStaleCards() async {
        let rows = [makePost(id: "first"), makePost(id: "second"), makePost(id: "third")]
        let map = clusteredMap { _ in
            ExploreMapPointsResponse(mode: .posts, visibleCount: 3, posts: rows)
        }
        let list = ExploreMapDiscoveriesViewModel(mapViewModel: map)
        list.removePost(id: "first")
        await list.load()
        XCTAssertEqual(list.posts.map(\.id), ["second", "third"])
        XCTAssertEqual(list.totalCount, 2)
        list.removePosts(byAuthorUserId: "author-second")
        let privatePost = makePost(id: "third", locationSharing: .privateLocation).asExplorePost
        list.syncVisibility(from: [privatePost])
        XCTAssertTrue(list.posts.isEmpty)
        XCTAssertEqual(list.totalCount, 0)
    }

    private func clusteredMap(
        loader: @escaping ExploreMapViewModel.MapPointsLoader
    ) -> ExploreMapViewModel {
        let map = ExploreMapViewModel(mapPointsLoader: loader)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 80)
        )
        map.lastCommittedRegion = region
        map.visibleRegion = region
        map.cameraPosition = .region(region)
        map.mode = .clusters
        map.visibleCount = 120
        map.clusters = [ExploreMapCluster(id: "cluster", latitude: 1, longitude: 1, postCount: 120)]
        return map
    }

    private func makePost(id: String, locationSharing: ExplorePostLocationSharing = .open) -> ExploreMapPost {
        ExploreMapPost(
            postId: id, scanId: "scan-\(id)", latitude: 1, longitude: 1,
            coordinateVisibility: .exact, heroImageUrl: "https://example.com/image.jpg",
            sharedAt: "2026-01-01T00:00:00Z", authorUserId: "author-\(id)", authorName: "Fixture",
            authorUsername: nil, authorAvatarUrl: nil, authorIsPro: nil,
            speciesCommonName: "Fixture bird", speciesScientificName: "Fixture species",
            petIdentification: nil, taxonomyKingdom: "Animalia", taxonomyClass: "Aves",
            publicLocationLabel: nil, locationSharing: locationSharing, timeOfDay: nil,
            currentMonth: nil, weatherCondition: nil, weatherTemperatureF: nil,
            likeCount: 0, commentCount: 0, viewerHasLiked: false, isOwnedByViewer: false
        )
    }
}
