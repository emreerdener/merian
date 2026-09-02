import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
@Suite(
    "Inference Integration Audit", .timeLimit(.minutes(1)),
    .sharedProcessState(.networkClientOverrides, .offlineQueueManager)
)
struct InferenceIntegrationAuditTests {
    enum Modality: CaseIterable {
        case visual, audio, describe

        var mode: InferenceLiveFailurePolicy.Mode {
            switch self {
            case .visual: .visual
            case .audio: .nonVisual(hasAudio: true)
            case .describe: .nonVisual(hasAudio: false)
            }
        }
    }

    @Test(arguments: Modality.allCases, [false, true])
    func authDrainWaitsForLiveResultAndRejectsLatePublication(modality: Modality, throwsFailure: Bool) async throws {
        try await InferenceLiveEngineTestSupport.withState {
            let gate = InferenceOperationGate()
            var parseCount = 0
            let service = InferenceLiveResultService(dependencies: .init(parseAndSave: { _ in
                parseCount += 1
                await gate.wait()
                if throwsFailure { throw URLError(.badServerResponse) }
                return parsedResult()
            }))
            let engine = InferenceLiveEngineTestSupport.makeEngine(resultService: service)
            defer { engine.cancelActiveRequest() }
            InferenceLiveEngineTestSupport.start(engine, mode: modality.mode)
            let liveTask = try #require(engine.inferenceTask)
            await gate.waitUntilStarted()

            engine.beginAuthTransitionWriteFence()
            var drainStarted = false
            var drainFinished = false
            let drain = Task { @MainActor in
                drainStarted = true
                await engine.awaitAuthTransitionWriteQuiescence()
                drainFinished = true
            }
            while !drainStarted { await Task.yield() }
            #expect(!drainFinished)
            #expect(liveTask.isCancelled)

            // Admission remains closed while the cancellation-ignoring producer
            // is draining. No replacement request may take its task slot.
            InferenceLiveEngineTestSupport.start(engine, mode: modality.mode)
            #expect(parseCount == 1)
            await gate.release()
            await drain.value
            try await liveTask.value

            #expect(drainFinished)
            #expect(engine.inferenceTask == nil)
            #expect(engine.speciesData == nil)
            #expect(engine.activeMedia.items.isEmpty)
            #expect(!engine.isProcessing)
            #expect(!engine.isEnrichmentLoading)
            #expect(!engine.isLookalikesLoading)
            #expect(!CircuitBreakerManager.shared.isCircuitTripped)
        }
    }

    @Test(arguments: Modality.allCases, [false, true])
    func noRecordOrMissingResultIDKeepsOriginalScan(modality: Modality, reportsPersistence: Bool) async throws {
        try await InferenceLiveEngineTestSupport.withState {
            let context = try makeContext()
            let original = LocalScanRecord(
                id: "original", speciesId: "original-species", scientificName: "Unknown", commonName: "Original"
            )
            original.customTags = ["garden"]
            original.fieldNotes = "Original field note"
            context.insert(original)
            try context.save()
            let service = InferenceLiveResultService(dependencies: .init(parseAndSave: { _ in
                parsedResult(confidence: reportsPersistence ? 0.95 : 0)
            }))
            let engine = InferenceLiveEngineTestSupport.makeEngine(resultService: service)
            defer { engine.cancelActiveRequest() }
            InferenceLiveEngineTestSupport.start(
                engine, mode: modality.mode,
                modelContext: context, targetEradicationScanId: original.id
            )
            let task = try #require(engine.inferenceTask)
            try await task.value

            let reader = ModelContext(context.container)
            let records = try reader.fetch(FetchDescriptor<LocalScanRecord>())
            #expect(records.map(\.id) == [original.id])
            #expect(records.first?.customTags == ["garden"])
            #expect(records.first?.fieldNotes == "Original field note")
            #expect(try reader.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 0)
            #expect(engine.speciesData?.confidenceScore == (reportsPersistence ? 0.95 : 0))
            #expect(!engine.isProcessing)
        }
    }

    @Test(arguments: Modality.allCases, [false, true])
    func suspendedResultCannotDeleteQueueOrOverwriteNewOwner(modality: Modality, replacesOwner: Bool) async throws {
        try await InferenceLiveEngineTestSupport.withState {
            let manager = OfflineQueueManager.shared
            let previousOnline = manager.isOnline
            let context = try makeContext()
            let scanId = UUID().uuidString.lowercased()
            let generation = UUID()
            let replacementGeneration = UUID()
            let job = OfflineJobRecord(
                id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
                kind: .scanIngestion, subjectId: scanId, status: .running,
                metadataJSON: InferenceGenerationMetadataContract.json(for: generation)
            )
            context.insert(OfflineQueuedScan(id: scanId, scanState: .pending))
            context.insert(job)
            try context.save()
            manager.modelContext = context
            manager.isOnline = false
            manager.foregroundInferenceGenerations[scanId] = generation
            manager.deferredLiveUploadScanIds.insert(scanId)
            let gate = InferenceOperationGate()
            let service = InferenceLiveResultService(dependencies: .init(parseAndSave: { request in
                #expect(request.persistenceFence?.scanId == scanId)
                #expect(request.persistenceFence?.generation == generation)
                await gate.wait()
                return parsedResult(scanId: scanId)
            }))
            let engine = InferenceLiveEngineTestSupport.makeEngine(resultService: service)
            var completionCount = 0
            let subscription = AppDIContainer.shared.appEventPublisher.publisher.sink { event in
                if case .foregroundBiologicalScanCompleted(let completedId) = event, completedId == scanId {
                    completionCount += 1
                }
            }
            defer {
                subscription.cancel()
                engine.activeScanId = nil
                engine.activeLiveInferenceAttemptGeneration = nil
                engine.activeForegroundInferenceGeneration = nil
                engine.cancelActiveRequest()
                manager.foregroundInferenceGenerations.removeValue(forKey: scanId)
                manager.startedForegroundInferenceGenerations.removeValue(forKey: scanId)
                manager.deferredLiveUploadScanIds.remove(scanId)
                manager.isOnline = previousOnline
            }
            InferenceLiveEngineTestSupport.start(
                engine, mode: modality.mode, modelContext: context,
                scanId: scanId, foregroundInferenceGeneration: generation
            )
            let task = try #require(engine.inferenceTask)
            await gate.waitUntilStarted()

            if replacesOwner {
                // A new exact durable/presentation owner supersedes this return,
                // even without cancelling the old Swift task.
                job.metadataJSON = InferenceGenerationMetadataContract.json(for: replacementGeneration)
                try context.save()
                manager.foregroundInferenceGenerations[scanId] = replacementGeneration
                manager.startedForegroundInferenceGenerations[scanId] = replacementGeneration
                manager.deferredLiveUploadScanIds.insert(scanId)
                engine.activeLiveInferenceAttemptGeneration = replacementGeneration
                engine.activeForegroundInferenceGeneration = replacementGeneration
            } else {
                engine.cancelActiveRequest()
            }
            await gate.release()
            try await task.value
            // Await only this fixture's exact retirement; never cancel host work.
            while manager.foregroundInferenceRetirementTasks.keys.contains(scanId) {
                await Task.yield()
            }

            let reader = ModelContext(context.container)
            #expect(try reader.fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.id) == [scanId])
            #expect(try reader.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
            #expect(completionCount == 0)
            #expect(engine.speciesData == nil)
            #expect(!engine.isEnrichmentLoading)
            #expect(!engine.isLookalikesLoading)
            if replacesOwner {
                #expect(manager.foregroundInferenceGenerations[scanId] == replacementGeneration)
                #expect(manager.startedForegroundInferenceGenerations[scanId] == replacementGeneration)
                #expect(manager.deferredLiveUploadScanIds.contains(scanId))
                #expect(engine.activeLiveInferenceAttemptGeneration == replacementGeneration)
                #expect(engine.isProcessing)
            } else {
                #expect(manager.foregroundInferenceGenerations[scanId] == nil)
                #expect(manager.startedForegroundInferenceGenerations[scanId] == nil)
                #expect(!manager.deferredLiveUploadScanIds.contains(scanId))
                #expect(!engine.isProcessing)
            }
        }
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func parsedResult(scanId: String? = nil, confidence: Double = 0.95) -> InferenceProcessingActor.ParseAndSaveResult {
        .init(
            mappedData: SpeciesData(
                scanId: scanId, commonName: "Test subject", scientificName: "Unknown",
                insightData: InsightData(aiReasoning: "Test observation", hazardType: "none"),
                confidenceScore: confidence, isBiological: scanId != nil
            ),
            isNewDiscovery: false, savedPaths: [], planUsed: nil, didCompletePersistence: true
        )
    }
}
