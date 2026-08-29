import SwiftData

@MainActor
struct AchievementDetailDependencies {
    let loadDetail: @MainActor (
        _ type: AchievementType,
        _ modelContainer: ModelContainer
    ) async -> AchievementDetailPayload?
    let openGoalDestination: @MainActor (
        _ destination: CaptureGoalDestination
    ) -> Void
    let resolveScanRoute: @MainActor (
        _ scanID: String,
        _ modelContext: ModelContext
    ) -> ScanInsightRoute?
    let selectionFeedback: @MainActor () -> Void
    let errorFeedback: @MainActor () -> Void
    let trackDetailOpened: @MainActor (
        _ type: String,
        _ state: String
    ) -> Void
    let trackContributionOpened: @MainActor (_ type: String) -> Void

    static var live: Self {
        let container = AppDIContainer.shared
        return Self(
            loadDetail: { type, modelContainer in
                let actor = ProfileDatabaseActor(
                    modelContainer: modelContainer
                )
                return await actor.calculateAchievementDetail(for: type)
            },
            openGoalDestination: { destination in
                container.appRouteCoordinator.request(
                    .captureGoal(destination),
                    source: .internalUserAction
                )
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
            selectionFeedback: {
                container.hapticManager.triggerSelectionPulse()
            },
            errorFeedback: {
                container.hapticManager.triggerErrorThump()
            },
            trackDetailOpened: { type, state in
                AppTelemetry.trackAchievementDetailOpened(
                    type: type,
                    state: state
                )
            },
            trackContributionOpened: { type in
                AppTelemetry.trackAchievementContributionOpened(type: type)
            }
        )
    }
}
