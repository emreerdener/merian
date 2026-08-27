import Foundation

extension ExploreFeedViewModel {
    func presentNotifications() {
        dependencies.feedback.selection()
        isNotificationsSheetPresented = true
    }

    func dismissNotifications() {
        isNotificationsSheetPresented = false
    }

    func refreshUnreadNotificationCount(force: Bool = false) async {
        guard let count = await dependencies.notifications
            .refreshUnreadCount(force) else { return }
        unreadNotificationCount = count
    }

    func startUnreadNotificationUpdates() async {
        await dependencies.notifications.startUpdates { [weak self] count in
            self?.unreadNotificationCount = count
        }
    }

    func stopUnreadNotificationUpdates() {
        dependencies.notifications.stopUpdates()
    }

    func preparePostForNavigation(postId: String) async throws -> ExplorePost {
        if store.post(id: postId) != nil {
            let refreshedPost = try await dependencies.interactions.loadPost(postId)
            upsertPost(refreshedPost)
            return refreshedPost
        }

        let loadedPost = try await dependencies.interactions.loadPost(postId)
        upsertPost(loadedPost)
        return loadedPost
    }

    func upsertPostForNotifications(_ post: ExplorePost) {
        upsertPost(post)
    }
}
