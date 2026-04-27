import Foundation

extension ExploreFeedViewModel {
    func presentNotifications() {
        HapticManager.shared.triggerSelectionPulse()
        isNotificationsSheetPresented = true
    }

    func dismissNotifications() {
        isNotificationsSheetPresented = false
    }

    func refreshUnreadNotificationCount() async {
        guard !isRefreshingUnreadNotificationCount else { return }

        isRefreshingUnreadNotificationCount = true
        defer { isRefreshingUnreadNotificationCount = false }

        do {
            unreadNotificationCount = try await MerianNetworkClient.shared.getUnreadExploreNotificationCount()
        } catch is CancellationError {
            // Absorb cancellation while the view is disappearing.
        } catch let error as URLError where error.code == .cancelled {
            // Absorb URLSession cancellation.
        } catch {
            // The badge should fail silently to avoid noisy Explore toasts from background refreshes.
        }
    }

    func preparePostForNavigation(postId: String) async throws -> ExplorePost {
        if posts.contains(where: { $0.id == postId }) {
            let refreshedPost = try await MerianNetworkClient.shared.getExplorePost(postId: postId)
            upsertPostForNotifications(refreshedPost)
            return refreshedPost
        }

        let loadedPost = try await MerianNetworkClient.shared.getExplorePost(postId: postId)
        upsertPostForNotifications(loadedPost)
        return loadedPost
    }

    func upsertPostForNotifications(_ post: ExplorePost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = post
        } else {
            posts.append(post)
        }
        reconcileActiveCommentsPost()
    }
}
