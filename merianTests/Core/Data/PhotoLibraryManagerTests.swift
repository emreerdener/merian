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
}
