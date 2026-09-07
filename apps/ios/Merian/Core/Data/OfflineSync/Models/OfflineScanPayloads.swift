import Foundation

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

/// A crash-safe claim for upgrading compressed audio persisted by an older
/// queue build. The row is fenced from upload/replay before this value leaves
/// the database actor.
struct LegacyQueuedAudioRepairCandidate: Sendable, Equatable {
    let scanId: String
    let references: [StoredMediaReference]
    let retainedAudioFileNames: Set<String>
}

struct LegacyQueuedAudioRepairReplacement: Sendable, Equatable {
    let sourceStorage: MediaStorageLocation
    let sourcePath: String
    let replacementFileName: String
}

enum LegacyQueuedAudioRepairState {
    /// Persisted before transcoding starts. Upload/inference claims must ignore
    /// the row until the replacement manifest commits.
    static let inProgressGeneration = -1
    static let completedGeneration = 2
}

struct LegacyQueuedAudioRepairResult: Sendable, Equatable {
    var repairedScanIds = Set<String>()
    var failedScanIds = Set<String>()
    var claimedScanIds = Set<String>()

    var didMutate: Bool {
        !claimedScanIds.isEmpty
    }
}

typealias LegacyQueuedAudioFilePreparer =
    @Sendable (URL, String) async throws -> URL
