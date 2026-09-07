import Foundation
@testable import Merian
import Testing

@Suite("Background Inference Dispatch")
@MainActor
struct BackgroundInferenceDispatchTests {
    @Test func preparationCanFinishBeforeTimeout() async throws {
        let value = try await BackgroundInferencePreparationRace.firstValue {
            "prepared"
        }

        #expect(value == "prepared")
    }

    @Test func timeoutWinsDeterministicallyAndCancelsPreparation() async {
        let recorder = CancellationRecorder()

        do {
            _ = try await BackgroundInferencePreparationRace.firstValue(
                timeout: {}
            ) {
                do {
                    try await Task.sleep(for: .seconds(30))
                    return "late"
                } catch {
                    await recorder.recordCancellation()
                    throw error
                }
            }
            Issue.record("The immediate timeout must win the race")
        } catch BackgroundInferencePreparationRace.Failure.timedOut {
            // Expected.
        } catch {
            Issue.record("Unexpected preparation error: \(error)")
        }

        let observedCancellation = await recorder.observedCancellation
        #expect(observedCancellation)
    }

    @Test func callerCancellationCancelsPreparationRace() async {
        let task = Task { @MainActor in
            try await BackgroundInferencePreparationRace.firstValue {
                try await Task.sleep(for: .seconds(30))
                return "late"
            }
        }

        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test func timeoutDoesNotAwaitNonCooperativePreparation() async {
        let gate = NonCooperativePreparationGate()
        let fallbackRelease = Task {
            try? await Task.sleep(for: .seconds(1))
            await gate.release()
        }
        let clock = ContinuousClock()
        let startedAt = clock.now

        do {
            _ = try await BackgroundInferencePreparationRace.firstValue(
                timeout: {}
            ) {
                await gate.waitIgnoringCancellation()
                await gate.recordCompletion(
                    observedCancellation: Task.isCancelled
                )
                return "late"
            }
            Issue.record("The immediate timeout must win the race")
        } catch BackgroundInferencePreparationRace.Failure.timedOut {
            // Expected.
        } catch {
            Issue.record("Unexpected preparation error: \(error)")
        }

        let elapsed = startedAt.duration(to: clock.now)
        #expect(elapsed < .milliseconds(500))
        await gate.release()
        fallbackRelease.cancel()
        #expect(await gate.waitForCompletion())
    }

    @Test func dispatchRevalidatesPreparationAcrossSuspensions() throws {
        let source = try OfflineSyncTestSupport.loadRepositorySource(
            at: Self.dispatchPath
        )
        let normalized = normalizedSource(source)

        #expect(normalized.components(
            separatedBy: "isInferencePreparationCurrent("
        ).count == 6)
        #expect(!source.contains("activeInferenceGenerations["))

        let firstTaskSnapshot = try #require(normalized.range(
            of: "let existingInferenceTasks = await backgroundSession.allTasks"
        ))
        let generationClaim = try #require(normalized.range(
            of: "guard claimInferenceGeneration(",
            range: firstTaskSnapshot.upperBound..<normalized.endIndex
        ))
        let serverRecovery = try #require(normalized.range(
            of: "let serverRecovery = await recoverCompletedInferenceFromServer(",
            range: generationClaim.upperBound..<normalized.endIndex
        ))
        let requestPreparation = try #require(normalized.range(
            of: "authenticatedRequest = try await prepareInferenceDownloadRequestWithTimeout(",
            range: serverRecovery.upperBound..<normalized.endIndex
        ))
        let secondTaskSnapshot = try #require(normalized.range(
            of: "let tasksBeforeDispatch = await backgroundSession.allTasks",
            range: requestPreparation.upperBound..<normalized.endIndex
        ))
        let durableActivation = try #require(normalized.range(
            of: "guard await queueActor.activateBackgroundAccountWork(",
            range: secondTaskSnapshot.upperBound..<normalized.endIndex
        ))
        let taskCreation = try #require(normalized.range(
            of: "let task = backgroundSession.downloadTask(",
            range: durableActivation.upperBound..<normalized.endIndex
        ))
        let resume = try #require(normalized.range(
            of: "task.resume()",
            range: taskCreation.upperBound..<normalized.endIndex
        ))

        #expect(firstTaskSnapshot.lowerBound < generationClaim.lowerBound)
        #expect(generationClaim.lowerBound < serverRecovery.lowerBound)
        #expect(serverRecovery.lowerBound < requestPreparation.lowerBound)
        #expect(requestPreparation.lowerBound < secondTaskSnapshot.lowerBound)
        #expect(secondTaskSnapshot.lowerBound < durableActivation.lowerBound)
        #expect(durableActivation.lowerBound < taskCreation.lowerBound)
        #expect(taskCreation.lowerBound < resume.lowerBound)
    }

    @Test func rejectedDispatchRetiresOwnershipBeforeCancellation() throws {
        let source = try OfflineSyncTestSupport.loadRepositorySource(
            at: Self.dispatchPath
        )
        let dispatchStart = try #require(source.range(
            of: "func dispatchInferenceDownloadTask("
        ))
        let activation = try #require(source.range(
            of: "guard await queueActor.activateBackgroundAccountWork(",
            range: dispatchStart.upperBound..<source.endIndex
        ))
        let taskCreation = try #require(source.range(
            of: "let task = backgroundSession.downloadTask(",
            range: activation.upperBound..<source.endIndex
        ))
        let retirementGate = try #require(source.range(
            of: "await Self.awaitDurableBackgroundWorkRetirement(",
            range: taskCreation.upperBound..<source.endIndex
        ))
        let retirement = try #require(source.range(
            of: "await self.retireRejectedBackgroundAccountWork(",
            range: retirementGate.upperBound..<source.endIndex
        ))
        let cancellation = try #require(source.range(
            of: "task.cancel()",
            range: retirement.upperBound..<source.endIndex
        ))
        let resume = try #require(source.range(
            of: "task.resume()",
            range: cancellation.upperBound..<source.endIndex
        ))

        #expect(activation.lowerBound < taskCreation.lowerBound)
        #expect(taskCreation.lowerBound < retirementGate.lowerBound)
        #expect(retirementGate.lowerBound < retirement.lowerBound)
        #expect(retirement.lowerBound < cancellation.lowerBound)
        #expect(cancellation.lowerBound < resume.lowerBound)
    }

    @Test func failedRetirementPreservesDurableGenerationOwnership() throws {
        let source = normalizedSource(
            try OfflineSyncTestSupport.loadRepositorySource(
                at: Self.dispatchPath
            )
        )
        let dispatchStart = try #require(source.range(
            of: "func dispatchInferenceDownloadTask("
        ))
        let nextMethod = try #require(source.range(
            of: "private func prepareInferenceDownloadRequestWithTimeout(",
            range: dispatchStart.upperBound..<source.endIndex
        ))
        let dispatchBody = source[
            dispatchStart.lowerBound..<nextMethod.lowerBound
        ]

        #expect(dispatchBody.contains(
            "var mustPreserveDurableInferenceOwnership = false"
        ))
        #expect(dispatchBody.contains(
            "if ownsInferenceGeneration, !didDispatch, !mustPreserveDurableInferenceOwnership { finishInferenceGeneration("
        ))
        let didRetireBranch = try #require(dispatchBody.range(
            of: "if didRetire {"
        ))
        let cancellation = try #require(dispatchBody.range(
            of: "task.cancel()",
            range: didRetireBranch.upperBound..<dispatchBody.endIndex
        ))
        let preservation = try #require(dispatchBody.range(
            of: "mustPreserveDurableInferenceOwnership = true",
            range: cancellation.upperBound..<dispatchBody.endIndex
        ))
        #expect(cancellation.lowerBound < preservation.lowerBound)
    }

    private static let dispatchPath =
        "apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceDispatch.swift"

    private func normalizedSource(_ source: String) -> String {
        source.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

private actor CancellationRecorder {
    private(set) var observedCancellation = false

    func recordCancellation() {
        observedCancellation = true
    }
}

private actor NonCooperativePreparationGate {
    private var isReleased = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: Bool?
    private var completionWaiters: [CheckedContinuation<Bool, Never>] = []

    func waitIgnoringCancellation() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func recordCompletion(observedCancellation: Bool) {
        completion = observedCancellation
        let waiters = completionWaiters
        completionWaiters.removeAll()
        waiters.forEach { $0.resume(returning: observedCancellation) }
    }

    func waitForCompletion() async -> Bool {
        if let completion { return completion }
        return await withCheckedContinuation { continuation in
            completionWaiters.append(continuation)
        }
    }
}
