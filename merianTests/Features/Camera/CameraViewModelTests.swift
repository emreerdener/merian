import Testing
import SwiftData
import Foundation
@testable import Merian

@MainActor
struct CameraViewModelTests {

    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(MerianSchemaV9.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        return ModelContext(container)
    }

    @Test func testCameraViewModelSafelyResetsModalsOnBackgrounding() async throws {
        // Arrange
        let viewModel = CameraViewModel()
        viewModel.activeSheet = .insight
        viewModel.isAnalyzingFullscreen = true

        // Act: fire the inactive-phase notification
        NotificationCenter.default.post(name: .appDidEnterInactivePhase, object: nil)

        // Let RunLoop.main process the event
        try await Task.sleep(nanoseconds: 100_000_000)

        // Assert: all modal state is reset
        #expect(viewModel.activeSheet == nil, "activeSheet must be nil after app backgrounds")
        #expect(viewModel.isAnalyzingFullscreen == false, "isAnalyzingFullscreen must be false after app backgrounds")
    }
}
