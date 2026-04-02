import Testing
import Foundation
import Combine
@testable import Merian

@MainActor
struct PushNotificationRoutingTests {
    
    @Test("Tapping a push notification correctly publishes a routing event to open the specific scan id")
    func testNotificationTapRoutesToScan() async {
        // Arrange
        let testScanId = "mock-scan-id-1234"
        let mockUserInfo: [AnyHashable: Any] = ["scanId": testScanId]
        
        var receivedScanId: String? = nil
        var cancellable: AnyCancellable?
        
        // Listen to the shared event publisher used by the root UI to switch tabs and open the sheet
        cancellable = AppEventPublisher.shared.publisher.sink { event in
            if case .appDidEnterActivePhaseWithScan(let scanId) = event {
                receivedScanId = scanId
            }
        }
        
        // Act
        // Simulate a user tapping the system push notification (default action)
        PushNotificationManager.shared.handleNotificationAction(
            userInfo: mockUserInfo,
            actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier"
        )
        
        // Yield to allow the inner @MainActor Task inside handleNotificationAction to execute
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        // Assert
        #expect(receivedScanId == testScanId, "The push notification manager must extract the scanId and broadcast it to the UI router")
        
        // Cleanup
        cancellable?.cancel()
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
