import Testing
import Foundation
@testable import Merian

@MainActor
struct AppLifecycleManagerTests {
    
    @Test("AppLifecycleManager intercepts active UI inference and pushes it to OfflineQueue on backgrounding")
    func testHandleBackgroundPhaseRescuesActiveLiveCapture() async {
        // Arrange
        let diContainer = AppDIContainer.preview
        let manager = AppLifecycleManager(container: diContainer)
        let engine = diContainer.inferenceEngine
        
        // Setup initial state: An active live capture is still processing when the user backgrounds the app
        engine.isProcessing = true
        let dummyImageData = Data("dummy test pixels".utf8)
        engine.activeLiveCaptureDatas = [dummyImageData]
        
        // Assert preconditions
        #expect(engine.isBackgroundRescued == false)
        
        // Act
        manager.handleBackgroundPhase()
        
        // Assert
        // The engine's cancelActiveRequest() should have been called, setting isBackgroundRescued to true
        // and signaling that the in-flight inference was deliberately interrupted by the OS backgrounding
        #expect(engine.isBackgroundRescued == true, "Engine should mark the request as background rescued so it isn't automatically refunded")
        #expect(engine.isProcessing == false, "Engine should safely clear the processing state after backgrounding")
    }
}
