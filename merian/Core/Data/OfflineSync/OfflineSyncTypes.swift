import Foundation
import SwiftData

// MARK: - Offline Sync Data Transfer Objects
//
// Sendable value types shared across the offline sync pipeline:
//   OfflineQueueManager (+Sync, +URLSession, +Queue)
//   BackgroundDatabaseActor
//   InferenceEngine (read-only, result hydration)
//
// Keeping these in one file prevents them from being buried inside actor or
// extension files where unrelated readers wouldn't think to look.

// MARK: - Pending Scan Payload

/// Minimal Sendable snapshot of a pending queued scan, safe to pass across actor boundaries.
///
/// Captured by `BackgroundDatabaseActor.fetchPendingScans` so the caller can build upload
/// items without touching the main-actor-bound `ModelContext` again.
struct PendingScanPayload: Sendable {
    let id: String
    let localImagePaths: [String]
}

// MARK: - Scan Upload Item

/// Flat representation of a single image file ready for a presigned R2 PUT.
struct ScanUploadItem {
    let scanId: String
    /// Per-scan slot index (0…N-1). Distinct from the flat batch position across all scans.
    let imageIndex: Int
    let fileName: String
    let fileURL: URL
}

// MARK: - Extracted Scan Data

/// Sendable snapshot of `OfflineQueuedScan` metadata captured on the main actor.
///
/// Passed across the actor boundary into `dispatchInferenceDownloadTask` so that
/// background inference can proceed without touching the main-actor-bound `ModelContext`.
struct ExtractedScanData: Sendable {
    /// Environmental and capture telemetry for the scan, used as Gemini inference context.
    let telemetry: CaptureTelemetry
    /// Filenames of local images relative to the Documents directory.
    let localImagePaths: [String]
    /// Confirmed R2 object keys stored at upload time.
    /// Non-empty on the offline queue path; empty on the live inference path.
    let r2Keys: [String]
    /// The model container, used to create a new `BackgroundDatabaseActor` on the inference thread.
    let container: ModelContainer
    let originalTimestamp: Date
}

// MARK: - Offline Scan Processing Result

/// Result returned by `BackgroundDatabaseActor.processAndCleanupOfflineScan`.
struct OfflineScanProcessingResult {
    let resolvedSpeciesName: String?
    let isNewDiscovery: Bool
    let finalScanId: String?
    /// The fully-parsed result, present when inference succeeded (confidenceScore > 0).
    /// Passed back to the main actor so the live InferenceEngine can be hydrated directly
    /// when the background path races ahead of the suspended live inference task.
    let speciesData: SpeciesData?
    /// True when the background context's save committed (inserting the `LocalScanRecord` on
    /// success, or a no-op save on a confidence==0 failure). When true, the caller must invoke
    /// `flushOfflineQueuedScan` on the main actor to delete the `OfflineQueuedScan` there.
    ///
    /// The background context intentionally does NOT delete the `OfflineQueuedScan`. Delegating
    /// the deletion to the main actor guarantees the main `ModelContext` always has a real
    /// pending change when it saves — the only reliable way to trigger `@Query` re-evaluation
    /// in a presented sheet (SwiftData platform limitation: background context saves do not
    /// reliably propagate to `@Query` in open sheets via remote change notifications).
    let wasCleaned: Bool
}
