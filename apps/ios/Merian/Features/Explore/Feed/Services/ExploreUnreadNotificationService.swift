import Foundation
import Supabase

@MainActor
final class ExploreUnreadNotificationService {
    private var channel: RealtimeChannelV2?
    private var listenerTask: Task<Void, Never>?
    private var startGeneration = UUID()
    private var isStarting = false

    nonisolated init() {}

    func refreshUnreadCount(force: Bool) async -> Int? {
        guard let accountWorkLease = try? SupabaseManager.shared
            .beginUnownedAccountBoundWork() else { return nil }
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
            return nil
        }

        return count
    }

    func startUpdates(
        onCountChanged: @escaping @MainActor (Int) -> Void
    ) async {
        guard !isStarting, channel == nil, listenerTask == nil else { return }
        guard SupabaseManager.shared.allowsUnownedAccountBoundWork else { return }

        let generation = UUID()
        startGeneration = generation
        isStarting = true
        defer {
            if startGeneration == generation {
                isStarting = false
            }
        }

        if let count = await refreshUnreadCount(force: false) {
            guard startGeneration == generation else { return }
            onCountChanged(count)
        }

        guard !Task.isCancelled,
              startGeneration == generation,
              SupabaseManager.shared.allowsUnownedAccountBoundWork,
              let accountWorkLease = try? SupabaseManager.shared
                  .beginUnownedAccountBoundWork() else {
            return
        }
        defer {
            SupabaseManager.shared.finishAccountBoundWork(accountWorkLease)
        }

        let userId = accountWorkLease.session.userID.uuidString
        let pendingChannel = SupabaseManager.shared.client.channel(
            "explore-notifications-\(userId)-\(UUID().uuidString)"
        )
        let changes = pendingChannel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "explore_post_notifications",
            filter: .eq("user_id", value: userId)
        )

        do {
            try await pendingChannel.subscribeWithError()
            guard !Task.isCancelled,
                  startGeneration == generation,
                  SupabaseManager.shared.allowsUnownedAccountBoundWork,
                  SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(
                      accountWorkLease
                  ) else {
                await SupabaseManager.shared.client.removeChannel(pendingChannel)
                return
            }

            channel = pendingChannel
            listenerTask = Task { [weak self] in
                for await _ in changes {
                    guard !Task.isCancelled, let self else { break }
                    if let count = await self.refreshUnreadCount(force: true) {
                        onCountChanged(count)
                    }
                }
            }
        } catch {
            MerianLog.network.debug(
                "Explore notifications realtime subscription failed: \(error.localizedDescription, privacy: .private)"
            )
            await SupabaseManager.shared.client.removeChannel(pendingChannel)
        }
    }

    func stopUpdates() {
        startGeneration = UUID()
        isStarting = false
        listenerTask?.cancel()
        listenerTask = nil

        guard let channel else { return }
        self.channel = nil

        Task {
            await SupabaseManager.shared.client.removeChannel(channel)
        }
    }
}
