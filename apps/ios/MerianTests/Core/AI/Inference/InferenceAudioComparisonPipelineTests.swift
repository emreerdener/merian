#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
@Suite("Inference Audio Comparison Pipeline")
struct InferenceAudioComparisonPipelineTests {
    @Test(arguments: ["saved", "no_match", "persistence_failed", "publication_failed", "queue_failed", "cancelled", "no_context"])
    func completionProofRequiresAllForegroundBoundaries(scenario: String) async throws {
        let fixture = AudioComparisonTestFixture()
        let harness = InferenceLivePipelineHarness()
        let isNoMatch = scenario == "no_match"
        harness.parsedResult = .init(
            mappedData: SpeciesData(
                scanId: fixture.assignment.scanId, commonName: "Synthetic subject", scientificName: "Synthetic taxon",
                insightData: InsightData(aiReasoning: "Synthetic observation", hazardType: "none"),
                confidenceScore: isNoMatch ? 0 : 0.95, isBiological: !isNoMatch, inferenceTier: "pro"
            ),
            isNewDiscovery: false, savedPaths: [], planUsed: "pro",
            didCompletePersistence: scenario != "persistence_failed"
        )
        let gate = InferenceOperationGate()
        if scenario == "cancelled" {
            harness.parseOperation = { [result = harness.parsedResult] in await gate.wait(); return result }
        }
        var queueFinalizations = 0
        let queue = InferenceLiveQueueService(dependencies: .init(
            releaseDeferredUpload: { _, _, _ in }, retireForegroundInference: { _, _, _, _ in },
            claimForegroundInferenceStart: { _, _ in true },
            isForegroundInferenceAttemptCurrent: { _, _ in true },
            foregroundInferenceGeneration: { _ in nil },
            deleteQueuedScan: { _, _, _ in queueFinalizations += 1; return scenario != "queue_failed" },
            rejectQueuedScan: { _, _, _ in true }, isForegroundInferenceProFunded: { _, _ in true }
        ))
        let service = InferenceLiveRequestService(dependencies: .init(
            makeComparisonCapture: { _, _ in fixture.capture },
            encodeVisualImages: { _ in [] }, uploadStagedVideoFiles: { _, _ in [] },
            identify: { request, _ in
                #expect(request.comparisonCapture === fixture.capture)
                try fixture.receive()
                return Data("synthetic-response".utf8)
            }
        ))
        let system = harness.makeSystem(queueService: queue, requestService: service)
        let session = try #require(system.pipeline.admit(scanId: fixture.assignment.scanId, foregroundGeneration: UUID(), modality: .nonVisual(hasAudio: true)))
        system.pipeline.activate(session)
        let schema = Schema([LocalScanRecord.self, OfflineQueuedScan.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let timeline: [CaptureSubmissionMediaItem] = [.audio("synthetic.wav")]
        let request = InferenceLivePipelineCoordinator.NonVisualRequest(
            session: session, submissionProjection: timeline.submissionMediaProjection,
            ownerMediaTimeline: [.audio(audioInputIndex: 0, sourceIndex: 0)], mediaTimeline: timeline,
            telemetry: DebugIdentificationReplayProfile.audioComparison(slot: .slot1).makeTelemetry(),
            modelContext: scenario == "no_context" ? nil : ModelContext(container), targetEradicationScanId: nil
        )
        let callbacks = InferenceLivePipelineCoordinator.Callbacks(
            finish: { _ in },
            publishCompletion: { completion in
                guard scenario != "publication_failed" else { return false }
                // Simulate the first draw while durable queue finalization is still pending.
                completion.comparisonCapture?.recordFirstRender(scanId: fixture.assignment.scanId)
                return true
            },
            scheduleHydration: { _ in }, applyFailure: { _ in }
        )
        let task = Task { await system.pipeline.executeNonVisual(request, callbacks: callbacks) }
        if scenario == "cancelled" { await gate.waitUntilStarted(); task.cancel(); await gate.release() }
        await task.value
        let qualifies = ["saved", "no_match"].contains(scenario)
        #expect(fixture.events.contains("finalized") == qualifies)
        #expect(fixture.events.contains("rendered") == (qualifies || scenario == "queue_failed"))
        if qualifies {
            #expect(queueFinalizations == 1)
            #expect(fixture.records.last?.contains(isNoMatch ? "completed_without_record" : "saved") == true)
        }
    }
}
#endif
