import Foundation
import Supabase

extension ConsentRealtimeCoordinator.Dependencies {
    static var live: Self {
        Self(
            isEnabled: {
                !TestExecutionCoordinator.isRunningTests
            },
            makeSubscription: { userId in
                let liveSubscription = LiveConsentRealtimeSubscription(
                    userId: userId
                )
                return ConsentRealtimeCoordinator.Subscription(
                    status: {
                        liveSubscription.status
                    },
                    subscribe: {
                        try await liveSubscription.subscribe()
                    },
                    nextChange: {
                        await liveSubscription.nextChange()
                    },
                    remove: {
                        await liveSubscription.remove()
                    }
                )
            },
            sleep: { delay in
                try await Task.sleep(for: .seconds(delay))
            },
            reportFailure: { error in
                MerianLog.general.debug(
                    "Analytics consent Realtime subscription failed; kind=\(MerianLog.errorKind(error), privacy: .public)."
                )
            }
        )
    }
}

@MainActor
private final class LiveConsentRealtimeSubscription {
    private let channel: RealtimeChannelV2
    private var changes: AsyncStream<InsertAction>.Iterator
    private let removeOperation: @MainActor () async -> Void

    init(userId: UUID) {
        let client = SupabaseManager.shared.client
        let channel = client.channel(
            "legal-analytics-consent-\(userId.uuidString)-\(UUID().uuidString)"
        )
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "user_analytics_consent_events",
            filter: .eq("user_id", value: userId.uuidString)
        )
        self.channel = channel
        self.changes = changes.makeAsyncIterator()
        removeOperation = {
            await client.removeChannel(channel)
        }
    }

    var status: ConsentRealtimeCoordinator.SubscriptionStatus {
        switch channel.status {
        case .subscribed:
            .subscribed
        case .subscribing:
            .subscribing
        case .unsubscribed, .unsubscribing:
            .inactive
        }
    }

    func subscribe() async throws {
        try await channel.subscribeWithError()
    }

    func nextChange() async -> Bool {
        var iterator = changes
        let change: InsertAction? = await iterator.next()
        changes = iterator
        return change != nil
    }

    func remove() async {
        await removeOperation()
    }
}
