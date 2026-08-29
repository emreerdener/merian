import Combine
import Observation
import SwiftData

@MainActor
@Observable
final class ProfileTabViewModel {
    private(set) var uniqueSpeciesCount = 0
    private(set) var currentStreak = 0
    private(set) var totalCaptures = 0
    private(set) var heatmapData: ProfileHeatmapData?
    private(set) var awards: [AwardPayload] = []
    private(set) var refreshToken = UUID()

    private let dependencies: ProfileTabDependencies
    private var refreshGeneration = 0

    init(dependencies: ProfileTabDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    var appEvents: AnyPublisher<AppEvent, Never> {
        dependencies.appEvents
    }

    func refreshKey(
        isAuthenticated: Bool,
        accountID: String?
    ) -> ProfileStatsRefreshKey {
        ProfileStatsRefreshKey(
            refreshToken: refreshToken,
            isAuthenticated: isAuthenticated,
            accountId: accountID
        )
    }

    func handle(event: AppEvent, fieldTripsEnabled: Bool) {
        switch event {
        case .scanLibraryChanged:
            invalidateStats()
        case .fieldTripProgressInvalidated,
             .fieldTripChallengeProgressInvalidated,
             .captureGoalContextInvalidated(.fieldTrip):
            if fieldTripsEnabled {
                invalidateStats()
            }
        default:
            break
        }
    }

    func refresh(
        key: ProfileStatsRefreshKey,
        modelContainer: ModelContainer,
        fieldTripsEnabled: Bool
    ) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let stats = await dependencies.calculateStats(modelContainer)
        guard canApply(generation: generation, key: key) else { return }

        uniqueSpeciesCount = stats.speciesCount
        currentStreak = stats.streak
        totalCaptures = stats.heatmap.totalCaptures
        heatmapData = stats.heatmap

        guard fieldTripsEnabled,
              key.isAuthenticated,
              let accountID = key.accountId else {
            awards = stats.awards
            return
        }

        let cachedProgress = dependencies.loadCachedFieldTripProgress(accountID)
        awards = stats.awards.mergingFirstFieldTripAchievement(cachedProgress)

        do {
            guard let refreshedProgress = try await dependencies
                .refreshFieldTripProgress() else { return }
            guard canApply(generation: generation, key: key) else { return }

            dependencies.saveFieldTripProgress(
                refreshedProgress,
                accountID
            )
            awards = stats.awards.mergingFirstFieldTripAchievement(
                refreshedProgress
            )
        } catch is CancellationError {
            return
        } catch {
            guard canApply(generation: generation, key: key) else { return }
            dependencies.logProgressRefreshFailure(error)
        }
    }

    func visibleAwards(fieldTripsEnabled: Bool) -> [AwardPayload] {
        guard !fieldTripsEnabled else { return awards }
        return awards.filter { $0.type != .firstFieldTrip }
    }

    func completedAwardCount(fieldTripsEnabled: Bool) -> Int {
        visibleAwards(fieldTripsEnabled: fieldTripsEnabled)
            .filter(\.isCompleted)
            .count
    }

#if DEBUG
    func setDebugSpeciesCount(_ count: Int) {
        uniqueSpeciesCount = count
    }
#endif

    func openFieldTrips() {
        dependencies.openFieldTrips()
    }

    func selectionFeedback() {
        dependencies.selectionFeedback()
    }

    func errorFeedback() {
        dependencies.errorFeedback()
    }

    func insightRoute(
        scanID: String,
        modelContext: ModelContext
    ) -> ScanInsightRoute? {
        dependencies.resolveScanRoute(scanID, modelContext)
    }

    private func invalidateStats() {
        refreshGeneration += 1
        refreshToken = UUID()
    }

    private func canApply(
        generation: Int,
        key: ProfileStatsRefreshKey
    ) -> Bool {
        !Task.isCancelled &&
            refreshGeneration == generation &&
            refreshToken == key.refreshToken
    }
}
