import XCTest
import CoreData
import UIKit
import SwiftData
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

    func testStartRefinementScanStagesPreparedHistoricalImage() async throws {
        let expectedCompressedData = makePNGData()
        let expectedFileURL = URL.documentsDirectory.appendingPathComponent("historical-refinement.webp")
        let expectedDisplaySignature = Data("\(expectedFileURL.path)|memory-map".utf8)
        let expectedPreviewCGImage = SendableCGImage(image: makePreviewCGImage())

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
            coverImagePath: "historical-refinement.webp"
        )

        viewModel.startRefinementScan(from: record)
        try await waitUntil { !viewModel.isStagingRefinement }

        XCTAssertEqual(viewModel.baseRefinementRecord?.id, record.id)
        XCTAssertEqual(viewModel.requestedCaptureMode, CaptureMode.describe)
        XCTAssertEqual(viewModel.stagedCapture.images.count, 1)
        XCTAssertEqual(viewModel.stagedCapture.images.first?.compressedData, expectedCompressedData)
        XCTAssertEqual(viewModel.stagedCapture.images.first?.displayData, expectedDisplaySignature)
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

    func testMultiCaptureDescribeStagesUntilIdentify() throws {
        let previousMultiCapture = UserDefaults.standard.bool(forKey: "isMultiCaptureEnabled")
        let previousRequiresConfirmation = UserDefaults.standard.bool(forKey: "requiresScanConfirmation")
        defer {
            UserDefaults.standard.set(previousMultiCapture, forKey: "isMultiCaptureEnabled")
            UserDefaults.standard.set(previousRequiresConfirmation, forKey: "requiresScanConfirmation")
        }

        UserDefaults.standard.set(true, forKey: "isMultiCaptureEnabled")
        UserDefaults.standard.set(false, forKey: "requiresScanConfirmation")

        let viewModel = CaptureWorkspaceViewModel(
            diContainer: .preview,
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
