import Foundation
import Testing

@testable import Merian

private enum AudioPlaybackSessionControllerTestError: Error {
    case activationFailed
}

private final class AudioPlaybackSessionOperationsProbe: @unchecked Sendable {
    struct Snapshot {
        let activationCount: Int
        let deactivationCount: Int
        let configurations: [AudioSessionCoordinator.Configuration]
    }

    private let lock = NSLock()
    private var remainingActivationFailures = 0
    private var activationCount = 0
    private var deactivationCount = 0
    private var configurations: [AudioSessionCoordinator.Configuration] = []

    func failNextActivation() {
        lock.withLock {
            remainingActivationFailures = 1
        }
    }

    func configureAndActivate(
        _ configuration: AudioSessionCoordinator.Configuration
    ) throws {
        let shouldFail = lock.withLock {
            activationCount += 1
            configurations.append(configuration)
            guard remainingActivationFailures > 0 else { return false }
            remainingActivationFailures -= 1
            return true
        }
        if shouldFail {
            throw AudioPlaybackSessionControllerTestError.activationFailed
        }
    }

    func deactivate() {
        lock.withLock {
            deactivationCount += 1
        }
    }

    var snapshot: Snapshot {
        lock.withLock {
            Snapshot(
                activationCount: activationCount,
                deactivationCount: deactivationCount,
                configurations: configurations
            )
        }
    }
}

private final class AudioPlaybackReleaseProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var releaseCount = 0

    func recordRelease() {
        lock.withLock {
            releaseCount += 1
        }
    }

    var count: Int {
        lock.withLock { releaseCount }
    }
}

private actor AudioPlaybackActivationGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    var waiterCount: Int { waiters.count }

    func releaseAll() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

@Suite("Mounted audio playback session controller")
struct AudioPlaybackSessionControllerTests {
    @Test("Shared audio playback delegates session mutation to its controller")
    func sharedPlaybackHasNoDirectAudioSessionMutation() throws {
        let root = try repositoryRoot()
        let controllerSource = try String(
            contentsOf: root.appendingPathComponent(
                "apps/ios/Merian/Core/Media/AudioPlaybackSessionController.swift"
            ),
            encoding: .utf8
        )
        #expect(!controllerSource.contains("import AVFoundation"))

        let dependenciesSource = try String(
            contentsOf: root.appendingPathComponent(
                "apps/ios/Merian/Core/Media/MediaPlaybackDependencies.swift"
            ),
            encoding: .utf8
        )
        #expect(!dependenciesSource.contains("import AVFoundation"))
        #expect(
            !dependenciesSource.contains("AVAudioSession.sharedInstance()")
        )

        let carouselSource = try String(
            contentsOf: root.appendingPathComponent(
                "apps/ios/Merian/Core/UI/Components/MediaCarousel/" +
                    "AudioPlayback/AudioPlaybackCarouselPage.swift"
            ),
            encoding: .utf8
        )
        #expect(carouselSource.contains("await sessionController.activate()"))
        #expect(
            carouselSource.components(
                separatedBy: "sessionController.activate()"
            ).count == 2
        )
        #expect(!carouselSource.contains("captureAndSwitchSession"))
        #expect(
            carouselSource.components(separatedBy: ".play()").count == 2
        )
        #expect(!carouselSource.contains("AVAudioSession.sharedInstance()"))

        let exploreMediaRoot = root.appendingPathComponent(
            "apps/ios/Merian/Features/Explore/Shared/Media"
        )
        let enumerator = FileManager.default.enumerator(
            at: exploreMediaRoot,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        let files = (enumerator?.allObjects as? [URL] ?? []).filter {
            $0.pathExtension == "swift"
        }
        #expect(!files.isEmpty)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("AVAudioSession.sharedInstance()"))
        }

        let exploreAudioSource = try String(
            contentsOf: exploreMediaRoot.appendingPathComponent(
                "Playback/ExplorePublicMediaView+Audio.swift"
            ),
            encoding: .utf8
        )
        #expect(!exploreAudioSource.contains("player.play()"))
        let exploreObservationSource = try String(
            contentsOf: exploreMediaRoot.appendingPathComponent(
                "Playback/ExplorePublicMediaView+Observation.swift"
            ),
            encoding: .utf8
        )
        #expect(exploreObservationSource.contains("startAudioPlayback(player)"))
    }

    @Test("Cleanup cannot deactivate a replacement recording lease")
    @MainActor
    func cleanupCannotDeactivateReplacement() async throws {
        let probe = AudioPlaybackSessionOperationsProbe()
        let releaseProbe = AudioPlaybackReleaseProbe()
        let coordinator = makeCoordinator(probe: probe)
        let controller = makeController(
            coordinator: coordinator,
            onRelease: { releaseProbe.recordRelease() }
        )

        #expect(await controller.activate())
        #expect(controller.hasActiveLease)
        let replacementLease = try await coordinator.activate(
            .recordMeasurement(preferredSampleRate: 48_000)
        )

        controller.deactivate()
        await waitForCondition { releaseProbe.count == 1 }
        #expect(!controller.hasActiveLease)
        #expect(probe.snapshot.deactivationCount == 0)
        #expect(
            probe.snapshot.configurations == [
                .playbackDucking,
                .recordMeasurement(preferredSampleRate: 48_000)
            ]
        )

        await coordinator.deactivate(ifCurrent: replacementLease)
        #expect(probe.snapshot.deactivationCount == 1)
    }

    @Test("Late activation is released after pending work is cancelled")
    @MainActor
    func cancelledLateActivationIsReleased() async throws {
        let probe = AudioPlaybackSessionOperationsProbe()
        let coordinator = makeCoordinator(probe: probe)
        let gate = AudioPlaybackActivationGate()
        let lease = try await coordinator.activate(.playbackDucking)
        let controller = AudioPlaybackSessionController(
            dependencies: .init(
                activate: { _ in
                    await gate.wait()
                    return lease
                },
                deactivate: { returnedLease in
                    await coordinator.deactivate(ifCurrent: returnedLease)
                },
                isCurrent: { returnedLease in
                    await coordinator.isCurrent(returnedLease)
                }
            )
        )

        let activation = Task { await controller.activate() }
        await waitForCondition { await gate.waiterCount == 1 }
        controller.cancelPendingActivation()
        await gate.releaseAll()

        #expect(await activation.value == false)
        await waitForCondition { probe.snapshot.deactivationCount == 1 }
        #expect(probe.snapshot.configurations == [.playbackDucking])
    }

    @Test("Cancelling queued activation performs no session mutation")
    @MainActor
    func pendingActivationCancellationReleasesLateLease() async {
        let probe = AudioPlaybackSessionOperationsProbe()
        let coordinator = makeCoordinator(probe: probe)
        let gate = AudioPlaybackActivationGate()
        let controller = makeController(
            coordinator: coordinator,
            beforeActivate: { await gate.wait() }
        )

        let activation = Task { await controller.activate() }
        await waitForCondition { await gate.waiterCount == 1 }
        controller.cancelPendingActivation()
        await gate.releaseAll()

        #expect(await activation.value == false)
        #expect(probe.snapshot.activationCount == 0)
        #expect(probe.snapshot.deactivationCount == 0)
        #expect(!controller.hasActiveLease)
    }

    @Test("Concurrent activation shares one lease request")
    @MainActor
    func concurrentActivationIsCoalesced() async {
        let probe = AudioPlaybackSessionOperationsProbe()
        let coordinator = makeCoordinator(probe: probe)
        let gate = AudioPlaybackActivationGate()
        let controller = makeController(
            coordinator: coordinator,
            beforeActivate: { await gate.wait() }
        )

        let first = Task { await controller.activate() }
        let second = Task { await controller.activate() }
        await waitForCondition { await gate.waiterCount == 1 }
        await gate.releaseAll()

        #expect(await first.value)
        #expect(await second.value)
        #expect(probe.snapshot.activationCount == 1)
        #expect(controller.hasActiveLease)

        controller.deactivate()
        await waitForCondition { probe.snapshot.deactivationCount == 1 }
    }

    @Test("Activation failure remains retryable")
    @MainActor
    func failedActivationCanRetry() async {
        let probe = AudioPlaybackSessionOperationsProbe()
        probe.failNextActivation()
        let coordinator = makeCoordinator(probe: probe)
        let controller = makeController(coordinator: coordinator)

        #expect(await controller.activate() == false)
        #expect(!controller.hasActiveLease)
        #expect(await controller.activate())
        #expect(controller.hasActiveLease)
        #expect(
            probe.snapshot.configurations == [
                .playbackDucking,
                .playbackDucking
            ]
        )

        controller.deactivate()
        await waitForCondition { probe.snapshot.deactivationCount == 2 }
    }

    @Test("Idle teardown performs no audio-session mutation")
    @MainActor
    func idleTeardownDoesNotActivateSession() async {
        let probe = AudioPlaybackSessionOperationsProbe()
        let coordinator = makeCoordinator(probe: probe)
        let controller = makeController(coordinator: coordinator)

        controller.deactivate()
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(probe.snapshot.activationCount == 0)
        #expect(probe.snapshot.deactivationCount == 0)
        #expect(!controller.hasActiveLease)
    }

    @Test("A stale mounted lease is reacquired before reuse")
    @MainActor
    func staleLeaseIsReacquired() async throws {
        let probe = AudioPlaybackSessionOperationsProbe()
        let coordinator = makeCoordinator(probe: probe)
        let controller = makeController(coordinator: coordinator)

        #expect(await controller.activate())
        _ = try await coordinator.activate(
            .recordMeasurement(preferredSampleRate: nil)
        )

        #expect(await controller.activate())
        #expect(
            probe.snapshot.configurations == [
                .playbackDucking,
                .recordMeasurement(preferredSampleRate: nil),
                .playbackDucking
            ]
        )

        controller.deactivate()
        await waitForCondition { probe.snapshot.deactivationCount == 1 }
    }

    @Test("Teardown during lease validation cannot reactivate playback")
    @MainActor
    func teardownDuringLeaseValidationDoesNotReactivate() async {
        let probe = AudioPlaybackSessionOperationsProbe()
        let coordinator = makeCoordinator(probe: probe)
        let validationGate = AudioPlaybackActivationGate()
        let controller = makeController(
            coordinator: coordinator,
            beforeIsCurrent: { await validationGate.wait() }
        )

        #expect(await controller.activate())
        let validation = Task { await controller.activate() }
        await waitForCondition { await validationGate.waiterCount == 1 }

        controller.deactivate()
        await validationGate.releaseAll()

        #expect(await validation.value == false)
        await waitForCondition { probe.snapshot.deactivationCount == 1 }
        #expect(probe.snapshot.activationCount == 1)
        #expect(!controller.hasActiveLease)
    }

    private func makeCoordinator(
        probe: AudioPlaybackSessionOperationsProbe
    ) -> AudioSessionCoordinator {
        AudioSessionCoordinator(
            operations: .init(
                configureAndActivate: { configuration in
                    try probe.configureAndActivate(configuration)
                },
                deactivate: { probe.deactivate() }
            )
        )
    }

    @MainActor
    private func makeController(
        coordinator: AudioSessionCoordinator,
        beforeActivate: @escaping @Sendable () async -> Void = {},
        beforeIsCurrent: @escaping @Sendable () async -> Void = {},
        onRelease: @escaping @Sendable () -> Void = {}
    ) -> AudioPlaybackSessionController {
        AudioPlaybackSessionController(
            dependencies: .init(
                activate: { configuration in
                    await beforeActivate()
                    return try await coordinator.activate(configuration)
                },
                deactivate: { lease in
                    onRelease()
                    await coordinator.deactivate(ifCurrent: lease)
                },
                isCurrent: { lease in
                    await beforeIsCurrent()
                    return await coordinator.isCurrent(lease)
                }
            )
        )
    }

    @MainActor
    private func waitForCondition(
        _ condition: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await condition() { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for audio playback session state")
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<10 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
