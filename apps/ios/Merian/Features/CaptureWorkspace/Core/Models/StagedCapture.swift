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
    case description(ObservationContext)

    static func defaultTimeline(
        imageCount: Int,
        observationContexts: [ObservationContext],
        audioFilePaths: [String]
    ) -> [CaptureSubmissionMediaItem] {
        var items: [CaptureSubmissionMediaItem] = (0..<imageCount).map { .image(index: $0) }
        items.append(contentsOf: observationContexts.map(Self.description))
        items.append(contentsOf: audioFilePaths.map(Self.audio))
        return items
    }
}

extension Array where Element == CaptureSubmissionMediaItem {
    var audioFilePaths: [String] {
        compactMap { item in
            guard case .audio(let path) = item else { return nil }
            return path
        }
    }

    var observationContexts: [ObservationContext] {
        compactMap { item in
            guard case .description(let context) = item else { return nil }
            return context
        }
    }
}

enum StagedCaptureNode {
    case image(index: Int, stagedImage: StagedImage)
    case audio(index: Int, stagedAudio: StagedAudio)
    case description(index: Int, stagedObservationContext: StagedObservationContext)

    var addedAt: Date {
        switch self {
        case .image(_, let stagedImage):
            return stagedImage.addedAt
        case .audio(_, let stagedAudio):
            return stagedAudio.addedAt
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

    /// Staged observation contexts from the Describe tab before submission.
    var observationContexts: [StagedObservationContext] = []
    
    /// Timestamp of the last submit action to prevent rapid duplicate enqueueing.
    var lastSubmitTime: CFAbsoluteTime?

    // MARK: - Derived State

    var isEmpty: Bool {
        images.isEmpty && audios.isEmpty && observationContexts.isEmpty
    }

    var totalItemCount: Int {
        images.count + audios.count + observationContexts.count
    }

    /// True when more than one modality carries content — drives routing to the combined endpoint.
    var isMultiModal: Bool {
        [!images.isEmpty, !audios.isEmpty, !observationContexts.isEmpty]
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
            case .description(_, let stagedObservationContext):
                return .description(stagedObservationContext.context)
            }
        }
    }

    // MARK: - Mutation

    /// Resets all modalities atomically. Call before starting a new submission.
    mutating func clearAll() {
        images.removeAll()
        audios.removeAll()
        observationContexts.removeAll()
    }
}

// MARK: - Modality Wrappers

/// A staged audio recording track with its captured file path.
struct StagedAudio {
    let filePath: String
    var addedAt: Date = Date()
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
    
    /// Chronological insertion tracking for dynamic UI sorting against other capture modalities.
    var addedAt: Date = Date()
}
