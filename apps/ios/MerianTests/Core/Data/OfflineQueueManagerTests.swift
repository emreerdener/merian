import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
struct OfflineQueueManagerTests {
    private func enableUnlimitedFreeScansForTest() {
        let deviceId = DeviceIdentityManager.shared.deviceId
        UserDefaults.standard.removeObject(forKey: "Merian_LastScanDate_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "Merian_ScansUsedToday_\(deviceId)")
        UsageManager.debugFreeScanLimitOverride = true
        UsageManager.shared.evaluateDailyRefresh()
    }

    private func restoreFreeScanLimitForTest() {
        let deviceId = DeviceIdentityManager.shared.deviceId
        UserDefaults.standard.removeObject(forKey: "Merian_LastScanDate_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "Merian_ScansUsedToday_\(deviceId)")
        UsageManager.debugFreeScanLimitOverride = nil
        UsageManager.shared.evaluateDailyRefresh()
    }

    private enum ExpectedSerializedMedia {
        case image(String)
        case audio(String)
        case description(String)
    }

    private struct MediaStagingUploadManifestContract: Decodable {
        let schemaVersion: Int
        let endpoint: String
        let maxFilesPerRequest: Int
        let maxImageBytes: Int
        let maxAudioBytes: Int
        let maxAudioFiles: Int
        let maxVideoBytes: Int
        let maxVideoFiles: Int
        let imageContentTypes: [String]
        let audioContentTypes: [String]
        let videoContentTypes: [String]
        let canonicalQueuedImageContentType: String
        let canonicalQueuedWavContentType: String
        let canonicalQueuedM4AContentType: String
        let canonicalQueuedVideoContentType: String
        let optionalRequestFields: [String]
        let optionalResponseFields: [String]
        let mediaRolesByKind: [String: [String]]
        let legacyFileNamesAccepted: Bool
    }

    private func loadMediaStagingContract() throws -> MediaStagingUploadManifestContract {
        var searchURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let contractURL = searchURL
                .appendingPathComponent("docs")
                .appendingPathComponent("contracts")
                .appendingPathComponent("media-staging-upload-manifest.json")
            if FileManager.default.fileExists(atPath: contractURL.path) {
                let data = try Data(contentsOf: contractURL)
                return try JSONDecoder().decode(MediaStagingUploadManifestContract.self, from: data)
            }
            searchURL.deleteLastPathComponent()
        }

        throw CocoaError(.fileNoSuchFile)
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

    private func makeTempVideoFilename(prefix: String = "queued_video") throws -> String {
        let filename = "\(prefix)_\(UUID().uuidString).mp4"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
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
                Issue.record("Queued serialized media kind mismatch: \(String(describing: actual))")
            }
        }
    }

    private func cleanupSerializedItems(_ items: [SerializedMediaItem]) {
        for item in items {
            switch item {
            case .image(let reference), .audio(let reference):
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(reference.serializedPath))
            case .video(let reference):
                for mediaReference in [reference.video, reference.thumbnail, reference.audio].compactMap({ $0 }) {
                    try? FileManager.default.removeItem(
                        at: URL.documentsDirectory.appendingPathComponent(mediaReference.serializedPath)
                    )
                }
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

    @Test func galleryQueueReplayOmitsBookkeepingTimestampWhenPhotoHasNoEmbeddedDate() throws {
        let context = try createIsolatedContext()
        defer { OfflineQueueManager.shared.modelContext = nil }
        let queueTimestamp = try #require(
            ISO8601DateFormatter().date(from: "2026-07-15T22:05:04Z")
        )
        let galleryItem = IdentifyVisualMediaItem.image(
            sourceIndex: 0,
            captureSource: .gallery,
            hasEmbeddedCaptureDate: false
        )
        let visualMediaItemsJSON = try #require(
            String(data: JSONEncoder().encode([galleryItem]), encoding: .utf8)
        )
        let scan = OfflineQueuedScan(
            timestamp: queueTimestamp,
            gpsLatitude: 33.45,
            gpsLongitude: 18.42,
            visualMediaItemsJSON: visualMediaItemsJSON
        )

        let extracted = OfflineQueueManager.shared.buildExtractedScanData(
            from: scan,
            container: context.container
        )

        #expect(extracted.telemetry.gpsLatitude == 33.45)
        #expect(extracted.telemetry.gpsLongitude == 18.42)
        #expect(extracted.telemetry.timestamp == nil)
        #expect(galleryItem.jsonObject["captureSource"] == nil)
        #expect(galleryItem.jsonObject["hasEmbeddedCaptureDate"] == nil)
    }

    @Test func galleryQueueReplayUsesEmbeddedCaptureDateWhenPresent() throws {
        let context = try createIsolatedContext()
        defer { OfflineQueueManager.shared.modelContext = nil }
        let captureDate = try #require(
            ISO8601DateFormatter().date(from: "2026-07-15T22:05:04Z")
        )
        let galleryItem = IdentifyVisualMediaItem.image(
            sourceIndex: 0,
            captureSource: .gallery,
            hasEmbeddedCaptureDate: true
        )
        let visualMediaItemsJSON = try #require(
            String(data: JSONEncoder().encode([galleryItem]), encoding: .utf8)
        )
        let scan = OfflineQueuedScan(
            timestamp: captureDate,
            gpsLatitude: 41.8781,
            gpsLongitude: -87.6298,
            visualMediaItemsJSON: visualMediaItemsJSON
        )

        let extracted = OfflineQueueManager.shared.buildExtractedScanData(
            from: scan,
            container: context.container
        )

        #expect(extracted.telemetry.timestamp == DateUtilities.iso8601Formatter.string(from: captureDate))
    }

    @Test func testScanStatusRecoveryActionRespectsServerIngestionState() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = try #require(
            formatter.date(from: "2026-07-05T15:00:00.000Z")
        )
        let finalizing = ScanStatusResponse(
            status: .notFound,
            jobStatus: .finalizing,
            jobStage: "video_promotion_started",
            jobAttemptCount: 1,
            retryAfter: "2026-07-05T15:02:00.000Z",
            lastError: nil
        )
        let retryable = ScanStatusResponse(
            status: .notFound,
            jobStatus: .failedRetryable,
            jobStage: "video_promotion_failed",
            jobAttemptCount: 1,
            retryAfter: nil,
            lastError: "Video promotion failed."
        )
        let terminal = ScanStatusResponse(
            status: .notFound,
            jobStatus: .failed,
            jobStage: "moderation_rejected",
            jobAttemptCount: 1,
            retryAfter: nil,
            lastError: "Rejected by moderation."
        )
        let found = ScanStatusResponse(
            status: .found,
            jobStatus: nil,
            jobStage: nil,
            jobAttemptCount: nil,
            retryAfter: nil,
            lastError: nil
        )

        #expect(OfflineQueueManager.scanStatusRecoveryAction(for: found, now: now) == .recovered)
        #expect(OfflineQueueManager.scanStatusRecoveryAction(for: finalizing, now: now) == .waitForServer(120))
        #expect(OfflineQueueManager.scanStatusRecoveryAction(for: retryable, now: now) == .retryAfter(30))
        #expect(OfflineQueueManager.scanStatusRecoveryAction(for: terminal, now: now) == .terminalFailure("Rejected by moderation."))
    }

    @Test func testMediaStagingContractMatchesDocumentedUploadManifestContract() throws {
        let contract = try loadMediaStagingContract()

        #expect(contract.schemaVersion == 2)
        #expect(contract.endpoint == "/generate-upload-urls")
        #expect(MerianConfig.mediaStagingMaxFilesPerRequest == contract.maxFilesPerRequest)
        #expect(MerianConfig.mediaStagingMaxAudioFilesPerRequest == contract.maxAudioFiles)
        #expect(MerianConfig.mediaStagingMaxVideoFilesPerRequest == contract.maxVideoFiles)
        #expect(MerianConfig.stagedImagePayloadMaxBytes == contract.maxImageBytes)
        #expect(MerianConfig.audioPayloadMaxBytes == contract.maxAudioBytes)
        #expect(MerianConfig.videoPayloadMaxBytes == contract.maxVideoBytes)
        #expect(StagedMediaKind.image.contentType(for: "queued.webp") == contract.canonicalQueuedImageContentType)
        #expect(StagedMediaKind.audio.contentType(for: "queued.wav") == contract.canonicalQueuedWavContentType)
        #expect(StagedMediaKind.audio.contentType(for: "queued.m4a") == contract.canonicalQueuedM4AContentType)
        #expect(StagedMediaKind.video.contentType(for: "queued.mp4") == contract.canonicalQueuedVideoContentType)
        #expect(contract.imageContentTypes.contains(StagedMediaKind.image.contentType(for: "queued.webp")))
        #expect(contract.audioContentTypes.contains(StagedMediaKind.audio.contentType(for: "queued.wav")))
        #expect(contract.audioContentTypes.contains(StagedMediaKind.audio.contentType(for: "queued.m4a")))
        #expect(contract.videoContentTypes.contains(StagedMediaKind.video.contentType(for: "queued.mp4")))
        #expect(contract.optionalRequestFields == ["clientScanId", "mediaRole"])
        #expect(contract.optionalResponseFields == ["mediaAssetId", "mediaSessionId"])
        #expect(contract.mediaRolesByKind["image"] == ["display", "thumbnail", "inference_frame"])
        #expect(contract.mediaRolesByKind["audio"] == ["audio"])
        #expect(contract.mediaRolesByKind["video"] == ["playback"])
        #expect(contract.legacyFileNamesAccepted)
    }

    @Test func testMediaStagingContractBuildsSanitizedMixedMediaKeys() throws {
        let scanId = "00000000-0000-0000-0000-000000000042"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let audioDirectory = directory.appendingPathComponent("field", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(repeating: 0x21, count: 64).write(to: directory.appendingPathComponent("image one.webp"))
        try Data(repeating: 0x42, count: 64).write(to: audioDirectory.appendingPathComponent("audio one.wav"))
        try Data(repeating: 0x63, count: 64).write(to: directory.appendingPathComponent("fallback video.mp4"))

        let payload = PendingScanPayload(
            id: scanId,
            localImagePaths: ["image one.webp"],
            localAudioPaths: ["field/audio one.wav"],
            localVideoPaths: ["fallback video.mp4"]
        )

        let items = MediaStagingContract.uploadItems(
            for: payload,
            userId: "USER/ABC",
            documentsDirectory: directory
        )
        #expect(items.count == 3)

        #expect(items[0].mediaKind == StagedMediaKind.image)
        #expect(items[0].fileName == "\(scanId)_image_one.webp")
        #expect(items[0].contentType == "image/webp")
        #expect(items[0].objectKey == "staging/user_abc/\(scanId)_image_one.webp")

        #expect(items[1].mediaKind == StagedMediaKind.audio)
        #expect(items[1].fileName == "\(scanId)_field_audio_one.wav")
        #expect(items[1].contentType == "audio/wav")
        #expect(items[1].objectKey == "staging/user_abc/\(scanId)_field_audio_one.wav")

        #expect(items[2].mediaKind == StagedMediaKind.video)
        #expect(items[2].fileName == "\(scanId)_fallback_video.mp4")
        #expect(items[2].contentType == "video/mp4")
        #expect(items[2].objectKey == "staging/user_abc/\(scanId)_fallback_video.mp4")

        let uploadFiles = try MediaStagingContract.uploadFiles(for: items)
        #expect(uploadFiles.map(\.clientScanId) == Array(repeating: Optional(payload.id), count: 3))
        #expect(uploadFiles.map(\.mediaRole) == ["display", "audio", "playback"])

        let splitKeys = MediaStagingContract.splitObjectKeys(
            items.map(\.objectKey),
            scanId: payload.id,
            localImagePaths: payload.localImagePaths,
            localAudioPaths: payload.localAudioPaths,
            localVideoPaths: payload.localVideoPaths
        )
        #expect(splitKeys.imageR2ObjectKeys == [items[0].objectKey])
        #expect(splitKeys.audioR2ObjectKeys == [items[1].objectKey])
        #expect(splitKeys.videoR2ObjectKeys == [items[2].objectKey])
    }

    @Test func testMediaStagingContractAllowsCanonicalVideoScanUploadShape() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageNames = (0..<5).map { "video-frame-\($0).webp" }
        let videoName = "playback.mp4"
        for imageName in imageNames {
            try Data(repeating: 0x21, count: 64).write(to: directory.appendingPathComponent(imageName))
        }
        try Data(repeating: 0x42, count: 128).write(to: directory.appendingPathComponent(videoName))

        let payload = PendingScanPayload(
            id: "scan-video-budget",
            localImagePaths: imageNames,
            localAudioPaths: [],
            localVideoPaths: [videoName]
        )
        let items = MediaStagingContract.uploadItems(
            for: payload,
            userId: "user-a",
            documentsDirectory: directory
        )

        #expect(items.count == 6)
        try MediaStagingContract.validateUploadBudget(items)
        let uploadFiles = try MediaStagingContract.uploadFiles(for: items)
        #expect(uploadFiles.count == 6)
        #expect(uploadFiles.filter { $0.mediaKind == .image }.count == 5)
        #expect(uploadFiles.filter { $0.mediaKind == .video }.count == 1)
    }

    @Test func testMediaStagingUploadTaskDescriptionPreservesUnderscoredScanIds() {
        let scanId = "queued_nonvisual_audio_only"
        let syncGeneration = UUID()
        let description = MediaStagingContract.uploadTaskDescription(
            scanId: scanId,
            uploadIndex: 12,
            syncGeneration: syncGeneration
        )
        let identity = MediaStagingContract.parseUploadTaskDescription(description)

        #expect(identity?.scanId == scanId)
        #expect(identity?.uploadIndex == 12)
        #expect(identity?.syncGeneration == syncGeneration)
        #expect(MediaStagingContract.uploadTaskDescription(description, belongsTo: scanId))
    }

    @Test func testInferenceTaskDescriptionPreservesGenerationAndUnderscoredScanId() {
        let scanId = "queued_nonvisual_audio_only"
        let generation = UUID()
        let description = InferenceURLSessionTaskContract.taskDescription(
            scanId: scanId,
            generation: generation
        )

        #expect(
            InferenceURLSessionTaskContract.parse(description)
                == InferenceURLSessionTaskIdentity(
                    scanId: scanId,
                    generation: generation
                )
        )
        #expect(
            InferenceURLSessionTaskContract.parse("inference_\(scanId)")
                == InferenceURLSessionTaskIdentity(
                    scanId: scanId,
                    generation: nil
                )
        )
    }

    @Test func testInferencePreparationIsSingleFlightAndCompareCleared() throws {
        let manager = OfflineQueueManager.shared
        let scanId = "preparation-generation-test"
        manager.inferencePreparationGenerations[scanId] = nil
        defer {
            manager.inferencePreparationGenerations[scanId] = nil
        }

        let firstGeneration = try #require(
            manager.beginInferencePreparation(scanId: scanId)
        )
        let replacementAttempt = manager.beginInferencePreparation(scanId: scanId)

        #expect(replacementAttempt == nil)

        manager.clearInferencePreparation(
            scanId: scanId,
            generation: UUID()
        )
        #expect(manager.inferencePreparationGenerations[scanId] == firstGeneration)

        manager.clearInferencePreparation(
            scanId: scanId,
            generation: firstGeneration
        )
        #expect(manager.inferencePreparationGenerations[scanId] == nil)
    }

    @Test func testUploadGenerationRejectsDelayedReplacementCallback() {
        let manager = OfflineQueueManager.shared
        let scanId = "upload-generation-test"
        let staleGeneration = UUID()
        let currentGeneration = UUID()
        manager.uploadPreparationGenerations[scanId] = nil
        manager.latestUploadGenerations[scanId] = currentGeneration
        defer {
            manager.uploadPreparationGenerations[scanId] = nil
            manager.latestUploadGenerations[scanId] = nil
        }

        #expect(
            !manager.isUploadGenerationCurrent(
                scanId: scanId,
                generation: staleGeneration
            )
        )
        #expect(
            manager.isUploadGenerationCurrent(
                scanId: scanId,
                generation: currentGeneration
            )
        )
        #expect(
            !manager.isUploadGenerationCurrent(
                scanId: scanId,
                generation: nil
            )
        )
    }

    @Test func testUploadCompletionClearsOnlyTheOwningCallbackToken() {
        let manager = OfflineQueueManager.shared
        let scanId = "upload-completion-token-test"
        manager.uploadCompletionTokens[scanId] = nil
        defer {
            manager.uploadCompletionTokens[scanId] = nil
        }

        let firstToken = manager.beginUploadCompletion(scanId: scanId)
        let replacementToken = manager.beginUploadCompletion(scanId: scanId)

        #expect(
            manager.finishUploadCompletion(
                scanId: scanId,
                token: firstToken
            )
        )
        #expect(manager.uploadCompletionScanIds.contains(scanId))
        #expect(manager.uploadCompletionTokens[scanId] == [replacementToken])

        #expect(
            manager.finishUploadCompletion(
                scanId: scanId,
                token: replacementToken
            )
        )
        #expect(!manager.uploadCompletionScanIds.contains(scanId))
    }

    @Test func testStaleUploadGenerationCannotFinishReplacementSync() {
        let manager = OfflineQueueManager.shared
        let staleGeneration = UUID()
        let currentGeneration = UUID()

        manager.syncTask?.cancel()
        manager.syncTask = nil
        manager.syncGeneration = currentGeneration
        manager.isSyncing = true
        SyncStateManager.shared.forceIdle()
        SyncStateManager.shared.beginSync(
            itemCount: 4,
            generation: currentGeneration
        )
        defer {
            manager.syncTask?.cancel()
            manager.syncTask = nil
            manager.syncGeneration = nil
            manager.isSyncing = false
            SyncStateManager.shared.forceIdle()
        }

        #expect(!manager.finishUploadSync(generation: staleGeneration))
        #expect(manager.syncGeneration == currentGeneration)
        #expect(manager.isSyncing)
        #expect(SyncStateManager.shared.pendingUploadCount == 4)

        #expect(manager.finishUploadSync(generation: currentGeneration))
        #expect(manager.syncGeneration == nil)
        #expect(!manager.isSyncing)
        #expect(SyncStateManager.shared.pendingUploadCount == 0)
    }

    @Test func testMediaStagingContractRejectsOversizedAudioBeforeUpload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioName = "oversized.wav"
        let audioURL = directory.appendingPathComponent(audioName)
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: audioURL)
        try handle.truncate(atOffset: UInt64(MerianConfig.audioPayloadMaxBytes + 1))
        try handle.close()

        let payload = PendingScanPayload(
            id: "scan-audio-budget",
            localImagePaths: [],
            localAudioPaths: [audioName],
            localVideoPaths: []
        )
        let items = MediaStagingContract.uploadItems(
            for: payload,
            userId: "user-a",
            documentsDirectory: directory
        )

        #expect(throws: MerianError.payloadTooLarge) {
            try MediaStagingContract.validateUploadBudget(items)
        }
    }

    @Test func testMediaStagingContractRejectsTooManyAudioFilesBeforeUpload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioNames = (0...MerianConfig.mediaStagingMaxAudioFilesPerRequest).map { "queued-\($0).wav" }
        for audioName in audioNames {
            try Data(repeating: 0x21, count: 64).write(to: directory.appendingPathComponent(audioName))
        }

        let payload = PendingScanPayload(
            id: "scan-too-many-audio",
            localImagePaths: [],
            localAudioPaths: audioNames,
            localVideoPaths: []
        )
        let items = MediaStagingContract.uploadItems(
            for: payload,
            userId: "user-a",
            documentsDirectory: directory
        )

        #expect(throws: MerianError.payloadTooLarge) {
            try MediaStagingContract.validateUploadBudget(items)
        }
    }

    @Test func testEnqueueCapture_WithValidData_PersistsQueuedScan() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let ctx = try createIsolatedContext()
        let scanId = UUID().uuidString
        let imageData = Data("dummy_image".utf8)

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

    @Test func testEnqueueCaptureCanHoldAndIdempotentlyReleaseLiveUpload() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let manager = OfflineQueueManager.shared
        manager.deferredLiveUploadScanIds.removeAll()
        let ctx = try createIsolatedContext()
        let scanId = UUID().uuidString
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
        let fetched = try #require(ctx.fetch(descriptor).first)
        #expect(fetched.queueState == .pending)

        manager.releaseDeferredLiveUpload(scanId: scanId, reason: "unit_test_body_sent")
        #expect(!manager.deferredLiveUploadScanIds.contains(scanId))
        manager.releaseDeferredLiveUpload(scanId: scanId, reason: "unit_test_duplicate_release")
        #expect(!manager.deferredLiveUploadScanIds.contains(scanId))

        if let json = fetched.capturedMediaJSON,
           let data = json.data(using: .utf8),
           let items = try? JSONDecoder().decode([SerializedMediaItem].self, from: data) {
            cleanupSerializedItems(items)
        }
    }

    @Test func testForegroundInferenceOwnershipOutlivesBodyUploadHandoff() {
        let manager = OfflineQueueManager.shared
        let scanId = UUID().uuidString
        let staleGeneration = UUID()
        let currentGeneration = UUID()
        let originalIsOnline = manager.isOnline
        manager.isOnline = false
        defer {
            manager.isOnline = originalIsOnline
            manager.foregroundInferenceGenerations.removeValue(
                forKey: scanId
            )
        }
        manager.deferredLiveUploadScanIds = [scanId]
        manager.foregroundInferenceGenerations.removeValue(forKey: scanId)

        manager.foregroundInferenceGenerations[scanId] =
            currentGeneration
        manager.releaseDeferredLiveUpload(
            scanId: scanId,
            foregroundInferenceGeneration: staleGeneration,
            reason: "unit_test_stale_body_sent"
        )
        #expect(
            manager.deferredLiveUploadScanIds.contains(scanId),
            "A delayed callback must not release the replacement attempt's upload hold"
        )
        manager.releaseDeferredLiveUpload(
            scanId: scanId,
            foregroundInferenceGeneration: currentGeneration,
            reason: "unit_test_body_sent"
        )

        #expect(!manager.deferredLiveUploadScanIds.contains(scanId))
        #expect(
            manager.foregroundInferenceScanIds.contains(scanId),
            "Recovery media may upload, but foreground inference must retain sole model-call ownership"
        )
    }

    @Test func testEnqueueDescribe_InsertsStagedScan() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

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
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let ctx = try createIsolatedContext()
        let scanId = UUID().uuidString
        let imageData = Data("queued_image".utf8)
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
        #expect(fetched.capturedMediaEntries?.count == items.count)
        #expect(fetched.serializedCapturedMediaItems == items)

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
            case .video(let reference):
                for mediaReference in [reference.video, reference.thumbnail, reference.audio].compactMap({ $0 }) {
                    try? FileManager.default.removeItem(
                        at: URL.documentsDirectory.appendingPathComponent(mediaReference.serializedPath)
                    )
                }
            case .description:
                break
            }
        }
    }

    @Test func testEnqueueCaptureSeparatesDisplayMediaFromInferenceFrames() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let ctx = try createIsolatedContext()
        let scanId = UUID().uuidString
        let videoFilename = try makeTempVideoFilename()

        OfflineQueueManager.shared.enqueueCapture(
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
            ]
        )

        try await Task.sleep(nanoseconds: 500_000_000)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        let fetched = try #require(ctx.fetch(descriptor).first)
        let inferenceImagePaths = try #require(fetched.inferenceImagePaths)
        let capturedMediaJSON = try #require(fetched.capturedMediaJSON)
        let items = try #require(MediaJSONParser.serializedItems(jsonString: capturedMediaJSON))
        let visualMediaItemsJSON = try #require(fetched.visualMediaItemsJSON)
        let visualMediaItemsData = try #require(visualMediaItemsJSON.data(using: .utf8))
        let visualMediaItems = try JSONDecoder().decode([IdentifyVisualMediaItem].self, from: visualMediaItemsData)

        defer {
            cleanupSerializedItems(items)
            for inferenceImagePath in inferenceImagePaths {
                try? FileManager.default.removeItem(
                    at: URL.documentsDirectory.appendingPathComponent(inferenceImagePath)
                )
            }
        }

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
        let thumbnailPath = try #require(videoReference.thumbnail?.serializedPath)
        #expect(!inferenceImagePaths.contains(thumbnailPath))

        guard case .image(let imageReference) = items[1] else {
            Issue.record("Expected queued mixed capture to serialize the display image second")
            return
        }
        #expect(!inferenceImagePaths.contains(imageReference.serializedPath))
    }

    @Test func testEnqueueNonVisualCaptureSupportsAllowedCombinationMatrix() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

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
                mediaTimeline: [.audio(audioWithDescription), .description(descriptionA)],
                expectedQueueState: .pending,
                expected: [.audio(audioWithDescription), .description(descriptionA.freeText)]
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
                mediaTimeline: [.description(descriptionA), .description(descriptionB)],
                expectedQueueState: .staged,
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
            #expect(fetched.queueState == scenario.expectedQueueState)

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

    @Test func testRetryQueuedScanNow_MakesFailedVisualScanRunnable() async throws {
        let ctx = try createIsolatedContext()
        let manager = OfflineQueueManager.shared
        let originalIsOnline = manager.isOnline
        defer { manager.isOnline = originalIsOnline }
        manager.isOnline = false

        let scanId = UUID().uuidString
        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .failed,
            inferenceImagePaths: ["retry-image.webp"],
            queueAttemptCount: 2,
            queueNextRetryAt: Date().addingTimeInterval(600),
            queueLastErrorCode: "upload_failed",
            queueLastErrorMessage: "Upload failed.",
            queueNeedsAttention: true
        )
        ctx.insert(scan)
        try ctx.save()

        let didRetry = manager.retryQueuedScanNow(scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        let fetched = try #require(ctx.fetch(descriptor).first)
        #expect(didRetry)
        #expect(fetched.queueState == .pending, "Visual failed scans must become runnable pending uploads")
        #expect(fetched.queueNextRetryAt == nil)
        #expect(fetched.queueLastErrorCode == nil)
        #expect(fetched.queueLastErrorMessage == nil)
        #expect(!fetched.queueNeedsAttention)
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

    @Test func staleForegroundGenerationCannotClearReplacementQueueWork() async throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let context = try createIsolatedContext()
        let scanId = UUID().uuidString.lowercased()
        let staleGeneration = UUID()
        let replacementGeneration = UUID()
        let originalIsOnline = manager.isOnline
        manager.isOnline = false
        manager.modelContext = context
        defer {
            manager.isOnline = originalIsOnline
            manager.foregroundInferenceGenerations.removeValue(
                forKey: scanId
            )
            manager.inferenceRetryTasks.cancel(scanId)
            manager.modelContext = originalContext
        }

        context.insert(OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .pending
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(
                    for: replacementGeneration
                )
        ))
        try context.save()
        manager.foregroundInferenceGenerations[scanId] =
            replacementGeneration
        let replacementRetryToken = manager.inferenceRetryTasks.replace(
            for: scanId,
            ownerGeneration: replacementGeneration
        ) { _ in
            Task {
                try? await Task.sleep(for: .seconds(30))
            }
        }

        let staleDidRelease = await manager.endForegroundInference(
            scanId: scanId,
            generation: staleGeneration,
            resumeBackground: false,
            reason: "unit_test_stale_release"
        )

        // Force the stale process-local view that motivated the durable fence:
        // A appears current in memory while the job has already advanced to B.
        manager.foregroundInferenceGenerations[scanId] =
            staleGeneration
        let staleCacheDidRelease = await manager.endForegroundInference(
            scanId: scanId,
            generation: staleGeneration,
            resumeBackground: false,
            reason: "unit_test_stale_cache_release"
        )
        let staleDidDelete = await manager.deleteQueuedScan(
            scanId: scanId,
            foregroundInferenceExpectation:
                ForegroundInferenceGenerationExpectation(
                    generation: staleGeneration
                )
        )
        manager.foregroundInferenceGenerations[scanId] =
            replacementGeneration

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        #expect(!staleDidRelease)
        #expect(!staleCacheDidRelease)
        #expect(!staleDidDelete)
        #expect(try context.fetch(descriptor).first != nil)
        #expect(
            try context.fetch(jobDescriptor).first?.metadataJSON
                == InferenceGenerationMetadataContract.json(
                    for: replacementGeneration
                )
        )
        #expect(
            manager.foregroundInferenceGenerations[scanId]
                == replacementGeneration
        )
        #expect(
            manager.inferenceRetryTasks.isCurrent(
                scanId,
                token: replacementRetryToken,
                ownerGeneration: replacementGeneration
            ),
            "Stale foreground cleanup must not cancel replacement retry work"
        )

        _ = await manager.deleteQueuedScan(scanId: scanId)
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
        let originalModelContext = manager.modelContext
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        defer {
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
            manager.modelContext = originalModelContext
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        manager.modelContext = nil
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
        let originalModelContext = manager.modelContext
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        defer {
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
            manager.modelContext = originalModelContext
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        manager.modelContext = nil
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
        let originalModelContext = manager.modelContext
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        defer {
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
            manager.modelContext = originalModelContext
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        manager.modelContext = nil
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

    @Test func testFinishCollectionSyncAttemptPausesAfterRetryBudget() async throws {
        let ctx = try createIsolatedContext()
        let manager = OfflineQueueManager.shared
        let originalRevision = manager.collectionSyncRevision
        let originalSyncing = manager.isCollectionSyncing
        let originalTask = manager.collectionSyncTask
        defer {
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
        }

        let job = OfflineJobRecord(
            id: OfflineQueueManager.collectionSyncJobId,
            kind: .collectionSync,
            status: .running,
            attemptCount: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        )
        ctx.insert(job)
        try ctx.save()

        manager.isCollectionSyncing = true
        manager.finishCollectionSyncAttempt(success: false, capturedRevision: 1)

        let jobId = OfflineQueueManager.collectionSyncJobId
        let descriptor = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.id == jobId })
        let fetched = try #require(ctx.fetch(descriptor).first)
        #expect(fetched.status == .needsAttention)
        #expect(fetched.nextRunAt == nil)
        #expect(fetched.attemptCount == OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts)
        #expect(fetched.lastErrorCode == "collection_sync_retry_limit_reached")
        #expect(!manager.hasPendingCollectionSyncJob)
    }

    @Test func testMarkCollectionSyncPendingResetsRetryBudgetForNewMutation() async throws {
        let ctx = try createIsolatedContext()
        let manager = OfflineQueueManager.shared
        let originalRevision = manager.collectionSyncRevision
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        defer {
            manager.collectionSyncRevision = originalRevision
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        let job = OfflineJobRecord(
            id: OfflineQueueManager.collectionSyncJobId,
            kind: .collectionSync,
            status: .needsAttention,
            nextRunAt: Date().addingTimeInterval(600),
            attemptCount: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts,
            lastErrorCode: "collection_sync_retry_limit_reached",
            lastErrorMessage: "Paused."
        )
        ctx.insert(job)
        try ctx.save()

        manager.markCollectionSyncPending()

        let jobId = OfflineQueueManager.collectionSyncJobId
        let descriptor = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.id == jobId })
        let fetched = try #require(ctx.fetch(descriptor).first)
        #expect(fetched.status == .pending)
        #expect(fetched.attemptCount == 0)
        #expect(fetched.nextRunAt == nil)
        #expect(fetched.lastErrorCode == nil)
        #expect(fetched.lastErrorMessage == nil)
    }
}
