import AVFoundation

extension AudioCaptureManager {
    struct Dependencies: Sendable {
        let recording: AudioRecordingEngineController.Dependencies
        let playback: AudioReviewPlaybackController.Dependencies
        let reviewBoost: AudioReviewBoostController.Dependencies
        let hasMicrophonePermission: @MainActor @Sendable () -> Bool

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
            playback: AudioReviewPlaybackController.Dependencies = .live,
            reviewBoost: AudioReviewBoostController.Dependencies = .live
        ) {
            self.recording = AudioRecordingEngineController.Dependencies(
                activateSession: activateRecordingSession,
                deactivateSession: deactivateAudioSession,
                startEngine: startEngine
            )
            self.playback = playback
            self.reviewBoost = reviewBoost
            self.hasMicrophonePermission = {
                AVAudioApplication.shared.recordPermission == .granted
            }
        }

        init(
            recording: AudioRecordingEngineController.Dependencies,
            playback: AudioReviewPlaybackController.Dependencies = .live,
            reviewBoost: AudioReviewBoostController.Dependencies = .live,
            hasMicrophonePermission: @escaping @MainActor @Sendable () -> Bool = {
                AVAudioApplication.shared.recordPermission == .granted
            }
        ) {
            self.recording = recording
            self.playback = playback
            self.reviewBoost = reviewBoost
            self.hasMicrophonePermission = hasMicrophonePermission
        }

        static let live = Self(
            recording: .live,
            playback: .live
        )
    }
}
