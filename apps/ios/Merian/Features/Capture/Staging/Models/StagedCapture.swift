import UIKit

/// Maximum number of staged capture items that can be combined into one submission.
/// Applies across images, audio clips, and descriptions.
let stagedCaptureCapacity = 2

/// Visual captures still top out at the same total staged capacity today.
let stagedImageCapacity = stagedCaptureCapacity

/// Ordered submission-time representation of staged capture content.
/// Images are referenced by their index in the parallel staged image arrays.
enum CaptureSubmissionMediaItem: Sendable, Equatable {
    case image(index: Int)
    case audio(String)
    case video(String, posterImageIndex: Int? = nil, audioFilePath: String? = nil)
    case description(ObservationContext)

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

enum IdentifyVisualMediaKind: String, Codable, Sendable {
    case image
    case videoFrame = "video_frame"
}

/// Local-only provenance persisted with queued visual media.
///
/// These values are intentionally omitted from `jsonObject`, which is the payload sent to
/// `/identify-multimodal`. They exist so an offline replay can distinguish a queue bookkeeping
/// timestamp from an embedded gallery capture date without adding a SwiftData column.
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
/// The indices identify inputs in the request rather than storage locations. The server
/// validates every reference before resolving it to a promoted URL; clients never place
/// object keys or URLs in this structure.
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

/// The single ordered projection used by live submission and durable queue replay.
///
/// Audio paths and descriptors are deliberately emitted together so interleaved video
/// companions can never be paired with a different standalone recording during upload.
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

    var observationContexts: [ObservationContext] {
        submissionMediaProjection.observationContexts
    }
}

enum StagedCaptureNode {
    case image(index: Int, stagedImage: StagedImage)
    case audio(index: Int, stagedAudio: StagedAudio)
    case video(index: Int, stagedVideo: StagedVideo)
    case description(index: Int, stagedObservationContext: StagedObservationContext)

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

/// A unified staging container that holds every capture modality a user can combine
/// before a single analysis submission.
///
/// Replaces the four parallel image arrays previously held in `CaptureWorkspaceViewModel`
/// (thumbnails, compressed inference data, display-quality data, and full-resolution
/// originals) with one coherent value type, now represented by `[StagedImage]`.
///
/// Supported submissions today are any one- or two-item combination of:
/// - images
/// - audio clips
/// - descriptions
///
/// Always accessed from `@MainActor` via `CaptureWorkspaceViewModel` — no `Sendable` conformance needed.
struct StagedCapture {

    // MARK: - Modalities

    /// Staged photographs. Capped at 2 — the same limit as the original image-only flow.
    var images: [StagedImage] = []

    /// File paths of staged audio recordings.
    var audios: [StagedAudio] = []

    /// Staged short video recordings. Each video carries five sampled frames for inference.
    var videos: [StagedVideo] = []

    /// Staged observation contexts from the Describe tab before submission.
    var observationContexts: [StagedObservationContext] = []
    
    /// Timestamp of the last submit action to prevent rapid duplicate enqueueing.
    var lastSubmitTime: CFAbsoluteTime?

    // MARK: - Derived State

    var isEmpty: Bool {
        images.isEmpty && audios.isEmpty && videos.isEmpty && observationContexts.isEmpty
    }

    var totalItemCount: Int {
        images.count + audios.count + videos.count + observationContexts.count
    }

    var hasVisualMedia: Bool {
        !images.isEmpty || !videos.isEmpty
    }

    /// True when more than one modality carries content — drives routing to the combined endpoint.
    var isMultiModal: Bool {
        [hasVisualMedia, !audios.isEmpty, !observationContexts.isEmpty]
            .filter { $0 }.count > 1
    }

    func availableSlots(limit: Int) -> Int {
        max(0, limit - totalItemCount)
    }

    func isAtCapacity(limit: Int) -> Bool {
        totalItemCount >= limit
    }

    var orderedNodes: [StagedCaptureNode] {
        var nodes: [StagedCaptureNode] = []

        for (index, image) in images.enumerated() {
            nodes.append(.image(index: index, stagedImage: image))
        }

        for (index, audio) in audios.enumerated() {
            nodes.append(.audio(index: index, stagedAudio: audio))
        }

        for (index, video) in videos.enumerated() {
            nodes.append(.video(index: index, stagedVideo: video))
        }

        for (index, context) in observationContexts.enumerated() {
            nodes.append(.description(index: index, stagedObservationContext: context))
        }

        return nodes.sorted { $0.addedAt < $1.addedAt }
    }

    var submissionMediaTimeline: [CaptureSubmissionMediaItem] {
        orderedNodes.map { node in
            switch node {
            case .image(let index, _):
                return .image(index: index)
            case .audio(_, let stagedAudio):
                return .audio(stagedAudio.filePath)
            case .video(_, let stagedVideo):
                return .video(stagedVideo.filePath, audioFilePath: stagedVideo.audioFilePath)
            case .description(_, let stagedObservationContext):
                return .description(stagedObservationContext.context)
            }
        }
    }

    var discardableLocalMediaFilePaths: [String] {
        audios.map(\.filePath)
            + videos.flatMap { video in
                [video.filePath, video.audioFilePath].compactMap { $0 }
            }
    }

    // MARK: - Mutation

    /// Resets all modalities atomically. Call before starting a new submission.
    mutating func clearAll() {
        images.removeAll()
        audios.removeAll()
        videos.removeAll()
        observationContexts.removeAll()
    }
}

// MARK: - Modality Wrappers

/// A staged audio recording track with its captured file path.
struct StagedAudio {
    let filePath: String
    var addedAt: Date = Date()
}

/// A staged short video clip with five sampled frame images used for AI inference.
struct StagedVideo {
    let filePath: String
    let sampledImages: [StagedImage]
    let audioFilePath: String?
    var addedAt: Date = Date()

    init(
        filePath: String,
        sampledImages: [StagedImage],
        audioFilePath: String? = nil,
        addedAt: Date = Date()
    ) {
        self.filePath = filePath
        self.sampledImages = sampledImages
        self.audioFilePath = audioFilePath
        self.addedAt = addedAt
    }

    var coverImage: StagedImage? {
        sampledImages.first
    }
}

/// A staged text observation context.
struct StagedObservationContext {
    let context: ObservationContext
    var addedAt: Date = Date()
}

// MARK: - StagedImage

/// One staged photograph — groups its inference copy, display copy, thumbnail, and full-resolution
/// original so they always move together and can never become index-misaligned.
struct StagedImage {

    /// 1024 px WebP/JPEG — the payload base64-encoded for Gemini inference. Never exposed to the UI.
    let compressedData: Data

    /// 2048 px WebP/JPEG — written to disk post-inference so the insight sheet and scan library
    /// render crisp without re-compressing from the inference payload.
    let displayData: Data

    /// Decoded `UIImage` used for thumbnail rendering in `ActiveScanToolbar`.
    let uiImage: UIImage

    /// Full-resolution original retained for the crop editor. Holds the `EnvironmentContext`
    /// captured at shutter time (GPS, weather) and whether it came from the photo library.
    let original: IdentifiableImage

    /// Optional transient focus metadata for the final post-crop inference image.
    let focusRegion: NormalizedImageFocusRegion?
    
    /// Chronological insertion tracking for dynamic UI sorting against other capture modalities.
    var addedAt: Date = Date()

    init(
        compressedData: Data,
        displayData: Data,
        uiImage: UIImage,
        original: IdentifiableImage,
        focusRegion: NormalizedImageFocusRegion? = nil,
        addedAt: Date = Date()
    ) {
        self.compressedData = compressedData
        self.displayData = displayData
        self.uiImage = uiImage
        self.original = original
        self.focusRegion = focusRegion
        self.addedAt = addedAt
    }

    func replacing(
        compressedData: Data? = nil,
        displayData: Data? = nil,
        uiImage: UIImage? = nil,
        original: IdentifiableImage? = nil
    ) -> StagedImage {
        StagedImage(
            compressedData: compressedData ?? self.compressedData,
            displayData: displayData ?? self.displayData,
            uiImage: uiImage ?? self.uiImage,
            original: original ?? self.original,
            focusRegion: focusRegion,
            addedAt: addedAt
        )
    }

    func replacingFocusRegion(_ focusRegion: NormalizedImageFocusRegion?) -> StagedImage {
        StagedImage(
            compressedData: compressedData,
            displayData: displayData,
            uiImage: uiImage,
            original: original,
            focusRegion: focusRegion,
            addedAt: addedAt
        )
    }
}
