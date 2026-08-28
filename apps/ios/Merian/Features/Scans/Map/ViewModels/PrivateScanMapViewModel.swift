import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

@MainActor
@Observable
final class PrivateScanMapViewModel {
    var cameraPosition: MapCameraPosition = .automatic
    private(set) var visibleRegion: MKCoordinateRegion?
    private(set) var viewportSize: CGSize = .zero
    private(set) var points: [PrivateScanMapPoint] = []
    private(set) var filteredPoints: [PrivateScanMapPoint] = []
    private(set) var visiblePoints: [PrivateScanMapPoint] = []
    private(set) var annotations: [PrivateScanMapAnnotation] = []
    private(set) var isProjectingViewport = false
    private(set) var didSetInitialCamera = false
    var selectedPointID: String?
    var selectedCategories: Set<SearchCategoryBucket> = []
    var selectedMediaFilters: Set<ScanMediaFilter> = []

    @ObservationIgnored private var viewportProjector: PrivateScanMapViewportProjector
    @ObservationIgnored private var viewportProjectionTask: Task<Void, Never>?
    @ObservationIgnored private var datasetGeneration: UInt64 = 0
    @ObservationIgnored private var viewportRequestGeneration: UInt64 = 0
    @ObservationIgnored private var isViewportProjectionSuspended = false

    init(
        viewportProjector: PrivateScanMapViewportProjector =
            PrivateScanMapViewportProjector()
    ) {
        self.viewportProjector = viewportProjector
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
        rebuildFilteredPoints()

        if didSetInitialCamera,
           visibleRegion == nil,
           let newestPoint = points.first {
            setCamera(
                region: PrivateScanMapRegion.centered(
                    on: newestPoint.coordinate,
                    span: 0.2
                )
            )
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
        scheduleViewportProjection()
    }

    func updateViewportSize(_ size: CGSize) {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            viewportSize = .zero
            scheduleViewportProjection()
            return
        }
        viewportSize = size
        scheduleViewportProjection()
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
        rebuildFilteredPoints()
    }

    func toggleMediaFilter(_ filter: ScanMediaFilter) {
        if selectedMediaFilters.contains(filter) {
            selectedMediaFilters.remove(filter)
        } else {
            selectedMediaFilters.insert(filter)
        }
        selectedPointID = nil
        rebuildFilteredPoints()
    }

    func clearFilters() {
        selectedCategories.removeAll()
        selectedMediaFilters.removeAll()
        selectedPointID = nil
        rebuildFilteredPoints()
    }

    func clearCategories() {
        selectedCategories.removeAll()
        selectedPointID = nil
        rebuildFilteredPoints()
    }

    func clearMediaFilters() {
        selectedMediaFilters.removeAll()
        selectedPointID = nil
        rebuildFilteredPoints()
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

    func waitForViewportProjection() async {
        let task = viewportProjectionTask
        await task?.value
    }

    func setViewportProjectionSuspended(_ isSuspended: Bool) {
        guard isViewportProjectionSuspended != isSuspended else { return }
        isViewportProjectionSuspended = isSuspended

        if isSuspended {
            viewportProjectionTask?.cancel()
            viewportProjectionTask = nil
            isProjectingViewport = false
        } else {
            scheduleViewportProjection()
        }
    }

    func resetSensitiveState() {
        viewportRequestGeneration &+= 1
        datasetGeneration &+= 1
        viewportProjectionTask?.cancel()
        viewportProjectionTask = nil
        isProjectingViewport = false

        let retiredProjector = viewportProjector
        viewportProjector = PrivateScanMapViewportProjector()
        Task {
            await retiredProjector.reset()
        }

        cameraPosition = .automatic
        visibleRegion = nil
        points = []
        filteredPoints = []
        visiblePoints = []
        annotations = []
        selectedPointID = nil
        selectedCategories = []
        selectedMediaFilters = []
        didSetInitialCamera = false
    }

    private func setCamera(region: MKCoordinateRegion) {
        visibleRegion = region
        cameraPosition = .region(region)
        scheduleViewportProjection()
    }

    private func rebuildFilteredPoints() {
        filteredPoints = points.filter { point in
            let matchesCategory = selectedCategories.isEmpty
                || selectedCategories.contains(point.category)
            let matchesMedia = selectedMediaFilters.isEmpty
                || !selectedMediaFilters.isDisjoint(with: point.mediaFilters)
            return matchesCategory && matchesMedia
        }
        datasetGeneration &+= 1
        scheduleViewportProjection()
    }

    private func scheduleViewportProjection() {
        viewportProjectionTask?.cancel()
        guard !isViewportProjectionSuspended else {
            viewportProjectionTask = nil
            isProjectingViewport = false
            return
        }
        viewportRequestGeneration &+= 1
        let requestGeneration = viewportRequestGeneration
        let datasetGeneration = datasetGeneration
        let points = filteredPoints
        let region = visibleRegion
        let viewportSize = viewportSize
        let viewportProjector = viewportProjector
        isProjectingViewport = region != nil

        viewportProjectionTask = Task { [weak self] in
            let projection = await viewportProjector.project(
                datasetGeneration: datasetGeneration,
                points: points,
                region: region,
                viewportSize: viewportSize
            )
            guard !Task.isCancelled,
                  let self,
                  requestGeneration == self.viewportRequestGeneration else {
                return
            }
            visiblePoints = projection.visiblePoints
            annotations = projection.annotations
            isProjectingViewport = false
            viewportProjectionTask = nil
        }
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
