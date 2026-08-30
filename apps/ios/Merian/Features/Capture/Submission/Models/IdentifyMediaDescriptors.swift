import Foundation

enum IdentifyVisualMediaKind: String, Codable, Sendable {
    case image
    case videoFrame = "video_frame"
}

/// Local-only provenance persisted with queued visual media.
///
/// These values are omitted from `IdentifyVisualMediaItem.jsonObject`, which is
/// the payload sent to `/identify-multimodal`.
enum IdentifyVisualCaptureSource: String, Codable, Sendable, Equatable {
    case camera
    case gallery
}

struct IdentifyVisualMediaItem: Codable, Sendable, Equatable {
    let kind: IdentifyVisualMediaKind
    let sourceIndex: Int?
    let clipIndex: Int?
    let frameIndex: Int?
    let focusRegion: NormalizedImageFocusRegion?
    let captureSource: IdentifyVisualCaptureSource?
    let hasEmbeddedCaptureDate: Bool?

    static func image(
        sourceIndex: Int,
        focusRegion: NormalizedImageFocusRegion? = nil,
        captureSource: IdentifyVisualCaptureSource? = nil,
        hasEmbeddedCaptureDate: Bool? = nil
    ) -> IdentifyVisualMediaItem {
        IdentifyVisualMediaItem(
            kind: .image,
            sourceIndex: sourceIndex,
            clipIndex: nil,
            frameIndex: nil,
            focusRegion: focusRegion,
            captureSource: captureSource,
            hasEmbeddedCaptureDate: hasEmbeddedCaptureDate
        )
    }

    static func videoFrame(clipIndex: Int, frameIndex: Int) -> IdentifyVisualMediaItem {
        IdentifyVisualMediaItem(
            kind: .videoFrame,
            sourceIndex: nil,
            clipIndex: clipIndex,
            frameIndex: frameIndex,
            focusRegion: nil,
            captureSource: nil,
            hasEmbeddedCaptureDate: nil
        )
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = ["kind": kind.rawValue]
        if let sourceIndex {
            object["sourceIndex"] = sourceIndex
        }
        if let clipIndex {
            object["clipIndex"] = clipIndex
        }
        if let frameIndex {
            object["frameIndex"] = frameIndex
        }
        if kind == .image, let focusRegion {
            object["focusRegion"] = focusRegion.jsonObject
        }
        return object
    }
}

extension Array where Element == IdentifyVisualMediaItem {
    var focusRegionsBySourceIndex: [Int: NormalizedImageFocusRegion] {
        reduce(into: [:]) { result, item in
            guard item.kind == .image,
                  let sourceIndex = item.sourceIndex,
                  let focusRegion = item.focusRegion else { return }
            result[sourceIndex] = focusRegion
        }
    }
}

enum IdentifyAudioMediaKind: String, Codable, Sendable {
    case audio
    case videoAudio = "video_audio"
}

struct IdentifyAudioMediaItem: Codable, Sendable, Equatable {
    let kind: IdentifyAudioMediaKind
    let sourceIndex: Int?
    let clipIndex: Int?

    static func audio(sourceIndex: Int) -> IdentifyAudioMediaItem {
        IdentifyAudioMediaItem(
            kind: .audio,
            sourceIndex: sourceIndex,
            clipIndex: nil
        )
    }

    static func videoAudio(clipIndex: Int) -> IdentifyAudioMediaItem {
        IdentifyAudioMediaItem(
            kind: .videoAudio,
            sourceIndex: nil,
            clipIndex: clipIndex
        )
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = ["kind": kind.rawValue]
        if let sourceIndex {
            object["sourceIndex"] = sourceIndex
        }
        if let clipIndex {
            object["clipIndex"] = clipIndex
        }
        return object
    }
}

enum IdentifyOwnerMediaKind: String, Codable, Sendable {
    case image
    case audio
    case video
    case description
}

/// An owner-visible item in the canonical submission timeline.
///
/// The indices identify request inputs rather than storage locations. Clients
/// never place object keys or URLs in this structure.
struct IdentifyOwnerMediaTimelineItem: Codable, Sendable, Equatable {
    let kind: IdentifyOwnerMediaKind
    let sourceIndex: Int?
    let audioInputIndex: Int?
    let clipIndex: Int?
    let contextIndex: Int?

    static func image(sourceIndex: Int) -> Self {
        Self(
            kind: .image,
            sourceIndex: sourceIndex,
            audioInputIndex: nil,
            clipIndex: nil,
            contextIndex: nil
        )
    }

    static func audio(audioInputIndex: Int, sourceIndex: Int) -> Self {
        Self(
            kind: .audio,
            sourceIndex: sourceIndex,
            audioInputIndex: audioInputIndex,
            clipIndex: nil,
            contextIndex: nil
        )
    }

    static func video(clipIndex: Int) -> Self {
        Self(
            kind: .video,
            sourceIndex: nil,
            audioInputIndex: nil,
            clipIndex: clipIndex,
            contextIndex: nil
        )
    }

    static func description(contextIndex: Int) -> Self {
        Self(
            kind: .description,
            sourceIndex: nil,
            audioInputIndex: nil,
            clipIndex: nil,
            contextIndex: contextIndex
        )
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = ["kind": kind.rawValue]
        if let sourceIndex {
            object["sourceIndex"] = sourceIndex
        }
        if let audioInputIndex {
            object["audioInputIndex"] = audioInputIndex
        }
        if let clipIndex {
            object["clipIndex"] = clipIndex
        }
        if let contextIndex {
            object["contextIndex"] = contextIndex
        }
        return object
    }
}
