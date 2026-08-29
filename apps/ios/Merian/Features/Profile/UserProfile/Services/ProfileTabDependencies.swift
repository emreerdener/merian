import Combine
import SwiftData

@MainActor
struct ProfileTabDependencies {
    let calculateStats: @MainActor (
        _ modelContainer: ModelContainer
    ) async -> ProfileAllStatsPayload
    let loadCachedFieldTripProgress: @MainActor (
        _ accountID: String
    ) -> FirstFieldTripAchievementProgress?
    let refreshFieldTripProgress: @MainActor () async throws
        -> FirstFieldTripAchievementProgress?
    let saveFieldTripProgress: @MainActor (
        _ progress: FirstFieldTripAchievementProgress,
        _ accountID: String
    ) -> Void
    let appEvents: AnyPublisher<AppEvent, Never>
    let openFieldTrips: @MainActor () -> Void
    let selectionFeedback: @MainActor () -> Void
    let errorFeedback: @MainActor () -> Void
    let resolveScanRoute: @MainActor (
        _ scanID: String,
        _ modelContext: ModelContext
    ) -> ScanInsightRoute?
    let logProgressRefreshFailure: @MainActor (_ error: Error) -> Void

    static var live: Self {
        let container = AppDIContainer.shared
        return Self(
            calculateStats: { modelContainer in
                let actor = ProfileDatabaseActor(
                    modelContainer: modelContainer
                )
                return await actor.calculateAll()
            },
            loadCachedFieldTripProgress: { accountID in
                FirstFieldTripAchievementProgressStore.load(
                    accountId: accountID
                )
            },
            refreshFieldTripProgress: {
                try await MerianNetworkClient.shared
                    .getFirstFieldTripAchievementProgress()
            },
            saveFieldTripProgress: { progress, accountID in
                FirstFieldTripAchievementProgressStore.save(
                    progress,
                    accountId: accountID
                )
            },
            appEvents: container.appEventPublisher.publisher,
            openFieldTrips: {
                container.appRouteCoordinator.request(
                    .fieldTrips,
                    source: .internalUserAction
                )
            },
            selectionFeedback: {
                container.hapticManager.triggerSelectionPulse()
            },
            errorFeedback: {
                container.hapticManager.triggerErrorThump()
            },
            resolveScanRoute: { scanID, modelContext in
                var descriptor = FetchDescriptor<LocalScanRecord>(
                    predicate: #Predicate { $0.id == scanID }
                )
                descriptor.fetchLimit = 1
                guard let record = try? modelContext.fetch(descriptor).first
                else {
                    return nil
                }
                return ScanInsightRoute(scanId: record.id)
            },
            logProgressRefreshFailure: { error in
                MerianLog.network.debug(
                    "First Field trip achievement refresh failed: \(error, privacy: .private)"
                )
            }
        )
    }
}
