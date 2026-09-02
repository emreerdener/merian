import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
private final class LiveResultDependencyRecorder {
    var result: InferenceProcessingActor.ParseAndSaveResult
    private(set) var requests: [InferenceLiveResultService.PersistenceRequest] = []

    init(result: InferenceProcessingActor.ParseAndSaveResult) {
        self.result = result
    }

    var dependencies: InferenceLiveResultService.Dependencies {
        .init(parseAndSave: { [self] request in
            requests.append(request)
            return result
        })
    }
}

@MainActor
@Suite("Inference Live Result Service")
struct InferenceLiveResultServiceTests {
    @Test func visualInputPreservesImagesContextTimelineAndFence() async throws {
        let recorder = LiveResultDependencyRecorder(result: makeParsedResult())
        let service = InferenceLiveResultService(dependencies: recorder.dependencies)
        let schema = Schema(CurrentSchema.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let images = [Data([0x01]), Data([0x02])]
        let displayImages = [Data([0x11]), Data([0x12])]
        let timeline: [CaptureSubmissionMediaItem] = [
            .image(index: 0),
            .audio("first.wav"),
            .video("clip.mov", posterImageIndex: 1, audioFilePath: "clip.wav"),
            .description(ObservationContext(freeText: "striped wings")),
            .audio("last.wav")
        ]
        let fence = LiveInferencePersistenceFence(scanId: "scan-id", generation: UUID())
        let request = makeRequest(
            media: .visual(compressedImages: images, displayImages: displayImages),
            timeline: timeline,
            modelContext: context,
            fence: fence
        )
        var validationCount = 0

        let outcome = try await service.process(request) { validationCount += 1 }

        #expect(validationCount == 2)
        #expect(recorder.requests.count == 1)
        let input = try #require(recorder.requests.first)
        #expect(input.resultData == request.response.resultData)
        #expect(input.compressedDatas == images)
        #expect(input.displayDatas == displayImages)
        #expect(!input.skipImageRequirement)
        #expect(input.modelContext === context)
        #expect(input.mediaTimeline == timeline)
        #expect(input.audioFilePaths == ["first.wav", "clip.wav", "last.wav"])
        #expect(input.videoFilePaths == ["clip.mov"])
        #expect(input.observationContextsJSON == request.response.observationContextsJSON)
        #expect(input.persistenceFence == fence)
        #expect(input.telemetry.locationName == "Test Habitat")
        #expect(input.telemetry.subjectDistanceInMeters == 1.5)
        #expect(input.telemetry.zoomFactor == 2)
        #expect(input.telemetry.timestamp == "2026-09-02T12:00:00Z")
        #expect(input.telemetry.gpsLatitude == nil)
        #expect(input.telemetry.gpsLongitude == nil)

        guard case .persisted(let result) = outcome else {
            Issue.record("A saved biological result must be classified as persisted")
            return
        }
        #expect(result.speciesData.commonName == "Test subject")
        #expect(result.isNewDiscovery)
        #expect(result.savedImagePaths == ["saved-image.jpg"])
        #expect(result.planUsed == "pro")
        #expect(outcome.completedResult?.speciesData.scanId == "scan-id")
    }

    @Test func nonVisualInputUsesNoImagesAndRetainsProjectedAudioOrder() async throws {
        let recorder = LiveResultDependencyRecorder(result: makeParsedResult())
        let service = InferenceLiveResultService(dependencies: recorder.dependencies)
        let timeline: [CaptureSubmissionMediaItem] = [
            .description(ObservationContext(freeText: "soft repeating call")),
            .audio("second.wav"),
            .audio("first.wav")
        ]

        _ = try await service.process(makeRequest(timeline: timeline)) {}

        let input = try #require(recorder.requests.first)
        #expect(input.compressedDatas.isEmpty)
        #expect(input.displayDatas.isEmpty)
        #expect(input.skipImageRequirement)
        #expect(input.audioFilePaths == ["second.wav", "first.wav"])
        #expect(input.videoFilePaths == nil)
        #expect(input.mediaTimeline == timeline)
        #expect(input.modelContext == nil)
        #expect(input.persistenceFence == nil)
    }

    @Test(arguments: [true, false])
    func emptyOptionalMediaPathsStayNil(nonVisual: Bool) async throws {
        let recorder = LiveResultDependencyRecorder(result: makeParsedResult())
        let service = InferenceLiveResultService(dependencies: recorder.dependencies)
        let request = makeRequest(
            media: nonVisual ? .nonVisual : .visual(compressedImages: [Data([0x01])], displayImages: [])
        )

        _ = try await service.process(request) {}

        let input = try #require(recorder.requests.first)
        #expect(input.audioFilePaths == nil)
        #expect(input.videoFilePaths == nil)
        #expect(input.displayDatas.isEmpty, "Display-image fallback stays owned by the actor")
        #expect(input.observationContextsJSON == request.response.observationContextsJSON)
    }

    @Test func confidenceZeroStillProvidesACompletedPresentationResult() async throws {
        let recorder = LiveResultDependencyRecorder(result: makeParsedResult(confidence: 0))
        let service = InferenceLiveResultService(dependencies: recorder.dependencies)

        let outcome = try await service.process(makeRequest()) {}

        guard case .completedWithoutRecord(let result) = outcome else {
            Issue.record("Confidence-zero must be terminal without a local record")
            return
        }
        #expect(result.speciesData.confidenceScore == 0)
        #expect(!result.isNewDiscovery)
        #expect(result.savedImagePaths.isEmpty)
        #expect(outcome.completedResult?.speciesData.scanId == "scan-id")
    }

    @Test(arguments: [0.0, 0.95])
    func rejectedPersistenceNeverExposesACompletedResult(confidence: Double) async throws {
        let recorder = LiveResultDependencyRecorder(
            result: makeParsedResult(confidence: confidence, didComplete: false)
        )
        let service = InferenceLiveResultService(dependencies: recorder.dependencies)

        let outcome = try await service.process(makeRequest()) {}

        guard case .persistenceRejected = outcome else {
            Issue.record("The actor's completion proof is required regardless of confidence")
            return
        }
        #expect(outcome.completedResult == nil)
    }

    @Test func missingMappedResultFailsClosed() async throws {
        let recorder = LiveResultDependencyRecorder(result: .init(
            mappedData: nil,
            isNewDiscovery: false,
            savedPaths: [],
            planUsed: nil,
            didCompletePersistence: true
        ))
        let service = InferenceLiveResultService(dependencies: recorder.dependencies)

        let outcome = try await service.process(makeRequest()) {}

        #expect(outcome.completedResult == nil)
    }

    @Test func staleAttemptAtEntryCannotInvokePersistence() async {
        let recorder = LiveResultDependencyRecorder(result: makeParsedResult())
        let service = InferenceLiveResultService(dependencies: recorder.dependencies)

        await #expect(throws: CancellationError.self) {
            try await service.process(makeRequest()) { throw CancellationError() }
        }

        #expect(recorder.requests.isEmpty)
    }

    @Test(arguments: [true, false])
    func sameScanReplacementIsRevalidatedBeforeOutcomeMapping(didComplete: Bool) async throws {
        let gate = InferenceOperationGate()
        let originalFence = LiveInferencePersistenceFence(scanId: "scan-id", generation: UUID())
        let parsedResult = makeParsedResult(didComplete: didComplete)
        let service = InferenceLiveResultService(dependencies: .init(parseAndSave: { request in
            #expect(request.persistenceFence == originalFence)
            await gate.wait()
            return parsedResult
        }))
        var currentFence = originalFence
        var validationCount = 0
        let task = Task {
            try await service.process(makeRequest(fence: originalFence)) {
                validationCount += 1
                guard currentFence == originalFence else { throw CancellationError() }
            }
        }
        await gate.waitUntilStarted()
        currentFence = LiveInferencePersistenceFence(scanId: originalFence.scanId, generation: UUID())
        await gate.release()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(validationCount == 2)
    }

    @Test func cancellationIgnoringPersistenceCannotReturnACompletedResult() async {
        let gate = InferenceOperationGate()
        let parsedResult = makeParsedResult()
        let service = InferenceLiveResultService(dependencies: .init(parseAndSave: { _ in
            await gate.wait()
            return parsedResult
        }))
        let task = Task {
            try await service.process(makeRequest()) { try Task.checkCancellation() }
        }
        await gate.waitUntilStarted()
        task.cancel()
        await gate.release()

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func parserFailurePropagatesWithoutReclassifyingRecovery() async {
        let service = InferenceLiveResultService(dependencies: .init(parseAndSave: { _ in
            throw MerianError.decodingFailed
        }))
        var validationCount = 0

        await #expect(throws: MerianError.decodingFailed) {
            try await service.process(makeRequest()) { validationCount += 1 }
        }

        #expect(validationCount == 1)
    }

    @Test(arguments: [true, false])
    func liveAdapterHonorsConfidenceZeroScanIdentity(matchesFence: Bool) async throws {
        let response = makeResponse(confidence: 0)
        let fence = LiveInferencePersistenceFence(
            scanId: matchesFence ? "SCAN-ID" : "replacement-scan-id",
            generation: UUID()
        )
        let outcome = try await InferenceLiveResultService.live.process(
            makeRequest(response: response, fence: fence)
        ) {}

        if matchesFence {
            guard case .completedWithoutRecord(let result) = outcome else {
                Issue.record("Matching confidence-zero response must complete without a record")
                return
            }
            #expect(result.savedImagePaths.isEmpty)
            #expect(result.speciesData.confidenceScore == 0)
            #expect(result.speciesData.locationName == "Test Habitat")
            #expect(result.speciesData.zoomFactor == 2)
            #expect(result.planUsed == nil)
        } else {
            #expect(outcome.completedResult == nil)
        }
    }

    @Test func liveAdapterRequiresPersistenceForPositiveConfidence() async throws {
        let outcome = try await InferenceLiveResultService.live.process(
            makeRequest(response: makeResponse(confidence: 0.95))
        ) {}

        #expect(outcome.completedResult == nil)
    }

    @Test func liveAdapterPreservesDecodingFailure() async {
        await #expect(throws: MerianError.decodingFailed) {
            try await InferenceLiveResultService.live.process(makeRequest()) {}
        }
    }

    private func makeRequest(
        response: InferenceLiveRequestService.Response? = nil,
        media: InferenceLiveResultService.Media = .nonVisual,
        timeline: [CaptureSubmissionMediaItem] = [],
        modelContext: ModelContext? = nil,
        fence: LiveInferencePersistenceFence? = nil
    ) -> InferenceLiveResultService.Request {
        .init(
            response: response ?? .init(
                resultData: Data("provider-response".utf8),
                observationContextsJSON: [#"{ "freeText": "striped wings" }"#],
                receivedAt: 100
            ),
            telemetry: CaptureTelemetry(
                subjectDistanceInMeters: 1.5,
                gpsLatitude: nil,
                gpsLongitude: nil,
                gpsElevation: nil,
                locationName: "Test Habitat",
                weatherCondition: "clear",
                weatherTemperatureF: 70,
                timeOfDay: "day",
                timestamp: "2026-09-02T12:00:00Z",
                zoomFactor: 2,
                estimatedSizeCm: nil
            ),
            media: media,
            mediaTimeline: timeline,
            submissionProjection: timeline.submissionMediaProjection,
            modelContext: modelContext,
            persistenceFence: fence
        )
    }

    private func makeParsedResult(
        confidence: Double = 0.95,
        didComplete: Bool = true
    ) -> InferenceProcessingActor.ParseAndSaveResult {
        .init(
            mappedData: SpeciesData(
                scanId: "scan-id",
                commonName: "Test subject",
                scientificName: "Test species",
                insightData: InsightData(aiReasoning: "Test observation", hazardType: "none"),
                confidenceScore: confidence,
                isBiological: confidence > 0,
                isLiveCapture: true,
                isInvasive: false,
                ecologyType: "wild"
            ),
            isNewDiscovery: confidence > 0,
            savedPaths: confidence > 0 ? ["saved-image.jpg"] : [],
            planUsed: "pro",
            didCompletePersistence: didComplete
        )
    }

    private func makeResponse(confidence: Double) -> InferenceLiveRequestService.Response {
        .init(
            resultData: Data(
                """
                {"success":true,"data":{
                    "scan_id":"scan-id",
                    "common_name":"Test subject",
                    "scientific_name":"Test species",
                    "is_biological_subject":\(confidence > 0),
                    "confidence_score":\(confidence)
                }}
                """.utf8
            ),
            observationContextsJSON: [],
            receivedAt: 100
        )
    }
}
