import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

private struct ExploreMapCacheEntry {
    var region: MKCoordinateRegion
    var speciesCategories: Set<ExploreMapSpeciesCategory>
    var response: ExploreMapPointsResponse
    var lastAccessedAt: Date

    var itemCount: Int {
        response.posts.count + response.clusters.count
    }
}

@MainActor
@Observable
final class ExploreMapViewModel {
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
    var selectedSpeciesCategories: Set<ExploreMapSpeciesCategory> = []
    private var appliedSpeciesCategories: Set<ExploreMapSpeciesCategory> = []

    @ObservationIgnored private let maxPostLimit = 500
    @ObservationIgnored private let thumbnailZoomLevelThreshold = 11.5
    @ObservationIgnored private let maxCachedRegions = 8
    @ObservationIgnored private let maxCachedItems = 1_400
    @ObservationIgnored private let freshCacheTTL: TimeInterval = 90
    @ObservationIgnored private let fallbackRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 120)
    )
    @ObservationIgnored private var cachedResponses: [ExploreMapCacheEntry] = []
    @ObservationIgnored private var debounceSearchTask: Task<Void, Never>?
    @ObservationIgnored private var needsRefreshAfterCurrentLoad = false

    private func scheduleAutomaticSearch() {
        debounceSearchTask?.cancel()
        debounceSearchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.searchCurrentArea()
        }
    }

    var selectedPost: ExploreMapPost? {
        guard let selectedPostId else { return nil }
        return visiblePosts.first(where: { $0.id == selectedPostId })
    }

    var hasActiveSpeciesFilters: Bool {
        !selectedSpeciesCategories.isEmpty
    }

    var visiblePosts: [ExploreMapPost] {
        if appliedSpeciesCategories == selectedSpeciesCategories {
            return posts
        }

        guard hasActiveSpeciesFilters, appliedSpeciesCategories.isEmpty else { return [] }
        return posts.filter { post in
            selectedSpeciesCategories.contains(Self.speciesCategory(for: post))
        }
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
        guard appliedSpeciesCategories == selectedSpeciesCategories else { return [] }
        guard hasActiveSpeciesFilters else { return clusters }
        return categoryCounts.isEmpty ? [] : clusters
    }

    var visibleDiscoveryCount: Int {
        if mode == .clusters && !visibleClusters.isEmpty {
            return visibleCount
        }

        return visiblePosts.count
    }

    var visibleCategoryCounts: [ExploreMapCategoryCount] {
        let availableCategories = Set(categoryCounts.map(\.category))
        let defaultCounts = ExploreMapSpeciesCategory.defaultFilters
            .filter { !availableCategories.contains($0) }
            .map { ExploreMapCategoryCount(category: $0, count: 0) }
        let selectedCounts = selectedSpeciesCategories
            .subtracting(availableCategories)
            .subtracting(ExploreMapSpeciesCategory.defaultFilters)
            .map { ExploreMapCategoryCount(category: $0, count: 0) }

        return (categoryCounts + defaultCounts + selectedCounts)
            .filter {
                $0.count >= 1
                    || ExploreMapSpeciesCategory.defaultFilters.contains($0.category)
                    || selectedSpeciesCategories.contains($0.category)
            }
            .sorted { lhs, rhs in
                if lhs.category.sortPriority != rhs.category.sortPriority {
                    return lhs.category.sortPriority < rhs.category.sortPriority
                }
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.category.title < rhs.category.title
            }
    }

    /// Determines whether map waypoints should be rendered as thumbnail images instead of generic dots.
    /// Thumbnails are automatically displayed whenever the map is zoomed in past the `thumbnailZoomLevelThreshold`,
    /// providing immediate visual context for discoveries in the area.
    var showsThumbnailWaypoints: Bool {
        guard mode == .posts, !visiblePosts.isEmpty else { return false }
        guard let region = visibleRegion ?? lastCommittedRegion else { return false }
        return zoomLevel(for: region) >= thumbnailZoomLevelThreshold
    }

    func loadInitialData(using environmentContextManager: EnvironmentContextManager) async {
        guard lastCommittedRegion == nil, !isLoading else { return }

        environmentContextManager.validatePermissions()
        let region = regionForInitialLoad(using: environmentContextManager)
        visibleRegion = region
        cameraPosition = .region(region)
        await fetchMapPoints(for: region)
    }

    func markCameraChanged(region: MKCoordinateRegion) {
        visibleRegion = region
        guard let lastCommittedRegion else { return }

        if regionMeaningfullyDiffers(region, from: lastCommittedRegion) {
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
        environmentContextManager.validatePermissions()
        let region = regionForInitialLoad(using: environmentContextManager)
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

        selectedPostId = nil
        visibleRegion = nextRegion
        cameraPosition = .region(nextRegion)
        needsSearchInArea = true
        scheduleAutomaticSearch()
    }

    func selectPost(_ postId: String?) {
        selectedPostId = postId
    }

    func clearSpeciesFilters() async {
        await setSpeciesFilters([])
    }

    func toggleSpeciesFilter(_ category: ExploreMapSpeciesCategory) async {
        var nextFilters = selectedSpeciesCategories
        if nextFilters.contains(category) {
            nextFilters.remove(category)
        } else {
            nextFilters.insert(category)
        }
        await setSpeciesFilters(nextFilters)
    }

    func setSpeciesFilters(_ categories: Set<ExploreMapSpeciesCategory>) async {
        guard categories != selectedSpeciesCategories else { return }
        selectedSpeciesCategories = categories
        selectedPostId = nil
        await searchCurrentArea()
    }

    func post(relativeTo postId: String?, by offset: Int) -> ExploreMapPost? {
        guard let postId,
              let currentIndex = visiblePosts.firstIndex(where: { $0.id == postId }) else {
            return nil
        }
        guard let targetIndex = wrappedPostIndex(from: currentIndex, offset: offset) else { return nil }
        return visiblePosts[targetIndex]
    }

    func post(relativeToSelectedBy offset: Int) -> ExploreMapPost? {
        post(relativeTo: selectedPostId, by: offset)
    }

    @discardableResult
    func selectAdjacentPost(by offset: Int) -> ExploreMapPost? {
        guard let nextPost = post(relativeToSelectedBy: offset) else { return nil }
        self.selectedPostId = nextPost.id
        return nextPost
    }

    func syncPosts(from canonicalPosts: [ExplorePost]) {
        let canonicalById = Dictionary(uniqueKeysWithValues: canonicalPosts.map { ($0.id, $0) })
        posts = posts.map { mapPost in
            guard let canonical = canonicalById[mapPost.id] else { return mapPost }
            return ExploreMapPost(
                postId: canonical.postId,
                scanId: canonical.scanId,
                latitude: mapPost.latitude,
                longitude: mapPost.longitude,
                coordinateVisibility: mapPost.coordinateVisibility,
                heroImageUrl: canonical.heroImageUrl,
                referenceThumbnailUrl: canonical.referenceThumbnailUrl ?? mapPost.referenceThumbnailUrl,
                sharedAt: canonical.sharedAt,
                authorUserId: canonical.authorUserId,
                authorName: canonical.authorName,
                authorUsername: canonical.authorUsername,
                authorAvatarUrl: canonical.authorAvatarUrl,
                authorIsPro: canonical.authorIsPro,
                speciesCommonName: canonical.speciesCommonName,
                speciesScientificName: canonical.speciesScientificName,
                petIdentification: canonical.petIdentification,
                taxonomyKingdom: mapPost.taxonomyKingdom,
                taxonomyClass: mapPost.taxonomyClass,
                publicLocationLabel: canonical.publicLocationLabel,
                locationSharing: canonical.locationSharing,
                timeOfDay: canonical.timeOfDay,
                currentMonth: canonical.currentMonth,
                weatherCondition: canonical.weatherCondition,
                weatherTemperatureF: canonical.weatherTemperatureF,
                likeCount: canonical.likeCount,
                commentCount: canonical.commentCount,
                viewerHasLiked: canonical.viewerHasLiked,
                isOwnedByViewer: canonical.isOwnedByViewer,
                mediaItems: canonical.mediaItems?.isEmpty == false ? canonical.mediaItems : mapPost.mediaItems
            )
        }

        if let selectedPostId, visiblePosts.contains(where: { $0.id == selectedPostId }) == false {
            self.selectedPostId = nil
        }
    }

    func removePost(id: String) {
        posts.removeAll { $0.id == id }
        if selectedPostId == id {
            selectedPostId = nil
        }
    }

    func removePosts(byAuthorUserId authorUserId: String) {
        posts.removeAll { $0.authorUserId == authorUserId }
        if selectedPost?.authorUserId == authorUserId {
            selectedPostId = nil
        }
    }

    private func fetchMapPoints(for region: MKCoordinateRegion) async {
        guard !isLoading else {
            needsRefreshAfterCurrentLoad = true
            return
        }

        let now = Date()
        let cachedWasFresh = applyCachedResponseIfAvailable(for: region, now: now)
        if cachedWasFresh {
            return
        }

        isLoading = true
        defer {
            isLoading = false

            if needsRefreshAfterCurrentLoad {
                needsRefreshAfterCurrentLoad = false
                let refreshRegion = visibleRegion ?? region
                Task { @MainActor [weak self] in
                    await self?.fetchMapPoints(for: refreshRegion)
                }
            }
        }

        let requestedSpeciesCategories = selectedSpeciesCategories

        do {
            let response = try await MerianNetworkClient.shared.getExploreMapPoints(
                northLatitude: region.northLatitude,
                southLatitude: region.southLatitude,
                eastLongitude: region.eastLongitude,
                westLongitude: region.westLongitude,
                zoomLevel: zoomLevel(for: region),
                limit: maxPostLimit,
                speciesCategories: requestedSpeciesCategories
            )
            storeCachedResponse(response, for: region, speciesCategories: requestedSpeciesCategories, now: now)
            apply(response: response, for: region, speciesCategories: requestedSpeciesCategories)
        } catch let error as MerianError {
            if case .httpError(let statusCode, _) = error, statusCode == 503 {
                hasServiceUnavailableError = true
                errorMessage = nil
            } else {
                hasServiceUnavailableError = false
                errorMessage = posts.isEmpty && clusters.isEmpty
                    ? ExploreErrorFormatter.message(for: error)
                    : nil
            }
            isOffline = false
        } catch let urlError as URLError {
            if isOfflineError(urlError) {
                isOffline = true
                hasServiceUnavailableError = false
                errorMessage = posts.isEmpty && clusters.isEmpty
                    ? "You’re offline. Reconnect to load discoveries on the map."
                    : nil
            } else {
                isOffline = false
                hasServiceUnavailableError = false
                errorMessage = posts.isEmpty && clusters.isEmpty
                    ? ExploreErrorFormatter.message(for: urlError)
                    : nil
            }
        } catch let decodingError as DecodingError {
#if DEBUG
            MerianLog.network.error(
                "Explore map response decoding failed: \(String(describing: decodingError), privacy: .public)"
            )
#endif
            isOffline = false
            hasServiceUnavailableError = false
            errorMessage = posts.isEmpty && clusters.isEmpty
                ? "Something went wrong. Please try again."
                : nil
        } catch {
            isOffline = false
            hasServiceUnavailableError = false
            errorMessage = posts.isEmpty && clusters.isEmpty
                ? ExploreErrorFormatter.message(for: error)
                : nil
        }
    }

    private func apply(
        response: ExploreMapPointsResponse,
        for region: MKCoordinateRegion,
        speciesCategories: Set<ExploreMapSpeciesCategory>
    ) {
        mode = response.mode
        clusters = response.clusters
        posts = Array(response.posts.prefix(maxPostLimit))
        visibleCount = response.visibleCount
        categoryCounts = response.categoryCounts
        appliedSpeciesCategories = speciesCategories
        errorMessage = nil
        hasServiceUnavailableError = false
        isOffline = false
        needsSearchInArea = false
        lastCommittedRegion = region

        if let selectedPostId, visiblePosts.contains(where: { $0.id == selectedPostId }) == false {
            self.selectedPostId = nil
        }
    }

    private func regionForInitialLoad(using environmentContextManager: EnvironmentContextManager) -> MKCoordinateRegion {
        guard let location = environmentContextManager.lastKnownLocation else {
            return fallbackRegion
        }

        return MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.45, longitudeDelta: 0.45)
        )
    }

    private func zoomLevel(for region: MKCoordinateRegion) -> Double {
        let longitudeDelta = max(region.span.longitudeDelta, 0.000_01)
        return max(0, min(log2(360 / longitudeDelta), 20))
    }

    private func regionMeaningfullyDiffers(_ lhs: MKCoordinateRegion, from rhs: MKCoordinateRegion) -> Bool {
        let latitudeThreshold = max(rhs.span.latitudeDelta * 0.18, 0.002)
        let longitudeThreshold = max(rhs.span.longitudeDelta * 0.18, 0.002)
        let zoomDelta = abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta) / max(rhs.span.longitudeDelta, 0.000_01)

        return abs(lhs.center.latitude - rhs.center.latitude) > latitudeThreshold
            || wrappedLongitudeDelta(lhs.center.longitude, rhs.center.longitude) > longitudeThreshold
            || zoomDelta > 0.22
    }

    private func applyCachedResponseIfAvailable(for region: MKCoordinateRegion, now: Date) -> Bool {
        guard let cacheIndex = cachedResponseIndex(for: region) else { return false }

        let cachedEntry = cachedResponses[cacheIndex]
        cachedResponses[cacheIndex].lastAccessedAt = now
        apply(response: cachedEntry.response, for: region, speciesCategories: cachedEntry.speciesCategories)
        pruneCachedResponses(around: region)

        return now.timeIntervalSince(cachedEntry.lastAccessedAt) < freshCacheTTL
    }

    private func cachedResponseIndex(
        for region: MKCoordinateRegion,
        speciesCategories: Set<ExploreMapSpeciesCategory>? = nil
    ) -> Int? {
        let requestedSpeciesCategories = speciesCategories ?? selectedSpeciesCategories
        return cachedResponses.indices
            .filter {
                regionsAreCacheCompatible(cachedResponses[$0].region, region)
                    && cachedResponses[$0].speciesCategories == requestedSpeciesCategories
            }
            .max(by: { cachedResponses[$0].lastAccessedAt < cachedResponses[$1].lastAccessedAt })
    }

    private func storeCachedResponse(
        _ response: ExploreMapPointsResponse,
        for region: MKCoordinateRegion,
        speciesCategories: Set<ExploreMapSpeciesCategory>,
        now: Date
    ) {
        let entry = ExploreMapCacheEntry(
            region: region,
            speciesCategories: speciesCategories,
            response: response,
            lastAccessedAt: now
        )

        if let existingIndex = cachedResponseIndex(for: region, speciesCategories: speciesCategories) {
            cachedResponses[existingIndex] = entry
        } else {
            cachedResponses.append(entry)
        }

        pruneCachedResponses(around: region)
    }

    private func pruneCachedResponses(around region: MKCoordinateRegion) {
        let expandedRegion = region.expanded(by: 2.5)
        cachedResponses.removeAll { expandedRegion.contains($0.region.center) == false }
        cachedResponses.sort { $0.lastAccessedAt > $1.lastAccessedAt }

        if cachedResponses.count > maxCachedRegions {
            cachedResponses = Array(cachedResponses.prefix(maxCachedRegions))
        }

        var totalItems = cachedResponses.reduce(0) { $0 + $1.itemCount }
        while totalItems > maxCachedItems, let lastEntry = cachedResponses.last {
            cachedResponses.removeLast()
            totalItems -= lastEntry.itemCount
        }
    }

    private func regionsAreCacheCompatible(_ lhs: MKCoordinateRegion, _ rhs: MKCoordinateRegion) -> Bool {
        let latitudeThreshold = max(max(lhs.span.latitudeDelta, rhs.span.latitudeDelta) * 0.12, 0.01)
        let longitudeThreshold = max(max(lhs.span.longitudeDelta, rhs.span.longitudeDelta) * 0.12, 0.01)
        let latitudeSpanRatio = max(lhs.span.latitudeDelta, rhs.span.latitudeDelta)
            / max(min(lhs.span.latitudeDelta, rhs.span.latitudeDelta), 0.000_01)
        let longitudeSpanRatio = max(lhs.span.longitudeDelta, rhs.span.longitudeDelta)
            / max(min(lhs.span.longitudeDelta, rhs.span.longitudeDelta), 0.000_01)

        return abs(lhs.center.latitude - rhs.center.latitude) <= latitudeThreshold
            && wrappedLongitudeDelta(lhs.center.longitude, rhs.center.longitude) <= longitudeThreshold
            && latitudeSpanRatio <= 1.18
            && longitudeSpanRatio <= 1.18
    }

    private func wrappedLongitudeDelta(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
    }

    private func isOfflineError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private var selectedPostIndex: Int? {
        guard let currentSelectedPostId = selectedPostId else { return nil }
        return visiblePosts.firstIndex(where: { $0.id == currentSelectedPostId })
    }

    private func wrappedPostIndex(from startIndex: Int, offset: Int) -> Int? {
        let filteredPosts = visiblePosts
        guard filteredPosts.indices.contains(startIndex) else { return nil }
        guard offset != 0 else { return startIndex }
        guard filteredPosts.count > 1 else { return nil }

        let count = filteredPosts.count
        let rawIndex = (startIndex + offset) % count
        return rawIndex >= 0 ? rawIndex : rawIndex + count
    }

    private static func speciesCategory(for post: ExploreMapPost) -> ExploreMapSpeciesCategory {
        let kingdom = post.taxonomyKingdom?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let className = post.taxonomyClass?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        if kingdom == "plantae" {
            return .plants
        }

        if kingdom == "fungi" {
            return .fungi
        }

        switch className {
        case "aves":
            return .birds
        case "mammalia":
            return .mammals
        case "reptilia", "squamata":
            return .reptiles
        case "amphibia":
            return .amphibians
        case "actinopterygii", "chondrichthyes", "sarcopterygii":
            return .fish
        case "insecta", "entognatha":
            return .insects
        case "arachnida":
            return .arachnids
        default:
            return .other
        }
    }
}

private extension MKCoordinateRegion {
    var northLatitude: Double {
        min(center.latitude + (span.latitudeDelta / 2), 90)
    }

    var southLatitude: Double {
        max(center.latitude - (span.latitudeDelta / 2), -90)
    }

    var eastLongitude: Double {
        wrappedLongitude(center.longitude + (span.longitudeDelta / 2))
    }

    var westLongitude: Double {
        wrappedLongitude(center.longitude - (span.longitudeDelta / 2))
    }

    func expanded(by factor: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: min(span.latitudeDelta * factor, 180),
                longitudeDelta: min(span.longitudeDelta * factor, 360)
            )
        )
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let latitudeContains = coordinate.latitude >= southLatitude && coordinate.latitude <= northLatitude
        guard latitudeContains else { return false }

        if westLongitude <= eastLongitude {
            return coordinate.longitude >= westLongitude && coordinate.longitude <= eastLongitude
        }

        return coordinate.longitude >= westLongitude || coordinate.longitude <= eastLongitude
    }

    private func wrappedLongitude(_ value: Double) -> Double {
        switch value {
        case let longitude where longitude > 180:
            return longitude - 360
        case let longitude where longitude < -180:
            return longitude + 360
        default:
            return value
        }
    }
}
