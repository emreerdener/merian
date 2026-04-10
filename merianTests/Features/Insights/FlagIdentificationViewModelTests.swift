import Testing
import SwiftData
import Foundation
@testable import Merian

@MainActor
struct FlagIdentificationViewModelTests {

    init() {
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = ModelContext(container)
        return context
    }

    @Test func testSubmitFlag_Success() async throws {
        // Arrange
        let context = try createIsolatedContext()
        let engine = InferenceEngine()
        
        let record = LocalScanRecord(
            speciesId: "flag_scan_001",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            isFlagged: false
        )
        engine.load(from: record)
        
        // Mock successful Edge Function response
        MockURLProtocol.mockEndpoints["/flag-issue"] = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        
        let viewModel = FlagIdentificationViewModel()
        viewModel.userSuggestion = "Is this actually a Coati?"
        
        // Act
        #expect(viewModel.isSubmitting == false)
        await viewModel.submitFlag(scanId: "flag_scan_001", engine: engine, context: context)
        
        // Assert native state toggles immediately
        #expect(engine.speciesData?.isFlagged == true, "submitFlag must seamlessly mutate the offline state")
        
        // Assert UI alerts
        #expect(viewModel.showAlert == true, "Alert should appear on success")
        #expect(viewModel.isSubmitting == false, "Loader must disable on success array completion")
        #expect(viewModel.alertMessage.contains("Thank you"))
    }

    @Test func testSubmitFlag_NetworkFailure_GracefulFallback() async throws {
        // Arrange
        let context = try createIsolatedContext()
        let engine = InferenceEngine()
        
        let record = LocalScanRecord(
            speciesId: "flag_scan_002",
            scientificName: "Equus caballus",
            commonName: "Horse",
            isFlagged: false
        )
        engine.load(from: record)
        
        // Mock failing server or networking disconnect
        MockURLProtocol.mockEndpoints["/flag-issue"] = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        
        let viewModel = FlagIdentificationViewModel()
        
        // Act
        await viewModel.submitFlag(scanId: "flag_scan_002", engine: engine, context: context)
        
        // Assert memory boundaries remain preserved gracefully due to offline queue tracking
        #expect(engine.speciesData?.isFlagged == true, "submitFlag must flip offline toggles before hitting the catch block")
        
        #expect(viewModel.showAlert == true, "User must still receive the success toast/alert to prevent feedback disruption")
        #expect(viewModel.isSubmitting == false, "Loader must disappear even on simulated network error")
    }
}
