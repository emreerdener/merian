import Foundation
import Network
import Observation
import os
import SwiftData

/// Tracks asynchronous terminal persistence spawned by background URLSession
/// delegate callbacks. Registration is synchronous and lock-protected so
/// `urlSessionDidFinishEvents` cannot overtake a hop to the main actor.
final class BackgroundURLSessionTerminalWorkTracker: @unchecked Sendable {
    struct Token: Hashable, Sendable {
        fileprivate let id = UUID()
    }

    private let lock = NSLock()
    private var activeTokens: Set<Token> = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    func begin() -> Token {
        let token = Token()
        _ = lock.withLock { activeTokens.insert(token) }
        return token
    }

    func finish(_ token: Token) {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            guard activeTokens.remove(token) != nil,
                  activeTokens.isEmpty else {
                return []
            }
            let pending = idleWaiters
            idleWaiters.removeAll()
            return pending
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            let isAlreadyIdle = lock.withLock {
                guard !activeTokens.isEmpty else { return true }
                idleWaiters.append(continuation)
                return false
            }
            if isAlreadyIdle {
                continuation.resume()
            }
        }
    }

    var activeCountForTesting: Int {
        lock.withLock { activeTokens.count }
    }
}

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
        config.allowsConstrainedNetworkAccess = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Ordinary Auth-work leases transferred to URLSession tasks at `resume`.
    /// Unlike a dispatch-scope lease, these remain live until the terminal
    /// delegate callback finishes all durable local processing.
    @ObservationIgnored var backgroundAccountWorkLeases:
        [Int: AccountBoundWorkLease] = [:]

    /// Terminal delegate processors must finish durable persistence and release
    /// their Auth-work leases before the app tells iOS it may suspend again.
    nonisolated static let backgroundTerminalWorkTracker =
        BackgroundURLSessionTerminalWorkTracker()

    /// Testable system-completion boundary shared by the URLSession delegate.
    /// The handler is taken only after every synchronously registered terminal
    /// processor has committed its durable state and released its Auth lease.
    static func invokeBackgroundSessionCompletionAfterTerminalWork(
        tracker: BackgroundURLSessionTerminalWorkTracker,
        takeHandler: @MainActor () -> (() -> Void)?
    ) async {
        await tracker.waitUntilIdle()
        takeHandler()?()
    }

    // MARK: - State

    /// Whether the device currently has a satisfied network path.
    var isOnline: Bool = false
    /// Live path policy is observable so views that own automatic-recovery
    /// tasks can stop or restart them when Wi-Fi, cellular, or Low Data Mode
    /// changes without a connectivity-status transition.
    private var currentPathIsConstrained = false
    private var currentPathIsExpensive = false
    /// Number of `OfflineQueuedScan` records that have not yet been uploaded.
    var unsyncedItemsCount: Int = 0
    /// Stored by the app delegate when iOS wakes the app for a background session event.
    var backgroundCompletionHandler: (() -> Void)?
    /// True while an upload batch is actively in-flight.
    var isSyncing: Bool = false
    /// True while a collection sync batch is actively in-flight.
    var isCollectionSyncing: Bool = false
    /// Process-local single-flight guard for the durable cloud-erasure queue.
    ///
    /// The persisted `.running` state remains restartable after termination,
    /// while this latch prevents two foreground wake sources from deleting the
    /// same SwiftData task concurrently in one process.
    @ObservationIgnored var isCloudDeletionSyncing: Bool = false
    /// SwiftData context injected at app startup via `ScanRepository.configure(with:)`.
    var modelContext: ModelContext?
    /// Hardware constraints injected for tests/previews; production uses the shared orchestrator.
    @ObservationIgnored var hardwareOrchestrator = HardwareOrchestrator.shared

    /// Active upload batch task. Cancelled immediately on connectivity loss.
    var syncTask: Task<Void, Never>?
    /// Generation currently allowed to mutate the global upload-sync latch.
    /// Expiration and completion paths must compare this value before clearing state.
    @ObservationIgnored var syncGeneration: UUID?
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
    @ObservationIgnored var inferencePreparationGenerations: [String: UUID] = [:]

    var inferencePreparationScanIds: Set<String> {
        Set(inferencePreparationGenerations.keys)
    }

    /// Scans that have been claimed as `.uploading` while signed URLs are being fetched
    /// and URLSession upload tasks are being created. Upload orphan reconciliation must
    /// treat these as active so it does not reset a live upload before its task exists.
    @ObservationIgnored var uploadPreparationGenerations: [String: UUID] = [:]

    var uploadPreparationScanIds: Set<String> {
        Set(uploadPreparationGenerations.keys)
    }

    /// Latest upload generation that successfully claimed each queued scan.
    ///
    /// This remains after preparation ends so a delayed completion from an older
    /// upload cannot be re-adopted after a replacement batch has finished.
    @ObservationIgnored var latestUploadGenerations: [String: UUID] = [:]

    /// Scans whose upload callbacks are being promoted from `.uploading` to
    /// `.staged`. Each callback owns one token, so finishing an older callback
    /// removes only its own membership and cannot hide a newer callback.
    @ObservationIgnored var uploadCompletionTokens: [String: Set<UUID>] = [:]

    var uploadCompletionScanIds: Set<String> {
        Set<String>(uploadCompletionTokens.compactMap { key, tokens -> String? in
            tokens.isEmpty ? nil : key
        })
    }

    /// Successful members observed for the current logical upload manifest.
    ///
    /// URLSession removes a completed task before its asynchronous result
    /// handler necessarily runs. Requiring duplicate-free equality with the
    /// expected object-key set prevents a successful sibling from advancing a
    /// scan while a failed or stale sibling's callback is still queued.
    @ObservationIgnored var uploadCompletionStates:
        [String: MediaStagingUploadCompletionState] = [:]

    /// Live scans that are durably queued but intentionally held until the
    /// foreground inference request has finished sending its body. This avoids
    /// two copies of the same media competing for the device uplink.
    @ObservationIgnored var deferredLiveUploadScanIds: Set<String> = []

    /// Foreground identification generation currently owning each queued scan.
    ///
    /// Recovery media may upload after the inline body is sent, but background
    /// inference must wait for this exact owner to finish. A dictionary rather
    /// than a set prevents a delayed completion from releasing a replacement
    /// foreground attempt for the same scan.
    @ObservationIgnored var foregroundInferenceGenerations: [String: UUID] = [:]

    var foregroundInferenceScanIds: Set<String> {
        Set(foregroundInferenceGenerations.keys)
    }

    /// Foreground generations that have atomically entered a provider pipeline.
    /// A generation is single-use even if a second engine instance attempts to
    /// submit the same queued work.
    @ObservationIgnored var startedForegroundInferenceGenerations: [String: UUID] = [:]

    /// Retrying durable handoffs for terminal foreground generations. Registry
    /// tokens ensure a delayed task cannot clear or act on a replacement.
    @ObservationIgnored let foregroundInferenceRetirementTasks =
        GenerationTaskRegistry<String>()

    /// Delayed status probes for inference tasks. Registry tokens prevent a
    /// cooperatively-cancelled probe from clearing or acting on its replacement.
    @ObservationIgnored let inferenceStatusProbeTasks = GenerationTaskRegistry<String>()

    /// Delayed polls for scans owned by the server-side ingestion job after the
    /// background URLSession task has finished or been cancelled locally.
    @ObservationIgnored let serverIngestionPollTasks = GenerationTaskRegistry<String>()

    /// Per-scan delayed inference replay tasks. These share the same
    /// compare-before-clear ownership contract as probes and server polls.
    @ObservationIgnored let inferenceRetryTasks = GenerationTaskRegistry<String>()

    /// Current inference generation for each scan. URLSession callbacks and
    /// watchdogs from older generations must not mutate a newer entry.
    @ObservationIgnored var activeInferenceGenerations: [String: UUID] = [:]
    /// Generations explicitly completed or invalidated during this process.
    /// Prevents a delayed URLSession callback from re-adopting retired work.
    @ObservationIgnored var retiredInferenceGenerations: Set<UUID> = []

    /// Last server-side ingestion job status observed for queued scans. Used only for
    /// user-facing transient copy while the backend remains the durable source of truth.
    var scanIngestionJobStates: [String: ScanIngestionJobStatus] = [:]
    /// Scan IDs whose next attempt was explicitly requested by the user. These may bypass
    /// expensive-network video deferral for one sync cycle.
    @ObservationIgnored var userRequestedLargeUploadScanIds: Set<String> = []

    /// Scans whose inference response is being processed. During this window the
    /// URLSession task is already gone, but replay must not treat the scan as orphaned.
    @ObservationIgnored var inferenceCompletionGenerations: [String: UUID] = [:]

    var inferenceCompletionScanIds: Set<String> {
        Set(inferenceCompletionGenerations.keys)
    }

    /// Dispatch timestamps for active inference tasks, used only for watchdog logging.
    @ObservationIgnored var inferenceDispatchDates: [String: Date] = [:]

    /// Guards the one-time cold-start reconciliation of orphaned `.uploading` scans.
    /// Runs exactly once per process life on the first connectivity restore.
    @ObservationIgnored var hasReconciledStartupState = false
    /// Process-local single-flight guard for upload/inference orphan
    /// reconciliation. Library, scheduler, reconnect, and URLSession wake
    /// sources can arrive together; only one may enumerate and mutate the
    /// durable queue at a time.
    @ObservationIgnored var isInferenceReplayReconciling = false
    /// Coalesces any wake received while replay reconciliation is active into
    /// one trailing pass so state changes are not dropped.
    @ObservationIgnored var inferenceReplayRequestedWhileReconciling = false

#if DEBUG
    /// Number of scans successfully claimed for inference by `replayInferenceStagedScans`.
    /// Incremented before any network work begins — provides a network-free observable
    /// for tests verifying that the staged-scan replay pipeline was triggered.
    @ObservationIgnored var replayedStagedScanCount: Int = 0
#endif

    // MARK: - Backoff State

    /// Cancellable task that fires a delayed `syncPendingScans()` retry after a URL-generation failure.
    /// Cancelled on connectivity loss so stale retries never fire after going offline.
    @ObservationIgnored var retryBackoffTask: Task<Void, Never>?

    // MARK: - Long-Lived Database Actors

    /// Persistent `BackgroundDatabaseActor` reused for queue claims, reconciliation,
    /// and replay. A single actor keeps upload and inference transitions ordered and
    /// prevents stale ModelContext snapshots from overwriting replacement work.
    @ObservationIgnored private var _queueDbActor: BackgroundDatabaseActor?
    /// Container that owns `_queueDbActor`. Tracked to detect container swaps (e.g. in
    /// tests) so a stale actor bound to a dead container is not returned to callers.
    @ObservationIgnored private var _queueDbActorContainer: ModelContainer?
    /// Persistent `ProfileDatabaseActor` reused for award recalculation.
    @ObservationIgnored private var _profileDbActor: ProfileDatabaseActor?
    /// Container that owns `_profileDbActor`; store recovery and tests can
    /// replace the app's model container during this process lifetime.
    @ObservationIgnored private var _profileDbActorContainer: ModelContainer?

    /// Claims the pre-dispatch single-flight slot for a scan.
    ///
    /// Returning `nil` is intentional: replacing an existing preparation would
    /// make its eventual compare-before-clear invisible to orphan reconciliation.
    func beginInferencePreparation(scanId: String) -> UUID? {
        guard inferencePreparationGenerations[scanId] == nil else { return nil }
        let generation = UUID()
        inferencePreparationGenerations[scanId] = generation
        return generation
    }

    func clearInferencePreparation(
        scanId: String,
        generation: UUID
    ) {
        guard inferencePreparationGenerations[scanId] == generation else { return }
        inferencePreparationGenerations[scanId] = nil
    }

    func isInferencePreparationCurrent(
        scanId: String,
        generation: UUID
    ) -> Bool {
        inferencePreparationGenerations[scanId] == generation
    }

    /// Claims the process-local orphan-reconciliation driver. A concurrent
    /// caller records one trailing pass instead of starting overlapping status
    /// probes and SwiftData transitions.
    func beginInferenceReplayReconciliation() -> Bool {
        guard !isInferenceReplayReconciling else {
            inferenceReplayRequestedWhileReconciling = true
            return false
        }
        isInferenceReplayReconciling = true
        return true
    }

    /// Releases the orphan-reconciliation driver and reports whether one
    /// coalesced trailing pass is required.
    @discardableResult
    func finishInferenceReplayReconciliation() -> Bool {
        guard isInferenceReplayReconciling else { return false }
        isInferenceReplayReconciling = false
        let shouldReplay = inferenceReplayRequestedWhileReconciling
        inferenceReplayRequestedWhileReconciling = false
        return shouldReplay
    }

    func beginUploadCompletion(scanId: String) -> UUID {
        let token = UUID()
        uploadCompletionTokens[scanId, default: []].insert(token)
        return token
    }

    @discardableResult
    func finishUploadCompletion(
        scanId: String,
        token: UUID
    ) -> Bool {
        guard uploadCompletionTokens[scanId]?.remove(token) != nil else {
            return false
        }
        if uploadCompletionTokens[scanId]?.isEmpty == true {
            uploadCompletionTokens[scanId] = nil
        }
        return true
    }

    func recordSuccessfulUploadMember(
        scanId: String,
        generation: UUID?,
        objectKey: String
    ) {
        var state = uploadCompletionStates[scanId]
        if state == nil || state?.generation != generation {
            state = MediaStagingUploadCompletionState(generation: generation)
        }
        guard var state else { return }
        state.recordSuccess(objectKey: objectKey)
        uploadCompletionStates[scanId] = state
    }

    func hasConfirmedSuccessfulUploadManifest(
        scanId: String,
        generation: UUID?,
        expectedObjectKeys: [String]
    ) -> Bool {
        guard let state = uploadCompletionStates[scanId],
              state.generation == generation else {
            return false
        }
        return state.matchesExactly(expectedObjectKeys: expectedObjectKeys)
    }

    func clearUploadCompletionState(
        scanId: String,
        generation: UUID?
    ) {
        guard let state = uploadCompletionStates[scanId],
              state.generation == generation else {
            return
        }
        uploadCompletionStates[scanId] = nil
    }

    /// Returns the shared queue actor, creating it if the container changed or the actor
    /// has not yet been created. In production the container is a process-lifetime singleton,
    /// so this is effectively a one-time allocation. In tests each test suite creates an
    /// in-memory container, and the identity check prevents returning a stale actor backed
    /// by a previous test's already-deallocated store.
    func resolvedQueueDbActor(container: ModelContainer) -> BackgroundDatabaseActor {
        if let existing = _queueDbActor, _queueDbActorContainer === container { return existing }
        let actor = BackgroundDatabaseActor(modelContainer: container)
        _queueDbActor = actor
        _queueDbActorContainer = container
        return actor
    }

    /// Returns the shared profile actor, creating it once from the provided container.
    func resolvedProfileDbActor(container: ModelContainer) -> ProfileDatabaseActor {
        if let existing = _profileDbActor,
           _profileDbActorContainer === container {
            return existing
        }
        let actor = ProfileDatabaseActor(modelContainer: container)
        _profileDbActor = actor
        _profileDbActorContainer = container
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
        currentPathIsConstrained
    }

    /// Automatic queue recovery may use an eligible satisfied path only.
    ///
    /// Delayed probes and request preparation call this after every suspension
    /// so a satisfied-path transition into Low Data Mode cannot start another
    /// foreground status or inference request.
    var allowsAutomaticNetworkWorkOnCurrentPath: Bool {
        isOnline && !currentPathIsConstrained
    }

    var allowsLargeQueuedUploadsOnCurrentNetwork: Bool {
        !currentPathIsConstrained && !currentPathIsExpensive
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let newStatus = path.status == .satisfied
            let newIsConstrained = path.isConstrained
            let newIsExpensive = path.isExpensive
            Task { @MainActor [weak self] in
                guard let self else { return }
                let connectivityChanged = newStatus != self.isOnline
                let policyChanged =
                    newIsConstrained != self.currentPathIsConstrained
                    || newIsExpensive != self.currentPathIsExpensive
                guard connectivityChanged || policyChanged else { return }

                self.isOnline = newStatus
                self.currentPathIsConstrained = newIsConstrained
                self.currentPathIsExpensive = newIsExpensive
                MerianLog.data.debug(
                    "Network: \(newStatus ? "Online" : "Offline", privacy: .public) constrained=\(newIsConstrained, privacy: .public) expensive=\(newIsExpensive, privacy: .public)"
                )

                if newStatus {
                    // Cancel any pending debounce before rescheduling to prevent stacked sync
                    // calls when the OS path monitor fires multiple times in quick succession
                    // (e.g. WiFi → cellular → WiFi within a single second).
                    self.reconnectDebounceTask?.cancel()
                    self.reconnectDebounceTask = nil
                    guard !newIsConstrained else {
                        OfflineJobScheduler.shared.cancelScheduledWake(
                            using: self
                        )
                        return
                    }
                    self.reconnectDebounceTask = Task { [weak self] in
                        guard let self else { return }
                        // Debounce 3s to let the OS networking stack fully settle before syncing.
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        guard !Task.isCancelled else { return }
                        // Skip background sync on constrained networks (Low Data Mode).
                        if self.isCurrentNetworkConstrained { return }
                        await OfflineJobScheduler.shared.drainRunnableJobs(using: self)
                    }
                } else {
                    OfflineJobScheduler.shared.cancelScheduledWake(using: self)
                    self.releaseAllDeferredLiveUploads(reason: "connectivity_lost")
                    self.releaseAllForegroundInferenceClaims(reason: "connectivity_lost")
                    // Circuit-break active uploads immediately on connectivity loss.
                    self.reconnectDebounceTask?.cancel()
                    self.reconnectDebounceTask = nil
                    self.syncTask?.cancel()
                    self.syncTask = nil
                    if let uploadGeneration = self.syncGeneration {
                        self.uploadPreparationGenerations = self.uploadPreparationGenerations.filter {
                            $0.value != uploadGeneration
                        }
                    }
                    self.syncGeneration = nil
                    self.collectionSyncTask?.cancel()
                    // Cancel any pending backoff retry — it must not fire while offline.
                    self.retryBackoffTask?.cancel()
                    self.inferenceStatusProbeTasks.cancelAll()
                    self.serverIngestionPollTasks.cancelAll()
                    self.inferenceRetryTasks.cancelAll()
                    self.retiredInferenceGenerations.formUnion(
                        self.activeInferenceGenerations.values
                    )
                    self.activeInferenceGenerations.removeAll()
                    self.inferencePreparationGenerations.removeAll()
                    self.inferenceDispatchDates.removeAll()
                    self.isSyncing = false
                    self.isCollectionSyncing = false
                    SyncStateManager.shared.forceIdle()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }
}
