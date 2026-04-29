import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ExploreMapViewModel {
    var cameraPosition: MapCameraPosition = .automatic
    var visibleRegion: MKCoordinateRegion?
    var lastCommittedRegion: MKCoordinateRegion?
    var needsSearchInArea = false
    var isLoading = false
    var errorMessage: String?
    var isOffline = false
    var mode: ExploreMapMode = .posts
    var clusters: [ExploreMapCluster] = []
    var posts: [ExploreMapPost] = []
    var selectedPostId: String?
    var visibleCount = 0

    @ObservationIgnored private let maxPostLimit = 500
    @ObservationIgnored private let fallbackRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 120)
    )

    var selectedPost: ExploreMapPost? {
        guard let selectedPostId else { return nil }
        return posts.first(where: { $0.id == selectedPostId })
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
        }
    }

    func searchCurrentArea() async {
        guard let region = visibleRegion ?? lastCommittedRegion else { return }
        await fetchMapPoints(for: region)
    }

    func recenter(using environmentContextManager: EnvironmentContextManager) async {
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
    }

    func selectPost(_ postId: String?) {
        selectedPostId = postId
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
                sharedAt: canonical.sharedAt,
                authorUserId: canonical.authorUserId,
                authorName: canonical.authorName,
                authorAvatarUrl: canonical.authorAvatarUrl,
                speciesCommonName: canonical.speciesCommonName,
                speciesScientificName: canonical.speciesScientificName,
                publicLocationLabel: canonical.publicLocationLabel,
                timeOfDay: canonical.timeOfDay,
                currentMonth: canonical.currentMonth,
                weatherCondition: canonical.weatherCondition,
                weatherTemperatureF: canonical.weatherTemperatureF,
                likeCount: canonical.likeCount,
                commentCount: canonical.commentCount,
                viewerHasLiked: canonical.viewerHasLiked,
                isOwnedByViewer: canonical.isOwnedByViewer
            )
        }

        if let selectedPostId, posts.contains(where: { $0.id == selectedPostId }) == false {
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
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await MerianNetworkClient.shared.getExploreMapPoints(
                northLatitude: region.northLatitude,
                southLatitude: region.southLatitude,
                eastLongitude: region.eastLongitude,
                westLongitude: region.westLongitude,
                zoomLevel: zoomLevel(for: region),
                limit: maxPostLimit
            )

            mode = response.mode
            clusters = response.clusters
            posts = Array(response.posts.prefix(maxPostLimit))
            visibleCount = response.visibleCount
            errorMessage = nil
            isOffline = false
            needsSearchInArea = false
            lastCommittedRegion = region

            if let selectedPostId, posts.contains(where: { $0.id == selectedPostId }) == false {
                self.selectedPostId = nil
            }
        } catch let urlError as URLError {
            if isOfflineError(urlError) {
                isOffline = true
                errorMessage = posts.isEmpty && clusters.isEmpty
                    ? "You’re offline. Reconnect to load discoveries on the map."
                    : nil
            } else {
                isOffline = false
                errorMessage = posts.isEmpty && clusters.isEmpty
                    ? ExploreErrorFormatter.message(for: urlError)
                    : nil
            }
        } catch {
            isOffline = false
            errorMessage = posts.isEmpty && clusters.isEmpty
                ? ExploreErrorFormatter.message(for: error)
                : nil
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
            || abs(lhs.center.longitude - rhs.center.longitude) > longitudeThreshold
            || zoomDelta > 0.22
    }

    private func isOfflineError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
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
