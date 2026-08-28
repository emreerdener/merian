import Combine
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ScansShellViewModel {
    struct Dependencies {
        let events: AnyPublisher<AppEvent, Never>
        let currentSession: @MainActor () -> ScansShellSession
        let loadExploreMediaIncidents: @MainActor () async throws
            -> [ExploreMediaIncident]
        let dismissedOverviewSignature: @MainActor (_ ownerUserID: String)
            -> String?
        let dismissOverview: @MainActor (
            _ signature: String,
            _ ownerUserID: String
        ) -> Void
        let clearOverviewDismissal: @MainActor (_ ownerUserID: String) -> Void
        let now: @MainActor () -> Date
        let sleep: @MainActor (_ duration: Duration) async throws -> Void
        let updateAppIconBadge: @MainActor () -> Void

        @MainActor
        static var live: Self {
            let container = AppDIContainer.shared
            return Self(
                events: container.appEventPublisher.publisher,
                currentSession: {
                    let supabase = SupabaseManager.shared
                    return ScansShellSession(
                        isAuthenticated: supabase.isAuthenticated,
                        ownerUserID: supabase.currentUser?.id.uuidString
                            .lowercased()
                    )
                },
                loadExploreMediaIncidents: {
                    try await MerianNetworkClient.shared
                        .getExploreMediaIncidents()
                },
                dismissedOverviewSignature: { ownerUserID in
                    ExploreMediaOverviewPreferences.dismissedSignature(
                        ownerUserID: ownerUserID
                    )
                },
                dismissOverview: { signature, ownerUserID in
                    ExploreMediaOverviewPreferences.dismiss(
                        signature: signature,
                        ownerUserID: ownerUserID
                    )
                },
                clearOverviewDismissal: { ownerUserID in
                    ExploreMediaOverviewPreferences.clear(
                        ownerUserID: ownerUserID
                    )
                },
                now: Date.init,
                sleep: { duration in
                    try await Task.sleep(for: duration)
                },
                updateAppIconBadge: {
                    AppIconBadgeCoordinator.updateAppIconBadge()
                }
            )
        }
    }

    private(set) var queuedScans: [QueuedScanSnapshot] = []
    private(set) var exploreMediaIncidents: [ExploreMediaIncident] = []
    private(set) var isExploreMediaIncidentRefreshRunning = false
    private(set) var dismissedUnavailableMediaOverviewSignature: String?

    @ObservationIgnored let libraryEvents: AnyPublisher<AppEvent, Never>
    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private let dataStore: ScansShellDataStore
    @ObservationIgnored private let thumbnailPipeline: ScansThumbnailPipeline
    @ObservationIgnored private var didApplyInitialRecoveryFilter = false
    @ObservationIgnored private var lastQueuedPipelineKickAt = Date.distantPast
    @ObservationIgnored private var lastExploreMediaIncidentRefreshAt =
        Date.distantPast
    @ObservationIgnored private var needsTrailingExploreMediaIncidentRefresh =
        false
    @ObservationIgnored private var activeIncidentRefreshDriverID: UUID?

    init(
        dependencies: Dependencies? = nil,
        dataStore: ScansShellDataStore? = nil,
        thumbnailPipeline: ScansThumbnailPipeline? = nil
    ) {
        let resolvedDependencies = dependencies ?? .live
        self.dependencies = resolvedDependencies
        self.dataStore = dataStore ?? ScansShellDataStore()
        self.thumbnailPipeline = thumbnailPipeline
            ?? ScansThumbnailPipeline()
        libraryEvents = resolvedDependencies.events
    }

    var exploreMediaIncidentSummary: ExploreMediaIncidentSummary {
        ExploreMediaIncidentSummary(incidents: exploreMediaIncidents)
    }

    var currentExploreMediaOwnerID: String? {
        dependencies.currentSession().ownerUserID
    }

    var isUnavailableMediaOverviewVisible: Bool {
        guard let signature = exploreMediaIncidentSummary
            .overviewDismissalSignature else {
            return false
        }
        return dismissedUnavailableMediaOverviewSignature != signature
    }

    func applyInitialRecoveryFilterIfNeeded(
        recoveryContext: ExploreMediaRecoveryRouteContext?,
        searchManager: ScansManager
    ) {
        guard recoveryContext != nil,
              !didApplyInitialRecoveryFilter else { return }
        didApplyInitialRecoveryFilter = true

        var updatedFilters = searchManager.filters
        updatedFilters.explorePostFilters.insert(.unavailableMedia)
        searchManager.filters = updatedFilters
    }

    func synchronizeUnavailableMediaOverviewPreference() {
        guard let ownerUserID = currentExploreMediaOwnerID else {
            dismissedUnavailableMediaOverviewSignature = nil
            return
        }

        dismissedUnavailableMediaOverviewSignature = dependencies
            .dismissedOverviewSignature(ownerUserID)
    }

    func dismissUnavailableMediaOverview() {
        guard let ownerUserID = currentExploreMediaOwnerID,
              let signature = exploreMediaIncidentSummary
                .overviewDismissalSignature else {
            return
        }

        dependencies.dismissOverview(signature, ownerUserID)
        dismissedUnavailableMediaOverviewSignature = signature
    }

    func resetExploreMediaIncidentRefreshThrottle() {
        lastExploreMediaIncidentRefreshAt = .distantPast
    }

    func exploreMediaIncidentRefreshID(
        recoveryContext: ExploreMediaRecoveryRouteContext?,
        isOnline: Bool,
        scenePhaseKey: String
    ) -> String {
        let ownerUserID = currentExploreMediaOwnerID ?? "guest"
        let recoveryOwnerID = recoveryContext?.ownerUserId ?? "none"
        return "\(ownerUserID)|\(recoveryOwnerID)|\(isOnline)|\(scenePhaseKey)"
    }

    func refreshExploreMediaIncidents(
        recoveryContext: ExploreMediaRecoveryRouteContext?,
        searchManager: ScansManager,
        isOnline: @escaping @MainActor () -> Bool
    ) async {
        let initialSession = dependencies.currentSession()
        guard isOnline(),
              initialSession.isAuthenticated else {
            resetExploreMediaIncidentState()
            needsTrailingExploreMediaIncidentRefresh = false
            return
        }

        if activeIncidentRefreshDriverID != nil {
            needsTrailingExploreMediaIncidentRefresh = true
            return
        }

        let driverID = UUID()
        activeIncidentRefreshDriverID = driverID
        isExploreMediaIncidentRefreshRunning = true
        defer {
            if activeIncidentRefreshDriverID == driverID {
                activeIncidentRefreshDriverID = nil
                isExploreMediaIncidentRefreshRunning = false

                if needsTrailingExploreMediaIncidentRefresh,
                   isOnline(),
                   dependencies.currentSession().isAuthenticated {
                    Task { @MainActor [weak self] in
                        await self?.refreshExploreMediaIncidents(
                            recoveryContext: recoveryContext,
                            searchManager: searchManager,
                            isOnline: isOnline
                        )
                    }
                }
            }
        }

        repeat {
            needsTrailingExploreMediaIncidentRefresh = false

            let elapsed = dependencies.now().timeIntervalSince(
                lastExploreMediaIncidentRefreshAt
            )
            let coalescingDelay = max(0, 5 - elapsed)
            if coalescingDelay > 0 {
                do {
                    try await dependencies.sleep(.seconds(coalescingDelay))
                } catch {
                    return
                }
            }
            needsTrailingExploreMediaIncidentRefresh = false

            guard !Task.isCancelled else { return }
            let expectedSession = dependencies.currentSession()
            guard isOnline(),
                  expectedSession.isAuthenticated,
                  let expectedOwnerID = expectedSession.ownerUserID else {
                resetExploreMediaIncidentState()
                return
            }
            if let recoveryContext,
               recoveryContext.ownerUserId != expectedOwnerID {
                resetExploreMediaIncidentState()
                return
            }
            lastExploreMediaIncidentRefreshAt = dependencies.now()

            do {
                let incidents = try await dependencies
                    .loadExploreMediaIncidents()
                guard !Task.isCancelled else { return }
                guard isOnline(),
                      dependencies.currentSession() == expectedSession else {
                    resetExploreMediaIncidentState()
                    return
                }

                exploreMediaIncidents = incidents
                clearUnavailableMediaFilterIfResolved(
                    incidents: incidents,
                    searchManager: searchManager
                )
                clearUnavailableMediaOverviewDismissalIfResolved(
                    incidents: incidents,
                    ownerUserID: expectedOwnerID
                )
                MerianLog.network.debug(
                    "Loaded \(incidents.count, privacy: .public) active Explore media recovery incident(s)."
                )
            } catch {
                guard !Task.isCancelled else { return }
                MerianLog.network.error(
                    "ScansShellViewModel: failed to refresh Explore media incidents: \(error.localizedDescription, privacy: .private)"
                )
            }
        } while needsTrailingExploreMediaIncidentRefresh && !Task.isCancelled
    }

    func refreshQueuedScans(in modelContainer: ModelContainer) {
        let result = dataStore.queuedSnapshots(in: modelContainer)
        guard queuedScans != result.snapshots else { return }

        MerianLog.data.debug(
            "ScansShellViewModel.refreshQueuedScans: changed queued=\(result.fetchedCount, privacy: .public) visible=\(result.snapshots.count, privacy: .public) completedMatches=\(result.completedCount, privacy: .public) states=\(result.stateSummary, privacy: .public) visibleIds=\(result.visibleIDSummary, privacy: .private)"
        )
        queuedScans = result.snapshots
    }

    func syncStateFromStore(
        searchManager: ScansManager,
        modelContext: ModelContext
    ) {
        let records = dataStore.biologicalRecords(in: modelContext)
        guard scanListSignature(records)
            != scanListSignature(searchManager.allScans) else { return }

        MerianLog.data.debug(
            "ScansShellViewModel.syncStateFromStore: changed records=\(records.count, privacy: .public)"
        )
        searchManager.allScans = records
        searchManager.performSearch(query: searchManager.searchQuery)
    }

    func selectedRecords(
        searchManager: ScansManager,
        modelContext: ModelContext
    ) -> [LocalScanRecord] {
        dataStore.selectedRecords(
            ids: searchManager.selectedScans,
            limit: searchManager.maxBatchSelectionLimit,
            in: modelContext
        )
    }

    func deleteSelectedRecords(
        searchManager: ScansManager,
        modelContext: ModelContext
    ) {
        guard !searchManager.isDownloading else { return }
        let records = selectedRecords(
            searchManager: searchManager,
            modelContext: modelContext
        )
        dataStore.delete(records: records, in: modelContext)
        searchManager.exitSelectionMode()
    }

    func refreshThumbnailPipeline(
        records: [LocalScanRecord],
        maxDimension: Int,
        modelContainer: ModelContainer,
        isOnline: Bool
    ) {
        thumbnailPipeline.refresh(
            records: records,
            maxDimension: maxDimension,
            modelContainer: modelContainer,
            isOnline: isOnline
        )
    }

    func queuedRefreshTaskID(
        offlineQueueManager: OfflineQueueManager
    ) -> String {
        let queueIdentity = queuedScans.map {
            [
                $0.id,
                String($0.queueState.rawValue),
                String($0.queueNeedsAttention),
                $0.queueNextRetryAt.map {
                    String($0.timeIntervalSinceReferenceDate)
                } ?? "none"
            ].joined(separator: ":")
        }
        .sorted()
        .joined(separator: "|")
        let forcedLargeUploadIdentity = offlineQueueManager
            .userRequestedLargeUploadScanIds
            .sorted()
            .joined(separator: ",")
        return [
            queueIdentity,
            "online:\(offlineQueueManager.isOnline)",
            "constrained:\(offlineQueueManager.isCurrentNetworkConstrained)",
            "large:\(offlineQueueManager.allowsLargeQueuedUploadsOnCurrentNetwork)",
            "forced:\(forcedLargeUploadIdentity)"
        ].joined(separator: "#")
    }

    func hasAutomaticQueuedRecoveryWork(
        offlineQueueManager: OfflineQueueManager
    ) -> Bool {
        queuedScans.contains { queuedScan in
            queuedScan.isAutomaticRecoveryEligibleForCurrentNetwork(
                isOnline: offlineQueueManager.isOnline,
                isConstrained:
                    offlineQueueManager.isCurrentNetworkConstrained,
                allowsVideoUploads:
                    offlineQueueManager
                        .allowsLargeQueuedUploadsOnCurrentNetwork,
                isForcedVideoUpload:
                    offlineQueueManager.userRequestedLargeUploadScanIds
                        .contains(queuedScan.id)
            )
        }
    }

    func refreshQueuedScansUntilCancelled(
        modelContainer: ModelContainer,
        offlineQueueManager: OfflineQueueManager
    ) async {
        guard hasAutomaticQueuedRecoveryWork(
            offlineQueueManager: offlineQueueManager
        ) else { return }

        while !Task.isCancelled {
            try? await dependencies.sleep(.milliseconds(1_500))
            guard !Task.isCancelled else { return }
            refreshQueuedScans(in: modelContainer)
            guard hasAutomaticQueuedRecoveryWork(
                offlineQueueManager: offlineQueueManager
            ) else { return }
        }
    }

    func kickQueuedScanPipelineIfNeeded(
        reason: String,
        offlineQueueManager: OfflineQueueManager
    ) {
        guard hasAutomaticQueuedRecoveryWork(
            offlineQueueManager: offlineQueueManager
        ) else { return }

        let now = dependencies.now()
        guard now.timeIntervalSince(lastQueuedPipelineKickAt) >= 2 else {
            return
        }

        lastQueuedPipelineKickAt = now
        MerianLog.data.debug(
            "ScansShellViewModel.kickQueuedScanPipeline: kicking reason=\(reason, privacy: .public)"
        )
        offlineQueueManager.syncPendingScans()
        offlineQueueManager.replayInferenceForUploadedScans()
    }

    func clearUnseenScanBadge(in appSettings: AppSettings) {
        appSettings.hasUnseenScan = false
        dependencies.updateAppIconBadge()
    }

    private func resetExploreMediaIncidentState() {
        exploreMediaIncidents = []
        lastExploreMediaIncidentRefreshAt = .distantPast
    }

    private func clearUnavailableMediaFilterIfResolved(
        incidents: [ExploreMediaIncident],
        searchManager: ScansManager
    ) {
        guard incidents.isEmpty,
              searchManager.filters.explorePostFilters.contains(
                  .unavailableMedia
              ) else {
            return
        }

        var updatedFilters = searchManager.filters
        updatedFilters.explorePostFilters.remove(.unavailableMedia)
        searchManager.filters = updatedFilters
    }

    private func clearUnavailableMediaOverviewDismissalIfResolved(
        incidents: [ExploreMediaIncident],
        ownerUserID: String
    ) {
        guard incidents.isEmpty else { return }
        dependencies.clearOverviewDismissal(ownerUserID)
        dismissedUnavailableMediaOverviewSignature = nil
    }

    private func scanListSignature(
        _ records: [LocalScanRecord]
    ) -> [String] {
        records.map { record in
            "\(record.id)|\(record.timestamp.timeIntervalSince1970)|\(record.hasBeenViewed)"
        }
    }
}
