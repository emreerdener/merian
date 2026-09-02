import Foundation
import Testing

@testable import Merian

@Suite("Notification Endpoints")
@MainActor
struct NotificationEndpointTests {
    private typealias RequestCase = NotificationAndPublicProfileEndpointRequestCase

    @Test func requestInventoryKeepsTheFourNotificationOperationsSeparate() {
        #expect(RequestCase.notifications.count == 19)
        #expect(RequestCase.notificationOperations.count == 4)
        #expect(Set(RequestCase.notificationOperations.map(\.function)) == [
            "get-explore-notifications", "get-explore-unread-notification-count",
            "mark-explore-notifications-read", "register-push-device"
        ])
    }

    @Test(arguments: NotificationAndPublicProfileEndpointRequestCase.notifications)
    func requestMappingRemainsStable(_ testCase: NotificationAndPublicProfileEndpointRequestCase) async throws {
        try await testCase.withResponse { client in
            try await testCase.invoke(client)
        }
    }

    @Test func notificationRowsKeepServerOrderTargetsAndMetadata() async throws {
        try await RequestCase.notificationList.withResponse { client in
            let rows = try await client.getExploreNotifications()
            #expect(rows.map(\.id) == ["reply", "follow", "publication", "community", "media"])
            let reply = try #require(rows.first)
            #expect(reply.type == .commentReply && reply.postId == "post")
            #expect(reply.commentId == "comment" && reply.parentCommentId == "parent")
            #expect(reply.reactionEmoji == "🦋" && reply.commentBody == "Test reply")
            #expect(reply.triggeringUserId == "actor" && reply.triggeringUserName == "Test actor")
            #expect(reply.recentActorNames == ["Test newest", "Test oldest"])
            #expect(reply.actionCount == 2 && !reply.isRead && reply.isReplyToViewerComment == true)
            #expect(reply.createdAt == "2026-01-01T12:00:00.000Z" && reply.updatedAt == "2026-01-01T12:01:00.000Z")
            #expect(reply.communityRequestId == nil && reply.fieldTripPublicationId == nil)

            let follow = try #require(rows.first { $0.id == "follow" })
            #expect(follow.type == .follow && follow.postId == nil && follow.isRead)
            #expect(follow.commentId == nil && follow.parentCommentId == nil && follow.isReplyToViewerComment == nil)
            #expect(follow.updatedAt == "2026-01-02T12:01:00Z")

            let publication = try #require(rows.first { $0.id == "publication" })
            #expect(publication.type == .fieldTripFollowedPublication && publication.postId == nil)
            #expect(publication.fieldTripPublicationId == "field-trip" && !publication.isRead)

            let community = try #require(rows.first { $0.id == "community" })
            #expect(community.type == .communityRequestResolved && community.communityRequestId == "request")
            #expect(community.communityTaxonCommonName == "Test bird")
            #expect(community.communityTaxonScientificName == "Testus example")
            #expect(community.communityRequestDisplayName == "Test request")

            let media = try #require(rows.last)
            #expect(media.type == .mediaMissing && media.postId == "media-post" && media.actionCount == 0)
        }
    }

    @Test func emptyNotificationPageRemainsValid() async throws {
        try await RequestCase.notificationList.withResponse(#"{"data":[]}"#) { client in
            let rows = try await client.getExploreNotifications()
            #expect(rows.isEmpty)
        }
    }

    @Test func unknownNotificationTypeStillRejectsThePage() async throws {
        let response = NotificationAndPublicProfileEndpointResponses.notifications
            .replacingOccurrences(of: #""type":"comment_reply""#, with: #""type":"future-type""#)
        try await RequestCase.notificationList.withResponse(response) { client in
            await #expect(throws: DecodingError.self) {
                _ = try await client.getExploreNotifications()
            }
        }
    }

    @Test(arguments: [0, -1, 27])
    func unreadCountKeepsTheTopLevelScalarWithoutClamping(_ count: Int) async throws {
        try await RequestCase.unreadCount.withResponse(#"{"unread_count":\#(count),"data":{"unread_count":999}}"#) { client in
            let unreadCount = try await client.getUnreadExploreNotificationCount()
            #expect(unreadCount == count)
        }
    }

    @Test(arguments: [true, false], [0, -1, 27])
    func markReadReturnsTheServerCountWithoutInterpretingSuccess(success: Bool, count: Int) async throws {
        try await RequestCase.markRead.withResponse(#"{"success":\#(success),"marked_count":\#(count)}"#) { client in
            let markedCount = try await client.markExploreNotificationsRead()
            #expect(markedCount == count)
        }
    }

    @Test(arguments: [#"{"marked_count":3}"#, #"{"success":true}"#, #"{"success":null,"marked_count":3}"#])
    func markReadStillRequiresItsTypedEnvelope(_ response: String) async throws {
        try await RequestCase.markRead.withResponse(response) { client in
            await #expect(throws: DecodingError.self) {
                _ = try await client.markExploreNotificationsRead()
            }
        }
    }

    // The shared-auth recovery regression stays in MerianNetworkClientTests,
    // where its exact protected CI selector continues to own the transport core.
    @Test func testRegisterPushDeviceEndpoint() async throws {
        try await RequestCase.registerPush.withResponse("{}") { client in
            try await client.registerPushDevice(
                deviceToken: "test-device-token", environment: "sandbox",
                exploreEnabled: true, commentMentionsEnabled: false, communityIdentificationsEnabled: true
            )
        }
    }
}
