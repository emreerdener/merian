import UIKit

/// Maximum number of images that can be staged for a single analysis submission.
/// Kept as a single source of truth so camera guards, toolbar pickers, and
/// view-layer checks never drift out of sync with each other.
let stagedImageCapacity = 2

/// A unified staging container that holds every capture modality a user can combine
/// before a single analysis submission.
///
/// Replaces the four parallel image arrays in `CameraViewModel` (`activeScanImages`,
/// `activeScannedDatas`, `activeOriginals`, `activeDisplayDatas`) with one coherent
/// value type. Any combination of modalities is valid:
/// - images only (existing behaviour, up to 2)
/// - description only (solo Describe path)
/// - images + description (combined path → `identify` with context injection)
/// - audio only / audio + images / audio + description (reserved; wired in when
///   `AudioRecordingView` ships its recording pipeline)
///
/// Always accessed from `@MainActor` via `CameraViewModel` — no `Sendable` conformance needed.
struct StagedCapture {

    // MARK: - Modalities

    /// Staged photographs. Capped at 2 — the same limit as the original image-only flow.
    var images: [StagedImage] = []

    /// Reserved for an audio recording clip.
    /// Populated when `AudioRecordingView` ships its recording pipeline.
    var audioFilePath: String?

    /// Optional describe description staged from the Describe tab before submission.
    var observationContext: ObservationContext?
    
    /// Timestamp of the last describe submission to prevent rapid identical enqueueing.
    var lastSubmitTime: CFAbsoluteTime?

    // MARK: - Derived State

    var isEmpty: Bool {
        images.isEmpty && audioFilePath == nil && observationContext == nil
    }

    /// True when more than one modality carries content — drives routing to the combined endpoint.
    var isMultiModal: Bool {
        [!images.isEmpty, audioFilePath != nil, observationContext != nil]
            .filter { $0 }.count > 1
    }

    // MARK: - Mutation

    /// Resets all modalities atomically. Call before starting a new submission.
    mutating func clearAll() {
        images.removeAll()
        audioFilePath = nil
        observationContext = nil
    }
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
