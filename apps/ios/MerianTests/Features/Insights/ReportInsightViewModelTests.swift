import Foundation
import SwiftData
import Testing

@testable import Merian

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
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let config = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let engine = InferenceEngine()
        let scanId = UUID().uuidString
        engine.speciesData = SpeciesData(
            scanId: scanId,
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.9,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial"
        )
        
        let viewModel = ReportInsightViewModel()
        
        #expect(viewModel.isSubmitting == false)
        #expect(viewModel.showAlert == false)
        
        // Mock a network collision logic bound - When network offline conditions occur, 
        // submitFlag() falls back by setting UI parameters smoothly to gracefully accept local input.
        await viewModel.submitFlag(scanId: scanId, engine: engine, context: context)
        
        #expect(viewModel.isSubmitting == false)
        #expect(viewModel.showAlert == true)
        #expect(viewModel.alertMessage == "Thank you! Your feedback helps us improve Naturebook's AI.")
    }

    @Test("Submit Flag Rejects Changed Scan Identity", .timeLimit(.minutes(1)))
    func testSubmitFlagRejectsChangedScanIdentity() async throws {
        let schema = Schema(CurrentSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "current_report_scan",
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.9,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial"
        )
        let viewModel = ReportInsightViewModel()

        await viewModel.submitFlag(
            scanId: "previous_report_scan",
            engine: engine,
            context: context
        )

        #expect(engine.speciesData?.isFlagged == false)
        #expect(viewModel.showAlert == false)
    }

    @Test("Submit Flag Rejects Stale Same-Scan Completion", .timeLimit(.minutes(1)))
    func testSubmitFlagRejectsStaleSameScanCompletion() async throws {
        let schema = Schema(CurrentSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let engine = InferenceEngine()
        let scanId = "reappearing_report_scan"
        engine.speciesData = makeSpeciesData(scanId: scanId)
        let initialPresentationGeneration = engine.scanPresentationGeneration
        let (requestStarted, requestStartedContinuation) = AsyncStream<Void>.makeStream()
        let (responseGate, responseGateContinuation) = AsyncStream<Void>.makeStream()
        let viewModel = ReportInsightViewModel { _, _, _, _ in
            requestStartedContinuation.yield()
            for await _ in responseGate {
                break
            }
        }

        let submission = Task { @MainActor in
            await viewModel.submitFlag(
                scanId: scanId,
                engine: engine,
                context: context
            )
        }
        for await _ in requestStarted {
            break
        }
        requestStartedContinuation.finish()

        engine.prepareForNewScan()
        engine.speciesData = makeSpeciesData(scanId: scanId)
        #expect(engine.scanPresentationGeneration != initialPresentationGeneration)

        responseGateContinuation.yield()
        responseGateContinuation.finish()
        await submission.value

        #expect(!viewModel.showAlert)
        #expect(!viewModel.isSubmitting)
    }

    private func makeSpeciesData(scanId: String) -> SpeciesData {
        SpeciesData(
            scanId: scanId,
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.9,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial"
        )
    }
}
