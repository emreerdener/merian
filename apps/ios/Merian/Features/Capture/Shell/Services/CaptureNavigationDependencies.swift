import Foundation

struct CaptureNavigationDependencies {
    let loadBadgeSnapshot: @MainActor @Sendable (
        _ lastSeenSharedAt: String
    ) async -> CaptureNavigationBadgeSnapshot
    let setHasUnseenExplorePost: @MainActor @Sendable (Bool) -> Void
    let performRouteFeedback: @MainActor @Sendable () -> Void

    @MainActor
    static func live(diContainer: AppDIContainer) -> Self {
        Self(
            loadBadgeSnapshot: { lastSeenSharedAt in
                async let recentPosts: [ExplorePost]? =
                    CaptureNavigationDependencies.loadRecentPosts()
                async let unreadCount = AppIconBadgeCoordinator
                    .refreshExploreUnreadNotificationCount()

                let (posts, count) = await (recentPosts, unreadCount)
                return CaptureNavigationBadgeSnapshot(
                    hasUnseenExternalPost: posts.map {
                        ExploreBadgePolicy.hasUnseenExternalPost(
                            in: $0,
                            lastSeenSharedAt: lastSeenSharedAt
                        )
                    } ?? false,
                    unreadNotificationCount: count
                )
            },
            setHasUnseenExplorePost: { hasUnseenPost in
                diContainer.appSettings.hasUnseenExplorePost = hasUnseenPost
            },
            performRouteFeedback: {
                diContainer.hapticManager.triggerSheetSpring()
            }
        )
    }

    @MainActor
    private static func loadRecentPosts() async -> [ExplorePost]? {
        do {
            return try await MerianNetworkClient.shared.getExploreFeed(limit: 20)
        } catch {
            MerianLog.network.debug(
                "Failed to fetch latest post for badge: \(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
    }
}
