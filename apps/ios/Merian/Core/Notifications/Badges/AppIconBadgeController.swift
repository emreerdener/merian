import Foundation

@MainActor
final class AppIconBadgeController {
    private struct ActiveRefresh {
        let id: UUID
        let task: Task<Int?, Never>
    }

    private let dependencies: AppIconBadgeDependencies
    private var activeRefresh: ActiveRefresh?
    private var lastRefreshAt: Date?
    private var stateGeneration: UInt = 0

    init(dependencies: AppIconBadgeDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    var exploreUnreadNotificationCount: Int {
        AppIconBadgePolicy.normalizedUnreadCount(
            dependencies.readExploreUnreadCount()
        )
    }

    func setExploreUnreadNotificationCount(_ count: Int) {
        invalidateRefresh()
        commitExploreUnreadNotificationCount(count)
    }

    func clearExploreUnreadNotificationCount() {
        setExploreUnreadNotificationCount(0)
    }

    func refreshExploreUnreadNotificationCount(
        force: Bool,
        loadUnreadCount: @escaping @MainActor () async throws -> Int
    ) async -> Int? {
        if let activeRefresh {
            return await activeRefresh.task.value
        }

        if AppIconBadgePolicy.canReuseRefresh(
            force: force,
            lastRefreshAt: lastRefreshAt,
            now: dependencies.now()
        ) {
            return exploreUnreadNotificationCount
        }

        let refreshID = UUID()
        let generation = stateGeneration
        let reportRefreshFailure = dependencies.reportRefreshFailure
        let task = Task<Int?, Never> { @MainActor [weak self] in
            do {
                let count = try await loadUnreadCount()
                guard let self,
                      !Task.isCancelled,
                      generation == stateGeneration else { return nil }
                let normalized = AppIconBadgePolicy.normalizedUnreadCount(
                    count
                )
                commitExploreUnreadNotificationCount(normalized)
                lastRefreshAt = dependencies.now()
                return normalized
            } catch is CancellationError {
                return nil
            } catch let error as URLError where error.code == .cancelled {
                return nil
            } catch {
                guard let self,
                      !Task.isCancelled,
                      generation == stateGeneration else { return nil }
                reportRefreshFailure(error)
                return nil
            }
        }
        activeRefresh = ActiveRefresh(id: refreshID, task: task)

        let count = await task.value
        if activeRefresh?.id == refreshID {
            activeRefresh = nil
        }
        return count
    }

    func resetAccountState() {
        invalidateRefresh()
        lastRefreshAt = nil
        dependencies.removeExploreUnreadCount()
        updateAppIconBadge()
    }

    func updateAppIconBadge() {
        dependencies.setBadgeCount(
            AppIconBadgePolicy.totalCount(
                hasUnseenScan: dependencies.hasUnseenScan(),
                exploreUnreadCount: exploreUnreadNotificationCount
            )
        )
    }

    private func invalidateRefresh() {
        stateGeneration &+= 1
        activeRefresh?.task.cancel()
        activeRefresh = nil
    }

    private func commitExploreUnreadNotificationCount(_ count: Int) {
        dependencies.writeExploreUnreadCount(
            AppIconBadgePolicy.normalizedUnreadCount(count)
        )
        updateAppIconBadge()
    }
}
