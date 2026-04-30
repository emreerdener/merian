import Testing
import SwiftData
import Foundation
@testable import Merian

@MainActor
struct OfflineQueueManagerTests {

    private enum ExpectedSerializedMedia {
        case image(String)
        case audio(String)
        case description(String)
    }

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

    private func makeTempAudioFilename(prefix: String = "queued_audio") throws -> String {
        let filename = "\(prefix)_\(UUID().uuidString).wav"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try Data(repeating: 0x21, count: 64).write(to: url)
        return filename
    }

    private func assertSerializedItems(
        _ items: [SerializedMediaItem],
        match expected: [ExpectedSerializedMedia]
    ) {
        #expect(items.count == expected.count)

        for (actual, expectation) in zip(items, expected) {
            switch (actual, expectation) {
            case (.image(let reference), .image(let expectedPath)):
                #expect(reference == expectedPath)
            case (.audio(let reference), .audio(let expectedPath)):
                #expect(reference == expectedPath)
            case (.description(let context), .description(let expectedText)):
                #expect(context.freeText == expectedText)
            default:
                Issue.record("Queued serialized media kind mismatch: \(String(describing: actual))")
            }
        }
    }

    private func cleanupSerializedItems(_ items: [SerializedMediaItem]) {
        for item in items {
            switch item {
            case .image(let reference), .audio(let reference):
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(reference.serializedPath))
            case .description:
                break
            }
        }
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
                if case .image(let reference) = item {
                    try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(reference.serializedPath))
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

    @Test func testEnqueueCapturePreservesMixedTimelineOrder() async throws {
        let ctx = try createIsolatedContext()
        let scanId = UUID().uuidString
        let imageData = "queued_image".data(using: .utf8)!
        let audioFilename = try makeTempAudioFilename()

        OfflineQueueManager.shared.enqueueCapture(
            imageDatas: [imageData],
            audioFilePaths: [audioFilename],
            telemetry: dummyTelemetry,
            scanId: scanId,
            mediaTimeline: [.audio(audioFilename), .image(index: 0)]
        )

        try await Task.sleep(nanoseconds: 500_000_000)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        let fetched = try #require(ctx.fetch(descriptor).first)
        let capturedMediaJSON = try #require(fetched.capturedMediaJSON)
        let items = try #require(MediaJSONParser.serializedItems(jsonString: capturedMediaJSON))

        #expect(items.count == 2)

        if case .audio(let reference) = items[0] {
            #expect(reference == audioFilename, "Queued capture must preserve the audio-first staging order")
        } else {
            Issue.record("Expected queued capture to serialize audio first")
        }

        if case .image = items[1] {
            // expected
        } else {
            Issue.record("Expected queued capture to serialize the image second")
        }

        for item in items {
            switch item {
            case .image(let reference):
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(reference.serializedPath))
            case .audio(let reference):
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(reference.serializedPath))
            case .description:
                break
            }
        }
    }

    @Test func testEnqueueNonVisualCaptureSupportsAllowedCombinationMatrix() async throws {
        let ctx = try createIsolatedContext()

        let descriptionA = ObservationContext(freeText: "queued description A")
        let descriptionB = ObservationContext(freeText: "queued description B")
        let audioOnly = try makeTempAudioFilename(prefix: "nonvisual_audio_only")
        let firstAudio = try makeTempAudioFilename(prefix: "nonvisual_audio_one")
        let secondAudio = try makeTempAudioFilename(prefix: "nonvisual_audio_two")
        let audioWithDescription = try makeTempAudioFilename(prefix: "nonvisual_audio_description")

        struct Scenario {
            let scanId: String
            let audioFileNames: [String]
            let observationContexts: [ObservationContext]
            let mediaTimeline: [CaptureSubmissionMediaItem]
            let expected: [ExpectedSerializedMedia]
        }

        let scenarios: [Scenario] = [
            .init(
                scanId: "queued_nonvisual_audio_only",
                audioFileNames: [audioOnly],
                observationContexts: [],
                mediaTimeline: [.audio(audioOnly)],
                expected: [.audio(audioOnly)]
            ),
            .init(
                scanId: "queued_nonvisual_audio_audio",
                audioFileNames: [firstAudio, secondAudio],
                observationContexts: [],
                mediaTimeline: [.audio(firstAudio), .audio(secondAudio)],
                expected: [.audio(firstAudio), .audio(secondAudio)]
            ),
            .init(
                scanId: "queued_nonvisual_audio_description",
                audioFileNames: [audioWithDescription],
                observationContexts: [descriptionA],
                mediaTimeline: [.audio(audioWithDescription), .description(descriptionA)],
                expected: [.audio(audioWithDescription), .description(descriptionA.freeText)]
            ),
            .init(
                scanId: "queued_nonvisual_description_only",
                audioFileNames: [],
                observationContexts: [descriptionA],
                mediaTimeline: [.description(descriptionA)],
                expected: [.description(descriptionA.freeText)]
            ),
            .init(
                scanId: "queued_nonvisual_description_description",
                audioFileNames: [],
                observationContexts: [descriptionA, descriptionB],
                mediaTimeline: [.description(descriptionA), .description(descriptionB)],
                expected: [.description(descriptionA.freeText), .description(descriptionB.freeText)]
            )
        ]

        for scenario in scenarios {
            let enqueued = OfflineQueueManager.shared.enqueueNonVisualCapture(
                audioFileNames: scenario.audioFileNames,
                observationContexts: scenario.observationContexts,
                mediaTimeline: scenario.mediaTimeline,
                telemetry: dummyTelemetry,
                scanId: scenario.scanId
            )
            #expect(enqueued)

            let scanId = scenario.scanId
            let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            let fetched = try #require(ctx.fetch(descriptor).first)
            #expect(fetched.queueState == .staged)

            let capturedMediaJSON = try #require(fetched.capturedMediaJSON)
            let items = try #require(MediaJSONParser.serializedItems(jsonString: capturedMediaJSON))
            assertSerializedItems(items, match: scenario.expected)
            cleanupSerializedItems(items)
        }
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

    @Test func testFinishCollectionSyncAttemptLeavesPendingFlagWhenSyncFails() async {
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
        manager.collectionSyncRevision = 21
        manager.isCollectionSyncing = true

        manager.finishCollectionSyncAttempt(success: false, capturedRevision: 21)

        #expect(manager.isCollectionSyncing == false, "A failed collection sync must still release the latch")
        #expect(manager.collectionSyncTask == nil, "A failed collection sync must clear the in-flight task handle")
        #expect(
            UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync),
            "A failed collection sync must keep the pending bit set so a later retry can pick it up"
        )
    }
}
