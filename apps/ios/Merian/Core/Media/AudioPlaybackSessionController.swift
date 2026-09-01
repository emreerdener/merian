import AVFoundation

@MainActor
final class AudioPlaybackSessionController {
    private var previousCategory: AVAudioSession.Category?
    private var previousCategoryOptions: AVAudioSession.CategoryOptions?

    func captureAndSwitchSession() {
        let session = AVAudioSession.sharedInstance()
        previousCategory = session.category
        previousCategoryOptions = session.categoryOptions

        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: .duckOthers
            )
        } catch {
            MerianLog.general.debug(
                "AudioPlaybackCarouselPage: setCategory failed: \(error, privacy: .private)"
            )
        }
    }

    func restoreSession() {
        guard let previousCategory else { return }
        let options = previousCategoryOptions ?? []
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(previousCategory, options: options)
        } catch {
            MerianLog.general.debug(
                "AudioPlaybackCarouselPage: session restore failed: \(error, privacy: .private)"
            )
        }
    }
}
