import Foundation
@testable import Merian
import os
import Testing

private actor CameraPhotoCaptureControlledSleeper {
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

@Suite("Camera photo capture coordinator")
struct CameraPhotoCaptureCoordinatorTests {
    @Test func cancellationBeforeRegistrationResumesAndClearsReservation() async {
        let coordinator = CameraPhotoCaptureCoordinator()
        let requestID: Int64 = 101

        #expect(coordinator.reserve(id: requestID))
        #expect(coordinator.cancel(id: requestID))

        do {
            let _: Data = try await withCheckedThrowingContinuation { continuation in
                #expect(!coordinator.register(
                    id: requestID,
                    continuation: continuation
                ))
            }
            Issue.record("Expected cancellation to win before registration")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }

        #expect(coordinator.pendingRequestCount == 0)
        #expect(!coordinator.cancel(id: requestID))
    }

    @Test func completionClaimsRequestExactlyOnce() async throws {
        let coordinator = CameraPhotoCaptureCoordinator()
        let requestID: Int64 = 102
        let expected = Data([0xCA, 0xFE])
        var didEvaluateLateResult = false

        #expect(coordinator.reserve(id: requestID))
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            #expect(coordinator.register(
                id: requestID,
                continuation: continuation
            ))
            #expect(coordinator.resolve(id: requestID) { .success(expected) })
            #expect(!coordinator.resolve(id: requestID) {
                didEvaluateLateResult = true
                return .success(Data())
            })
            #expect(!coordinator.cancel(id: requestID))
        }

        #expect(data == expected)
        #expect(!didEvaluateLateResult)
        #expect(coordinator.pendingRequestCount == 0)
    }

    @Test func cancellationClaimsActiveRequestExactlyOnce() async {
        let coordinator = CameraPhotoCaptureCoordinator()
        let requestID: Int64 = 103

        #expect(coordinator.reserve(id: requestID))

        do {
            let _: Data = try await withCheckedThrowingContinuation { continuation in
                #expect(coordinator.register(
                    id: requestID,
                    continuation: continuation
                ))
                #expect(coordinator.cancel(id: requestID))
                #expect(!coordinator.cancel(id: requestID))
                #expect(!coordinator.resolve(id: requestID) { .success(Data()) })
            }
            Issue.record("Expected active request cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }

        #expect(coordinator.pendingRequestCount == 0)
    }

    @Test func cancellationAndCompletionRaceHasExactlyOneWinner() async {
        for offset in 0..<100 {
            let coordinator = CameraPhotoCaptureCoordinator()
            let requestID = Int64(1_000 + offset)
            let winnerCount = OSAllocatedUnfairLock(initialState: 0)

            #expect(coordinator.reserve(id: requestID))

            do {
                let _: Data = try await withCheckedThrowingContinuation { continuation in
                    #expect(coordinator.register(
                        id: requestID,
                        continuation: continuation
                    ))

                    DispatchQueue.concurrentPerform(iterations: 2) { terminalPath in
                        let won = if terminalPath == 0 {
                            coordinator.cancel(id: requestID)
                        } else {
                            coordinator.resolve(id: requestID) {
                                .success(Data([0x01]))
                            }
                        }
                        if won {
                            winnerCount.withLock { $0 += 1 }
                        }
                    }
                }
            } catch is CancellationError {
                // Either terminal path may win.
            } catch {
                Issue.record("Expected success or CancellationError, received \(error)")
            }

            #expect(winnerCount.withLock { $0 } == 1)
            #expect(coordinator.pendingRequestCount == 0)
        }
    }

    @Test func timeoutResumesWithExistingCameraErrorContract() async {
        let sleeper = CameraPhotoCaptureControlledSleeper()
        let coordinator = CameraPhotoCaptureCoordinator(
            timeoutNanoseconds: 1,
            sleep: { _ in await sleeper.sleep() }
        )
        let requestID: Int64 = 104

        #expect(coordinator.reserve(id: requestID))
        let captureTask = Task<Data, Error> {
            try await withCheckedThrowingContinuation { continuation in
                #expect(coordinator.register(
                    id: requestID,
                    continuation: continuation
                ))
            }
        }

        guard await waitForPendingSleep(in: sleeper) else {
            #expect(coordinator.cancel(id: requestID))
            _ = await captureTask.result
            Issue.record("Timed out waiting for the photo timeout task")
            return
        }
        await sleeper.resumeOldest()

        do {
            _ = try await captureTask.value
            Issue.record("Expected the shutter timeout")
        } catch let error as NSError {
            #expect(error.domain == "CameraManager")
            #expect(error.code == -4)
            #expect(error.localizedDescription == "Hardware shutter timed out")
        }

        #expect(coordinator.pendingRequestCount == 0)
        #expect(!coordinator.resolve(id: requestID) { .success(Data()) })
    }

    @Test func identifierCanBeReservedAgainAfterTerminalResolution() async throws {
        let coordinator = CameraPhotoCaptureCoordinator()
        let requestID: Int64 = 105

        #expect(coordinator.reserve(id: requestID))
        let first: Data = try await withCheckedThrowingContinuation { continuation in
            #expect(coordinator.register(
                id: requestID,
                continuation: continuation
            ))
            #expect(coordinator.resolve(id: requestID) { .success(Data([1])) })
        }
        #expect(first == Data([1]))

        #expect(coordinator.reserve(id: requestID))
        #expect(coordinator.cancel(id: requestID))

        do {
            let _: Data = try await withCheckedThrowingContinuation { continuation in
                #expect(!coordinator.register(
                    id: requestID,
                    continuation: continuation
                ))
            }
            Issue.record("Expected the replacement reservation to preserve cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }

        #expect(coordinator.pendingRequestCount == 0)
    }

    private func waitForPendingSleep(
        in sleeper: CameraPhotoCaptureControlledSleeper
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        while clock.now < deadline {
            if await sleeper.pendingCount() == 1 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(1))
        }

        return false
    }
}
