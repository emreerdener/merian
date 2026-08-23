import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

struct PrivateScanMapCategoryCount: Identifiable, Equatable, Sendable {
    let category: SearchCategoryBucket
    let count: Int

    var id: String { category.rawValue }
}

struct PrivateScanMapMediaCount: Identifiable, Equatable, Sendable {
    let mediaFilter: ScanMediaFilter
    let count: Int

    var id: String { mediaFilter.rawValue }
}

@MainActor
@Observable
final class PrivateScanMapViewModel {
    var cameraPosition: MapCameraPosition = .automatic
    private(set) var visibleRegion: MKCoordinateRegion?
    private(set) var viewportSize: CGSize = .zero
    private(set) var points: [PrivateScanMapPoint] = []
    private(set) var didSetInitialCamera = false
    var selectedPointID: String?
    var selectedCategories: Set<SearchCategoryBucket> = []
    var selectedMediaFilters: Set<ScanMediaFilter> = []

    var filteredPoints: [PrivateScanMapPoint] {
        points.filter { point in
            let matchesCategory = selectedCategories.isEmpty
                || selectedCategories.contains(point.category)
            let matchesMedia = selectedMediaFilters.isEmpty
                || !selectedMediaFilters.isDisjoint(with: point.mediaFilters)
            return matchesCategory && matchesMedia
        }
    }

    var visiblePoints: [PrivateScanMapPoint] {
        guard let visibleRegion else { return [] }
        return filteredPoints.filter {
            PrivateScanMapRegion.contains($0.coordinate, in: visibleRegion)
        }
    }

    var annotations: [PrivateScanMapAnnotation] {
        guard let visibleRegion else { return [] }
        return PrivateScanMapClusterer.annotations(
            points: filteredPoints,
            region: visibleRegion,
            viewportSize: viewportSize
        )
    }

    var selectedPoint: PrivateScanMapPoint? {
        guard let selectedPointID else { return nil }
        return filteredPoints.first(where: { $0.id == selectedPointID })
    }

    var categoryCounts: [PrivateScanMapCategoryCount] {
        let counts = Dictionary(grouping: points, by: \.category)
            .mapValues(\.count)
        return SearchCategoryBucket.libraryFilterPriority.compactMap { category in
            guard let count = counts[category], count > 0 else { return nil }
            return PrivateScanMapCategoryCount(category: category, count: count)
        }
    }

    var mediaCounts: [PrivateScanMapMediaCount] {
        ScanMediaFilter.allCases.compactMap { filter in
            let count = points.filter { $0.mediaFilters.contains(filter) }.count
            guard count > 0 else { return nil }
            return PrivateScanMapMediaCount(mediaFilter: filter, count: count)
        }
    }

    var hasActiveFilters: Bool {
        !selectedCategories.isEmpty || !selectedMediaFilters.isEmpty
    }

    var activeFilterCount: Int {
        selectedCategories.count + selectedMediaFilters.count
    }

    var effectiveZoomLevel: Double {
        guard let visibleRegion else { return 0 }
        let longitudeDelta = max(visibleRegion.span.longitudeDelta, 0.000_01)
        return max(0, min(log2(360 / longitudeDelta), 20))
    }

    var showsThumbnailWaypoints: Bool {
        effectiveZoomLevel >= 11.5
    }

    func update(snapshot: PrivateScanMapSnapshot) {
        points = snapshot.points
        if let selectedPointID,
           !points.contains(where: { $0.id == selectedPointID }) {
            self.selectedPointID = nil
        }

        selectedCategories = selectedCategories.filter { selected in
            points.contains(where: { $0.category == selected })
        }
        selectedMediaFilters = selectedMediaFilters.filter { selected in
            points.contains(where: { $0.mediaFilters.contains(selected) })
        }

        if points.isEmpty {
            selectedPointID = nil
        }
    }

    func setInitialCamera(currentLocation: CLLocation?) {
        guard !didSetInitialCamera else { return }
        didSetInitialCamera = true

        if let coordinate = currentLocation?.coordinate,
           Self.isValidCurrentCoordinate(coordinate) {
            setCamera(
                region: PrivateScanMapRegion.centered(on: coordinate, span: 0.45)
            )
            return
        }

        if let newestPoint = points.first {
            setCamera(
                region: PrivateScanMapRegion.centered(
                    on: newestPoint.coordinate,
                    span: 0.2
                )
            )
        }
    }

    func recenter(on location: CLLocation) {
        guard Self.isValidCurrentCoordinate(location.coordinate) else { return }
        selectedPointID = nil
        setCamera(
            region: PrivateScanMapRegion.centered(
                on: location.coordinate,
                span: 0.45
            )
        )
    }

    func showAllFilteredScans() {
        guard let region = PrivateScanMapRegion.fitted(
            to: filteredPoints.map(\.coordinate),
            padding: 1.25,
            minimumSpan: 0.2
        ) else {
            return
        }
        selectedPointID = nil
        setCamera(region: region)
    }

    func updateVisibleRegion(_ region: MKCoordinateRegion) {
        visibleRegion = region
        if let selectedPoint,
           !PrivateScanMapRegion.contains(selectedPoint.coordinate, in: region) {
            selectedPointID = nil
        }
    }

    func updateViewportSize(_ size: CGSize) {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return
        }
        viewportSize = size
    }

    func selectPoint(_ id: String?) {
        selectedPointID = id
    }

    func toggleCategory(_ category: SearchCategoryBucket) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        selectedPointID = nil
    }

    func toggleMediaFilter(_ filter: ScanMediaFilter) {
        if selectedMediaFilters.contains(filter) {
            selectedMediaFilters.remove(filter)
        } else {
            selectedMediaFilters.insert(filter)
        }
        selectedPointID = nil
    }

    func clearFilters() {
        selectedCategories.removeAll()
        selectedMediaFilters.removeAll()
        selectedPointID = nil
    }

    func clearCategories() {
        selectedCategories.removeAll()
        selectedPointID = nil
    }

    func clearMediaFilters() {
        selectedMediaFilters.removeAll()
        selectedPointID = nil
    }

    func focusRegion(for cluster: PrivateScanMapCluster) -> MKCoordinateRegion? {
        guard effectiveZoomLevel < 18,
              !Self.hasCoincidentCoordinates(cluster.points) else {
            return nil
        }
        return cluster.focusRegion
    }

    func focus(on cluster: PrivateScanMapCluster) {
        guard let region = focusRegion(for: cluster) else { return }
        selectedPointID = nil
        setCamera(region: region)
    }

    private func setCamera(region: MKCoordinateRegion) {
        visibleRegion = region
        cameraPosition = .region(region)
    }

    private static func isValidCurrentCoordinate(
        _ coordinate: CLLocationCoordinate2D
    ) -> Bool {
        PrivateScanMapRegion.isValidCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    private static func hasCoincidentCoordinates(
        _ points: [PrivateScanMapPoint]
    ) -> Bool {
        guard let first = points.first else { return true }
        return points.dropFirst().allSatisfy {
            abs($0.latitude - first.latitude) < 0.000_001
                && min(
                    PrivateScanMapRegion.positiveLongitudeDistance(
                        from: first.longitude,
                        to: $0.longitude
                    ),
                    PrivateScanMapRegion.positiveLongitudeDistance(
                        from: $0.longitude,
                        to: first.longitude
                    )
                ) < 0.000_001
        }
    }
}
