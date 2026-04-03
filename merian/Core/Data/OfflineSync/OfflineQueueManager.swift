import Foundation
import Network
import Observation
import os
import SwiftData

// MARK: - Offline Queue Manager

/// Persistent background sync engine for upload queuing and cloud deletions.
///
/// Observes network reachability via `NWPathMonitor` and automatically replays
/// queued operations when connectivity is restored. All sync work runs in
/// `BackgroundTaskWrapper` tasks so iOS grants extended execution time.
///
/// Extensions:
/// - `OfflineQueueManager+Sync` — upload, deletion, and collection sync flows
/// - `OfflineQueueManager+URLSession` — background session delegate and inference pipeline
/// - `OfflineQueueManager+Queue` — capture enqueue and local queue maintenance
@MainActor
@Observable final class OfflineQueueManager: NSObject {

    // MARK: - Singleton

    static let shared = OfflineQueueManager()

    // MARK: - Infrastructure

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.merian.OfflineSyncMonitor")

    /// Background `URLSession` used for resumable R2 staging uploads.
    /// Lazy so iOS can re-attach in-flight tasks on relaunch before the session is first accessed.
    /// Note: Background sessions permanently stall in the iOS Simulator due to Xcode debugger attachment.
    /// A `.default` configuration is conditionally used for `.simulator` builds to ensure local testing works.
    @ObservationIgnored
    lazy var backgroundSession: URLSession = {
        #if targetEnvironment(simulator)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 90
        #else
        let config = URLSessionConfiguration.background(withIdentifier: "com.merian.OfflineSyncBackground")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        #endif
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - State

    /// Whether the device currently has a satisfied network path.
    var isOnline: Bool = false
    /// Number of `OfflineQueuedScan` records that have not yet been uploaded.
    var unsyncedItemsCount: Int = 0
    /// Stored by the app delegate when iOS wakes the app for a background session event.
    var backgroundCompletionHandler: (() -> Void)?
    /// True while an upload batch is actively in-flight.
    var isSyncing: Bool = false
    /// True while a collection sync batch is actively in-flight.
    var isCollectionSyncing: Bool = false
    /// SwiftData context injected at app startup via `ScanRepository.configure(with:)`.
    var modelContext: ModelContext?

    /// Active upload batch task. Cancelled immediately on connectivity loss.
    var syncTask: Task<Void, Never>?
    /// Active collection sync task. Cancelled immediately on connectivity loss.
    var collectionSyncTask: Task<Void, Never>?
    /// Debounced reconnect task. Cancelled and replaced on each connectivity-restored event
    /// to prevent stacked syncs when the OS path monitor fires multiple times in quick succession.
    @ObservationIgnored private var reconnectDebounceTask: Task<Void, Never>?

    /// In-memory counter tracking consecutive transient upload/inference failures per scan ID.
    /// Resets on app restart — a fresh process always gets a clean slate of retries.
    @ObservationIgnored var uploadRetryCount: [String: Int] = [:]

    /// Guards the one-time cold-start reconciliation of orphaned `.uploading` scans.
    /// Runs exactly once per process life on the first connectivity restore.
    @ObservationIgnored var hasReconciledStartupState = false

    /// Counts inference pipelines currently in flight.
    /// Used by `replayInferenceForUploadedScans` to skip `resetOrphanedInferencingScans`
    /// when a live pipeline holds `.inferencing` legitimately, preventing a double-pipeline race.
    @ObservationIgnored var activeInferencePipelineCount: Int = 0

    /// Maximum consecutive transient errors before a scan is tombstoned.
    static let maxUploadRetries = 3
    /// Maximum delay between `generateUploadURLs` failure retries (seconds).
    static let maxUploadRetryDelay: TimeInterval = 30

    // MARK: - Backoff & Debounce State

    /// Current exponential-backoff delay for `generateUploadURLs` failures.
    /// Doubles on each consecutive failure up to `maxUploadRetryDelay`; reset to 0 on success.
    @ObservationIgnored var uploadRetryDelay: TimeInterval = 0
    /// Cancellable task that fires a delayed `syncPendingScans()` retry after a URL-generation failure.
    /// Cancelled on connectivity loss so stale retries never fire after going offline.
    @ObservationIgnored var retryBackoffTask: Task<Void, Never>?
    /// Cancellable task that coalesces rapid burst completions into a single `calculateAwards()` pass.
    /// Scheduled 0.5 s after the last inference completion; cancelled and rescheduled on each new result.
    @ObservationIgnored var awardsDebounceTask: Task<Void, Never>?

    // MARK: - Long-Lived Database Actors

    /// Persistent `BackgroundDatabaseActor` reused across offline inference calls.
    /// Avoids the per-call actor allocation + ModelContext setup overhead when scans
    /// complete in rapid succession. Initialized lazily on first use after `modelContext` is set.
    @ObservationIgnored private var _inferenceDbActor: BackgroundDatabaseActor?
    /// Persistent `ProfileDatabaseActor` reused for award recalculation.
    @ObservationIgnored private var _profileDbActor: ProfileDatabaseActor?

    /// Returns the shared inference actor, creating it once from the provided container.
    func resolvedInferenceDbActor(container: ModelContainer) -> BackgroundDatabaseActor {
        if let existing = _inferenceDbActor { return existing }
        let actor = BackgroundDatabaseActor(modelContainer: container)
        _inferenceDbActor = actor
        return actor
    }

    /// Returns the shared profile actor, creating it once from the provided container.
    func resolvedProfileDbActor(container: ModelContainer) -> ProfileDatabaseActor {
        if let existing = _profileDbActor { return existing }
        let actor = ProfileDatabaseActor(modelContainer: container)
        _profileDbActor = actor
        return actor
    }

    // MARK: - Lifecycle

    private override init() {
        super.init()
        _ = backgroundSession // Force-init so iOS can re-attach background tasks on relaunch.
        startMonitoring()
    }

    // MARK: - Network Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let newStatus = path.status == .satisfied
                guard newStatus != self?.isOnline else { return }

                self?.isOnline = newStatus
                MerianLog.data.debug("Network: \(newStatus ? "Online" : "Offline", privacy: .public)")

                if newStatus {
                    // Cancel any pending debounce before rescheduling to prevent stacked sync
                    // calls when the OS path monitor fires multiple times in quick succession
                    // (e.g. WiFi → cellular → WiFi within a single second).
                    self?.reconnectDebounceTask?.cancel()
                    self?.reconnectDebounceTask = Task { [weak self] in
                        guard let self else { return }
                        // Debounce 1s to let the OS networking stack fully settle before syncing.
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !Task.isCancelled else { return }
                        self.syncPendingScans()
                        self.replayInferenceForUploadedScans()
                        await self.syncPendingDeletions()
                        self.syncCollectionsIfPending()
                    }
                } else {
                    // Circuit-break active uploads immediately on connectivity loss.
                    self?.reconnectDebounceTask?.cancel()
                    self?.syncTask?.cancel()
                    self?.collectionSyncTask?.cancel()
                    // Cancel any pending backoff retry — it must not fire while offline.
                    self?.retryBackoffTask?.cancel()
                    self?.isSyncing = false
                    self?.isCollectionSyncing = false
                    SyncStateManager.shared.completeSync()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }
}
