import CoreData
import MapKit
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Merian

extension CaptureWorkspaceViewModelRefinementTests {
    func testStartRefinementScanStagesPreparedHistoricalImage() async throws {
        let expectedCompressedData = makePNGData()
        let expectedFileName = "historical-refinement-\(UUID().uuidString).webp"
        let expectedFileURL = URL.documentsDirectory.appendingPathComponent(expectedFileName)
        let expectedDisplaySignature = Data("\(expectedFileURL.path)|reencode".utf8)
        let expectedPreviewCGImage = SendableCGImage(image: makePreviewCGImage())
        try expectedCompressedData.write(to: expectedFileURL)
        defer { try? FileManager.default.removeItem(at: expectedFileURL) }

        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { request in
                return PreparedStagedImage(
                    compressedData: expectedCompressedData,
                    displayData: Data("\(request.fileURL.path)|reencode".utf8),
                    historicalContext: request.historicalContext,
                    previewCGImage: expectedPreviewCGImage
                )
            },
            prewarmHeadersOnInit: false
        )

        let record = LocalScanRecord(
            speciesId: "species-1",
            scientificName: "Haemorhous mexicanus",
            commonName: "House Finch",
            coverImagePath: expectedFileName
        )

        viewModel.startRefinementScan(from: record)
        try await waitUntil { !viewModel.isStagingRefinement }

        XCTAssertEqual(viewModel.baseRefinementContext?.scanId, record.id)
        XCTAssertEqual(viewModel.requestedCaptureMode, CaptureMode.describe)
        XCTAssertEqual(viewModel.stagedCapture.images.count, 1)
        XCTAssertEqual(viewModel.stagedCapture.images.first?.compressedData, expectedCompressedData)
        XCTAssertEqual(viewModel.stagedCapture.images.first?.displayData, expectedDisplaySignature)
    }

    func testRefinementWithoutFunctionalProOpensSoftPaywall() {
        RevenueCatManager.shared.isSubscribed = false
        RevenueCatManager.shared.isProActive = false
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        let record = LocalScanRecord(
            speciesId: "paywall-species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly"
        )

        viewModel.startRefinementScan(from: record)

        XCTAssertEqual(viewModel.activeSheet, .paywall)
        XCTAssertNil(viewModel.baseRefinementContext)
        XCTAssertNil(viewModel.requestedCaptureMode)
    }

    func testDailyQuotaPaywallRequestReplacesInsightSheet() {
        let diContainer = AppDIContainer.preview
        let previousPaywallRequest = diContainer.usageManager.showPaywall
        defer {
            diContainer.usageManager.showPaywall = previousPaywallRequest
        }
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .insight
        )
        diContainer.usageManager.showPaywall = true

        viewModel.handlePaywallPresentationRequest(
            isRequested: diContainer.usageManager.showPaywall
        )

        XCTAssertFalse(diContainer.usageManager.showPaywall)
        XCTAssertNil(viewModel.activeSheet)
        XCTAssertTrue(viewModel.isRootPresentationDismissing)

        viewModel.handleRootSheetDismissed()

        XCTAssertEqual(viewModel.activeSheet, .paywall)
        XCTAssertFalse(viewModel.isRootPresentationDismissing)
    }

    func testPersistedMultiCapturePreferenceIsLockedWithoutFunctionalPro() {
        RevenueCatManager.shared.isSubscribed = false
        RevenueCatManager.shared.isProActive = false
        let diContainer = AppDIContainer.preview
        diContainer.appSettings.isMultiCaptureEnabled = true
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )

        XCTAssertFalse(viewModel.isMultiCaptureFunctionallyEnabled)
        XCTAssertEqual(viewModel.stagedCaptureLimit, 1)
    }

    func testStartRefinementScanWithRemoteImageEntersReanalysisFlow() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        viewModel.activeSheet = .insight

        let media = CapturedMediaSnapshot(items: [
            .image(.remoteURL("https://example.com/historical-scan.jpg"))
        ])
        let record = LocalScanRecord(
            speciesId: "remote-image-species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            capturedMediaJSON: media.jsonString
        )

        viewModel.startRefinementScan(from: record)

        XCTAssertNil(viewModel.activeSheet)
        XCTAssertEqual(viewModel.baseRefinementContext?.scanId, record.id)
        XCTAssertEqual(viewModel.requestedCaptureMode, .describe)
        XCTAssertTrue(viewModel.describePromptFlow.isReanalysis)
        viewModel.cancelRefinementStaging()
    }

    func testStartRefinementScanWithMultipleImagesStagesFirstAndEntersReanalysisFlow() async throws {
        let firstFileName = "historical-refinement-first-\(UUID().uuidString).png"
        let secondFileName = "historical-refinement-second-\(UUID().uuidString).png"
        let firstFileURL = URL.documentsDirectory.appendingPathComponent(firstFileName)
        let secondFileURL = URL.documentsDirectory.appendingPathComponent(secondFileName)
        try makePNGData(color: .systemGreen).write(to: firstFileURL)
        try makePNGData(color: .systemOrange).write(to: secondFileURL)
        defer {
            try? FileManager.default.removeItem(at: firstFileURL)
            try? FileManager.default.removeItem(at: secondFileURL)
        }
        let previewImage = SendableCGImage(image: makePreviewCGImage())

        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { request in
                PreparedStagedImage(
                    compressedData: Data(request.fileURL.lastPathComponent.utf8),
                    displayData: Data(request.fileURL.path.utf8),
                    historicalContext: request.historicalContext,
                    previewCGImage: previewImage
                )
            },
            prewarmHeadersOnInit: false
        )
        viewModel.activeSheet = .insight

        let media = CapturedMediaSnapshot(items: [
            .image(.documents(firstFileName)),
            .image(.documents(secondFileName))
        ])
        let record = LocalScanRecord(
            speciesId: "multi-image-species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            capturedMediaJSON: media.jsonString
        )

        viewModel.startRefinementScan(from: record)
        try await waitUntil { !viewModel.isStagingRefinement }

        XCTAssertNil(viewModel.activeSheet)
        XCTAssertEqual(viewModel.baseRefinementContext?.scanId, record.id)
        XCTAssertEqual(viewModel.requestedCaptureMode, .describe)
        XCTAssertTrue(viewModel.describePromptFlow.isReanalysis)
        XCTAssertEqual(viewModel.stagedCapture.images.count, 1)
        XCTAssertEqual(
            viewModel.stagedCapture.images.first?.compressedData,
            Data(firstFileName.utf8)
        )
    }

    func testStartRefinementScanSkipsUnusableImageAndStagesNextCandidate() async throws {
        let firstFileName = "historical-refinement-unusable-\(UUID().uuidString).png"
        let secondFileName = "historical-refinement-usable-\(UUID().uuidString).png"
        let firstFileURL = URL.documentsDirectory.appendingPathComponent(firstFileName)
        let secondFileURL = URL.documentsDirectory.appendingPathComponent(secondFileName)
        try makePNGData(color: .systemGreen).write(to: firstFileURL)
        try makePNGData(color: .systemOrange).write(to: secondFileURL)
        defer {
            try? FileManager.default.removeItem(at: firstFileURL)
            try? FileManager.default.removeItem(at: secondFileURL)
        }
        let previewImage = SendableCGImage(image: makePreviewCGImage())

        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { request in
                guard request.fileURL.lastPathComponent == secondFileName else {
                    return nil
                }
                return PreparedStagedImage(
                    compressedData: Data(secondFileName.utf8),
                    displayData: Data(request.fileURL.path.utf8),
                    historicalContext: request.historicalContext,
                    previewCGImage: previewImage
                )
            },
            prewarmHeadersOnInit: false
        )
        let media = CapturedMediaSnapshot(items: [
            .image(.documents(firstFileName)),
            .image(.documents(secondFileName))
        ])
        let record = LocalScanRecord(
            speciesId: "fallback-image-species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            capturedMediaJSON: media.jsonString
        )

        viewModel.startRefinementScan(from: record)
        try await waitUntil { !viewModel.isStagingRefinement }

        XCTAssertEqual(viewModel.stagedCapture.images.count, 1)
        XCTAssertEqual(
            viewModel.stagedCapture.images.first?.compressedData,
            Data(secondFileName.utf8)
        )
    }

    func testStartRefinementScanMaterializesRemoteAudioBeforeStaging() async throws {
        let preparedFileName = "historical-refinement-\(UUID().uuidString).wav"
        let preparedURL = URL.documentsDirectory.appendingPathComponent(preparedFileName)
        try makeInferenceTestPCM16WAVData(
            sampleRate: 44_100,
            channels: 1
        ).write(to: preparedURL)
        defer { try? FileManager.default.removeItem(at: preparedURL) }

        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            preparedHistoricalAudioLoader: { reference in
                guard reference.isRemote else { return nil }
                return preparedURL
            },
            prewarmHeadersOnInit: false
        )
        let media = CapturedMediaSnapshot(items: [
            .image(.documents("missing-historical-image-\(UUID().uuidString).png")),
            .audio(.remoteURL("https://media.merian.app/historical-call.m4a"))
        ])
        let record = LocalScanRecord(
            speciesId: "audio-species",
            scientificName: "Strix varia",
            commonName: "Barred Owl",
            capturedMediaJSON: media.jsonString
        )

        viewModel.startRefinementScan(from: record)
        try await waitUntil { !viewModel.isStagingRefinement }

        XCTAssertEqual(viewModel.stagedCapture.audios.count, 1)
        XCTAssertEqual(viewModel.stagedCapture.audios.first?.filePath, preparedFileName)
        XCTAssertFalse(viewModel.stagedCapture.audios.first?.filePath.hasPrefix("https://") == true)
    }

    func testStartRefinementScanUsesLegacyVideoCompanionAudioFallback() async throws {
        let preparedFileName = "historical-refinement-\(UUID().uuidString).wav"
        let preparedURL = URL.documentsDirectory.appendingPathComponent(preparedFileName)
        try makeInferenceTestPCM16WAVData(
            sampleRate: 44_100,
            channels: 1
        ).write(to: preparedURL)
        defer { try? FileManager.default.removeItem(at: preparedURL) }

        let companionReference = StoredMediaReference.remoteURL(
            "https://media.merian.app/historical-video-companion.m4a"
        )
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            preparedHistoricalAudioLoader: { reference in
                guard reference == companionReference else { return nil }
                return preparedURL
            },
            prewarmHeadersOnInit: false
        )
        let media = CapturedMediaSnapshot(items: [
            .video(StoredVideoMediaReference(
                video: .remoteURL("https://media.merian.app/historical-video.mp4"),
                audio: companionReference
            ))
        ])
        let record = LocalScanRecord(
            speciesId: "video-audio-species",
            scientificName: "Strix varia",
            commonName: "Barred Owl",
            capturedMediaJSON: media.jsonString
        )

        viewModel.startRefinementScan(from: record)
        try await waitUntil { !viewModel.isStagingRefinement }

        XCTAssertEqual(viewModel.stagedCapture.audios.count, 1)
        XCTAssertEqual(viewModel.stagedCapture.audios.first?.filePath, preparedFileName)
    }

    func testStartRefinementScanFallsBackToDescriptionWhenHistoricalAudioCannotBePrepared() async throws {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            preparedHistoricalAudioLoader: { _ in
                throw InferenceAudioPreparationError.sourceUnavailable
            },
            prewarmHeadersOnInit: false
        )
        let fallbackText = "A clear two-note hoot repeated from the oak canopy."
        let media = CapturedMediaSnapshot(items: [
            .audio(.remoteURL("https://media.merian.app/missing-call.m4a")),
            .description(ObservationContext(freeText: fallbackText))
        ])
        let record = LocalScanRecord(
            speciesId: "audio-fallback-species",
            scientificName: "Strix varia",
            commonName: "Barred Owl",
            capturedMediaJSON: media.jsonString
        )

        viewModel.startRefinementScan(from: record)
        try await waitUntil { !viewModel.isStagingRefinement }

        XCTAssertTrue(viewModel.stagedCapture.audios.isEmpty)
        XCTAssertEqual(
            viewModel.stagedCapture.observationContexts.first?.context.freeText,
            fallbackText
        )
    }

    func testStartRefinementScanPreselectsDescribeSubjectFromOriginalScan() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )

        let record = LocalScanRecord(
            speciesId: "original-species-id",
            scientificName: "Epipremnum aureum",
            commonName: "Golden Pothos",
            semanticTags: ["Houseplants"]
        )

        viewModel.startRefinementScan(from: record)

        XCTAssertEqual(viewModel.refinementSubjectId, "subj_plan")
        XCTAssertEqual(viewModel.describePromptFlow, .reanalysis(subjectId: "subj_plan"))
    }

    func testNonBiologicalCorrectionRefinementContextDoesNotMutateOriginalScan() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )

        let record = LocalScanRecord(
            speciesId: "object-1",
            scientificName: "Inanimate Object",
            commonName: "Sticker",
            capturedMediaJSON: #"[]"#,
            coverImagePath: "/tmp/original.jpg",
            isBiological: false,
            confidenceScore: 1.0,
            userReviewStateRaw: UserReviewState.unreviewed.rawValue
        )

        viewModel.startRefinementScan(
            from: record,
            initialDescription: "This should not prefill Describe.",
            entryPoint: .nonBiologicalCorrection
        )

        XCTAssertEqual(viewModel.baseRefinementContext?.scanId, record.id)
        XCTAssertEqual(viewModel.baseRefinementContext?.entryPoint, .nonBiologicalCorrection)
        XCTAssertNil(viewModel.refinementInitialDescriptionDraft)
        XCTAssertEqual(viewModel.requestedCaptureMode, .describe)
        XCTAssertFalse(record.isBiological)
        XCTAssertEqual(record.scientificName, "Inanimate Object")
        XCTAssertEqual(record.commonName, "Sticker")
        XCTAssertEqual(record.confidenceScore, 1.0)
        XCTAssertEqual(record.coverImagePath, "/tmp/original.jpg")
    }

    func testNonBiologicalCorrectionEntryPointIsLimitedToNonBiologicalScans() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )

        let biologicalRecord = LocalScanRecord(
            speciesId: "species-allowed-only-through-standard",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            isBiological: true
        )

        viewModel.startRefinementScan(from: biologicalRecord, entryPoint: .nonBiologicalCorrection)

        XCTAssertNil(viewModel.baseRefinementContext)
        XCTAssertNil(viewModel.requestedCaptureMode)
    }

    func testStartRefinementScanClearsLoadingStateWhenPreparationFails() async throws {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )

        let record = LocalScanRecord(
            speciesId: "species-2",
            scientificName: "Quercus alba",
            commonName: "White Oak",
            coverImagePath: "missing-refinement.webp"
        )

        viewModel.startRefinementScan(from: record)
        try await waitUntil { !viewModel.isStagingRefinement }

        XCTAssertEqual(viewModel.baseRefinementContext?.scanId, record.id)
        XCTAssertTrue(viewModel.stagedCapture.images.isEmpty)
        XCTAssertEqual(viewModel.requestedCaptureMode, CaptureMode.describe)
    }

    func testMediaModeToggleRemainsVisibleWhenRefinementStagingIsFull() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        let uiImage = makeUIImage()

        let record = LocalScanRecord(
            speciesId: "species-3",
            scientificName: "Bubo virginianus",
            commonName: "Great Horned Owl"
        )
        viewModel.baseRefinementContext = RefinementScanContext(record: record)
        viewModel.stagedCapture.images = [
            StagedImage(
                compressedData: makePNGData(),
                displayData: makePNGData(color: .systemBlue),
                uiImage: uiImage,
                original: IdentifiableImage(image: uiImage)
            )
        ]
        viewModel.stagedCapture.observationContexts = [
            StagedObservationContext(context: ObservationContext(freeText: "Perched in a bare tree"))
        ]

        XCTAssertFalse(viewModel.hasAvailableStagedCaptureSlot)
        XCTAssertTrue(viewModel.shouldShowMediaModeToggle)
    }

    func testMediaModeToggleStillHidesAtCapacityOutsideRefinement() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )

        viewModel.stagedCapture.observationContexts = [
            StagedObservationContext(context: ObservationContext(freeText: "First note"))
        ]

        XCTAssertFalse(viewModel.hasAvailableStagedCaptureSlot)
        XCTAssertFalse(viewModel.shouldShowMediaModeToggle)
    }

}
