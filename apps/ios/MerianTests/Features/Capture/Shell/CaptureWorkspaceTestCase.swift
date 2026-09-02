import CoreData
import MapKit
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Merian

@MainActor
final class CaptureWorkspaceViewModelRefinementTests: OfflineQueueTestCase {
    static let entitlementTestUserID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000778"
    )!

    var previousProState = false
    var previousSubscribedState = false

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

    func makePNGData(color: UIColor = .systemTeal) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    func makePreviewCGImage(color: UIColor = .systemTeal) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return image.cgImage ?? UIImage(systemName: "photo")!.cgImage!
    }

    func makeUIImage(color: UIColor = .systemTeal) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    func makePreparedStagedImage(color: UIColor = .systemTeal) -> PreparedStagedImage {
        PreparedStagedImage(
            compressedData: makePNGData(color: color),
            displayData: makePNGData(color: .systemBlue),
            historicalContext: nil,
            previewCGImage: SendableCGImage(image: makePreviewCGImage(color: color))
        )
    }

    func waitUntil(
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

    func deliverRoute(
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

    func makeModelContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    func enableUnlimitedFreeScansForTest() {
        let deviceId = DeviceIdentityManager.shared.deviceId
        UserDefaults.standard.removeObject(forKey: "Merian_LastScanDate_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "Merian_ScansUsedToday_\(deviceId)")
        UsageManager.debugFreeScanLimitOverride = true
        UsageManager.shared.evaluateDailyRefresh()
        activatePaidEntitlementAccountForTest()
    }

    func restoreFreeScanLimitForTest() {
        let deviceId = DeviceIdentityManager.shared.deviceId
        UserDefaults.standard.removeObject(forKey: "Merian_LastScanDate_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "Merian_ScansUsedToday_\(deviceId)")
        UsageManager.debugFreeScanLimitOverride = nil
        UsageManager.shared.evaluateDailyRefresh()
        resetEntitlementAccountForTest()
    }

    func activatePaidEntitlementAccountForTest() {
        EntitlementManager.shared.resetForTesting(
            userID: Self.entitlementTestUserID
        )
    }

    func resetEntitlementAccountForTest() {
        EntitlementManager.shared.resetForTesting()
    }

    func makeTempAudioFilename(prefix: String = "capture_vm_audio") throws -> String {
        let filename = "\(prefix)_\(UUID().uuidString).wav"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try makeInferenceTestPCM16WAVData().write(to: url)
        return filename
    }

    func makeTempVideoFilename(prefix: String = "capture_vm_video") throws -> String {
        let filename = "\(prefix)_\(UUID().uuidString).mp4"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try Data(repeating: 0x56, count: 256).write(to: url)
        return filename
    }

    func cleanupQueuedScans(in context: ModelContext) {
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

}
