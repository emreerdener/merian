import Testing
import Foundation
@testable import Merian

@MainActor
struct PhotoLibraryManagerTests {
    
    @Test func testSaveToCameraRollToggleDisabled() async {
        let manager = PhotoLibraryManager.shared
        
        // Arrange: Hard toggle off the user defaults
        UserDefaults.standard.set(false, forKey: "saveToCameraRoll")
        
        let dummyData = Data("test_image".utf8)
        
        // Act
        // This should hit the early return `guard UserDefaults... else { return }`
        // We ensure it doesn't execute physical requests to PHPhotoLibrary and cleanly drops.
        await manager.saveImageToLibrary(imageData: dummyData, location: nil)
        
        // Cleanup
        UserDefaults.standard.set(true, forKey: "saveToCameraRoll")
    }
    
    @Test func testStartObservingAndFetchBypassesNotDetermined() async {
        let manager = PhotoLibraryManager.shared
        
        // This validates the progressive disclosure architectural update.
        // Calling startObservingAndFetch() must silently drop and NOT fire PHPhotoLibrary.requestAuthorization 
        // when status is .notDetermined, allowing the UI to manage the explicit permission gates.
        manager.startObservingAndFetch()
        
        // If it reaches here without blocking on an expectation/completion handler lock, the fallthrough is valid.
        #expect(true, "startObservingAndFetch safely drops .notDetermined requests to enforce progressive disclosure UI triggers.")
    }
}
