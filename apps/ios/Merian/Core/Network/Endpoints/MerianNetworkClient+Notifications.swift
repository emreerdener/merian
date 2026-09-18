import Foundation

/// Notification catalog, read counts, and push-device requests. Badge policy,
/// permissions, registration lifetime, and navigation stay with their callers.
extension MerianNetworkClient {
    func getExploreNotifications(
        limit: Int = 50,
        beforeUpdatedAt: String? = nil,
        beforeNotificationId: String? = nil
    ) async throws -> [ExploreNotification] {
        var payload: [String: Any] = ["limit": limit, "supports_post_reactions": true]
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
            function: "get-explore-unread-notification-count", payload: ["supports_post_reactions": true], responseType: ExploreUnreadNotificationCountResponse.self
        ).unreadCount
    }

    func markExploreNotificationsRead() async throws -> Int {
        try await performAuthenticatedJSONPost(
            function: "mark-explore-notifications-read", payload: ["supports_post_reactions": true], responseType: ExploreMarkNotificationsReadResponse.self
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
            "supports_post_reactions": true,
            "comment_mentions_enabled": commentMentionsEnabled,
            "community_identifications_enabled": communityIdentificationsEnabled
        ]
        try await performAuthenticatedJSONPost(
            function: "register-push-device", payload: payload
        )
    }
}
