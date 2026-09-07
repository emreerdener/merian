import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite(
    "Background Inference Recovery",
    .serialized,
    .sharedProcessState(.offlineQueueManager)
)
@MainActor
struct BackgroundInferenceRecoveryTests {
    @Test func testFoundServerStatusPersistsOwnershipBeforeLocalHydration() throws {
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        manager.modelContext = context
        defer {
            OfflineJobScheduler.shared.cancelScheduledWake(using: manager)
            manager.modelContext = originalContext
        }
        let scanId = UUID().uuidString
        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .inferencing
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        manager.persistServerStatus(
            scanId: scanId,
            response: ScanStatusResponse(
                scanId: scanId,
                status: .found,
                jobStatus: nil,
                jobStage: nil,
                jobAttemptCount: nil,
                retryAfter: nil,
                lastError: nil
            )
        )

        #expect(manager.hasDurableCompletedServerResult(scanId: scanId))
        #expect(
            scan.queueLastErrorCode ==
                OfflineQueueManager.completedServerResultRecoveryCode
        )
        #expect(
            job.lastErrorCode ==
                OfflineQueueManager.completedServerResultRecoveryCode
        )
        #expect(scan.queueState == .inferencing)
    }

    @Test func testCompletedServerResultContractMismatchPausesWithoutRetryLoop() throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        defer {
            OfflineJobScheduler.shared.cancelScheduledWake(using: manager)
            manager.modelContext = originalContext
        }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        let scanId = UUID().uuidString
        let retryAfter = Date().addingTimeInterval(60)
        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .inferencing,
            queueAttemptCount: 0
        )
        scan.queueLastServerStatus = "complete"
        scan.queueLastServerStage = "media_finalization_complete"
        scan.queueLastServerRetryAfter = retryAfter
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running
        )
        job.serverStatus = "complete"
        job.serverStage = "media_finalization_complete"
        job.serverRetryAfter = retryAfter
        context.insert(scan)
        context.insert(job)
        try context.save()

        #expect(
            manager.markCompletedServerResultContractMismatch(
                scanId: scanId
            )
        )

        #expect(scan.queueState == .failed)
        #expect(scan.queueNeedsAttention)
        #expect(scan.queueAttemptCount == 0)
        #expect(scan.queueNextRetryAt == nil)
        #expect(
            scan.queueLastErrorCode ==
                OfflineQueueManager.completedServerResultContractMismatchCode
        )
        #expect(scan.queueLastServerStatus == "complete")
        #expect(scan.queueLastServerStage == "media_finalization_complete")
        #expect(scan.queueLastServerRetryAfter == retryAfter)
        #expect(job.status == .needsAttention)
        #expect(job.attemptCount == 0)
        #expect(job.nextRunAt == nil)
        #expect(
            job.lastErrorCode ==
                OfflineQueueManager.completedServerResultContractMismatchCode
        )
        #expect(job.serverStatus == "complete")
        #expect(job.serverStage == "media_finalization_complete")
        #expect(job.serverRetryAfter == retryAfter)
        #expect(manager.hasDurableCompletedServerResult(scanId: scanId))
    }
}
