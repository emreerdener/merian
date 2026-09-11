@MainActor
enum AppIconBadgeCoordinator {
    private static let controller = AppIconBadgeController()

    static var exploreUnreadNotificationCount: Int {
        controller.exploreUnreadNotificationCount
    }

    static func setExploreUnreadNotificationCount(_ count: Int) {
        controller.setExploreUnreadNotificationCount(count)
    }

    static func clearExploreUnreadNotificationCount() {
        controller.clearExploreUnreadNotificationCount()
    }

    static func refreshExploreUnreadNotificationCount(
        force: Bool = false,
        loadUnreadCount: @escaping @MainActor () async throws -> Int =
            AppIconBadgeDependencies.loadUnreadCount
    ) async -> Int? {
        await controller.refreshExploreUnreadNotificationCount(
            force: force,
            loadUnreadCount: loadUnreadCount
        )
    }

    static func resetAccountState() {
        controller.resetAccountState()
    }

    static func updateAppIconBadge() {
        controller.updateAppIconBadge()
    }
}
