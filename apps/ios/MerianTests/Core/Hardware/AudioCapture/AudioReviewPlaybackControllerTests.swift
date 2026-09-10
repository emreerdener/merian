import Foundation
import Testing

@testable import Merian

@MainActor
private final class AudioReviewPlaybackPlayerSpy: AudioReviewPlaybackPlayer {
    let duration: TimeInterval
    var currentTime: TimeInterval = 0
    private(set) var playCount = 0
    private(set) var stopCount = 0
    private let playsSuccessfully: Bool

    init(
        duration: TimeInterval = 10,
        playsSuccessfully: Bool = true
    ) {
        self.duration = duration
        self.playsSuccessfully = playsSuccessfully
    }

    func play() -> Bool {
        playCount += 1
        return playsSuccessfully
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class AudioReviewPlaybackPlayerFactory {
    private var players: [AudioReviewPlaybackPlayerSpy]

    init(players: [AudioReviewPlaybackPlayerSpy]) {
        self.players = players
    }

    func makePlayer(for _: URL) throws -> any AudioReviewPlaybackPlayer {
        guard !players.isEmpty else {
            throw CocoaError(.fileReadUnknown)
        }
        return players.removeFirst()
    }
}

@MainActor
private final class AudioReviewPlaybackCallbackProbe {
    private(set) var progressValues: [Double] = []
    private(set) var completionCount = 0

    func recordProgress(_ progress: Double) {
        progressValues.append(progress)
    }

    func recordCompletion() {
        completionCount += 1
    }
}

private actor AudioReviewPlaybackWaitGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    var waiterCount: Int { waiters.count }

    func releaseFirst() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }
}

private actor AudioReviewPlaybackLeaseProbe {
    private(set) var deactivationCount = 0

    func recordDeactivation() {
        deactivationCount += 1
    }
}

private struct AudioReviewPlaybackWaitFailure: Error {}

@Suite("Audio review playback controller")
@MainActor
struct AudioReviewPlaybackControllerTests {
    @Test("Stop before activation rejects the late lease and never starts playback")
    func stopBeforeActivationRejectsLateLease() async throws {
        let player = AudioReviewPlaybackPlayerSpy()
        let activationGate = AudioReviewPlaybackWaitGate()
        let leaseProbe = AudioReviewPlaybackLeaseProbe()
        let sessionCoordinator = makeSessionCoordinator()
        let lease = try await sessionCoordinator.activate(.playback)
        let callbacks = AudioReviewPlaybackCallbackProbe()
        let controller = AudioReviewPlaybackController(
            dependencies: .init(
                makePlayer: { _ in player },
                activateSession: {
                    await activationGate.wait()
                    return lease
                },
                deactivateSession: { returnedLease in
                    await leaseProbe.recordDeactivation()
                    await sessionCoordinator.deactivate(
                        ifCurrent: returnedLease
                    )
                },
                waitForProgressTick: {
                    try await Task.sleep(for: .seconds(60))
                },
                waitForCompletion: { _ in
                    try await Task.sleep(for: .seconds(60))
                }
            )
        )

        let started = controller.start(
            fileURL: temporaryAudioURL(),
            resumeProgress: 0,
            onProgress: { callbacks.recordProgress($0) },
            onCompletion: { callbacks.recordCompletion() }
        )
        #expect(started)
        try await waitUntil {
            await activationGate.waiterCount == 1
        }

        controller.stop()
        await activationGate.releaseFirst()
        try await waitUntil {
            await leaseProbe.deactivationCount == 1
        }

        #expect(player.playCount == 0)
        #expect(player.stopCount == 1)
        #expect(callbacks.completionCount == 0)
        #expect(callbacks.progressValues.isEmpty)
    }

    @Test("Failed player start finalizes playback and releases its lease")
    func failedPlayerStartFinalizesAndReleasesLease() async throws {
        let player = AudioReviewPlaybackPlayerSpy(
            playsSuccessfully: false
        )
        let completionGate = AudioReviewPlaybackWaitGate()
        let leaseProbe = AudioReviewPlaybackLeaseProbe()
        let sessionCoordinator = makeSessionCoordinator()
        let callbacks = AudioReviewPlaybackCallbackProbe()
        let controller = AudioReviewPlaybackController(
            dependencies: .init(
                makePlayer: { _ in player },
                activateSession: {
                    try await sessionCoordinator.activate(.playback)
                },
                deactivateSession: { lease in
                    await leaseProbe.recordDeactivation()
                    await sessionCoordinator.deactivate(ifCurrent: lease)
                },
                waitForProgressTick: {
                    try await Task.sleep(for: .seconds(60))
                },
                waitForCompletion: { _ in
                    await completionGate.wait()
                }
            )
        )

        let started = controller.start(
            fileURL: temporaryAudioURL(),
            resumeProgress: 0,
            onProgress: { callbacks.recordProgress($0) },
            onCompletion: { callbacks.recordCompletion() }
        )
        #expect(started)
        try await waitUntil {
            let deactivationCount = await leaseProbe.deactivationCount
            return callbacks.completionCount == 1 && deactivationCount == 1
        }

        let completionWaiterCount = await completionGate.waiterCount
        #expect(player.playCount == 1)
        #expect(player.stopCount == 1)
        #expect(completionWaiterCount == 0)
        #expect(callbacks.progressValues.isEmpty)
    }

    @Test("Completion wait failure finalizes playback and releases its lease")
    func completionWaitFailureFinalizesAndReleasesLease() async throws {
        let player = AudioReviewPlaybackPlayerSpy()
        let leaseProbe = AudioReviewPlaybackLeaseProbe()
        let sessionCoordinator = makeSessionCoordinator()
        let callbacks = AudioReviewPlaybackCallbackProbe()
        let controller = AudioReviewPlaybackController(
            dependencies: .init(
                makePlayer: { _ in player },
                activateSession: {
                    try await sessionCoordinator.activate(.playback)
                },
                deactivateSession: { lease in
                    await leaseProbe.recordDeactivation()
                    await sessionCoordinator.deactivate(ifCurrent: lease)
                },
                waitForProgressTick: {
                    try await Task.sleep(for: .seconds(60))
                },
                waitForCompletion: { _ in
                    throw AudioReviewPlaybackWaitFailure()
                }
            )
        )

        let started = controller.start(
            fileURL: temporaryAudioURL(),
            resumeProgress: 0,
            onProgress: { callbacks.recordProgress($0) },
            onCompletion: { callbacks.recordCompletion() }
        )
        #expect(started)
        try await waitUntil {
            let deactivationCount = await leaseProbe.deactivationCount
            return callbacks.completionCount == 1 && deactivationCount == 1
        }

        #expect(player.playCount == 1)
        #expect(player.stopCount == 1)
        #expect(callbacks.progressValues.isEmpty)
    }

    @Test("Cancelled completion cannot finish replacement playback")
    func staleCompletionCannotFinishReplacement() async throws {
        let firstPlayer = AudioReviewPlaybackPlayerSpy()
        let secondPlayer = AudioReviewPlaybackPlayerSpy()
        let playerFactory = AudioReviewPlaybackPlayerFactory(
            players: [firstPlayer, secondPlayer]
        )
        let completionGate = AudioReviewPlaybackWaitGate()
        let firstCallbacks = AudioReviewPlaybackCallbackProbe()
        let secondCallbacks = AudioReviewPlaybackCallbackProbe()
        let sessionCoordinator = makeSessionCoordinator()
        let controller = AudioReviewPlaybackController(
            dependencies: makeDependencies(
                playerFactory: playerFactory,
                sessionCoordinator: sessionCoordinator,
                completionGate: completionGate
            )
        )

        let firstStarted = controller.start(
            fileURL: temporaryAudioURL(),
            resumeProgress: 0,
            onProgress: { firstCallbacks.recordProgress($0) },
            onCompletion: { firstCallbacks.recordCompletion() }
        )
        #expect(firstStarted)
        try await waitUntil {
            let waiterCount = await completionGate.waiterCount
            return firstPlayer.playCount == 1 && waiterCount == 1
        }

        controller.stop()
        let secondStarted = controller.start(
            fileURL: temporaryAudioURL(),
            resumeProgress: 0,
            onProgress: { secondCallbacks.recordProgress($0) },
            onCompletion: { secondCallbacks.recordCompletion() }
        )
        #expect(secondStarted)
        try await waitUntil {
            let waiterCount = await completionGate.waiterCount
            return secondPlayer.playCount == 1 && waiterCount == 2
        }

        await completionGate.releaseFirst()
        try await Task.sleep(for: .milliseconds(20))
        controller.seek(to: 0.6)

        #expect(firstCallbacks.completionCount == 0)
        #expect(secondCallbacks.completionCount == 0)
        #expect(secondPlayer.currentTime == 6)

        await completionGate.releaseFirst()
        try await waitUntil {
            secondCallbacks.completionCount == 1
        }

        #expect(firstCallbacks.completionCount == 0)
        #expect(firstPlayer.stopCount == 1)
        #expect(secondPlayer.stopCount == 1)
    }

    @Test("Manager preserves resume progress and clears state on completion")
    func managerPreservesResumeProgressAndClearsCompletionState() async throws {
        let player = AudioReviewPlaybackPlayerSpy()
        let playerFactory = AudioReviewPlaybackPlayerFactory(players: [player])
        let completionGate = AudioReviewPlaybackWaitGate()
        let sessionCoordinator = makeSessionCoordinator()
        let playbackDependencies = makeDependencies(
            playerFactory: playerFactory,
            sessionCoordinator: sessionCoordinator,
            completionGate: completionGate
        )
        let manager = AudioCaptureManager(
            dependencies: .init(
                activateRecordingSession: { _ in
                    try await sessionCoordinator.activate(.playback)
                },
                deactivateAudioSession: { lease in
                    await sessionCoordinator.deactivate(ifCurrent: lease)
                },
                startEngine: { _ in },
                playback: playbackDependencies
            )
        )
        manager.debugStageRecordingForFinish(
            fileName: "review.wav",
            autoSubmitOnMaxDuration: false
        )
        manager.debugFinishRecording(reachedMaxDuration: false)
        manager.seekPlayback(to: 0.25)

        manager.playPendingRecording()
        #expect(manager.isPlaying)
        try await waitUntil {
            let waiterCount = await completionGate.waiterCount
            return player.playCount == 1 && waiterCount == 1
        }

        #expect(player.currentTime == 2.5)
        await completionGate.releaseFirst()
        try await waitUntil {
            !manager.isPlaying
        }

        #expect(manager.playbackProgress == 0)
        #expect(manager.pendingPlaybackPath == "review.wav")
    }

    @Test("Manager reset stops playback and releases the playback lease")
    func managerResetStopsPlaybackAndReleasesLease() async throws {
        let player = AudioReviewPlaybackPlayerSpy()
        let playerFactory = AudioReviewPlaybackPlayerFactory(players: [player])
        let completionGate = AudioReviewPlaybackWaitGate()
        let leaseProbe = AudioReviewPlaybackLeaseProbe()
        let sessionCoordinator = makeSessionCoordinator()
        let playbackDependencies = makeDependencies(
            playerFactory: playerFactory,
            sessionCoordinator: sessionCoordinator,
            completionGate: completionGate,
            leaseProbe: leaseProbe
        )
        let manager = AudioCaptureManager(
            dependencies: .init(
                activateRecordingSession: { _ in
                    try await sessionCoordinator.activate(.playback)
                },
                deactivateAudioSession: { lease in
                    await sessionCoordinator.deactivate(ifCurrent: lease)
                },
                startEngine: { _ in },
                playback: playbackDependencies
            )
        )
        manager.debugStageRecordingForFinish(
            fileName: "reset-review.wav",
            autoSubmitOnMaxDuration: false
        )
        manager.debugFinishRecording(reachedMaxDuration: false)
        manager.playPendingRecording()
        try await waitUntil {
            let waiterCount = await completionGate.waiterCount
            return player.playCount == 1 && waiterCount == 1
        }
        manager.seekPlayback(to: 0.6)

        manager.reset()
        await completionGate.releaseFirst()
        try await waitUntil {
            await leaseProbe.deactivationCount == 1
        }

        #expect(!manager.isPlaying)
        #expect(manager.playbackProgress == 0)
        #expect(manager.pendingPlaybackPath == nil)
        #expect(player.stopCount == 1)
    }

    private func makeDependencies(
        playerFactory: AudioReviewPlaybackPlayerFactory,
        sessionCoordinator: AudioSessionCoordinator,
        completionGate: AudioReviewPlaybackWaitGate,
        leaseProbe: AudioReviewPlaybackLeaseProbe? = nil
    ) -> AudioReviewPlaybackController.Dependencies {
        .init(
            makePlayer: { try playerFactory.makePlayer(for: $0) },
            activateSession: {
                try await sessionCoordinator.activate(.playback)
            },
            deactivateSession: { lease in
                if let leaseProbe {
                    await leaseProbe.recordDeactivation()
                }
                await sessionCoordinator.deactivate(ifCurrent: lease)
            },
            waitForProgressTick: {
                try await Task.sleep(for: .seconds(60))
            },
            waitForCompletion: { _ in
                await completionGate.wait()
            }
        )
    }

    private func makeSessionCoordinator() -> AudioSessionCoordinator {
        AudioSessionCoordinator(
            operations: .init(
                configureAndActivate: { _ in },
                deactivate: {}
            )
        )
    }

    private func temporaryAudioURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for playback state")
    }
}
