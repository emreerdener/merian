import Foundation

/// A unified staging container that holds every capture modality a user can
/// combine before a single analysis submission.
///
/// The Shell owns mutation of this value. Staging keeps the ephemeral draft
/// coherent; Submission owns conversion into request and replay descriptors.
struct StagedCapture {
    /// Staged photographs. Capped by the active capture policy.
    var images: [StagedImage] = []

    /// Staged audio recordings and their local file references.
    var audios: [StagedAudio] = []

    /// Staged short video recordings and their sampled inference frames.
    var videos: [StagedVideo] = []

    /// Staged observation contexts from the Describe tab.
    var observationContexts: [StagedObservationContext] = []

    /// Timestamp of the last submit action to prevent rapid duplicate enqueueing.
    var lastSubmitTime: CFAbsoluteTime?

    var isEmpty: Bool {
        images.isEmpty && audios.isEmpty && videos.isEmpty && observationContexts.isEmpty
    }

    var totalItemCount: Int {
        images.count + audios.count + videos.count + observationContexts.count
    }

    var hasVisualMedia: Bool {
        !images.isEmpty || !videos.isEmpty
    }

    /// True when more than one modality carries content.
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

    var discardableLocalMediaFilePaths: [String] {
        audios.map(\.filePath)
            + videos.flatMap { video in
                [video.filePath, video.audioFilePath].compactMap { $0 }
            }
    }

    /// Resets every modality atomically while retaining duplicate-submit state.
    mutating func clearAll() {
        images.removeAll()
        audios.removeAll()
        videos.removeAll()
        observationContexts.removeAll()
    }
}
