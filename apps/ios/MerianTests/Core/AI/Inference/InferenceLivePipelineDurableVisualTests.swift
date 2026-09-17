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

    @Test func completedAttemptCannotDispatchOrPublishTwice() async throws {
        let harness = InferenceLivePipelineHarness()
        harness.sendsRequestBodyCallback = false
        let system = harness.makeSystem()
        let session = try #require(system.pipeline.admit(
            scanId: "duplicate-delivery", foregroundGeneration: UUID(), modality: .visual
        ))
        system.pipeline.activate(session)
        let request = harness.visualRequest(session: session)
        await system.pipeline.executeVisual(request, callbacks: harness.visualCallbacks())
        harness.resetEvents()
        await system.pipeline.executeVisual(request, callbacks: harness.visualCallbacks())
        #expect(!harness.events.contains(.identify))
        #expect(!harness.events.contains(.parse))
        #expect(!harness.events.contains(.commit))
        #expect(!harness.events.contains(.hydration))
        #expect(!harness.events.contains(.notification))
        #expect(!harness.events.contains(.milestone))
    }

    @Test func cancellationDuringPersistenceSuppressesLatePublication() async throws {
        let gate = InferenceOperationGate()
        let harness = InferenceLivePipelineHarness()
        harness.sendsRequestBodyCallback = false
        harness.parseOperation = { [result = harness.parsedResult] in
            await gate.wait()
            return result
        }
        let system = harness.makeSystem()
        let session = try #require(system.pipeline.admit(
            scanId: "cancelled-persistence", foregroundGeneration: UUID(), modality: .visual
        ))
        system.pipeline.activate(session)
        let task = Task { @MainActor in
            await system.pipeline.executeVisual(
                harness.visualRequest(session: session), callbacks: harness.visualCallbacks()
            )
        }
        await gate.waitUntilStarted()
        task.cancel()
        await gate.release()
        await task.value
        #expect(!harness.events.contains(.commit))
        #expect(!harness.events.contains(.hydration))
        #expect(!harness.events.contains(.notification))
        #expect(!harness.events.contains(.milestone))
        #expect(system.attempt.activeForegroundGeneration == nil)
    }

}
