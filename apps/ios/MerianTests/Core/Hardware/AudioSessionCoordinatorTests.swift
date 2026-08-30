import Foundation
import Testing

@testable import Merian

private enum AudioSessionCoordinatorTestError: Error {
    case activationFailed
}

private final class AudioSessionOperationsProbe: @unchecked Sendable {
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

    func failNextActivations(_ count: Int = 1) {
        lock.withLock {
            remainingActivationFailures = count
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
            throw AudioSessionCoordinatorTestError.activationFailed
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

@Suite("Audio session coordinator")
struct AudioSessionCoordinatorTests {
    @Test("Failed replacement restores the prior configuration and lease")
    func failedReplacementRestoresPriorConfiguration() async throws {
        let probe = AudioSessionOperationsProbe()
        let coordinator = AudioSessionCoordinator(
            operations: .init(
                configureAndActivate: { configuration in
                    try probe.configureAndActivate(configuration)
                },
                deactivate: {
                    probe.deactivate()
                }
            )
        )
        let priorLease = try await coordinator.activate(.playback)
        probe.failNextActivations()

        await #expect(throws: AudioSessionCoordinatorTestError.self) {
            _ = try await coordinator.activate(
                .recordMeasurement(preferredSampleRate: nil)
            )
        }
        await coordinator.deactivate(ifCurrent: priorLease)

        let snapshot = probe.snapshot
        #expect(snapshot.activationCount == 3)
        #expect(snapshot.deactivationCount == 1)
        #expect(
            snapshot.configurations == [
                .playback,
                .recordMeasurement(preferredSampleRate: nil),
                .playback
            ]
        )
    }

    @Test("A successful replacement makes the prior lease stale")
    func successfulReplacementMakesPriorLeaseStale() async throws {
        let probe = AudioSessionOperationsProbe()
        let coordinator = AudioSessionCoordinator(
            operations: .init(
                configureAndActivate: { configuration in
                    try probe.configureAndActivate(configuration)
                },
                deactivate: {
                    probe.deactivate()
                }
            )
        )
        let priorLease = try await coordinator.activate(.playback)
        let replacementLease = try await coordinator.activate(
            .recordMeasurement(preferredSampleRate: 48_000)
        )

        await coordinator.deactivate(ifCurrent: priorLease)
        #expect(probe.snapshot.deactivationCount == 0)

        await coordinator.deactivate(ifCurrent: replacementLease)
        #expect(probe.snapshot.deactivationCount == 1)

        await coordinator.deactivate(ifCurrent: replacementLease)
        #expect(probe.snapshot.deactivationCount == 1)
    }

    @Test("Failed rollback deactivates and invalidates the prior lease")
    func failedRollbackInvalidatesPriorLease() async throws {
        let probe = AudioSessionOperationsProbe()
        let coordinator = AudioSessionCoordinator(
            operations: .init(
                configureAndActivate: { configuration in
                    try probe.configureAndActivate(configuration)
                },
                deactivate: {
                    probe.deactivate()
                }
            )
        )
        let priorLease = try await coordinator.activate(.playback)
        probe.failNextActivations(2)

        await #expect(throws: AudioSessionCoordinatorTestError.self) {
            _ = try await coordinator.activate(
                .recordMeasurement(preferredSampleRate: nil)
            )
        }
        await coordinator.deactivate(ifCurrent: priorLease)

        #expect(probe.snapshot.activationCount == 3)
        #expect(probe.snapshot.deactivationCount == 1)

        let recoveredLease = try await coordinator.activate(.playback)
        await coordinator.deactivate(ifCurrent: recoveredLease)
        #expect(probe.snapshot.deactivationCount == 2)
    }

    @Test("Failed first activation cleans up partial session state")
    func failedFirstActivationCleansUpPartialState() async {
        let probe = AudioSessionOperationsProbe()
        probe.failNextActivations()
        let coordinator = AudioSessionCoordinator(
            operations: .init(
                configureAndActivate: { configuration in
                    try probe.configureAndActivate(configuration)
                },
                deactivate: {
                    probe.deactivate()
                }
            )
        )

        await #expect(throws: AudioSessionCoordinatorTestError.self) {
            _ = try await coordinator.activate(.playback)
        }

        #expect(probe.snapshot.activationCount == 1)
        #expect(probe.snapshot.deactivationCount == 1)
    }
}
