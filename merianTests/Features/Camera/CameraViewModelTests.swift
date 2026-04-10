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

        // Act: fire the background-phase event via AppEventPublisher (replaces legacy NotificationCenter)
        AppEventPublisher.shared.send(.appDidEnterBackgroundPhase)

        // Let RunLoop.main process the event
        try await Task.sleep(nanoseconds: 100_000_000)

        // Assert: all modal state is reset
        #expect(viewModel.activeSheet == nil, "activeSheet must be nil after app backgrounds")
        #expect(viewModel.editingCropIndex == nil, "editingCropIndex must be nil after app backgrounds")
    }

    @Test func testStartRefinementScanStoresRecordAndClosesActiveSheet() async throws {
        // Arrange
        let viewModel = CameraViewModel()
        viewModel.activeSheet = .insight

        let record = LocalScanRecord(
            speciesId: "species_refine",
            scientificName: "Test Species",
            commonName: "Test",
            localImagePath: "test.jpg"
        )

        // Act
        viewModel.startRefinementScan(from: record)

        // Assert
        #expect(viewModel.baseRefinementRecord?.speciesId == "species_refine", "ViewModel must natively capture the refinement record.")
        #expect(viewModel.activeSheet == nil, "ViewModel must strictly hide the active sheet upon jump back to camera viewfinder.")
    }

    @Test func testSubmitActiveScanClearsBuffersAndStateSynchronously() async throws {
        // Arrange
        let viewModel = CameraViewModel()
        
        let record = LocalScanRecord(
            speciesId: "species_refine",
            scientificName: "Test Species",
            commonName: "Test",
            localImagePath: "test.jpg"
        )
        viewModel.startRefinementScan(from: record)

        // Simulate active capture staging
        viewModel.activeScannedDatas = [Data()]
        viewModel.activeDisplayDatas = [Data()]
        
        let context = try createIsolatedContext()

        // Act
        viewModel.submitActiveScan(modelContext: context)

        // Assert: given submitActiveScan is non-async up to the Task boundary,
        // all synchronously wiped memory locks should instantly flush to prevent user double-taps safely.
        #expect(viewModel.baseRefinementRecord == nil, "submitActiveScan must wipe the baseRefinementRecord synchronously immediately.")
        #expect(viewModel.activeScannedDatas.isEmpty, "submitActiveScan must wipe stage data immediately")
        #expect(viewModel.activeDisplayDatas.isEmpty, "submitActiveScan must wipe stage data immediately")
        #expect(viewModel.activeSheet == .insight, "UI should implicitly launch processing skeleton sheet.")
    }

    @Test func testSubmitActiveScanOfflineInterceptor() async throws {
        // Arrange
        let viewModel = CameraViewModel()
        viewModel.activeScannedDatas = [Data()]
        viewModel.activeDisplayDatas = [Data()]
        let context = try createIsolatedContext()

        // Explicitly simulate offline state within the globally injected queue manager
        let originalState = AppDIContainer.shared.offlineQueueManager.isOnline
        AppDIContainer.shared.offlineQueueManager.isOnline = false
        
        defer {
            AppDIContainer.shared.offlineQueueManager.isOnline = originalState
        }

        // Act
        viewModel.submitActiveScan(modelContext: context)

        // Assert
        #expect(viewModel.activeScannedDatas.isEmpty, "submitActiveScan must wipe stage data immediately regardless of network.")
        #expect(viewModel.activeSheet == nil, "UI must NOT launch InsightSheet skeleton if offline.")
        #expect(viewModel.offlineToastMessage == "No network connection. Scan queued for upload.", "UI must generate a toast message for offline interception.")
    }
}
