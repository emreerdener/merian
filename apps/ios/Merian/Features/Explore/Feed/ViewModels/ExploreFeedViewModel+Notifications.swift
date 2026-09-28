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
        let context = visibility.context
        guard let count = await dependencies.notifications
            .refreshUnreadCount(force), context == visibility.context else { return }
        unreadNotificationCount = count
    }

    func startUnreadNotificationUpdates() async {
        let context = visibility.context
        await dependencies.notifications.startUpdates { [weak self] count in
            guard let self, context == self.visibility.context else { return }
            self.unreadNotificationCount = count
        }
    }

    func stopUnreadNotificationUpdates() {
        dependencies.notifications.stopUpdates()
    }

    func preparePostForNavigation(postId: String) async throws -> ExplorePost {
        let context = visibility.context
        guard visibility.isVisible(postID: postId) else {
            throw MerianError.httpError(statusCode: 404, message: "Explore post is no longer available.")
        }
        let loadedPost = try await dependencies.interactions.loadPost(postId)
        guard !Task.isCancelled, visibility.context == context,
              visibility.isVisible(postID: postId) else { throw CancellationError() }
        upsertPost(loadedPost)
        return loadedPost
    }

    func upsertPostForNotifications(_ post: ExplorePost) {
        upsertPost(post)
    }
}
