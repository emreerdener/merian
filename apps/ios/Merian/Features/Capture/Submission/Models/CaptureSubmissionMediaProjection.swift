import Foundation

/// The single ordered projection used by live submission and durable replay.
///
/// Audio paths and descriptors are emitted together so interleaved video audio
/// can never be paired with a different standalone recording during upload.
struct CaptureSubmissionMediaProjection: Sendable, Equatable {
    let audioFilePaths: [String]
    let audioMediaItems: [IdentifyAudioMediaItem]
    let videoFilePaths: [String]
    let observationContexts: [ObservationContext]
    let ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem]
}

enum CaptureSubmissionProjectionItem: Sendable, Equatable {
    case image
    case audio(String, sourceIndex: Int?)
    case video(String, audioFilePath: String?)
    case description(ObservationContext)
}

extension Array where Element == CaptureSubmissionProjectionItem {
    var submissionMediaProjection: CaptureSubmissionMediaProjection {
        var audioFilePaths: [String] = []
        var audioMediaItems: [IdentifyAudioMediaItem] = []
        var videoFilePaths: [String] = []
        var observationContexts: [ObservationContext] = []
        var ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem] = []
        var imageSourceIndex = 0
        var audioInputIndex = 0
        var standaloneAudioSourceIndex = 0
        var videoClipIndex = 0
        var contextIndex = 0

        for item in self {
            switch item {
            case .image:
                ownerMediaTimeline.append(.image(sourceIndex: imageSourceIndex))
                imageSourceIndex += 1

            case .audio(let path, let persistedSourceIndex):
                guard !path.isEmpty else { continue }
                let sourceIndex = persistedSourceIndex ?? standaloneAudioSourceIndex
                audioFilePaths.append(path)
                audioMediaItems.append(.audio(sourceIndex: sourceIndex))
                ownerMediaTimeline.append(.audio(
                    audioInputIndex: audioInputIndex,
                    sourceIndex: sourceIndex
                ))
                audioInputIndex += 1
                standaloneAudioSourceIndex += 1

            case .video(let path, let audioFilePath):
                guard !path.isEmpty else { continue }
                videoFilePaths.append(path)
                ownerMediaTimeline.append(.video(clipIndex: videoClipIndex))
                if let audioFilePath, !audioFilePath.isEmpty {
                    audioFilePaths.append(audioFilePath)
                    audioMediaItems.append(.videoAudio(clipIndex: videoClipIndex))
                    audioInputIndex += 1
                }
                videoClipIndex += 1

            case .description(let context):
                guard !context.isEmpty else { continue }
                observationContexts.append(context)
                ownerMediaTimeline.append(.description(contextIndex: contextIndex))
                contextIndex += 1
            }
        }

        return CaptureSubmissionMediaProjection(
            audioFilePaths: audioFilePaths,
            audioMediaItems: audioMediaItems,
            videoFilePaths: videoFilePaths,
            observationContexts: observationContexts,
            ownerMediaTimeline: ownerMediaTimeline
        )
    }
}

extension Array where Element == CaptureSubmissionMediaItem {
    var submissionMediaProjection: CaptureSubmissionMediaProjection {
        map { item in
            switch item {
            case .image:
                return .image
            case .audio(let path):
                return .audio(path, sourceIndex: nil)
            case .video(let path, _, let audioFilePath):
                return .video(path, audioFilePath: audioFilePath)
            case .description(let context):
                return .description(context)
            }
        }.submissionMediaProjection
    }

    var audioFilePaths: [String] {
        submissionMediaProjection.audioFilePaths
    }

    var videoFilePaths: [String] {
        submissionMediaProjection.videoFilePaths
    }

    var observationContexts: [ObservationContext] {
        submissionMediaProjection.observationContexts
    }
}
