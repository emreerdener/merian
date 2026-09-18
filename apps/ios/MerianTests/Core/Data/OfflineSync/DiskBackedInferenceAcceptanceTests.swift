import Foundation
@testable import Merian
import SwiftData
import Testing
import UIKit

/// Composes durable admission/restart, response persistence and Insight binding.
/// Provider responses and external completion effects are injected; the queue stays offline.
@MainActor
@Suite(
    "Disk Backed Inference Acceptance",
    .serialized,
    .sharedProcessState(.offlineQueueManager)
)
struct DiskBackedInferenceAcceptanceTests {
    @Test func visualAdmissionDispatchPersistenceAndInsightRejectDuplicateExecution() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }
        let manager = OfflineQueueManager.shared
        let previousContext = manager.modelContext
        let previousOnline = manager.isOnline
        let previousCount = manager.unsyncedItemsCount
        let container = try open(URL.temporaryDirectory.appendingPathComponent("visual-flow-\(UUID()).sqlite"))
        let context = ModelContext(container)
        let scanId = UUID().uuidString.lowercased()
        let generation = UUID()
        var filesToRemove: [String] = []
        manager.modelContext = context
        manager.isOnline = false
        defer {
            for path in filesToRemove {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(path))
            }
            manager.deferredLiveUploadScanIds.remove(scanId)
            manager.foregroundInferenceGenerations[scanId] = nil
            manager.startedForegroundInferenceGenerations[scanId] = nil
            manager.foregroundInferenceRetirementTasks.cancel(scanId)
            manager.modelContext = previousContext
            manager.isOnline = previousOnline
            manager.unsyncedItemsCount = previousCount
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { renderer in
            UIColor.green.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let imageData = try #require(image.jpegData(compressionQuality: 0.8))
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil,
            gpsElevation: nil, locationName: nil, weatherCondition: nil,
            weatherTemperatureF: nil, timeOfDay: nil, timestamp: "2026-09-18T00:00:00Z"
        )
        let didQueue = await withCheckedContinuation { continuation in
            manager.enqueueCapture(
                imageDatas: [imageData], telemetry: telemetry, scanId: scanId,
                foregroundInferenceGeneration: generation, startSyncImmediately: false,
                onQueued: { continuation.resume(returning: $0) }
            )
        }
        #expect(didQueue)
        let queued = try #require(ModelContext(container).fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let route = queued.queuedScanContext()
        filesToRemove += MediaJSONParser.imagePaths(jsonString: queued.capturedMediaJSON ?? "[]")
        #expect(filesToRemove.count == 1)
        let queuedPath = try #require(filesToRemove.first)
        #expect(try Data(contentsOf: URL.documentsDirectory.appendingPathComponent(queuedPath)) == imageData)
        var dispatchCount = 0
        let providerGate = InferenceOperationGate()
        let requestService = InferenceLiveRequestService(dependencies: .init(
            encodeVisualImages: { await InferenceProcessingActor.shared.encodeBase64(compressedDatas: $0) },
            uploadStagedVideoFiles: { _, _ in
                Issue.record("A still-image request must not stage video uploads")
                return []
            },
            identify: { request, _ in
                dispatchCount += 1
                // This executes at the real dispatch boundary, before returning synthetic provider bytes.
                let fresh = ModelContext(container)
                let queuedCount = try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>())
                let jobCount = try fresh.fetchCount(FetchDescriptor<OfflineJobRecord>())
                let scanCount = try fresh.fetchCount(FetchDescriptor<LocalScanRecord>())
                #expect(queuedCount == 1)
                #expect(jobCount == 1)
                #expect(scanCount == 0)
                #expect(request.clientScanId == scanId)
                #expect(request.durableQueueOwnsRecovery)
                #expect(request.base64ImageDatas == [imageData.base64EncodedString()])
                await providerGate.wait()
                return Data("""
                {"success":true,"data":{"scan_id":"\(scanId)","is_biological_subject":true,
                "is_live_capture":true,"ecology_type":"wild","is_invasive":false,
                "scientific_name":"Danaus plexippus","common_name":"Monarch Butterfly",
                "confidence_score":0.98,"insight_data":{"hazard_type":"none","ai_reasoning":"Synthetic fixture."}}}
                """.utf8)
            }
        ))
        let harness = InferenceLivePipelineHarness()
        let system = harness.makeSystem(queueService: .live, requestService: requestService, resultService: .live)
        let session = try #require(system.pipeline.admit(
            scanId: scanId, foregroundGeneration: generation, modality: .visual
        ))
        system.pipeline.activate(session)
        let timeline: [CaptureSubmissionMediaItem] = [.image(index: 0)]
        let request = InferenceLivePipelineCoordinator.VisualRequest(
            session: session, compressedImages: [imageData], displayImages: [imageData],
            submissionProjection: timeline.submissionMediaProjection, ownerMediaTimeline: nil,
            mediaTimeline: timeline, visualMediaItems: [.image(sourceIndex: 0)], telemetry: telemetry,
            preferredGoal: nil, modelContext: context, targetEradicationScanId: nil
        )
        let firstExecution = Task { @MainActor in
            await system.pipeline.executeVisual(request, callbacks: harness.visualCallbacks())
        }
        await providerGate.waitUntilStarted()
        #expect(system.pipeline.admit(scanId: scanId, foregroundGeneration: generation, modality: .visual) == nil)
        #expect(dispatchCount == 1)
        await providerGate.release()
        await firstExecution.value
        await system.pipeline.executeVisual(request, callbacks: harness.visualCallbacks())
        #expect(system.pipeline.admit(scanId: scanId, foregroundGeneration: generation, modality: .visual) == nil)
        #expect(dispatchCount == 1)
        for event in [InferenceLivePipelineHarness.Event.commit, .hydration, .notification, .milestone] {
            #expect(harness.events.filter { $0 == event }.count == 1)
        }
        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        // Completion retains the ingestion ledger for diagnostics; it must no longer be runnable.
        let jobs = try fresh.fetch(FetchDescriptor<OfflineJobRecord>())
        #expect(jobs.count == 1)
        #expect(jobs.first?.id == OfflineQueueManager.scanIngestionJobId(scanId: scanId))
        #expect(jobs.first?.status == .complete)
        #expect(jobs.first?.nextRunAt == nil)
        let records = try fresh.fetch(FetchDescriptor<LocalScanRecord>())
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.id == scanId)
        let savedPaths = MediaJSONParser.imagePaths(jsonString: record.capturedMediaJSON ?? "[]")
        filesToRemove += savedPaths
        #expect(savedPaths.count == 1)
        let savedPath = try #require(savedPaths.first)
        #expect(try Data(contentsOf: URL.documentsDirectory.appendingPathComponent(savedPath)) == imageData)
        let engine = InferenceEngine()
        defer { engine.cancelActiveRequest() }
        let insight = InsightSheetViewModel(inferenceEngine: engine)
        for _ in 0..<2 {
            insight.beginPresentationSession()
            #expect(insight.bindQueuedPresentationPreferringCompletedRecord(
                route, modelContext: ModelContext(container), inferenceEngine: engine
            ))
            #expect(insight.presentedLocalRecordScanId == scanId)
            #expect(engine.speciesData?.scanId == scanId)
            insight.endPresentationSession()
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
    }

    @Test func interruptedFileAdoptionRemovesPartialDestinationFiles() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = root.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.wav")
        let missing = root.appendingPathComponent("missing.wav")
        try Data("synthetic admission bytes".utf8).write(to: first)

        #expect(throws: CocoaError.self) {
            try OfflineCaptureFileStore.persistFiles(
                [first.path, missing.path], documentsDirectory: destination
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    @Test func describeAdmissionPersistsBeforeCompletionAndRestoresInsight() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }
        let manager = OfflineQueueManager.shared
        let previousContext = manager.modelContext
        let previousOnline = manager.isOnline
        let previousCount = manager.unsyncedItemsCount
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let url = URL.temporaryDirectory.appendingPathComponent("capture-flow-\(UUID()).sqlite")
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        let context = ModelContext(container)
        let scanId = UUID().uuidString.lowercased()
        let generation = UUID()
        manager.modelContext = context
        manager.isOnline = false
        defer {
            manager.inferenceRetryTasks.cancel(scanId)
            manager.activeInferenceGenerations[scanId] = nil
            manager.retiredInferenceGenerations.remove(generation)
            SyncStateManager.shared.forceIdle()
            manager.modelContext = previousContext
            manager.isOnline = previousOnline
            manager.unsyncedItemsCount = previousCount
        }
        manager.enqueueDescribe(
            observationContext: ObservationContext(freeText: "Synthetic butterfly observation"),
            telemetry: CaptureTelemetry(
                subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil,
                gpsElevation: nil, locationName: nil, weatherCondition: nil,
                weatherTemperatureF: nil, timeOfDay: nil, timestamp: "2026-09-18T00:00:00Z"
            ), scanId: scanId
        )
        // Read from an independent context before admitting any synthetic response.
        let queued = try #require(ModelContext(container).fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        #expect(queued.id == scanId)
        #expect(queued.queueState == .staged)
        let route = queued.queuedScanContext()
        let media = queued.capturedMediaJSON
        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(await actor.tryClaimForInference(scanId: scanId, generation: generation))
        #expect(manager.claimInferenceGeneration(scanId: scanId, proposedGeneration: generation) == generation)
        let response = Data("""
        {"success":true,"data":{"scan_id":"\(scanId)","is_biological_subject":true,
        "is_live_capture":true,"ecology_type":"wild","is_invasive":false,
        "scientific_name":"Danaus plexippus","common_name":"Monarch Butterfly",
        "confidence_score":0.98,"insight_data":{"hazard_type":"none","ai_reasoning":"Synthetic fixture."}}}
        """.utf8)
        let result = await BackgroundInferenceFinalizationService.live.processAndCleanupOfflineScan(
            resultData: response, originalImagePaths: [], scanId: scanId,
            originalTimestamp: queued.timestamp, capturedMediaJSON: media,
            expectedGeneration: generation, persistenceActor: actor
        )
        #expect(result.wasCleaned)
        #expect(await manager.deleteQueuedScan(
            scanId: scanId,
            inferenceExpectation: InferenceGenerationExpectation(generation: generation)
        ))
        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
        let engine = InferenceEngine()
        defer { engine.cancelActiveRequest() }
        let insight = InsightSheetViewModel(inferenceEngine: engine)
        insight.beginPresentationSession()
        #expect(insight.bindQueuedPresentationPreferringCompletedRecord(
            route, modelContext: fresh, inferenceEngine: engine
        ))
        #expect(insight.presentedLocalRecordScanId == scanId)
        #expect(engine.speciesData?.scanId == scanId)
        insight.endPresentationSession()
        insight.beginPresentationSession()
        #expect(insight.bindQueuedPresentationPreferringCompletedRecord(
            route, modelContext: fresh, inferenceEngine: engine
        ))
        #expect(insight.presentedLocalRecordScanId == scanId)
        insight.endPresentationSession()
    }

    @Test func reopenedQueueRejectsStaleAndDuplicateResultsAndRestoresInsight() async throws {
        let url = URL.temporaryDirectory.appendingPathComponent("acceptance-\(UUID()).sqlite")
        let scanId = UUID().uuidString.lowercased()
        let oldGeneration = UUID()
        let media = MediaJSONParser.jsonString(from: [
            .description(ObservationContext(freeText: "Synthetic butterfly observation"))
        ])
        // Intentionally keep SQLite/WAL until process exit, like MigrationPlanTests.
        try seedInterruptedStore(url: url, scanId: scanId, generation: oldGeneration, media: media)
        let container = try open(url)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.reconcileOrphanedInferencingScans(activeInferenceScanIds: [])
        let generation = UUID()
        #expect(await actor.tryClaimForInference(scanId: scanId, generation: generation))
        #expect(!(await actor.tryClaimForInference(scanId: scanId, generation: UUID())))

        let routeContext = ModelContext(container)
        let route = try #require(routeContext.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
            .queuedScanContext()
        let rejected = await deliver(scanId: scanId, generation: oldGeneration, media: media, actor: actor)
        #expect(!rejected.wasCleaned)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)

        // Two actor instances reproduce separate foreground/background contexts,
        // sharing the real per-scan persistence coordinator and SQLite store.
        let secondActor = BackgroundDatabaseActor(modelContainer: container)
        async let first = deliver(scanId: scanId, generation: generation, media: media, actor: actor)
        async let duplicate = deliver(scanId: scanId, generation: generation, media: media, actor: secondActor)
        let results = await [first, duplicate]
        let allDeliveriesCleaned = results.allSatisfy(\.wasCleaned)
        let newDiscoveryCount = results.filter(\.isNewDiscovery).count
        #expect(allDeliveriesCleaned)
        #expect(newDiscoveryCount == 1)

        let fresh = ModelContext(container)
        let records = try fresh.fetch(FetchDescriptor<LocalScanRecord>())
        #expect(records.count == 1)
        // Queue retirement belongs to the terminal delivery owner, outside this finalization seam.
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(records.first?.id == scanId)
        #expect(records.first?.capturedMediaJSON == media)

        let engine = InferenceEngine()
        defer { engine.cancelActiveRequest() }
        let insight = InsightSheetViewModel(inferenceEngine: engine)
        insight.beginPresentationSession()
        #expect(insight.bindQueuedPresentationPreferringCompletedRecord(
            route, modelContext: fresh, inferenceEngine: engine
        ))
        #expect(insight.queuedContext == nil)
        #expect(insight.presentedLocalRecordScanId == scanId)
        #expect(engine.speciesData?.scanId == scanId)
        let presentedGeneration = insight.scanBoundActionGeneration
        insight.endPresentationSession()
        #expect(!insight.revealBottomBarTools(
            expectedScanId: scanId, expectedGeneration: presentedGeneration
        ))
    }

    @Test func invalidResponseAfterRestartPreservesDurableWork() async throws {
        let url = URL.temporaryDirectory.appendingPathComponent("acceptance-\(UUID()).sqlite")
        let scanId = UUID().uuidString.lowercased()
        let generation = UUID()
        try seedInterruptedStore(url: url, scanId: scanId, generation: generation, media: nil)
        let container = try open(url)
        let result = await BackgroundInferenceFinalizationService.live.processAndCleanupOfflineScan(
            resultData: Data("interrupted response".utf8), originalImagePaths: [],
            scanId: scanId, originalTimestamp: Date(timeIntervalSince1970: 1),
            expectedGeneration: generation, persistenceActor: BackgroundDatabaseActor(modelContainer: container)
        )
        #expect(!result.wasCleaned)
        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

    @Test func rejectedStoreSavePreservesQueueForWritableRetry() async throws {
        let url = URL.temporaryDirectory.appendingPathComponent("acceptance-save-\(UUID()).sqlite")
        let scanId = UUID().uuidString.lowercased()
        let generation = UUID()
        try seedInterruptedStore(url: url, scanId: scanId, generation: generation, media: nil)
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let readOnly = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: url, allowsSave: false)
        ])
        let rejected = await deliver(
            scanId: scanId, generation: generation, media: nil,
            actor: BackgroundDatabaseActor(modelContainer: readOnly)
        )
        #expect(!rejected.wasCleaned)
        let writable = try open(url)
        let fresh = ModelContext(writable)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
        let retry = await deliver(
            scanId: scanId, generation: generation, media: nil,
            actor: BackgroundDatabaseActor(modelContainer: writable)
        )
        #expect(retry.wasCleaned)
        #expect(try ModelContext(writable).fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
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

    private func open(_ url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
    }

    private func seedInterruptedStore(url: URL, scanId: String, generation: UUID, media: String?) throws {
        let container = try open(url)
        let context = ModelContext(container)
        context.insert(OfflineQueuedScan(
            id: scanId, timestamp: Date(timeIntervalSince1970: 1),
            capturedMediaJSON: media, scanState: .inferencing
        ))
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId), kind: .scanIngestion,
            subjectId: scanId, status: .running,
            metadataJSON: InferenceGenerationMetadataContract.json(for: generation)
        ))
        try context.save()
    }

    private func deliver(
        scanId: String, generation: UUID, media: String?, actor: BackgroundDatabaseActor
    ) async -> OfflineScanProcessingResult {
        let response = Data("""
        {"success":true,"data":{"scan_id":"\(scanId)","is_biological_subject":true,
        "is_live_capture":true,"ecology_type":"wild","is_invasive":false,
        "scientific_name":"Danaus plexippus","common_name":"Monarch Butterfly",
        "confidence_score":0.98,"insight_data":{"hazard_type":"none","ai_reasoning":"Synthetic fixture."}}}
        """.utf8)
        return await BackgroundInferenceFinalizationService.live.processAndCleanupOfflineScan(
            resultData: response, originalImagePaths: [], scanId: scanId,
            originalTimestamp: Date(timeIntervalSince1970: 1), capturedMediaJSON: media,
            expectedGeneration: generation, persistenceActor: actor
        )
    }
}
