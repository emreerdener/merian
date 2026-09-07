import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite(
    "Background Inference Retry",
    .serialized,
    .sharedProcessState(.offlineQueueManager)
)
@MainActor
struct BackgroundInferenceRetryTests {
    @Test func scheduledServerFailureMarkerIsReadFromDurableStore() async throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        defer {
            OfflineJobScheduler.shared.cancelScheduledWake(using: manager)
            manager.modelContext = originalContext
        }

        let scan = OfflineQueuedScan(
            id: UUID().uuidString.lowercased(),
            scanState: .inferencing
        )
        context.insert(scan)
        try context.save()
        // Keep the marker-free model resident in the manager's context. The
        // background actor then commits the marker through a separate context.
        let scanId = scan.id
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        _ = try #require(context.fetch(descriptor).first)

        let actor = BackgroundDatabaseActor(
            modelContainer: context.container
        )
        #expect(
            await actor.scheduleInferenceRetry(
                id: scanId,
                expectedGeneration: nil,
                code: OfflineQueueManager.serverRetryableFailureCode,
                message: "Retry the exact backend generation.",
                delay: 1,
                resetMediaUploads: false
            ) == 1
        )

        #expect(
            manager.hasDurableScheduledServerFailureRetry(scanId: scanId)
        )
        #expect(manager.queueAttemptCount(for: scanId) == 1)

        // Reproduce the migrated-store failure seen on TestFlight: one
        // SwiftData context loses the queue-row copy while the durable job
        // still owns the exact retry. Reads must heal from the surviving
        // mirror instead of restarting forever at attempt one.
        let driftContext = ModelContext(context.container)
        let driftedScan = try #require(
            driftContext.fetch(descriptor).first
        )
        driftedScan.queueLastErrorCode = nil
        driftedScan.queueAttemptCount = 0
        try driftContext.save()
        #expect(
            manager.hasDurableScheduledServerFailureRetry(scanId: scanId)
        )
        #expect(manager.queueAttemptCount(for: scanId) == 1)

        // A transient signer/PUT failure is part of the required re-stage, not
        // a new inference decision. Its event keeps the precise upload error,
        // while the durable machine latch and committed count must survive.
        #expect(
            manager.updateQueuedScanForRetry(
                scanId: scanId,
                code: "upload_transport_error",
                message: "The re-stage connection was interrupted.",
                delay: 1,
                resetTo: .pending
            ) == 2
        )
        #expect(
            manager.hasDurableScheduledServerFailureRetry(scanId: scanId)
        )
        #expect(manager.queueAttemptCount(for: scanId) == 2)

        let verificationContext = ModelContext(context.container)
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(
            persisted.queueLastErrorCode
                == OfflineQueueManager.serverRetryableFailureCode
        )
        #expect(persisted.queueAttemptCount == 2)
    }

    @Test func persistedRetryWakeSurvivesCancelledProcessOwner() async throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let originalOnline = manager.isOnline
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.isOnline = true
        OfflineJobScheduler.shared.cancelScheduledWake(using: manager)
        defer {
            OfflineJobScheduler.shared.cancelScheduledWake(using: manager)
            manager.isOnline = originalOnline
            manager.modelContext = originalContext
        }
        try #require(!manager.isCurrentNetworkConstrained)

        let scanId = UUID().uuidString.lowercased()
        context.insert(OfflineQueuedScan(
            id: scanId,
            scanState: .inferencing
        ))
        try context.save()

        let actor = BackgroundDatabaseActor(
            modelContainer: context.container
        )
        #expect(
            await actor.scheduleInferenceRetry(
                id: scanId,
                expectedGeneration: nil,
                code: "inference_retry",
                message: "Retry after process-owner cancellation.",
                delay: 3_600
            ) == 1
        )

        let verificationContext = ModelContext(context.container)
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let persistedRetryDate = try #require(
            verificationContext.fetch(descriptor).first?.queueNextRetryAt
        )

        let restoredWakeDate = await Task { @MainActor in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            #expect(Task.isCancelled)
            OfflineJobScheduler.shared.scheduleNextPersistedWake(
                using: manager
            )
            return OfflineJobScheduler.shared.scheduledWakeDate
        }.value

        #expect(restoredWakeDate == persistedRetryDate)
    }

    @Test func pollTokenValidationRejectsReplacementOwner() {
        let manager = OfflineQueueManager.shared
        let scanId = "server-poll-owner-\(UUID().uuidString)"
        manager.serverIngestionPollTasks.cancel(scanId)
        defer { manager.serverIngestionPollTasks.cancel(scanId) }

        let originalToken = manager.serverIngestionPollTasks.replace(
            for: scanId,
            ownerGeneration: nil
        ) { _ in Task {} }

        #expect(manager.isServerIngestionPollCurrent(
            scanId: scanId,
            token: originalToken
        ))
        #expect(manager.isServerIngestionPollCurrent(
            scanId: scanId,
            token: nil
        ))

        let replacementToken = manager.serverIngestionPollTasks.replace(
            for: scanId,
            ownerGeneration: nil
        ) { _ in Task {} }

        #expect(!manager.isServerIngestionPollCurrent(
            scanId: scanId,
            token: originalToken
        ))
        #expect(manager.isServerIngestionPollCurrent(
            scanId: scanId,
            token: replacementToken
        ))
    }
}
