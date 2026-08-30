import Foundation

/// A modality-preserving reference into a staged capture's collections.
enum StagedCaptureNode: Identifiable {
    case image(index: Int, stagedImage: StagedImage)
    case audio(index: Int, stagedAudio: StagedAudio)
    case video(index: Int, stagedVideo: StagedVideo)
    case description(index: Int, stagedObservationContext: StagedObservationContext)

    var id: String {
        switch self {
        case .image(let index, _):
            return "img_\(index)"
        case .audio(let index, _):
            return "audio_\(index)"
        case .video(let index, _):
            return "video_\(index)"
        case .description(let index, _):
            return "desc_\(index)"
        }
    }

    var addedAt: Date {
        switch self {
        case .image(_, let stagedImage):
            return stagedImage.addedAt
        case .audio(_, let stagedAudio):
            return stagedAudio.addedAt
        case .video(_, let stagedVideo):
            return stagedVideo.addedAt
        case .description(_, let stagedObservationContext):
            return stagedObservationContext.addedAt
        }
    }
}

extension StagedCapture {
    /// Returns one chronological sequence while retaining each collection index.
    var orderedNodes: [StagedCaptureNode] {
        var nodes: [StagedCaptureNode] = []

        nodes.append(contentsOf: images.enumerated().map { index, image in
            .image(index: index, stagedImage: image)
        })
        nodes.append(contentsOf: audios.enumerated().map { index, audio in
            .audio(index: index, stagedAudio: audio)
        })
        nodes.append(contentsOf: videos.enumerated().map { index, video in
            .video(index: index, stagedVideo: video)
        })
        nodes.append(contentsOf: observationContexts.enumerated().map { index, context in
            .description(index: index, stagedObservationContext: context)
        })

        return nodes.sorted { $0.addedAt < $1.addedAt }
    }
}
