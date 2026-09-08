// MARK: - Pending Scan Payload

/// Minimal Sendable snapshot of a pending queued scan, safe to pass across actor boundaries.
///
/// Captured by `BackgroundDatabaseActor.fetchPendingScans` so the caller can build upload
/// items without touching the main-actor-bound `ModelContext` again.
struct PendingScanPayload: Sendable {
    let id: String
    let localImagePaths: [String]
    let localAudioPaths: [String]
    let localVideoPaths: [String]

    var localUploadPaths: [String] {
        localImagePaths + localAudioPaths + localVideoPaths
    }
}
