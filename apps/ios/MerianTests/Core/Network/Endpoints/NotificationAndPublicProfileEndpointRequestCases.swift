import Foundation
import Testing

@testable import Merian

/// Explicit wire expectations; invalid sentinels prove forwarding, not server acceptance.
struct NotificationAndPublicProfileEndpointRequestCase: Sendable, CustomTestStringConvertible {
    let name: String
    let function: String
    let expectedJSON: String
    let responseJSON: String
    let invoke: @MainActor @Sendable (MerianNetworkClient) async throws -> Void

    var testDescription: String { name }
    var path: String { "/\(function)" }

    static var notificationOperations: [Self] { [notificationList, unreadCount, markRead, registerPush] }
    static var publicProfileOperations: [Self] { [username, displayName, avatar, usernameAvailability] }
    static var operations: [Self] { notificationOperations + publicProfileOperations }
    static var typedOperations: [Self] { [notificationList, unreadCount, markRead] + publicProfileOperations }
    static var readOperations: [Self] { [notificationList, unreadCount, usernameAvailability] }
    static var mutations: [Self] { [markRead, registerPush, username, displayName, avatar] }
    static var notifications: [Self] { notificationOperations + notificationCursors + pushFlags + rawPushValues }
    static var publicProfile: [Self] { publicProfileOperations + profileVariations }

    static let notificationList = Self(
        name: "notification defaults", function: "get-explore-notifications",
        expectedJSON: #"{"limit":50}"#, responseJSON: NotificationAndPublicProfileEndpointResponses.notifications
    ) { client in
        _ = try await client.getExploreNotifications()
    }

    static let unreadCount = Self(
        name: "unread count sends an empty object", function: "get-explore-unread-notification-count",
        expectedJSON: "{}", responseJSON: #"{"unread_count":11}"#
    ) { client in
        _ = try await client.getUnreadExploreNotificationCount()
    }

    static let markRead = Self(
        name: "mark read sends an empty object", function: "mark-explore-notifications-read",
        expectedJSON: "{}", responseJSON: #"{"success":false,"marked_count":3}"#
    ) { client in
        _ = try await client.markExploreNotificationsRead()
    }

    static let registerPush = Self(
        name: "push registration", function: "register-push-device",
        expectedJSON: """
        {"device_token":"test-device-token","platform":"ios","environment":"sandbox",
         "explore_enabled":true,"comment_mentions_enabled":false,"community_identifications_enabled":true}
        """, responseJSON: ""
    ) { client in
        try await client.registerPushDevice(
            deviceToken: "test-device-token", environment: "sandbox",
            exploreEnabled: true, commentMentionsEnabled: false, communityIdentificationsEnabled: true
        )
    }

    static let username = Self(
        name: "username update forwards pasted text", function: "update-public-username",
        expectedJSON: #"{"username":" @Test.Handle "}"#, responseJSON: #"{"username":"test_server"}"#
    ) { client in
        _ = try await client.updatePublicUsername(" @Test.Handle ")
    }

    static let displayName = Self(
        name: "display-name update", function: "update-public-display-name",
        expectedJSON: #"{"display_name":"Test observer"}"#, responseJSON: #"{"display_name":"Test server label"}"#
    ) { client in
        _ = try await client.updatePublicDisplayName("Test observer")
    }

    static let avatar = Self(
        name: "avatar promotion", function: "update-public-avatar",
        expectedJSON: #"{"r2_object_key":"staging/test-user/avatar.webp","mime_type":"image/webp"}"#,
        responseJSON: #"{"avatar_url":"https://media.example.test/avatars/avatar.webp"}"#
    ) { client in
        _ = try await client.updatePublicAvatar(r2ObjectKey: "staging/test-user/avatar.webp", mimeType: "image/webp")
    }

    static let usernameAvailability = Self(
        name: "username availability forwards pasted text", function: "check-public-username",
        expectedJSON: #"{"username":" @Test.Handle "}"#,
        responseJSON: #"{"available":true,"username":"test_server","error":null}"#
    ) { client in
        _ = try await client.checkPublicUsernameAvailability(" @Test.Handle ")
    }

    static let clearedDisplayName = Self(
        name: "empty display name clears the override", function: "update-public-display-name",
        expectedJSON: #"{"display_name":""}"#, responseJSON: #"{"display_name":"test_alias_23"}"#
    ) { client in
        _ = try await client.updatePublicDisplayName("")
    }

    @MainActor
    func withResponse(
        _ responseJSON: String? = nil,
        body: (MerianNetworkClient) async throws -> Void
    ) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        try await confirmation("Exactly one endpoint POST") { sent in
            fixture.transport.register(path: path) { request in
                sent()
                try NetworkEndpointTestSupport.expectPOST(request, function: function, json: expectedJSON)
                return try NetworkEndpointTestSupport.response(to: request, json: responseJSON ?? self.responseJSON)
            }
            try await body(fixture.client)
        }
    }

    private static var notificationCursors: [Self] {
        let values: [(String, String?, String?, String)] = [
            ("neither", nil, nil, ""),
            ("timestamp only", "cursor-time", nil, ""),
            ("ID only", nil, "cursor-id", ""),
            ("complete", "cursor-time", "cursor-id", #","before_updated_at":"cursor-time","before_notification_id":"cursor-id""#),
            ("blank pair", "", "", #","before_updated_at":"","before_notification_id":"""#)
        ]
        return values.map { name, time, identifier, suffix in
            Self(
                name: "notification cursor: \(name)", function: "get-explore-notifications",
                expectedJSON: #"{"limit":-1\#(suffix)}"#, responseJSON: #"{"data":[]}"#
            ) { client in
                _ = try await client.getExploreNotifications(
                    limit: -1, beforeUpdatedAt: time, beforeNotificationId: identifier
                )
            }
        }
    }

    private static var pushFlags: [Self] {
        [false, true].flatMap { explore in
            [false, true].flatMap { mentions in
                [false, true].map { community in
                    Self(
                        name: "push flags: \(explore)/\(mentions)/\(community)", function: "register-push-device",
                        expectedJSON: """
                        {"device_token":"test-device-token","platform":"ios","environment":"production",
                         "explore_enabled":\(explore),"comment_mentions_enabled":\(mentions),
                         "community_identifications_enabled":\(community)}
                        """, responseJSON: ""
                    ) { client in
                        try await client.registerPushDevice(
                            deviceToken: "test-device-token", environment: "production",
                            exploreEnabled: explore, commentMentionsEnabled: mentions,
                            communityIdentificationsEnabled: community
                        )
                    }
                }
            }
        }
    }

    private static var rawPushValues: [Self] {
        [
            Self(name: "push text is not normalized", function: "register-push-device",
                 expectedJSON: """
                 {"device_token":" TEST TOKEN ","platform":"ios","environment":" Sandbox ",
                  "explore_enabled":false,"comment_mentions_enabled":true,"community_identifications_enabled":false}
                 """, responseJSON: "") { client in
                try await client.registerPushDevice(
                    deviceToken: " TEST TOKEN ", environment: " Sandbox ",
                    exploreEnabled: false, commentMentionsEnabled: true, communityIdentificationsEnabled: false
                )
            },
            Self(name: "empty push strings are not omitted", function: "register-push-device",
                 expectedJSON: """
                 {"device_token":"","platform":"ios","environment":"",
                  "explore_enabled":false,"comment_mentions_enabled":false,"community_identifications_enabled":false}
                 """, responseJSON: "") { client in
                try await client.registerPushDevice(
                    deviceToken: "", environment: "",
                    exploreEnabled: false, commentMentionsEnabled: false, communityIdentificationsEnabled: false
                )
            }
        ]
    }

    private static var profileVariations: [Self] {
        let longUsername = String(repeating: "x", count: 25)
        let longDisplayName = String(repeating: "x", count: 256)
        return [
            Self(name: "empty username update", function: "update-public-username",
                 expectedJSON: #"{"username":""}"#, responseJSON: username.responseJSON) { client in
                _ = try await client.updatePublicUsername("")
            },
            Self(name: "username whitespace is preserved", function: "update-public-username",
                 expectedJSON: #"{"username":" \n "}"#, responseJSON: username.responseJSON) { client in
                _ = try await client.updatePublicUsername(" \n ")
            },
            Self(name: "empty availability input", function: "check-public-username",
                 expectedJSON: #"{"username":""}"#, responseJSON: usernameAvailability.responseJSON) { client in
                _ = try await client.checkPublicUsernameAvailability("")
            },
            Self(name: "availability whitespace is preserved", function: "check-public-username",
                 expectedJSON: #"{"username":" \n "}"#, responseJSON: usernameAvailability.responseJSON) { client in
                _ = try await client.checkPublicUsernameAvailability(" \n ")
            },
            clearedDisplayName,
            Self(name: "display whitespace is preserved", function: "update-public-display-name",
                 expectedJSON: #"{"display_name":"  Test  observer \n "}"#, responseJSON: displayName.responseJSON) { client in
                _ = try await client.updatePublicDisplayName("  Test  observer \n ")
            },
            Self(name: "JPEG avatar key and MIME", function: "update-public-avatar",
                 expectedJSON: #"{"r2_object_key":"staging/test-user/avatar.jpg","mime_type":"image/jpeg"}"#,
                 responseJSON: avatar.responseJSON) { client in
                _ = try await client.updatePublicAvatar(r2ObjectKey: "staging/test-user/avatar.jpg", mimeType: "image/jpeg")
            },
            Self(name: "avatar key and MIME are not normalized", function: "update-public-avatar",
                 expectedJSON: #"{"r2_object_key":" Staging/Test.jpg ","mime_type":" IMAGE/JPEG "}"#,
                 responseJSON: avatar.responseJSON) { client in
                _ = try await client.updatePublicAvatar(r2ObjectKey: " Staging/Test.jpg ", mimeType: " IMAGE/JPEG ")
            },
            Self(name: "empty avatar fields are not omitted", function: "update-public-avatar",
                 expectedJSON: #"{"r2_object_key":"","mime_type":""}"#, responseJSON: avatar.responseJSON) { client in
                _ = try await client.updatePublicAvatar(r2ObjectKey: "", mimeType: "")
            },
            Self(name: "username update is not truncated", function: "update-public-username",
                 expectedJSON: #"{"username":"\#(longUsername)"}"#, responseJSON: username.responseJSON) { client in
                _ = try await client.updatePublicUsername(longUsername)
            },
            Self(name: "availability input is not truncated", function: "check-public-username",
                 expectedJSON: #"{"username":"\#(longUsername)"}"#, responseJSON: usernameAvailability.responseJSON) { client in
                _ = try await client.checkPublicUsernameAvailability(longUsername)
            },
            Self(name: "display name is not truncated", function: "update-public-display-name",
                 expectedJSON: #"{"display_name":"\#(longDisplayName)"}"#, responseJSON: displayName.responseJSON) { client in
                _ = try await client.updatePublicDisplayName(longDisplayName)
            }
        ]
    }
}
