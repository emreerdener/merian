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
    private(set) var phase: SyncPhase = .idle

    private struct UploadActivity {
        let generation: UUID
        let itemCount: Int
    }

    private enum InferenceActivity {
        case inferencing
        case finalizing
    }

    /// Upload and inference work is tracked by generation rather than an integer count.
    /// A late completion can remove only the exact generation that originally began work.
    private var activeUpload: UploadActivity?
    private var activeInferences: [UUID: InferenceActivity] = [:]

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
    func beginSync(itemCount: Int, generation: UUID) {
        activeUpload = UploadActivity(
            generation: generation,
            itemCount: itemCount
        )
        refreshPhase()
    }

    /// Registers one inference generation. Re-registering the same token is idempotent.
    func beginInferencing(generation: UUID) {
        if activeInferences[generation] == nil {
            activeInferences[generation] = .inferencing
        }
        refreshPhase()
    }

    /// Transitions to `.finalizing` once inference has returned and persistence is about to begin.
    func beginFinalizing(generation: UUID) {
        guard activeInferences[generation] != nil else { return }
        activeInferences[generation] = .finalizing
        refreshPhase()
    }

    /// Completes only the matching inference generation. Unknown or already-completed tokens
    /// are harmless no-ops, so a late callback cannot decrement newer work.
    ///
    /// Call this ONLY from the inference completion path (`processInferenceDownloadResult`).
    /// Upload-phase completions use `completeUploadPhase(generation:)`.
    func completeSync(generation: UUID) {
        activeInferences[generation] = nil
        refreshPhase()
    }

    /// Clears only the matching upload generation. A stale expiration or delegate callback
    /// cannot clear a replacement batch.
    func completeUploadPhase(generation: UUID) {
        guard activeUpload?.generation == generation else { return }
        activeUpload = nil
        refreshPhase()
    }

    /// Invalidates all current tokens. Late completions become no-ops because their
    /// generations are no longer registered.
    func forceIdle() {
        activeUpload = nil
        activeInferences.removeAll()
        refreshPhase()
    }

    private func refreshPhase() {
        if activeInferences.values.contains(where: { activity in
            if case .finalizing = activity { return true }
            return false
        }) {
            phase = .finalizing
        } else if !activeInferences.isEmpty {
            phase = .inferencing
        } else if let activeUpload {
            phase = .uploading(count: activeUpload.itemCount)
        } else {
            phase = .idle
        }
    }
}
