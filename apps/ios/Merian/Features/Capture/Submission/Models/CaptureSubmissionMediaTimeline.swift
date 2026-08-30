import Foundation

/// Ordered submission-time representation of staged capture content.
/// Images reference their index in the normalized submission image collection.
enum CaptureSubmissionMediaItem: Sendable, Equatable {
    case image(index: Int)
    case audio(String)
    case video(String, posterImageIndex: Int? = nil, audioFilePath: String? = nil)
    case description(ObservationContext)

    /// Legacy/fallback ordering used when no captured-media manifest exists.
    static func defaultTimeline(
        imageCount: Int,
        observationContexts: [ObservationContext],
        audioFilePaths: [String],
        videoFilePaths: [String] = []
    ) -> [CaptureSubmissionMediaItem] {
        var items: [CaptureSubmissionMediaItem] = (0..<imageCount).map { .image(index: $0) }
        items.append(contentsOf: observationContexts.map(Self.description))
        items.append(contentsOf: audioFilePaths.map(Self.audio))
        items.append(contentsOf: videoFilePaths.map { .video($0) })
        return items
    }
}

extension StagedCapture {
    var submissionMediaTimeline: [CaptureSubmissionMediaItem] {
        orderedNodes.map { node in
            switch node {
            case .image(let index, _):
                return .image(index: index)
            case .audio(_, let stagedAudio):
                return .audio(stagedAudio.filePath)
            case .video(_, let stagedVideo):
                return .video(
                    stagedVideo.filePath,
                    audioFilePath: stagedVideo.audioFilePath
                )
            case .description(_, let stagedObservationContext):
                return .description(stagedObservationContext.context)
            }
        }
    }
}

extension Array where Element == CaptureSubmissionMediaItem {
    var discardableLocalMediaFilePaths: [String] {
        flatMap { item -> [String] in
            switch item {
            case .audio(let path):
                return [path]
            case .video(let path, _, let audioFilePath):
                return [path, audioFilePath].compactMap { $0 }
            case .image, .description:
                return []
            }
        }
    }
}
