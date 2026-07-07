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
    /// Hardware constraints injected for tests/previews; production uses the shared orchestrator.
    @ObservationIgnored var hardwareOrchestrator = HardwareOrchestrator.shared

    /// Active upload batch task. Cancelled immediately on connectivity loss.
    var syncTask: Task<Void, Never>?
    /// Active collection sync task. Cancelled immediately on connectivity loss.
    /// Returns `true` when the attempt succeeded and `false` when the pending bit
    /// should be left in place for a later retry opportunity.
    var collectionSyncTask: Task<Bool, Never>?
    /// Monotonic revision bumped on every local collection mutation enqueue.
    /// Prevents an older successful sync run from clearing a newer pending delete/rename.
    @ObservationIgnored var collectionSyncRevision: UInt64 = 0
    /// Debounced reconnect task. Cancelled and replaced on each connectivity-restored event
    /// to prevent stacked syncs when the OS path monitor fires multiple times in quick succession.
    @ObservationIgnored private var reconnectDebounceTask: Task<Void, Never>?

    /// Scans that have been claimed as `.inferencing` while the background URLSession
    /// download task is still being built. Replay must treat these as active so the
    /// WeatherKit/request-construction window does not get mistaken for an orphan.
    @ObservationIgnored var inferencePreparationScanIds: Set<String> = []

    /// Scans that have been claimed as `.uploading` while signed URLs are being fetched
    /// and URLSession upload tasks are being created. Upload orphan reconciliation must
    /// treat these as active so it does not reset a live upload before its task exists.
    @ObservationIgnored var uploadPreparationScanIds: Set<String> = []

    /// Scans whose upload task has completed and is being promoted from `.uploading`
    /// to `.staged`. During this tiny window the URLSession task is gone, so orphan
    /// reconciliation must still treat the scan as active.
    @ObservationIgnored var uploadCompletionScanIds: Set<String> = []

    /// Delayed status probes for inference tasks. The edge function can persist the
    /// scan but lose the background response path; these probes recover from that gap.
    @ObservationIgnored var inferenceStatusProbeTasks: [String: Task<Void, Never>] = [:]

    /// Delayed polls for scans owned by the server-side ingestion job after the
    /// background URLSession task has finished or been cancelled locally.
    @ObservationIgnored var serverIngestionPollTasks: [String: Task<Void, Never>] = [:]

    /// Last server-side ingestion job status observed for queued scans. Used only for
    /// user-facing transient copy while the backend remains the durable source of truth.
    var scanIngestionJobStates: [String: ScanIngestionJobStatus] = [:]
    /// Scan IDs whose next attempt was explicitly requested by the user. These may bypass
    /// expensive-network video deferral for one sync cycle.
    @ObservationIgnored var userRequestedLargeUploadScanIds: Set<String> = []

    /// Scans whose inference response is being processed. During this window the
    /// URLSession task is already gone, but replay must not treat the scan as orphaned.
    @ObservationIgnored var inferenceCompletionScanIds: Set<String> = []

    /// Dispatch timestamps for active inference tasks, used only for watchdog logging.
    @ObservationIgnored var inferenceDispatchDates: [String: Date] = [:]

    /// Guards the one-time cold-start reconciliation of orphaned `.uploading` scans.
    /// Runs exactly once per process life on the first connectivity restore.
    @ObservationIgnored var hasReconciledStartupState = false

#if DEBUG
    /// Number of scans successfully claimed for inference by `replayInferenceStagedScans`.
    /// Incremented before any network work begins — provides a network-free observable
    /// for tests verifying that the staged-scan replay pipeline was triggered.
    @ObservationIgnored var replayedStagedScanCount: Int = 0
#endif

    // MARK: - Backoff & Debounce State

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
    /// Container that owns `_inferenceDbActor`. Tracked to detect container swaps (e.g. in
    /// tests) so a stale actor bound to a dead container is not returned to callers.
    @ObservationIgnored private var _inferenceDbActorContainer: ModelContainer?
    /// Persistent `ProfileDatabaseActor` reused for award recalculation.
    @ObservationIgnored private var _profileDbActor: ProfileDatabaseActor?

    /// Returns the shared inference actor, creating it if the container changed or the actor
    /// has not yet been created. In production the container is a process-lifetime singleton,
    /// so this is effectively a one-time allocation. In tests each test suite creates an
    /// in-memory container, and the identity check prevents returning a stale actor backed
    /// by a previous test's already-deallocated store.
    func resolvedInferenceDbActor(container: ModelContainer) -> BackgroundDatabaseActor {
        if let existing = _inferenceDbActor, _inferenceDbActorContainer === container { return existing }
        let actor = BackgroundDatabaseActor(modelContainer: container)
        _inferenceDbActor = actor
        _inferenceDbActorContainer = container
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
        if !TestExecutionCoordinator.isRunningTests {
            startMonitoring()
        }
    }

    // MARK: - Network Monitoring

    var isCurrentNetworkConstrained: Bool {
        monitor.currentPath.isConstrained
    }

    var allowsLargeQueuedUploadsOnCurrentNetwork: Bool {
        let path = monitor.currentPath
        return !path.isConstrained && !path.isExpensive
    }

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
                        // Debounce 3s to let the OS networking stack fully settle before syncing.
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        guard !Task.isCancelled else { return }
                        // Skip background sync on constrained networks (Low Data Mode).
                        if self.isCurrentNetworkConstrained { return }
                        await OfflineJobScheduler.shared.drainRunnableJobs(using: self)
                    }
                } else {
                    // Circuit-break active uploads immediately on connectivity loss.
                    self?.reconnectDebounceTask?.cancel()
                    self?.reconnectDebounceTask = nil
                    self?.syncTask?.cancel()
                    self?.collectionSyncTask?.cancel()
                    // Cancel any pending backoff retry — it must not fire while offline.
                    self?.retryBackoffTask?.cancel()
                    self?.serverIngestionPollTasks.values.forEach { $0.cancel() }
                    self?.serverIngestionPollTasks.removeAll()
                    self?.isSyncing = false
                    self?.isCollectionSyncing = false
                    SyncStateManager.shared.forceIdle()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }
}
