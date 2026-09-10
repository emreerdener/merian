import Foundation
@testable import Merian
import os
import Testing

private actor CameraVideoRecordingControlledSleeper {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep() async {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func pendingCount() -> Int {
        continuations.count
    }

    func resumeOldest() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

@Suite("Camera video recording coordinator")
struct CameraVideoRecordingCoordinatorTests {
    @Test func installAndCompletionExposeOnlyTheActiveGeneration() async throws {
        let coordinator = CameraVideoRecordingCoordinator()
        let generation = makeGeneration(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let expected = CameraVideoRecording(
            fileURL: generation.outputURL,
            duration: 4.5
        )

        let recording: CameraVideoRecording = try await withCheckedThrowingContinuation { continuation in
            guard coordinator.install(
                generation: generation,
                maxDuration: 5,
                startHandler: nil,
                continuation: continuation
            ) else {
                Issue.record("Expected the first recording request to install")
                continuation.resume(throwing: TestFailure.setup)
                return
            }

            #expect(coordinator.activeGeneration == generation)
            #expect(coordinator.isActive(generation))

            guard let completion = coordinator.take(generation: generation) else {
                Issue.record("Expected the active generation to complete")
                continuation.resume(throwing: TestFailure.setup)
                return
            }
            #expect(coordinator.activeGeneration == nil)
            #expect(!coordinator.isActive(generation))
            #expect(coordinator.take(generation: generation) == nil)
            let copiedCompletion = completion
            #expect(completion.resume(returning: expected))
            #expect(!copiedCompletion.resume(throwing: TestFailure.setup))
        }

        #expect(recording.fileURL == expected.fileURL)
        #expect(recording.duration == expected.duration)
    }

    @Test func startClaimRequiresTheExactCallbackAndIsOneShot() async throws {
        let coordinator = CameraVideoRecordingCoordinator()
        let generation = makeGeneration(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        let startedAt = Date(timeIntervalSince1970: 1_234)

        let recording: CameraVideoRecording = try await withCheckedThrowingContinuation { continuation in
            guard coordinator.install(
                generation: generation,
                maxDuration: 7,
                startHandler: {},
                continuation: continuation
            ) else {
                Issue.record("Expected the recording request to install")
                continuation.resume(throwing: TestFailure.setup)
                return
            }

            #expect(coordinator.claimStart(
                callbackURL: URL(fileURLWithPath: "/tmp/wrong.mp4"),
                startedAt: startedAt
            ) == nil)
            #expect(coordinator.claimStop(
                generation: generation,
                scheduledAction: nil
            ))

            guard let context = coordinator.claimStart(
                callbackURL: generation.outputURL,
                startedAt: startedAt
            ) else {
                Issue.record("Expected the matching callback to claim start")
                let completion = coordinator.take(generation: generation)
                completion?.resume(throwing: TestFailure.setup)
                return
            }

            #expect(context.generation == generation)
            #expect(context.maxDuration == 7)
            #expect(context.stopWasRequested)
            #expect(context.handler != nil)
            #expect(coordinator.claimStart(
                callbackURL: generation.outputURL,
                startedAt: startedAt
            ) == nil)

            guard let completion = coordinator.take(generation: generation) else {
                Issue.record("Expected completion after the start claim")
                continuation.resume(throwing: TestFailure.setup)
                return
            }
            #expect(completion.startedAt == startedAt)
            completion.resume(returning: CameraVideoRecording(
                fileURL: generation.outputURL,
                duration: 0
            ))
        }

        #expect(recording.fileURL == generation.outputURL)
    }

    @Test func replacementActionsRejectStaleTimeoutAndStopWork() async throws {
        let coordinator = CameraVideoRecordingCoordinator()
        let generation = makeGeneration(id: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")
        let firedActionCount = OSAllocatedUnfairLock(initialState: 0)
        let fire: CameraVideoRecordingCoordinator.ScheduledActionHandler = { _ in
            firedActionCount.withLock { $0 += 1 }
        }

        let recording: CameraVideoRecording = try await withCheckedThrowingContinuation { continuation in
            guard coordinator.install(
                generation: generation,
                maxDuration: 5,
                startHandler: nil,
                continuation: continuation
            ) else {
                Issue.record("Expected the recording request to install")
                continuation.resume(throwing: TestFailure.setup)
                return
            }

            guard let firstTimeout = coordinator.scheduleTimeout(
                for: generation,
                after: 60,
                fire: fire
            ), let currentTimeout = coordinator.scheduleTimeout(
                for: generation,
                after: 60,
                fire: fire
            ), let firstStop = coordinator.scheduleStop(
                for: generation,
                after: 60,
                fire: fire
            ), let currentStop = coordinator.scheduleStop(
                for: generation,
                after: 60,
                fire: fire
            ) else {
                Issue.record("Expected scheduled actions for the active generation")
                let completion = coordinator.take(generation: generation)
                completion?.resume(throwing: TestFailure.setup)
                return
            }

            #expect(!coordinator.isCurrentTimeout(firstTimeout))
            #expect(coordinator.isCurrentTimeout(currentTimeout))
            #expect(coordinator.take(
                generation: generation,
                expectedTimeoutAction: firstTimeout
            ) == nil)
            #expect(!coordinator.claimStop(
                generation: generation,
                scheduledAction: firstStop
            ))
            #expect(coordinator.claimStop(
                generation: generation,
                scheduledAction: currentStop
            ))
            #expect(!coordinator.claimStop(
                generation: generation,
                scheduledAction: currentStop
            ))

            guard let completion = coordinator.take(
                generation: generation,
                expectedTimeoutAction: currentTimeout
            ) else {
                Issue.record("Expected the current timeout action to complete")
                continuation.resume(throwing: TestFailure.setup)
                return
            }
            completion.resume(returning: CameraVideoRecording(
                fileURL: generation.outputURL,
                duration: 5
            ))
        }

        #expect(recording.fileURL == generation.outputURL)
        #expect(firedActionCount.withLock { $0 } == 0)
    }

    @Test func replacedTaskDoesNotFireWhenSleepIgnoresCancellation() async throws {
        let sleeper = CameraVideoRecordingControlledSleeper()
        let coordinator = CameraVideoRecordingCoordinator(
            sleep: { _ in await sleeper.sleep() }
        )
        let generation = makeGeneration(id: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")
        let firedActions = OSAllocatedUnfairLock(
            initialState: [CameraVideoRecordingScheduledAction]()
        )

        let recording: CameraVideoRecording = try await withCheckedThrowingContinuation { continuation in
            guard coordinator.install(
                generation: generation,
                maxDuration: 5,
                startHandler: nil,
                continuation: continuation
            ) else {
                Issue.record("Expected the recording request to install")
                continuation.resume(throwing: TestFailure.setup)
                return
            }

            Task {
                defer {
                    coordinator.take(generation: generation)?
                        .resume(throwing: TestFailure.setup)
                }

                guard let firstTimeout = coordinator.scheduleTimeout(
                    for: generation,
                    after: 1,
                    fire: { action in
                        firedActions.withLock { $0.append(action) }
                    }
                ), await waitUntil({ await sleeper.pendingCount() == 1 }),
                let currentTimeout = coordinator.scheduleTimeout(
                    for: generation,
                    after: 2,
                    fire: { action in
                        firedActions.withLock { $0.append(action) }
                    }
                ), await waitUntil({ await sleeper.pendingCount() == 2 }) else {
                    Issue.record("Expected both scheduled tasks to enter the controlled sleeper")
                    return
                }

                await sleeper.resumeOldest()
                await sleeper.resumeOldest()
                guard await waitUntil({ firedActions.withLock { $0.count } == 1 }) else {
                    Issue.record("Expected only the replacement action to fire")
                    return
                }

                #expect(firedActions.withLock { $0 } == [currentTimeout])
                #expect(!coordinator.isCurrentTimeout(firstTimeout))
                guard let completion = coordinator.take(
                    generation: generation,
                    expectedTimeoutAction: currentTimeout
                ) else {
                    Issue.record("Expected the replacement timeout to complete")
                    return
                }
                #expect(completion.resume(returning: CameraVideoRecording(
                    fileURL: generation.outputURL,
                    duration: 2
                )))
            }
        }

        #expect(recording.fileURL == generation.outputURL)
    }

    @Test func callbackCompletionRejectsTheWrongURLAndClearsState() async throws {
        let coordinator = CameraVideoRecordingCoordinator()
        let generation = makeGeneration(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")

        let recording: CameraVideoRecording = try await withCheckedThrowingContinuation { continuation in
            guard coordinator.install(
                generation: generation,
                maxDuration: 5,
                startHandler: nil,
                continuation: continuation
            ) else {
                Issue.record("Expected the recording request to install")
                continuation.resume(throwing: TestFailure.setup)
                return
            }

            #expect(coordinator.take(
                callbackURL: URL(fileURLWithPath: "/tmp/recording-a.mp4")
            ) == nil)
            guard let completion = coordinator.take(
                callbackURL: generation.outputURL
            ) else {
                Issue.record("Expected the exact callback URL to complete")
                continuation.resume(throwing: TestFailure.setup)
                return
            }
            #expect(coordinator.take(callbackURL: generation.outputURL) == nil)
            completion.resume(returning: CameraVideoRecording(
                fileURL: generation.outputURL,
                duration: 5
            ))
        }

        #expect(recording.fileURL == generation.outputURL)
        #expect(coordinator.activeGeneration == nil)
    }

    @Test func cancellationAndDelegateCompletionRaceHasOneWinner() async throws {
        for offset in 0..<100 {
            let coordinator = CameraVideoRecordingCoordinator()
            let generation = CameraVideoRecordingGeneration(
                id: UUID(),
                outputURL: URL(fileURLWithPath: "/tmp/race-\(offset).mp4")
            )
            let completions = OSAllocatedUnfairLock(
                initialState: [CameraVideoRecordingCoordinator.Completion]()
            )

            let recording: CameraVideoRecording = try await withCheckedThrowingContinuation { continuation in
                guard coordinator.install(
                    generation: generation,
                    maxDuration: 5,
                    startHandler: nil,
                    continuation: continuation
                ) else {
                    Issue.record("Expected race request \(offset) to install")
                    continuation.resume(throwing: TestFailure.setup)
                    return
                }

                DispatchQueue.concurrentPerform(iterations: 2) { terminalPath in
                    let completion = if terminalPath == 0 {
                        coordinator.take(generation: generation)
                    } else {
                        coordinator.take(callbackURL: generation.outputURL)
                    }
                    if let completion {
                        completions.withLock { $0.append(completion) }
                    }
                }

                let winners = completions.withLock { $0 }
                #expect(winners.count == 1)
                guard let winner = winners.first else {
                    continuation.resume(throwing: TestFailure.setup)
                    return
                }
                winner.resume(returning: CameraVideoRecording(
                    fileURL: generation.outputURL,
                    duration: 1
                ))
            }

            #expect(recording.fileURL == generation.outputURL)
            #expect(coordinator.activeGeneration == nil)
        }
    }

    private func makeGeneration(id: String) -> CameraVideoRecordingGeneration {
        guard let uuid = UUID(uuidString: id) else {
            preconditionFailure("Invalid deterministic test UUID: \(id)")
        }
        return CameraVideoRecordingGeneration(
            id: uuid,
            outputURL: URL(fileURLWithPath: "/tmp/\(uuid.uuidString).mp4")
        )
    }

    private func waitUntil(
        _ condition: () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        while clock.now < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }

    private enum TestFailure: Error {
        case setup
    }
}
