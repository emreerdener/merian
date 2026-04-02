import Testing
import SwiftData
import Foundation
@testable import Merian

@MainActor
struct CameraViewModelTests {

    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        return ModelContext(container)
    }

    @Test func testCameraViewModelSafelyResetsModalsOnBackgrounding() async throws {
        // Arrange
        let viewModel = CameraViewModel()
        viewModel.activeSheet = .insight
        viewModel.editingCropIndex = 1

        // Act: fire the inactive-phase event via AppEventPublisher (replaces legacy NotificationCenter)
        AppEventPublisher.shared.send(.appDidEnterInactivePhase)

        // Let RunLoop.main process the event
        try await Task.sleep(nanoseconds: 100_000_000)

        // Assert: all modal state is reset
        #expect(viewModel.activeSheet == nil, "activeSheet must be nil after app backgrounds")
        #expect(viewModel.editingCropIndex == nil, "editingCropIndex must be nil after app backgrounds")
    }
}
