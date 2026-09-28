import AVFoundation

/// Reuses the original picture track and replaces only the preview soundtrack.
@MainActor
enum StagedVideoPreviewComposition {
    static func makeItem(videoURL: URL, boostedAudioURL: URL) async throws -> AVPlayerItem {
        let original = AVURLAsset(url: videoURL)
        let boosted = AVURLAsset(url: boostedAudioURL)
        guard let video = try await original.loadTracks(withMediaType: .video).first,
              let originalAudio = try await original.loadTracks(withMediaType: .audio).first,
              let audio = try await boosted.loadTracks(withMediaType: .audio).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let duration = try await original.load(.duration)
        let videoRange = try await video.load(.timeRange)
        let originalAudioRange = try await originalAudio.load(.timeRange)
        let audioRange = try await audio.load(.timeRange)
        let transform = try await video.load(.preferredTransform)
        try Task.checkCancellation()
        guard duration.isNumeric, duration.seconds > 0,
              originalAudioRange.start.isNumeric,
              originalAudioRange.start >= .zero,
              originalAudioRange.start < duration else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let composition = AVMutableComposition()
        guard let picture = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ), let soundtrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw CocoaError(.fileReadCorruptFile) }
        try picture.insertTimeRange(videoRange, of: video, at: videoRange.start)
        picture.preferredTransform = transform
        let audioDuration = CMTimeMinimum(
            audioRange.duration,
            CMTimeMinimum(originalAudioRange.duration, duration - originalAudioRange.start)
        )
        guard audioDuration.isNumeric, audioDuration.seconds > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try soundtrack.insertTimeRange(
            CMTimeRange(start: audioRange.start, duration: audioDuration),
            of: audio, at: originalAudioRange.start
        )
        if composition.duration < duration {
            composition.insertEmptyTimeRange(CMTimeRange(
                start: composition.duration, duration: duration - composition.duration
            ))
        }
        try Task.checkCancellation()
        return AVPlayerItem(asset: composition)
    }
}
