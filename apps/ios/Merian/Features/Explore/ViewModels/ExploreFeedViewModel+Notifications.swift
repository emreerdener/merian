import Foundation
import Supabase

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

    func startUnreadNotificationUpdates() async {
        await refreshUnreadNotificationCount()
        await startRealtimeUnreadNotificationUpdates()
    }

    func stopUnreadNotificationUpdates() {
        unreadNotificationListenerTask?.cancel()
        unreadNotificationListenerTask = nil

        guard let channel = unreadNotificationsChannel else { return }
        unreadNotificationsChannel = nil

        Task {
            await SupabaseManager.shared.client.removeChannel(channel)
        }
    }

    func preparePostForNavigation(postId: String) async throws -> ExplorePost {
        if store.post(id: postId) != nil {
            let refreshedPost = try await MerianNetworkClient.shared.getExplorePost(postId: postId)
            upsertPost(refreshedPost)
            return refreshedPost
        }

        let loadedPost = try await MerianNetworkClient.shared.getExplorePost(postId: postId)
        upsertPost(loadedPost)
        return loadedPost
    }

    func upsertPostForNotifications(_ post: ExplorePost) {
        upsertPost(post)
    }

    private func startRealtimeUnreadNotificationUpdates() async {
        guard unreadNotificationsChannel == nil, unreadNotificationListenerTask == nil else { return }
        guard let userId = await resolveExploreNotificationsUserId() else { return }

        let channel = SupabaseManager.shared.client.channel(
            "explore-notifications-\(userId)-\(UUID().uuidString)"
        )
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "explore_post_notifications",
            filter: .eq("user_id", value: userId)
        )

        do {
            try await channel.subscribeWithError()
            unreadNotificationsChannel = channel
            unreadNotificationListenerTask = Task { [weak self] in
                for await _ in changes {
                    guard !Task.isCancelled else { break }
                    await self?.refreshUnreadNotificationCount()
                }
            }
        } catch {
            MerianLog.network.debug(
                "Explore notifications realtime subscription failed: \(error.localizedDescription, privacy: .private)"
            )
            await SupabaseManager.shared.client.removeChannel(channel)
        }
    }

    private func resolveExploreNotificationsUserId() async -> String? {
        if let currentUserId = SupabaseManager.shared.currentUser?.id.uuidString {
            return currentUserId
        }

        guard let session = try? await SupabaseManager.shared.client.auth.session else {
            return nil
        }
        return session.user.id.uuidString
    }
}
