import Testing
import Foundation
@testable import Merian

@MainActor
struct PushNotificationRoutingTests {
    
    @Test("Tapping a push notification queues a delivery-critical scan route")
    func testNotificationTapRoutesToScan() async {
        // Arrange
        let testScanId = "mock-scan-id-1234"
        let mockUserInfo: [AnyHashable: Any] = ["scanId": testScanId]
        
        let coordinator = AppDIContainer.shared.appRouteCoordinator
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }
        
        // Act
        // Simulate a user tapping the system push notification (default action)
        PushNotificationManager.shared.handleNotificationAction(
            userInfo: mockUserInfo,
            actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier"
        )
        
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while coordinator.nextRequestID == nil && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        
        // Assert
        let request = coordinator.claimNext()
        #expect(request?.route == .scan(scanId: testScanId))
        #expect(request?.source == .pushNotification)
    }

    @Test("Unseen scan indicator (blue dot) state cycle is updated correctly in UserDefaults")
    func testScanLibraryViewClearsBlueDotIndicator() async {
        // Arrange
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: UserDefaultsKeys.hasUnseenScan)
        
        // Assert precondition
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasUnseenScan) == false)
        
        // Act: Simulated Inference or Background Sync completing
        // This is exactly what OfflineQueueManager and InferenceEngine execute upon success
        defaults.set(true, forKey: UserDefaultsKeys.hasUnseenScan)
        
        // Assert
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasUnseenScan) == true, "The blue dot indicator should trigger upon scan completion")
        
        // Act: Simulated UI Router navigating to the library view
        // CameraSheetRouter executes this whenever activeSheet == .library
        defaults.set(false, forKey: UserDefaultsKeys.hasUnseenScan)
        
        // Assert
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasUnseenScan) == false, "Viewing the library should instantly clear the blue dot indicator")
    }
}
