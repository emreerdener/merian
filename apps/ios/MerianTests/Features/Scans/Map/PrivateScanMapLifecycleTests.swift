import CoreLocation
import Foundation
import MapKit
@testable import Merian
import SwiftData
import Testing
import UIKit

@Suite("Private Scan Map lifecycle")
@MainActor
struct PrivateScanMapLifecycleTests {
    @Test("A refresh requested during a failed attempt is not lost")
    func failedRefreshDrainsPendingGeneration() async {
        let expected = makeIndexSnapshot(id: "fresh", revision: 2)
        let service = FailingThenSuccessfulMapIndexService(success: expected)
        let store = PrivateScanMapStore(indexService: service)

        let refreshTask = Task { await store.refresh() }
        await service.waitUntilFirstRequestStarts()
        store.requestRefresh()
        await service.failFirstRequest()
        await refreshTask.value

        #expect(await service.requestCount == 2)
        #expect(store.snapshot == expected)
    }

    @Test("Sensitive reset empties state and rejects stale refresh completion")
    func sensitiveResetFencesRefresh() async {
        let initial = makeIndexSnapshot(id: "initial", revision: 1)
        let stale = makeIndexSnapshot(id: "stale", revision: 2)
        let service = BlockingSecondMapIndexService(
            initial: initial,
            stale: stale
        )
        let store = PrivateScanMapStore(indexService: service)

        await store.refresh()
        #expect(store.snapshot == initial)

        let refreshTask = Task { await store.refresh() }
        await service.waitUntilSecondRequestStarts()
        store.resetSensitiveState()

        #expect(store.snapshot == .empty)

        await service.releaseSecondRequest()
        await refreshTask.value
        await service.waitUntilReset()

        #expect(store.snapshot == .empty)
        #expect(await service.resetCount == 1)
    }

    @Test("Sensitive reset clears view-owned map presentation state")
    func sensitiveResetClearsViewModel() async {
        let snapshot = makeIndexSnapshot(
            id: "private-location",
            revision: 1
        ).interactiveSnapshot
        let viewModel = PrivateScanMapViewModel()

        viewModel.update(snapshot: snapshot)
        viewModel.updateViewportSize(CGSize(width: 320, height: 640))
        viewModel.updateVisibleRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12, longitude: 45),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        ))
        viewModel.toggleCategory(.birds)
        viewModel.toggleMediaFilter(.image)
        viewModel.selectPoint("private-location")
        viewModel.setInitialCamera(
            currentLocation: CLLocation(latitude: 12, longitude: 45)
        )

        viewModel.resetSensitiveState()
        await Task.yield()

        #expect(viewModel.points.isEmpty)
        #expect(viewModel.filteredPoints.isEmpty)
        #expect(viewModel.visiblePoints.isEmpty)
        #expect(viewModel.annotations.isEmpty)
        #expect(viewModel.visibleRegion == nil)
        #expect(viewModel.selectedPointID == nil)
        #expect(viewModel.selectedCategories.isEmpty)
        #expect(viewModel.selectedMediaFilters.isEmpty)
        #expect(!viewModel.didSetInitialCamera)
        #expect(!viewModel.isProjectingViewport)
    }

    @Test("Sensitive reset rejects an in-flight preview")
    func sensitiveResetFencesPreview() async {
        let renderer = BlockingMapPreviewRenderer()
        let store = PrivateScanMapStore(previewRenderer: renderer)

        let previewTask = Task {
            await store.previewImage(
                size: CGSize(width: 120, height: 90),
                displayScale: 2,
                userInterfaceStyle: .light
            )
        }
        await renderer.waitUntilRequestStarts()
        store.resetSensitiveState()

        await renderer.waitUntilReset()
        #expect(await previewTask.value == nil)
        #expect(await renderer.resetCount == 1)
    }

    @Test("Cancelled startup never requests current location")
    func cancelledStartupSkipsLocation() async {
        let refreshGate = MapTestContinuationGate()
        var didUpdateSnapshot = false
        var locationRequestCount = 0
        var didSetInitialCamera = false

        let startupTask = Task { @MainActor in
            await PrivateScanMapStartupSequence.run(
                refresh: {
                    await refreshGate.wait()
                },
                updateSnapshot: {
                    didUpdateSnapshot = true
                },
                needsInitialCamera: { true },
                isCurrent: { true },
                requestCurrentLocation: {
                    locationRequestCount += 1
                    return CLLocation(latitude: 12, longitude: 45)
                },
                setInitialCamera: { _ in
                    didSetInitialCamera = true
                }
            )
        }

        await refreshGate.waitUntilEntered()
        startupTask.cancel()
        await refreshGate.release()
        await startupTask.value

        #expect(!didUpdateSnapshot)
        #expect(locationRequestCount == 0)
        #expect(!didSetInitialCamera)
    }

    @Test("A reset during startup location lookup rejects the stale result")
    func resetDuringStartupLocationRejectsResult() async {
        let locationGate = MapTestContinuationGate()
        var isCurrent = true
        var didUpdateSnapshot = false
        var didSetInitialCamera = false

        let startupTask = Task { @MainActor in
            await PrivateScanMapStartupSequence.run(
                refresh: {},
                updateSnapshot: {
                    didUpdateSnapshot = true
                },
                needsInitialCamera: { true },
                isCurrent: { isCurrent },
                requestCurrentLocation: {
                    await locationGate.wait()
                    return CLLocation(latitude: 12, longitude: 45)
                },
                setInitialCamera: { _ in
                    didSetInitialCamera = true
                }
            )
        }

        await locationGate.waitUntilEntered()
        isCurrent = false
        await locationGate.release()
        await startupTask.value

        #expect(didUpdateSnapshot)
        #expect(!didSetInitialCamera)
    }

    @Test("A reset invalidates a manual current-location request")
    func resetInvalidatesManualLocationRequest() async {
        let locationGate = MapTestContinuationGate()
        var isCurrent = true

        let locationTask = Task { @MainActor in
            await PrivateScanMapLocationRequestSequence.run(
                isCurrent: { isCurrent },
                requestCurrentLocation: {
                    await locationGate.wait()
                    return CLLocation(latitude: 12, longitude: 45)
                }
            )
        }

        await locationGate.waitUntilEntered()
        isCurrent = false
        await locationGate.release()

        switch await locationTask.value {
        case .invalidated:
            break
        case .location, .unavailable:
            Issue.record("Expected the stale location request to be invalidated")
        }
    }

    @Test("A configured store can recover durable state after reset")
    func configuredStoreRecoversAfterReset() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema([LocalScanRecord.self]),
            configurations: [configuration]
        )
        let record = LocalScanRecord(
            id: "durable-after-reset",
            speciesId: "durable-after-reset",
            scientificName: "Corvus brachyrhynchos",
            commonName: "American Crow",
            timestamp: Date(timeIntervalSince1970: 100),
            capturedMediaJSON: CapturedMediaSnapshot(items: []).jsonString,
            isBiological: true,
            taxonomyKingdom: "animalia",
            taxonomyClass: "aves",
            gpsLatitude: 12,
            gpsLongitude: 45
        )
        container.mainContext.insert(record)
        try container.mainContext.save()

        let eventStream = AppEventPublisher()
        let store = PrivateScanMapStore()
        store.configure(
            modelContainer: container,
            eventStream: eventStream
        )
        await store.refresh()
        #expect(
            store.snapshot.interactiveSnapshot.points.map(\.id)
                == ["durable-after-reset"]
        )

        store.resetSensitiveState()
        #expect(store.snapshot == .empty)

        eventStream.send(.scanLibraryChanged)
        await store.refresh()

        #expect(
            store.snapshot.interactiveSnapshot.points.map(\.id)
                == ["durable-after-reset"]
        )
    }

    private func makeIndexSnapshot(
        id: String,
        revision: UInt64
    ) -> PrivateScanMapIndexSnapshot {
        let point = PrivateScanMapPoint(
            id: id,
            latitude: 12,
            longitude: 45,
            commonName: "Scan \(id)",
            scientificName: "Species \(id)",
            timestamp: Date(timeIntervalSince1970: 100),
            locationName: nil,
            category: .birds,
            mediaFilters: [.image],
            thumbnail: ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: nil,
                audioPath: nil,
                hasVideo: false,
                hasAudio: false,
                placeholderStyle: .archived
            )
        )
        return PrivateScanMapIndexSnapshot(
            revision: revision,
            spatialRevision: revision,
            previewSnapshot: PrivateScanMapPreviewSnapshot(points: [
                PrivateScanMapPreviewPoint(
                    id: id,
                    latitude: point.latitude,
                    longitude: point.longitude
                )
            ]),
            interactiveSnapshot: PrivateScanMapSnapshot(
                points: [point],
                revision: revision
            )
        )
    }
}

private enum MapIndexTestError: Error {
    case expectedFailure
}

private actor FailingThenSuccessfulMapIndexService: PrivateScanMapIndexServing {
    private let success: PrivateScanMapIndexSnapshot
    private var firstRequestStarted = false
    private var firstRequestStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstRequestRelease: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0

    init(success: PrivateScanMapIndexSnapshot) {
        self.success = success
    }

    func refresh() async throws -> PrivateScanMapIndexSnapshot {
        requestCount += 1
        guard requestCount == 1 else { return success }

        firstRequestStarted = true
        firstRequestStartWaiters.forEach { $0.resume() }
        firstRequestStartWaiters.removeAll()
        await withCheckedContinuation { continuation in
            firstRequestRelease = continuation
        }
        throw MapIndexTestError.expectedFailure
    }

    func waitUntilFirstRequestStarts() async {
        guard !firstRequestStarted else { return }
        await withCheckedContinuation { continuation in
            firstRequestStartWaiters.append(continuation)
        }
    }

    func failFirstRequest() {
        firstRequestRelease?.resume()
        firstRequestRelease = nil
    }
}

private actor BlockingSecondMapIndexService: PrivateScanMapIndexServing {
    private let initial: PrivateScanMapIndexSnapshot
    private let stale: PrivateScanMapIndexSnapshot
    private var secondRequestStarted = false
    private var secondRequestStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var secondRequestRelease: CheckedContinuation<Void, Never>?
    private var resetWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requestCount = 0
    private(set) var resetCount = 0

    init(
        initial: PrivateScanMapIndexSnapshot,
        stale: PrivateScanMapIndexSnapshot
    ) {
        self.initial = initial
        self.stale = stale
    }

    func refresh() async throws -> PrivateScanMapIndexSnapshot {
        requestCount += 1
        guard requestCount > 1 else { return initial }

        secondRequestStarted = true
        secondRequestStartWaiters.forEach { $0.resume() }
        secondRequestStartWaiters.removeAll()
        await withCheckedContinuation { continuation in
            secondRequestRelease = continuation
        }
        return stale
    }

    func reset() {
        resetCount += 1
        resetWaiters.forEach { $0.resume() }
        resetWaiters.removeAll()
    }

    func waitUntilSecondRequestStarts() async {
        guard !secondRequestStarted else { return }
        await withCheckedContinuation { continuation in
            secondRequestStartWaiters.append(continuation)
        }
    }

    func releaseSecondRequest() {
        secondRequestRelease?.resume()
        secondRequestRelease = nil
    }

    func waitUntilReset() async {
        guard resetCount == 0 else { return }
        await withCheckedContinuation { continuation in
            resetWaiters.append(continuation)
        }
    }
}

private actor BlockingMapPreviewRenderer: PrivateScanMapPreviewRendering {
    private var requestStarted = false
    private var requestStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var requestRelease: CheckedContinuation<Void, Never>?
    private var resetWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var resetCount = 0

    func image(
        snapshot _: PrivateScanMapPreviewSnapshot,
        revision _: UInt64,
        size _: CGSize,
        displayScale _: CGFloat,
        userInterfaceStyle _: UIUserInterfaceStyle
    ) async -> UIImage? {
        requestStarted = true
        requestStartWaiters.forEach { $0.resume() }
        requestStartWaiters.removeAll()
        await withCheckedContinuation { continuation in
            requestRelease = continuation
        }
        return UIImage()
    }

    func reset() {
        resetCount += 1
        requestRelease?.resume()
        requestRelease = nil
        resetWaiters.forEach { $0.resume() }
        resetWaiters.removeAll()
    }

    func waitUntilRequestStarts() async {
        guard !requestStarted else { return }
        await withCheckedContinuation { continuation in
            requestStartWaiters.append(continuation)
        }
    }

    func waitUntilReset() async {
        guard resetCount == 0 else { return }
        await withCheckedContinuation { continuation in
            resetWaiters.append(continuation)
        }
    }
}

private actor MapTestContinuationGate {
    private var isEntered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        isEntered = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters.removeAll()
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !isEntered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
