import Testing
import SwiftData
import Foundation
@testable import Merian

@MainActor
struct CameraViewModelTests {
    
    // Setup a volatile structural context to isolate testing safely natively.
    @MainActor
    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(MerianSchemaV9.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = ModelContext(container)
        return context
    }
    
    @Test func testCameraViewModelSafelyResetsModalsOnBackgrounding() async throws {
        // Arrange
        let viewModel = CameraViewModel()
        
        // Simulating the user actively navigating through physical modals via the new ActiveSheet enum bounds
        viewModel.activeSheet = .insight
        viewModel.isAnalyzingFullscreen = true
        
        // Act: Fire the background lifecycle notification that `AppDelegate` pushes natively
        NotificationCenter.default.post(name: NSNotification.Name("AppDidEnterInactivePhase"), object: nil)
        
        // Let the `RunLoop.main` process the event dynamically inside the test bounds
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Assert: Ensure strict UI bounds resetting securely closing all views naturally guaranteeing the user starts fresh!
        #expect(viewModel.activeSheet == nil, "ActiveSheet MUST evaluate to nil on app background entirely clearing standard navigation")
        #expect(viewModel.isAnalyzingFullscreen == false, "Fullscreen analysis MUST immediately abort securely mapped")
    }
}
