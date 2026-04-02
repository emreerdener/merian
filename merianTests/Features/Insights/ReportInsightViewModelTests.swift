import Foundation
import Testing
import SwiftData
@testable import merian

@Suite("ReportInsightViewModel Tests")
@MainActor
struct ReportInsightViewModelTests {
    
    @Test("Initialization and UI Constants", .timeLimit(.minutes(1)))
    func testInitialization() async throws {
        let viewModel = ReportInsightViewModel()
        
        // Assert all the declarative properties initialize correctly for UI consumption
        #expect(viewModel.flagReason == "Inappropriate content")
        #expect(viewModel.reasons.count == 3)
        #expect(viewModel.isSubmitting == false)
        #expect(viewModel.showAlert == false)
        #expect(viewModel.userSuggestion == "")
    }

    @Test("Submit Flag Edge Fallback Toggles UI State Properly", .timeLimit(.minutes(1)))
    func testSubmitFlagTogglesState() async throws {
        let schema = Schema([LocalScanRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let engine = InferenceEngine(
            modelContext: context,
            hardwareOrchestrator: HardwareOrchestrator(),
            cameraManager: CameraManager(),
            environmentContextManager: EnvironmentContextManager()
        )
        
        let viewModel = ReportInsightViewModel()
        
        #expect(viewModel.isSubmitting == false)
        #expect(viewModel.showAlert == false)
        
        // Mock a network collision logic bound - When network offline conditions occur, 
        // submitFlag() falls back by setting UI parameters smoothly to gracefully accept local input.
        await viewModel.submitFlag(scanId: UUID().uuidString, engine: engine, context: context)
        
        #expect(viewModel.isSubmitting == false)
        #expect(viewModel.showAlert == true)
        #expect(viewModel.alertMessage == "Thank you! Your feedback helps us improve Merian's AI.")
    }
}
