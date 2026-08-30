import CoreData
import MapKit
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Merian

extension CaptureWorkspaceViewModelRefinementTests {
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
        XCTAssertTrue(viewModel.shouldSuppressCaptureChromeForCrop)
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
        try await waitUntil { viewModel.stagedCapture.images.count == 1 }

        XCTAssertTrue(viewModel.hasPendingRequiredGalleryCrop)
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

        XCTAssertTrue(viewModel.hasPendingRequiredGalleryCrop)
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
        viewModel.stagedCapture.observationContexts = [
            StagedObservationContext(context: ObservationContext(freeText: "Existing capture"))
        ]

        viewModel.importPendingExternalImageIfPossible()
        try await waitUntil {
            viewModel.offlineToastMessage?.title ==
                "Finish your current capture to import the shared photo."
        }
        let blockedImports = await store.pendingImports()
        XCTAssertEqual(blockedImports.count, 1)

        viewModel.stagedCapture.observationContexts.removeAll()
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

        XCTAssertTrue(viewModel.hasPendingRequiredGalleryCrop)
        XCTAssertEqual(
            viewModel.imageToCrop?.id,
            viewModel.stagedCapture.images.first?.original.id
        )
        let remainingImports = await store.pendingImports()
        XCTAssertTrue(remainingImports.isEmpty)
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

        autoSubmitViewModel.imageToCrop = nil
        XCTAssertTrue(autoSubmitViewModel.completeRequiredGalleryCrop(for: autoSubmitImageId))
        XCTAssertTrue(autoSubmitViewModel.isAutomaticStagedSubmissionPending)
        XCTAssertFalse(autoSubmitViewModel.shouldPresentActiveScanToolbar)
        XCTAssertFalse(autoSubmitViewModel.shouldSuppressCaptureChromeForCrop)

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

        confirmationViewModel.imageToCrop = nil
        XCTAssertFalse(confirmationViewModel.completeRequiredGalleryCrop(for: confirmationImageId))
        XCTAssertFalse(confirmationViewModel.isAutomaticStagedSubmissionPending)
        XCTAssertTrue(confirmationViewModel.shouldPresentActiveScanToolbar)
        XCTAssertFalse(confirmationViewModel.shouldSuppressCaptureChromeForCrop)
    }

}
