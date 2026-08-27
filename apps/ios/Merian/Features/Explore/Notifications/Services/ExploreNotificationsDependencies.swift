import Foundation

struct ExploreNotificationsDependencies {
    let loadNotifications: @MainActor (
        _ limit: Int,
        _ beforeUpdatedAt: String?,
        _ beforeNotificationId: String?
    ) async throws -> [ExploreNotification]
    let markNotificationsRead: @MainActor () async throws -> Void
    let includesFieldTripNotifications: @MainActor () -> Bool
    let reportFetchFailure: @MainActor (_ error: Error, _ context: String) -> Void
    let errorMessage: @MainActor (Error) -> String
}

extension ExploreNotificationsViewModel {
    typealias Dependencies = ExploreNotificationsDependencies
}

extension ExploreNotificationsDependencies {
    static let live = Self(
        loadNotifications: { limit, beforeUpdatedAt, beforeNotificationId in
            try await MerianNetworkClient.shared.getExploreNotifications(
                limit: limit,
                beforeUpdatedAt: beforeUpdatedAt,
                beforeNotificationId: beforeNotificationId
            )
        },
        markNotificationsRead: {
            _ = try await MerianNetworkClient.shared.markExploreNotificationsRead()
        },
        includesFieldTripNotifications: {
            FeatureFlags.isEnabled(.fieldTrips)
        },
        reportFetchFailure: { error, context in
            if context == "pagination" {
                MerianLog.network.error(
                    "Explore notifications pagination failed: \(error.localizedDescription, privacy: .private)"
                )
            } else {
                MerianLog.network.error(
                    "Explore notifications fetch failed: \(error.localizedDescription, privacy: .private)"
                )
            }
            AppTelemetry.trackExploreNotificationsFetchFailed(context: context)
        },
        errorMessage: ExploreErrorFormatter.message(for:)
    )
}
