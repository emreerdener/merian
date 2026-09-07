import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite(
    "Capture Admission Tests",
    .serialized,
    .sharedProcessState(.offlineQueueManager)
)
@MainActor
struct CaptureAdmissionTests {
    @MainActor
    private struct ManagerSnapshot {
        let modelContext: ModelContext?
        let isOnline: Bool
        let unsyncedItemsCount: Int

        init(_ manager: OfflineQueueManager) {
            modelContext = manager.modelContext
            isOnline = manager.isOnline
            unsyncedItemsCount = manager.unsyncedItemsCount
        }

        func restore(_ manager: OfflineQueueManager) {
            manager.modelContext = modelContext
            manager.isOnline = isOnline
            manager.unsyncedItemsCount = unsyncedItemsCount
        }
    }

    private enum ExpectedSerializedMedia {
        case image(String)
        case audio(String)
        case description(String)
    }

    @Test func testEnqueueCapture_WithValidData_PersistsQueuedScan() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let manager = OfflineQueueManager.shared
        let snapshot = ManagerSnapshot(manager)
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = false
        let scanId = UUID().uuidString
        defer {
            manager.deferredLiveUploadScanIds.remove(scanId)
            snapshot.restore(manager)
        }

        let didQueue = await withCheckedContinuation { continuation in
            manager.enqueueCapture(
                imageDatas: [Data("dummy_image".utf8)],
                telemetry: dummyTelemetry,
                scanId: scanId,
                startSyncImmediately: false,
                onQueued: { continuation.resume(returning: $0) }
            )
        }

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let fetched = try context.fetch(descriptor).first
        #expect(didQueue)
        #expect(fetched != nil, "Scan must be inserted into the context")
        #expect(
            fetched?.queueState == .pending,
            "The persisted fixture must not start an unowned background upload"
        )
        #expect(manager.unsyncedItemsCount == 1, "Unsynced count must update")

        if let json = fetched?.capturedMediaJSON,
           let items = MediaJSONParser.serializedItems(jsonString: json) {
            cleanupSerializedItems(items)
        }
    }

    @Test func testEnqueueCaptureCanHoldAndIdempotentlyReleaseLiveUpload() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let manager = OfflineQueueManager.shared
        let snapshot = ManagerSnapshot(manager)
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = false
        let scanId = UUID().uuidString
        defer {
            manager.deferredLiveUploadScanIds.remove(scanId)
            snapshot.restore(manager)
        }

        let didQueue = await withCheckedContinuation { continuation in
            manager.enqueueCapture(
                imageDatas: [Data("deferred_live_image".utf8)],
                telemetry: dummyTelemetry,
                scanId: scanId,
                startSyncImmediately: false,
                onQueued: { continuation.resume(returning: $0) }
            )
        }

        #expect(didQueue)
        #expect(manager.deferredLiveUploadScanIds.contains(scanId))
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let fetched = try #require(context.fetch(descriptor).first)
        #expect(fetched.queueState == .pending)

        manager.releaseDeferredLiveUpload(
            scanId: scanId,
            reason: "unit_test_body_sent"
        )
        #expect(!manager.deferredLiveUploadScanIds.contains(scanId))
        manager.releaseDeferredLiveUpload(
            scanId: scanId,
            reason: "unit_test_duplicate_release"
        )
        #expect(!manager.deferredLiveUploadScanIds.contains(scanId))

        if let json = fetched.capturedMediaJSON,
           let items = MediaJSONParser.serializedItems(jsonString: json) {
            cleanupSerializedItems(items)
        }
    }

    @Test func testEnqueueDescribe_InsertsStagedScan() throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let manager = OfflineQueueManager.shared
        let snapshot = ManagerSnapshot(manager)
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = false
        let scanId = UUID().uuidString
        defer { snapshot.restore(manager) }

        manager.enqueueDescribe(
            observationContext: ObservationContext(
                freeText: "Red small forest mushroom"
            ),
            telemetry: dummyTelemetry,
            scanId: scanId
        )

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let fetched = try context.fetch(descriptor).first
        #expect(fetched != nil, "Describe scan must be inserted into the context")
        #expect(
            fetched?.queueState == .staged,
            "Describe scans must start staged because they bypass media upload"
        )
    }

    @Test func testEnqueueCapturePreservesMixedTimelineOrder() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let manager = OfflineQueueManager.shared
        let snapshot = ManagerSnapshot(manager)
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = false
        let scanId = UUID().uuidString
        let audioFilename = try makeTempAudioFilename()
        defer {
            manager.deferredLiveUploadScanIds.remove(scanId)
            snapshot.restore(manager)
        }

        let didQueue = await withCheckedContinuation { continuation in
            manager.enqueueCapture(
                imageDatas: [Data("queued_image".utf8)],
                audioFilePaths: [audioFilename],
                telemetry: dummyTelemetry,
                scanId: scanId,
                mediaTimeline: [.audio(audioFilename), .image(index: 0)],
                startSyncImmediately: false,
                onQueued: { continuation.resume(returning: $0) }
            )
        }

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let fetched = try #require(context.fetch(descriptor).first)
        let capturedMediaJSON = try #require(fetched.capturedMediaJSON)
        let items = try #require(
            MediaJSONParser.serializedItems(jsonString: capturedMediaJSON)
        )
        defer { cleanupSerializedItems(items) }

        #expect(didQueue)
        #expect(items.count == 2)
        #expect(fetched.capturedMediaEntries?.count == items.count)
        #expect(fetched.serializedCapturedMediaItems == items)

        if case .audio(let reference) = items[0] {
            #expect(reference == audioFilename)
        } else {
            Issue.record("Expected queued capture to serialize audio first")
        }

        if case .image = items[1] {
            // Expected.
        } else {
            Issue.record("Expected queued capture to serialize the image second")
        }
    }

    @Test func testEnqueueCaptureSeparatesDisplayMediaFromInferenceFrames() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let manager = OfflineQueueManager.shared
        let snapshot = ManagerSnapshot(manager)
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = false
        let scanId = UUID().uuidString
        let videoFilename = try makeTempVideoFilename()
        defer {
            manager.deferredLiveUploadScanIds.remove(scanId)
            snapshot.restore(manager)
        }

        let didQueue = await withCheckedContinuation { continuation in
            manager.enqueueCapture(
                imageDatas: [
                    Data("video_frame_0".utf8),
                    Data("video_frame_1".utf8),
                    Data("still_inference".utf8)
                ],
                displayImageDatas: [
                    Data("video_cover".utf8),
                    Data("still_display".utf8)
                ],
                videoFilePaths: [videoFilename],
                telemetry: dummyTelemetry,
                scanId: scanId,
                mediaTimeline: [
                    .video(videoFilename, posterImageIndex: 0),
                    .image(index: 1)
                ],
                visualMediaItems: [
                    .videoFrame(clipIndex: 0, frameIndex: 0),
                    .videoFrame(clipIndex: 0, frameIndex: 1),
                    .image(
                        sourceIndex: 0,
                        focusRegion: NormalizedImageFocusRegion(
                            x: 0.1,
                            y: 0.2,
                            width: 0.5,
                            height: 0.4
                        )
                    )
                ],
                startSyncImmediately: false,
                onQueued: { continuation.resume(returning: $0) }
            )
        }

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let fetched = try #require(context.fetch(descriptor).first)
        let inferenceImagePaths = try #require(fetched.inferenceImagePaths)
        let capturedMediaJSON = try #require(fetched.capturedMediaJSON)
        let items = try #require(
            MediaJSONParser.serializedItems(jsonString: capturedMediaJSON)
        )
        let visualMediaItemsJSON = try #require(fetched.visualMediaItemsJSON)
        let visualMediaItemsData = try #require(
            visualMediaItemsJSON.data(using: .utf8)
        )
        let visualMediaItems = try JSONDecoder().decode(
            [IdentifyVisualMediaItem].self,
            from: visualMediaItemsData
        )
        defer {
            cleanupSerializedItems(items)
            for path in inferenceImagePaths {
                try? FileManager.default.removeItem(
                    at: URL.documentsDirectory.appendingPathComponent(path)
                )
            }
        }

        #expect(didQueue)
        #expect(inferenceImagePaths.count == 3)
        #expect(visualMediaItems.count == inferenceImagePaths.count)
        #expect(visualMediaItems[2].focusRegion == NormalizedImageFocusRegion(
            x: 0.1,
            y: 0.2,
            width: 0.5,
            height: 0.4
        ))
        #expect(items.count == 2)

        guard case .video(let videoReference) = items[0] else {
            Issue.record("Expected queued mixed capture to serialize the video first")
            return
        }
        let thumbnailPath = try #require(
            videoReference.thumbnail?.serializedPath
        )
        #expect(!inferenceImagePaths.contains(thumbnailPath))

        guard case .image(let imageReference) = items[1] else {
            Issue.record("Expected queued mixed capture to serialize the display image second")
            return
        }
        #expect(!inferenceImagePaths.contains(imageReference.serializedPath))
    }

    @Test func testEnqueueNonVisualCaptureSupportsAllowedCombinationMatrix() throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let manager = OfflineQueueManager.shared
        let snapshot = ManagerSnapshot(manager)
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = false
        defer { snapshot.restore(manager) }

        let descriptionA = ObservationContext(freeText: "queued description A")
        let descriptionB = ObservationContext(freeText: "queued description B")
        let audioOnly = try makeTempAudioFilename(
            prefix: "nonvisual_audio_only"
        )
        let firstAudio = try makeTempAudioFilename(
            prefix: "nonvisual_audio_one"
        )
        let secondAudio = try makeTempAudioFilename(
            prefix: "nonvisual_audio_two"
        )
        let audioWithDescription = try makeTempAudioFilename(
            prefix: "nonvisual_audio_description"
        )

        struct Scenario {
            let scanId: String
            let audioFileNames: [String]
            let observationContexts: [ObservationContext]
            let mediaTimeline: [CaptureSubmissionMediaItem]
            let expectedQueueState: ScanQueueState
            let expected: [ExpectedSerializedMedia]
        }

        let scenarios: [Scenario] = [
            .init(
                scanId: "queued_nonvisual_audio_only",
                audioFileNames: [audioOnly],
                observationContexts: [],
                mediaTimeline: [.audio(audioOnly)],
                expectedQueueState: .pending,
                expected: [.audio(audioOnly)]
            ),
            .init(
                scanId: "queued_nonvisual_audio_audio",
                audioFileNames: [firstAudio, secondAudio],
                observationContexts: [],
                mediaTimeline: [.audio(firstAudio), .audio(secondAudio)],
                expectedQueueState: .pending,
                expected: [.audio(firstAudio), .audio(secondAudio)]
            ),
            .init(
                scanId: "queued_nonvisual_audio_description",
                audioFileNames: [audioWithDescription],
                observationContexts: [descriptionA],
                mediaTimeline: [
                    .audio(audioWithDescription),
                    .description(descriptionA)
                ],
                expectedQueueState: .pending,
                expected: [
                    .audio(audioWithDescription),
                    .description(descriptionA.freeText)
                ]
            ),
            .init(
                scanId: "queued_nonvisual_description_only",
                audioFileNames: [],
                observationContexts: [descriptionA],
                mediaTimeline: [.description(descriptionA)],
                expectedQueueState: .staged,
                expected: [.description(descriptionA.freeText)]
            ),
            .init(
                scanId: "queued_nonvisual_description_description",
                audioFileNames: [],
                observationContexts: [descriptionA, descriptionB],
                mediaTimeline: [
                    .description(descriptionA),
                    .description(descriptionB)
                ],
                expectedQueueState: .staged,
                expected: [
                    .description(descriptionA.freeText),
                    .description(descriptionB.freeText)
                ]
            )
        ]

        for scenario in scenarios {
            let enqueued = manager.enqueueNonVisualCapture(
                audioFileNames: scenario.audioFileNames,
                observationContexts: scenario.observationContexts,
                mediaTimeline: scenario.mediaTimeline,
                telemetry: dummyTelemetry,
                scanId: scenario.scanId
            )
            #expect(enqueued)

            let scanId = scenario.scanId
            let descriptor = FetchDescriptor<OfflineQueuedScan>(
                predicate: #Predicate { $0.id == scanId }
            )
            let fetched = try #require(context.fetch(descriptor).first)
            #expect(fetched.queueState == scenario.expectedQueueState)

            let capturedMediaJSON = try #require(fetched.capturedMediaJSON)
            let items = try #require(
                MediaJSONParser.serializedItems(jsonString: capturedMediaJSON)
            )
            assertSerializedItems(items, match: scenario.expected)
            let sourceIndices = items.compactMap { item -> Int? in
                guard case .audio(let reference) = item else { return nil }
                return reference.sourceIndex
            }
            let expectedAudioCount = scenario.expected.reduce(into: 0) { count, item in
                if case .audio = item { count += 1 }
            }
            #expect(sourceIndices == Array(0..<expectedAudioCount))
            cleanupSerializedItems(items)
        }
    }

    @Test func testEnqueueNonVisualCaptureRejectsExtensionSpoofedWAVBeforePersistence() throws {
        let manager = OfflineQueueManager.shared
        let snapshot = ManagerSnapshot(manager)
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = false
        defer { snapshot.restore(manager) }

        let scanId = "invalid_audio_\(UUID().uuidString.lowercased())"
        let fileName = "extension_spoof_\(UUID().uuidString).wav"
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        try Data("not a WAV container".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let enqueued = manager.enqueueNonVisualCapture(
            audioFileNames: [fileName],
            observationContexts: [],
            mediaTimeline: [.audio(fileName)],
            telemetry: dummyTelemetry,
            scanId: scanId
        )

        #expect(!enqueued)
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        #expect(try context.fetch(descriptor).isEmpty)
    }

    private func enableUnlimitedFreeScansForTest() {
        let deviceId = DeviceIdentityManager.shared.deviceId
        UserDefaults.standard.removeObject(
            forKey: "Merian_LastScanDate_\(deviceId)"
        )
        UserDefaults.standard.removeObject(
            forKey: "Merian_ScansUsedToday_\(deviceId)"
        )
        UsageManager.debugFreeScanLimitOverride = true
        UsageManager.shared.evaluateDailyRefresh()
        EntitlementManager.shared.resetForTesting(
            userID: UUID(
                uuidString: "00000000-0000-4000-8000-000000000777"
            )!
        )
        RevenueCatManager.shared.isSubscribed = true
    }

    private func restoreFreeScanLimitForTest() {
        let deviceId = DeviceIdentityManager.shared.deviceId
        UserDefaults.standard.removeObject(
            forKey: "Merian_LastScanDate_\(deviceId)"
        )
        UserDefaults.standard.removeObject(
            forKey: "Merian_ScansUsedToday_\(deviceId)"
        )
        UsageManager.debugFreeScanLimitOverride = nil
        UsageManager.shared.evaluateDailyRefresh()
        RevenueCatManager.shared.isSubscribed = false
        EntitlementManager.shared.resetForTesting()
    }

    private func makeTempAudioFilename(
        prefix: String = "queued_audio"
    ) throws -> String {
        let filename = "\(prefix)_\(UUID().uuidString).wav"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try makeInferenceTestPCM16WAVData().write(to: url)
        return filename
    }

    private func makeTempVideoFilename(
        prefix: String = "queued_video"
    ) throws -> String {
        let filename = "\(prefix)_\(UUID().uuidString).mp4"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try Data(repeating: 0x42, count: 128).write(to: url)
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
                Issue.record("Queued serialized media kind mismatch: \(actual)")
            }
        }
    }

    private func cleanupSerializedItems(_ items: [SerializedMediaItem]) {
        for item in items {
            switch item {
            case .image(let reference), .audio(let reference):
                removeDocument(reference.serializedPath)
            case .video(let reference):
                for mediaReference in [
                    reference.video,
                    reference.thumbnail,
                    reference.audio
                ].compactMap({ $0 }) {
                    removeDocument(mediaReference.serializedPath)
                }
            case .description:
                break
            }
        }
    }

    private func removeDocument(_ path: String) {
        try? FileManager.default.removeItem(
            at: URL.documentsDirectory.appendingPathComponent(path)
        )
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
}
