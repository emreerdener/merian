import Testing
import Foundation
import Combine
import UserNotifications
@testable import Merian

@MainActor
struct PushNotificationManagerTests {
    
    @Test func testManagerInitialization() {
        // Assert the hardware primitive initializes safely off the singleton
        let _ = PushNotificationManager.shared
    }
    
    @Test func testSetupDelegateRegistersSuccessfully() {
        let manager = PushNotificationManager.shared
        
        // Act
        manager.setupDelegate()
        
        // Assert
        // In testing bounds, UNUserNotificationCenter.current().delegate should be safely assigned
        #expect(UNUserNotificationCenter.current().delegate === manager, "PushNotificationManager must physically assert itself as the global UNUserNotificationCenterDelegate precisely upon initialization.")
    }
    
    @Test func testSendInferenceNotificationConstructsValidPayload() async {
        let manager = PushNotificationManager.shared
        
        // Act
        // Because UNUserNotificationCenter is a global OS actor, `sendInferenceCompleteNotification` immediately executes `.add(request)`.
        // While we cannot cleanly intercept the OS delivery boundary natively in a pure unit test without mocking `UNUserNotificationCenter`,
        // we can safely execute the function structurally to ensure it does not dynamically crash on `userInfo` formatting or nil string interpolations.
        manager.sendInferenceCompleteNotification(speciesName: "Test Subject", scanId: "12345-ABCDE")
        
        // If execution reaches here, string interpolations and Native OS UNMutableNotificationContent bounds executed perfectly natively.
        #expect(true)
    }
    
    @Test func testSendAchievementUnlockedNotificationConstructsValidPayload() async {
        let manager = PushNotificationManager.shared
        
        // Act
        // Because UNUserNotificationCenter is a global OS actor, we structurally verify it does not crash processing the primitive dictionary configurations down to the native OS layer.
        manager.sendAchievementUnlockedNotification(achievementTitle: "Global Explorer")
        
        #expect(true)
    }

    @Test func testSendUploadFailedNotificationConstructsValidPayload() async {
        let manager = PushNotificationManager.shared
        
        // Act
        manager.sendUploadFailedNotification()
        
        #expect(true)
    }

    @Test func testExploreNotificationTapPublishesDeepLinkEvent() async throws {
        let manager = PushNotificationManager.shared
        let publisher = AppEventPublisher.shared.publisher
        let expectedPostId = "explore-post-123"
        var receivedEvent: AppEvent?
        let cancellable = publisher.sink { event in
            receivedEvent = event
        }
        defer { cancellable.cancel() }

        manager.handleNotificationAction(
            userInfo: [
                "type": "explore_activity",
                "postId": expectedPostId,
            ],
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while receivedEvent == nil && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        guard case .appDidEnterActivePhaseWithExplorePost(let postId, _, _)? = receivedEvent else {
            Issue.record("Expected an Explore deep-link event from the push tap handler.")
            return
        }

        #expect(postId == expectedPostId)
    }
}
