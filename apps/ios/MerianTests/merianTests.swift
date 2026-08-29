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
