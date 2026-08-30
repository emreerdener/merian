import Foundation

/// Immutable Record UI snapshot assembled by the Capture shell.
struct AudioRecordingPresentation: Equatable {
    let isRecording: Bool
    let isReviewing: Bool
    let isPlaying: Bool
    let recordingProgress: Double
    let playbackProgress: Double
    let spectrogramColumns: [SpectrogramColumn]
    let snrLevel: SNRLevel
    let audioHintsEnabled: Bool
    let maximumDuration: TimeInterval
    let liveColumnCapacity: Int

    var showsSpectrogram: Bool {
        isRecording || isReviewing
    }

    var countdownProgress: Double {
        isRecording ? recordingProgress : playbackProgress
    }

    var countdownAccessibilityPrefix: String {
        isRecording
            ? "Audio recording time remaining"
            : "Audio playback time remaining"
    }

    var spectrogramLayout: AudioSpectrogramDisplayLayout {
        isReviewing
            ? .fitToData
            : .liveHorizon(capacity: liveColumnCapacity)
    }

    func showsPlayhead(isScrubbing: Bool) -> Bool {
        isReviewing
            && (isPlaying || isScrubbing || playbackProgress > 0)
    }
}

enum AudioRecordingIdleArtwork {
    static let names = [
        "blue-bird",
        "frog",
        "owl",
        "cicada",
        "cricket",
        "falcon",
        "rattlesnake",
        "whale"
    ]

    static func nextIndex(after index: Int) -> Int {
        guard !names.isEmpty else { return 0 }
        return (index + 1) % names.count
    }
}

enum AudioRecordingLayoutPolicy {
    static func spectrogramHeight(
        viewportHeight: Double,
        composingCenter: Double,
        bottomClearance: Double
    ) -> Double {
        let centerY = viewportHeight * composingCenter
        let halfHeight = min(
            centerY - 100,
            viewportHeight - bottomClearance - centerY - 88
        )
        return max(180, halfHeight * 2)
    }
}

enum AudioSNRPresentation {
    static func label(for level: SNRLevel) -> String {
        switch level {
        case .clear: "Clear"
        case .caution: "Some noise"
        case .warning: "Shield mic"
        case .clipping: "Move mic away"
        }
    }
}
