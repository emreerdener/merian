import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Capture identity admission", .serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureIdentityAdmissionTests {
    @Test func identityFenceClosingDuringMediaStagingRejectsPersistence() async throws {
        let harness = CaptureAdmissionTests()
        harness.enableUnlimitedFreeScansForTest()
        defer { harness.restoreFreeScanLimitForTest() }
        let manager = OfflineQueueManager.shared
        let snapshot = CaptureAdmissionTests.ManagerSnapshot(manager)
        defer { snapshot.restore(manager) }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = false
        // Admission succeeds before staging; the final owner check represents
        // an identity transition closing the fence during the file-write await.
        manager.captureLibraryAdmission = { expectedOwner in expectedOwner == nil }
        let accepted = await withCheckedContinuation { continuation in
            manager.enqueueCapture(
                imageDatas: [Data("fenced_capture".utf8)], telemetry: harness.dummyTelemetry,
                startSyncImmediately: false,
                onQueued: { continuation.resume(returning: $0) }
            )
        }
        #expect(!accepted)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

}
