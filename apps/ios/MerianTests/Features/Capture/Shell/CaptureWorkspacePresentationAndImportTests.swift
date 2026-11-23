import CoreData
import MapKit
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Merian

extension CaptureWorkspaceViewModelRefinementTests {
    func testUnvisitedImportedPhotoGetsSquareArtifactsAndUncroppedEditorSource() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 180, height: 80)).pngData { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 180, height: 80))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("capture-default-" + UUID().uuidString + ".png")
        try source.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await CaptureWorkspaceDependencies.livePreparedImageLoader(
            .init(fileURL: url, isPro: false, historicalContext: nil))
        let prepared = try XCTUnwrap(result)
        let ai = try XCTUnwrap(UIImage(data: prepared.compressedData))
        let display = try XCTUnwrap(UIImage(data: prepared.displayData))
        XCTAssertEqual(ai.size.width, ai.size.height)
        XCTAssertEqual(display.size.width, display.size.height)
        XCTAssertGreaterThan(prepared.previewCGImage.image.width, prepared.previewCGImage.image.height)
        XCTAssertTrue(try XCTUnwrap(prepared.metrics).isWithinImageBudgets)
    }

    func testCaptureControlClearancesPreserveOverlayPositions() {
        XCTAssertEqual(CaptureControlBarLayout.reservedHeight, 204)
        XCTAssertEqual(CaptureControlBarLayout.fullScreenOverlayClearance, 250)
        XCTAssertEqual(CaptureControlBarLayout.describeContentBottomClearance, 204)
        XCTAssertGreaterThan(
            CaptureControlBarLayout.fullScreenOverlayClearance,
            CaptureControlBarLayout.reservedHeight
        )
        XCTAssertEqual(
            CaptureControlBarLayout.describeContentBottomClearance,
            CaptureControlBarLayout.reservedHeight
        )
    }

    func testViewfinderHintsHideAfterSingleScanContentIsStaged() {
        RevenueCatManager.shared.isSubscribed = false
        RevenueCatManager.shared.isProActive = false
        let diContainer = AppDIContainer.preview
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
        viewModel.stagedCapture.audios = [StagedAudio(filePath: "second.wav")]

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

        XCTAssertEqual(
            viewModel.stagePendingDescribeDraftForActiveSubmission(
                ObservationContext(freeText: "Small green subject on concrete")
            ), .staged
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

        XCTAssertEqual(
            viewModel.stagePendingDescribeDraftForActiveSubmission(
                ObservationContext(freeText: "Fresh draft for this analysis")
            ), .staged
        )

        XCTAssertEqual(viewModel.stagedCapture.observationContexts.count, 1)
        XCTAssertEqual(
            viewModel.stagedCapture.observationContexts.first?.context.freeText,
            "Fresh draft for this analysis"
        )
    }

    func testPhotoLibraryPreparedImagePresentsOptionalReview() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )

        viewModel.commitPreparedStagedImages([makePreparedStagedImage()], presentsReview: true)

        let stagedImage = viewModel.stagedCapture.images.first
        XCTAssertEqual(viewModel.stagedCapture.images.count, 1)
        XCTAssertEqual(viewModel.imageToCrop?.id, stagedImage?.original.id)
        XCTAssertTrue(viewModel.shouldSuppressCaptureChromeForCrop)
    }

    func testPreparedImageWithoutReviewPresentationCanSubmit() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )

        viewModel.commitPreparedStagedImages([makePreparedStagedImage()])

        XCTAssertEqual(viewModel.stagedCapture.images.count, 1)
        XCTAssertNil(viewModel.imageToCrop)
        XCTAssertTrue(viewModel.canSubmitDraft)
    }

    func testPendingExternalImageImportStagesThroughGalleryCropFlowAndCleansInbox() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-external-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appendingPathComponent("shared-photo.png")
        try makePNGData().write(to: sourceURL)
        let store = ExternalImageImportStore(rootURL: rootURL.appendingPathComponent("Inbox"))
        _ = try await store.stageIncomingImage(at: sourceURL)
        let preparedImage = makePreparedStagedImage()

        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in preparedImage },
            prewarmHeadersOnInit: false,
            externalImageImportStore: store
        )

        viewModel.importPendingExternalImageIfPossible()
        // Staging precedes the awaited inbox removal. Review is presented only
        // when that operation finishes, so observe the completed draft boundary.
        try await waitUntil {
            viewModel.stagedCapture.images.count == 1 && !viewModel.draftSession.hasUnresolvedWork
        }

        XCTAssertEqual(viewModel.imageToCrop?.id, viewModel.stagedCapture.images.first?.original.id)
        let remainingImports = await store.pendingImports()
        XCTAssertTrue(remainingImports.isEmpty)
    }

    func testExternalImageImportOverridesLaunchExploreAndSurvivesTimeoutReset() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-external-import-launch-route-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appendingPathComponent("shared-photo.png")
        try makePNGData().write(to: sourceURL)
        let store = ExternalImageImportStore(rootURL: rootURL.appendingPathComponent("Inbox"))
        _ = try await store.stageIncomingImage(at: sourceURL)
        let preparedImage = makePreparedStagedImage()
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in preparedImage },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .explore,
            externalImageImportStore: store
        )

        deliverRoute(
            .processExternalImageImports,
            source: .durableExternalImport,
            to: viewModel
        )
        diContainer.appEventPublisher.send(.appDidResumeAfterTimeout)

        try await waitUntil { viewModel.activeSheet == nil }
        viewModel.handleRootSheetDismissed()

        try await waitUntil {
            viewModel.activeSheet == nil &&
                viewModel.stagedCapture.images.count == 1 &&
                viewModel.imageToCrop != nil
        }

        let remainingImports = await store.pendingImports()
        XCTAssertTrue(remainingImports.isEmpty)
    }

    func testPendingExternalImageImportRemainsQueuedUntilCaptureCapacityIsAvailable() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-external-import-capacity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appendingPathComponent("shared-photo.png")
        try makePNGData().write(to: sourceURL)
        let store = ExternalImageImportStore(rootURL: rootURL.appendingPathComponent("Inbox"))
        _ = try await store.stageIncomingImage(at: sourceURL)
        let preparedImage = makePreparedStagedImage()
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in preparedImage },
            prewarmHeadersOnInit: false,
            externalImageImportStore: store
        )
        viewModel.stagedCapture.audios = (0..<viewModel.stagedCaptureLimit).map { StagedAudio(filePath: "existing-\($0).wav") }

        viewModel.importPendingExternalImageIfPossible()
        try await waitUntil {
            viewModel.offlineToastMessage?.title ==
                "Finish your current capture to import the shared photo."
        }
        let blockedImports = await store.pendingImports()
        XCTAssertEqual(blockedImports.count, 1)

        viewModel.stagedCapture.audios.removeAll()
        viewModel.importPendingExternalImageIfPossible()
        try await waitUntil { viewModel.stagedCapture.images.count == 1 }

        let remainingImports = await store.pendingImports()
        XCTAssertTrue(remainingImports.isEmpty)
    }

    func testUnreadablePendingExternalImageImportIsDiscardedWithUserFeedback() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-external-import-failure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appendingPathComponent("shared-photo.jpg")
        try Data("invalid image".utf8).write(to: sourceURL)
        let store = ExternalImageImportStore(rootURL: rootURL.appendingPathComponent("Inbox"))
        _ = try await store.stageIncomingImage(at: sourceURL)
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in throw MediaPreparationError.unreadableImage },
            prewarmHeadersOnInit: false,
            externalImageImportStore: store
        )

        viewModel.importPendingExternalImageIfPossible()
        try await waitUntil {
            viewModel.offlineToastMessage?.title == "Naturebook couldn’t import that photo."
        }

        XCTAssertTrue(viewModel.stagedCapture.images.isEmpty)
        let remainingImports = await store.pendingImports()
        XCTAssertTrue(remainingImports.isEmpty)
    }

    func testServerDeniedExternalImageImportIsRetainedBeforePreparationAndCrop() async throws {
        enableUnlimitedFreeScansForTest()
        ScanAdmissionManager.shared.overridingPreview = { _ in
            ScanAdmissionPreview(
                decision: .dailyQuotaExhausted,
                effectivePlan: "free",
                dailyLimit: 1,
                dailyRemaining: 0
            )
        }
        let queueManager = OfflineQueueManager.shared
        let previousOnlineState = queueManager.isOnline
        queueManager.isOnline = true
        defer {
            queueManager.isOnline = previousOnlineState
            ScanAdmissionManager.shared.resetForTesting()
            restoreFreeScanLimitForTest()
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-external-import-admission-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appendingPathComponent("shared-photo.png")
        try makePNGData().write(to: sourceURL)
        let store = ExternalImageImportStore(rootURL: rootURL.appendingPathComponent("Inbox"))
        _ = try await store.stageIncomingImage(at: sourceURL)
        let preparedImage = makePreparedStagedImage()
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in preparedImage },
            prewarmHeadersOnInit: false,
            externalImageImportStore: store
        )

        let result = await viewModel.importNextPendingExternalImage()

        XCTAssertEqual(result, .temporarilyBlocked)
        XCTAssertEqual(viewModel.activeSheet, .paywall)
        XCTAssertTrue(viewModel.stagedCapture.isEmpty)
        XCTAssertNil(viewModel.imageToCrop)
        XCTAssertFalse(viewModel.isCheckingScanAdmission)
        let retainedImports = await store.pendingImports()
        XCTAssertEqual(retainedImports.count, 1)
    }

    func testQuotaBlockedExternalImportIsRetainedAndProEntitlementRetriesIt() async throws {
        let previousProState = RevenueCatManager.shared.isProActive
        let previousSubscribedState = RevenueCatManager.shared.isSubscribed
        defer {
            RevenueCatManager.shared.isSubscribed = previousSubscribedState
            RevenueCatManager.shared.isProActive = previousProState
            restoreFreeScanLimitForTest()
        }
        UsageManager.debugFreeScanLimitOverride = false
        UsageManager.shared.freeScansRemaining = 0
        RevenueCatManager.shared.isSubscribed = false
        RevenueCatManager.shared.isProActive = false

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-external-import-quota-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let sourceURL = rootURL.appendingPathComponent("shared-photo.png")
        try makePNGData().write(to: sourceURL)
        let store = ExternalImageImportStore(rootURL: rootURL.appendingPathComponent("Inbox"))
        _ = try await store.stageIncomingImage(at: sourceURL)
        let preparedImage = makePreparedStagedImage()
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in preparedImage },
            prewarmHeadersOnInit: false,
            externalImageImportStore: store
        )

        let blockedResult = await viewModel.importNextPendingExternalImage()

        XCTAssertEqual(blockedResult, .temporarilyBlocked)
        XCTAssertEqual(viewModel.activeSheet, .paywall)
        let blockedImports = await store.pendingImports()
        XCTAssertEqual(blockedImports.count, 1)

        RevenueCatManager.shared.isSubscribed = true
        RevenueCatManager.shared.isProActive = true
        let prematureRetryResult = await viewModel.importNextPendingExternalImage()

        XCTAssertEqual(prematureRetryResult, .temporarilyBlocked)
        XCTAssertEqual(viewModel.activeSheet, .paywall)
        XCTAssertTrue(viewModel.stagedCapture.isEmpty)
        XCTAssertNil(viewModel.imageToCrop)
        let importsRetainedBehindPaywall = await store.pendingImports()
        XCTAssertEqual(importsRetainedBehindPaywall.count, 1)

        viewModel.importPendingExternalImageIfPossible()
        try await waitUntil {
            viewModel.activeSheet == nil && viewModel.isRootPresentationDismissing
        }

        XCTAssertTrue(viewModel.stagedCapture.isEmpty)
        XCTAssertNil(viewModel.imageToCrop)
        let importsRetainedDuringDismissal = await store.pendingImports()
        XCTAssertEqual(importsRetainedDuringDismissal.count, 1)

        viewModel.handleRootSheetDismissed()
        try await waitUntil {
            !viewModel.isRootPresentationDismissing &&
                viewModel.stagedCapture.images.count == 1 &&
                viewModel.imageToCrop != nil
        }

        XCTAssertEqual(
            viewModel.imageToCrop?.id,
            viewModel.stagedCapture.images.first?.original.id
        )
        let remainingImports = await store.pendingImports()
        XCTAssertTrue(remainingImports.isEmpty)
    }

    func testRemovingReviewedImageClearsCropState() throws {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        viewModel.commitPreparedStagedImages([makePreparedStagedImage()], presentsReview: true)

        viewModel.removeReviewedMedia(session: try XCTUnwrap(viewModel.mediaReviewSession))

        XCTAssertTrue(viewModel.stagedCapture.images.isEmpty)
        XCTAssertNil(viewModel.imageToCrop)
        XCTAssertNil(viewModel.editingCropIndex)
    }

    func testImportedObservationRemainsManualAfterOptionalReview() throws {
        for autoSubmit in [false, true] {
            let container = AppDIContainer.preview
            container.appSettings.autoSubmitScans = autoSubmit
            let model = CaptureWorkspaceViewModel(diContainer: container,
                preparedImageLoader: { _ in nil }, prewarmHeadersOnInit: false)
            let operation = try XCTUnwrap(model.beginDraftOperation())
            model.commitPreparedStagedImages([makePreparedStagedImage()], presentsReview: true)
            model.completeDraftOperation(operation, succeeded: true)
            let imageID = try XCTUnwrap(model.stagedCapture.images.first?.original.id)
            let commit = try XCTUnwrap(model.beginPhotoReviewCommit(imageID: imageID))
            XCTAssertTrue(model.finishPhotoReviewCommit(commit, succeeded: true))
            XCTAssertTrue(model.canSubmitDraft)
            XCTAssertFalse(model.isAutomaticSubmissionArmed)
            XCTAssertFalse(model.isAutomaticStagedSubmissionPending)
            // Outer presentation still owns hardware until its matching dismissal.
            XCTAssertTrue(model.shouldSuppressCaptureChromeForCrop)
        }
    }

}
