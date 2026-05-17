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

    /// Number of inference pipelines currently in-flight (inferencing → finalizing → complete).
    /// `completeSync()` only transitions to `.idle` when this reaches zero, preventing a burst
    /// of concurrent scans from prematurely clearing the sync indicator when the first one finishes.
    private var activeInferenceCount: Int = 0

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

    /// Transitions to `.inferencing` and increments the active count for this scan's pipeline.
    func beginInferencing() {
        activeInferenceCount += 1
        phase = .inferencing
    }

    /// Transitions to `.finalizing` once inference has returned and persistence is about to begin.
    func beginFinalizing() {
        phase = .finalizing
    }

    /// Decrements the active inference pipeline count. Resets to `.idle` only when all in-flight
    /// pipelines have completed — prevents a burst of concurrent scans from prematurely clearing
    /// the indicator when the first one finishes while others are still inferencing or finalizing.
    ///
    /// Call this ONLY from the inference completion path (`processInferenceDownloadResult`).
    /// Upload-phase completions use `completeUploadPhase()` to avoid touching the count.
    func completeSync() {
        activeInferenceCount = max(0, activeInferenceCount - 1)
        if activeInferenceCount == 0 {
            phase = .idle
        }
    }

    /// Transitions to `.idle` only if no inference pipelines are currently active.
    ///
    /// Call this from upload-phase completions (e.g. empty scan queue, URL generation failure)
    /// where there was no inference to begin with — these paths never call `beginInferencing()`,
    /// so they must not decrement `activeInferenceCount`.
    func completeUploadPhase() {
        if activeInferenceCount == 0 {
            phase = .idle
        }
    }

    /// Resets immediately to `.idle` regardless of active count. Used on connectivity loss to
    /// circuit-break all in-flight pipelines — they will replay when connectivity is restored.
    func forceIdle() {
        activeInferenceCount = 0
        phase = .idle
    }
}
