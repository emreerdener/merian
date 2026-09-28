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
    @ObservationIgnored
    private var badgeOwnerID: UUID?

    init(dependencies: CaptureNavigationDependencies) {
        self.dependencies = dependencies
    }

    func refreshBadges(
        lastSeenSharedAt: String,
        userID: UUID? = nil,
        isAccountWorkAllowed: Bool = true
    ) async {
        let generation = UUID()
        refreshGeneration = generation
        guard !Task.isCancelled else { return }
        if badgeOwnerID != userID || !isAccountWorkAllowed {
            hasUnreadExploreNotifications = false
            dependencies.setHasUnseenExplorePost(false)
        }
        badgeOwnerID = userID
        guard isAccountWorkAllowed else { return }

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
