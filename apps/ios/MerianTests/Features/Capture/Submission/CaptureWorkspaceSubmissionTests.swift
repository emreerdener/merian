import CoreData
import MapKit
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Merian

extension CaptureWorkspaceViewModelRefinementTests {
    func testExhaustedQuotaPreviewShowsPaywallBeforeVisualProcessing() async throws {
        enableUnlimitedFreeScansForTest()
        ScanAdmissionManager.shared.overridingPreview = { _ in
            ScanAdmissionPreview(
                decision: .dailyQuotaExhausted,
                effectivePlan: "free",
                dailyLimit: 1,
                dailyRemaining: 0
            )
        }
        defer {
            ScanAdmissionManager.shared.resetForTesting()
            restoreFreeScanLimitForTest()
        }

        let diContainer = AppDIContainer.preview
        let originalContext = OfflineQueueManager.shared.modelContext
        let originalOnline = OfflineQueueManager.shared.isOnline
        let modelContext = try makeModelContext()
        OfflineQueueManager.shared.modelContext = modelContext
        OfflineQueueManager.shared.isOnline = true
        defer {
            cleanupQueuedScans(in: modelContext)
            OfflineQueueManager.shared.modelContext = originalContext
            OfflineQueueManager.shared.isOnline = originalOnline
        }

        let uiImage = makeUIImage()
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        viewModel.stagedCapture.images = [
            StagedImage(
                compressedData: makePNGData(),
                displayData: makePNGData(color: .systemBlue),
                uiImage: uiImage,
                original: IdentifiableImage(image: uiImage)
            )
        ]
        XCTAssertTrue(viewModel.beginAutomaticStagedSubmissionIfEligible())
        XCTAssertFalse(viewModel.shouldPresentActiveScanToolbar)

        await viewModel.submitStagedCapture(modelContext: modelContext)

        XCTAssertEqual(viewModel.activeSheet, .paywall)
        XCTAssertEqual(viewModel.stagedCapture.images.count, 1)
        XCTAssertFalse(viewModel.isAutomaticStagedSubmissionPending)
        XCTAssertTrue(viewModel.shouldPresentActiveScanToolbar)
        XCTAssertFalse(viewModel.isCheckingScanAdmission)
        XCTAssertFalse(diContainer.inferenceEngine.isProcessing)
        XCTAssertEqual(
            try modelContext.fetch(FetchDescriptor<OfflineQueuedScan>()).count,
            0
        )
    }

    func testScanAdmissionPreviewUsesBoundedFailFastTransportPolicy() {
        let configuration = PinnedNetworkTransport.makeConfiguration()

        XCTAssertEqual(
            ScanAdmissionManager.previewRequestTimeout,
            2
        )
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertNil(configuration.urlCache)
    }

    func testConnectivityUnavailableAdmissionQueuesWithoutForegroundInferenceAndCancelsVisualContext() async throws {
        enableUnlimitedFreeScansForTest()
        ScanAdmissionManager.shared.overridingPreview = { _ in
            throw URLError(.timedOut)
        }

        let defaultsSuite = "merian.tests.capture-admission.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        let appSettings = AppSettings(
            userDefaults: defaults,
            observeExternalChanges: false
        )
        appSettings.isExpeditionModeActive = true
        let queueOrchestrator = HardwareOrchestrator(
            appSettings: appSettings,
            observeSystemChanges: false,
            functionalProAccessProvider: { true }
        )
        queueOrchestrator.evaluateConstraints(thermalState: .nominal)
        XCTAssertTrue(queueOrchestrator.isExpeditionModeActive)

        let diContainer = AppDIContainer.preview
        let queueManager = OfflineQueueManager.shared
        let originalContext = queueManager.modelContext
        let originalOnline = queueManager.isOnline
        let originalOrchestrator = queueManager.hardwareOrchestrator
        let modelContext = try makeModelContext()
        queueManager.modelContext = modelContext
        queueManager.isOnline = true
        queueManager.hardwareOrchestrator = queueOrchestrator
        defer {
            cleanupQueuedScans(in: modelContext)
            queueManager.modelContext = originalContext
            queueManager.isOnline = originalOnline
            queueManager.hardwareOrchestrator = originalOrchestrator
            appSettings.isExpeditionModeActive = false
            defaults.removePersistentDomain(forName: defaultsSuite)
            ScanAdmissionManager.shared.resetForTesting()
            restoreFreeScanLimitForTest()
        }

        let uiImage = makeUIImage()
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        let contextTask = makePendingEnvironmentContextTask()
        viewModel.preFetchTask = contextTask
        defer { contextTask.cancel() }
        viewModel.stagedCapture.images = [
            StagedImage(
                compressedData: makePNGData(),
                displayData: makePNGData(color: .systemBlue),
                uiImage: uiImage,
                original: IdentifiableImage(image: uiImage)
            )
        ]
        XCTAssertTrue(viewModel.beginAutomaticStagedSubmissionIfEligible())
        XCTAssertFalse(viewModel.shouldPresentActiveScanToolbar)

        await viewModel.submitStagedCapture(modelContext: modelContext)

        try await waitUntil {
            let queueCount = try? modelContext.fetch(
                FetchDescriptor<OfflineQueuedScan>()
            ).count
            return queueCount == 1 &&
                viewModel.offlineToastMessage?.title == "Scan queued for later."
        }
        let queuedScan = try XCTUnwrap(
            modelContext.fetch(FetchDescriptor<OfflineQueuedScan>()).first
        )
        XCTAssertNil(queueManager.foregroundInferenceGenerations[queuedScan.id])
        XCTAssertFalse(diContainer.inferenceEngine.isProcessing)
        XCTAssertNil(viewModel.activeSheet)
        XCTAssertTrue(contextTask.isCancelled)
        XCTAssertTrue(viewModel.stagedCapture.isEmpty)
        XCTAssertFalse(viewModel.isAutomaticStagedSubmissionPending)
        XCTAssertFalse(viewModel.shouldPresentActiveScanToolbar)
        XCTAssertTrue(queueManager.isOnline)

        let description = ObservationContext(
            freeText: "A small bird calling from a nearby tree"
        )
        let didEnqueueNonVisual = await viewModel.submitNonVisualCapture(
            audioFileNames: [],
            observationContexts: [description],
            mediaTimeline: [.description(description)],
            modelContext: modelContext
        )

        XCTAssertTrue(didEnqueueNonVisual)
        try await waitUntil {
            let queueCount = try? modelContext.fetch(
                FetchDescriptor<OfflineQueuedScan>()
            ).count
            return queueCount == 2 &&
                viewModel.offlineToastMessage?.title ==
                    "Capture queued for analysis."
        }
        let queuedScans = try modelContext.fetch(
            FetchDescriptor<OfflineQueuedScan>()
        )
        XCTAssertEqual(queuedScans.count, 2)
        XCTAssertTrue(queuedScans.allSatisfy {
            queueManager.foregroundInferenceGenerations[$0.id] == nil
        })
        XCTAssertFalse(diContainer.inferenceEngine.isProcessing)
        XCTAssertNil(viewModel.activeSheet)
        XCTAssertTrue(queueManager.isOnline)
    }

    func testMalformedScanAdmissionPreviewRemainsFailClosed() async {
        ScanAdmissionManager.shared.overridingPreview = { _ in
            ScanAdmissionPreview(
                decision: .allowed,
                effectivePlan: "unexpected_plan",
                dailyLimit: nil,
                dailyRemaining: nil
            )
        }
        let queueManager = OfflineQueueManager.shared
        let originalOnline = queueManager.isOnline
        queueManager.isOnline = true
        defer {
            queueManager.isOnline = originalOnline
            ScanAdmissionManager.shared.resetForTesting()
        }

        let viewModel = CaptureWorkspaceViewModel(
            diContainer: AppDIContainer.preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        let route = await viewModel.requestScanAdmission(
            flashFallbackEligible: true
        )

        XCTAssertNil(route)
        XCTAssertEqual(
            viewModel.offlineToastMessage?.title,
            "Unable to check scan availability. Please try again."
        )
        XCTAssertNil(viewModel.activeSheet)
    }

    func testScanAdmissionPreviewUsesServerMediaEligibilityShape() {
        XCTAssertTrue(
            CaptureSubmissionPolicy.isFlashFallbackEligible([
                .image(index: 0)
            ])
        )
        XCTAssertFalse(
            CaptureSubmissionPolicy.isFlashFallbackEligible([
                .image(index: 0),
                .description(ObservationContext(freeText: "Nearby leaves"))
            ])
        )
        XCTAssertFalse(
            CaptureSubmissionPolicy.isFlashFallbackEligible(
                [.image(index: 0)],
                targetEradicationScanId: UUID().uuidString.lowercased()
            )
        )
    }

    func testOfflineVisualSubmissionDoesNotActivateInferenceProcessing() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let diContainer = AppDIContainer.preview
        let originalContext = OfflineQueueManager.shared.modelContext
        let originalOnline = OfflineQueueManager.shared.isOnline
        let modelContext = try makeModelContext()
        OfflineQueueManager.shared.modelContext = modelContext
        OfflineQueueManager.shared.isOnline = false
        defer {
            cleanupQueuedScans(in: modelContext)
            OfflineQueueManager.shared.modelContext = originalContext
            OfflineQueueManager.shared.isOnline = originalOnline
        }

        let uiImage = makeUIImage()
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        viewModel.stagedCapture.images = [
            StagedImage(
                compressedData: makePNGData(),
                displayData: makePNGData(color: .systemBlue),
                uiImage: uiImage,
                original: IdentifiableImage(image: uiImage)
            )
        ]

        await viewModel.submitStagedCapture(modelContext: modelContext)

        try await waitUntil {
            viewModel.offlineToastMessage?.title ==
                "No network connection. Scan queued for later."
        }
        XCTAssertFalse(diContainer.inferenceEngine.isProcessing)
        XCTAssertNil(viewModel.activeSheet)
    }

    func testOfflineVisualQueueFailureDiscardsFilesAndCancelsContext() async throws {
        activatePaidEntitlementAccountForTest()
        defer { resetEntitlementAccountForTest() }

        let diContainer = AppDIContainer.preview
        let originalContext = OfflineQueueManager.shared.modelContext
        let originalOnline = OfflineQueueManager.shared.isOnline
        let modelContext = try makeModelContext()
        OfflineQueueManager.shared.modelContext = modelContext
        OfflineQueueManager.shared.isOnline = false

        let videoFilename = try makeTempVideoFilename()
        let audioFilename = try makeTempAudioFilename()
        let videoURL = FileManager.default.temporaryDirectory.appendingPathComponent(videoFilename)
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(audioFilename)

        defer {
            cleanupQueuedScans(in: modelContext)
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: audioURL)
            OfflineQueueManager.shared.modelContext = originalContext
            OfflineQueueManager.shared.isOnline = originalOnline
        }

        let uiImage = makeUIImage()
        let oversizedFrameData = Data(
            repeating: 0x7A,
            count: Int(MerianConfig.offlineQueueSinglePayloadSoftLimitBytes) + 1
        )
        let stagedFrame = StagedImage(
            compressedData: oversizedFrameData,
            displayData: Data([0x01]),
            uiImage: uiImage,
            original: IdentifiableImage(image: uiImage)
        )
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        let contextTask = makePendingEnvironmentContextTask()
        viewModel.preFetchTask = contextTask
        defer { contextTask.cancel() }
        viewModel.stagedCapture.videos = [
            StagedVideo(
                filePath: videoFilename,
                sampledImages: [stagedFrame],
                audioFilePath: audioFilename
            )
        ]

        await viewModel.submitStagedCapture(modelContext: modelContext)

        try await waitUntil {
            viewModel.offlineToastMessage?.title ==
                "Unable to save capture. Please try again."
        }
        try await waitUntil {
            !FileManager.default.fileExists(atPath: videoURL.path)
                && !FileManager.default.fileExists(atPath: audioURL.path)
        }

        XCTAssertFalse(diContainer.inferenceEngine.isProcessing)
        XCTAssertNil(viewModel.activeSheet)
        XCTAssertTrue(contextTask.isCancelled)
        XCTAssertTrue(viewModel.stagedCapture.isEmpty)
        XCTAssertEqual(try modelContext.fetch(FetchDescriptor<OfflineQueuedScan>()).count, 0)
    }

    func testOfflineAudioSubmissionDoesNotActivateInferenceProcessingAndQueuesPending() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let diContainer = AppDIContainer.preview
        let originalContext = OfflineQueueManager.shared.modelContext
        let originalOnline = OfflineQueueManager.shared.isOnline
        let modelContext = try makeModelContext()
        OfflineQueueManager.shared.modelContext = modelContext
        OfflineQueueManager.shared.isOnline = false
        defer {
            cleanupQueuedScans(in: modelContext)
            OfflineQueueManager.shared.modelContext = originalContext
            OfflineQueueManager.shared.isOnline = originalOnline
        }

        let audioFilename = try makeTempAudioFilename()
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )

        await viewModel.submitNonVisualCapture(
            audioFileNames: [audioFilename],
            observationContexts: [],
            mediaTimeline: [.audio(audioFilename)],
            modelContext: modelContext
        )

        XCTAssertEqual(
            viewModel.offlineToastMessage?.title,
            "No network connection. Queued for analysis."
        )
        XCTAssertFalse(diContainer.inferenceEngine.isProcessing)
        XCTAssertNil(viewModel.activeSheet)

        let queuedScans = try modelContext.fetch(FetchDescriptor<OfflineQueuedScan>())
        XCTAssertEqual(queuedScans.count, 1)
        XCTAssertEqual(queuedScans.first?.queueState, .pending)
    }

    func testMultiCaptureDescribeStagesUntilIdentify() async throws {
        let diContainer = AppDIContainer.preview
        diContainer.appSettings.isMultiCaptureEnabled = true
        diContainer.appSettings.requiresScanConfirmation = false
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        let modelContext = try makeModelContext()

        let didStageFirstDescription = await viewModel.submitDescribe(
            observationContext: ObservationContext(
                freeText: "First staged description"
            ),
            modelContext: modelContext
        )
        XCTAssertTrue(didStageFirstDescription)

        viewModel.stagedCapture.lastSubmitTime = nil

        let didStageSecondDescription = await viewModel.submitDescribe(
            observationContext: ObservationContext(
                freeText: "Second staged description"
            ),
            modelContext: modelContext
        )
        XCTAssertTrue(didStageSecondDescription)

        XCTAssertEqual(viewModel.stagedCapture.observationContexts.count, 2)
        XCTAssertNil(viewModel.activeSheet)
    }
}

private extension CaptureWorkspaceViewModelRefinementTests {
    func makePendingEnvironmentContextTask() -> Task<EnvironmentContext, Never> {
        Task {
            try? await Task.sleep(for: .seconds(30))
            return EnvironmentContext(location: nil)
        }
    }
}
