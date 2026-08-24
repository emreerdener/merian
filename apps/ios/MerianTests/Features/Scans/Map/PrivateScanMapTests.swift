import CoreLocation
import Foundation
import MapKit
@testable import Merian
import SwiftData
import Testing

@Suite("Private Scan Map")
@MainActor
struct PrivateScanMapTests {
    @Test("Collections search aliases find the private map card")
    func collectionSearchAliases() {
        for query in ["map", "private", "location", "your scans", "SCAN MAP"] {
            #expect(PrivateScanMapCollectionSearch.matches(query))
        }
        #expect(!PrivateScanMapCollectionSearch.matches("fungi album"))
    }

    @Test("Projection includes only completed biological scans with valid saved GPS")
    func projectionValidation() {
        let valid = makeRecord(id: "valid", latitude: 12.5, longitude: 45.5)
        let zeroCoordinate = makeRecord(id: "zero", latitude: 0, longitude: 0)
        let missingLatitude = makeRecord(id: "missing-latitude", latitude: nil, longitude: 45)
        let missingLongitude = makeRecord(id: "missing-longitude", latitude: 12, longitude: nil)
        let nonFinite = makeRecord(id: "non-finite", latitude: .nan, longitude: 45)
        let invalidLatitude = makeRecord(id: "invalid-latitude", latitude: 91, longitude: 45)
        let invalidLongitude = makeRecord(id: "invalid-longitude", latitude: 12, longitude: 181)
        let nonBiological = makeRecord(
            id: "non-biological",
            latitude: 12,
            longitude: 45,
            isBiological: false
        )

        let snapshot = PrivateScanMapSnapshot(records: [
            valid,
            zeroCoordinate,
            missingLatitude,
            missingLongitude,
            nonFinite,
            invalidLatitude,
            invalidLongitude,
            nonBiological
        ])

        #expect(snapshot.points.map(\.id) == ["valid"])
        #expect(PrivateScanMapRegion.isValidCoordinate(latitude: 0, longitude: 1))
        #expect(!PrivateScanMapRegion.isValidCoordinate(latitude: 0, longitude: 0))
    }

    @Test("Collections preview projects only spatial values")
    func previewProjectionIsSpatialOnly() throws {
        let mapped = makeRecord(
            id: "mapped",
            latitude: 12.345_678_901,
            longitude: 45.678_901_234
        )
        let invalid = makeRecord(id: "invalid", latitude: 0, longitude: 0)
        let nonBiological = makeRecord(
            id: "non-biological",
            latitude: 12,
            longitude: 45,
            isBiological: false
        )

        let original = PrivateScanMapPreviewSnapshot(records: [
            mapped,
            invalid,
            nonBiological
        ])
        let point = try #require(original.points.first)
        #expect(original.points.count == 1)
        #expect(point.id == "mapped")
        #expect(point.latitude == 12.345_678_901)
        #expect(point.longitude == 45.678_901_234)

        mapped.commonName = "Changed presentation"
        mapped.scientificName = "Changed species"
        mapped.capturedMediaJSON = "not-json"
        mapped.referenceImageUrl = "https://invalid.example/ignored.webp"
        let presentationOnlyChange = PrivateScanMapPreviewSnapshot(records: [mapped])
        #expect(presentationOnlyChange == original)

        mapped.gpsLongitude = 46
        let coordinateChange = PrivateScanMapPreviewSnapshot(records: [mapped])
        #expect(coordinateChange != original)
    }

    @Test("Projection preserves owner GPS regardless of publication state")
    func exactCoordinatePreservation() {
        let sharedScan = makeRecord(
            id: "shared-to-explore",
            latitude: 12.345_678_901,
            longitude: 45.678_901_234
        )
        let privateScan = makeRecord(
            id: "never-shared",
            latitude: -23.456_789_012,
            longitude: -67.890_123_456
        )

        let points = PrivateScanMapSnapshot(records: [sharedScan, privateScan]).points
        let sharedPoint = points.first { $0.id == sharedScan.id }
        let privatePoint = points.first { $0.id == privateScan.id }

        #expect(sharedPoint?.latitude == 12.345_678_901)
        #expect(sharedPoint?.longitude == 45.678_901_234)
        #expect(privatePoint?.latitude == -23.456_789_012)
        #expect(privatePoint?.longitude == -67.890_123_456)
    }

    @Test("Projection derives category, media, and corrected display values locally")
    func localProjectionValues() {
        let record = makeRecord(
            id: "local-values",
            latitude: 12,
            longitude: 45,
            taxonomyClass: "aves",
            media: [
                .image(.documents("bird.webp")),
                .video(StoredVideoMediaReference(.documents("bird.mp4"))),
                .audio(.documents("bird.wav"))
            ]
        )
        record.userIdentificationOverride = "Corvus brachyrhynchos"

        let point = PrivateScanMapSnapshot(records: [record]).points.first

        #expect(point?.category == .birds)
        #expect(point?.mediaFilters == [.image, .video, .audio])
        #expect(point?.scientificName == "Corvus brachyrhynchos")
    }

    @Test("Projection keeps the saved reference image behind captured media")
    func projectionPreservesReferenceFallback() throws {
        let record = makeRecord(
            id: "fallback",
            latitude: 12,
            longitude: 45,
            media: [.image(.documents("missing-owner-image.webp"))]
        )
        record.referenceImageUrl = "https://images.example.org/reference.webp"

        let point = try #require(
            PrivateScanMapSnapshot(records: [record]).points.first
        )

        #expect(point.thumbnail.imagePath == "missing-owner-image.webp")
        #expect(
            point.thumbnail.fallbackImageUrl
                == "https://images.example.org/reference.webp"
        )
    }

    @Test("Missing map media can request a safe reference image")
    func missingVisualReferenceCandidate() throws {
        let record = makeRecord(
            id: "missing-visual",
            latitude: 12,
            longitude: 45,
            media: [.image(.documents("missing-owner-image.webp"))]
        )
        record.isLocallyArchived = true
        record.gbifTaxonKey = 123
        record.scientificName = "Taxonomy Unavailable"
        record.commonName = "Unknown Subject"
        record.userIdentificationOverride = "Lagerstroemia indica"

        let candidate = try #require(
            ScanThumbnailBackfillCandidate(missingVisualFallbackFor: record)
        )
        #expect(candidate.scanId == record.id)
        #expect(candidate.scientificName == "Lagerstroemia indica")
        #expect(candidate.gbifTaxonKey == nil)

        record.referenceImageUrl = "https://images.example.org/reference.webp"
        #expect(
            ScanThumbnailBackfillCandidate(
                missingVisualFallbackFor: record
            ) == nil
        )
    }

    @Test("Reference recovery rejects unresolved people and domestic pets")
    func referenceCandidatePrivacyPolicy() {
        let unresolved = makeRecord(
            id: "unresolved",
            latitude: 12,
            longitude: 45
        )
        unresolved.scientificName = "Taxonomy Unavailable"
        unresolved.commonName = "Unknown Subject"

        let human = makeRecord(id: "human", latitude: 12, longitude: 45)
        human.scientificName = "Homo sapiens"
        human.commonName = "Human"

        let cat = makeRecord(id: "cat", latitude: 12, longitude: 45)
        cat.scientificName = "Felis catus"
        cat.commonName = "Domestic cat"

        let dogOverride = makeRecord(
            id: "dog-override",
            latitude: 12,
            longitude: 45
        )
        dogOverride.userIdentificationOverride = "Canis lupus familiaris"

        for record in [unresolved, human, cat, dogOverride] {
            #expect(
                ScanThumbnailBackfillCandidate(
                    missingVisualFallbackFor: record
                ) == nil
            )
            #expect(ScanThumbnailBackfillCandidate(record: record) == nil)
        }

        #expect(
            dogOverride.scanThumbnailPresentation.placeholderStyle
                == .unavailableReference(.other)
        )
    }

    @Test("Full extent follows the short arc across the antimeridian")
    func antimeridianExtent() throws {
        let snapshot = PrivateScanMapSnapshot(points: [
            makePoint(id: "east", latitude: 10, longitude: 179),
            makePoint(id: "west", latitude: 12, longitude: -179)
        ])
        let region = try #require(snapshot.fullExtentRegion)

        #expect(region.span.longitudeDelta < 4)
        #expect(abs(abs(region.center.longitude) - 180) < 0.000_001)
        #expect(PrivateScanMapRegion.contains(snapshot.points[0].coordinate, in: region))
        #expect(PrivateScanMapRegion.contains(snapshot.points[1].coordinate, in: region))
    }

    @Test("Initial camera prefers one-shot location and otherwise uses latest mapped scan")
    func initialCameraLocationAndFallback() throws {
        let points = [
            makePoint(
                id: "latest",
                latitude: 12.25,
                longitude: 45.25,
                timestamp: Date(timeIntervalSince1970: 200)
            ),
            makePoint(
                id: "older",
                latitude: 11.75,
                longitude: 44.75,
                timestamp: Date(timeIntervalSince1970: 100)
            )
        ]

        let currentLocationModel = PrivateScanMapViewModel()
        currentLocationModel.update(snapshot: PrivateScanMapSnapshot(points: points))
        currentLocationModel.setInitialCamera(
            currentLocation: CLLocation(latitude: -22.5, longitude: 67.5)
        )
        let currentRegion = try #require(currentLocationModel.visibleRegion)
        #expect(currentRegion.center.latitude == -22.5)
        #expect(currentRegion.center.longitude == 67.5)

        let fallbackModel = PrivateScanMapViewModel()
        fallbackModel.update(snapshot: PrivateScanMapSnapshot(points: points))
        fallbackModel.setInitialCamera(currentLocation: nil)
        let fallbackRegion = try #require(fallbackModel.visibleRegion)
        #expect(fallbackRegion.center.latitude == 12.25)
        #expect(fallbackRegion.center.longitude == 45.25)

        let invalidLocationModel = PrivateScanMapViewModel()
        invalidLocationModel.update(snapshot: PrivateScanMapSnapshot(points: points))
        invalidLocationModel.setInitialCamera(currentLocation: CLLocation(latitude: 0, longitude: 0))
        #expect(invalidLocationModel.visibleRegion?.center.latitude == 12.25)

        let deferredFallbackModel = PrivateScanMapViewModel()
        deferredFallbackModel.setInitialCamera(currentLocation: nil)
        #expect(deferredFallbackModel.visibleRegion == nil)
        deferredFallbackModel.update(snapshot: PrivateScanMapSnapshot(points: points))
        #expect(deferredFallbackModel.visibleRegion?.center.latitude == 12.25)
        #expect(deferredFallbackModel.visibleRegion?.center.longitude == 45.25)
    }

    @Test("Species and media filters compose while media selections use OR")
    func localFiltering() {
        let model = PrivateScanMapViewModel()
        model.update(snapshot: PrivateScanMapSnapshot(points: [
            makePoint(id: "bird-image", latitude: 12, longitude: 45, category: .birds, media: [.image]),
            makePoint(id: "bird-video", latitude: 12.01, longitude: 45.01, category: .birds, media: [.video]),
            makePoint(id: "plant-audio", latitude: 12.02, longitude: 45.02, category: .plants, media: [.audio])
        ]))

        model.toggleCategory(.birds)
        #expect(model.filteredPoints.map(\.id) == ["bird-image", "bird-video"])

        model.toggleMediaFilter(.video)
        #expect(model.filteredPoints.map(\.id) == ["bird-video"])

        model.toggleMediaFilter(.image)
        #expect(Set(model.filteredPoints.map(\.id)) == ["bird-image", "bird-video"])

        model.clearFilters()
        #expect(model.filteredPoints.count == 3)
    }

    @Test("Viewport count uses every filtered point rather than annotation count")
    func viewportCount() async {
        let model = PrivateScanMapViewModel()
        model.update(snapshot: PrivateScanMapSnapshot(points: [
            makePoint(id: "a", latitude: 12, longitude: 45),
            makePoint(id: "b", latitude: 12.000_01, longitude: 45.000_01),
            makePoint(id: "outside", latitude: -24, longitude: -68)
        ]))
        model.updateViewportSize(CGSize(width: 390, height: 700))
        model.updateVisibleRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12, longitude: 45),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        ))
        await model.waitForViewportProjection()

        #expect(model.visiblePoints.count == 2)
        #expect(model.annotations.count == 1)
        guard case .cluster(let cluster) = model.annotations.first else {
            Issue.record("Expected the coincident viewport points to cluster")
            return
        }
        #expect(cluster.count == 2)
    }

    @Test("Navigation suspension retains state and resumes the latest projection")
    func navigationProjectionSuspension() async {
        let model = PrivateScanMapViewModel()
        model.updateViewportSize(CGSize(width: 390, height: 700))
        model.setViewportProjectionSuspended(true)
        model.update(snapshot: PrivateScanMapSnapshot(points: [
            makePoint(id: "retained", latitude: 12, longitude: 45)
        ]))
        model.updateVisibleRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12, longitude: 45),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        ))
        await model.waitForViewportProjection()

        #expect(model.visiblePoints.isEmpty)
        #expect(model.annotations.isEmpty)
        #expect(!model.isProjectingViewport)

        model.setViewportProjectionSuspended(false)
        await model.waitForViewportProjection()

        #expect(model.visiblePoints.map(\.id) == ["retained"])
        #expect(model.annotations.count == 1)
    }

    @Test("Show scans recovers an empty current-location viewport")
    func showScansRecovery() async {
        let model = PrivateScanMapViewModel()
        model.update(snapshot: PrivateScanMapSnapshot(points: [
            makePoint(id: "mapped-a", latitude: 12, longitude: 45),
            makePoint(id: "mapped-b", latitude: 12.2, longitude: 45.2)
        ]))
        model.updateVisibleRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -30, longitude: 120),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        ))
        await model.waitForViewportProjection()
        #expect(model.visiblePoints.isEmpty)

        model.showAllFilteredScans()
        await model.waitForViewportProjection()

        #expect(model.visiblePoints.count == 2)
    }

    @Test("Snapshot updates clear deleted selection and unavailable filters")
    func deletionWhileOpen() {
        let model = PrivateScanMapViewModel()
        let selected = makePoint(
            id: "selected",
            latitude: 12,
            longitude: 45,
            category: .birds,
            media: [.video]
        )
        let remaining = makePoint(
            id: "remaining",
            latitude: 13,
            longitude: 46,
            category: .plants,
            media: [.image]
        )
        model.update(snapshot: PrivateScanMapSnapshot(points: [selected, remaining]))
        model.selectPoint(selected.id)
        model.toggleCategory(.birds)
        model.toggleMediaFilter(.video)

        model.update(snapshot: PrivateScanMapSnapshot(points: [remaining]))

        #expect(model.selectedPointID == nil)
        #expect(model.selectedCategories.isEmpty)
        #expect(model.selectedMediaFilters.isEmpty)
    }

    @Test("Waypoints switch from dots to thumbnails at zoom level 11.5")
    func thumbnailZoomThreshold() {
        let model = PrivateScanMapViewModel()
        model.updateVisibleRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12, longitude: 45),
            span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
        ))
        #expect(!model.showsThumbnailWaypoints)

        model.updateVisibleRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12, longitude: 45),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))
        #expect(model.showsThumbnailWaypoints)
    }

    @Test("Clustering is deterministic at 56 points and bounded for large libraries")
    func deterministicClustering() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12, longitude: 45),
            span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)
        )
        let viewport = CGSize(width: 390, height: 844)
        let points = (0..<5_000).map { index in
            let row = index / 100
            let column = index % 100
            return makePoint(
                id: "large-\(index)",
                latitude: 10.1 + (Double(row) * 0.075),
                longitude: 43.1 + (Double(column) * 0.038)
            )
        }

        let first = PrivateScanMapClusterer.annotations(
            points: points,
            region: region,
            viewportSize: viewport
        )
        let second = PrivateScanMapClusterer.annotations(
            points: Array(points.reversed()),
            region: region,
            viewportSize: viewport
        )

        #expect(first == second)
        #expect(first.count <= 112)
        let representedPointCount = first.reduce(0) { count, annotation in
            switch annotation {
            case .point:
                return count + 1
            case .cluster(let cluster):
                return count + cluster.count
            }
        }
        #expect(representedPointCount == points.count)
    }

    @Test("Collections preview clustering stays deterministic for large libraries")
    func deterministicPreviewClustering() throws {
        let points = (0..<5_000).map { index in
            let row = index / 100
            let column = index % 100
            return PrivateScanMapPreviewPoint(
                id: "preview-large-\(index)",
                latitude: 10.1 + (Double(row) * 0.075),
                longitude: 43.1 + (Double(column) * 0.038)
            )
        }
        let snapshot = PrivateScanMapPreviewSnapshot(points: points)
        let region = try #require(snapshot.fullExtentRegion)
        let viewport = CGSize(width: 390, height: 292.5)

        let first = PrivateScanMapClusterer.previewAnnotations(
            points: snapshot.points,
            region: region,
            viewportSize: viewport
        )
        let second = PrivateScanMapClusterer.previewAnnotations(
            points: Array(snapshot.points.reversed()),
            region: region,
            viewportSize: viewport
        )

        #expect(first == second)
        #expect(first.count <= 63)
        let representedPointCount = first.reduce(0) { count, annotation in
            switch annotation {
            case .point:
                return count + 1
            case .cluster(let cluster):
                return count + cluster.count
            }
        }
        #expect(representedPointCount == points.count)
    }

    @Test("Clustering defers annotations until map layout has a viewport")
    func zeroSizedViewportDefersAnnotations() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12, longitude: 45),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        let interactive = PrivateScanMapClusterer.annotations(
            points: [makePoint(id: "interactive", latitude: 12, longitude: 45)],
            region: region,
            viewportSize: .zero
        )
        let preview = PrivateScanMapClusterer.previewAnnotations(
            points: [
                PrivateScanMapPreviewPoint(
                    id: "preview",
                    latitude: 12,
                    longitude: 45
                )
            ],
            region: region,
            viewportSize: .zero
        )

        #expect(interactive.isEmpty)
        #expect(preview.isEmpty)
    }

    @Test("View model clears annotations when a laid-out viewport collapses")
    func viewportCollapseDefersAnnotations() async {
        let model = PrivateScanMapViewModel()
        model.update(snapshot: PrivateScanMapSnapshot(points: [
            makePoint(id: "interactive", latitude: 12, longitude: 45)
        ]))
        model.updateViewportSize(CGSize(width: 390, height: 844))
        model.updateVisibleRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12, longitude: 45),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        ))
        await model.waitForViewportProjection()
        #expect(!model.annotations.isEmpty)

        model.updateViewportSize(.zero)
        await model.waitForViewportProjection()

        #expect(model.viewportSize == .zero)
        #expect(model.annotations.isEmpty)
    }

    @Test("Coincident clusters stay available for list recovery at maximum zoom")
    func coincidentClusterRecovery() async throws {
        let model = PrivateScanMapViewModel()
        let points = [
            makePoint(id: "same-a", latitude: 12, longitude: 45),
            makePoint(id: "same-b", latitude: 12, longitude: 45)
        ]
        model.update(snapshot: PrivateScanMapSnapshot(points: points))
        model.updateViewportSize(CGSize(width: 390, height: 844))
        model.updateVisibleRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12, longitude: 45),
            span: MKCoordinateSpan(latitudeDelta: 0.000_1, longitudeDelta: 0.000_1)
        ))
        await model.waitForViewportProjection()

        let annotation = try #require(model.annotations.first)
        guard case .cluster(let cluster) = annotation else {
            Issue.record("Expected coincident points to remain clustered")
            return
        }
        #expect(model.focusRegion(for: cluster) == nil)
        #expect(cluster.count == 2)
    }

    @Test("Background index revisions separate content from spatial changes")
    func backgroundIndexRevisions() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema([LocalScanRecord.self]),
            configurations: [configuration]
        )
        let mapped = makeRecord(
            id: "mapped",
            latitude: 12.345_678_901,
            longitude: 45.678_901_234
        )
        let invalid = makeRecord(id: "invalid", latitude: 0, longitude: 0)
        let nonBiological = makeRecord(
            id: "non-biological",
            latitude: 10,
            longitude: 20,
            isBiological: false
        )
        container.mainContext.insert(mapped)
        container.mainContext.insert(invalid)
        container.mainContext.insert(nonBiological)
        try container.mainContext.save()

        let service = PrivateScanMapIndexService(modelContainer: container)
        let initial = try await service.refresh()
        let initialPoint = try #require(initial.interactiveSnapshot.points.first)

        #expect(initial.revision == 1)
        #expect(initial.spatialRevision == 1)
        #expect(initial.interactiveSnapshot.points.count == 1)
        #expect(initialPoint.id == mapped.id)
        #expect(initialPoint.latitude == 12.345_678_901)
        #expect(initialPoint.longitude == 45.678_901_234)

        let unchanged = try await service.refresh()
        #expect(unchanged.revision == initial.revision)
        #expect(unchanged.spatialRevision == initial.spatialRevision)

        mapped.commonName = "Updated presentation"
        try container.mainContext.save()
        let presentationChange = try await service.refresh()
        #expect(presentationChange.revision == initial.revision + 1)
        #expect(presentationChange.spatialRevision == initial.spatialRevision)
        #expect(
            presentationChange.interactiveSnapshot.points.first?.commonName
                == "Updated presentation"
        )

        mapped.gpsLongitude = 46.25
        try container.mainContext.save()
        let coordinateChange = try await service.refresh()
        #expect(coordinateChange.revision == presentationChange.revision + 1)
        #expect(
            coordinateChange.spatialRevision
                == presentationChange.spatialRevision + 1
        )
        #expect(
            coordinateChange.interactiveSnapshot.points.first?.longitude
                == 46.25
        )

        container.mainContext.delete(mapped)
        try container.mainContext.save()
        let deletion = try await service.refresh()
        #expect(deletion.interactiveSnapshot.points.isEmpty)
        #expect(deletion.previewSnapshot.points.isEmpty)
        #expect(deletion.revision == coordinateChange.revision + 1)
        #expect(deletion.spatialRevision == coordinateChange.spatialRevision + 1)
    }

    @Test("Spatial index keeps antimeridian candidates without false positives")
    func spatialIndexAntimeridianCandidates() {
        let index = PrivateScanMapSpatialIndex(points: [
            makePoint(id: "east", latitude: 10, longitude: 179.5),
            makePoint(id: "west", latitude: 10, longitude: -179.5),
            makePoint(id: "far", latitude: 10, longitude: 120)
        ])
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 10, longitude: 180),
            span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)
        )

        #expect(Set(index.candidates(in: region).map(\.id)) == ["east", "west"])
    }

    private func makeRecord(
        id: String,
        latitude: Double?,
        longitude: Double?,
        isBiological: Bool = true,
        taxonomyClass: String? = "aves",
        media: [SerializedMediaItem] = []
    ) -> LocalScanRecord {
        LocalScanRecord(
            id: id,
            speciesId: id,
            scientificName: "Species \(id)",
            commonName: "Scan \(id)",
            timestamp: Date(timeIntervalSince1970: 100),
            capturedMediaJSON: CapturedMediaSnapshot(items: media).jsonString,
            isBiological: isBiological,
            taxonomyKingdom: "animalia",
            taxonomyClass: taxonomyClass,
            gpsLatitude: latitude,
            gpsLongitude: longitude
        )
    }

    private func makePoint(
        id: String,
        latitude: Double,
        longitude: Double,
        timestamp: Date = Date(timeIntervalSince1970: 100),
        category: SearchCategoryBucket = .birds,
        media: Set<ScanMediaFilter> = [.image]
    ) -> PrivateScanMapPoint {
        PrivateScanMapPoint(
            id: id,
            latitude: latitude,
            longitude: longitude,
            commonName: "Scan \(id)",
            scientificName: "Species \(id)",
            timestamp: timestamp,
            locationName: nil,
            category: category,
            mediaFilters: media,
            thumbnail: ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: nil,
                audioPath: nil,
                hasVideo: media.contains(.video),
                hasAudio: media.contains(.audio),
                placeholderStyle: .archived
            )
        )
    }
}
