import Foundation

/// Notification catalog, read counts, and push-device requests. Badge policy,
/// permissions, registration lifetime, and navigation stay with their callers.
extension MerianNetworkClient {
    func getExploreNotifications(
        limit: Int = 50,
        beforeUpdatedAt: String? = nil,
        beforeNotificationId: String? = nil
    ) async throws -> [ExploreNotification] {
        var payload: [String: Any] = ["limit": limit]
        if let beforeUpdatedAt, let beforeNotificationId {
            payload["before_updated_at"] = beforeUpdatedAt
            payload["before_notification_id"] = beforeNotificationId
        }

        return try await performAuthenticatedJSONPost(
            function: "get-explore-notifications", payload: payload, responseType: ExploreNotificationsResponse.self
        ).data
    }

    func getUnreadExploreNotificationCount() async throws -> Int {
        try await performAuthenticatedJSONPost(
            function: "get-explore-unread-notification-count", payload: [:], responseType: ExploreUnreadNotificationCountResponse.self
        ).unreadCount
    }

    func markExploreNotificationsRead() async throws -> Int {
        try await performAuthenticatedJSONPost(
            function: "mark-explore-notifications-read", payload: [:], responseType: ExploreMarkNotificationsReadResponse.self
        ).markedCount
    }

    func registerPushDevice(
        deviceToken: String,
        environment: String,
        exploreEnabled: Bool,
        commentMentionsEnabled: Bool,
        communityIdentificationsEnabled: Bool
    ) async throws {
        let payload: [String: Any] = [
            "device_token": deviceToken,
            "platform": "ios",
            "environment": environment,
            "explore_enabled": exploreEnabled,
            "comment_mentions_enabled": commentMentionsEnabled,
            "community_identifications_enabled": communityIdentificationsEnabled
        ]
        try await performAuthenticatedJSONPost(
            function: "register-push-device", payload: payload
        )
    }
}
