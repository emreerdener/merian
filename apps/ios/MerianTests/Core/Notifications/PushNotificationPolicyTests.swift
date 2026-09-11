import Foundation
import Testing

@testable import Merian

struct PushNotificationPolicyTests {
    @Test("APNs tokens use stable lowercase hexadecimal encoding")
    func tokenEncoding() {
        #expect(
            PushNotificationPolicy.encodedDeviceToken(
                Data([0x00, 0x0F, 0x10, 0xFF])
            ) == "000f10ff"
        )
    }

    @Test("Registration requires a nonempty token")
    func registrationRequiresToken() {
        #expect(makeRegistrationRequest(token: nil) == nil)
        #expect(makeRegistrationRequest(token: "") == nil)
    }

    @Test("Authorization gates every remote preference")
    func authorizationGatesPreferences() throws {
        let denied = try #require(
            makeRegistrationRequest(token: "token", authorized: false)
        )
        #expect(!denied.exploreEnabled)
        #expect(!denied.commentMentionsEnabled)
        #expect(!denied.communityIdentificationsEnabled)

        let authorized = try #require(
            makeRegistrationRequest(token: "token", authorized: true)
        )
        #expect(authorized.exploreEnabled)
        #expect(authorized.commentMentionsEnabled)
        #expect(authorized.communityIdentificationsEnabled)
        #expect(authorized.accountScopeID == "account-test")
        #expect(authorized.environment == "sandbox")
    }

    @Test("Explore activity routes preserve comment aliases")
    func explorePostRoute() {
        let route = PushNotificationPolicy.route(
            userInfo: [
                "type": "explore_activity",
                "postId": "post-1",
                "comment_id": "comment-1",
                "parent_comment_id": "parent-1"
            ],
            isDismissAction: false
        )

        #expect(
            route == .explorePost(
                postId: "post-1",
                targetCommentId: "comment-1",
                targetReplyParentCommentId: "parent-1"
            )
        )
    }

    @Test("Community routes take priority and preserve snake-case input")
    func communityRoute() {
        let route = PushNotificationPolicy.route(
            userInfo: [
                "type": "explore_activity",
                "community_request_id": "request-1",
                "postId": "post-1"
            ],
            isDismissAction: false
        )

        #expect(
            route == .communityIdentification(requestId: "request-1")
        )
    }

    @Test("Scan routing and dismiss behavior remain stable")
    func scanAndDismissRoutes() {
        let payload: [AnyHashable: Any] = ["scanId": "scan-1"]
        #expect(
            PushNotificationPolicy.route(
                userInfo: payload,
                isDismissAction: false
            ) == .scan(scanId: "scan-1")
        )
        #expect(
            PushNotificationPolicy.route(
                userInfo: payload,
                isDismissAction: true
            ) == nil
        )
        #expect(
            PushNotificationPolicy.route(
                userInfo: ["scan_id": "scan-1"],
                isDismissAction: false
            ) == nil
        )
    }

    @Test("Foreground presentation keeps Explore visible")
    func foregroundPresentation() {
        #expect(
            PushNotificationPolicy.foregroundPresentation(
                notificationType: "explore_activity",
                suppressesInferenceBanners: true
            ) == .bannerSoundAndList
        )
        #expect(
            PushNotificationPolicy.foregroundPresentation(
                notificationType: "achievement",
                suppressesInferenceBanners: false
            ) == .silent
        )
        #expect(
            PushNotificationPolicy.foregroundPresentation(
                notificationType: nil,
                suppressesInferenceBanners: true
            ) == .silent
        )
        #expect(
            PushNotificationPolicy.foregroundPresentation(
                notificationType: nil,
                suppressesInferenceBanners: false
            ) == .bannerSoundAndList
        )
    }

    @Test("Local notification descriptors preserve the system contract")
    func descriptors() {
        let imageURL = URL(fileURLWithPath: "/tmp/species.jpg")
        let inference = PushNotificationPolicy.inferenceCompleteDescriptor(
            speciesName: "Monarch",
            scanID: "scan-1",
            imageURL: imageURL
        )
        #expect(inference.identifier == "inference_scan-1")
        #expect(inference.title == "Monarch")
        #expect(
            inference.body ==
                "Analysis complete. Tap to view full insights."
        )
        #expect(inference.userInfo == ["scanId": "scan-1"])
        #expect(
            inference.categoryIdentifier ==
                PushNotificationIdentifiers.inferenceCategory
        )
        #expect(
            inference.threadIdentifier ==
                PushNotificationIdentifiers.inferenceThread
        )
        #expect(inference.isTimeSensitive)
        #expect(inference.attachmentURL == imageURL)

        let failure = PushNotificationPolicy.uploadFailedDescriptor(
            identifier: "failure-1"
        )
        #expect(failure.title == "Upload failed")
        #expect(failure.userInfo == ["type": "failure"])
        #expect(!failure.isTimeSensitive)

        let achievement = PushNotificationPolicy.achievementDescriptor(
            title: "Global Explorer",
            identifier: "achievement-1"
        )
        #expect(achievement.title == "Achievement Unlocked!")
        #expect(achievement.body == "You just earned: Global Explorer")
        #expect(achievement.userInfo == ["type": "achievement"])
    }

    private func makeRegistrationRequest(
        token: String?,
        authorized: Bool = true
    ) -> PushRegistrationRequest? {
        PushNotificationPolicy.registrationRequest(
            accountScopeID: "account-test",
            deviceToken: token,
            environment: "sandbox",
            hasAuthorization: authorized,
            exploreEnabled: true,
            commentMentionsEnabled: true,
            communityIdentificationsEnabled: true
        )
    }
}
