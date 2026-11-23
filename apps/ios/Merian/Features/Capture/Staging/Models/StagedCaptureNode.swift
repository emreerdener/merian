import Foundation

/// A modality-preserving reference into a staged capture's collections.
enum StagedCaptureNode: Identifiable {
    case image(index: Int, stagedImage: StagedImage)
    case audio(index: Int, stagedAudio: StagedAudio)
    case video(index: Int, stagedVideo: StagedVideo)
    case description(index: Int, stagedObservationContext: StagedObservationContext)

    var id: String {
        switch self {
        case .image(_, let image):
            return "img_\(image.original.id)"
        case .audio(_, let audio):
            return "audio_\(audio.id)"
        case .video(_, let video):
            return "video_\(video.id)"
        case .description(_, let context):
            return "desc_\(context.id)"
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

    var itemID: UUID {
        switch self {
        case .image(_, let value): value.original.id
        case .audio(_, let value): value.id
        case .video(_, let value): value.id
        case .description(_, let value): value.id
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

        // Equal historical timestamps retain the established collection order.
        // Identity is independent of this tie policy and of mutable indexes.
        return nodes.enumerated().sorted {
            if let retainedItemOrder {
                let lhs = retainedItemOrder.firstIndex(of: $0.element.itemID) ?? retainedItemOrder.count
                let rhs = retainedItemOrder.firstIndex(of: $1.element.itemID) ?? retainedItemOrder.count
                if lhs != rhs { return lhs < rhs }
            }
            if $0.element.addedAt == $1.element.addedAt { return $0.offset < $1.offset }
            return $0.element.addedAt < $1.element.addedAt
        }.map(\.element)
    }
}
