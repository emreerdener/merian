import Foundation
import os
import SwiftData
import Testing
@testable import Merian

@Suite("Cloud Deletion Intent", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct CloudDeletionIntentTests {
    @Test func provenanceSurvivesDuplicateEnqueueWithoutRetagging() throws {
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let id = UUID().uuidString.lowercased()
        try context.ensurePendingCloudDeletionTask(scanId: id,
            requestingAccountID: CloudDeletionTestSupport.accountID, origin: .reanalysisReplacement)
        try context.save()
        try context.ensurePendingCloudDeletionTask(scanId: id,
            requestingAccountID: CloudDeletionTestSupport.otherAccountID, origin: .explicitUserDeletion)
        try context.save()
        let fresh = ModelContext(context.container)
        let job = try #require(try fresh.fetchOfflineJob(id: "cloud-deletion:\(id)"))
        let intent = try #require(CloudDeletionIntent.restoring(job.metadataJSON, scanID: id))
        #expect(intent.requestingAccountID == CloudDeletionTestSupport.accountID)
        #expect(intent.origin == .reanalysisReplacement)
        #expect(CloudDeletionIntent.restoring(job.metadataJSON, scanID: "another-scan") == nil)
    }

    @Test func legacyIntentIsHeldAcrossDiskReopenAndCannotAcquireAuthority() async throws {
        let manager = OfflineQueueManager.shared
        let original = (manager.modelContext, manager.isOnline, manager.isCloudDeletionSyncing)
        let scheduler = CloudDeletionTestSupport.scheduler()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            scheduler.cancelScheduledWake(using: manager)
            manager.modelContext = original.0
            manager.isOnline = original.1
            manager.isCloudDeletionSyncing = original.2
            try? FileManager.default.removeItem(at: directory)
        }
        let schema = Schema(CurrentSchema.models)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("legacy.sqlite"))
        let id = UUID().uuidString.lowercased()
        manager.isOnline = true
        manager.isCloudDeletionSyncing = false
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            manager.modelContext = context
            context.insert(PendingCloudDeletionTask(scanId: id))
            try context.save()
            // A fresh request cannot turn a persisted legacy replacement into a user deletion.
            try context.ensurePendingCloudDeletionTask(scanId: id,
                requestingAccountID: CloudDeletionTestSupport.accountID, origin: .explicitUserDeletion)
            try context.save()
            await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(), scheduler: scheduler) { _, _ in
                Issue.record("Unproven deletion must never dispatch")
            }
            manager.modelContext = nil
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let read = ModelContext(reopened)
        manager.modelContext = read
        let job = try #require(try read.fetchOfflineJob(id: "cloud-deletion:\(id)"))
        #expect(job.status == .needsAttention)
        #expect(job.lastErrorCode == CloudDeletionIntent.legacyHoldCode)
        #expect(job.metadataJSON == nil)
        #expect(job.nextRunAt == nil)
        #expect(try read.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 1)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
    }

    @Test func foreignAccountWaitsUntilOriginalAccountReturns() async throws {
        let manager = OfflineQueueManager.shared
        let original = (manager.modelContext, manager.isOnline, manager.isCloudDeletionSyncing)
        let scheduler = CloudDeletionTestSupport.scheduler(owner: CloudDeletionTestSupport.otherAccountID)
        let ownerScheduler = CloudDeletionTestSupport.scheduler()
        defer {
            scheduler.cancelScheduledWake(using: manager)
            ownerScheduler.cancelScheduledWake(using: manager)
            manager.modelContext = original.0
            manager.isOnline = original.1
            manager.isCloudDeletionSyncing = original.2
        }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = true
        manager.isCloudDeletionSyncing = false
        let id = UUID().uuidString.lowercased()
        try context.ensurePendingCloudDeletionTask(scanId: id,
            requestingAccountID: CloudDeletionTestSupport.accountID, origin: .nonBiologicalRetention)
        let job = try #require(try context.fetchOfflineJob(id: "cloud-deletion:\(id)"))
        job.nextRunAt = .distantPast
        try context.save()
        await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(owner: CloudDeletionTestSupport.otherAccountID), scheduler: scheduler) { _, _ in
            Issue.record("Another account must not dispatch this deletion")
        }
        #expect(job.status == .pending)
        #expect(job.nextRunAt == .distantPast)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let auth = AuthSessionLifecycleCoordinatorHarness(userID: CloudDeletionTestSupport.accountID)
        auth.resumeCloudDeletions = {
            await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(), scheduler: ownerScheduler) { scanID, owner in
                #expect(scanID == id)
                #expect(owner == CloudDeletionTestSupport.accountID)
                calls.withLock { $0 += 1 }
            }
        }
        // Only the auth event returns the owner; no foreground or reconnect.
        await AuthSessionLifecycleCoordinator(dependencies: auth.dependencies())
            .handle(auth.event(origin: .runtimeTransition))
        #expect(calls.withLock { $0 } == 1)
        #expect(try context.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 0)
    }

    @Test func accountReturnRestartsDiscoveryBeforeEarlierForeignCursor() async throws {
        let manager = OfflineQueueManager.shared
        let original = (manager.modelContext, manager.isOnline, manager.isCloudDeletionSyncing)
        let scheduler = CloudDeletionTestSupport.scheduler()
        let otherScheduler = CloudDeletionTestSupport.scheduler(owner: CloudDeletionTestSupport.otherAccountID)
        defer {
            scheduler.cancelScheduledWake(using: manager)
            otherScheduler.cancelScheduledWake(using: manager)
            manager.modelContext = original.0
            manager.isOnline = original.1
            manager.isCloudDeletionSyncing = original.2
        }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        context.autosaveEnabled = false
        manager.modelContext = context
        manager.isOnline = true
        manager.isCloudDeletionSyncing = false
        var ids: [String] = []
        for index in 0..<401 {
            let id = String(format: "%08x-0000-4000-8000-00000000d399", index)
            ids.append(id)
            try context.ensurePendingCloudDeletionTask(scanId: id, timestamp: .distantPast,
                requestingAccountID: CloudDeletionTestSupport.accountID, origin: .explicitUserDeletion)
        }
        try context.save()
        // The other account consumes a whole discovery budget without offering work.
        await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(owner: CloudDeletionTestSupport.otherAccountID), scheduler: otherScheduler) { _, _ in
            Issue.record("Foreign work must remain private")
        }
        let cursor = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.cloudDeletionDiscoveryJobID))
        #expect(cursor.metadataJSON != nil)
        otherScheduler.cancelScheduledWake(using: manager)
        manager.modelContext = ModelContext(context.container)
        let sent = OSAllocatedUnfairLock(initialState: [String]())
        let auth = AuthSessionLifecycleCoordinatorHarness(userID: CloudDeletionTestSupport.accountID)
        auth.resumeCloudDeletions = {
            await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(), scheduler: scheduler) { id, _ in
                sent.withLock { $0.append(id) }
            }
        }
        await AuthSessionLifecycleCoordinator(dependencies: auth.dependencies())
            .handle(auth.event(origin: .runtimeTransition))
        // Keeping the old cursor would send only the last task and strand the prefix.
        #expect(Set(sent.withLock { $0 }) == Set(ids.prefix(200)))
    }

    @Test func staleLeaseDoesNotAcknowledgeCompletedTransport() async throws {
        let manager = OfflineQueueManager.shared
        let original = (manager.modelContext, manager.isOnline, manager.isCloudDeletionSyncing)
        let scheduler = CloudDeletionTestSupport.scheduler()
        defer {
            scheduler.cancelScheduledWake(using: manager)
            manager.modelContext = original.0
            manager.isOnline = original.1
            manager.isCloudDeletionSyncing = original.2
        }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = true
        manager.isCloudDeletionSyncing = false
        let id = UUID().uuidString.lowercased()
        try context.ensurePendingCloudDeletionTask(scanId: id,
            requestingAccountID: CloudDeletionTestSupport.accountID, origin: .explicitUserDeletion)
        try context.save()
        let current = OSAllocatedUnfairLock(initialState: true)
        var finished = false
        var work = CloudDeletionTestSupport.accountWork()
        work.isCurrent = { _ in current.withLock { $0 } }
        work.finish = { _ in finished = true }
        await manager.syncPendingDeletions(accountWork: work, scheduler: scheduler) { _, _ in
            current.withLock { $0 = false }
        }
        #expect(finished)
        #expect(try context.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 1)
        let job = try #require(try context.fetchOfflineJob(id: "cloud-deletion:\(id)"))
        #expect(job.status == .running)
        #expect(job.lastErrorCode == nil)
        #expect(!manager.isCloudDeletionSyncing)
    }

    @Test(arguments: ["{}", "{", "{\"version\":2}", String(repeating: "x", count: 2049)])
    func malformedMetadataNeverAuthorizesDeletion(json: String) {
        #expect(CloudDeletionIntent.restoring(json, scanID: UUID().uuidString) == nil)
    }
}
