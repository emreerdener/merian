import AVFoundation

@MainActor
enum AudioPlaybackMonitor {
    static func observe(
        _ monitoredPlayer: AVAudioPlayer,
        isCurrent: () -> Bool,
        isPlaybackActive: () -> Bool,
        onProgress: (_ progress: Double) -> Void,
        onFailure: () -> Void
    ) async {
        while !Task.isCancelled {
            guard isCurrent(), monitoredPlayer.duration > 0 else { return }
            guard monitoredPlayer.isPlaying else {
                try? await Task.sleep(
                    nanoseconds: AudioPlaybackControlPolicy
                        .unexpectedStopGraceNanoseconds
                )
                guard !Task.isCancelled,
                      isPlaybackActive(),
                      isCurrent(),
                      !monitoredPlayer.isPlaying else { return }
                onFailure()
                return
            }
            onProgress(monitoredPlayer.currentTime / monitoredPlayer.duration)
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
