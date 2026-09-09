import Foundation
import SwiftData
import Testing

@testable import Merian

extension ScanRepositoryTests {
    // MARK: - Deletion queueing

    @Test func testEradicateScanQueuesPendingCloudDeletionAndRemovesRecord() async throws {
        let ctx = try ScanRepositoryTestSupport.makeContext()
        let record = LocalScanRecord(
            speciesId: "delete-queueing",
            scientificName: "Cardinalis cardinalis",
            commonName: "Northern Cardinal"
        )
        ctx.insert(record)
        try ctx.save()

        let offlineQueue = OfflineQueueManager.shared
        let originalOnline = offlineQueue.isOnline
        defer { offlineQueue.isOnline = originalOnline }
        offlineQueue.modelContext = ctx
        offlineQueue.isOnline = false

        let cleanup = ScanRepository.shared.eradicateScan(record: record, modelContext: ctx)
        await cleanup?.value

        let recordId = record.id
        let recordDescriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == recordId })
        let deletionDescriptor = FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == recordId })

        #expect(try ctx.fetch(recordDescriptor).isEmpty, "eradicateScan must remove the local record immediately after queueing cloud deletion")
        #expect(try ctx.fetch(deletionDescriptor).count == 1, "eradicateScan must persist exactly one pending cloud deletion task")
    }

    @Test func testEradicateScanReusesExistingPendingCloudDeletionTask() async throws {
        let ctx = try ScanRepositoryTestSupport.makeContext()
        let record = LocalScanRecord(
            speciesId: "delete-idempotency",
            scientificName: "Cyanocitta cristata",
            commonName: "Blue Jay"
        )
        let existingTask = PendingCloudDeletionTask(scanId: record.id, timestamp: Date(timeIntervalSince1970: 123))

        ctx.insert(record)
        ctx.insert(existingTask)
        try ctx.save()

        let offlineQueue = OfflineQueueManager.shared
        let originalOnline = offlineQueue.isOnline
        defer { offlineQueue.isOnline = originalOnline }
        offlineQueue.modelContext = ctx
        offlineQueue.isOnline = false

        let cleanup = ScanRepository.shared.eradicateScan(record: record, modelContext: ctx)
        await cleanup?.value

        let recordId = record.id
        let recordDescriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == recordId })
        let deletionDescriptor = FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == recordId })
        let remainingTasks = try ctx.fetch(deletionDescriptor)

        #expect(try ctx.fetch(recordDescriptor).isEmpty, "eradicateScan should still delete the local record when a deletion task already exists")
        #expect(remainingTasks.count == 1, "eradicateScan must not duplicate pending cloud deletion tasks for the same scan")
        #expect(remainingTasks.first?.timestamp == existingTask.timestamp, "The existing pending cloud deletion task should be reused unchanged")
    }

}
