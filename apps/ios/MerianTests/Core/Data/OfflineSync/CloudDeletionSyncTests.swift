import Foundation
import os
@testable import Merian
import SwiftData
import Testing

@Suite("Cloud Deletion Sync", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct CloudDeletionSyncTests {
    @Test func cloudDeletionRequiresExplicitNetworkConfirmation() {
        #expect(
            OfflineQueueManager.cloudDeletionWasConfirmed(error: nil)
        )
        #expect(
            !OfflineQueueManager.cloudDeletionWasConfirmed(
                error: MerianError.invalidResponse
            )
        )
        #expect(
            !OfflineQueueManager.cloudDeletionWasConfirmed(
                error: MerianError.httpError(
                    statusCode: 503,
                    message: "Temporary failure"
                )
            )
        )
        #expect(
            !OfflineQueueManager.cloudDeletionWasConfirmed(
                error: URLError(.notConnectedToInternet)
            )
        )
    }

    @Test func cloudDeletionRetriesNeverEnterAnUnrecoverableState() {
        for status in [
            OfflineJobStatus.needsAttention,
            .complete,
            .cancelled
        ] {
            #expect(
                OfflineQueueManager.cloudDeletionStatusRequiresRecovery(status)
            )
        }
        for status in [
            OfflineJobStatus.pending,
            .running,
            .waiting
        ] {
            #expect(
                !OfflineQueueManager.cloudDeletionStatusRequiresRecovery(status)
            )
        }

        #expect(
            OfflineQueueManager.nextCloudDeletionRetryAttempt(after: -1) == 1
        )
        #expect(
            OfflineQueueManager.nextCloudDeletionRetryAttempt(after: 0) == 1
        )
        #expect(
            OfflineQueueManager.nextCloudDeletionRetryAttempt(
                after: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
            ) == OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        )
        #expect(
            OfflineQueueManager.nextCloudDeletionRetryAttempt(after: .max)
                == OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        )
    }

    @Test func cloudDeletionDrainIsProcessSingleFlight() async throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let originalIsOnline = manager.isOnline
        let originalIsSyncing = manager.isCloudDeletionSyncing
        defer {
            manager.isCloudDeletionSyncing = originalIsSyncing
            manager.isOnline = originalIsOnline
            manager.modelContext = originalContext
        }

        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        let scanId = UUID().uuidString.lowercased()
        context.insert(PendingCloudDeletionTask(scanId: scanId))
        try context.save()
        manager.isOnline = true
        // Simulate a first foreground wake source already owning the drain.
        manager.isCloudDeletionSyncing = true

        await manager.syncPendingDeletions()

        let pending = try context.fetch(
            FetchDescriptor<PendingCloudDeletionTask>()
        )
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>())
        #expect(pending.map(\.scanId) == [scanId])
        #expect(jobs.isEmpty)
        #expect(manager.isCloudDeletionSyncing)
    }

    @Test func onlyExplicitHistoryRefusalCreatesAHold() {
        let code = OfflineQueueManager.cloudDeletionHistoryHoldCode
        #expect(OfflineQueueManager.cloudDeletionRequiresHistoryReview(
            error: MerianError.httpError(statusCode: 409, message: "{\"code\":\"\(code)\"}")
        ))
        let errors: [Error] = [
            MerianError.httpError(statusCode: 503, message: "{\"code\":\"\(code)\"}"),
            MerianError.httpError(statusCode: 409, message: "{\"code\":\"revision_conflict\"}"),
            MerianError.httpError(statusCode: 409, message: "{\"error\":\"\(code)\"}"),
            MerianError.httpError(statusCode: 409, message: code),
            MerianError.invalidResponse,
            URLError(.notConnectedToInternet)
        ]
        for error in errors {
            #expect(!OfflineQueueManager.cloudDeletionRequiresHistoryReview(error: error))
        }
    }

    @Test func historyHoldSurvivesStoreReopenAndReenqueue() async throws {
        let manager = OfflineQueueManager.shared
        let scheduler = CloudDeletionTestSupport.scheduler()
        let originalContext = manager.modelContext
        let originalOnline = manager.isOnline
        let originalSyncing = manager.isCloudDeletionSyncing
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            scheduler.cancelScheduledWake(using: manager)
            manager.modelContext = originalContext
            manager.isOnline = originalOnline
            manager.isCloudDeletionSyncing = originalSyncing
            try? FileManager.default.removeItem(at: directory)
        }
        let schema = Schema(CurrentSchema.models)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("hold.sqlite"))
        let scanID = UUID().uuidString.lowercased()
        let calls = OSAllocatedUnfairLock(initialState: 0)
        manager.isOnline = true
        manager.isCloudDeletionSyncing = false
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            manager.modelContext = context
            try context.ensurePendingCloudDeletionTask(scanId: scanID, requestingAccountID: CloudDeletionTestSupport.accountID, origin: .explicitUserDeletion)
            try context.save()
            await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(), scheduler: scheduler) { _, _ in
                calls.withLock { $0 += 1 }
                throw MerianError.httpError(statusCode: 409, message:
                    #"{"error":"Update Merian to review and delete this saved scan.","code":"legacy_observation_delete_requires_upgrade"}"#)
            }
            manager.modelContext = nil
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let read = ModelContext(reopened)
        read.autosaveEnabled = false
        manager.modelContext = read
        let job = try #require(try read.fetchOfflineJob(id: "cloud-deletion:\(scanID)"))
        #expect(job.status == .needsAttention)
        #expect(job.lastErrorCode == OfflineQueueManager.cloudDeletionHistoryHoldCode)
        #expect(job.lastHTTPStatus == 409)
        #expect(job.nextRunAt == nil)
        #expect(job.attemptCount == 0)
        #expect(try read.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 1)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)

        // An idempotent enqueue and a new drain cannot upgrade old intent.
        try read.ensurePendingCloudDeletionTask(scanId: scanID, requestingAccountID: CloudDeletionTestSupport.accountID, origin: .explicitUserDeletion)
        try read.save()
        await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(), scheduler: scheduler) { _, _ in calls.withLock { $0 += 1 } }
        #expect(calls.withLock { $0 } == 1)
        #expect(job.status == .needsAttention)
        #expect(try read.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 1)
        let events = try read.fetch(FetchDescriptor<OfflineQueueEvent>())
        #expect(events.filter { $0.kind == .needsAttention }.count == 1)
        #expect(!events.contains { $0.kind == .completed || $0.kind == .retryScheduled })
    }

    @Test func heldPrefixDoesNotStarveUnrelatedDeletion() async throws {
        let manager = OfflineQueueManager.shared
        let scheduler = CloudDeletionTestSupport.scheduler()
        let originalContext = manager.modelContext
        let originalOnline = manager.isOnline
        let originalSyncing = manager.isCloudDeletionSyncing
        defer {
            scheduler.cancelScheduledWake(using: manager)
            manager.modelContext = originalContext
            manager.isOnline = originalOnline
            manager.isCloudDeletionSyncing = originalSyncing
        }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        context.autosaveEnabled = false
        manager.modelContext = context
        manager.isOnline = true
        manager.isCloudDeletionSyncing = false
        for _ in 0..<201 {
            let scanID = UUID().uuidString.lowercased()
            try context.ensurePendingCloudDeletionTask(scanId: scanID, timestamp: .distantPast, requestingAccountID: CloudDeletionTestSupport.accountID, origin: .explicitUserDeletion)
            let job = try #require(try context.fetchOfflineJob(id: "cloud-deletion:\(scanID)"))
            // A generic status repair must not revive a held task either.
            job.status = .complete
            job.lastErrorCode = OfflineQueueManager.cloudDeletionHistoryHoldCode
        }
        let runnableID = UUID().uuidString.lowercased()
        try context.ensurePendingCloudDeletionTask(scanId: runnableID, requestingAccountID: CloudDeletionTestSupport.accountID, origin: .explicitUserDeletion)
        try context.save()
        let dispatched = OSAllocatedUnfairLock(initialState: [String]())
        await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(), scheduler: scheduler) { scanID, _ in dispatched.withLock { $0.append(scanID) } }
        #expect(dispatched.withLock { $0 } == [runnableID])
        #expect(try context.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 201)
        #expect(try context.fetchOfflineJob(id: "cloud-deletion:\(runnableID)")?.status == .complete)
    }


    @Test(arguments: [409, 503])
    func ordinaryFailureStillRetriesUntilConfirmed(status: Int) async throws {
        let manager = OfflineQueueManager.shared
        let scheduler = CloudDeletionTestSupport.scheduler()
        let originalContext = manager.modelContext
        let originalOnline = manager.isOnline
        let originalSyncing = manager.isCloudDeletionSyncing
        defer {
            scheduler.cancelScheduledWake(using: manager)
            manager.modelContext = originalContext
            manager.isOnline = originalOnline
            manager.isCloudDeletionSyncing = originalSyncing
        }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        context.autosaveEnabled = false
        manager.modelContext = context
        manager.isOnline = true
        manager.isCloudDeletionSyncing = false
        let scanID = UUID().uuidString.lowercased()
        try context.ensurePendingCloudDeletionTask(scanId: scanID, requestingAccountID: CloudDeletionTestSupport.accountID, origin: .explicitUserDeletion)
        try context.save()
        await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(), scheduler: scheduler) { _, _ in
            throw MerianError.httpError(statusCode: status, message: #"{"code":"temporary_failure"}"#)
        }
        let job = try #require(try context.fetchOfflineJob(id: "cloud-deletion:\(scanID)"))
        #expect(job.status == .waiting)
        #expect(job.attemptCount == 1)
        #expect(job.nextRunAt != nil)
        #expect(!OfflineQueueManager.cloudDeletionIsHeld(job))
        #expect(try context.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 1)
        job.nextRunAt = .distantPast
        try context.save()
        await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(), scheduler: scheduler) { _, _ in }
        #expect(job.status == .complete)
        #expect(try context.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 0)
    }


    @Test func largeHeldBacklogContinuesInBoundedDurablePages() async throws {
        let manager = OfflineQueueManager.shared
        let scheduler = CloudDeletionTestSupport.scheduler()
        let originalContext = manager.modelContext
        let originalOnline = manager.isOnline
        let originalSyncing = manager.isCloudDeletionSyncing
        defer {
            scheduler.cancelScheduledWake(using: manager)
            manager.modelContext = originalContext
            manager.isOnline = originalOnline
            manager.isCloudDeletionSyncing = originalSyncing
        }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        context.autosaveEnabled = false
        manager.modelContext = context
        manager.isOnline = true
        manager.isCloudDeletionSyncing = false
        // Numeric and hexadecimal prefixes sort differently with the default
        // localized comparator. Every timestamp ties to exercise the keyset.
        for index in 0..<801 {
            let scanID = String(format: "%08x-0000-4000-8000-00000000d204", index)
            try context.ensurePendingCloudDeletionTask(scanId: scanID, timestamp: .distantPast, requestingAccountID: CloudDeletionTestSupport.accountID, origin: .explicitUserDeletion)
            let job = try #require(try context.fetchOfflineJob(id: "cloud-deletion:\(scanID)"))
            job.status = .needsAttention
            job.lastErrorCode = OfflineQueueManager.cloudDeletionHistoryHoldCode
        }
        let runnableID = UUID().uuidString.lowercased()
        try context.ensurePendingCloudDeletionTask(scanId: runnableID, requestingAccountID: CloudDeletionTestSupport.accountID, origin: .explicitUserDeletion)
        try context.save()
        let dispatched = OSAllocatedUnfairLock(initialState: [String]())
        for _ in 0..<2 {
            await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(), scheduler: scheduler) { id, _ in dispatched.withLock { $0.append(id) } }
            #expect(dispatched.withLock { $0.isEmpty })
            #expect(scheduler.nextPersistedWakeDate(using: manager) != nil)
            scheduler.cancelScheduledWake(using: manager)
            // Continuation is read from disk-backed state, not a process cursor.
            let fresh = ModelContext(context.container)
            fresh.autosaveEnabled = false
            manager.modelContext = fresh
        }
        await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(), scheduler: scheduler) { id, _ in dispatched.withLock { $0.append(id) } }
        #expect(dispatched.withLock { $0 } == [runnableID])
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        let fresh = ModelContext(context.container)
        let continuation = try #require(try fresh.fetchOfflineJob(id: OfflineQueueManager.cloudDeletionDiscoveryJobID))
        #expect(continuation.status == .complete)
        #expect(continuation.metadataJSON == nil)
        #expect(try fresh.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 801)
    }


    @Test func discoveryWakeWaitsForActiveDeletionBatch() async throws {
        let manager = OfflineQueueManager.shared
        let scheduler = CloudDeletionTestSupport.scheduler()
        let originalContext = manager.modelContext
        let originalOnline = manager.isOnline
        let originalSyncing = manager.isCloudDeletionSyncing
        defer {
            scheduler.cancelScheduledWake(using: manager)
            manager.modelContext = originalContext
            manager.isOnline = originalOnline
            manager.isCloudDeletionSyncing = originalSyncing
        }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        context.autosaveEnabled = false
        manager.modelContext = context
        manager.isOnline = true
        manager.isCloudDeletionSyncing = false
        for _ in 0..<201 {
            try context.ensurePendingCloudDeletionTask(scanId: UUID().uuidString.lowercased(), requestingAccountID: CloudDeletionTestSupport.accountID, origin: .explicitUserDeletion)
        }
        let unrelatedRetry = Date().addingTimeInterval(3_600)
        context.insert(OfflineJobRecord(
            id: "unrelated-retry", kind: .collectionSync,
            status: .waiting, nextRunAt: unrelatedRetry
        ))
        try context.save()
        let calls = OSAllocatedUnfairLock(initialState: 0)
        await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(), scheduler: scheduler) { _, _ in
            let first = calls.withLock { count in
                count += 1
                return count == 1
            }
            if first {
                try await MainActor.run {
                    // Inspect during dispatch, with the durable continuation
                    // already saved. Other services must keep their deadlines.
                    let active = try #require(manager.modelContext)
                    let persisted = ModelContext(active.container)
                    let cursor = try #require(try persisted.fetchOfflineJob(id: OfflineQueueManager.cloudDeletionDiscoveryJobID))
                    #expect(cursor.metadataJSON != nil)
                    #expect(cursor.nextRunAt != nil)
                    #expect(manager.isCloudDeletionSyncing)
                    #expect(scheduler.nextPersistedWakeDate(using: manager) == unrelatedRetry)
                    #expect(scheduler.scheduledWakeDate == unrelatedRetry)
                }
            }
        }
        #expect(calls.withLock { $0 } == 200)
        #expect(!manager.isCloudDeletionSyncing)
        let continuation = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.cloudDeletionDiscoveryJobID))
        #expect(continuation.nextRunAt != nil)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == continuation.nextRunAt)
        #expect(scheduler.scheduledWakeDate != nil)
        #expect(try context.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 1)
    }

    @Test func interruptedOfferedBatchIsRevisitedAfterCursorReachesEnd() async throws {
        let manager = OfflineQueueManager.shared
        let scheduler = CloudDeletionTestSupport.scheduler()
        let originalContext = manager.modelContext
        let originalOnline = manager.isOnline
        let originalSyncing = manager.isCloudDeletionSyncing
        defer {
            scheduler.cancelScheduledWake(using: manager)
            manager.modelContext = originalContext
            manager.isOnline = originalOnline
            manager.isCloudDeletionSyncing = originalSyncing
        }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        context.autosaveEnabled = false
        manager.modelContext = context
        manager.isOnline = true
        manager.isCloudDeletionSyncing = false
        let interruptedID = "00000000-0000-4000-8000-00000000d201"
        let tailID = "00000000-0000-4000-8000-00000000d202"
        try context.ensurePendingCloudDeletionTask(scanId: interruptedID, timestamp: Date(timeIntervalSinceReferenceDate: 90), requestingAccountID: CloudDeletionTestSupport.accountID, origin: .explicitUserDeletion)
        try context.ensurePendingCloudDeletionTask(scanId: tailID, timestamp: Date(timeIntervalSinceReferenceDate: 110), requestingAccountID: CloudDeletionTestSupport.accountID, origin: .explicitUserDeletion)
        let interrupted = try #require(try context.fetchOfflineJob(id: "cloud-deletion:\(interruptedID)"))
        interrupted.status = .running
        interrupted.nextRunAt = nil
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.cloudDeletionDiscoveryJobID,
            kind: .cloudDeletion, status: .waiting, nextRunAt: .distantPast,
            metadataJSON: #"{"version":2,"timestamp":100,"scanID":"00000000-0000-4000-8000-00000000d201","accountID":"00000000-0000-4000-8000-00000000d301","offeredWork":true}"#
        ))
        try context.save()
        manager.modelContext = ModelContext(context.container)
        let sent = OSAllocatedUnfairLock(initialState: [String]())
        await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(), scheduler: scheduler) { id, _ in sent.withLock { $0.append(id) } }
        #expect(sent.withLock { $0 } == [tailID])
        #expect(scheduler.nextPersistedWakeDate(using: manager) != nil)
        scheduler.cancelScheduledWake(using: manager)
        manager.modelContext = ModelContext(context.container)
        await manager.syncPendingDeletions(accountWork: CloudDeletionTestSupport.accountWork(), scheduler: scheduler) { id, _ in sent.withLock { $0.append(id) } }
        #expect(sent.withLock { $0 } == [tailID, interruptedID])
        let fresh = ModelContext(context.container)
        #expect(try fresh.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 0)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
    }

}
