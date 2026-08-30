import AVFoundation
import Foundation

/// Serializes process-wide recording and playback audio-session ownership.
actor AudioSessionCoordinator {
    enum Configuration: Equatable, Sendable {
        case recordMeasurement(preferredSampleRate: Double?)
        case playback
    }

    struct Lease: Sendable {
        fileprivate let token: UInt64
    }

    struct Operations: Sendable {
        let configureAndActivate:
            @Sendable (_ configuration: Configuration) throws -> Void
        let deactivate: @Sendable () -> Void

        static let live = Self(
            configureAndActivate: { configuration in
                let session = AVAudioSession.sharedInstance()

                switch configuration {
                case .recordMeasurement(let preferredSampleRate):
                    try session.setCategory(
                        .record,
                        mode: .measurement,
                        options: .duckOthers
                    )
                    try session.setAllowHapticsAndSystemSoundsDuringRecording(
                        true
                    )
                    if let preferredSampleRate {
                        try? session.setPreferredSampleRate(
                            preferredSampleRate
                        )
                    }
                case .playback:
                    try session.setCategory(.playback, mode: .default)
                }
                try session.setActive(true)
            },
            deactivate: {
                try? AVAudioSession.sharedInstance().setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
            }
        )
    }

    static let shared = AudioSessionCoordinator()

    private let operations: Operations
    private var nextToken: UInt64 = 0
    private var activeToken: UInt64?
    private var activeConfiguration: Configuration?

    init(operations: Operations = .live) {
        self.operations = operations
    }

    func activate(_ configuration: Configuration) throws -> Lease {
        let previousConfiguration = activeConfiguration
        do {
            try operations.configureAndActivate(configuration)
        } catch let activationError {
            recoverAfterFailedActivation(
                previousConfiguration: previousConfiguration
            )
            throw activationError
        }

        // Publish replacement ownership only after the complete configuration
        // succeeds. Failure recovery either restores the prior owner or clears
        // ownership after fail-closed deactivation.
        nextToken &+= 1
        activeToken = nextToken
        activeConfiguration = configuration
        let lease = Lease(token: nextToken)
        return lease
    }

    func deactivate(ifCurrent lease: Lease?) {
        guard let lease, lease.token == activeToken else { return }
        operations.deactivate()
        activeToken = nil
        activeConfiguration = nil
    }

    private func recoverAfterFailedActivation(
        previousConfiguration: Configuration?
    ) {
        guard let previousConfiguration else {
            // A first activation may have changed the category before failing.
            // Leave no partially configured session behind.
            operations.deactivate()
            activeToken = nil
            activeConfiguration = nil
            return
        }

        do {
            try operations.configureAndActivate(previousConfiguration)
        } catch {
            // The prior token is meaningful only if its configuration can be
            // restored. Fail closed when the rollback itself is unavailable.
            operations.deactivate()
            activeToken = nil
            activeConfiguration = nil
        }
    }
}

enum MediaPlaybackAudioSession {
    /// AVPlayer does not reliably reactivate output after capture leaves the shared
    /// session inactive or configured for recording. Call before audible media starts.
    @discardableResult
    static func activate(source: String) async -> Bool {
        do {
            _ = try await AudioSessionCoordinator.shared.activate(.playback)
            return true
        } catch {
            MerianLog.general.error(
                "Media playback audio-session activation failed: source=\(source, privacy: .public) error=\(error, privacy: .private)"
            )
            return false
        }
    }
}
