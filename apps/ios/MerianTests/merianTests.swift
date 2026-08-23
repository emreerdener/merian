import CoreData
import MapKit
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Merian

@MainActor
final class ScrollAwareToolbarTitleBadgeTests: XCTestCase {
    private let longTitle = "Fragrant Olive, Sweet Olive, Tea Olive, and Many More Common Names"

    func testLongTitleUsesCompactMaximumWidth() {
        let size = fittingSize(for: longTitle, horizontalSizeClass: .compact)

        XCTAssertEqual(size.width, 200, accuracy: 0.5)
    }

    func testLongTitleUsesRegularMaximumWidth() {
        let size = fittingSize(for: longTitle, horizontalSizeClass: .regular)

        XCTAssertEqual(size.width, 320, accuracy: 0.5)
    }

    func testShortTitleKeepsItsNaturalWidth() {
        let size = fittingSize(for: "Bee", horizontalSizeClass: .compact)

        XCTAssertLessThan(size.width, 200)
    }

    private func fittingSize(
        for title: String,
        horizontalSizeClass: UserInterfaceSizeClass
    ) -> CGSize {
        let view = ScrollAwareToolbarTitleBadge(title: title, isVisible: true)
            .environment(\.horizontalSizeClass, horizontalSizeClass)
        let controller = UIHostingController(rootView: view)

        return controller.sizeThatFits(in: CGSize(width: 1_000, height: 100))
    }
}

@MainActor
final class CaptureWorkspaceViewModelRefinementTests: XCTestCase {
    private static let entitlementTestUserID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000778"
    )!

    private var previousProState = false
    private var previousSubscribedState = false

    override func setUp() {
        super.setUp()
        previousProState = RevenueCatManager.shared.isProActive
        previousSubscribedState = RevenueCatManager.shared.isSubscribed
        RevenueCatManager.shared.isSubscribed = true
        RevenueCatManager.shared.isProActive = true
    }

    override func tearDown() {
        RevenueCatManager.shared.isSubscribed = previousSubscribedState
        RevenueCatManager.shared.isProActive = previousProState
        super.tearDown()
    }

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

    private func deliverRoute(
        _ route: AppRoute,
        source: AppRouteSource,
        to viewModel: CaptureWorkspaceViewModel,
        now: Date = Date()
    ) {
        let coordinator = viewModel.diContainer.appRouteCoordinator
        coordinator.request(route, source: source, now: now)
        viewModel.consumeNextAppRoute(now: now)

        if case .deferred? = coordinator.inFlightOutcome {
            viewModel.handleRootSheetDismissed(now: now)
            viewModel.consumeNextAppRoute(now: now)
        }
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
        activatePaidEntitlementAccountForTest()
    }

    private func restoreFreeScanLimitForTest() {
        let deviceId = DeviceIdentityManager.shared.deviceId
        UserDefaults.standard.removeObject(forKey: "Merian_LastScanDate_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "Merian_ScansUsedToday_\(deviceId)")
        UsageManager.debugFreeScanLimitOverride = nil
        UsageManager.shared.evaluateDailyRefresh()
        resetEntitlementAccountForTest()
    }

    private func activatePaidEntitlementAccountForTest() {
        EntitlementManager.shared.resetForTesting(
            userID: Self.entitlementTestUserID
        )
    }

    private func resetEntitlementAccountForTest() {
        EntitlementManager.shared.resetForTesting()
    }

    private func makeTempAudioFilename(prefix: String = "capture_vm_audio") throws -> String {
        let filename = "\(prefix)_\(UUID().uuidString).wav"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try makeInferenceTestPCM16WAVData().write(to: url)
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

    func testExploreDeepLinkSurvivesImmediateSessionTimeoutReset() async throws {
        let postId = "widget-post-123"
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .explore
        )

        deliverRoute(
            .explorePost(
                postId: postId,
                targetCommentId: nil,
                targetReplyParentCommentId: nil
            ),
            source: .deepLink,
            to: viewModel
        )
        try await waitUntil {
            viewModel.activeSheet == .explore && viewModel.pendingExplorePostId == postId
        }

        diContainer.appEventPublisher.send(.appDidResumeAfterTimeout)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.activeSheet, .explore)
        XCTAssertEqual(viewModel.pendingExplorePostId, postId)
    }

    func testSpeciesDictionaryDeepLinkOverridesConflictsAndSurvivesTimeoutReset() async throws {
        let speciesId = "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .explore
        )
        viewModel.pendingExplorePostId = "stale-post"
        viewModel.pendingCommunityIdentificationRequestId = "stale-request"
        viewModel.pendingExploreShowsFieldTrips = true

        deliverRoute(
            .speciesDictionary(speciesId: speciesId),
            source: .deepLink,
            to: viewModel
        )
        try await waitUntil {
            viewModel.activeSheet == .explore &&
                viewModel.pendingSpeciesDictionaryRoute?.speciesId == speciesId
        }

        XCTAssertEqual(viewModel.pendingSpeciesDictionaryRoute?.entryPoint, .deepLink)
        XCTAssertNil(viewModel.pendingExplorePostId)
        XCTAssertNil(viewModel.pendingCommunityIdentificationRequestId)
        XCTAssertFalse(viewModel.pendingExploreShowsFieldTrips)

        diContainer.appEventPublisher.send(.appDidResumeAfterTimeout)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.activeSheet, .explore)
        XCTAssertEqual(viewModel.pendingSpeciesDictionaryRoute?.speciesId, speciesId)
    }

    func testCommunityAndLibraryRoutesOverrideGenericLaunchExplore() async throws {
        let requestId = "community-request-123"
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .explore
        )

        deliverRoute(
            .communityIdentification(requestId: requestId),
            source: .internalUserAction,
            to: viewModel
        )
        try await waitUntil {
            viewModel.activeSheet == .explore &&
                viewModel.pendingCommunityIdentificationRequestId == requestId
        }

        diContainer.appRouteCoordinator.request(.scansLibrary, source: .appIntent)
        XCTAssertEqual(viewModel.activeSheet, .explore)
        viewModel.dismissActivePresentation()
        viewModel.handleRootSheetDismissed()
        viewModel.consumeNextAppRoute()
        try await waitUntil { viewModel.activeSheet == .scans }

        XCTAssertNil(viewModel.pendingCommunityIdentificationRequestId)
        XCTAssertNil(viewModel.pendingExplorePostId)
        XCTAssertNil(viewModel.pendingScansRecoveryContext)
    }

    func testRapidLocalSheetHandoffWaitsForDismissalAndKeepsLatestDestination() {
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .insight
        )
        let insightPresentationID = viewModel.activePresentation?.id

        viewModel.activeSheet = .profile
        XCTAssertNil(viewModel.activePresentation)

        viewModel.activeSheet = .scans
        XCTAssertNil(viewModel.activePresentation)

        viewModel.handleRootSheetDismissed()

        XCTAssertEqual(viewModel.activeSheet, .scans)
        XCTAssertNotEqual(viewModel.activePresentation?.id, insightPresentationID)
    }

    func testRouteArrivingDuringRootSheetTeardownDefersUntilExactDismissal() {
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .insight
        )

        viewModel.dismissActivePresentation()
        let requestID = diContainer.appRouteCoordinator.request(
            .scansLibrary,
            source: .deepLink
        )
        viewModel.consumeNextAppRoute()

        XCTAssertEqual(diContainer.appRouteCoordinator.inFlightRequest?.id, requestID)
        XCTAssertEqual(
            diContainer.appRouteCoordinator.inFlightOutcome,
            .deferred(reason: .presentationOccupied)
        )
        XCTAssertNil(viewModel.activePresentation)

        viewModel.handleRootSheetDismissed()
        viewModel.consumeNextAppRoute()

        XCTAssertEqual(viewModel.activeSheet, .scans)
        XCTAssertEqual(viewModel.activePresentation?.routeRequestID, requestID)
    }

    func testRouteDefersAcrossFeatureLocalPresentationUntilOnDismiss() {
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        let requestID = diContainer.appRouteCoordinator.request(
            .scansLibrary,
            source: .deepLink
        )

        viewModel.consumeNextAppRoute(isFeaturePresentationOccupied: true)
        XCTAssertEqual(
            diContainer.appRouteCoordinator.inFlightOutcome,
            .deferred(reason: .presentationOccupied)
        )
        XCTAssertNil(viewModel.activePresentation)

        viewModel.handleFeaturePresentationDismissed()
        viewModel.consumeNextAppRoute()

        XCTAssertEqual(viewModel.activeSheet, .scans)
        XCTAssertEqual(viewModel.activePresentation?.routeRequestID, requestID)
    }

    func testNonBiologicalLibraryRoutePreservesCollectionDestination() async throws {
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .insight
        )

        deliverRoute(
            .nonBiologicalScans,
            source: .internalUserAction,
            to: viewModel
        )
        try await waitUntil {
            viewModel.activeSheet == .scans &&
                viewModel.pendingScansShowsNonBiologicalCollection
        }

        XCTAssertNil(viewModel.pendingScansRecoveryContext)
    }

    func testProfileRecoveryRouteRejectsMismatchedOwnerWithoutStalling() async throws {
        let context = ExploreMediaRecoveryRouteContext(
            ownerUserId: "5d8372cc-1078-49a4-af27-e32d10290bad"
        )
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .profile
        )

        deliverRoute(
            .scansLibraryRecovery(context),
            source: .internalUserAction,
            to: viewModel
        )

        XCTAssertNil(viewModel.activeSheet)
        XCTAssertNil(viewModel.pendingScansRecoveryContext)
        XCTAssertEqual(
            diContainer.appRouteCoordinator.recentOutcomes.last?.outcome,
            .rejected(reason: .staleAccount)
        )
    }

    func testProfileFieldTripsRouteOpensExistingExploreFieldTripsRoot() async throws {
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .profile
        )
        viewModel.pendingExplorePostId = "stale-post"

        deliverRoute(.fieldTrips, source: .internalUserAction, to: viewModel)
        try await waitUntil {
            viewModel.activeSheet == .explore && viewModel.pendingExploreShowsFieldTrips
        }

        XCTAssertNil(viewModel.pendingExplorePostId)
        XCTAssertNil(viewModel.pendingCommunityIdentificationRequestId)
        XCTAssertNil(viewModel.pendingCaptureGoalDestination)
    }

    func testScanRouteOverridesGenericLaunchExplore() async throws {
        let modelContext = try makeModelContext()
        let previousModelContext = OfflineQueueManager.shared.modelContext
        OfflineQueueManager.shared.modelContext = modelContext
        defer { OfflineQueueManager.shared.modelContext = previousModelContext }

        let record = LocalScanRecord(
            speciesId: "launch-route-species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly"
        )
        modelContext.insert(record)
        try modelContext.save()

        let viewModel = CaptureWorkspaceViewModel(
            diContainer: AppDIContainer.preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false,
            initialActiveSheet: .explore
        )

        deliverRoute(
            .scan(scanId: record.id),
            source: .deepLink,
            to: viewModel
        )
        try await waitUntil { viewModel.activeSheet == .insight }

        XCTAssertNil(viewModel.pendingExplorePostId)
        XCTAssertNil(viewModel.pendingCommunityIdentificationRequestId)
    }

    func testSessionTimeoutResetClearsStaleExploreRoute() async throws {
        let diContainer = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: diContainer,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )
        viewModel.pendingExplorePostId = "stale-post"
        viewModel.activeSheet = .explore

        diContainer.appEventPublisher.send(.appDidResumeAfterTimeout)

        try await waitUntil {
            viewModel.activeSheet == nil && viewModel.pendingExplorePostId == nil
        }
    }

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
        let configuration = ScanAdmissionManager.previewSessionConfiguration()

        XCTAssertEqual(
            configuration.timeoutIntervalForRequest,
            ScanAdmissionManager.previewRequestTimeout
        )
        XCTAssertEqual(
            configuration.timeoutIntervalForResource,
            ScanAdmissionManager.previewRequestTimeout
        )
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(
            configuration.requestCachePolicy,
            .reloadIgnoringLocalCacheData
        )
    }

    func testConnectivityUnavailableAdmissionQueuesVisualAndNonVisualCaptureWithoutForegroundInference() async throws {
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
            CaptureWorkspaceViewModel.isFlashFallbackEligible([
                .image(index: 0)
            ])
        )
        XCTAssertFalse(
            CaptureWorkspaceViewModel.isFlashFallbackEligible([
                .image(index: 0),
                .description(ObservationContext(freeText: "Nearby leaves"))
            ])
        )
        XCTAssertFalse(
            CaptureWorkspaceViewModel.isFlashFallbackEligible(
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

    func testOfflineVisualQueueFailureDiscardsStagedVideoFiles() async throws {
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
    private func makeMapPost(
        id: String,
        latitude: Double,
        coordinateVisibility: ExploreCoordinateVisibility = .exact,
        mediaKinds: [ExploreMediaKind] = [.image]
    ) -> ExploreMapPost {
        ExploreMapPost(
            postId: id,
            scanId: "scan-\(id)",
            latitude: latitude,
            longitude: -97.743,
            coordinateVisibility: coordinateVisibility,
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
            locationSharing: .open,
            timeOfDay: nil,
            currentMonth: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false,
            isOwnedByViewer: false,
            mediaItems: mediaKinds.enumerated().map { index, kind in
                ExploreMediaItem(
                    kind: kind,
                    url: "https://example.com/\(id)-\(kind.rawValue)",
                    thumbnailUrl: kind == .audio ? nil : "https://example.com/\(id)-\(kind.rawValue).webp",
                    orderIndex: index,
                    durationSeconds: kind == .image ? nil : 4,
                    hasAudio: kind != .image
                )
            }
        )
    }

    private func makeCanonicalPost(
        from mapPost: ExploreMapPost,
        locationSharing: ExplorePostLocationSharing
    ) -> ExplorePost {
        ExplorePost(
            postId: mapPost.postId,
            scanId: mapPost.scanId,
            heroImageUrl: mapPost.heroImageUrl,
            referenceThumbnailUrl: mapPost.referenceThumbnailUrl,
            sharedAt: mapPost.sharedAt,
            authorUserId: mapPost.authorUserId,
            authorName: mapPost.authorName,
            authorUsername: mapPost.authorUsername,
            authorAvatarUrl: mapPost.authorAvatarUrl,
            authorIsPro: mapPost.authorIsPro,
            hashtags: nil,
            speciesCommonName: mapPost.speciesCommonName,
            speciesScientificName: mapPost.speciesScientificName,
            petIdentification: mapPost.petIdentification,
            publicLocationLabel: mapPost.publicLocationLabel,
            locationSharing: locationSharing,
            timeOfDay: mapPost.timeOfDay,
            currentMonth: mapPost.currentMonth,
            weatherCondition: mapPost.weatherCondition,
            weatherTemperatureF: mapPost.weatherTemperatureF,
            likeCount: mapPost.likeCount,
            commentCount: mapPost.commentCount,
            viewerHasLiked: mapPost.viewerHasLiked,
            isOwnedByViewer: mapPost.isOwnedByViewer,
            rankingValue: nil,
            mediaItems: mapPost.mediaItems
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

    func testMediaTypeFiltersMatchAnySelectedKindAndCombineWithSpecies() {
        let viewModel = ExploreMapViewModel()
        let image = makeMapPost(id: "image", latitude: 30.267, mediaKinds: [.image])
        let video = makeMapPost(id: "video", latitude: 30.268, mediaKinds: [.video])
        let mixed = makeMapPost(id: "mixed", latitude: 30.269, mediaKinds: [.image, .audio])
        viewModel.posts = [image, video, mixed]

        viewModel.selectedMediaTypes = [.video, .audio]
        viewModel.selectedSpeciesCategories = [.insects]

        XCTAssertEqual(viewModel.visiblePosts.map(\.id), ["video", "mixed"])
        XCTAssertTrue(viewModel.hasActiveFilters)
        XCTAssertEqual(viewModel.activeFilterCount, 3)
    }

    func testVisibleMediaTypeCountsIncludeZeroCountTypes() {
        let viewModel = ExploreMapViewModel()
        viewModel.mediaTypeCounts = [
            ExploreMapMediaTypeCount(mediaType: .video, count: 3),
            ExploreMapMediaTypeCount(mediaType: .audio, count: 1)
        ]

        XCTAssertEqual(viewModel.visibleMediaTypeCounts, [
            ExploreMapMediaTypeCount(mediaType: .image, count: 0),
            ExploreMapMediaTypeCount(mediaType: .video, count: 3),
            ExploreMapMediaTypeCount(mediaType: .audio, count: 1)
        ])
    }

    func testClearingAllFiltersClearsSelection() async {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(id: "selected", latitude: 30.267, mediaKinds: [.audio])
        viewModel.posts = [post]
        viewModel.selectedSpeciesCategories = [.insects]
        viewModel.selectedMediaTypes = [.audio]
        viewModel.selectPost(post.id)

        await viewModel.clearFilters()

        XCTAssertTrue(viewModel.selectedSpeciesCategories.isEmpty)
        XCTAssertTrue(viewModel.selectedMediaTypes.isEmpty)
        XCTAssertNil(viewModel.selectedPostId)
        XCTAssertFalse(viewModel.hasActiveFilters)
    }

    func testFocusCentersSelectsAndClearsAllFilters() {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(id: "focus", latitude: 12.3456)
        viewModel.selectedSpeciesCategories = [.insects]
        viewModel.selectedMediaTypes = [.audio]

        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        XCTAssertEqual(viewModel.posts.map(\.id), [post.id])
        XCTAssertEqual(viewModel.selectedPostId, post.id)
        XCTAssertEqual(viewModel.visibleRegion?.center.latitude ?? .nan, post.latitude, accuracy: 0.0001)
        XCTAssertEqual(viewModel.visibleRegion?.center.longitude ?? .nan, post.longitude, accuracy: 0.0001)
        XCTAssertEqual(viewModel.visibleRegion?.span.latitudeDelta ?? .nan, 0.05, accuracy: 0.0001)
        XCTAssertTrue(viewModel.selectedSpeciesCategories.isEmpty)
        XCTAssertTrue(viewModel.selectedMediaTypes.isEmpty)
        XCTAssertFalse(viewModel.hasActiveFilters)
    }

    func testFocusUsesApproximateRegionForObscuredCoordinates() {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(
            id: "obscured-focus",
            latitude: -23.5,
            coordinateVisibility: .obscured
        )

        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        XCTAssertEqual(viewModel.selectedPostId, post.id)
        XCTAssertEqual(viewModel.visibleRegion?.span.latitudeDelta ?? .nan, 0.2, accuracy: 0.0001)
        XCTAssertEqual(viewModel.visibleRegion?.span.longitudeDelta ?? .nan, 0.2, accuracy: 0.0001)
    }

    func testFocusedCameraCommitPreservesSelectionBeforeUserPan() {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(id: "camera-focus", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        let settledRegion = MKCoordinateRegion(
            center: post.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.08)
        )
        viewModel.markCameraChanged(region: settledRegion)

        XCTAssertEqual(viewModel.selectedPostId, post.id)
        XCTAssertEqual(viewModel.lastCommittedRegion?.span.longitudeDelta ?? .nan, 0.08, accuracy: 0.0001)
        XCTAssertFalse(viewModel.needsSearchInArea)

        let pannedRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: post.latitude + 1,
                longitude: post.longitude
            ),
            span: settledRegion.span
        )
        viewModel.markCameraChanged(region: pannedRegion)

        XCTAssertNil(viewModel.selectedPostId)
        XCTAssertTrue(viewModel.needsSearchInArea)
    }

    func testFocusedCameraCommitTreatsNonContainingFirstRegionAsUserPan() {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(id: "camera-interrupted", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        let pannedRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: post.latitude + 1,
                longitude: post.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        viewModel.markCameraChanged(region: pannedRegion)

        XCTAssertNil(viewModel.selectedPostId)
        XCTAssertTrue(viewModel.needsSearchInArea)
        XCTAssertEqual(
            viewModel.visibleRegion?.center.latitude ?? .nan,
            pannedRegion.center.latitude,
            accuracy: 0.0001
        )
    }

    func testClusterRefreshPreservesFocusedTarget() async {
        let viewModel = ExploreMapViewModel { _ in
            ExploreMapPointsResponse(mode: .clusters, visibleCount: 8)
        }
        let post = makeMapPost(id: "cluster-focus", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        await viewModel.refreshFocusedArea()

        XCTAssertEqual(viewModel.posts.map(\.id), [post.id])
        XCTAssertEqual(viewModel.selectedPostId, post.id)
    }

    func testAuthoritativePostRefreshRemovesMissingFocusedTarget() async {
        let viewModel = ExploreMapViewModel { _ in
            ExploreMapPointsResponse(mode: .posts, visibleCount: 0)
        }
        let post = makeMapPost(id: "missing-focus", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        await viewModel.refreshFocusedArea()

        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertNil(viewModel.selectedPostId)
        XCTAssertNil(viewModel.selectedPost)
    }

    func testFocusSuppressesOlderInFlightMapResponse() async {
        var requestCount = 0
        let stalePost = makeMapPost(id: "stale-map-post", latitude: 40)
        let staleResponse = ExploreMapPointsResponse(
            mode: .posts,
            visibleCount: 1,
            posts: [stalePost]
        )
        let refreshedResponse = ExploreMapPointsResponse(mode: .clusters, visibleCount: 5)
        let viewModel = ExploreMapViewModel { _ in
            requestCount += 1
            if requestCount == 1 {
                try await Task.sleep(for: .milliseconds(75))
                return staleResponse
            }
            return refreshedResponse
        }
        let initialRegion = MKCoordinateRegion(
            center: stalePost.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        viewModel.visibleRegion = initialRegion
        viewModel.lastCommittedRegion = initialRegion

        let staleRequest = Task { await viewModel.searchCurrentArea() }
        while !viewModel.isLoading {
            await Task.yield()
        }

        let focusedPost = makeMapPost(id: "current-focus", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: focusedPost))
        await viewModel.refreshFocusedArea()
        await staleRequest.value

        for _ in 0..<100 {
            if requestCount >= 2, !viewModel.isLoading { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(viewModel.posts.map(\.id), [focusedPost.id])
        XCTAssertEqual(viewModel.selectedPostId, focusedPost.id)
        XCTAssertFalse(viewModel.posts.contains(where: { $0.id == stalePost.id }))
    }

    func testCanonicalPrivacyChangeRemovesFocusedPost() {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(id: "privacy-focus", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        viewModel.syncPosts(from: [
            makeCanonicalPost(from: post, locationSharing: .privateLocation)
        ])

        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertNil(viewModel.selectedPostId)
        XCTAssertNil(viewModel.selectedPost)
    }

    func testExplicitPostRemovalClearsFocusedTarget() {
        let viewModel = ExploreMapViewModel()
        let post = makeMapPost(id: "removed-focus", latitude: 12.3456)
        viewModel.focus(on: ExploreMapFocusTarget(post: post))

        viewModel.removePost(id: post.id)

        XCTAssertTrue(viewModel.posts.isEmpty)
        XCTAssertNil(viewModel.selectedPostId)
    }

    func testFocusTargetMapsPublicDetailPointIntoMapPost() throws {
        let mapPost = makeMapPost(id: "mapped-focus", latitude: 0)
        let canonicalPost = makeCanonicalPost(from: mapPost, locationSharing: .open)
        let detailData = Data("""
        {
            "post_id": "mapped-focus",
            "location_sharing": "open",
            "taxonomy_kingdom": "Animalia",
            "taxonomy_class": "Insecta",
            "map_point": {
                "latitude": 12.3456,
                "longitude": -45.6789,
                "coordinate_visibility": "obscured"
            }
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(ExplorePostDetail.self, from: detailData)

        let target = ExploreMapFocusTarget(post: canonicalPost, detail: detail)

        XCTAssertEqual(target?.post.id, canonicalPost.id)
        XCTAssertEqual(target?.post.latitude ?? .nan, 12.3456, accuracy: 0.0001)
        XCTAssertEqual(target?.post.longitude ?? .nan, -45.6789, accuracy: 0.0001)
        XCTAssertEqual(target?.post.coordinateVisibility, .obscured)
        XCTAssertEqual(target?.post.taxonomyKingdom, "Animalia")
        XCTAssertEqual(target?.post.taxonomyClass, "Insecta")
    }

    func testObservationMapPresentationFailsClosedAndUsesExactOrApproximatePolicy() throws {
        let mapPost = makeMapPost(id: "presentation", latitude: 0)
        let openPost = makeCanonicalPost(from: mapPost, locationSharing: .open)

        func decodeDetail(
            postId: String = "presentation",
            locationSharing: String = "open",
            latitude: Double = 12.3456,
            visibility: String
        ) throws -> ExplorePostDetail {
            let data = Data("""
            {
                "post_id": "\(postId)",
                "location_sharing": "\(locationSharing)",
                "map_point": {
                    "latitude": \(latitude),
                    "longitude": -45.6789,
                    "coordinate_visibility": "\(visibility)"
                }
            }
            """.utf8)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(ExplorePostDetail.self, from: data)
        }

        let exact = try XCTUnwrap(ExploreObservationMapPresentation(
            post: openPost,
            detail: decodeDetail(visibility: "exact")
        ))
        XCTAssertEqual(exact.spanDelta, 0.05, accuracy: 0.0001)
        XCTAssertNil(exact.approximateRadiusMeters)

        let obscured = try XCTUnwrap(ExploreObservationMapPresentation(
            post: openPost,
            detail: decodeDetail(visibility: "obscured")
        ))
        XCTAssertEqual(obscured.spanDelta, 0.2, accuracy: 0.0001)
        XCTAssertEqual(
            obscured.approximateRadiusMeters ?? .nan,
            ExploreObservationMapPresentation.approximateCoordinateRadiusMeters,
            accuracy: 0.0001
        )

        let privatePost = makeCanonicalPost(from: mapPost, locationSharing: .privateLocation)
        XCTAssertNil(ExploreObservationMapPresentation(
            post: privatePost,
            detail: try decodeDetail(visibility: "exact")
        ))
        XCTAssertNil(ExploreObservationMapPresentation(
            post: openPost,
            detail: try decodeDetail(postId: "different-post", visibility: "exact")
        ))
        XCTAssertNil(ExploreObservationMapPresentation(
            post: openPost,
            detail: try decodeDetail(latitude: 200, visibility: "exact")
        ))
    }
}

final class ExplorePostDetailOriginTests: XCTestCase {
    private func makeRoute(origin: ExplorePostDetailOrigin) -> ExplorePostRoute {
        ExplorePostRoute(
            postId: "post-origin",
            shouldFocusCommentComposer: false,
            shouldOpenInsight: false,
            targetCommentId: nil,
            targetReplyParentCommentId: nil,
            origin: origin
        )
    }

    func testOnlyMainFeedOriginEnablesObservationMapNavigation() {
        XCTAssertTrue(makeRoute(origin: .feed).allowsObservationMapNavigation)
        XCTAssertFalse(makeRoute(origin: .map).allowsObservationMapNavigation)
        XCTAssertFalse(makeRoute(origin: .other).allowsObservationMapNavigation)
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

    func testFeedAudioAndVideoUseDedicatedCenterPlaybackZone() {
        XCTAssertTrue(
            ExploreFeedMediaInteractionPolicy.usesCenterPlaybackZone(
                surface: .feed,
                mediaKind: .video,
                hasNavigationAction: true
            )
        )
        XCTAssertTrue(
            ExploreFeedMediaInteractionPolicy.usesCenterPlaybackZone(
                surface: .feed,
                mediaKind: .audio,
                hasNavigationAction: true
            )
        )
        XCTAssertEqual(ExploreFeedMediaInteractionPolicy.centerPlaybackHitSize, 96)
    }

    func testCenterPlaybackZoneDoesNotReplaceImageOrDetailInteractions() {
        XCTAssertFalse(
            ExploreFeedMediaInteractionPolicy.usesCenterPlaybackZone(
                surface: .feed,
                mediaKind: .image,
                hasNavigationAction: true
            )
        )
        XCTAssertFalse(
            ExploreFeedMediaInteractionPolicy.usesCenterPlaybackZone(
                surface: .detail,
                mediaKind: .video,
                hasNavigationAction: true
            )
        )
        XCTAssertFalse(
            ExploreFeedMediaInteractionPolicy.usesCenterPlaybackZone(
                surface: .feed,
                mediaKind: .video,
                hasNavigationAction: false
            )
        )
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

final class ExploreShareMessageFormatterTests: XCTestCase {
    func testImageAndVideoMessagesUseContentFirstCopy() {
        for mediaKind in [ExploreMediaKind.image, .video] {
            XCTAssertEqual(
                ExploreShareMessageFormatter.message(
                    commonName: "Northern Cardinal",
                    postId: "post-123",
                    primaryMediaKind: mediaKind
                ),
                "Check out this Northern Cardinal\nhttps://naturebook.earth/explore/post/post-123"
            )
        }
    }

    func testAudioMessageInvitesRecipientToListen() {
        XCTAssertEqual(
            ExploreShareMessageFormatter.message(
                commonName: "Northern Cardinal",
                postId: "post-123",
                primaryMediaKind: .audio
            ),
            "Listen to this Northern Cardinal\nhttps://naturebook.earth/explore/post/post-123"
        )
    }

    func testMissingMediaUsesCheckOutFallback() {
        XCTAssertEqual(
            ExploreShareMessageFormatter.message(
                commonName: "Northern Cardinal",
                postId: "post-123",
                primaryMediaKind: nil
            ),
            "Check out this Northern Cardinal\nhttps://naturebook.earth/explore/post/post-123"
        )
    }

    func testPrimaryMediaKindControlsMixedMediaCopy() {
        let mediaItems = [
            ExploreMediaItem(
                kind: .video,
                url: "https://example.com/cardinal.mp4",
                thumbnailUrl: nil,
                orderIndex: 0,
                durationSeconds: 4,
                hasAudio: true
            ),
            ExploreMediaItem(
                kind: .audio,
                url: "https://example.com/cardinal.m4a",
                thumbnailUrl: nil,
                orderIndex: 1,
                durationSeconds: 8,
                hasAudio: true
            )
        ]

        XCTAssertEqual(
            ExploreShareMessageFormatter.message(
                commonName: "Northern Cardinal",
                postId: "post-123",
                primaryMediaKind: mediaItems.first?.kind
            ),
            "Check out this Northern Cardinal\nhttps://naturebook.earth/explore/post/post-123"
        )
    }

    func testMessageExcludesAppScientificLocationAndAuthorCopy() {
        let message = ExploreShareMessageFormatter.message(
            commonName: "Northern Cardinal",
            postId: "post-123",
            primaryMediaKind: .image
        )

        XCTAssertFalse(message.contains("Merian"))
        XCTAssertFalse(message.contains("Explore post"))
        XCTAssertFalse(message.contains("Cardinalis cardinalis"))
        XCTAssertFalse(message.contains("Chicago"))
        XCTAssertFalse(message.contains("@author"))
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

final class ProfilePublicationRecoverySummaryTests: XCTestCase {
    func testRecoveryNoticeIsHiddenWhenUnavailableScansAreAllPrivate() {
        let stats = ProfileSocialStats(
            followerCount: 0,
            followingCount: 0,
            visiblePublishedPostCount: 0,
            publicationIntentCount: 0,
            recoveryNeededPostCount: 5,
            degradedPostCount: 0,
            quarantinedPostCount: 5
        )

        XCTAssertNil(ProfilePublicationRecoverySummary.publishedOnly(from: stats))
    }

    func testRecoveryNoticeOnlyTalliesPublishedScans() throws {
        let stats = ProfileSocialStats(
            followerCount: 0,
            followingCount: 0,
            visiblePublishedPostCount: 2,
            publicationIntentCount: 3,
            recoveryNeededPostCount: 5,
            degradedPostCount: 0,
            quarantinedPostCount: 5
        )

        let summary = try XCTUnwrap(
            ProfilePublicationRecoverySummary.publishedOnly(from: stats)
        )

        XCTAssertEqual(summary.recoveryNeededCount, 3)
        XCTAssertEqual(summary.quarantinedCount, 3)
    }

    func testRecoveryNoticeUsesUserFacingCopy() {
        let summary = ProfilePublicationRecoverySummary(
            publicationIntentCount: 41,
            visibleCount: 34,
            recoveryNeededCount: 5,
            quarantinedCount: 5
        )

        XCTAssertEqual(summary.userFacingTitle, "5 published scans need attention")
        XCTAssertEqual(
            summary.userFacingMessage,
            "Their media isn’t available, so they’re temporarily hidden from Explore. "
                + "Your posts and activity are safe."
        )
        XCTAssertEqual(
            summary.userFacingEmptyMessage,
            "Your published scans are temporarily hidden until their media is available again."
        )
    }

    func testRecoveryNoticeUsesSingularLanguage() {
        let summary = ProfilePublicationRecoverySummary(
            publicationIntentCount: 1,
            visibleCount: 0,
            recoveryNeededCount: 1,
            quarantinedCount: 1
        )

        XCTAssertEqual(summary.userFacingTitle, "1 published scan needs attention")
        XCTAssertEqual(
            summary.userFacingMessage,
            "Its media isn’t available, so it’s temporarily hidden from Explore. "
                + "Your posts and activity are safe."
        )
    }

    func testRecoveryNoticeDismissalSignatureChangesWithPublishedTotals() {
        let summary = ProfilePublicationRecoverySummary(
            publicationIntentCount: 41,
            visibleCount: 34,
            recoveryNeededCount: 5,
            quarantinedCount: 5
        )
        let changedSummary = ProfilePublicationRecoverySummary(
            publicationIntentCount: 42,
            visibleCount: 34,
            recoveryNeededCount: 6,
            quarantinedCount: 6
        )

        XCTAssertEqual(summary.overviewDismissalSignature, "41:34:5:5")
        XCTAssertNotEqual(
            summary.overviewDismissalSignature,
            changedSummary.overviewDismissalSignature
        )
    }

    func testRecoveryNoticeDismissalIsAccountScopedAndClearable() throws {
        let suiteName = "ProfilePublicationRecoveryOverviewPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstOwnerID = UUID().uuidString
        let secondOwnerID = UUID().uuidString
        let signature = "41:34:5:5"

        ProfileRecoveryNoticePreferences.dismiss(
            signature: signature,
            ownerUserID: firstOwnerID,
            defaults: defaults
        )

        XCTAssertEqual(
            ProfileRecoveryNoticePreferences.dismissedSignature(
                ownerUserID: firstOwnerID.uppercased(),
                defaults: defaults
            ),
            signature
        )
        XCTAssertNil(
            ProfileRecoveryNoticePreferences.dismissedSignature(
                ownerUserID: secondOwnerID,
                defaults: defaults
            )
        )

        ProfileRecoveryNoticePreferences.clear(
            ownerUserID: firstOwnerID,
            defaults: defaults
        )
        XCTAssertNil(
            ProfileRecoveryNoticePreferences.dismissedSignature(
                ownerUserID: firstOwnerID,
                defaults: defaults
            )
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
        MerianNetworkClient.shared.overridingAuthUserID = UUID(
            uuidString: "11111111-1111-4111-8111-111111111111"
        )
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
