import Foundation
import Network
import SwiftData
import Observation
import os

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
    @ObservationIgnored
    lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.merian.OfflineSyncBackground")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
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
    /// SwiftData context injected at app startup via `ScanRepository.configure(with:)`.
    var modelContext: ModelContext?

    /// Active upload batch task. Cancelled immediately on connectivity loss.
    var syncTask: Task<Void, Never>?

    /// In-memory counter tracking consecutive transient upload failures per scan ID.
    /// Resets on app restart — a fresh process always gets a clean slate of retries.
    @ObservationIgnored var uploadRetryCount: [String: Int] = [:]

    /// Maximum consecutive transient errors before a scan is tombstoned.
    static let maxUploadRetries = 3

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
                    // Debounce 1s to let the OS networking stack fully settle before syncing.
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    self?.syncPendingScans()
                    await self?.syncPendingDeletions()
                    self?.syncCollectionsIfPending()
                } else {
                    // Circuit-break active uploads immediately on connectivity loss.
                    self?.syncTask?.cancel()
                    self?.isSyncing = false
                    SyncStateManager.shared.completeSync()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }
}
