import Foundation
import MapKit
import XCTest

@testable import Merian

@MainActor
final class ExploreMapViewModelTests: XCTestCase {
    private func makeMapPost(
        id: String,
        latitude: Double,
        coordinateVisibility: ExploreCoordinateVisibility = .exact,
        mediaKinds: [ExploreMediaKind] = [.image]
    ) -> ExploreMapPost {
        ExploreMapPost(
            postId: id,
            scanId: "scan-\(id)",
            latitude: latitude,
            longitude: -97.743,
            coordinateVisibility: coordinateVisibility,
            heroImageUrl: "https://example.com/\(id).jpg",
            sharedAt: "2026-05-05T12:00:00Z",
            authorUserId: "author-\(id)",
            authorName: "Test Author",
            authorUsername: nil,
            authorAvatarUrl: nil,
            authorIsPro: nil,
            speciesCommonName: "Monarch Butterfly",
            speciesScientificName: "Danaus plexippus",
            petIdentification: nil,
            taxonomyKingdom: "Animalia",
            taxonomyClass: "Insecta",
            publicLocationLabel: "Austin, TX",
            locationSharing: .open,
            timeOfDay: nil,
            currentMonth: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false,
            isOwnedByViewer: false,
            mediaItems: mediaKinds.enumerated().map { index, kind in
                ExploreMediaItem(
                    kind: kind,
                    url: "https://example.com/\(id)-\(kind.rawValue)",
                    thumbnailUrl: kind == .audio ? nil : "https://example.com/\(id)-\(kind.rawValue).webp",
                    orderIndex: index,
                    durationSeconds: kind == .image ? nil : 4,
                    hasAudio: kind != .image
                )
            }
        )
    }

    private func makeCanonicalPost(
        from mapPost: ExploreMapPost,
        locationSharing: ExplorePostLocationSharing
    ) -> ExplorePost {
        ExplorePost(
            postId: mapPost.postId,
            scanId: mapPost.scanId,
            heroImageUrl: mapPost.heroImageUrl,
            referenceThumbnailUrl: mapPost.referenceThumbnailUrl,
            sharedAt: mapPost.sharedAt,
            authorUserId: mapPost.authorUserId,
            authorName: mapPost.authorName,
            authorUsername: mapPost.authorUsername,
            authorAvatarUrl: mapPost.authorAvatarUrl,
            authorIsPro: mapPost.authorIsPro,
            hashtags: nil,
            speciesCommonName: mapPost.speciesCommonName,
            speciesScientificName: mapPost.speciesScientificName,
            petIdentification: mapPost.petIdentification,
            publicLocationLabel: mapPost.publicLocationLabel,
            locationSharing: locationSharing,
            timeOfDay: mapPost.timeOfDay,
            currentMonth: mapPost.currentMonth,
            weatherCondition: mapPost.weatherCondition,
            weatherTemperatureF: mapPost.weatherTemperatureF,
            likeCount: mapPost.likeCount,
            commentCount: mapPost.commentCount,
            viewerHasLiked: mapPost.viewerHasLiked,
            isOwnedByViewer: mapPost.isOwnedByViewer,
            rankingValue: nil,
            mediaItems: mapPost.mediaItems
        )
    }

    func testSelectAdjacentPostAdvancesThroughCurrentMapOrder() {
        let viewModel = ExploreMapViewModel()
        let newest = makeMapPost(id: "newest", latitude: 30.267)
        let middle = makeMapPost(id: "middle", latitude: 30.268)
        let oldest = makeMapPost(id: "oldest", latitude: 30.269)

        viewModel.posts = [newest, middle, oldest]
        viewModel.selectPost(newest.id)

        XCTAssertEqual(viewModel.selectAdjacentPost(by: 1)?.id, middle.id)
        XCTAssertEqual(viewModel.selectedPostId, middle.id)
        XCTAssertEqual(viewModel.selectAdjacentPost(by: 1)?.id, oldest.id)
        XCTAssertEqual(viewModel.selectedPostId, oldest.id)
    }

    func testSelectAdjacentPostWrapsForwardToBeginning() {
        let viewModel = ExploreMapViewModel()
        let first = makeMapPost(id: "first", latitude: 30.267)
        let second = makeMapPost(id: "second", latitude: 30.268)

        viewModel.posts = [first, second]
        viewModel.selectPost(second.id)

        XCTAssertEqual(viewModel.selectAdjacentPost(by: 1)?.id, first.id)
        XCTAssertEqual(viewModel.selectedPostId, first.id)
    }

    func testSelectAdjacentPostWrapsBackwardToEnd() {
        let viewModel = ExploreMapViewModel()
        let first = makeMapPost(id: "first", latitude: 30.267)
        let second = makeMapPost(id: "second", latitude: 30.268)

        viewModel.posts = [first, second]
        viewModel.selectPost(first.id)

        XCTAssertEqual(viewModel.selectAdjacentPost(by: -1)?.id, second.id)
        XCTAssertEqual(viewModel.selectedPostId, second.id)
    }

    func testSelectAdjacentPostReturnsNilWhenOnlyOnePostExists() {
        let viewModel = ExploreMapViewModel()
        let onlyPost = makeMapPost(id: "only", latitude: 30.267)

        viewModel.posts = [onlyPost]
        viewModel.selectPost(onlyPost.id)

        XCTAssertNil(viewModel.selectAdjacentPost(by: 1))
        XCTAssertEqual(viewModel.selectedPostId, onlyPost.id)
    }

    func testOrderedMapPostsPutsSelectedPostAtEnd() {
        let viewModel = ExploreMapViewModel()
        let first = makeMapPost(id: "first", latitude: 30.267)
        let second = makeMapPost(id: "second", latitude: 30.268)
        let third = makeMapPost(id: "third", latitude: 30.269)

        viewModel.posts = [first, second, third]

        // When no post is selected, order is unchanged
        XCTAssertEqual(viewModel.orderedMapPosts.map(\.id), ["first", "second", "third"])

        // When a post is selected, it's moved to the end
        viewModel.selectPost("second")
        XCTAssertEqual(viewModel.orderedMapPosts.map(\.id), ["first", "third", "second"])

        // When selection is cleared, order is unchanged
        viewModel.selectPost(nil)
        XCTAssertEqual(viewModel.orderedMapPosts.map(\.id), ["first", "second", "third"])
    }

    func testMediaTypeFiltersMatchAnySelectedKindAndCombineWithSpecies() {
        let viewModel = ExploreMapViewModel()
        let image = makeMapPost(id: "image", latitude: 30.267, mediaKinds: [.image])
        let video = makeMapPost(id: "video", latitude: 30.268, mediaKinds: [.video])
        let mixed = makeMapPost(id: "mixed", latitude: 30.269, mediaKinds: [.image, .audio])
        viewModel.posts = [image, video, mixed]

        viewModel.selectedMediaTypes = [.video, .audio]
        viewModel.selectedSpeciesCategories = [.insects]

        XCTAssertEqual(viewModel.visiblePosts.map(\.id), ["video", "mixed"])
        XCTAssertTrue(viewModel.hasActiveFilters)
        XCTAssertEqual(viewModel.activeFilterCount, 3)
    }

    func testVisibleMediaTypeCountsIncludeZeroCountTypes() {
        let viewModel = ExploreMapViewModel()
        viewModel.mediaTypeCounts = [
            ExploreMapMediaTypeCount(mediaType: .video, count: 3),
            ExploreMapMediaTypeCount(mediaType: .audio, count: 1)
        ]

        XCTAssertEqual(viewModel.visibleMediaTypeCounts, [
            ExploreMapMediaTypeCount(mediaType: .image, count: 0),
            ExploreMapMediaTypeCount(mediaType: .video, count: 3),
            ExploreMapMediaTypeCount(mediaType: .audio, count: 1)
        ])
    }

    func testClearingAllFiltersClearsSelection() async {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(id: "selected", latitude: 30.267, mediaKinds: [.audio])
        viewModel.posts = [post]
        viewModel.selectedSpeciesCategories = [.insects]
        viewModel.selectedMediaTypes = [.audio]
        viewModel.selectPost(post.id)

        await viewModel.clearFilters()

        XCTAssertTrue(viewModel.selectedSpeciesCategories.isEmpty)
        XCTAssertTrue(viewModel.selectedMediaTypes.isEmpty)
        XCTAssertNil(viewModel.selectedPostId)
        XCTAssertFalse(viewModel.hasActiveFilters)
    }

    func testFocusCentersSelectsAndClearsAllFilters() {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(id: "focus", latitude: 12.3456)
        viewModel.selectedSpeciesCategories = [.insects]
        viewModel.selectedMediaTypes = [.audio]

        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        XCTAssertEqual(viewModel.posts.map(\.id), [post.id])
        XCTAssertEqual(viewModel.selectedPostId, post.id)
        XCTAssertEqual(viewModel.visibleRegion?.center.latitude ?? .nan, post.latitude, accuracy: 0.0001)
        XCTAssertEqual(viewModel.visibleRegion?.center.longitude ?? .nan, post.longitude, accuracy: 0.0001)
        XCTAssertEqual(viewModel.visibleRegion?.span.latitudeDelta ?? .nan, 0.05, accuracy: 0.0001)
        XCTAssertTrue(viewModel.selectedSpeciesCategories.isEmpty)
        XCTAssertTrue(viewModel.selectedMediaTypes.isEmpty)
        XCTAssertFalse(viewModel.hasActiveFilters)
    }

    func testFocusUsesApproximateRegionForObscuredCoordinates() {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(
            id: "obscured-focus",
            latitude: -23.5,
            coordinateVisibility: .obscured
        )

        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        XCTAssertEqual(viewModel.selectedPostId, post.id)
        XCTAssertEqual(viewModel.visibleRegion?.span.latitudeDelta ?? .nan, 0.2, accuracy: 0.0001)
        XCTAssertEqual(viewModel.visibleRegion?.span.longitudeDelta ?? .nan, 0.2, accuracy: 0.0001)
    }

    func testFocusedCameraCommitPreservesSelectionBeforeUserPan() {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(id: "camera-focus", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        let settledRegion = MKCoordinateRegion(
            center: post.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.08)
        )
        viewModel.markCameraChanged(region: settledRegion)

        XCTAssertEqual(viewModel.selectedPostId, post.id)
        XCTAssertEqual(viewModel.lastCommittedRegion?.span.longitudeDelta ?? .nan, 0.08, accuracy: 0.0001)
        XCTAssertFalse(viewModel.needsSearchInArea)

        let pannedRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: post.latitude + 1,
                longitude: post.longitude
            ),
            span: settledRegion.span
        )
        viewModel.markCameraChanged(region: pannedRegion)

        XCTAssertNil(viewModel.selectedPostId)
        XCTAssertTrue(viewModel.needsSearchInArea)
    }

    func testFocusedCameraCommitTreatsNonContainingFirstRegionAsUserPan() {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(id: "camera-interrupted", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        let pannedRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: post.latitude + 1,
                longitude: post.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        viewModel.markCameraChanged(region: pannedRegion)

        XCTAssertNil(viewModel.selectedPostId)
        XCTAssertTrue(viewModel.needsSearchInArea)
        XCTAssertEqual(
            viewModel.visibleRegion?.center.latitude ?? .nan,
            pannedRegion.center.latitude,
            accuracy: 0.0001
        )
    }

    func testClusterRefreshPreservesFocusedTarget() async {
        let viewModel = ExploreMapViewModel { _ in
            ExploreMapPointsResponse(mode: .clusters, visibleCount: 8)
        }
        let post = makeMapPost(id: "cluster-focus", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        await viewModel.refreshFocusedArea()

        XCTAssertEqual(viewModel.posts.map(\.id), [post.id])
        XCTAssertEqual(viewModel.selectedPostId, post.id)
    }

    func testAuthoritativePostRefreshRemovesMissingFocusedTarget() async {
        let viewModel = ExploreMapViewModel { _ in
            ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
        }
        let post = makeMapPost(id: "missing-focus", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        await viewModel.refreshFocusedArea()

        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertNil(viewModel.selectedPostId)
        XCTAssertNil(viewModel.selectedPost)
    }

    func testFocusSuppressesOlderInFlightMapResponse() async {
        var requestCount = 0
        let stalePost = makeMapPost(id: "stale-map-post", latitude: 40)
        let staleResponse = ExploreMapPointsResponse(
            mode: .posts,
            visibleCount: 1,
            posts: [stalePost]
        )
        let refreshedResponse = ExploreMapPointsResponse(mode: .clusters, visibleCount: 5)
        let viewModel = ExploreMapViewModel { _ in
            requestCount += 1
            if requestCount == 1 {
                try await Task.sleep(for: .milliseconds(75))
                return staleResponse
            }
            return refreshedResponse
        }
        let initialRegion = MKCoordinateRegion(
            center: stalePost.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        viewModel.visibleRegion = initialRegion
        viewModel.lastCommittedRegion = initialRegion

        let staleRequest = Task { await viewModel.searchCurrentArea() }
        while !viewModel.isLoading {
            await Task.yield()
        }

        let focusedPost = makeMapPost(id: "current-focus", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: focusedPost))
        await viewModel.refreshFocusedArea()
        await staleRequest.value

        for _ in 0..<100 {
            if requestCount >= 2, !viewModel.isLoading { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(viewModel.posts.map(\.id), [focusedPost.id])
        XCTAssertEqual(viewModel.selectedPostId, focusedPost.id)
        XCTAssertFalse(viewModel.posts.contains(where: { $0.id == stalePost.id }))
    }

    func testCanonicalPrivacyChangeRemovesFocusedPost() {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(id: "privacy-focus", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        viewModel.syncPosts(from: [
            makeCanonicalPost(from: post, locationSharing: .privateLocation)
        ])

        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertNil(viewModel.selectedPostId)
        XCTAssertNil(viewModel.selectedPost)
    }

    func testExplicitPostRemovalClearsFocusedTarget() {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(id: "removed-focus", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        viewModel.removePost(id: post.id)

        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertNil(viewModel.selectedPostId)
    }

    func testFocusTargetMapsPublicDetailPointIntoMapPost() throws {
        let mapPost = makeMapPost(id: "mapped-focus", latitude: 0)
        let canonicalPost = makeCanonicalPost(from: mapPost, locationSharing: .open)
        let detailData = Data("""
        {
            "post_id": "mapped-focus",
            "location_sharing": "open",
            "taxonomy_kingdom": "Animalia",
            "taxonomy_class": "Insecta",
            "map_point": {
                "latitude": 12.3456,
                "longitude": -45.6789,
                "coordinate_visibility": "obscured"
            }
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(ExplorePostDetail.self, from: detailData)

        let target = ExploreMapFocusTarget(post: canonicalPost, detail: detail)

        XCTAssertEqual(target?.post.id, canonicalPost.id)
        XCTAssertEqual(target?.post.latitude ?? .nan, 12.3456, accuracy: 0.0001)
        XCTAssertEqual(target?.post.longitude ?? .nan, -45.6789, accuracy: 0.0001)
        XCTAssertEqual(target?.post.coordinateVisibility, .obscured)
        XCTAssertEqual(target?.post.taxonomyKingdom, "Animalia")
        XCTAssertEqual(target?.post.taxonomyClass, "Insecta")
    }

    func testObservationMapPresentationFailsClosedAndUsesExactOrApproximatePolicy() throws {
        let mapPost = makeMapPost(id: "presentation", latitude: 0)
        let openPost = makeCanonicalPost(from: mapPost, locationSharing: .open)

        func decodeDetail(
            postId: String = "presentation",
            locationSharing: String = "open",
            latitude: Double = 12.3456,
            visibility: String
        ) throws -> ExplorePostDetail {
            let data = Data("""
            {
                "post_id": "\(postId)",
                "location_sharing": "\(locationSharing)",
                "map_point": {
                    "latitude": \(latitude),
                    "longitude": -45.6789,
                    "coordinate_visibility": "\(visibility)"
                }
            }
            """.utf8)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(ExplorePostDetail.self, from: data)
        }

        let exact = try XCTUnwrap(ExploreObservationMapPresentation(
            post: openPost,
            detail: decodeDetail(visibility: "exact")
        ))
        XCTAssertEqual(exact.spanDelta, 0.05, accuracy: 0.0001)
        XCTAssertNil(exact.approximateRadiusMeters)

        let obscured = try XCTUnwrap(ExploreObservationMapPresentation(
            post: openPost,
            detail: decodeDetail(visibility: "obscured")
        ))
        XCTAssertEqual(obscured.spanDelta, 0.2, accuracy: 0.0001)
        XCTAssertEqual(
            obscured.approximateRadiusMeters ?? .nan,
            ExploreObservationMapPresentation.approximateCoordinateRadiusMeters,
            accuracy: 0.0001
        )

        let privatePost = makeCanonicalPost(from: mapPost, locationSharing: .privateLocation)
        XCTAssertNil(ExploreObservationMapPresentation(
            post: privatePost,
            detail: try decodeDetail(visibility: "exact")
        ))
        XCTAssertNil(ExploreObservationMapPresentation(
            post: openPost,
            detail: try decodeDetail(postId: "different-post", visibility: "exact")
        ))
        XCTAssertNil(ExploreObservationMapPresentation(
            post: openPost,
            detail: try decodeDetail(latitude: 200, visibility: "exact")
        ))
    }

    func testLoaderReceivesViewportLimitZoomAndSelectedFilters() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var receivedRequest: ExploreMapPointsRequest?
        let viewModel = ExploreMapViewModel(
            dependencies: .init(
                loadPoints: { request in
                    receivedRequest = request
                    return ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
                },
                now: { now },
                debounceCameraSearch: { }
            )
        )
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30.267, longitude: -97.743),
            span: MKCoordinateSpan(latitudeDelta: 0.45, longitudeDelta: 0.45)
        )
        viewModel.visibleRegion = region
        viewModel.selectedSpeciesCategories = [.birds, .insects]
        viewModel.selectedMediaTypes = [.image, .audio]

        await viewModel.searchCurrentArea()

        let request = try XCTUnwrap(receivedRequest)
        XCTAssertEqual(request.limit, 500)
        XCTAssertEqual(request.region.center.latitude, region.center.latitude, accuracy: 0.0001)
        XCTAssertEqual(request.region.center.longitude, region.center.longitude, accuracy: 0.0001)
        XCTAssertEqual(request.zoomLevel, log2(360 / 0.45), accuracy: 0.0001)
        XCTAssertEqual(request.speciesCategories, [.birds, .insects])
        XCTAssertEqual(request.mediaTypes, [.image, .audio])
    }

    func testFreshRegionCacheAvoidsDuplicateLoad() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var loadCount = 0
        let viewModel = ExploreMapViewModel(
            dependencies: .init(
                loadPoints: { _ in
                    loadCount += 1
                    return ExploreMapPointsResponse(mode: .clusters, visibleCount: 9)
                },
                now: { now },
                debounceCameraSearch: { }
            )
        )
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30.267, longitude: -97.743),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )
        viewModel.visibleRegion = region

        await viewModel.searchCurrentArea()
        await viewModel.searchCurrentArea()

        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(viewModel.visibleCount, 9)
    }

    func testStaleRegionCacheRevalidatesAfterApplyingCachedResponse() async {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var loadCount = 0
        let viewModel = ExploreMapViewModel(
            dependencies: .init(
                loadPoints: { _ in
                    loadCount += 1
                    return ExploreMapPointsResponse(mode: .clusters, visibleCount: loadCount)
                },
                now: { now },
                debounceCameraSearch: { }
            )
        )
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30.267, longitude: -97.743),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )
        viewModel.visibleRegion = region

        await viewModel.searchCurrentArea()
        now = now.addingTimeInterval(91)
        await viewModel.searchCurrentArea()

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(viewModel.visibleCount, 2)
    }

    func testFailedAreaRefreshKeepsRenderedPostsAndShowsOfflineState() async {
        var loadCount = 0
        let existingPost = makeMapPost(id: "cached", latitude: 30.267)
        let viewModel = ExploreMapViewModel { _ in
            loadCount += 1
            if loadCount == 1 {
                return ExploreMapPointsResponse(
                    mode: .posts,
                    visibleCount: 1,
                    posts: [existingPost]
                )
            }
            throw URLError(.notConnectedToInternet)
        }
        viewModel.visibleRegion = MKCoordinateRegion(
            center: existingPost.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )

        await viewModel.searchCurrentArea()
        viewModel.visibleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: existingPost.latitude + 2,
                longitude: existingPost.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )
        await viewModel.searchCurrentArea()

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(viewModel.posts.map(\.id), [existingPost.id])
        XCTAssertTrue(viewModel.isOffline)
        XCTAssertNil(viewModel.errorMessage)
    }
}
