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

    func refreshUnreadNotificationCount(force: Bool = false) async {
        guard let accountWorkLease = try? SupabaseManager.shared
            .beginUnownedAccountBoundWork() else { return }
        defer {
            SupabaseManager.shared.finishAccountBoundWork(accountWorkLease)
        }
        guard let count = await AppIconBadgeCoordinator
            .refreshExploreUnreadNotificationCount(force: force),
              !Task.isCancelled,
              SupabaseManager.shared.allowsUnownedAccountBoundWork,
              SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(
                accountWorkLease
              ) else {
            return
        }
        unreadNotificationCount = count
    }

    func startUnreadNotificationUpdates() async {
        guard SupabaseManager.shared.allowsUnownedAccountBoundWork else {
            return
        }
        await refreshUnreadNotificationCount()
        guard !Task.isCancelled,
              SupabaseManager.shared.allowsUnownedAccountBoundWork else {
            return
        }
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
        guard let accountWorkLease = try? SupabaseManager.shared
            .beginUnownedAccountBoundWork() else { return }
        defer {
            SupabaseManager.shared.finishAccountBoundWork(accountWorkLease)
        }
        let userId = accountWorkLease.session.userID.uuidString

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
            guard !Task.isCancelled,
                  SupabaseManager.shared.allowsUnownedAccountBoundWork,
                  SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(
                    accountWorkLease
                  ) else {
                await SupabaseManager.shared.client.removeChannel(channel)
                return
            }
            unreadNotificationsChannel = channel
            unreadNotificationListenerTask = Task { [weak self] in
                for await _ in changes {
                    guard !Task.isCancelled else { break }
                    await self?.refreshUnreadNotificationCount(force: true)
                }
            }
        } catch {
            MerianLog.network.debug(
                "Explore notifications realtime subscription failed: \(error.localizedDescription, privacy: .private)"
            )
            await SupabaseManager.shared.client.removeChannel(channel)
        }
    }

}
