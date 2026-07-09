import CoreData
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Merian

@MainActor
final class CaptureWorkspaceViewModelRefinementTests: XCTestCase {
    private func makePNGData(color: UIColor = .systemTeal) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    private func makePreviewCGImage(color: UIColor = .systemTeal) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return image.cgImage ?? UIImage(systemName: "photo")!.cgImage!
    }

    private func makeUIImage(color: UIColor = .systemTeal) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    private func makePreparedStagedImage(color: UIColor = .systemTeal) -> PreparedStagedImage {
        PreparedStagedImage(
            compressedData: makePNGData(color: color),
            displayData: makePNGData(color: .systemBlue),
            historicalContext: nil,
            previewCGImage: SendableCGImage(image: makePreviewCGImage(color: color))
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollingIntervalNanoseconds: UInt64 = 10_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        var elapsed: UInt64 = 0

        while elapsed < timeoutNanoseconds {
            if condition() {
                return
            }

            try await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
            elapsed += pollingIntervalNanoseconds
        }

        XCTFail("Timed out waiting for refinement staging to settle")
    }

    private func makeModelContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func enableUnlimitedFreeScansForTest() {
        let deviceId = DeviceIdentityManager.shared.deviceId
        UserDefaults.standard.removeObject(forKey: "Merian_LastScanDate_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "Merian_ScansUsedToday_\(deviceId)")
        UsageManager.debugFreeScanLimitOverride = true
        UsageManager.shared.evaluateDailyRefresh()
    }

    private func restoreFreeScanLimitForTest() {
        let deviceId = DeviceIdentityManager.shared.deviceId
        UserDefaults.standard.removeObject(forKey: "Merian_LastScanDate_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "Merian_ScansUsedToday_\(deviceId)")
        UsageManager.debugFreeScanLimitOverride = nil
        UsageManager.shared.evaluateDailyRefresh()
    }

    private func makeTempAudioFilename(prefix: String = "capture_vm_audio") throws -> String {
        let filename = "\(prefix)_\(UUID().uuidString).wav"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try Data(repeating: 0x4D, count: 128).write(to: url)
        return filename
    }

    private func makeTempVideoFilename(prefix: String = "capture_vm_video") throws -> String {
        let filename = "\(prefix)_\(UUID().uuidString).mp4"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try Data(repeating: 0x56, count: 256).write(to: url)
        return filename
    }

    private func cleanupQueuedScans(in context: ModelContext) {
        let scans = (try? context.fetch(FetchDescriptor<OfflineQueuedScan>())) ?? []
        for scan in scans {
            for item in scan.capturedMediaSnapshot.items {
                switch item {
                case .image(let reference), .audio(let reference):
                    if let targetURL = reference.resolvedURL {
                        try? FileManager.default.removeItem(at: targetURL)
                    }
                case .video(let reference):
                    for mediaReference in [reference.video, reference.thumbnail, reference.audio].compactMap({ $0 }) {
                        if let targetURL = mediaReference.resolvedURL {
                            try? FileManager.default.removeItem(at: targetURL)
                        }
                    }
                case .description:
                    break
                }
            }
            context.delete(scan)
        }
        do {
            try context.save()
        } catch {
            XCTFail("Failed to persist queued-scan cleanup in test context: \(error)")
        }
    }

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

    func testViewfinderHintsHideAfterSingleScanContentIsStaged() {
        let diContainer = AppDIContainer.preview
        diContainer.appSettings.isMultiCaptureEnabled = false
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        let uiImage = makeUIImage()

        viewModel.stagedCapture.images = [
            StagedImage(
                compressedData: makePNGData(),
                displayData: makePNGData(color: .systemBlue),
                uiImage: uiImage,
                original: IdentifiableImage(image: uiImage)
            )
        ]

        XCTAssertFalse(viewModel.hasAvailableStagedCaptureSlot)
        XCTAssertFalse(viewModel.shouldShowViewfinderHints)
    }

    func testViewfinderHintsHideWhenMultiScanStagingIsFull() {
        let diContainer = AppDIContainer.preview
        diContainer.appSettings.isMultiCaptureEnabled = true
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        let uiImage = makeUIImage()

        viewModel.stagedCapture.images = [
            StagedImage(
                compressedData: makePNGData(),
                displayData: makePNGData(color: .systemBlue),
                uiImage: uiImage,
                original: IdentifiableImage(image: uiImage)
            )
        ]
        viewModel.stagedCapture.observationContexts = [
            StagedObservationContext(context: ObservationContext(freeText: "Second staged note"))
        ]

        XCTAssertFalse(viewModel.hasAvailableStagedCaptureSlot)
        XCTAssertFalse(viewModel.shouldShowViewfinderHints)
    }

    func testActiveToolbarSubmissionStagesPendingDescribeDraft() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        viewModel.baseRefinementContext = RefinementScanContext(
            record: LocalScanRecord(
                speciesId: "species-reanalysis",
                scientificName: "Danaus plexippus",
                commonName: "Monarch Butterfly"
            )
        )
        let uiImage = makeUIImage()
        viewModel.stagedCapture.images = [
            StagedImage(
                compressedData: makePNGData(),
                displayData: makePNGData(color: .systemBlue),
                uiImage: uiImage,
                original: IdentifiableImage(image: uiImage)
            )
        ]

        XCTAssertTrue(
            viewModel.stagePendingDescribeDraftForActiveSubmission(
                ObservationContext(freeText: "Small green subject on concrete")
            )
        )

        XCTAssertEqual(viewModel.stagedCapture.observationContexts.count, 1)
        XCTAssertEqual(
            viewModel.stagedCapture.observationContexts.first?.context.freeText,
            "Small green subject on concrete"
        )
    }

    func testActiveToolbarSubmissionReplacesExistingStagedDescribeDraft() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        let uiImage = makeUIImage()
        viewModel.stagedCapture.images = [
            StagedImage(
                compressedData: makePNGData(),
                displayData: makePNGData(color: .systemBlue),
                uiImage: uiImage,
                original: IdentifiableImage(image: uiImage)
            )
        ]
        viewModel.stagedCapture.observationContexts = [
            StagedObservationContext(context: ObservationContext(freeText: "Previous draft"))
        ]

        XCTAssertTrue(
            viewModel.stagePendingDescribeDraftForActiveSubmission(
                ObservationContext(freeText: "Fresh draft for this analysis")
            )
        )

        XCTAssertEqual(viewModel.stagedCapture.observationContexts.count, 1)
        XCTAssertEqual(
            viewModel.stagedCapture.observationContexts.first?.context.freeText,
            "Fresh draft for this analysis"
        )
    }

    func testPhotoLibraryPreparedImageRequiresCropAndPresentsCropSheet() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )

        viewModel.commitPreparedStagedImages([makePreparedStagedImage()], requiresCrop: true)

        let stagedImage = viewModel.stagedCapture.images.first
        XCTAssertEqual(viewModel.stagedCapture.images.count, 1)
        XCTAssertTrue(viewModel.hasPendingRequiredGalleryCrop)
        XCTAssertEqual(viewModel.imageToCrop?.id, stagedImage?.original.id)
        XCTAssertTrue(viewModel.isRequiredGalleryCrop(stagedImage?.original.id ?? UUID()))
    }

    func testPreparedImageWithoutRequiredCropDoesNotPresentCropSheet() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )

        viewModel.commitPreparedStagedImages([makePreparedStagedImage()])

        XCTAssertEqual(viewModel.stagedCapture.images.count, 1)
        XCTAssertFalse(viewModel.hasPendingRequiredGalleryCrop)
        XCTAssertNil(viewModel.imageToCrop)
    }

    func testCancelingRequiredGalleryCropRemovesImageAndClearsCropState() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        viewModel.commitPreparedStagedImages([makePreparedStagedImage()], requiresCrop: true)
        let imageId = try! XCTUnwrap(viewModel.stagedCapture.images.first?.original.id)

        viewModel.cancelRequiredGalleryCrop(for: imageId)

        XCTAssertTrue(viewModel.stagedCapture.images.isEmpty)
        XCTAssertFalse(viewModel.hasPendingRequiredGalleryCrop)
        XCTAssertNil(viewModel.imageToCrop)
        XCTAssertNil(viewModel.editingCropIndex)
    }

    func testCompletingRequiredGalleryCropAllowsAutoSubmitOnlyWhenExistingRulesAllow() {
        let autoSubmitContainer = AppDIContainer.preview
        autoSubmitContainer.appSettings.requiresScanConfirmation = false
        autoSubmitContainer.appSettings.isMultiCaptureEnabled = false
        let autoSubmitViewModel = CaptureWorkspaceViewModel(
            diContainer: autoSubmitContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        autoSubmitViewModel.commitPreparedStagedImages([makePreparedStagedImage()], requiresCrop: true)
        let autoSubmitImageId = try! XCTUnwrap(autoSubmitViewModel.stagedCapture.images.first?.original.id)

        XCTAssertTrue(autoSubmitViewModel.completeRequiredGalleryCrop(for: autoSubmitImageId))

        let confirmationContainer = AppDIContainer.preview
        confirmationContainer.appSettings.requiresScanConfirmation = true
        confirmationContainer.appSettings.isMultiCaptureEnabled = false
        let confirmationViewModel = CaptureWorkspaceViewModel(
            diContainer: confirmationContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        confirmationViewModel.commitPreparedStagedImages([makePreparedStagedImage()], requiresCrop: true)
        let confirmationImageId = try! XCTUnwrap(confirmationViewModel.stagedCapture.images.first?.original.id)

        XCTAssertFalse(confirmationViewModel.completeRequiredGalleryCrop(for: confirmationImageId))
    }

    func testExploreDeepLinkSurvivesImmediateSessionTimeoutReset() async throws {
        let postId = "widget-post-123"
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )

        AppEventPublisher.shared.send(.appDidEnterActivePhaseWithExplorePost(postId: postId, targetCommentId: nil, targetReplyParentCommentId: nil))
        try await waitUntil {
            viewModel.activeSheet == .explore && viewModel.pendingExplorePostId == postId
        }

        AppEventPublisher.shared.send(.appDidResumeAfterTimeout)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.activeSheet, .explore)
        XCTAssertEqual(viewModel.pendingExplorePostId, postId)
    }

    func testSessionTimeoutResetClearsStaleExploreRoute() async throws {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        viewModel.pendingExplorePostId = "stale-post"
        viewModel.activeSheet = .explore

        AppEventPublisher.shared.send(.appDidResumeAfterTimeout)

        try await waitUntil {
            viewModel.activeSheet == nil && viewModel.pendingExplorePostId == nil
        }
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

        viewModel.submitStagedCapture(modelContext: modelContext)

        try await waitUntil { viewModel.offlineToastMessage == "No network connection. Queued for upload." }
        XCTAssertFalse(diContainer.inferenceEngine.isProcessing)
        XCTAssertNil(viewModel.activeSheet)
    }

    func testOfflineVisualQueueFailureDiscardsStagedVideoFiles() async throws {
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
        viewModel.stagedCapture.videos = [
            StagedVideo(
                filePath: videoFilename,
                sampledImages: [stagedFrame],
                audioFilePath: audioFilename
            )
        ]

        viewModel.submitStagedCapture(modelContext: modelContext)

        try await waitUntil { viewModel.offlineToastMessage == "Unable to save capture. Please try again." }
        try await waitUntil {
            !FileManager.default.fileExists(atPath: videoURL.path)
                && !FileManager.default.fileExists(atPath: audioURL.path)
        }

        XCTAssertFalse(diContainer.inferenceEngine.isProcessing)
        XCTAssertNil(viewModel.activeSheet)
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

        viewModel.submitNonVisualCapture(
            audioFileNames: [audioFilename],
            observationContexts: [],
            mediaTimeline: [.audio(audioFilename)],
            modelContext: modelContext
        )

        try await waitUntil { viewModel.offlineToastMessage == "No network connection. Queued for analysis." }
        XCTAssertFalse(diContainer.inferenceEngine.isProcessing)
        XCTAssertNil(viewModel.activeSheet)

        let queuedScans = try modelContext.fetch(FetchDescriptor<OfflineQueuedScan>())
        XCTAssertEqual(queuedScans.count, 1)
        XCTAssertEqual(queuedScans.first?.queueState, .pending)
    }

    func testMultiCaptureDescribeStagesUntilIdentify() throws {
        let diContainer = AppDIContainer.preview
        diContainer.appSettings.isMultiCaptureEnabled = true
        diContainer.appSettings.requiresScanConfirmation = false
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        let modelContext = try makeModelContext()

        XCTAssertTrue(
            viewModel.submitDescribe(
                observationContext: ObservationContext(freeText: "First staged description"),
                modelContext: modelContext
            )
        )

        viewModel.stagedCapture.lastSubmitTime = nil

        XCTAssertTrue(
            viewModel.submitDescribe(
                observationContext: ObservationContext(freeText: "Second staged description"),
                modelContext: modelContext
            )
        )

        XCTAssertEqual(viewModel.stagedCapture.observationContexts.count, 2)
        XCTAssertNil(viewModel.activeSheet)
    }
}

@MainActor
final class ExploreLocationPrivacyTests: XCTestCase {
    func testDisplayLabelKeepsCityAndStateFromExactAddress() {
        XCTAssertEqual(
            ExploreLocationPrivacy.displayLabel(from: "123 Main St, Austin, TX, United States"),
            "Austin, TX"
        )
        XCTAssertEqual(
            ExploreLocationPrivacy.displayLabel(from: "Austin, Travis County, TX, United States"),
            "Austin, TX"
        )
        XCTAssertEqual(
            ExploreLocationPrivacy.displayLabel(from: "123 Main St, Austin, TX 78701, United States"),
            "Austin, TX"
        )
        XCTAssertEqual(
            ExploreLocationPrivacy.displayLabel(from: "123 Main St, Austin, Texas 78701, United States"),
            "Austin, TX"
        )
        XCTAssertEqual(
            ExploreLocationPrivacy.displayLabel(from: "123 Main St, Austin, TX 78701 United States"),
            "Austin, TX"
        )
    }

    func testDisplayLabelFallsBackToStateForLandmarkAndSingleState() {
        XCTAssertEqual(ExploreLocationPrivacy.displayLabel(from: "Central Park, NY"), "New York")
        XCTAssertEqual(ExploreLocationPrivacy.displayLabel(from: "Little Sarasota Bay, FL"), "Florida")
        XCTAssertEqual(ExploreLocationPrivacy.displayLabel(from: "FL"), "Florida")
        XCTAssertEqual(ExploreLocationPrivacy.displayLabel(from: "California"), "California")
    }

    func testDisplayLabelKeepsSafeCityOnlyHistoricalLabels() {
        XCTAssertEqual(ExploreLocationPrivacy.displayLabel(from: "Austin"), "Austin")
    }

    func testDisplayLabelSuppressesCoordinatesAndSmallSiteLabels() {
        XCTAssertNil(ExploreLocationPrivacy.displayLabel(from: "30.2672, -97.7431"))
        XCTAssertNil(ExploreLocationPrivacy.displayLabel(from: "Zilker Park"))
        XCTAssertNil(ExploreLocationPrivacy.displayLabel(from: "Little Sarasota Bay"))
    }
}

@MainActor
final class ExploreAuthorDisplayNameTests: XCTestCase {
    func testDisplayNameRemovesTrailingLastInitialOnly() {
        XCTAssertEqual(ExplorePost.publicAuthorDisplayName(from: "River W."), "River")
        XCTAssertEqual(ExplorePost.publicAuthorDisplayName(from: "Mary Jane W."), "Mary Jane")
        XCTAssertEqual(ExplorePost.publicAuthorDisplayName(from: "Moss Walker"), "Moss Walker")
    }

    func testPreferUsernameUsesHandleWhenAvailable() {
        XCTAssertEqual(
            ExplorePost.publicAuthorDisplayName(
                from: "River W.",
                username: "river_w",
                preferUsername: true
            ),
            "@river_w"
        )
    }

    func testDefaultDisplayNameStillPrefersPublicName() {
        XCTAssertEqual(
            ExplorePost.publicAuthorDisplayName(from: "River W.", username: "river_w"),
            "River"
        )
    }

    func testPreferUsernameFallsBackToPublicNameWhenMissingOrBlank() {
        XCTAssertEqual(
            ExplorePost.publicAuthorDisplayName(
                from: "River W.",
                username: nil,
                preferUsername: true
            ),
            "River"
        )
        XCTAssertEqual(
            ExplorePost.publicAuthorDisplayName(
                from: "River W.",
                username: "   ",
                preferUsername: true
            ),
            "River"
        )
    }

    func testUsernameDisplayTrimsWhitespaceAndAddsAtPrefixOnce() {
        XCTAssertEqual(ExplorePost.publicUsernameDisplayValue(" river_w "), "@river_w")
        XCTAssertEqual(ExplorePost.publicUsernameDisplayValue("@river_w"), "@river_w")
    }

    func testCommentDisplayNamePrefersUsernameWhenAvailable() {
        let comment = ExploreComment(
            commentId: "comment-123",
            postId: "post-123",
            parentCommentId: nil,
            authorUserId: "author-123",
            authorName: "River W.",
            authorUsername: "river_w",
            authorAvatarUrl: nil,
            body: "Beautiful find.",
            createdAt: "2026-06-15T10:00:00.000Z",
            viewerCanDelete: false,
            viewerCanModerate: false,
            viewerCanReport: true,
            replyCount: nil,
            reactions: nil,
            mentions: nil
        )

        XCTAssertEqual(comment.displayAuthorName, "@river_w")
    }

    func testReactionToggleAddsNewViewerReaction() {
        let updatedComment = makeComment(reactions: nil)
            .applyingReactionToggle(emoji: "\u{1F44D}")

        XCTAssertEqual(updatedComment.reactions?.count, 1)
        XCTAssertEqual(updatedComment.reactions?.first?.emoji, "\u{1F44D}")
        XCTAssertEqual(updatedComment.reactions?.first?.count, 1)
        XCTAssertEqual(updatedComment.reactions?.first?.viewerHasReacted, true)
    }

    func testReactionToggleIncrementsInactiveReaction() {
        let updatedComment = makeComment(
            reactions: [
                ExploreCommentReaction(emoji: "\u{1F44D}", count: 2, viewerHasReacted: false)
            ]
        )
        .applyingReactionToggle(emoji: "\u{1F44D}")

        XCTAssertEqual(updatedComment.reactions?.first?.count, 3)
        XCTAssertEqual(updatedComment.reactions?.first?.viewerHasReacted, true)
    }

    func testReactionToggleRemovesLastActiveReaction() {
        let updatedComment = makeComment(
            reactions: [
                ExploreCommentReaction(emoji: "\u{1F44D}", count: 1, viewerHasReacted: true)
            ]
        )
        .applyingReactionToggle(emoji: "\u{1F44D}")

        XCTAssertEqual(updatedComment.reactions?.isEmpty, true)
    }

    func testReactionToggleDecrementsActiveMultiCountReaction() {
        let updatedComment = makeComment(
            reactions: [
                ExploreCommentReaction(emoji: "\u{1F44D}", count: 3, viewerHasReacted: true)
            ]
        )
        .applyingReactionToggle(emoji: "\u{1F44D}")

        XCTAssertEqual(updatedComment.reactions?.first?.count, 2)
        XCTAssertEqual(updatedComment.reactions?.first?.viewerHasReacted, false)
    }

    private func makeComment(reactions: [ExploreCommentReaction]?) -> ExploreComment {
        ExploreComment(
            commentId: "comment-123",
            postId: "post-123",
            parentCommentId: nil,
            authorUserId: "author-123",
            authorName: "River W.",
            authorUsername: "river_w",
            authorAvatarUrl: nil,
            body: "Beautiful find.",
            createdAt: "2026-06-15T10:00:00.000Z",
            viewerCanDelete: false,
            viewerCanModerate: false,
            viewerCanReport: true,
            replyCount: nil,
            reactions: reactions,
            mentions: nil
        )
    }
}

@MainActor
final class ExploreMapViewModelSelectionTests: XCTestCase {
    private func makeMapPost(id: String, latitude: Double) -> ExploreMapPost {
        ExploreMapPost(
            postId: id,
            scanId: "scan-\(id)",
            latitude: latitude,
            longitude: -97.743,
            coordinateVisibility: .exact,
            heroImageUrl: "https://example.com/\(id).jpg",
            sharedAt: "2026-05-05T12:00:00Z",
            authorUserId: "author-\(id)",
            authorName: "Test Author",
            authorUsername: nil,
            authorAvatarUrl: nil,
            authorIsPro: nil,
            speciesCommonName: "Monarch Butterfly",
            speciesScientificName: "Danaus plexippus",
            petIdentification: nil,
            taxonomyKingdom: "Animalia",
            taxonomyClass: "Insecta",
            publicLocationLabel: "Austin, TX",
            locationSharing: nil,
            timeOfDay: nil,
            currentMonth: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false,
            isOwnedByViewer: false
        )
    }

    func testSelectAdjacentPostAdvancesThroughCurrentMapOrder() {
        let viewModel = ExploreMapViewModel()
        let newest = makeMapPost(id: "newest", latitude: 30.267)
        let middle = makeMapPost(id: "middle", latitude: 30.268)
        let oldest = makeMapPost(id: "oldest", latitude: 30.269)

        viewModel.posts = [newest, middle, oldest]
        viewModel.selectPost(newest.id)

        XCTAssertEqual(viewModel.selectAdjacentPost(by: 1)?.id, middle.id)
        XCTAssertEqual(viewModel.selectedPostId, middle.id)
        XCTAssertEqual(viewModel.selectAdjacentPost(by: 1)?.id, oldest.id)
        XCTAssertEqual(viewModel.selectedPostId, oldest.id)
    }

    func testSelectAdjacentPostWrapsForwardToBeginning() {
        let viewModel = ExploreMapViewModel()
        let first = makeMapPost(id: "first", latitude: 30.267)
        let second = makeMapPost(id: "second", latitude: 30.268)

        viewModel.posts = [first, second]
        viewModel.selectPost(second.id)

        XCTAssertEqual(viewModel.selectAdjacentPost(by: 1)?.id, first.id)
        XCTAssertEqual(viewModel.selectedPostId, first.id)
    }

    func testSelectAdjacentPostWrapsBackwardToEnd() {
        let viewModel = ExploreMapViewModel()
        let first = makeMapPost(id: "first", latitude: 30.267)
        let second = makeMapPost(id: "second", latitude: 30.268)

        viewModel.posts = [first, second]
        viewModel.selectPost(first.id)

        XCTAssertEqual(viewModel.selectAdjacentPost(by: -1)?.id, second.id)
        XCTAssertEqual(viewModel.selectedPostId, second.id)
    }

    func testSelectAdjacentPostReturnsNilWhenOnlyOnePostExists() {
        let viewModel = ExploreMapViewModel()
        let onlyPost = makeMapPost(id: "only", latitude: 30.267)

        viewModel.posts = [onlyPost]
        viewModel.selectPost(onlyPost.id)

        XCTAssertNil(viewModel.selectAdjacentPost(by: 1))
        XCTAssertEqual(viewModel.selectedPostId, onlyPost.id)
    }

    func testOrderedMapPostsPutsSelectedPostAtEnd() {
        let viewModel = ExploreMapViewModel()
        let first = makeMapPost(id: "first", latitude: 30.267)
        let second = makeMapPost(id: "second", latitude: 30.268)
        let third = makeMapPost(id: "third", latitude: 30.269)

        viewModel.posts = [first, second, third]

        // When no post is selected, order is unchanged
        XCTAssertEqual(viewModel.orderedMapPosts.map(\.id), ["first", "second", "third"])

        // When a post is selected, it's moved to the end
        viewModel.selectPost("second")
        XCTAssertEqual(viewModel.orderedMapPosts.map(\.id), ["first", "third", "second"])

        // When selection is cleared, order is unchanged
        viewModel.selectPost(nil)
        XCTAssertEqual(viewModel.orderedMapPosts.map(\.id), ["first", "second", "third"])
    }
}

final class ExploreVideoPlaybackOverlayStateTests: XCTestCase {
    func testPlaybackUnavailableRestoresVisiblePlayControlAfterFadedAutoplay() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)

        state.reduce(.playbackUnavailable)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
    }

    func testCoordinatorPauseRestoresVisiblePlayControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)

        state.reduce(.playbackPaused)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
    }

    func testInterruptionAfterControlFadeRestoresVisiblePlayControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: true)
        state.reduce(.controlFadeCompleted)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)

        state.reduce(.playbackPaused)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
    }

    func testHiddenVideoTapRevealsControlsWhilePlaybackIsStillMarkedPlaying() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)

        state.reduce(.revealControls)

        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
    }

    func testAutoplayStartsWithoutShowingPlaybackControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: false, showsPlaybackControl: true)

        state.reduce(.autoplayStarted)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertTrue(state.isAutoplayControlSuppressed)
    }

    func testPlayerBecamePlayingPreservesHiddenControlsForLoopingPlayback() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)

        state.reduce(.playerBecamePlaying)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
    }

    func testPlayerBecamePlayingHidesStaleVisibleControlDuringHiddenAutoplay() {
        var state = ExploreVideoPlaybackOverlayState(
            isPlaying: true,
            showsPlaybackControl: true,
            isAutoplayControlSuppressed: true
        )

        state.reduce(.playerBecamePlaying)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertTrue(state.isAutoplayControlSuppressed)
    }

    func testRevealControlsClearsHiddenAutoplaySuppression() {
        var state = ExploreVideoPlaybackOverlayState(
            isPlaying: true,
            showsPlaybackControl: false,
            isAutoplayControlSuppressed: true
        )

        state.reduce(.revealControls)
        state.reduce(.playerBecamePlaying)

        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.isAutoplayControlSuppressed)
    }

    func testPlaybackWaitingDuringVisiblePlaybackStillAllowsFade() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: true)

        state.reduce(.playbackWaiting)
        state.reduce(.controlFadeCompleted)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
    }

    func testPlaybackWaitingBeforePlaybackKeepsPlayControlVisible() {
        var state = ExploreVideoPlaybackOverlayState(
            isPlaying: false,
            showsPlaybackControl: false,
            isAutoplayControlSuppressed: true
        )

        state.reduce(.playbackWaiting)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.isAutoplayControlSuppressed)
    }

    func testTemporaryPlayerPauseDuringHiddenAutoplayDoesNotRevealControl() {
        var state = ExploreVideoPlaybackOverlayState(
            isPlaying: true,
            showsPlaybackControl: false,
            isAutoplayControlSuppressed: true
        )

        state.reduce(.playbackTemporarilyPaused)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertTrue(state.isAutoplayControlSuppressed)
    }

    func testRecoveryRebuildCanResumeAutoplayWithoutVisibleControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)
        state.reduce(.playbackInterrupted)
        state.reduce(.recoveryRebuildCompleted)

        state.reduce(.autoplayStarted)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertTrue(state.isAutoplayControlSuppressed)
    }

    func testInterruptionMarksPlaybackRecoverableWithVisiblePlayControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)

        state.reduce(.playbackInterrupted)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertTrue(state.needsPlayerRebuildForRecovery)
    }

    func testPauseAfterInterruptionKeepsRecoveryRebuildRequired() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)
        state.reduce(.playbackInterrupted)

        state.reduce(.playbackPaused)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertTrue(state.needsPlayerRebuildForRecovery)
    }

    func testAutoplayFailureAfterRecoveryLeavesVisiblePlayControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)
        state.reduce(.playbackInterrupted)
        state.reduce(.recoveryRebuildCompleted)

        state.reduce(.playbackPaused)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertFalse(state.isAutoplayControlSuppressed)
    }

    func testSuccessfulRecoveryRebuildAndResumeClearsRecoveryState() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)
        state.reduce(.playbackInterrupted)

        state.reduce(.recoveryRebuildCompleted)
        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)

        state.reduce(.playbackStarted)
        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
    }

    func testHiddenUnhealthyTapRepairCanStartWithVisibleControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)
        state.reduce(.playbackInterrupted)
        state.reduce(.recoveryRebuildCompleted)

        state.reduce(.playbackStarted)

        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertFalse(state.isAutoplayControlSuppressed)
    }

    func testPausedRecoveryRebuildLeavesPlayControlVisible() {
        var state = ExploreVideoPlaybackOverlayState(
            isPlaying: false,
            showsPlaybackControl: false,
            needsPlayerRebuildForRecovery: true
        )

        state.reduce(.recoveryRebuildCompleted)
        state.reduce(.playbackPaused)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertFalse(state.isAutoplayControlSuppressed)
    }

    func testControlFadeOnlyHidesWhilePlaybackIsStillMarkedPlaying() {
        var pausedState = ExploreVideoPlaybackOverlayState(isPlaying: false, showsPlaybackControl: true)
        pausedState.reduce(.controlFadeCompleted)

        XCTAssertFalse(pausedState.isPlaying)
        XCTAssertTrue(pausedState.showsPlaybackControl)

        var playingState = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: true)
        playingState.reduce(.controlFadeCompleted)

        XCTAssertTrue(playingState.isPlaying)
        XCTAssertFalse(playingState.showsPlaybackControl)
    }

    func testControlFadeDoesNotHideControlsWhileRecoveryIsPending() {
        var state = ExploreVideoPlaybackOverlayState(
            isPlaying: true,
            showsPlaybackControl: true,
            needsPlayerRebuildForRecovery: true
        )

        state.reduce(.controlFadeCompleted)

        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertTrue(state.needsPlayerRebuildForRecovery)
    }
}

@MainActor
final class ExplorePostStoreMediaMergeTests: XCTestCase {
    func testUpsertPreservesExistingVideoMediaWhenRefreshOmitsMediaItems() {
        let store = ExplorePostStore()
        let videoItem = ExploreMediaItem(
            kind: .video,
            url: "https://media.example/video.mp4",
            thumbnailUrl: "https://media.example/poster.jpg",
            orderIndex: 0,
            durationSeconds: 4.2,
            hasAudio: true
        )

        store.upsert(makePost(mediaItems: [videoItem]), includeInFeed: true)
        store.upsert(makePost(mediaItems: nil))

        XCTAssertEqual(store.post(id: "post-1")?.resolvedMediaItems, [videoItem])
    }

    func testUpsertPreservesExistingVideoMediaWhenRefreshUsesEmptyMediaItems() {
        let store = ExplorePostStore()
        let videoItem = ExploreMediaItem(
            kind: .video,
            url: "https://media.example/video.mp4",
            thumbnailUrl: "https://media.example/poster.jpg",
            orderIndex: 0,
            durationSeconds: 4.2,
            hasAudio: true
        )

        store.upsert(makePost(mediaItems: [videoItem]), includeInFeed: true)
        store.upsert(makePost(mediaItems: []))

        XCTAssertEqual(store.post(id: "post-1")?.resolvedMediaItems, [videoItem])
    }

    func testUpsertUsesIncomingMediaItemsWhenPresent() {
        let store = ExplorePostStore()
        let oldVideoItem = ExploreMediaItem(
            kind: .video,
            url: "https://media.example/old-video.mp4",
            thumbnailUrl: "https://media.example/old-poster.jpg",
            orderIndex: 0,
            durationSeconds: 4.2,
            hasAudio: true
        )
        let newImageItem = ExploreMediaItem(
            kind: .image,
            url: "https://media.example/new-image.jpg",
            thumbnailUrl: "https://media.example/new-image.jpg",
            orderIndex: 0,
            durationSeconds: nil,
            hasAudio: false
        )

        store.upsert(makePost(mediaItems: [oldVideoItem]), includeInFeed: true)
        store.upsert(makePost(mediaItems: [newImageItem]))

        XCTAssertEqual(store.post(id: "post-1")?.resolvedMediaItems, [newImageItem])
    }

    func testFeedRefreshPreservesExistingVideoMediaWhenPayloadOmitsMediaItems() {
        let store = ExplorePostStore()
        let videoItem = ExploreMediaItem(
            kind: .video,
            url: "https://media.example/video.mp4",
            thumbnailUrl: "https://media.example/poster.jpg",
            orderIndex: 0,
            durationSeconds: 4.2,
            hasAudio: true
        )

        store.setFeedPosts([makePost(mediaItems: [videoItem])])
        store.setFeedPosts([makePost(mediaItems: nil)])

        XCTAssertEqual(store.post(id: "post-1")?.resolvedMediaItems, [videoItem])
    }

    func testAppendingFeedPostPreservesSupplementalVideoMediaWhenPayloadOmitsMediaItems() {
        let store = ExplorePostStore()
        let videoItem = ExploreMediaItem(
            kind: .video,
            url: "https://media.example/video.mp4",
            thumbnailUrl: "https://media.example/poster.jpg",
            orderIndex: 0,
            durationSeconds: 4.2,
            hasAudio: true
        )

        store.upsert(makePost(mediaItems: [videoItem]))
        store.appendUniqueFeedPosts([makePost(mediaItems: nil)])

        XCTAssertEqual(store.post(id: "post-1")?.resolvedMediaItems, [videoItem])
    }

    private func makePost(mediaItems: [ExploreMediaItem]?) -> ExplorePost {
        ExplorePost(
            postId: "post-1",
            scanId: "scan-1",
            heroImageUrl: "https://media.example/hero.jpg",
            sharedAt: "2026-07-08T00:00:00Z",
            authorUserId: "author-1",
            authorName: "Test Author",
            authorUsername: "author",
            authorAvatarUrl: nil,
            authorIsPro: false,
            hashtags: nil,
            speciesCommonName: "Great Blue Heron",
            speciesScientificName: "Ardea herodias",
            petIdentification: nil,
            publicLocationLabel: "Austin, TX",
            locationSharing: nil,
            timeOfDay: nil,
            currentMonth: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false,
            isOwnedByViewer: false,
            rankingValue: nil,
            mediaItems: mediaItems
        )
    }
}

final class ExploreVideoPlaybackResumeIntentStateTests: XCTestCase {
    func testSystemResumeIntentSurvivesRepeatedInterruptionWhileAlreadyPaused() {
        var state = ExploreVideoPlaybackResumeIntentState()

        state.markSystemInterruption(shouldResume: true)
        state.markSystemInterruption(shouldResume: false)

        XCTAssertTrue(state.consumeSystemResumeIntent())
        XCTAssertFalse(state.consumeSystemResumeIntent())
    }

    func testClearingResumeIntentsCancelsSystemResume() {
        var state = ExploreVideoPlaybackResumeIntentState()
        state.markSystemInterruption(shouldResume: true)

        state.clear()

        XCTAssertFalse(state.consumeSystemResumeIntent())
    }
}

@MainActor
final class ExploreVideoPlaybackCoordinatorTests: XCTestCase {
    func testSingleOverlayPausesAndResumesWhenDismissed() {
        let coordinator = ExploreVideoPlaybackCoordinator()

        let token = coordinator.beginOverlay(reason: "comments")

        XCTAssertEqual(coordinator.overlayDepth, 1)
        XCTAssertEqual(coordinator.pauseGeneration, 1)
        XCTAssertEqual(coordinator.resumeGeneration, 0)
        XCTAssertTrue(coordinator.hasActiveOverlay)

        coordinator.endOverlay(token)

        XCTAssertEqual(coordinator.overlayDepth, 0)
        XCTAssertEqual(coordinator.pauseGeneration, 1)
        XCTAssertEqual(coordinator.resumeGeneration, 1)
        XCTAssertFalse(coordinator.hasActiveOverlay)
    }

    func testNestedOverlaysResumeOnlyAfterFinalDismissal() {
        let coordinator = ExploreVideoPlaybackCoordinator()

        let commentsToken = coordinator.beginOverlay(reason: "comments")
        let profileToken = coordinator.beginOverlay(reason: "profile")

        XCTAssertEqual(coordinator.overlayDepth, 2)
        XCTAssertEqual(coordinator.pauseGeneration, 2)
        XCTAssertEqual(coordinator.resumeGeneration, 0)

        coordinator.endOverlay(profileToken)

        XCTAssertEqual(coordinator.overlayDepth, 1)
        XCTAssertEqual(coordinator.resumeGeneration, 0)
        XCTAssertTrue(coordinator.hasActiveOverlay)

        coordinator.endOverlay(commentsToken)

        XCTAssertEqual(coordinator.overlayDepth, 0)
        XCTAssertEqual(coordinator.resumeGeneration, 1)
        XCTAssertFalse(coordinator.hasActiveOverlay)
    }

    func testDuplicateOverlayDismissIsIgnored() {
        let coordinator = ExploreVideoPlaybackCoordinator()
        let token = coordinator.beginOverlay(reason: "share")

        coordinator.endOverlay(token)
        coordinator.endOverlay(token)

        XCTAssertEqual(coordinator.overlayDepth, 0)
        XCTAssertEqual(coordinator.pauseGeneration, 1)
        XCTAssertEqual(coordinator.resumeGeneration, 1)
    }

    func testActivePlayerCanBeActivatedAndCleared() {
        let coordinator = ExploreVideoPlaybackCoordinator()

        coordinator.activate(playerID: "player-a", surface: .feed)
        XCTAssertEqual(coordinator.activePlayerID, "player-a")

        coordinator.clearActivePlayer("player-b")
        XCTAssertEqual(coordinator.activePlayerID, "player-a")

        coordinator.clearActivePlayer("player-a")
        XCTAssertNil(coordinator.activePlayerID)
    }
}

final class ExploreAuthorProfileNavigationPolicyTests: XCTestCase {
    func testProfileNavigationCanOpenAtRootButStopsAtMaxDepth() {
        XCTAssertTrue(ExploreAuthorProfileNavigationPolicy.canOpenProfile(from: 0))
        XCTAssertFalse(
            ExploreAuthorProfileNavigationPolicy.canOpenProfile(
                from: ExploreAuthorProfileNavigationPolicy.maxProfileDepth
            )
        )
    }

    func testProfileNavigationDepthCapsAtMaxDepth() {
        XCTAssertEqual(ExploreAuthorProfileNavigationPolicy.nextProfileDepth(from: 0), 1)
        XCTAssertEqual(
            ExploreAuthorProfileNavigationPolicy.nextProfileDepth(from: 1),
            ExploreAuthorProfileNavigationPolicy.maxProfileDepth
        )
    }
}

@MainActor
final class ExploreMediaLayoutTests: XCTestCase {
    private func makeStripedImage(
        size: CGSize,
        topColor: UIColor,
        bottomColor: UIColor
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            topColor.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.5))

            bottomColor.setFill()
            context.fill(CGRect(x: 0, y: size.height * 0.5, width: size.width, height: size.height * 0.5))
        }
    }

    private func render<V: View>(_ view: V, width: CGFloat = 320) -> UIImage {
        let fittingSize = CGSize(width: width, height: width)
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: view.frame(width: width, height: width))
            renderer.scale = 1
            if let image = renderer.uiImage {
                return image
            }
        }

        let controller = UIHostingController(rootView: view.frame(width: width, height: width))
        controller.view.bounds = CGRect(origin: .zero, size: fittingSize)
        controller.view.frame = CGRect(origin: .zero, size: fittingSize)
        controller.view.backgroundColor = .clear

        let window = UIWindow(frame: controller.view.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()

        controller.view.setNeedsLayout()
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: fittingSize, format: format).image { context in
            controller.view.layer.render(in: context.cgContext)
        }

        window.isHidden = true
        return image
    }

    private struct RGBAPixel {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8
    }

    private func rgbaPixel(in image: UIImage, x: Int, y: Int) -> RGBAPixel {
        guard let cgImage = image.cgImage,
              let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
            XCTFail("Failed to crop pixel from rendered image")
            return RGBAPixel(r: 0, g: 0, b: 0, a: 0)
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            XCTFail("Failed to create pixel sampling context")
            return RGBAPixel(r: 0, g: 0, b: 0, a: 0)
        }

        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return RGBAPixel(r: pixel[0], g: pixel[1], b: pixel[2], a: pixel[3])
    }

    private func assertPixel(
        _ pixel: RGBAPixel,
        approximately color: UIColor,
        tolerance: Int = 28,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), file: file, line: line)

        XCTAssertGreaterThanOrEqual(Int(pixel.a), 245, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(Int(pixel.r) - Int(red * 255)), tolerance, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(Int(pixel.g) - Int(green * 255)), tolerance, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(Int(pixel.b) - Int(blue * 255)), tolerance, file: file, line: line)
    }

    func testExploreFeedMediaViewLandscapeImageFillsSquare() {
        let topColor = UIColor.systemTeal
        let bottomColor = UIColor.systemOrange
        let image = makeStripedImage(
            size: CGSize(width: 1200, height: 800),
            topColor: topColor,
            bottomColor: bottomColor
        )

        let rendered = render(
            ExploreFeedMediaView(
                imageUrl: "preview-landscape",
                reloadGeneration: 0,
                preloadedImage: image
            )
        )

        XCTAssertEqual(rendered.size.width, 320, accuracy: 1)
        XCTAssertEqual(rendered.size.height, 320, accuracy: 1)

        assertPixel(rgbaPixel(in: rendered, x: 160, y: 8), approximately: topColor)
        assertPixel(rgbaPixel(in: rendered, x: 160, y: 311), approximately: bottomColor)
    }

    func testExploreFeedMediaViewPortraitImageFillsSquare() {
        let topColor = UIColor.systemPink
        let bottomColor = UIColor.systemIndigo
        let image = makeStripedImage(
            size: CGSize(width: 800, height: 1200),
            topColor: topColor,
            bottomColor: bottomColor
        )

        let rendered = render(
            ExploreFeedMediaView(
                imageUrl: "preview-portrait",
                reloadGeneration: 0,
                preloadedImage: image
            )
        )

        XCTAssertEqual(rendered.size.width, 320, accuracy: 1)
        XCTAssertEqual(rendered.size.height, 320, accuracy: 1)

        assertPixel(rgbaPixel(in: rendered, x: 160, y: 8), approximately: topColor)
        assertPixel(rgbaPixel(in: rendered, x: 160, y: 311), approximately: bottomColor)
    }

    func testExploreDetailMediaViewLandscapeImageFillsSquare() {
        let topColor = UIColor.systemGreen
        let bottomColor = UIColor.systemBlue
        let image = makeStripedImage(
            size: CGSize(width: 1200, height: 800),
            topColor: topColor,
            bottomColor: bottomColor
        )

        let rendered = render(
            ExploreDetailMediaView(
                imageUrl: "preview-detail",
                reloadGeneration: 0,
                preloadedImage: image,
                allowsZoom: false
            )
        )

        XCTAssertEqual(rendered.size.width, 320, accuracy: 1)
        XCTAssertEqual(rendered.size.height, 320, accuracy: 1)

        assertPixel(rgbaPixel(in: rendered, x: 160, y: 24), approximately: topColor)
        assertPixel(rgbaPixel(in: rendered, x: 160, y: 295), approximately: bottomColor)
    }
}

@MainActor
final class ExploreReplyLoadingStateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.mockEndpoints = [:]

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MerianNetworkClient.shared.overridingSession = URLSession(configuration: config)
        MerianNetworkClient.shared.resetSpeciesDictionaryCacheForTesting()
    }

    private func makeComment(id: String = "parent-comment-123") -> ExploreComment {
        ExploreComment(
            commentId: id,
            postId: "post-123",
            parentCommentId: nil,
            authorUserId: "author-123",
            authorName: "Parent Author",
            authorUsername: nil,
            authorAvatarUrl: nil,
            body: "Parent body",
            createdAt: "2026-05-19T10:00:00.000Z",
            viewerCanDelete: false,
            viewerCanModerate: false,
            viewerCanReport: true,
            replyCount: 1,
            reactions: nil,
            mentions: nil
        )
    }

    func testLoadRepliesMarksLoadedAndClearsLoadingState() async throws {
        let viewModel = ExploreFeedViewModel()
        let parentComment = makeComment()
        let responseData = """
        {
            "success": true,
            "data": [
                {
                    "comment_id": "reply-123",
                    "post_id": "post-123",
                    "parent_comment_id": "parent-comment-123",
                    "author_user_id": "reply-author-123",
                    "author_name": "Reply Author",
                    "body": "Reply body",
                    "created_at": "2026-05-19T10:01:00.000Z",
                    "viewer_can_delete": false,
                    "viewer_can_moderate": false,
                    "viewer_can_report": true,
                    "reply_count": 0,
                    "reactions": []
                }
            ]
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/get-explore-comment-replies"] = { _ in
            (mockResponse, responseData)
        }

        await viewModel.loadReplies(for: parentComment)

        XCTAssertFalse(viewModel.loadingReplyCommentIds.contains(parentComment.id))
        XCTAssertTrue(viewModel.hasLoadedRepliesByCommentId.contains(parentComment.id))
        XCTAssertFalse(viewModel.failedReplyCommentIds.contains(parentComment.id))
        XCTAssertEqual(viewModel.repliesByCommentId[parentComment.id]?.first?.id, "reply-123")

        let replyState = viewModel.replyThreadRenderState(for: parentComment.id)
        XCTAssertFalse(replyState.isLoading)
        XCTAssertTrue(replyState.hasLoadedReplies)
        XCTAssertEqual(replyState.replies.first?.id, "reply-123")
    }

    func testCancelledLoadRepliesClearsLoadingWithoutFailureOrLoadedState() async {
        let viewModel = ExploreFeedViewModel()
        let parentComment = makeComment()

        MockURLProtocol.mockEndpoints["/get-explore-comment-replies"] = { _ in
            throw URLError(.cancelled)
        }

        await viewModel.loadReplies(for: parentComment)

        XCTAssertFalse(viewModel.loadingReplyCommentIds.contains(parentComment.id))
        XCTAssertFalse(viewModel.hasLoadedRepliesByCommentId.contains(parentComment.id))
        XCTAssertFalse(viewModel.failedReplyCommentIds.contains(parentComment.id))

        let replyState = viewModel.replyThreadRenderState(for: parentComment.id)
        XCTAssertFalse(replyState.isLoading)
        XCTAssertFalse(replyState.hasLoadedReplies)
        XCTAssertFalse(replyState.didFail)
    }

    func testFailedLoadRepliesClearsLoadingAndSetsRetryState() async {
        let viewModel = ExploreFeedViewModel()
        let parentComment = makeComment()

        MockURLProtocol.mockEndpoints["/get-explore-comment-replies"] = { _ in
            throw NSError(domain: "ExploreReplyLoadingStateTests", code: 1)
        }

        await viewModel.loadReplies(for: parentComment)

        XCTAssertFalse(viewModel.loadingReplyCommentIds.contains(parentComment.id))
        XCTAssertFalse(viewModel.hasLoadedRepliesByCommentId.contains(parentComment.id))
        XCTAssertTrue(viewModel.failedReplyCommentIds.contains(parentComment.id))

        let replyState = viewModel.replyThreadRenderState(for: parentComment.id)
        XCTAssertFalse(replyState.isLoading)
        XCTAssertFalse(replyState.hasLoadedReplies)
        XCTAssertTrue(replyState.didFail)
    }
}
