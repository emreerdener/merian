import Foundation
import Network
import SwiftData

@MainActor
final class OfflineJobScheduler {
    static let shared = OfflineJobScheduler()

    private static let minimumWakeDelay: TimeInterval = 1
    private static let databaseReadRetryDelay: TimeInterval = 5

    private weak var scheduledManager: OfflineQueueManager?
    private var scheduledSourceDate: Date?
    private var scheduledWakeToken: UUID?
    private var scheduledWakeTask: Task<Void, Never>?

    /// Actual in-process wake time. Kept internal so regression tests can prove
    /// a persisted future retry was restored instead of merely displayed.
    private(set) var scheduledWakeDate: Date?

    private init() {}

    func drainRunnableJobs(using manager: OfflineQueueManager) async {
        guard manager.isOnline,
              !manager.isCurrentNetworkConstrained else {
            cancelScheduledWake(using: manager)
            return
        }

        // Arm a future deadline before awaiting any other network drain. A
        // deletion backlog, for example, must not delay a scan retry that
        // becomes eligible while that drain is still in flight.
        scheduleNextPersistedWake(using: manager)
        await manager.reconcileDeferredFundingReservations()
        manager.syncPendingScans()
        manager.replayInferenceForUploadedScans()
        await manager.replayPendingFieldTripProgress()
        await manager.syncPendingDeletions()
        manager.syncCollectionsIfPending()

        // The upload and inference drains intentionally dispatch their network
        // work without blocking this coordinator. Yield once so their atomic
        // claims can clear a due retry date before selecting the next wake.
        await Task.yield()
        scheduleNextPersistedWake(using: manager)
    }

    /// Recreates the process-local timer from durable SwiftData dates.
    ///
    /// A retry timestamp is an eligibility boundary, not a timer. This bridge
    /// must run after foregrounding or reconnecting because Swift tasks do not
    /// survive process termination and may be cancelled on connectivity loss.
    func scheduleNextPersistedWake(
        using manager: OfflineQueueManager,
        now: Date = Date()
    ) {
        guard manager.isOnline,
              !manager.isCurrentNetworkConstrained else {
            cancelScheduledWake(using: manager)
            return
        }
        guard let sourceDate = nextPersistedWakeDate(using: manager) else {
            cancelScheduledWake(using: manager)
            return
        }

        if scheduledManager === manager,
           scheduledSourceDate == sourceDate,
           scheduledWakeTask != nil {
            return
        }

        cancelScheduledWake()
        let wakeDate = max(
            sourceDate,
            now.addingTimeInterval(Self.minimumWakeDelay)
        )
        let token = UUID()
        scheduledManager = manager
        scheduledSourceDate = sourceDate
        scheduledWakeDate = wakeDate
        scheduledWakeToken = token
        scheduledWakeTask = Task { @MainActor [weak self, weak manager] in
            guard let self, let manager else { return }
            do {
                try await Task.sleep(
                    for: .seconds(max(0, wakeDate.timeIntervalSinceNow))
                )
            } catch {
                return
            }
            guard self.scheduledWakeToken == token,
                  self.scheduledManager === manager else {
                return
            }

            self.scheduledWakeTask = nil
            self.scheduledWakeToken = nil
            self.scheduledSourceDate = nil
            self.scheduledWakeDate = nil
            self.scheduledManager = nil
            await self.drainRunnableJobs(using: manager)
        }

        MerianLog.data.debug(
            "OfflineJobScheduler: restored persisted wake in \(String(format: "%.1f", wakeDate.timeIntervalSince(now)), privacy: .public)s"
        )
    }

    func cancelScheduledWake(using manager: OfflineQueueManager? = nil) {
        if let manager, scheduledManager !== manager {
            return
        }
        scheduledWakeToken = nil
        scheduledWakeTask?.cancel()
        scheduledWakeTask = nil
        scheduledSourceDate = nil
        scheduledWakeDate = nil
        scheduledManager = nil
    }

    /// Returns the earliest active durable retry across scan ingestion and the
    /// generic offline-job bridge. Past dates remain past so the caller can
    /// schedule an immediate bounded wake rather than silently rolling them
    /// forward.
    func nextPersistedWakeDate(
        using manager: OfflineQueueManager
    ) -> Date? {
        guard let context = manager.modelContext else { return nil }
        // Queue transitions are also written by BackgroundDatabaseActor. Read
        // through a fresh context so a cached main-context fault cannot hide a
        // newly persisted retry date or retain one that an atomic claim cleared.
        let readContext = ModelContext(context.container)
        let firstNonRunnableRaw = ScanQueueState.externalImport.rawValue
        let scanDescriptor = FetchDescriptor<OfflineQueuedScan>()
        let scans: [OfflineQueuedScan]
        do {
            scans = try readContext.fetch(scanDescriptor)
        } catch {
            MerianLog.data.error(
                "OfflineJobScheduler: scan deadline read failed: \(error, privacy: .private)"
            )
            return Date().addingTimeInterval(Self.databaseReadRetryDelay)
        }
        let blockedScanJobIds = Set<String>(scans.compactMap { scan -> String? in
            (scan.queueNeedsAttention ||
                scan.scanStateRaw >= firstNonRunnableRaw)
                ? OfflineQueueManager.scanIngestionJobId(scanId: scan.id)
                : nil
        })
        var candidates: [Date] = scans.compactMap { scan -> Date? in
            guard !scan.queueNeedsAttention,
                  scan.scanStateRaw < firstNonRunnableRaw else {
                return nil
            }
            return scan.queueNextRetryAt
        }

        let jobDescriptor = FetchDescriptor<OfflineJobRecord>()
        let activeStatuses: Set<String> = [
            OfflineJobStatus.pending.rawValue,
            OfflineJobStatus.running.rawValue,
            OfflineJobStatus.waiting.rawValue
        ]
        let jobs: [OfflineJobRecord]
        do {
            jobs = try readContext.fetch(jobDescriptor)
        } catch {
            MerianLog.data.error(
                "OfflineJobScheduler: job deadline read failed: \(error, privacy: .private)"
            )
            candidates.append(
                Date().addingTimeInterval(Self.databaseReadRetryDelay)
            )
            return candidates.min()
        }
        candidates.append(contentsOf: jobs.compactMap { job -> Date? in
            guard activeStatuses.contains(job.statusRaw),
                  !blockedScanJobIds.contains(job.id) else {
                return nil
            }
            return job.nextRunAt
        })

        return candidates.min()
    }
}
