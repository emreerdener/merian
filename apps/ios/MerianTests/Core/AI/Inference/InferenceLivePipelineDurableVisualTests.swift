import Foundation
import Testing

@testable import Merian

@MainActor
@Suite("Inference Live Pipeline Durable Visual Success")
struct InferenceLivePipelineDurableVisualTests {
    @Test func finalizesExactQueueOwnerBeforeVisualFollowUps() async throws {
        let harness = InferenceLivePipelineHarness()
        harness.sendsRequestBodyCallback = false
        let system = harness.makeSystem()
        let generation = UUID()
        let session = try #require(system.pipeline.admit(
            scanId: "scan-a",
            foregroundGeneration: generation,
            modality: .visual
        ))
        system.pipeline.activate(session)
        harness.resetEvents()

        await system.pipeline.executeVisual(
            harness.visualRequest(session: session),
            callbacks: harness.visualCallbacks()
        )

        #expect(harness.events == [
            .circuitCheck,
            .encode,
            .identify,
            .localAnalysisCancelled,
            .parse,
            .completionPrepared,
            .completionCircuitSuccess,
            .completionTelemetry,
            .commit,
            .benchmark("response"),
            .delete("scan-a", generation),
            .notificationPreferenceRead,
            .notification,
            .benchmark("postflight"),
            .benchmark("total"),
            .hydration,
            .milestone,
            .finish(session.attemptGeneration)
        ])
        #expect(system.attempt.activeForegroundGeneration == nil)
    }
}
