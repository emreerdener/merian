import Foundation
import Observation

@MainActor
@Observable
final class CaptureNavigationViewModel {
    private(set) var hasUnreadExploreNotifications = false

    @ObservationIgnored
    private let dependencies: CaptureNavigationDependencies
    @ObservationIgnored
    private var refreshGeneration = UUID()

    init(dependencies: CaptureNavigationDependencies) {
        self.dependencies = dependencies
    }

    func refreshBadges(lastSeenSharedAt: String) async {
        let generation = UUID()
        refreshGeneration = generation

        let snapshot = await dependencies.loadBadgeSnapshot(lastSeenSharedAt)
        guard !Task.isCancelled, refreshGeneration == generation else { return }

        if let unreadNotificationCount = snapshot.unreadNotificationCount {
            hasUnreadExploreNotifications = unreadNotificationCount > 0
        }
        dependencies.setHasUnseenExplorePost(
            snapshot.hasUnseenExternalPost
        )
    }

    func invalidateRefresh() {
        refreshGeneration = UUID()
    }

    func performRouteFeedback() {
        dependencies.performRouteFeedback()
    }
}
