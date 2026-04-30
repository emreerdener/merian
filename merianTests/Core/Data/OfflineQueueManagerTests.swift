import Testing
import SwiftData
import Foundation
@testable import Merian

@MainActor
struct OfflineQueueManagerTests {

    @MainActor
    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = ModelContext(container)
        OfflineQueueManager.shared.modelContext = context
        return context
    }

    private var dummyTelemetry: CaptureTelemetry {
        CaptureTelemetry(
            subjectDistanceInMeters: 2.5,
            gpsLatitude: 37.7749,
            gpsLongitude: -122.4194,
            gpsElevation: 10,
            locationName: "San Francisco",
            weatherCondition: "Clear",
            weatherTemperatureF: 65,
            timeOfDay: "Morning",
            timestamp: "2026-04-24T00:00:00Z",
            zoomFactor: 1.0
        )
    }

    @Test func testEnqueueCapture_WithValidData_PersistsQueuedScan() async throws {
        let ctx = try createIsolatedContext()
        let scanId = UUID().uuidString
        let imageData = "dummy_image".data(using: .utf8)!

        OfflineQueueManager.shared.enqueueCapture(
            imageDatas: [imageData],
            telemetry: dummyTelemetry,
            scanId: scanId
        )

        // Wait a brief moment for the BackgroundTaskWrapper to complete the disk write
        // and dispatch to the MainActor for insertion.
        try await Task.sleep(nanoseconds: 500_000_000)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched != nil, "Scan must be inserted into the context")
        #expect(
            fetched?.queueState == .pending || fetched?.queueState == .uploading,
            "New capture scans must be persisted and may advance to .uploading immediately when sync kicks off"
        )
        #expect(OfflineQueueManager.shared.unsyncedItemsCount == 1, "Unsynced count must update")

        // Clean up disk footprint
        if let jsonStr = fetched?.capturedMediaJSON,
           let jsonData = jsonStr.data(using: .utf8),
           let items = try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData) {
            for item in items {
                if case .image(let path) = item {
                    try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(path))
                }
            }
        }
    }

    @Test func testEnqueueDescribe_InsertsStagedScan() async throws {
        let ctx = try createIsolatedContext()
        let scanId = UUID().uuidString
        let context = ObservationContext(freeText: "Red small forest mushroom")

        OfflineQueueManager.shared.enqueueDescribe(
            observationContext: context,
            telemetry: dummyTelemetry,
            scanId: scanId
        )

        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched != nil, "Describe scan must be inserted into the context")
        #expect(fetched?.queueState == .staged, "Describe scans must start in .staged state because they bypass R2 uploads")
    }

    @Test func testSoftDeleteQueuedScan_TransitionsToFailedState() async throws {
        let ctx = try createIsolatedContext()
        let scanId = UUID().uuidString

        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .pending
        )
        ctx.insert(scan)
        try ctx.save()

        OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.queueState == .failed, "Scan must transition to failed state")
    }

    @Test func testDeleteQueuedScan_RemovesDatabaseRecord() async throws {
        let ctx = try createIsolatedContext()
        let scanId = UUID().uuidString

        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .pending
        )
        ctx.insert(scan)
        try ctx.save()

        await OfflineQueueManager.shared.deleteQueuedScan(scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched == nil, "Scan record must be deleted from the context")
    }

    @Test func testPurgeSoftDeletedRecords_RemovesFailedScans() async throws {
        let ctx = try createIsolatedContext()

        let failedScan = OfflineQueuedScan(id: UUID().uuidString, timestamp: Date(), scanState: .failed)
        let pendingScan = OfflineQueuedScan(id: UUID().uuidString, timestamp: Date(), scanState: .pending)

        ctx.insert(failedScan)
        ctx.insert(pendingScan)
        try ctx.save()

        OfflineQueueManager.shared.purgeSoftDeletedRecords()

        let failedRaw = ScanQueueState.failed.rawValue
        let failedDescriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.scanStateRaw == failedRaw })
        let remainingFailed = try ctx.fetch(failedDescriptor)
        #expect(remainingFailed.isEmpty, "All failed scans must be purged")

        let pendingRaw = ScanQueueState.pending.rawValue
        let pendingDescriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.scanStateRaw == pendingRaw })
        let remainingPending = try ctx.fetch(pendingDescriptor)
        #expect(remainingPending.count == 1, "Pending scans must not be affected by purge")
    }

    @Test func testFlushOfflineQueuedScan_RemovesRecordFromMainContext() async throws {
        let ctx = try createIsolatedContext()
        let scanId = UUID().uuidString

        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .pending
        )
        ctx.insert(scan)
        try ctx.save()

        OfflineQueueManager.shared.flushOfflineQueuedScan(scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched == nil, "Scan must be flushed and deleted from the main context")
    }

    @Test func testFinishCollectionSyncAttemptLeavesPendingFlagForNewerCollectionMutation() async {
        let manager = OfflineQueueManager.shared
        let originalRevision = manager.collectionSyncRevision
        let originalSyncing = manager.isCollectionSyncing
        let originalTask = manager.collectionSyncTask
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        defer {
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
        manager.collectionSyncRevision = 8
        manager.isCollectionSyncing = true

        // Simulate a fresh local edit landing while revision 7 was in flight.
        manager.finishCollectionSyncAttempt(success: true, capturedRevision: 7)

        #expect(manager.isCollectionSyncing == false, "Completion must always release the collection sync latch")
        #expect(manager.collectionSyncTask == nil, "Completion must clear the in-flight collection sync task handle")
        #expect(
            UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync),
            "An older successful collection sync must not clear a newer pending local mutation"
        )
    }

    @Test func testFinishCollectionSyncAttemptClearsPendingFlagWhenNoNewerMutationExists() async {
        let manager = OfflineQueueManager.shared
        let originalRevision = manager.collectionSyncRevision
        let originalSyncing = manager.isCollectionSyncing
        let originalTask = manager.collectionSyncTask
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        defer {
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
        manager.collectionSyncRevision = 12
        manager.isCollectionSyncing = true

        manager.finishCollectionSyncAttempt(success: true, capturedRevision: 12)

        #expect(
            !UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync),
            "A successful collection sync may clear the pending bit only when no newer local collection change exists"
        )
    }
}
