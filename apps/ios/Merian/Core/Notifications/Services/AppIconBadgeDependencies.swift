import Foundation

@MainActor
struct AppIconBadgeDependencies {
    let readExploreUnreadCount: @MainActor () -> Int
    let writeExploreUnreadCount: @MainActor (_ count: Int) -> Void
    let removeExploreUnreadCount: @MainActor () -> Void
    let hasUnseenScan: @MainActor () -> Bool
    let setBadgeCount: @MainActor (_ count: Int) -> Void
    let now: @MainActor () -> Date
    let reportRefreshFailure: @MainActor (_ error: any Error) -> Void

    static var live: Self {
        Self(
            readExploreUnreadCount: {
                UserDefaults.standard.integer(
                    forKey:
                    UserDefaultsKeys.exploreUnreadNotificationBadgeCount
                )
            },
            writeExploreUnreadCount: { count in
                UserDefaults.standard.set(
                    count,
                    forKey:
                    UserDefaultsKeys.exploreUnreadNotificationBadgeCount
                )
            },
            removeExploreUnreadCount: {
                UserDefaults.standard.removeObject(
                    forKey:
                    UserDefaultsKeys.exploreUnreadNotificationBadgeCount
                )
            },
            hasUnseenScan: { AppSettings.shared.hasUnseenScan },
            setBadgeCount: {
                PushNotificationManager.shared.setBadgeCount($0)
            },
            now: Date.init,
            reportRefreshFailure: { error in
                MerianLog.notifications.debug(
                    "Failed to refresh Explore app icon badge count: \(error.localizedDescription, privacy: .private)"
                )
            }
        )
    }

    static func loadUnreadCount() async throws -> Int {
        try await MerianNetworkClient.shared
            .getUnreadExploreNotificationCount()
    }
}
