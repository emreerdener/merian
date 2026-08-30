import CoreGraphics
import Observation

@MainActor
@Observable
final class AudioRecordingViewModel {
    struct Dependencies {
        let seekPlayback: @MainActor (_ progress: Double) -> Void
        let idleArtworkSelectionFeedback: @MainActor () -> Void
        let scrubBeginFeedback: @MainActor () -> Void
        let scrubCommitFeedback: @MainActor () -> Void
    }

    private(set) var idleArtworkIndex = 0
    private(set) var isScrubbing = false

    @ObservationIgnored private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var idleArtworkName: String {
        guard AudioRecordingIdleArtwork.names.indices.contains(
            idleArtworkIndex
        ) else {
            return AudioRecordingIdleArtwork.names[0]
        }
        return AudioRecordingIdleArtwork.names[idleArtworkIndex]
    }

    func advanceIdleArtworkAfterTimer() {
        advanceIdleArtwork()
    }

    func advanceIdleArtworkAfterSelection() {
        dependencies.idleArtworkSelectionFeedback()
        advanceIdleArtwork()
    }

    func updateScrubbing(locationX: CGFloat, width: CGFloat) {
        if !isScrubbing {
            dependencies.scrubBeginFeedback()
        }
        isScrubbing = true
        dependencies.seekPlayback(
            AudioSpectrogramSeekingPolicy.normalizedProgress(
                locationX: locationX,
                width: width
            )
        )
    }

    func finishScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        dependencies.scrubCommitFeedback()
    }

    private func advanceIdleArtwork() {
        idleArtworkIndex = AudioRecordingIdleArtwork.nextIndex(
            after: idleArtworkIndex
        )
    }
}
