import Foundation
@testable import Merian
import SwiftData
import Testing

/// Composes durable restart, real response decoding/finalization and Insight binding.
/// The provider boundary is a synthetic response; this never starts a queue worker.
@MainActor
@Suite("Disk Backed Inference Acceptance")
struct DiskBackedInferenceAcceptanceTests {
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
        #expect(results.allSatisfy(\.wasCleaned))
        #expect(results.filter(\.isNewDiscovery).count == 1)

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
