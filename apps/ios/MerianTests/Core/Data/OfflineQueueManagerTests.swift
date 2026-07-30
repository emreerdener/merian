import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite(.serialized)
@MainActor
struct OfflineQueueManagerTests {
    @Test func cloudDeletionRequiresExplicitNetworkConfirmation() {
        #expect(
            OfflineQueueManager.cloudDeletionWasConfirmed(error: nil)
        )
        #expect(
            !OfflineQueueManager.cloudDeletionWasConfirmed(
                error: MerianError.invalidResponse
            )
        )
        #expect(
            !OfflineQueueManager.cloudDeletionWasConfirmed(
                error: MerianError.httpError(
                    statusCode: 503,
                    message: "Temporary failure"
                )
            )
        )
        #expect(
            !OfflineQueueManager.cloudDeletionWasConfirmed(
                error: URLError(.notConnectedToInternet)
            )
        )
    }

    @Test func cloudDeletionRetriesNeverEnterAnUnrecoverableState() {
        for status in [
            OfflineJobStatus.needsAttention,
            .complete,
            .cancelled
        ] {
            #expect(
                OfflineQueueManager.cloudDeletionStatusRequiresRecovery(status)
            )
        }
        for status in [
            OfflineJobStatus.pending,
            .running,
            .waiting
        ] {
            #expect(
                !OfflineQueueManager.cloudDeletionStatusRequiresRecovery(status)
            )
        }

        #expect(
            OfflineQueueManager.nextCloudDeletionRetryAttempt(after: -1) == 1
        )
        #expect(
            OfflineQueueManager.nextCloudDeletionRetryAttempt(after: 0) == 1
        )
        #expect(
            OfflineQueueManager.nextCloudDeletionRetryAttempt(
                after: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
            ) == OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        )
        #expect(
            OfflineQueueManager.nextCloudDeletionRetryAttempt(after: .max)
                == OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        )
    }

    @Test func cloudDeletionDrainIsProcessSingleFlight() async throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let originalIsOnline = manager.isOnline
        let originalIsSyncing = manager.isCloudDeletionSyncing
        defer {
            manager.isCloudDeletionSyncing = originalIsSyncing
            manager.isOnline = originalIsOnline
            manager.modelContext = originalContext
        }

        let context = try createIsolatedContext()
        let scanId = UUID().uuidString.lowercased()
        context.insert(PendingCloudDeletionTask(scanId: scanId))
        try context.save()
        manager.isOnline = true
        // Simulate a first foreground wake source already owning the drain.
        manager.isCloudDeletionSyncing = true

        await manager.syncPendingDeletions()

        let pending = try context.fetch(
            FetchDescriptor<PendingCloudDeletionTask>()
        )
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>())
        #expect(pending.map(\.scanId) == [scanId])
        #expect(jobs.isEmpty)
        #expect(manager.isCloudDeletionSyncing)
    }

    @Test func queueDiagnosticsExportOmitsPrivateAndFreeFormValues() throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        defer {
            manager.modelContext = originalContext
        }

        let context = try createIsolatedContext()
        let scanId = UUID().uuidString.lowercased()
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let privatePath = "PRIVATE-MEDIA-PATH-\(UUID().uuidString).webp"
        let privateDescription = "PRIVATE-DESCRIPTION-\(UUID().uuidString)"
        let privateNotes = "PRIVATE-FIELD-NOTES-\(UUID().uuidString)"
        let privateLocation = "PRIVATE-LOCATION-\(UUID().uuidString)"
        let privateMessage = "PRIVATE-ERROR-MESSAGE-\(UUID().uuidString)"
        let privateMetadata = "PRIVATE-METADATA-\(UUID().uuidString)"
        let privateMachineField =
            "PRIVATE-MACHINE-FIELD-\(UUID().uuidString) / raw"
        let mediaJSON = CapturedMediaSnapshot(items: [
            .image(.documents(privatePath)),
            .description(ObservationContext(
                freeText: privateDescription,
                addedAt: Date()
            ))
        ]).jsonString

        let scan = OfflineQueuedScan(
            id: scanId,
            capturedMediaJSON: mediaJSON,
            coverImagePath: privatePath,
            gpsLatitude: 39.781721,
            gpsLongitude: -89.650148,
            locationName: privateLocation,
            fieldNotes: privateNotes,
            queueLastErrorCode: "upload_http_503",
            queueLastErrorMessage: privateMessage,
            queueLastHTTPStatus: 503,
            queueLastServerStatus: "failed_retryable",
            queueLastServerStage: "background_ingestion_failed"
        )
        let job = OfflineJobRecord(
            id: jobId,
            kind: .scanIngestion,
            subjectId: scanId,
            status: .waiting,
            lastErrorCode: "upload_http_503",
            lastErrorMessage: privateMessage,
            lastHTTPStatus: 503,
            serverStatus: privateMachineField,
            serverStage: privateMachineField,
            metadataJSON: #"{"private":"\#(privateMetadata)"}"#
        )
        let event = OfflineQueueEvent(
            jobId: jobId,
            scanId: scanId,
            kind: .retryScheduled,
            message: privateMessage,
            errorCode: privateMachineField,
            httpStatus: 503,
            metadataJSON: #"{"private":"\#(privateMetadata)"}"#
        )
        context.insert(scan)
        context.insert(job)
        context.insert(event)
        try context.save()

        let exportURL = try manager.writeQueueDiagnosticsExport()
        defer {
            try? FileManager.default.removeItem(at: exportURL)
        }
        let exportData = try Data(contentsOf: exportURL)
        let exportText = try #require(String(
            data: exportData,
            encoding: .utf8
        ))
        let exportObject = try #require(
            JSONSerialization.jsonObject(with: exportData) as? [String: Any]
        )

        for privateValue in [
            privatePath,
            privateDescription,
            privateNotes,
            privateLocation,
            privateMessage,
            privateMetadata,
            privateMachineField,
            "39.781721",
            "-89.650148"
        ] {
            #expect(!exportText.contains(privateValue))
        }
        #expect(exportText.contains(scanId))
        #expect(exportObject["formatVersion"] as? Int == 1)
        #expect(exportText.contains("upload_http_503"))
        #expect(exportText.contains("failed_retryable"))
        #expect(exportText.contains("background_ingestion_failed"))
        #expect(exportText.contains(OfflineQueueEventKind.retryScheduled.rawValue))
        for provenanceKey in [
            "version",
            "build",
            "sourceRevision",
            "sourceFingerprint",
            "sourceState"
        ] {
            #expect(exportText.contains(#""\#(provenanceKey)""#))
        }
    }

    @Test func queueDiagnosticsRowLimitsAlwaysStayWithinOneThroughFiveHundred() throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        defer {
            manager.modelContext = originalContext
        }

        let context = try createIsolatedContext()
        for index in 0..<510 {
            context.insert(OfflineJobRecord(
                id: "diagnostics-job-\(index)",
                kind: .future,
                updatedAt: Date(
                    timeIntervalSince1970: TimeInterval(index)
                )
            ))
            context.insert(OfflineQueuedScan(
                id: UUID().uuidString.lowercased(),
                timestamp: Date(
                    timeIntervalSince1970: TimeInterval(index)
                )
            ))
            context.insert(OfflineQueueEvent(
                kind: .diagnostics,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
        try context.save()

        let maximumURL = try manager.writeQueueDiagnosticsExport(
            eventLimit: .max
        )
        defer {
            try? FileManager.default.removeItem(at: maximumURL)
        }
        let maximumData = try Data(contentsOf: maximumURL)
        let maximumObject = try #require(
            JSONSerialization.jsonObject(with: maximumData) as? [String: Any]
        )
        let maximumEvents = try #require(
            maximumObject["events"] as? [[String: Any]]
        )
        let maximumJobs = try #require(
            maximumObject["jobs"] as? [[String: Any]]
        )
        let maximumScans = try #require(
            maximumObject["scans"] as? [[String: Any]]
        )
        #expect(maximumEvents.count == 500)
        #expect(maximumJobs.count == 500)
        #expect(maximumScans.count == 500)

        let minimumURL = try manager.writeQueueDiagnosticsExport(eventLimit: 0)
        defer {
            try? FileManager.default.removeItem(at: minimumURL)
        }
        let minimumData = try Data(contentsOf: minimumURL)
        let minimumObject = try #require(
            JSONSerialization.jsonObject(with: minimumData) as? [String: Any]
        )
        let minimumEvents = try #require(
            minimumObject["events"] as? [[String: Any]]
        )
        #expect(minimumEvents.count == 1)
    }

    @Test func inferenceReplayReconciliationCoalescesConcurrentWakeSources() {
        let manager = OfflineQueueManager.shared
        let originalIsReconciling = manager.isInferenceReplayReconciling
        let originalNeedsTrailingPass =
            manager.inferenceReplayRequestedWhileReconciling
        defer {
            manager.isInferenceReplayReconciling = originalIsReconciling
            manager.inferenceReplayRequestedWhileReconciling =
                originalNeedsTrailingPass
        }

        manager.isInferenceReplayReconciling = false
        manager.inferenceReplayRequestedWhileReconciling = false

        #expect(manager.beginInferenceReplayReconciliation())
        #expect(!manager.beginInferenceReplayReconciliation())
        #expect(!manager.beginInferenceReplayReconciliation())
        #expect(manager.isInferenceReplayReconciling)
        #expect(manager.inferenceReplayRequestedWhileReconciling)

        #expect(manager.finishInferenceReplayReconciliation())
        #expect(!manager.isInferenceReplayReconciling)
        #expect(!manager.inferenceReplayRequestedWhileReconciling)
        #expect(!manager.finishInferenceReplayReconciliation())

        // The single trailing caller can claim a fresh pass immediately.
        #expect(manager.beginInferenceReplayReconciliation())
        #expect(!manager.finishInferenceReplayReconciliation())
    }

    @Test func scheduledServerFailureRetryBreaksStatusUploadDeadlock() {
        #expect(
            OfflineQueueManager.isServerRetryableFailureCode(
                OfflineQueueManager.serverRetryableFailureCode
            )
        )
        #expect(
            !OfflineQueueManager.isServerRetryableFailureCode(nil)
        )
        #expect(
            !OfflineQueueManager.isServerRetryableFailureCode(
                "inference_retry"
            )
        )

        #expect(
            !OfflineQueueManager.scanStatusActionPermitsInferenceDispatch(
                .retryAfter(1),
                hasScheduledServerFailureRetry: false
            )
        )
        #expect(
            OfflineQueueManager.scanStatusActionPermitsInferenceDispatch(
                .retryAfter(1),
                hasScheduledServerFailureRetry: true
            )
        )
        #expect(
            OfflineQueueManager.scanStatusActionPermitsInferenceDispatch(
                .unresolved,
                hasScheduledServerFailureRetry: false
            )
        )
        for action in [
            ScanStatusRecoveryAction.recovered,
            .waitForServer(1),
            .terminalFailure("No retry")
        ] {
            #expect(
                !OfflineQueueManager.scanStatusActionPermitsInferenceDispatch(
                    action,
                    hasScheduledServerFailureRetry: true
                )
            )
        }
    }

    @Test func scheduledServerFailureMarkerIsReadFromDurableStore() async throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let context = try createIsolatedContext()
        defer {
            OfflineJobScheduler.shared.cancelScheduledWake(using: manager)
            manager.modelContext = originalContext
        }

        let scan = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .inferencing
        )
        context.insert(scan)
        try context.save()
        // Keep the marker-free model resident in the manager's context. The
        // background actor then commits the marker through a separate context.
        let scanId = scan.id
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        _ = try #require(context.fetch(descriptor).first)

        let actor = BackgroundDatabaseActor(
            modelContainer: context.container
        )
        #expect(
            await actor.scheduleInferenceRetry(
                id: scanId,
                expectedGeneration: nil,
                code: OfflineQueueManager.serverRetryableFailureCode,
                message: "Retry the exact backend generation.",
                delay: 1,
                resetMediaUploads: false
            ) == 1
        )

        #expect(
            manager.hasDurableScheduledServerFailureRetry(scanId: scanId)
        )
        #expect(manager.queueAttemptCount(for: scanId) == 1)

        // Reproduce the migrated-store failure seen on TestFlight: one
        // SwiftData context loses the queue-row copy while the durable job
        // still owns the exact retry. Reads must heal from the surviving
        // mirror instead of restarting forever at attempt one.
        let driftContext = ModelContext(context.container)
        let driftedScan = try #require(
            driftContext.fetch(descriptor).first
        )
        driftedScan.queueLastErrorCode = nil
        driftedScan.queueAttemptCount = 0
        try driftContext.save()
        #expect(
            manager.hasDurableScheduledServerFailureRetry(scanId: scanId)
        )
        #expect(manager.queueAttemptCount(for: scanId) == 1)

        // A transient signer/PUT failure is part of the required re-stage, not
        // a new inference decision. Its event keeps the precise upload error,
        // while the durable machine latch and committed count must survive.
        #expect(
            manager.updateQueuedScanForRetry(
                scanId: scanId,
                code: "upload_transport_error",
                message: "The re-stage connection was interrupted.",
                delay: 1,
                resetTo: .pending
            ) == 2
        )
        #expect(
            manager.hasDurableScheduledServerFailureRetry(scanId: scanId)
        )
        #expect(manager.queueAttemptCount(for: scanId) == 2)

        let verificationContext = ModelContext(context.container)
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(
            persisted.queueLastErrorCode
                == OfflineQueueManager.serverRetryableFailureCode
        )
        #expect(persisted.queueAttemptCount == 2)
    }

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
        let minFileBytes: Int
        let maxImageBytes: Int
        let maxImageFiles: Int
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
        let uploadPurposes: [String]
        let optionalResponseFields: [String]
        let mediaRolesByKind: [String: [String]]
        let fileNamesMustBeUnique: Bool
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

    private func loadRepositorySource(
        at relativePath: String
    ) throws -> String {
        var searchURL = URL(
            fileURLWithPath: #filePath
        ).deletingLastPathComponent()
        for _ in 0..<8 {
            let sourceURL = searchURL.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                return try String(
                    contentsOf: sourceURL,
                    encoding: .utf8
                )
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

    @Test func backgroundInferencePlatformRoute404RemainsRetryable() throws {
        let url = try #require(
            URL(string: "https://example.supabase.co/functions/v1/identify-multimodal")
        )
        let officialPayload = Data(
            #"{"code":"NOT_FOUND","message":"Requested function was not found"}"#.utf8
        )
        let platformResponse = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["SB-Error-Code": "NOT_FOUND"]
            )
        )
        let handlerResponse = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: [
                    "X-Merian-Handler": "1",
                    "SB-Error-Code": "NOT_FOUND"
                ]
            )
        )

        #expect(OfflineQueueManager.shouldRetryBackgroundInferenceRouteFailure(
            statusCode: 404,
            functionRouteEvidence: EdgeFunctionRouteResponseEvidence(
                response: platformResponse
            ),
            responseData: officialPayload
        ))
        #expect(!OfflineQueueManager.shouldRetryBackgroundInferenceRouteFailure(
            statusCode: 404,
            functionRouteEvidence: EdgeFunctionRouteResponseEvidence(
                response: handlerResponse
            ),
            responseData: officialPayload
        ))
        #expect(!OfflineQueueManager.shouldRetryBackgroundInferenceRouteFailure(
            statusCode: 503,
            functionRouteEvidence: EdgeFunctionRouteResponseEvidence(
                response: platformResponse
            ),
            responseData: officialPayload
        ))
    }

    @Test func backgroundInferencePreservesRecoverableHTTPFailures() throws {
        let url = try #require(
            URL(string: "https://example.supabase.co/functions/v1/identify-multimodal")
        )

        func evidence(
            statusCode: Int,
            headers: [String: String] = ["X-Merian-Handler": "1"]
        ) throws -> EdgeFunctionRouteResponseEvidence {
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: headers
                )
            )
            return EdgeFunctionRouteResponseEvidence(response: response)
        }

        for statusCode in [401, 408, 409, 425, 429, 503] {
            #expect(
                OfflineQueueManager.backgroundInferenceResponseDisposition(
                    statusCode: statusCode,
                    functionRouteEvidence: try evidence(statusCode: statusCode),
                    responseData: Data()
                ) == .retry
            )
        }

        let rateLimitEvidence = try evidence(
            statusCode: 429,
            headers: [
                "X-Merian-Handler": "1",
                "Retry-After": "3600"
            ]
        )
        #expect(rateLimitEvidence.retryAfterSeconds == 3600)

        let rejectedPayload = Data(
            #"{"code":"observation_rejected","error":"Unable to process."}"#.utf8
        )
        #expect(
            OfflineQueueManager.backgroundInferenceResponseDisposition(
                statusCode: 400,
                functionRouteEvidence: try evidence(statusCode: 400),
                responseData: rejectedPayload
            ) == .terminal
        )
        #expect(
            OfflineQueueManager.backgroundInferenceResponseDisposition(
                statusCode: 400,
                functionRouteEvidence: try evidence(statusCode: 400),
                responseData: Data(#"{"code":"bad_request"}"#.utf8)
            ) == .needsAttention
        )
        #expect(
            OfflineQueueManager.backgroundInferenceResponseDisposition(
                statusCode: 404,
                functionRouteEvidence: try evidence(statusCode: 404),
                responseData: Data(#"{"code":"not_found"}"#.utf8)
            ) == .needsAttention
        )
        let validSuccessPayload = Data(
            """
            {
              "success": true,
              "data": {
                "scan_id": "queued-valid-response",
                "is_biological_subject": false,
                "confidence_score": 0
              }
            }
            """.utf8
        )
        #expect(
            OfflineQueueManager.backgroundInferenceResponseDisposition(
                statusCode: 200,
                functionRouteEvidence: try evidence(statusCode: 200),
                responseData: validSuccessPayload
            ) == .success
        )
        for invalidSuccessPayload in [
            Data(),
            Data(#"{"success":true,"data":"truncated"}"#.utf8),
            Data(
                #"{"success":false,"data":{"scan_id":"queued-failure","confidence_score":0}}"#.utf8
            ),
            Data(
                #"{"success":true,"data":{"scan_id":"queued-missing-confidence"}}"#.utf8
            ),
            Data(
                #"{"success":true,"data":{"scan_id":"queued-invalid-confidence","confidence_score":2}}"#.utf8
            )
        ] {
            #expect(
                OfflineQueueManager.backgroundInferenceResponseDisposition(
                    statusCode: 200,
                    functionRouteEvidence: try evidence(statusCode: 200),
                    responseData: invalidSuccessPayload
                ) == .retry
            )
        }

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
        let staleRetryDate = ScanStatusResponse(
            status: .notFound,
            jobStatus: .retrying,
            jobStage: "video_promotion_failed",
            jobAttemptCount: 1,
            retryAfter: "2026-07-05T14:59:00.000Z",
            lastError: "Retry already due."
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
        #expect(OfflineQueueManager.scanStatusRecoveryAction(for: staleRetryDate, now: now) == .waitForServer(1))
        #expect(OfflineQueueManager.scanStatusRecoveryAction(for: terminal, now: now) == .terminalFailure("Rejected by moderation."))
        #expect(
            OfflineQueueManager.requiresMediaRestagingAfterServerFailure(
                ScanStatusResponse(
                    status: .notFound,
                    jobStatus: .failedRetryable,
                    jobStage: "background_ingestion_failed",
                    jobAttemptCount: 1,
                    retryAfter: nil,
                    lastError: "Scan insert failed."
                )
            )
        )
        #expect(
            OfflineQueueManager.requiresMediaRestagingAfterServerFailure(
                ScanStatusResponse(
                    status: .notFound,
                    jobStatus: .failedRetryable,
                    jobStage: "identity_merge_interrupted",
                    jobAttemptCount: 1,
                    retryAfter: nil,
                    lastError: "Account ownership changed."
                )
            )
        )
        #expect(
            OfflineQueueManager.requiresMediaRestagingAfterServerFailure(retryable)
        )
        #expect(
            !OfflineQueueManager.requiresMediaRestagingAfterServerFailure(
                ScanStatusResponse(
                    status: .notFound,
                    jobStatus: .failedRetryable,
                    jobStage: "ai_inference_failed",
                    jobAttemptCount: 1,
                    retryAfter: nil,
                    lastError: "Provider request failed."
                )
            )
        )
        #expect(
            !OfflineQueueManager.requiresMediaRestagingAfterServerFailure(
                ScanStatusResponse(
                    status: .found,
                    jobStatus: .failedRetryable,
                    jobStage: "background_ingestion_failed",
                    jobAttemptCount: 1,
                    retryAfter: nil,
                    lastError: "Post-insert finalization failed."
                )
            )
        )
    }

    @Test func testFoundServerStatusPersistsOwnershipBeforeLocalHydration() throws {
        let context = try createIsolatedContext()
        let manager = OfflineQueueManager.shared
        defer { manager.modelContext = nil }
        let scanId = UUID().uuidString
        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .inferencing
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        manager.persistServerStatus(
            scanId: scanId,
            response: ScanStatusResponse(
                scanId: scanId,
                status: .found,
                jobStatus: nil,
                jobStage: nil,
                jobAttemptCount: nil,
                retryAfter: nil,
                lastError: nil
            )
        )

        #expect(manager.hasDurableCompletedServerResult(scanId: scanId))
        #expect(
            scan.queueLastErrorCode ==
                OfflineQueueManager.completedServerResultRecoveryCode
        )
        #expect(
            job.lastErrorCode ==
                OfflineQueueManager.completedServerResultRecoveryCode
        )
        #expect(scan.queueState == .inferencing)
    }

    @Test func testMediaStagingContractMatchesDocumentedUploadManifestContract() throws {
        let contract = try loadMediaStagingContract()

        #expect(contract.schemaVersion == 4)
        #expect(contract.endpoint == "/generate-upload-urls")
        #expect(MerianConfig.mediaStagingMaxFilesPerRequest == contract.maxFilesPerRequest)
        #expect(contract.minFileBytes == 1)
        #expect(MerianConfig.mediaStagingMaxImageFilesPerRequest == contract.maxImageFiles)
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
        #expect(
            contract.optionalRequestFields ==
                ["clientScanId", "mediaRole", "uploadPurpose"]
        )
        #expect(contract.uploadPurposes == ["scan_share_restore"])
        #expect(contract.optionalResponseFields == ["mediaAssetId", "mediaSessionId"])
        #expect(contract.mediaRolesByKind["image"] == ["display", "thumbnail", "inference_frame"])
        #expect(contract.mediaRolesByKind["audio"] == ["audio"])
        #expect(contract.mediaRolesByKind["video"] == ["playback"])
        #expect(contract.fileNamesMustBeUnique)
        #expect(contract.legacyFileNamesAccepted)
    }

    @Test func testMediaStagingContractBuildsSanitizedMixedMediaKeys() throws {
        let scanId = "00000000-0000-0000-0000-000000000042"
        let ownerId = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        let canonicalOwnerId = ownerId.lowercased()
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
            userId: ownerId,
            documentsDirectory: directory
        )
        #expect(items.count == 3)

        #expect(items[0].mediaKind == StagedMediaKind.image)
        #expect(items[0].fileName == "\(scanId)_image_one.webp")
        #expect(items[0].contentType == "image/webp")
        #expect(items[0].objectKey == "staging/\(canonicalOwnerId)/\(scanId)_image_one.webp")

        #expect(items[1].mediaKind == StagedMediaKind.audio)
        #expect(items[1].fileName == "\(scanId)_field_audio_one.wav")
        #expect(items[1].contentType == "audio/wav")
        #expect(items[1].objectKey == "staging/\(canonicalOwnerId)/\(scanId)_field_audio_one.wav")

        #expect(items[2].mediaKind == StagedMediaKind.video)
        #expect(items[2].fileName == "\(scanId)_fallback_video.mp4")
        #expect(items[2].contentType == "video/mp4")
        #expect(items[2].objectKey == "staging/\(canonicalOwnerId)/\(scanId)_fallback_video.mp4")

        let presignedURLs = items.map { item in
            PreSignedURL(
                fileName: item.fileName,
                signedUrl: "https://r2.invalid/bucket/\(item.objectKey)",
                objectKey: item.objectKey,
                mediaAssetId: nil,
                mediaSessionId: nil
            )
        }
        #expect(
            MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: items,
                presignedURLs: presignedURLs
            )
        )
        #expect(
            !MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: items,
                presignedURLs: Array(presignedURLs.dropLast())
            )
        )
        var mixedOwnerURLs = presignedURLs
        mixedOwnerURLs[1] = PreSignedURL(
            fileName: items[1].fileName,
            signedUrl: "https://r2.invalid/bucket/staging/other-owner/\(items[1].fileName)",
            objectKey: "staging/other-owner/\(items[1].fileName)",
            mediaAssetId: nil,
            mediaSessionId: nil
        )
        #expect(
            !MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: items,
                presignedURLs: mixedOwnerURLs
            )
        )
        var mixedOriginURLs = presignedURLs
        mixedOriginURLs[1] = PreSignedURL(
            fileName: items[1].fileName,
            signedUrl: "https://other-r2.invalid/bucket/\(items[1].objectKey)",
            objectKey: items[1].objectKey,
            mediaAssetId: nil,
            mediaSessionId: nil
        )
        #expect(
            !MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: items,
                presignedURLs: mixedOriginURLs
            )
        )
        var insecureURLs = presignedURLs
        insecureURLs[0] = PreSignedURL(
            fileName: items[0].fileName,
            signedUrl: "http://r2.invalid/bucket/\(items[0].objectKey)",
            objectKey: items[0].objectKey,
            mediaAssetId: nil,
            mediaSessionId: nil
        )
        #expect(
            !MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: items,
                presignedURLs: insecureURLs
            )
        )
        #expect(
            !MediaStagingContract.presignedUploadManifestIsValid(
                uploadItems: [items[0], items[0]],
                presignedURLs: [presignedURLs[0], presignedURLs[0]]
            )
        )

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

    @Test func testMediaStagingContractRejectsSixStillImagesBeforeUpload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageNames = (0...MerianConfig.mediaStagingMaxImageFilesPerRequest)
            .map { "still-\($0).webp" }
        for imageName in imageNames {
            try Data(repeating: 0x21, count: 64)
                .write(to: directory.appendingPathComponent(imageName))
        }
        let payload = PendingScanPayload(
            id: "scan-too-many-stills",
            localImagePaths: imageNames,
            localAudioPaths: [],
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

    @Test func testMediaStagingContractRejectsDuplicateSanitizedDestinationsBeforeUpload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageName = "duplicate.webp"
        try Data(repeating: 0x21, count: 64)
            .write(to: directory.appendingPathComponent(imageName))
        let payload = PendingScanPayload(
            id: "scan-duplicate-media",
            localImagePaths: [imageName, imageName],
            localAudioPaths: [],
            localVideoPaths: []
        )
        let items = MediaStagingContract.uploadItems(
            for: payload,
            userId: "user-a",
            documentsDirectory: directory
        )

        #expect(throws: MerianError.invalidResponse) {
            try MediaStagingContract.validateUploadBudget(items)
        }
    }

    @Test func testMediaStagingUploadTaskDescriptionPreservesUnderscoredScanIds() {
        let scanId = "queued_nonvisual_audio_only"
        let syncGeneration = UUID()
        let ownerId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let objectKey = "staging/\(ownerId)/\(scanId)_audio.wav"
        let description = MediaStagingContract.uploadTaskDescription(
            scanId: scanId,
            uploadIndex: 12,
            syncGeneration: syncGeneration,
            objectKey: objectKey
        )
        let identity = MediaStagingContract.parseUploadTaskDescription(description)

        #expect(identity?.scanId == scanId)
        #expect(identity?.uploadIndex == 12)
        #expect(identity?.syncGeneration == syncGeneration)
        #expect(identity?.objectKey == objectKey)
        #expect(MediaStagingContract.uploadTaskDescription(description, belongsTo: scanId))
    }

    @Test func testMediaStagingContractAcceptsAuthenticatedCanonicalKeyAfterIdentityChanges() {
        let fileName = "scan-42_image.webp"
        let authenticatedOwnerId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let authenticatedKey = "staging/\(authenticatedOwnerId)/\(fileName)"
        let signedPath = "/merian-media/staging/\(authenticatedOwnerId)/\(fileName)"

        #expect(MediaStagingContract.isCanonicalObjectKey(
            authenticatedKey,
            fileName: fileName
        ))
        #expect(
            MediaStagingContract.objectKey(fromPresignedURLPath: signedPath)
                == authenticatedKey
        )
        #expect(
            MediaStagingContract.ownerId(fromObjectKey: authenticatedKey)
                == authenticatedOwnerId
        )
        #expect(!MediaStagingContract.isCanonicalObjectKey(
            "staging/cccccccc-cccc-4ccc-8ccc-cccccccccccc/other-file.webp",
            fileName: fileName
        ))
        #expect(!MediaStagingContract.isCanonicalObjectKey(
            "staging/not-a-uuid/\(fileName)",
            fileName: fileName
        ))
        #expect(
            MediaStagingContract.objectKey(
                fromPresignedURLPath:
                    "/merian-media/staging/\(authenticatedOwnerId)/../\(fileName)"
            ) == nil
        )
    }

    @Test func testMediaStagingOwnerResolutionPrefersPersistedAuthSession() {
        let sessionUserId = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        let hydratedUserId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let deviceId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

        #expect(
            MediaStagingContract.preferredOwnerId(
                sessionUserId: sessionUserId,
                hydratedUserId: hydratedUserId,
                deviceId: deviceId
            ) == sessionUserId.lowercased()
        )
        #expect(
            MediaStagingContract.preferredOwnerId(
                sessionUserId: nil,
                hydratedUserId: hydratedUserId,
                deviceId: deviceId
            ) == hydratedUserId
        )
        #expect(
            MediaStagingContract.preferredOwnerId(
                sessionUserId: nil,
                hydratedUserId: nil,
                deviceId: deviceId
            ) == deviceId
        )
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

    @Test func testUploadFailureFencesEverySiblingCallbackInGeneration() {
        let manager = OfflineQueueManager.shared
        let scanId = "upload-generation-failure-fence-test"
        let failedGeneration = UUID()
        manager.uploadPreparationGenerations[scanId] = nil
        manager.latestUploadGenerations[scanId] = failedGeneration
        defer {
            manager.uploadPreparationGenerations[scanId] = nil
            manager.latestUploadGenerations[scanId] = nil
        }

        manager.invalidateUploadGeneration(
            scanId: scanId,
            generation: failedGeneration
        )

        #expect(
            !manager.isUploadGenerationCurrent(
                scanId: scanId,
                generation: failedGeneration
            )
        )
        #expect(
            !manager.isUploadGenerationCurrent(
                scanId: scanId,
                generation: nil
            )
        )
    }

    @Test func testUploadManifestWaitsForEverySiblingCallbackOutcome() {
        let manager = OfflineQueueManager.shared
        let scanId = "upload-manifest-outcome-accumulator-test"
        let generation = UUID()
        let ownerId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let firstKey = "staging/\(ownerId)/first.webp"
        let secondKey = "staging/\(ownerId)/second.webp"
        manager.uploadCompletionStates[scanId] = nil
        defer {
            manager.uploadCompletionStates[scanId] = nil
        }

        manager.recordSuccessfulUploadMember(
            scanId: scanId,
            generation: generation,
            objectKey: firstKey
        )
        #expect(
            !manager.hasConfirmedSuccessfulUploadManifest(
                scanId: scanId,
                generation: generation,
                expectedObjectKeys: [firstKey, secondKey]
            )
        )

        manager.recordSuccessfulUploadMember(
            scanId: scanId,
            generation: generation,
            objectKey: secondKey
        )
        #expect(
            manager.hasConfirmedSuccessfulUploadManifest(
                scanId: scanId,
                generation: generation,
                expectedObjectKeys: [firstKey, secondKey]
            )
        )
        manager.recordSuccessfulUploadMember(
            scanId: scanId,
            generation: generation,
            objectKey: "staging/\(ownerId)/stale.webp"
        )
        #expect(
            !manager.hasConfirmedSuccessfulUploadManifest(
                scanId: scanId,
                generation: generation,
                expectedObjectKeys: [firstKey, secondKey]
            ),
            "A successful key outside the current queued manifest must fail closed"
        )

        let replacementGeneration = UUID()
        manager.recordSuccessfulUploadMember(
            scanId: scanId,
            generation: replacementGeneration,
            objectKey: secondKey
        )
        #expect(
            !manager.hasConfirmedSuccessfulUploadManifest(
                scanId: scanId,
                generation: generation,
                expectedObjectKeys: [firstKey, secondKey]
            )
        )

        let legacyScanId = "\(scanId)-legacy"
        manager.uploadCompletionStates[legacyScanId] = nil
        defer {
            manager.uploadCompletionStates[legacyScanId] = nil
        }
        manager.recordSuccessfulUploadMember(
            scanId: legacyScanId,
            generation: nil,
            objectKey: firstKey
        )
        #expect(
            manager.hasConfirmedSuccessfulUploadManifest(
                scanId: legacyScanId,
                generation: nil,
                expectedObjectKeys: [firstKey]
            )
        )
    }

    @Test func testCompleteUploadManifestResetsRetryOnlyWithDurableStagingCommit() async throws {
        let context = try createIsolatedContext()
        let manager = OfflineQueueManager.shared
        let scanId = UUID().uuidString
        let generation = UUID()
        let ownerId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let firstKey = "staging/\(ownerId)/first.webp"
        let secondKey = "staging/\(ownerId)/second.webp"
        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .uploading
        )
        scan.queueAttemptCount = 3
        scan.queueLastErrorCode = "upload_transport"
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .waiting,
            lastAttemptAt: Date(),
            nextRunAt: Date().addingTimeInterval(30),
            attemptCount: 3,
            lastErrorCode: "upload_transport",
            lastErrorMessage: "Retry upload"
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        manager.uploadPreparationGenerations[scanId] = nil
        manager.latestUploadGenerations[scanId] = generation
        defer {
            manager.latestUploadGenerations[scanId] = nil
            manager.uploadCompletionStates[scanId] = nil
            manager.modelContext = nil
        }

        manager.recordSuccessfulUploadMember(
            scanId: scanId,
            generation: generation,
            objectKey: firstKey
        )
        #expect(
            !manager.hasConfirmedSuccessfulUploadManifest(
                scanId: scanId,
                generation: generation,
                expectedObjectKeys: [firstKey, secondKey]
            )
        )
        #expect(scan.queueAttemptCount == 3)
        #expect(scan.queueLastErrorCode == "upload_transport")

        manager.recordSuccessfulUploadMember(
            scanId: scanId,
            generation: generation,
            objectKey: secondKey
        )
        #expect(
            manager.hasConfirmedSuccessfulUploadManifest(
                scanId: scanId,
                generation: generation,
                expectedObjectKeys: [firstKey, secondKey]
            )
        )
        #expect(
            scan.queueAttemptCount == 3,
            "In-memory manifest completion must not clear durable retry state"
        )

        let actor = BackgroundDatabaseActor(modelContainer: context.container)
        let outcome = await actor.markScanAsStaged(
            scanId: scanId,
            r2Keys: [firstKey, secondKey]
        )
        let verificationContext = ModelContext(context.container)
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        jobDescriptor.fetchLimit = 1
        let persistedScan = try verificationContext.fetch(scanDescriptor).first
        let persistedJob = try verificationContext.fetch(jobDescriptor).first

        #expect(outcome == .staged)
        #expect(persistedScan?.queueState == .staged)
        #expect(persistedScan?.stagedR2Keys == [firstKey, secondKey])
        #expect(persistedScan?.queueAttemptCount == 0)
        #expect(persistedScan?.queueLastErrorCode == nil)
        #expect(persistedJob?.status == .running)
        #expect(persistedJob?.attemptCount == 0)
        #expect(persistedJob?.lastErrorCode == nil)
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

    @Test func testMediaStagingContractRejectsEmptyFilesBeforeUpload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageName = "empty.webp"
        try Data().write(to: directory.appendingPathComponent(imageName))
        let payload = PendingScanPayload(
            id: "scan-empty-media",
            localImagePaths: [imageName],
            localAudioPaths: [],
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

    @Test func unsyncedCountIncludesOnlyAutomaticallyRunnableScans() throws {
        let context = try createIsolatedContext()
        let manager = OfflineQueueManager.shared

        let runnableScan = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .pending
        )
        context.insert(runnableScan)
        context.insert(OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .staged,
            queueNeedsAttention: true
        ))
        context.insert(OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .failed
        ))
        context.insert(OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .externalImport
        ))
        try context.save()

        manager.updateUnsyncedItemCount()

        #expect(
            manager.unsyncedItemsCount == 1,
            "Attention-only, failed, and legacy rows must not keep automatic queue work active"
        )

        // Background sync writes through a separate model actor/context. The
        // observable badge must read the committed store rather than retaining
        // the main context's cached runnable copy.
        let backgroundContext = ModelContext(context.container)
        let runnableId = runnableScan.id
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == runnableId }
        )
        let backgroundScan = try #require(backgroundContext.fetch(descriptor).first)
        backgroundScan.queueNeedsAttention = true
        try backgroundContext.save()

        manager.updateUnsyncedItemCount()

        #expect(
            manager.unsyncedItemsCount == 0,
            "A background-committed attention transition must quiet automatic queue work"
        )
    }

    @Test func uploadBatchSelectionSkipsBlockedHeadRowsAndPacksLaterWork() throws {
        let emptyRows = (0..<5).map { index in
            PendingScanPayload(
                id: "empty-\(index)",
                localImagePaths: [],
                localAudioPaths: [],
                localVideoPaths: []
            )
        }
        let fiveItems = PendingScanPayload(
            id: "five-items",
            localImagePaths: (0..<5).map { "image-\($0).webp" },
            localAudioPaths: [],
            localVideoPaths: []
        )
        let twoItems = PendingScanPayload(
            id: "two-items",
            localImagePaths: ["later-a.webp", "later-b.webp"],
            localAudioPaths: [],
            localVideoPaths: []
        )
        let oneItem = PendingScanPayload(
            id: "one-item",
            localImagePaths: ["later-fit.webp"],
            localAudioPaths: [],
            localVideoPaths: []
        )

        let selected = OfflineQueueManager.shared.selectUploadBatch(
            from: emptyRows + [fiveItems, twoItems, oneItem]
        )

        #expect(selected.map(\.id) == [fiveItems.id, oneItem.id])
        #expect(selected.flatMap(\.localUploadPaths).count == 6)

        let remoteURL = URL(string: "https://r2.invalid/upload")!
        let videoItem = ScanUploadItem(
            scanId: "video-policy",
            uploadIndex: 0,
            mediaKind: .video,
            localPath: "video.mp4",
            fileName: "video.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            contentType: "video/mp4",
            objectKey: "staging/owner/video.mp4"
        )
        let imageItem = ScanUploadItem(
            scanId: "image-policy",
            uploadIndex: 0,
            mediaKind: .image,
            localPath: "image.webp",
            fileName: "image.webp",
            fileURL: URL(fileURLWithPath: "/tmp/image.webp"),
            contentType: "image/webp",
            objectKey: "staging/owner/image.webp"
        )
        let deferredVideoRequest =
            OfflineQueueManager.shared.queuedUploadRequest(
                remoteURL: remoteURL,
                item: videoItem,
                scanContainsPlaybackVideo: true,
                allowsExpensiveVideoUpload: false
            )
        let forcedVideoRequest =
            OfflineQueueManager.shared.queuedUploadRequest(
                remoteURL: remoteURL,
                item: videoItem,
                scanContainsPlaybackVideo: true,
                allowsExpensiveVideoUpload: true
            )
        let videoSiblingImageRequest =
            OfflineQueueManager.shared.queuedUploadRequest(
                remoteURL: remoteURL,
                item: imageItem,
                scanContainsPlaybackVideo: true,
                allowsExpensiveVideoUpload: false
            )
        let imageRequest =
            OfflineQueueManager.shared.queuedUploadRequest(
                remoteURL: remoteURL,
                item: imageItem,
                scanContainsPlaybackVideo: false,
                allowsExpensiveVideoUpload: false
            )

        #expect(!deferredVideoRequest.allowsConstrainedNetworkAccess)
        #expect(!deferredVideoRequest.allowsExpensiveNetworkAccess)
        #expect(!forcedVideoRequest.allowsConstrainedNetworkAccess)
        #expect(forcedVideoRequest.allowsExpensiveNetworkAccess)
        #expect(!videoSiblingImageRequest.allowsConstrainedNetworkAccess)
        #expect(!videoSiblingImageRequest.allowsExpensiveNetworkAccess)
        #expect(!imageRequest.allowsConstrainedNetworkAccess)
        #expect(imageRequest.allowsExpensiveNetworkAccess)

        let syncSource = try loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager+Sync.swift"
        )
        #expect(syncSource.contains(
            "var entriesByScanId: [String: [UploadDispatchEntry]]"
        ))
        #expect(syncSource.contains("let uploadTasks = entries.map"))
        #expect(syncSource.contains("for uploadTask in uploadTasks"))
        #expect(syncSource.contains(
            "candidateScanIds: undispatchedScanIDs"
        ))
        #expect(syncSource.contains("finalPolicy.isOnline"))
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
        #expect(fetched.queueAttemptCount == 0)
        #expect(!fetched.queueNeedsAttention)
    }

    @Test func testRetryQueuedScanNowRejectsLegacyExternalImport() throws {
        let ctx = try createIsolatedContext()
        let manager = OfflineQueueManager.shared
        let scanId = UUID().uuidString.lowercased()
        let retryAt = Date().addingTimeInterval(600)
        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .externalImport,
            queueAttemptCount: 2,
            queueNextRetryAt: retryAt,
            queueLastErrorCode: "legacy_external_import",
            queueLastErrorMessage: "This legacy row cannot be replayed.",
            queueNeedsAttention: true
        )
        ctx.insert(scan)
        try ctx.save()

        let didRetry = manager.retryQueuedScanNow(scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let fetched = try #require(ctx.fetch(descriptor).first)
        #expect(!didRetry)
        #expect(fetched.queueState == .externalImport)
        #expect(fetched.queueAttemptCount == 2)
        #expect(fetched.queueNextRetryAt == retryAt)
        #expect(fetched.queueLastErrorCode == "legacy_external_import")
        #expect(fetched.queueNeedsAttention)
    }

    @Test func testManualRetryResetsBudgetForDescriptionOnlyScan() async throws {
        let ctx = try createIsolatedContext()
        let manager = OfflineQueueManager.shared
        let originalIsOnline = manager.isOnline
        defer { manager.isOnline = originalIsOnline }
        manager.isOnline = false

        let scanId = UUID().uuidString.lowercased()
        let capturedMediaJSON = try #require(
            CapturedMediaSnapshot(items: [
                .description(
                    ObservationContext(freeText: "Perched beside the trail")
                )
            ]).jsonString
        )
        let scan = OfflineQueuedScan(
            id: scanId,
            capturedMediaJSON: capturedMediaJSON,
            scanState: .failed,
            queueAttemptCount:
                OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts,
            queueLastErrorCode: "automatic_retry_limit_reached",
            queueNeedsAttention: true
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .needsAttention,
            attemptCount:
                OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts,
            lastErrorCode: "automatic_retry_limit_reached"
        )
        ctx.insert(scan)
        ctx.insert(job)
        try ctx.save()

        let didRetry = manager.retryQueuedScanNow(scanId: scanId)

        let fetchedScan = try #require(
            ctx.fetch(
                FetchDescriptor<OfflineQueuedScan>(
                    predicate: #Predicate { $0.id == scanId }
                )
            ).first
        )
        let jobId = job.id
        let fetchedJob = try #require(
            ctx.fetch(
                FetchDescriptor<OfflineJobRecord>(
                    predicate: #Predicate { $0.id == jobId }
                )
            ).first
        )
        #expect(didRetry)
        #expect(fetchedScan.queueState == .staged)
        #expect(fetchedScan.queueAttemptCount == 0)
        #expect(fetchedScan.queueLastErrorCode == nil)
        #expect(!fetchedScan.queueNeedsAttention)
        #expect(fetchedJob.status == .pending)
        #expect(fetchedJob.attemptCount == 0)
        #expect(fetchedJob.lastErrorCode == nil)
    }

    @Test func testManualRetryResumesCompletedServerResultRecovery() async throws {
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
            inferenceImagePaths: ["already-analyzed.webp"],
            queueAttemptCount: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts,
            queueLastErrorCode: "server_result_local_recovery_exhausted",
            queueLastErrorMessage: "Local recovery paused.",
            queueNeedsAttention: true
        )
        scan.queueLastServerStatus = "complete"
        ctx.insert(scan)
        try ctx.save()

        let didRetry = manager.retryQueuedScanNow(scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let fetched = try #require(ctx.fetch(descriptor).first)
        #expect(didRetry)
        #expect(fetched.queueState == .inferencing)
        #expect(fetched.queueLastServerStatus == "complete")
        #expect(
            fetched.queueLastErrorCode
                == OfflineQueueManager.completedServerResultRecoveryCode
        )
        #expect(manager.hasDurableCompletedServerResult(scanId: scanId))
        #expect(!fetched.queueNeedsAttention)
    }

    @Test func persistedScanRetryRestoresAnActualSchedulerWake() throws {
        let manager = OfflineQueueManager.shared
        let scheduler = OfflineJobScheduler.shared
        let originalContext = manager.modelContext
        let originalIsOnline = manager.isOnline
        let context = try createIsolatedContext()
        let now = Date()
        let retryAt = now.addingTimeInterval(90)
        defer {
            scheduler.cancelScheduledWake(using: manager)
            manager.isOnline = originalIsOnline
            manager.modelContext = originalContext
        }

        manager.modelContext = context
        manager.isOnline = true
        scheduler.cancelScheduledWake()

        let scheduled = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            timestamp: now,
            scanState: .staged,
            queueNextRetryAt: retryAt
        )
        let ignoredNeedsAttention = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            timestamp: now,
            scanState: .staged,
            queueNextRetryAt: now.addingTimeInterval(10),
            queueNeedsAttention: true
        )
        let ignoredFailed = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            timestamp: now,
            scanState: .failed,
            queueNextRetryAt: now.addingTimeInterval(5)
        )
        context.insert(scheduled)
        context.insert(ignoredNeedsAttention)
        context.insert(ignoredFailed)
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(
                scanId: ignoredNeedsAttention.id
            ),
            kind: .scanIngestion,
            subjectId: ignoredNeedsAttention.id,
            status: .waiting,
            nextRunAt: now.addingTimeInterval(10)
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(
                scanId: ignoredFailed.id
            ),
            kind: .scanIngestion,
            subjectId: ignoredFailed.id,
            status: .waiting,
            nextRunAt: now.addingTimeInterval(5)
        ))
        context.insert(OfflineJobRecord(
            id: "test-collection-retry",
            kind: .collectionSync,
            status: .waiting,
            nextRunAt: now.addingTimeInterval(120)
        ))
        try context.save()

        let persistedWake = try #require(
            scheduler.nextPersistedWakeDate(using: manager)
        )
        #expect(abs(persistedWake.timeIntervalSince(retryAt)) < 0.1)

        scheduler.scheduleNextPersistedWake(using: manager, now: now)

        let wakeDate = try #require(scheduler.scheduledWakeDate)
        #expect(abs(wakeDate.timeIntervalSince(retryAt)) < 0.1)
        #expect(QueuedScanContext(from: scheduled).canRetryNow)
    }

    @Test func retryUpdateReportsOnlyCommittedPersistence() throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        defer { manager.modelContext = originalContext }

        manager.modelContext = nil
        #expect(
            manager.updateQueuedScanForRetry(
                scanId: UUID().uuidString.lowercased(),
                code: "test_retry",
                message: "Test retry",
                delay: 5,
                resetTo: .pending
            ) == nil
        )

        let context = try createIsolatedContext()
        let scan = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            timestamp: Date(),
            scanState: .uploading
        )
        context.insert(scan)
        try context.save()

        let attempt = manager.updateQueuedScanForRetry(
            scanId: scan.id,
            code: "test_retry",
            message: "Test retry",
            delay: 5,
            resetTo: .pending
        )
        #expect(attempt == 1)
        #expect(scan.queueAttemptCount == 1)
        #expect(scan.queueState == .pending)
        #expect(scan.queueNextRetryAt != nil)
    }

    @Test func stalePersistedRetrySchedulesImmediateBoundedWake() throws {
        let manager = OfflineQueueManager.shared
        let scheduler = OfflineJobScheduler.shared
        let originalContext = manager.modelContext
        let originalIsOnline = manager.isOnline
        let context = try createIsolatedContext()
        let now = Date()
        defer {
            scheduler.cancelScheduledWake(using: manager)
            manager.isOnline = originalIsOnline
            manager.modelContext = originalContext
        }

        manager.modelContext = context
        manager.isOnline = true
        scheduler.cancelScheduledWake()
        context.insert(OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            timestamp: now,
            scanState: .staged,
            queueNextRetryAt: now.addingTimeInterval(-60)
        ))
        try context.save()

        scheduler.scheduleNextPersistedWake(using: manager, now: now)

        let wakeDate = try #require(scheduler.scheduledWakeDate)
        #expect(wakeDate.timeIntervalSince(now) >= 0.9)
        #expect(wakeDate.timeIntervalSince(now) <= 1.1)
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
