import XCTest
import CoreData
import UIKit
import SwiftData
import SwiftUI
@testable import Merian

final class merianTests: XCTestCase {
    func testModelStoreRecoveryRejectsNonCorruptionFailures() {
        let migrationError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: [NSLocalizedDescriptionKey: "Persistent store is incompatible with the current model version."]
        )

        XCTAssertFalse(ModelStoreRecoveryCoordinator.shouldAttemptRecovery(for: migrationError))
    }

    func testModelStoreRecoveryAcceptsSQLiteCorruptionFailures() {
        let corruptionError = NSError(
            domain: NSSQLiteErrorDomain,
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "database disk image is malformed"]
        )

        XCTAssertTrue(ModelStoreRecoveryCoordinator.shouldAttemptRecovery(for: corruptionError))
    }

    func testModelStoreRecoveryQuarantinesStoreArtifacts() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, conformingTo: .directory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("default.store")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")

        try Data("store".utf8).write(to: storeURL)
        try Data("shm".utf8).write(to: shmURL)
        try Data("wal".utf8).write(to: walURL)

        let quarantineDirectory = try ModelStoreRecoveryCoordinator.quarantineStoreArtifacts(at: storeURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineDirectory.appendingPathComponent("default.store").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineDirectory.appendingPathComponent("default.store-shm").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineDirectory.appendingPathComponent("default.store-wal").path))
    }
}

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

    private func cleanupQueuedScans(in context: ModelContext) {
        let scans = (try? context.fetch(FetchDescriptor<OfflineQueuedScan>())) ?? []
        for scan in scans {
            for item in scan.capturedMediaSnapshot.items {
                switch item {
                case .image(let reference), .audio(let reference):
                    if let targetURL = reference.resolvedURL {
                        try? FileManager.default.removeItem(at: targetURL)
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
        let expectedDisplaySignature = Data("\(expectedFileURL.path)|memory-map".utf8)
        let expectedPreviewCGImage = SendableCGImage(image: makePreviewCGImage())
        try expectedCompressedData.write(to: expectedFileURL)
        defer { try? FileManager.default.removeItem(at: expectedFileURL) }

        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { request in
                let strategyLabel = switch request.displayDataStrategy {
                case .reencodeDisplaySized:
                    "reencode"
                case .memoryMapOriginalFile:
                    "memory-map"
                }

                return PreparedStagedImage(
                    compressedData: expectedCompressedData,
                    displayData: Data("\(request.fileURL.path)|\(strategyLabel)".utf8),
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

        XCTAssertEqual(viewModel.baseRefinementRecord?.id, record.id)
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

        XCTAssertEqual(viewModel.baseRefinementRecord?.id, record.id)
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

        viewModel.baseRefinementRecord = LocalScanRecord(
            speciesId: "species-3",
            scientificName: "Bubo virginianus",
            commonName: "Great Horned Owl"
        )
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

    func testExploreDeepLinkSurvivesImmediateSessionTimeoutReset() async throws {
        let postId = "widget-post-123"
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
            preparedImageLoader: { _ in nil },
            prewarmHeadersOnInit: false
        )

        AppEventPublisher.shared.send(.appDidEnterActivePhaseWithExplorePost(postId: postId))
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
            authorAvatarUrl: nil,
            speciesCommonName: "Monarch Butterfly",
            speciesScientificName: "Danaus plexippus",
            publicLocationLabel: "Austin, TX",
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

    private func rgbaPixel(in image: UIImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        guard let cgImage = image.cgImage,
              let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
            XCTFail("Failed to crop pixel from rendered image")
            return (0, 0, 0, 0)
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
            return (0, 0, 0, 0)
        }

        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    private func assertPixel(
        _ pixel: (r: UInt8, g: UInt8, b: UInt8, a: UInt8),
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
