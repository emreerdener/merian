import Foundation
import Network
import SwiftData

@MainActor
final class OfflineJobScheduler {
    static let shared = OfflineJobScheduler()

    /// The drain effects, separated from scheduling policy so
    /// tests can exercise their ordering without starting live queue work.
    struct DrainOperations {
        var syncLibraryDetails: @MainActor (OfflineQueueManager) async -> Void = { _ in }
        var syncPublications: @MainActor (OfflineQueueManager) async -> Void = { _ in }
        var syncIdentificationReviews: @MainActor (OfflineQueueManager) async -> Void = { _ in }
        let reconcileFunding: @MainActor (OfflineQueueManager) async -> Void
        let syncPendingScans: @MainActor (OfflineQueueManager) -> Void
        let replayInference: @MainActor (OfflineQueueManager) -> Void
        let replayFieldTripProgress: @MainActor (OfflineQueueManager) async -> Void
        let syncPendingDeletions: @MainActor (OfflineQueueManager) async -> Void
        let syncCollections: @MainActor (OfflineQueueManager) -> Void

        fileprivate static let live = DrainOperations(
            syncLibraryDetails: { manager in
                if let context = manager.modelContext {
                    await LibraryDetailsSyncService.drain(context: context, manager: .shared)
                }
            },
            syncPublications: { await $0.syncObservationPublications() },
            syncIdentificationReviews: { await $0.syncPendingIdentificationReviews() },
            reconcileFunding: { await $0.reconcileDeferredFundingReservations() },
            syncPendingScans: { $0.syncPendingScans() },
            replayInference: { $0.replayInferenceForUploadedScans() },
            replayFieldTripProgress: { await $0.replayPendingFieldTripProgress() },
            syncPendingDeletions: { await $0.syncPendingDeletions() },
            syncCollections: { $0.syncCollectionsIfPending() }
        )
    }

    private static let minimumWakeDelay: TimeInterval = 1
    private static let databaseReadRetryDelay: TimeInterval = 5

    private let drainOperations: DrainOperations
    private let deletionAccountID: @MainActor () -> UUID?
    private weak var scheduledManager: OfflineQueueManager?
    private var scheduledSourceDate: Date?
    private var scheduledWakeToken: UUID?
    private var scheduledWakeTask: Task<Void, Never>?
    private weak var libraryRetryManager: OfflineQueueManager?
    private var libraryRetryDate: Date?
    private weak var publicationRetryManager: OfflineQueueManager?
    private var publicationRetryDate: Date?
    private var publicationRetryOwner: UUID?

    /// Actual in-process wake time. Kept internal so regression tests can prove
    /// a persisted future retry was restored instead of merely displayed.
    private(set) var scheduledWakeDate: Date?

    private init() {
        drainOperations = .live
        deletionAccountID = { CloudDeletionAccountWork.currentAccountID }
    }

    init(drainOperations: DrainOperations,
         deletionAccountID: @escaping @MainActor () -> UUID? = { CloudDeletionAccountWork.currentAccountID }) {
        self.drainOperations = drainOperations
        self.deletionAccountID = deletionAccountID
    }

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
        await drainOperations.syncLibraryDetails(manager)
        await drainOperations.reconcileFunding(manager)
        drainOperations.syncPendingScans(manager)
        await drainOperations.syncIdentificationReviews(manager)
        await drainOperations.syncPublications(manager)
        drainOperations.replayInference(manager)
        await drainOperations.replayFieldTripProgress(manager)
        await drainOperations.syncPendingDeletions(manager)
        drainOperations.syncCollections(manager)

        // The upload and inference drains intentionally dispatch their network
        // work without blocking this coordinator. Yield once so their atomic
        // claims can clear a due retry date before selecting the next wake.
        await Task.yield()
        scheduleNextPersistedWake(using: manager)
    }

    /// Persistence can fail while acknowledging an RPC, so retry cannot depend
    /// on saving another deadline. The immutable pending job survives restart;
    /// this fallback supplies a bounded wake while the process remains alive.
    func scheduleLibraryDetailsRetry(using manager: OfflineQueueManager, now: Date = Date()) {
        libraryRetryManager = manager
        libraryRetryDate = now.addingTimeInterval(Self.databaseReadRetryDelay)
        scheduleNextPersistedWake(using: manager, now: now)
    }

    /// Called only after the details drain acquired its exact-owner lease.
    /// Offline or identity-fenced attempts must retain the recovery wake.
    func libraryDetailsDrainDidStart(using manager: OfflineQueueManager) {
        guard libraryRetryManager === manager else { return }
        libraryRetryDate = nil
        libraryRetryManager = nil
    }

    func schedulePublicationRetry(using manager: OfflineQueueManager, now: Date = Date()) {
        publicationRetryManager = manager
        publicationRetryOwner = deletionAccountID()
        publicationRetryDate = now.addingTimeInterval(Self.databaseReadRetryDelay)
        scheduleNextPersistedWake(using: manager, now: now)
    }

    func publicationDrainDidStart(using manager: OfflineQueueManager) {
        guard publicationRetryManager === manager, publicationRetryOwner == deletionAccountID() else { return }
        publicationRetryDate = nil; publicationRetryManager = nil
        publicationRetryOwner = nil
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
        let libraryDeadline = libraryRetryManager === manager ? libraryRetryDate : nil
        let publicationDeadline = publicationRetryManager === manager && publicationRetryOwner != nil &&
            publicationRetryOwner == deletionAccountID() &&
            !manager.publicationDeliveryOwner.isRunning ? publicationRetryDate : nil
        guard let sourceDate = [nextPersistedWakeDate(using: manager), libraryDeadline, publicationDeadline].compactMap({ $0 }).min() else {
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
            (!scan.permitsOrdinaryInference || scan.queueNeedsAttention ||
                scan.scanStateRaw >= firstNonRunnableRaw)
                ? OfflineQueueManager.scanIngestionJobId(scanId: scan.id)
                : nil
        })
        var candidates: [Date] = scans.compactMap { scan -> Date? in
            guard scan.permitsOrdinaryInference, !scan.queueNeedsAttention,
                  scan.scanStateRaw < firstNonRunnableRaw else {
                return nil
            }
            return scan.queueNextRetryAt
        }

        let ordinaryScanJobIDs = Set(scans.filter(\.permitsOrdinaryInference).map {
            OfflineQueueManager.scanIngestionJobId(scanId: $0.id)
        })
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
        let deletionOwner = deletionAccountID()
        if let owner = deletionOwner, !manager.publicationDeliveryOwner.isRunning {
            do {
                let retryFloor = publicationRetryManager === manager && publicationRetryOwner == owner ? publicationRetryDate : nil
                candidates.append(contentsOf: try ObservationPublicationPersistence.candidates(container: context.container, ownerID: owner).map { candidate in
                    retryFloor.map { max($0, candidate.1) } ?? candidate.1
                })
            } catch { candidates.append(Date().addingTimeInterval(Self.databaseReadRetryDelay)) }
        }
        candidates.append(contentsOf: jobs.compactMap { job -> Date? in
            // Publication deadlines above require validated owner-bound envelopes.
            // Unknown kinds cannot be drained by this binary.
            guard let kind = OfflineJobKind(rawValue: job.kindRaw),
                  kind != .observationPublicationSync, kind != .observationReanalysisSync,
                  kind != .future || job.id.hasPrefix("library-details:") else { return nil }
            // A qualified, damaged or absent queue row cannot feed a legacy wake loop.
            if kind == .scanIngestion, !ordinaryScanJobIDs.contains(job.id) { return nil }
            // Enrollment recovery is explicit, including damaged/unknown hold metadata.
            guard !job.id.hasPrefix(ObservationHistoryEnrollmentIntent.prefix),
                  !job.id.hasPrefix(ObservationHistorySelectionIntent.prefix) else { return nil }
            // Discovery cannot advance while the deletion drain owns its
            // single-flight latch. Keep its durable deadline for restart, but
            // avoid re-entering every sync service once per second during a
            // slow network batch. The drain rearms it when releasing the latch.
            if job.kind == .cloudDeletion {
                guard let deletionOwner else { return nil }
                if job.id == OfflineQueueManager.cloudDeletionDiscoveryJobID {
                    guard !manager.isCloudDeletionSyncing else { return nil }
                } else {
                    guard !OfflineQueueManager.cloudDeletionIsHeld(job),
                          let scanID = job.subjectId,
                          let intent = CloudDeletionIntent.restoring(job.metadataJSON, scanID: scanID),
                          intent.requestingAccountID == deletionOwner else { return nil }
                }
            }
            guard activeStatuses.contains(job.statusRaw),
                  !blockedScanJobIds.contains(job.id) else {
                return nil
            }
            return job.nextRunAt
        })

        return candidates.min()
    }
}
