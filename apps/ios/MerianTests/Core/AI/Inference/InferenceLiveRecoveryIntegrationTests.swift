import Foundation
import Testing

@testable import Merian

@MainActor
@Suite(
    "Inference Live Recovery Integration",
    .serialized,
    .sharedProcessState(.networkClientOverrides)
)
struct InferenceLiveRecoveryIntegrationTests {
    @Test(arguments: [
        InferenceLiveFailurePolicy.Mode.visual,
        .nonVisual(hasAudio: true),
        .nonVisual(hasAudio: false)
    ])
    func decodingFailuresKeepModalitySpecificPresentationAndCircuit(
        mode: InferenceLiveFailurePolicy.Mode
    ) async throws {
        try await InferenceLiveEngineTestSupport.withState {
            var parseCount = 0
            let engine = InferenceLiveEngineTestSupport.makeEngine(
                resultService: .init(dependencies: .init(parseAndSave: { _ in
                    parseCount += 1
                    throw MerianError.decodingFailed
                }))
            )
            defer { engine.cancelActiveRequest() }

            for attempt in 1...3 {
                InferenceLiveEngineTestSupport.start(engine, mode: mode)
                try await #require(engine.inferenceTask).value
                #expect(parseCount == attempt)
                #expect(engine.speciesData?.isInferenceErrorPlaceholder == true)
                #expect(engine.speciesData?.commonName == (mode == .visual ? "Analysis Failed" : "Analysis delayed"))
                #expect(engine.speciesData?.scientificName == (mode == .visual ? "Data Unreadable" : "Please try again"))
                #expect(engine.queuedPresentationScanId == nil)
                #expect(!engine.isProcessing)
                #expect(CircuitBreakerManager.shared.isCircuitTripped == (mode != .visual && attempt == 3))
            }
        }
    }

    @Test(arguments: [true, false], [
        "ai_request_already_completed", "ai_request_in_progress",
        "scan_already_complete", "scan_already_finalized"
    ])
    func recoverableConflictsPresentRestorationWithoutTrippingTheCircuit(
        nonVisual: Bool,
        code: String
    ) async throws {
        try await InferenceLiveEngineTestSupport.withState {
            var parseCount = 0
            let engine = InferenceLiveEngineTestSupport.makeEngine(
                resultService: .init(dependencies: .init(parseAndSave: { _ in
                    parseCount += 1
                    throw MerianError.httpError(statusCode: 409, message: #"{"code":"\#(code)"}"#)
                }))
            )
            defer { engine.cancelActiveRequest() }

            for attempt in 1...3 {
                InferenceLiveEngineTestSupport.start(
                    engine, mode: nonVisual ? .nonVisual(hasAudio: false) : .visual
                )
                try await #require(engine.inferenceTask).value
                #expect(parseCount == attempt)
                #expect(engine.speciesData?.commonName == "Restoring scan")
                #expect(engine.speciesData?.scientificName == "Safely saved")
                #expect(engine.speciesData?.isInferenceErrorPlaceholder == true)
                #expect(!CircuitBreakerManager.shared.isCircuitTripped)
                #expect(!engine.isProcessing)
                // Queue-less fixtures prove publication, not durable recovery.
                #expect(engine.recoverablePresentationScanId == nil)
                #expect(engine.queuedPresentationScanId == nil)
            }
        }
    }

    @Test(arguments: [true, false], [true, false])
    func replacedAttemptsRejectLateGenericAndPaywallFailures(
        nonVisual: Bool,
        quotaFailure: Bool
    ) async throws {
        try await InferenceLiveEngineTestSupport.withState {
            let gate = InferenceOperationGate()
            var paywallRequests = 0
            let engine = makeFailingEngine(
                gate: gate, quotaFailure: quotaFailure,
                requestPaywall: { paywallRequests += 1 }
            )
            defer { engine.cancelActiveRequest() }
            primeCircuitBelowThreshold()
            InferenceLiveEngineTestSupport.start(
                engine, mode: nonVisual ? .nonVisual(hasAudio: false) : .visual
            )
            let staleTask = try #require(engine.inferenceTask)
            await gate.waitUntilStarted()

            let replacementGeneration = UUID()
            engine.activeLiveInferenceAttemptGeneration = replacementGeneration
            engine.speciesData = replacementResult()
            engine.isProcessing = true
            await gate.release()
            try await staleTask.value

            #expect(engine.speciesData?.commonName == "Replacement result")
            #expect(engine.isProcessing)
            #expect(engine.activeLiveInferenceAttemptGeneration == replacementGeneration)
            #expect(engine.recoverablePresentationScanId == nil)
            #expect(engine.queuedPresentationScanId == nil)
            #expect(paywallRequests == 0)
            #expect(!CircuitBreakerManager.shared.isCircuitTripped)
        }
    }

    @Test(arguments: [true, false], [true, false])
    func taskCancellationPrecedesLateGenericAndPaywallFailures(
        nonVisual: Bool,
        quotaFailure: Bool
    ) async throws {
        try await InferenceLiveEngineTestSupport.withState {
            let gate = InferenceOperationGate()
            var paywallRequests = 0
            let engine = makeFailingEngine(
                gate: gate, quotaFailure: quotaFailure,
                requestPaywall: { paywallRequests += 1 }
            )
            defer { engine.cancelActiveRequest() }
            primeCircuitBelowThreshold()
            InferenceLiveEngineTestSupport.start(
                engine, mode: nonVisual ? .nonVisual(hasAudio: false) : .visual
            )
            let task = try #require(engine.inferenceTask)
            await gate.waitUntilStarted()

            // Keep the local identity intact: cancellation alone must suppress
            // the non-cooperative parser's subsequently thrown error.
            task.cancel()
            await gate.release()
            try await task.value

            #expect(engine.speciesData == nil)
            #expect(!engine.isProcessing)
            #expect(engine.activeLiveInferenceAttemptGeneration == nil)
            #expect(engine.queuedPresentationScanId == nil)
            #expect(paywallRequests == 0)
            #expect(!CircuitBreakerManager.shared.isCircuitTripped)
        }
    }

    @Test(arguments: [true, false], [true, false])
    func logicalAndTransportCancellationStaySilentWithoutQueueOwnership(
        nonVisual: Bool,
        transportCancellation: Bool
    ) async throws {
        try await InferenceLiveEngineTestSupport.withState {
            let engine = InferenceLiveEngineTestSupport.makeEngine(
                resultService: .init(dependencies: .init(parseAndSave: { _ in
                    if transportCancellation { throw URLError(.cancelled) }
                    throw CancellationError()
                }))
            )
            defer { engine.cancelActiveRequest() }
            primeCircuitBelowThreshold()
            InferenceLiveEngineTestSupport.start(
                engine, mode: nonVisual ? .nonVisual(hasAudio: false) : .visual
            )
            try await #require(engine.inferenceTask).value

            #expect(engine.speciesData == nil)
            #expect(!engine.isProcessing)
            #expect(engine.activeLiveInferenceAttemptGeneration == nil)
            #expect(engine.queuedPresentationScanId == nil)
            #expect(!CircuitBreakerManager.shared.isCircuitTripped)
        }
    }

    @Test(arguments: [true, false])
    func dailyQuotaUsesTheInjectedPaywallWithoutAnErrorResult(nonVisual: Bool) async throws {
        try await InferenceLiveEngineTestSupport.withState {
            var paywallRequests = 0
            let engine = InferenceLiveEngineTestSupport.makeEngine(
                resultService: .init(dependencies: .init(parseAndSave: { _ in
                    throw quotaError()
                })),
                requestPaywall: { paywallRequests += 1 }
            )
            defer { engine.cancelActiveRequest() }
            primeCircuitBelowThreshold()
            InferenceLiveEngineTestSupport.start(
                engine, mode: nonVisual ? .nonVisual(hasAudio: false) : .visual
            )
            try await #require(engine.inferenceTask).value

            #expect(paywallRequests == 1)
            #expect(engine.speciesData == nil)
            #expect(!engine.isProcessing)
            #expect(!CircuitBreakerManager.shared.isCircuitTripped)
        }
    }

    private func makeFailingEngine(
        gate: InferenceOperationGate,
        quotaFailure: Bool,
        requestPaywall: @escaping @MainActor () -> Void
    ) -> InferenceEngine {
        InferenceLiveEngineTestSupport.makeEngine(
            resultService: .init(dependencies: .init(parseAndSave: { _ in
                await gate.wait()
                if quotaFailure { throw quotaError() }
                throw MerianError.invalidResponse
            })),
            requestPaywall: requestPaywall
        )
    }

    private func primeCircuitBelowThreshold() {
        CircuitBreakerManager.shared.recordFailure()
        CircuitBreakerManager.shared.recordFailure()
        #expect(!CircuitBreakerManager.shared.isCircuitTripped)
    }

    private func quotaError() -> MerianError {
        .httpError(statusCode: 429, message: #"{"code":"ai_quota_daily_exceeded"}"#)
    }

    private func replacementResult() -> SpeciesData {
        SpeciesData(
            commonName: "Replacement result", scientificName: "Unknown",
            insightData: InsightData(aiReasoning: "Test observation", hazardType: "none"),
            confidenceScore: 0, isBiological: false
        )
    }
}
