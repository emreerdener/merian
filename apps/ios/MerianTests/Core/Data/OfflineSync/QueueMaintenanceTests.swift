import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct QueueMaintenanceTests {
    @MainActor
    private struct ManagerState {
        let modelContext: ModelContext?
        let unsyncedItemsCount: Int

        init(manager: OfflineQueueManager) {
            modelContext = manager.modelContext
            unsyncedItemsCount = manager.unsyncedItemsCount
        }

        func restore(manager: OfflineQueueManager) {
            manager.modelContext = modelContext
            manager.unsyncedItemsCount = unsyncedItemsCount
        }
    }

    @Test func softDeleteTransitionsToFailedState() throws {
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let manager = OfflineQueueManager.shared
        let originalState = ManagerState(manager: manager)
        defer { originalState.restore(manager: manager) }
        manager.modelContext = context

        let scanId = UUID().uuidString
        context.insert(OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .pending
        ))
        try context.save()

        let didDelete = manager.softDeleteQueuedScan(scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let fetched = try context.fetch(descriptor).first
        #expect(didDelete)
        #expect(fetched?.queueState == .failed)
        #expect(fetched?.queueNeedsAttention == true)
    }

    @Test func unsyncedCountIncludesOnlyAutomaticallyRunnableScans() throws {
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let manager = OfflineQueueManager.shared
        let originalState = ManagerState(manager: manager)
        defer { originalState.restore(manager: manager) }
        manager.modelContext = context

        let runnableScan = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .pending
        )
        context.insert(runnableScan)
        context.insert(OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .staged,
            queueNeedsAttention: true
        ))
        context.insert(OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .failed
        ))
        context.insert(OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .externalImport
        ))
        try context.save()

        manager.updateUnsyncedItemCount()

        #expect(manager.unsyncedItemsCount == 1)

        // Background sync writes through a separate context. The observable
        // badge must read the committed store rather than a cached main-context
        // copy.
        let backgroundContext = ModelContext(context.container)
        let runnableId = runnableScan.id
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == runnableId }
        )
        let backgroundScan = try #require(
            backgroundContext.fetch(descriptor).first
        )
        backgroundScan.queueNeedsAttention = true
        try backgroundContext.save()

        manager.updateUnsyncedItemCount()

        #expect(manager.unsyncedItemsCount == 0)
    }

    @Test func purgeRemovesOnlyNonActionableFailedScans() throws {
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let manager = OfflineQueueManager.shared
        let originalState = ManagerState(manager: manager)
        defer { originalState.restore(manager: manager) }
        manager.modelContext = context

        let purgeableId = UUID().uuidString
        let attentionId = UUID().uuidString
        let pendingId = UUID().uuidString
        context.insert(OfflineQueuedScan(
            id: purgeableId,
            timestamp: Date(),
            scanState: .failed,
            queueNeedsAttention: false
        ))
        context.insert(OfflineQueuedScan(
            id: attentionId,
            timestamp: Date(),
            scanState: .failed,
            queueNeedsAttention: true
        ))
        context.insert(OfflineQueuedScan(
            id: pendingId,
            timestamp: Date(),
            scanState: .pending
        ))
        try context.save()

        manager.purgeSoftDeletedRecords()

        let descriptor = FetchDescriptor<OfflineQueuedScan>()
        let remainingIds = Set(try context.fetch(descriptor).map(\.id))
        #expect(!remainingIds.contains(purgeableId))
        #expect(remainingIds.contains(attentionId))
        #expect(remainingIds.contains(pendingId))
    }

    @Test func flushRemovesQueueRecordAndPreferredGoalHint() throws {
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let manager = OfflineQueueManager.shared
        let originalState = ManagerState(manager: manager)
        defer { originalState.restore(manager: manager) }
        manager.modelContext = context

        let scanId = UUID().uuidString
        context.insert(OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            scanState: .pending
        ))
        context.insert(ActiveOfflineQueuedScanGoalHint(
            scanId: scanId,
            userFieldTripId: "queue-maintenance-trip",
            itemId: "queue-maintenance-goal"
        ))
        try context.save()

        let didFlush = manager.flushOfflineQueuedScan(scanId: scanId)

        let queueDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let hintDescriptor = FetchDescriptor<ActiveOfflineQueuedScanGoalHint>(
            predicate: #Predicate { $0.scanId == scanId }
        )
        #expect(didFlush)
        #expect(try context.fetch(queueDescriptor).isEmpty)
        #expect(try context.fetch(hintDescriptor).isEmpty)
    }
}
