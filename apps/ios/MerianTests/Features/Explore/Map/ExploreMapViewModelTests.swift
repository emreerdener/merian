import Foundation
import MapKit
import XCTest

@testable import Merian

@MainActor
final class ExploreMapViewModelTests: XCTestCase {
    func testPlaceRegionFramesWholeDestinationAndSearchesFinalViewport() async throws {
        var loadedRegion: MKCoordinateRegion?
        let model = ExploreMapViewModel(dependencies: .init(
            loadPoints: { request in
                loadedRegion = request.region
                return ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
            },
            now: { Date() },
            debounceCameraSearch: { XCTFail("Place selection should search on camera settle") }
        ))
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 10)
        )
        model.selectedSpeciesCategories = [.birds]
        model.selectedPostId = "previous"
        model.navigate(to: MKMapItem(placemark: MKPlacemark(coordinate: region.center)), region: region)
        XCTAssertEqual(model.cameraPosition.region?.span.longitudeDelta, 10)
        XCTAssertNil(model.selectedPostId)
        XCTAssertEqual(model.selectedSpeciesCategories, [.birds])
        XCTAssertNil(loadedRegion)
        var settled = region
        settled.span.latitudeDelta = 15
        model.markCameraChanged(region: settled)
        await model.debounceSearchTask?.value
        XCTAssertEqual(loadedRegion?.span.latitudeDelta, 15)
        XCTAssertEqual(loadedRegion?.span.longitudeDelta, 10)
    }

    func testLocateSearchesSettledLocalViewportAndKeepsEmptyResultsLocal() async throws {
        var loadedRegion: MKCoordinateRegion?
        let model = ExploreMapViewModel(dependencies: .init(
            loadPoints: { request in
                loadedRegion = request.region
                return ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
            },
            now: { Date() },
            debounceCameraSearch: { XCTFail("Locate should search immediately after camera settle") }
        ))
        model.selectedSpeciesCategories = [.birds]
        model.selectedPostId = "previous"
        model.navigate(to: CLLocation(latitude: 1, longitude: 1))
        let requested = try XCTUnwrap(model.cameraPosition.region)
        XCTAssertLessThan(requested.span.longitudeDelta, 0.02)
        XCTAssertEqual(model.selectedSpeciesCategories, [.birds])
        XCTAssertNil(model.selectedPostId)
        XCTAssertNil(loadedRegion)

        var settled = requested
        settled.span.latitudeDelta *= 2
        model.markCameraChanged(region: settled)
        await model.debounceSearchTask?.value
        XCTAssertEqual(loadedRegion?.span.latitudeDelta, settled.span.latitudeDelta)
        XCTAssertEqual(loadedRegion?.span.longitudeDelta, settled.span.longitudeDelta)
        XCTAssertEqual(model.cameraPosition.region?.span.longitudeDelta, requested.span.longitudeDelta)
        XCTAssertTrue(model.visiblePosts.isEmpty)
    }

    func testManualAreaSearchClearsPendingImmediateDestination() async {
        var debounceCount = 0
        let model = ExploreMapViewModel(dependencies: .init(
            loadPoints: { _ in ExploreMapPointsResponse(mode: .posts, visibleCount: 0) },
            now: { Date() },
            debounceCameraSearch: { debounceCount += 1 }
        ))
        let destination = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        model.navigate(to: MKMapItem(placemark: MKPlacemark(coordinate: destination.center)))
        model.markCameraChanged(region: destination)
        await model.searchCurrentArea()
        XCTAssertNil(model.immediateSearchRegion)

        var laterRegion = destination
        laterRegion.center.latitude += 2
        model.markCameraChanged(region: laterRegion)
        await model.debounceSearchTask?.value
        XCTAssertEqual(debounceCount, 1)
    }

    func testRepeatedDestinationSettleDoesNotCancelOrDebounceImmediateSearch() async {
        var releaseDestination: CheckedContinuation<ExploreMapPointsResponse, Never>?
        var requestCount = 0
        var debounceCount = 0
        let model = ExploreMapViewModel(dependencies: .init(
            loadPoints: { _ in
                requestCount += 1
                let response: ExploreMapPointsResponse
                if requestCount == 1 {
                    response = await withCheckedContinuation { releaseDestination = $0 }
                } else {
                    response = ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
                }
                try Task.checkCancellation()
                return response
            },
            now: { Date() },
            debounceCameraSearch: { debounceCount += 1 }
        ))
        let destination = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        model.navigate(to: MKMapItem(placemark: MKPlacemark(coordinate: destination.center)))
        model.markCameraChanged(region: destination)
        model.markCameraChanged(region: destination)
        while releaseDestination == nil { await Task.yield() }
        model.markCameraChanged(region: destination)
        releaseDestination?.resume(returning: ExploreMapPointsResponse(mode: .posts, visibleCount: 0))
        await model.debounceSearchTask?.value

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(debounceCount, 0)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.lastCommittedRegion?.center.latitude, destination.center.latitude)
    }

    func testAdjustedDestinationSettleStartsImmediatelyWithFinalBounds() async {
        var loadedRegion: MKCoordinateRegion?
        let model = ExploreMapViewModel(dependencies: .init(
            loadPoints: { request in
                loadedRegion = request.region
                return ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
            },
            now: { Date() },
            debounceCameraSearch: { XCTFail("Destination adjustments must not debounce") }
        ))
        let destination = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        var finalRegion = destination
        finalRegion.span.latitudeDelta = 0.8
        model.navigate(to: MKMapItem(placemark: MKPlacemark(coordinate: destination.center)))
        model.markCameraChanged(region: destination)
        model.markCameraChanged(region: finalRegion)
        await model.debounceSearchTask?.value
        XCTAssertEqual(loadedRegion?.span.latitudeDelta, finalRegion.span.latitudeDelta)
        XCTAssertEqual(model.lastCommittedRegion?.span.latitudeDelta, finalRegion.span.latitudeDelta)
    }

    func testPlaceSearchCommitsBeforeObsoleteRequestFinishes() async {
        var releaseInitial: CheckedContinuation<ExploreMapPointsResponse, Never>?
        var requestCount = 0
        let model = ExploreMapViewModel(dependencies: .init(
            loadPoints: { _ in
                requestCount += 1
                if requestCount == 1 {
                    return await withCheckedContinuation { releaseInitial = $0 }
                }
                return ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
            },
            now: { Date() },
            debounceCameraSearch: { XCTFail("Place selection must not debounce") }
        ))
        let initial = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        let destination = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 2, longitude: 2),
            span: initial.span
        )
        let initialLoad = Task { await model.fetchMapPoints(for: initial) }
        while releaseInitial == nil { await Task.yield() }
        model.visibleRegion = initial
        await model.fetchMapPoints(for: initial, forceRefresh: true)

        model.navigate(to: MKMapItem(placemark: MKPlacemark(coordinate: destination.center)))
        model.markCameraChanged(region: destination)
        await model.debounceSearchTask?.value

        XCTAssertEqual(requestCount, 2, "The destination must start while the old request is suspended")
        XCTAssertEqual(model.lastCommittedRegion?.center.latitude, destination.center.latitude)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.needsSearchInArea)

        releaseInitial?.resume(returning: ExploreMapPointsResponse(mode: .posts, visibleCount: 0))
        await initialLoad.value
        XCTAssertEqual(model.lastCommittedRegion?.center.latitude, destination.center.latitude)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(requestCount, 2)
    }

    func testObsoleteFailureCannotClearDestinationLoadingOrDrainItsRefresh() async {
        var releaseInitial: CheckedContinuation<ExploreMapPointsResponse, Error>?
        var releaseDestination: CheckedContinuation<ExploreMapPointsResponse, Error>?
        var requestCount = 0
        let destinationStarted = expectation(description: "Destination starts before old request finishes")
        let model = ExploreMapViewModel(dependencies: .init(
            loadPoints: { _ in
                requestCount += 1
                if requestCount == 1 {
                    return try await withCheckedThrowingContinuation { releaseInitial = $0 }
                }
                if requestCount == 2 {
                    return try await withCheckedThrowingContinuation {
                        releaseDestination = $0
                        destinationStarted.fulfill()
                    }
                }
                return ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
            },
            now: { Date() },
            debounceCameraSearch: { XCTFail("Place selection must not debounce") }
        ))
        let initial = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        let destination = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 2, longitude: 2),
            span: initial.span
        )
        let initialLoad = Task { await model.fetchMapPoints(for: initial) }
        while releaseInitial == nil { await Task.yield() }
        model.navigate(to: MKMapItem(placemark: MKPlacemark(coordinate: destination.center)))
        model.markCameraChanged(region: destination)
        await fulfillment(of: [destinationStarted], timeout: 2)
        await model.fetchMapPoints(for: destination, forceRefresh: true)

        releaseInitial?.resume(throwing: URLError(.notConnectedToInternet))
        await initialLoad.value
        XCTAssertTrue(model.isLoading, "Old cleanup must not clear the current loading state")
        XCTAssertTrue(model.needsRefreshAfterCurrentLoad)
        XCTAssertTrue(model.needsForcedRefreshAfterCurrentLoad)
        XCTAssertFalse(model.isOffline)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(requestCount, 2)

        for _ in 0..<100 where releaseDestination == nil { await Task.yield() }
        releaseDestination?.resume(returning: ExploreMapPointsResponse(mode: .posts, visibleCount: 0))
        await model.debounceSearchTask?.value
        for _ in 0..<100 where requestCount < 3 { await Task.yield() }
        XCTAssertEqual(requestCount, 3, "Only the destination's completion drains its queued refresh")
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.lastCommittedRegion?.center.latitude, destination.center.latitude)
    }

    func testSelectedPlaceSearchesSettledViewportImmediatelyBelowPanThreshold() async {
        var loadedRequests: [ExploreMapPointsRequest] = []
        var debounceCount = 0
        let model = ExploreMapViewModel(dependencies: .init(
            loadPoints: { request in
                try Task.checkCancellation()
                loadedRequests.append(request)
                return ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
            },
            now: { Date() },
            debounceCameraSearch: { debounceCount += 1 }
        ))
        let initial = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        var destination = initial
        destination.center.latitude += 0.01
        model.lastCommittedRegion = initial
        model.visibleRegion = initial
        model.selectedSpeciesCategories = [.birds]
        model.selectedMediaTypes = [.audio]
        model.needsSearchInArea = true

        model.navigate(to: MKMapItem(placemark: MKPlacemark(coordinate: destination.center)))
        XCTAssertTrue(loadedRequests.isEmpty)
        XCTAssertFalse(model.needsSearchInArea, "The previous area's search button is hidden while moving")
        model.markCameraChanged(region: destination)
        await model.debounceSearchTask?.value

        XCTAssertEqual(loadedRequests.count, 1)
        XCTAssertEqual(loadedRequests.first?.region.center.latitude, destination.center.latitude)
        XCTAssertEqual(loadedRequests.first?.speciesCategories, [.birds])
        XCTAssertEqual(loadedRequests.first?.mediaTypes, [.audio])
        XCTAssertEqual(debounceCount, 0)
        XCTAssertFalse(model.needsSearchInArea)

        var pannedRegion = destination
        pannedRegion.center.latitude += 2
        model.markCameraChanged(region: pannedRegion)
        await model.debounceSearchTask?.value
        XCTAssertEqual(debounceCount, 1, "Later pans retain the normal debounce")
        XCTAssertEqual(loadedRequests.count, 2)
    }

    func testSettledDestinationDoesNotCancelItsOwnDiscoveryRequest() async {
        let model = ExploreMapViewModel(dependencies: .init(
            loadPoints: { _ in
                try Task.checkCancellation()
                return ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
            },
            now: { Date() },
            debounceCameraSearch: {}
        ))
        let destination = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        model.navigate(to: MKMapItem(placemark: MKPlacemark(coordinate: destination.center)))
        model.markCameraChanged(region: destination)
        for _ in 0..<50 where model.lastCommittedRegion == nil { await Task.yield() }
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.lastCommittedRegion?.center.latitude, destination.center.latitude)
    }

    func testPlaceNavigationPreservesFiltersAndClearsSelection() {
        let model = ExploreMapViewModel()
        model.selectedSpeciesCategories = [.birds]
        model.selectedPostId = "previous"
        let coordinate = CLLocationCoordinate2D(latitude: 1, longitude: 1)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        model.navigate(to: item)
        XCTAssertTrue(model.cameraPosition.item === item)
        XCTAssertEqual(model.selectedSpeciesCategories, [.birds])
        XCTAssertNil(model.selectedPostId)
    }

    func testFirstSettledDestinationLoadsAfterInitialRequestIsInvalidated() async {
        var releaseInitial: CheckedContinuation<ExploreMapPointsResponse, Never>?
        var loadedRegions: [MKCoordinateRegion] = []
        let model = ExploreMapViewModel(dependencies: .init(
            loadPoints: { request in
                loadedRegions.append(request.region)
                if loadedRegions.count == 1 {
                    return await withCheckedContinuation { releaseInitial = $0 }
                }
                return ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
            },
            now: { Date() },
            debounceCameraSearch: {}
        ))
        let initial = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        let destination = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 2, longitude: 2),
            span: initial.span
        )
        let firstLoad = Task { await model.fetchMapPoints(for: initial) }
        while releaseInitial == nil { await Task.yield() }
        model.visibleRegion = initial
        await model.fetchMapPoints(for: initial, forceRefresh: true)
        model.navigate(to: MKMapItem(placemark: MKPlacemark(coordinate: destination.center)))
        releaseInitial?.resume(returning: ExploreMapPointsResponse(mode: .posts, visibleCount: 0))
        await firstLoad.value
        XCTAssertNil(model.lastCommittedRegion, "A pre-navigation response must not commit while moving")
        XCTAssertFalse(model.needsRefreshAfterCurrentLoad)
        XCTAssertFalse(model.needsForcedRefreshAfterCurrentLoad)
        model.markCameraChanged(region: destination)
        await model.debounceSearchTask?.value
        XCTAssertEqual(loadedRegions.count, 2)
        XCTAssertEqual(model.lastCommittedRegion?.center.latitude, destination.center.latitude)
    }

    func testPostFocusSupersedesPendingPlaceSearch() async {
        var debounceCount = 0
        let model = ExploreMapViewModel(dependencies: .init(
            loadPoints: { _ in ExploreMapPointsResponse(mode: .posts, visibleCount: 0) },
            now: { Date() },
            debounceCameraSearch: { debounceCount += 1 }
        ))
        let destination = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        model.navigate(to: MKMapItem(placemark: MKPlacemark(coordinate: destination.center)))
        model.focus(on: ExploreMapFocusTarget(post: makeMapPost(id: "focus", latitude: 30)))
        // A user pan can be the next callback if the focus camera move never settles.
        model.markCameraChanged(region: destination)
        await model.debounceSearchTask?.value
        XCTAssertEqual(debounceCount, 1)
    }

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

    func testReportInvalidationFencesLateResultsAndCachedRegionReuse() async {
        let post = makeMapPost(id: "reported-map", latitude: 1)
        var pending: CheckedContinuation<ExploreMapPointsResponse, Never>?
        var calls = 0
        let model = ExploreMapViewModel { _ in
            calls += 1
            if calls == 1 {
                return await withCheckedContinuation { pending = $0 }
            }
            return ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
        }
        let region = MKCoordinateRegion(center: post.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
        model.visibleRegion = region
        model.lastCommittedRegion = region
        let stale = Task { await model.searchCurrentArea() }
        while pending == nil { await Task.yield() }
        model.invalidateReportedContent([post.id])
        pending?.resume(returning: ExploreMapPointsResponse(mode: .posts, visibleCount: 1, posts: [post]))
        await stale.value
        XCTAssertTrue(model.posts.isEmpty)
        XCTAssertEqual(model.visibleCount, 0)
        await model.fetchMapPoints(for: region)
        XCTAssertEqual(calls, 2)
        model.invalidateReportedContent([post.id])
        await model.fetchMapPoints(for: region)
        XCTAssertEqual(calls, 3)
        XCTAssertTrue(model.posts.isEmpty)
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
        var canonicalPost = makeCanonicalPost(from: mapPost, locationSharing: .open)
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
        canonicalPost.identification = try decoder.decode(ExploreIdentification.self, from: Data(#"{"version":1,"rank":"genus","label_source":"ai_primary","original_rank":"genus","original_scientific_name":"Examplea","original_common_name":null}"#.utf8))
        canonicalPost.referenceThumbnailUrl = "https://example.invalid/species.webp"

        let target = ExploreMapFocusTarget(post: canonicalPost, detail: detail)

        XCTAssertEqual(target?.post.id, canonicalPost.id)
        XCTAssertEqual(target?.post.latitude ?? .nan, 12.3456, accuracy: 0.0001)
        XCTAssertEqual(target?.post.longitude ?? .nan, -45.6789, accuracy: 0.0001)
        XCTAssertEqual(target?.post.coordinateVisibility, .obscured)
        XCTAssertEqual(target?.post.taxonomyKingdom, "Animalia")
        XCTAssertEqual(target?.post.taxonomyClass, "Insecta")
        XCTAssertEqual(target?.post.identification, canonicalPost.identification)
        if let target {
            let viewModel = ExploreMapViewModel()
            viewModel.focus(on: ExploreMapFocusTarget(post: mapPost))
            viewModel.syncPosts(from: [canonicalPost])
            XCTAssertEqual(viewModel.selectedPost?.identification, canonicalPost.identification)
            XCTAssertNotEqual(target.post.mapThumbnailUrl, canonicalPost.referenceThumbnailUrl)
            XCTAssertEqual(target.post.asExplorePost.identification, canonicalPost.identification)
        }
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
