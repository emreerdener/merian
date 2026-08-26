import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ExploreMapViewModel {
    typealias MapPointsLoader = @MainActor (
        _ request: ExploreMapPointsRequest
    ) async throws -> ExploreMapPointsResponse

    struct Dependencies {
        let loadPoints: MapPointsLoader
        let now: @MainActor () -> Date
        let debounceCameraSearch: @MainActor () async throws -> Void
    }

    var cameraPosition: MapCameraPosition = .automatic
    var visibleRegion: MKCoordinateRegion?
    var lastCommittedRegion: MKCoordinateRegion?
    var needsSearchInArea = false
    var isLoading = false
    var errorMessage: String?
    var hasServiceUnavailableError = false
    var isOffline = false
    var mode: ExploreMapMode = .posts
    var clusters: [ExploreMapCluster] = []
    var posts: [ExploreMapPost] = []
    var selectedPostId: String?
    var visibleCount = 0
    var categoryCounts: [ExploreMapCategoryCount] = []
    var mediaTypeCounts: [ExploreMapMediaTypeCount] = []
    var selectedSpeciesCategories: Set<ExploreMapSpeciesCategory> = []
    var selectedMediaTypes: Set<ExploreMediaKind> = []

    var appliedSpeciesCategories: Set<ExploreMapSpeciesCategory> = []
    var appliedMediaTypes: Set<ExploreMediaKind> = []

    @ObservationIgnored let maxPostLimit = 500
    @ObservationIgnored let fallbackRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 120)
    )
    @ObservationIgnored var responseCache = ExploreMapResponseCache()
    @ObservationIgnored var debounceSearchTask: Task<Void, Never>?
    @ObservationIgnored var needsRefreshAfterCurrentLoad = false
    @ObservationIgnored var needsForcedRefreshAfterCurrentLoad = false
    @ObservationIgnored var requestGeneration = 0
    @ObservationIgnored var focusedPost: ExploreMapPost?
    @ObservationIgnored var isAwaitingFocusedCameraCommit = false
    @ObservationIgnored let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    convenience init(
        mapPointsLoader: @escaping MapPointsLoader = Dependencies.live.loadPoints
    ) {
        let liveDependencies = Dependencies.live
        self.init(
            dependencies: Dependencies(
                loadPoints: mapPointsLoader,
                now: liveDependencies.now,
                debounceCameraSearch: liveDependencies.debounceCameraSearch
            )
        )
    }

    var selectedPost: ExploreMapPost? {
        guard let selectedPostId else { return nil }
        return visiblePosts.first(where: { $0.id == selectedPostId })
    }

    var hasActiveSpeciesFilters: Bool {
        !selectedSpeciesCategories.isEmpty
    }

    var hasActiveMediaTypeFilters: Bool {
        !selectedMediaTypes.isEmpty
    }

    var hasActiveFilters: Bool {
        hasActiveSpeciesFilters || hasActiveMediaTypeFilters
    }

    var activeFilterCount: Int {
        selectedSpeciesCategories.count + selectedMediaTypes.count
    }

    var visiblePosts: [ExploreMapPost] {
        ExploreMapFilterPolicy.visiblePosts(
            from: posts,
            selectedSpeciesCategories: selectedSpeciesCategories,
            selectedMediaTypes: selectedMediaTypes,
            appliedSpeciesCategories: appliedSpeciesCategories,
            appliedMediaTypes: appliedMediaTypes
        )
    }

    var orderedMapPosts: [ExploreMapPost] {
        let basePosts = visiblePosts
        guard let selectedPostId,
              let selectedIndex = basePosts.firstIndex(where: { $0.id == selectedPostId }) else {
            return basePosts
        }

        var reordered = basePosts
        let selectedPost = reordered.remove(at: selectedIndex)
        reordered.append(selectedPost)
        return reordered
    }

    var visibleClusters: [ExploreMapCluster] {
        guard appliedSpeciesCategories == selectedSpeciesCategories,
              appliedMediaTypes == selectedMediaTypes else { return [] }
        guard hasActiveFilters else { return clusters }
        return visibleCount == 0 ? [] : clusters
    }

    var visibleDiscoveryCount: Int {
        if mode == .clusters, !visibleClusters.isEmpty {
            return visibleCount
        }
        return visiblePosts.count
    }

    var visibleCategoryCounts: [ExploreMapCategoryCount] {
        ExploreMapFilterPolicy.visibleCategoryCounts(
            from: categoryCounts,
            selectedCategories: selectedSpeciesCategories
        )
    }

    var visibleMediaTypeCounts: [ExploreMapMediaTypeCount] {
        ExploreMapFilterPolicy.visibleMediaTypeCounts(from: mediaTypeCounts)
    }

    /// Uses thumbnail waypoints at close camera zooms once individual posts are active.
    var showsThumbnailWaypoints: Bool {
        guard mode == .posts, !visiblePosts.isEmpty else { return false }
        guard let region = visibleRegion ?? lastCommittedRegion else { return false }
        return ExploreMapCameraPolicy.zoomLevel(for: region)
            >= ExploreMapCameraPolicy.thumbnailZoomLevel
    }

    func loadInitialData(using environmentContextManager: EnvironmentContextManager) async {
        guard lastCommittedRegion == nil, !isLoading else { return }

        environmentContextManager.validatePermissions()
        let region = initialRegion(using: environmentContextManager)
        visibleRegion = region
        cameraPosition = .region(region)
        await fetchMapPoints(for: region)
    }

    func markCameraChanged(region: MKCoordinateRegion) {
        if isAwaitingFocusedCameraCommit, let focusedPost {
            isAwaitingFocusedCameraCommit = false
            if region.containsForExploreMap(focusedPost.coordinate) {
                visibleRegion = region
                lastCommittedRegion = region
                needsSearchInArea = false
                return
            }
        }

        visibleRegion = region
        guard let lastCommittedRegion else { return }

        if regionMeaningfullyDiffers(region, from: lastCommittedRegion) {
            invalidateFocusedPost()
            needsSearchInArea = true
            selectedPostId = nil
            scheduleAutomaticSearch()
        }
    }

    func searchCurrentArea() async {
        debounceSearchTask?.cancel()
        debounceSearchTask = nil
        guard let region = visibleRegion ?? lastCommittedRegion else { return }
        await fetchMapPoints(for: region)
    }

    func recenter(using environmentContextManager: EnvironmentContextManager) async {
        debounceSearchTask?.cancel()
        debounceSearchTask = nil
        invalidateFocusedPost()
        selectedPostId = nil
        environmentContextManager.validatePermissions()
        let region = initialRegion(using: environmentContextManager)
        visibleRegion = region
        cameraPosition = .region(region)
        await fetchMapPoints(for: region)
    }

    func zoomIntoCluster(_ cluster: ExploreMapCluster) {
        let currentSpan = visibleRegion?.span ?? lastCommittedRegion?.span ?? fallbackRegion.span
        let nextRegion = MKCoordinateRegion(
            center: cluster.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: max(currentSpan.latitudeDelta * 0.45, 0.02),
                longitudeDelta: max(currentSpan.longitudeDelta * 0.45, 0.02)
            )
        )

        invalidateFocusedPost()
        selectedPostId = nil
        visibleRegion = nextRegion
        cameraPosition = .region(nextRegion)
        needsSearchInArea = true
        scheduleAutomaticSearch()
    }

    private func scheduleAutomaticSearch() {
        debounceSearchTask?.cancel()
        debounceSearchTask = Task { @MainActor [weak self] in
            guard let debounceCameraSearch = self?.dependencies.debounceCameraSearch else {
                return
            }
            try? await debounceCameraSearch()
            guard !Task.isCancelled else { return }
            await self?.searchCurrentArea()
        }
    }

    private func initialRegion(
        using environmentContextManager: EnvironmentContextManager
    ) -> MKCoordinateRegion {
        guard let location = environmentContextManager.lastKnownLocation else {
            return fallbackRegion
        }

        return MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.45, longitudeDelta: 0.45)
        )
    }

    private func regionMeaningfullyDiffers(
        _ lhs: MKCoordinateRegion,
        from rhs: MKCoordinateRegion
    ) -> Bool {
        let latitudeThreshold = max(rhs.span.latitudeDelta * 0.18, 0.002)
        let longitudeThreshold = max(rhs.span.longitudeDelta * 0.18, 0.002)
        let zoomDelta = abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta)
            / max(rhs.span.longitudeDelta, 0.000_01)

        return abs(lhs.center.latitude - rhs.center.latitude) > latitudeThreshold
            || wrappedLongitudeDelta(lhs.center.longitude, rhs.center.longitude) > longitudeThreshold
            || zoomDelta > 0.22
    }

    private func wrappedLongitudeDelta(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
    }
}
