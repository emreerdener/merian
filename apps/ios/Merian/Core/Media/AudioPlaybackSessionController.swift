import Foundation

/// Owns one token-aware playback lease for a mounted media surface.
///
/// Activation is coalesced, and teardown invalidates pending work before
/// releasing the exact acquired lease. A late release therefore cannot
/// deactivate a recording or playback session that replaced this owner.
@MainActor
final class AudioPlaybackSessionController {
    struct Dependencies: Sendable {
        let activate:
            @Sendable (AudioSessionCoordinator.Configuration) async throws
                -> AudioSessionCoordinator.Lease
        let deactivate:
            @Sendable (AudioSessionCoordinator.Lease) async -> Void
        let isCurrent:
            @Sendable (AudioSessionCoordinator.Lease) async -> Bool

        static let live = Self(
            activate: { configuration in
                try await AudioSessionCoordinator.shared.activate(
                    configuration
                )
            },
            deactivate: { lease in
                await AudioSessionCoordinator.shared.deactivate(
                    ifCurrent: lease
                )
            },
            isCurrent: { lease in
                await AudioSessionCoordinator.shared.isCurrent(lease)
            }
        )
    }

    private struct ActiveActivation {
        let id: UUID
        let task: Task<AudioSessionCoordinator.Lease?, Never>
    }

    private struct HeldLease {
        let activationID: UUID
        let lease: AudioSessionCoordinator.Lease
    }

    private let configuration: AudioSessionCoordinator.Configuration
    private let dependencies: Dependencies
    private var lifecycleGeneration: UInt64 = 0
    private var activeActivation: ActiveActivation?
    private var retiringActivation: ActiveActivation?
    private var heldLease: HeldLease?

    init(
        configuration: AudioSessionCoordinator.Configuration =
            .playbackDucking,
        dependencies: Dependencies = .live
    ) {
        self.configuration = configuration
        self.dependencies = dependencies
    }

    var hasActiveLease: Bool {
        heldLease != nil
    }

    func activate() async -> Bool {
        guard !Task.isCancelled else { return false }
        let generation = lifecycleGeneration
        await drainRetiringActivation()
        guard generation == lifecycleGeneration,
              !Task.isCancelled else { return false }

        while let existingLease = heldLease {
            let isCurrent = await dependencies.isCurrent(existingLease.lease)
            guard generation == lifecycleGeneration,
                  !Task.isCancelled else { return false }
            guard heldLease?.activationID == existingLease.activationID else {
                continue
            }
            if isCurrent { return true }
            heldLease = nil
        }

        let activation: ActiveActivation
        if let activeActivation {
            activation = activeActivation
        } else {
            let id = UUID()
            let configuration = configuration
            let activate = dependencies.activate
            let task = Task<AudioSessionCoordinator.Lease?, Never> {
                do {
                    return try await activate(configuration)
                } catch {
                    return nil
                }
            }
            activation = ActiveActivation(id: id, task: task)
            activeActivation = activation
        }

        let acquiredLease = await activation.task.value
        if retiringActivation?.id == activation.id {
            finishRetiringActivation(
                activation,
                acquiredLease: acquiredLease
            )
            return false
        }
        guard generation == lifecycleGeneration else { return false }
        if heldLease?.activationID == activation.id {
            return true
        }
        guard activeActivation?.id == activation.id else {
            if let acquiredLease {
                release(acquiredLease)
            }
            return false
        }

        activeActivation = nil
        guard let acquiredLease else { return false }
        heldLease = HeldLease(
            activationID: activation.id,
            lease: acquiredLease
        )
        return true
    }

    func deactivate() {
        cancelPendingActivation()
        guard let heldLease else { return }
        self.heldLease = nil
        release(heldLease.lease)
    }

    func cancelPendingActivation() {
        lifecycleGeneration &+= 1
        if let activeActivation {
            activeActivation.task.cancel()
            retiringActivation = activeActivation
            self.activeActivation = nil
        }
    }

    private func drainRetiringActivation() async {
        while let retiringActivation {
            let acquiredLease = await retiringActivation.task.value
            finishRetiringActivation(
                retiringActivation,
                acquiredLease: acquiredLease
            )
        }
    }

    private func finishRetiringActivation(
        _ activation: ActiveActivation,
        acquiredLease: AudioSessionCoordinator.Lease?
    ) {
        guard retiringActivation?.id == activation.id else { return }
        retiringActivation = nil
        if let acquiredLease {
            release(acquiredLease)
        }
    }

    private func release(_ lease: AudioSessionCoordinator.Lease) {
        let deactivate = dependencies.deactivate
        Task {
            await deactivate(lease)
        }
    }
}
