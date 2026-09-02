import Foundation
import Testing

@testable import Merian

@MainActor
@Suite(
    "Inference Live Result Integration",
    .serialized,
    .sharedProcessState(.networkClientOverrides)
)
struct InferenceLiveResultIntegrationTests {
    @Test(arguments: [true, false])
    func bothPipelinesPublishConfidenceZeroCompletion(nonVisual: Bool) async throws {
        try await InferenceLiveEngineTestSupport.withState {
            var requests: [InferenceLiveResultService.PersistenceRequest] = []
            let resultService = InferenceLiveResultService(dependencies: .init(parseAndSave: { request in
                requests.append(request)
                return parsedResult(didComplete: true)
            }))
            let engine = InferenceLiveEngineTestSupport.makeEngine(resultService: resultService)
            defer { engine.cancelActiveRequest() }

            start(engine, nonVisual: nonVisual)
            let task = try #require(engine.inferenceTask)
            try await task.value

            #expect(requests.count == 1)
            let request = try #require(requests.first)
            #expect(request.skipImageRequirement == nonVisual)
            #expect(request.compressedDatas == (nonVisual ? [] : [Data([0x01])]))
            #expect(request.displayDatas == (nonVisual ? [] : [Data([0x11])]))
            #expect(request.persistenceFence == nil)
            #expect(engine.speciesData?.commonName == "No identification")
            #expect(engine.speciesData?.confidenceScore == 0)
            #expect(engine.speciesData?.isInferenceErrorPlaceholder == false)
            #expect(!engine.isProcessing)
            #expect(engine.activeScanId == nil)
            #expect(engine.activeLiveInferenceAttemptGeneration == nil)
        }
    }

    @Test(arguments: [true, false])
    func persistedCompletionPreservesMediaOrder(nonVisual: Bool) async throws {
        try await InferenceLiveEngineTestSupport.withState {
            let firstContext = ObservationContext(freeText: "striped wings")
            let lastContext = ObservationContext(freeText: "resting on a leaf")
            let timeline: [CaptureSubmissionMediaItem] = nonVisual
                ? [.description(firstContext), .description(lastContext)]
                : [.description(firstContext), .image(index: 0), .description(lastContext)]
            var requests: [InferenceLiveResultService.PersistenceRequest] = []
            let resultService = InferenceLiveResultService(dependencies: .init(parseAndSave: { request in
                requests.append(request)
                return parsedResult(
                    didComplete: true,
                    confidence: 0.95,
                    savedPaths: nonVisual ? [] : ["saved-image.jpg"]
                )
            }))
            let engine = InferenceLiveEngineTestSupport.makeEngine(resultService: resultService)
            defer { engine.cancelActiveRequest() }

            start(engine, nonVisual: nonVisual, mediaTimeline: timeline)
            let task = try #require(engine.inferenceTask)
            try await task.value

            #expect(requests.count == 1)
            let request = try #require(requests.first)
            #expect(request.mediaTimeline == timeline)
            #expect(request.audioFilePaths == nil)
            #expect(request.videoFilePaths == nil)
            let persistedContexts = try request.observationContextsJSON.map {
                try JSONDecoder().decode(ObservationContext.self, from: Data($0.utf8))
            }
            #expect(persistedContexts == [firstContext, lastContext])
            let expectedMedia: [MediaItem] = nonVisual
                ? [.description(firstContext), .description(lastContext)]
                : [.description(firstContext), .image("saved-image.jpg"), .description(lastContext)]
            #expect(engine.speciesData?.confidenceScore == 0.95)
            #expect(engine.activeMedia.items == expectedMedia)
            #expect(!engine.isProcessing)
        }
    }

    @Test(arguments: [true, false])
    func rejectedPersistenceDoesNotPublishSuccessOrAnError(nonVisual: Bool) async throws {
        try await InferenceLiveEngineTestSupport.withState {
            var parseCount = 0
            let resultService = InferenceLiveResultService(dependencies: .init(parseAndSave: { _ in
                parseCount += 1
                return parsedResult(didComplete: false)
            }))
            let engine = InferenceLiveEngineTestSupport.makeEngine(resultService: resultService)
            defer { engine.cancelActiveRequest() }

            start(engine, nonVisual: nonVisual)
            let task = try #require(engine.inferenceTask)
            try await task.value

            #expect(parseCount == 1)
            #expect(engine.speciesData == nil)
            #expect(!engine.isProcessing)
            #expect(engine.activeLiveInferenceAttemptGeneration == nil)
            #expect(!CircuitBreakerManager.shared.isCircuitTripped)
        }
    }

    @Test(arguments: [true, false])
    func stalePersistenceCannotOverwriteAReplacementAttempt(nonVisual: Bool) async throws {
        try await InferenceLiveEngineTestSupport.withState {
            let gate = InferenceOperationGate()
            let resultService = InferenceLiveResultService(dependencies: .init(parseAndSave: { _ in
                await gate.wait()
                return parsedResult(didComplete: true)
            }))
            let engine = InferenceLiveEngineTestSupport.makeEngine(resultService: resultService)
            defer { engine.cancelActiveRequest() }
            start(engine, nonVisual: nonVisual)
            let staleTask = try #require(engine.inferenceTask)
            await gate.waitUntilStarted()

            // Both attempts are queue-less. Without task cancellation, the
            // replaced local identity must reject the late persistence return.
            let replacementGeneration = UUID()
            engine.activeLiveInferenceAttemptGeneration = replacementGeneration
            engine.speciesData = replacementSpecies()
            engine.isProcessing = true
            await gate.release()
            try await staleTask.value

            #expect(engine.speciesData?.commonName == "Replacement result")
            #expect(engine.isProcessing)
            #expect(engine.activeLiveInferenceAttemptGeneration == replacementGeneration)
            #expect(!CircuitBreakerManager.shared.isCircuitTripped)
        }
    }

    private func start(
        _ engine: InferenceEngine,
        nonVisual: Bool,
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil
    ) {
        InferenceLiveEngineTestSupport.start(
            engine,
            mode: nonVisual ? .nonVisual(hasAudio: false) : .visual,
            mediaTimeline: mediaTimeline
        )
    }

    private func parsedResult(
        didComplete: Bool,
        confidence: Double = 0,
        savedPaths: [String] = []
    ) -> InferenceProcessingActor.ParseAndSaveResult {
        .init(
            mappedData: SpeciesData(
                // Fixtures omit the ID to keep notification,
                // milestone, and reference effects outside these tests.
                scanId: nil,
                commonName: confidence > 0 ? "Test subject" : "No identification",
                scientificName: "Unknown",
                insightData: InsightData(aiReasoning: "Test observation", hazardType: "none"),
                confidenceScore: confidence,
                isBiological: confidence > 0
            ),
            isNewDiscovery: false,
            savedPaths: savedPaths,
            planUsed: nil,
            didCompletePersistence: didComplete
        )
    }

    private func replacementSpecies() -> SpeciesData {
        SpeciesData(
            commonName: "Replacement result",
            scientificName: "Unknown",
            insightData: InsightData(aiReasoning: "Replacement observation", hazardType: "none"),
            confidenceScore: 0,
            isBiological: false
        )
    }
}
