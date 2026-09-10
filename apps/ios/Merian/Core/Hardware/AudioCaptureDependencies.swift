import AVFoundation

extension AudioCaptureManager {
    struct Dependencies: Sendable {
        let recording: AudioRecordingEngineController.Dependencies
        let playback: AudioReviewPlaybackController.Dependencies

        init(
            activateRecordingSession: @escaping @Sendable (
                _ preferredSampleRate: Double?
            ) async throws -> AudioSessionCoordinator.Lease,
            deactivateAudioSession: @escaping @Sendable (
                _ lease: AudioSessionCoordinator.Lease?
            ) async -> Void,
            startEngine: @escaping @Sendable (
                _ engine: AVAudioEngine
            ) throws -> Void,
            playback: AudioReviewPlaybackController.Dependencies = .live
        ) {
            self.recording = AudioRecordingEngineController.Dependencies(
                activateSession: activateRecordingSession,
                deactivateSession: deactivateAudioSession,
                startEngine: startEngine
            )
            self.playback = playback
        }

        init(
            recording: AudioRecordingEngineController.Dependencies,
            playback: AudioReviewPlaybackController.Dependencies = .live
        ) {
            self.recording = recording
            self.playback = playback
        }

        static let live = Self(
            recording: .live,
            playback: .live
        )
    }
}
