import Observation
import SwiftData

@MainActor
@Observable
final class AchievementDetailViewModel {
    private(set) var detail: AchievementDetailPayload?
    private(set) var isLoading = true

    private let dependencies: AchievementDetailDependencies
    private var loadGeneration = 0

    init(dependencies: AchievementDetailDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func resolvedAward(fallback award: AwardPayload) -> AwardPayload {
        detail?.award ?? award
    }

    var contributions: [AchievementContribution] {
        detail?.contributions ?? []
    }

    @discardableResult
    func load(
        award: AwardPayload,
        modelContainer: ModelContainer,
        backgroundReload: Bool = false
    ) async -> AwardPayload? {
        loadGeneration += 1
        let generation = loadGeneration
        if !backgroundReload {
            isLoading = true
        }
        defer {
            if loadGeneration == generation {
                isLoading = false
            }
        }

        let resolvedDetail = await dependencies.loadDetail(
            award.type,
            modelContainer
        )
        guard canApply(generation) else { return nil }

        detail = resolvedDetail
        guard !backgroundReload else { return nil }

        let resolvedAward = resolvedDetail?.award ?? award
        dependencies.trackDetailOpened(
            resolvedAward.type.rawValue,
            resolvedAward.isCompleted ? "completed" : "in_progress"
        )
        return resolvedAward
    }

    func openGoalDestination(_ destination: CaptureGoalDestination) {
        dependencies.openGoalDestination(destination)
    }

    func insightRoute(
        scanID: String,
        modelContext: ModelContext,
        tracksContributionFor award: AwardPayload? = nil
    ) -> ScanInsightRoute? {
        guard let route = dependencies.resolveScanRoute(scanID, modelContext)
        else {
            return nil
        }
        if let award {
            dependencies.trackContributionOpened(award.type.rawValue)
        }
        return route
    }

    func selectionFeedback() {
        dependencies.selectionFeedback()
    }

    func errorFeedback() {
        dependencies.errorFeedback()
    }

    private func canApply(_ generation: Int) -> Bool {
        !Task.isCancelled && loadGeneration == generation
    }
}
