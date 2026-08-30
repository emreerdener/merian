import AVFoundation

extension AudioCaptureManager {
    struct Dependencies: Sendable {
        let activateRecordingSession:
            @Sendable (_ preferredSampleRate: Double?) async throws
                -> AudioSessionCoordinator.Lease
        let deactivateAudioSession:
            @Sendable (_ lease: AudioSessionCoordinator.Lease?) async -> Void
        let startEngine: @Sendable (_ engine: AVAudioEngine) throws -> Void

        static let live = Self(
            activateRecordingSession: { preferredSampleRate in
                try await AudioSessionCoordinator.shared.activate(
                    .recordMeasurement(
                        preferredSampleRate: preferredSampleRate
                    )
                )
            },
            deactivateAudioSession: { lease in
                await AudioSessionCoordinator.shared.deactivate(
                    ifCurrent: lease
                )
            },
            startEngine: { engine in
                try engine.start()
            }
        )
    }
}
