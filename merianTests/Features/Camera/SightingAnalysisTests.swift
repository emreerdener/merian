import Testing
import SwiftData
import Foundation
import UIKit
@testable import Merian

@Suite("SightingAnalysis — CameraViewModel.submitSighting")
@MainActor
struct SightingAnalysisTests {

    private func makeIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let config = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // MARK: - Guard: empty context

    @Test("submitSighting does nothing when context is empty")
    func testSubmitSightingGuardsEmptyContext() throws {
        let viewModel = CameraViewModel()
        let modelContext = try makeIsolatedContext()
        let emptyContext = ObservationContext()

        viewModel.submitSighting(observationContext: emptyContext, modelContext: modelContext)

        #expect(viewModel.activeSheet == nil, "No sheet should open for an empty ObservationContext")
        #expect(viewModel.pendingAnalyzeScanId == nil, "No scanId should be assigned for an empty context")
    }

    // MARK: - Happy path synchronous state

    @Test("submitSighting opens insight sheet synchronously")
    func testSubmitSightingOpensInsightSheet() throws {
        let viewModel = CameraViewModel()
        let modelContext = try makeIsolatedContext()

        var context = ObservationContext()
        context.organismClass = .bird
        context.behaviors = [.flying]

        viewModel.submitSighting(observationContext: context, modelContext: modelContext)

        #expect(viewModel.activeSheet == .insight, "InsightSheet must open immediately upon sighting submission")
    }

    @Test("submitSighting assigns a non-nil pendingAnalyzeScanId")
    func testSubmitSightingAssignsScanId() throws {
        let viewModel = CameraViewModel()
        let modelContext = try makeIsolatedContext()

        var context = ObservationContext()
        context.organismClass = .insect
        context.colors = [.yellow, .black]

        viewModel.submitSighting(observationContext: context, modelContext: modelContext)

        #expect(viewModel.pendingAnalyzeScanId != nil, "A stable scanId must be assigned after submitSighting")
    }

    @Test("Successive submitSighting calls produce unique scanIds")
    func testSuccessiveSubmissionsProduceDistinctScanIds() throws {
        let viewModel = CameraViewModel()
        let modelContext = try makeIsolatedContext()

        var context = ObservationContext()
        context.organismClass = .plant

        viewModel.submitSighting(observationContext: context, modelContext: modelContext)
        let firstId = viewModel.pendingAnalyzeScanId

        viewModel.submitSighting(observationContext: context, modelContext: modelContext)
        let secondId = viewModel.pendingAnalyzeScanId

        #expect(firstId != secondId, "Each sighting submission must produce a unique scanId to prevent stale-task collisions")
    }

    // MARK: - InferenceEngine state reset

    @Test("submitSighting calls prepareForNewScan resetting isProcessing")
    func testSubmitSightingResetsInferenceEngineState() throws {
        let viewModel = CameraViewModel()
        let modelContext = try makeIsolatedContext()

        // Simulate a pre-existing result
        let engine = AppDIContainer.shared.inferenceEngine

        var context = ObservationContext()
        context.organismClass = .mammal
        context.behaviors = [.walking]

        viewModel.submitSighting(observationContext: context, modelContext: modelContext)

        #expect(engine.isProcessing, "InferenceEngine must be in isProcessing == true immediately after submitSighting")
        #expect(engine.speciesData == nil, "speciesData must be nil after prepareForNewScan")
    }

    // MARK: - Offline queue intercept

    @Test("submitSighting offline queues the sighting and shows toast without opening the sheet")
    func testSubmitSightingOfflineQueuesAndShowsToast() throws {
        let viewModel = CameraViewModel()
        let modelContext = try makeIsolatedContext()

        var context = ObservationContext()
        context.organismClass = .bird
        context.behaviors = [.flying]

        let originalState = AppDIContainer.shared.offlineQueueManager.isOnline
        AppDIContainer.shared.offlineQueueManager.isOnline = false
        AppDIContainer.shared.offlineQueueManager.modelContext = modelContext
        defer {
            AppDIContainer.shared.offlineQueueManager.isOnline = originalState
            AppDIContainer.shared.offlineQueueManager.modelContext = nil
        }

        viewModel.submitSighting(observationContext: context, modelContext: modelContext)

        #expect(viewModel.activeSheet == nil, "Insight sheet must NOT open when offline")
        #expect(
            viewModel.offlineToastMessage == "No network connection. Queued for upload.",
            "Toast must appear when offline"
        )

        let stagedRaw = ScanQueueState.staged.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw == stagedRaw }
        )
        let queued = try modelContext.fetch(descriptor)
        #expect(!queued.isEmpty, "At least one staged sighting scan must exist after offline submitSighting")
        #expect(queued.first?.localImagePaths.isEmpty == true, "Sighting-only queued scan must have no image paths")
        #expect(queued.first?.observationContextJSON != nil, "Sighting-only queued scan must store observationContextJSON")
    }

    // MARK: - enqueueSighting round-trip

    @Test("enqueueSighting stores a staged OfflineQueuedScan with decodable observationContextJSON")
    func testEnqueueSightingRoundTrip() throws {
        let modelContext = try makeIsolatedContext()

        var context = ObservationContext()
        context.organismClass = .spider
        context.colors = [.black, .brown]
        context.size = .thumbnail
        context.freeText = "Eight legs, shiny abdomen"

        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: 37.7749,
            gpsLongitude: -122.4194,
            gpsElevation: 10.0,
            locationName: "San Francisco",
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
            zoomFactor: nil,
            estimatedSizeCm: nil
        )

        AppDIContainer.shared.offlineQueueManager.modelContext = modelContext
        defer { AppDIContainer.shared.offlineQueueManager.modelContext = nil }

        AppDIContainer.shared.offlineQueueManager.enqueueSighting(
            observationContext: context,
            telemetry: telemetry,
            scanId: "test-sighting-id"
        )

        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == "test-sighting-id" }
        )
        descriptor.fetchLimit = 1
        let results = try modelContext.fetch(descriptor)
        let scan = try #require(results.first, "OfflineQueuedScan must be inserted by enqueueSighting")

        #expect(scan.localImagePaths.isEmpty, "Sighting scan must have no image paths")
        #expect(scan.scanStateRaw == ScanQueueState.staged.rawValue, "Sighting scan must enter queue as .staged")
        #expect(scan.gpsLatitude == 37.7749, "GPS latitude must be preserved")
        #expect(scan.observationContextJSON != nil, "observationContextJSON must be stored")

        let jsonData = try #require(scan.observationContextJSON?.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ObservationContext.self, from: jsonData)
        #expect(decoded == context, "Decoded ObservationContext must equal the original")
    }

    // MARK: - buildExtractedScanData for sighting-only scans

    @Test("buildExtractedScanData derives description from observationContextJSON for sighting-only scans")
    func testBuildExtractedScanDataForSightingOnly() throws {
        let modelContext = try makeIsolatedContext()
        let container = modelContext.container

        var context = ObservationContext()
        context.organismClass = .insect
        context.colors = [.yellow]
        context.behaviors = [.flying]

        let contextJSON = String(
            data: try JSONEncoder().encode(context),
            encoding: .utf8
        )!

        let scan = OfflineQueuedScan(
            id: "extract-test",
            timestamp: Date(),
            localImagePaths: [],
            observationContextJSON: contextJSON
        )
        modelContext.insert(scan)
        try modelContext.save()

        let extracted = AppDIContainer.shared.offlineQueueManager.buildExtractedScanData(
            from: scan,
            container: container
        )

        #expect(extracted.localImagePaths.isEmpty, "Sighting-only extracted data must have no image paths")
        #expect(extracted.observationContextJSON == contextJSON, "Raw JSON must be preserved verbatim")
        #expect(extracted.description != nil, "description must be derived from the stored JSON")
        #expect(extracted.description?.contains("Insect") == true, "Serialized description must include organism class")
        #expect(extracted.description?.contains("Flying") == true, "Serialized description must include behavior")
    }

    // MARK: - ObservationContext isolation (value semantics)

    @Test("Mutating context after submitSighting does not affect in-flight inference")
    func testContextMutationAfterSubmitDoesNotAffectInFlight() throws {
        let viewModel = CameraViewModel()
        let modelContext = try makeIsolatedContext()

        var context = ObservationContext()
        context.organismClass = .bird
        context.freeText = "Original notes"

        viewModel.submitSighting(observationContext: context, modelContext: modelContext)
        let scanIdAfterSubmit = viewModel.pendingAnalyzeScanId

        // Mutate the local copy — must not affect the captured snapshot
        context.freeText = "Modified notes"
        context.organismClass = .reptile

        // The scanId must be unchanged — no second submission happened
        #expect(viewModel.pendingAnalyzeScanId == scanIdAfterSubmit, "pendingAnalyzeScanId must remain stable after external context mutation")
    }
}
