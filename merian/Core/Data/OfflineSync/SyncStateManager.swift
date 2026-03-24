import Foundation
import Observation

// MARK: - Sync Phase

/// Exhaustive states of the offline-sync pipeline.
///
/// Driven exclusively by `OfflineQueueManager` — do not mutate from anywhere else.
enum SyncPhase: Equatable {
    /// No sync activity in progress.
    case idle
    /// Image files are being uploaded to R2 staging. `count` is the number of scans in the batch.
    case uploading(count: Int)
    /// All files landed; the Gemini inference Edge function is running.
    case inferencing
    /// Inference complete; writing `LocalScanRecord` and cleaning up queue entries.
    case finalizing

    /// True for any active (non-idle) phase.
    var isActive: Bool { self != .idle }

    /// Human-readable label for debugging and UI.
    var label: String {
        switch self {
        case .idle:                 return "Idle"
        case .uploading(let n):     return "Uploading (\(n))"
        case .inferencing:          return "Inferencing"
        case .finalizing:           return "Finalizing"
        }
    }
}

// MARK: - Sync State Manager

/// Observable source of truth for sync progress, consumed by UI components.
///
/// Driven exclusively by `OfflineQueueManager` — do not mutate from anywhere else.
@MainActor
@Observable final class SyncStateManager {

    // MARK: - Singleton

    static let shared = SyncStateManager()

    // MARK: - State

    /// Current phase of the sync pipeline.
    var phase: SyncPhase = .idle

    // MARK: - Computed Compatibility Shims

    /// True while any sync phase is active. Use `phase` for granular UI decisions.
    var isSyncing: Bool { phase.isActive }

    /// Number of scans in the current upload batch; 0 outside `.uploading`.
    var pendingUploadCount: Int {
        if case .uploading(let count) = phase { return count }
        return 0
    }

    // MARK: - Lifecycle

    private init() {}

    // MARK: - Sync Control

    /// Transitions to `.uploading` for a known batch size.
    func beginSync(itemCount: Int) {
        phase = .uploading(count: itemCount)
    }

    /// Transitions to `.inferencing` once all image files for a scan have landed in R2 staging.
    func beginInferencing() {
        phase = .inferencing
    }

    /// Transitions to `.finalizing` once inference has returned and persistence is about to begin.
    func beginFinalizing() {
        phase = .finalizing
    }

    /// Resets to `.idle` after all batch uploads have settled or on connectivity loss.
    func completeSync() {
        phase = .idle
    }
}
