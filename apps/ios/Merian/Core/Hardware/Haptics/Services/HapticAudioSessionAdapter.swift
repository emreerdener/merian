import AVFoundation

@MainActor
struct HapticAudioSessionAdapter {
    let prepareForFeedback: @MainActor (HapticEvent) -> Void
    let snapshot: @MainActor () -> HapticAudioSessionSnapshot

    static let live = Self(
        prepareForFeedback: { event in
            let session = AVAudioSession.sharedInstance()
            guard session.category == .record ||
                  session.category == .playAndRecord ||
                  session.category == .multiRoute else {
                return
            }

            do {
                try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            } catch {
                MerianLog.hardware.warning(
                    """
                    Unable to allow haptics during recording for \
                    \(event.rawValue, privacy: .public): \
                    \(error, privacy: .private)
                    """
                )
            }
        },
        snapshot: {
            let session = AVAudioSession.sharedInstance()
            return HapticAudioSessionSnapshot(
                category: session.category.rawValue,
                mode: session.mode.rawValue
            )
        }
    )
}
