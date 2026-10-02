import Foundation
@testable import Merian
import Supabase
import SwiftData
import Testing

@MainActor
@Suite("Historical sync update-required recovery", .serialized, .sharedProcessState(.offlineQueueManager))
struct HistoricalSyncUpdateRequiredTests {
    @Test func onlyExactCompatibilityErrorsAreRecognized() {
        #expect(ClientUpdateRequiredPolicy.matches(PostgrestError(code: "PT426", message: "client_update_required")))
        #expect(ClientUpdateRequiredPolicy.matches(MerianError.httpError(
            statusCode: 426, message: #"{"code":"client_update_required"}"#
        )))
        let errors: [Error] = [
            PostgrestError(code: "PT426", message: "unrelated"),
            PostgrestError(code: "42501", message: "client_update_required"),
            MerianError.httpError(statusCode: 500, message: #"{"code":"client_update_required"}"#),
            MerianError.httpError(statusCode: 426, message: "update required"),
            URLError(.notConnectedToInternet)
        ]
        for error in errors {
            #expect(!ClientUpdateRequiredPolicy.matches(error))
        }
    }

    @Test func targetedReadPausesWithoutRepeatedFetchAndIgnoresStaleLease() async throws {
        for stale in [false, true] {
            let suite = "history-update-tests-\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let lease = AccountBoundWorkLease(id: UUID(), session: AuthTransitionSession(userID: UUID(), isAnonymous: false))
            let update = AppUpdateCoordinator(defaults: defaults, buildIdentity: "1:10", allowsUpdatePrompt: true) { lease.session.userID }
            var fetchCount = 0, finishCount = 0
            let client = HistoricalSyncCloudClient(
                beginAccountWork: { lease }, finishAccountWork: { _ in finishCount += 1 },
                isAccountWorkCurrent: { _ in !stale },
                fetchScanPage: { _ in throw URLError(.badServerResponse) },
                fetchScan: { _ in
                    fetchCount += 1
                    throw PostgrestError(code: "PT426", message: "client_update_required")
                },
                fetchCollectionPage: { _ in [] }
            )
            let repository = ScanRepository(historicalCloudClient: client)
            repository.appUpdateCoordinator = update
            let context = try OfflineSyncTestSupport.makeIsolatedContext()
            let queued = OfflineQueuedScan(id: UUID().uuidString, timestamp: Date(), scanState: .inferencing)
            context.insert(queued)
            try context.save()
            for _ in 0..<2 {
                let outcome = await repository.syncHistoricalScanDown(scanId: queued.id, modelContext: context)
                #expect(outcome == (stale ? .transientFailure : .clientUpdateRequired))
            }
            #expect(fetchCount == (stale ? 2 : 1))
            #expect(finishCount == 2)
            #expect(update.showsPrompt == !stale)
            #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
            #expect(queued.queueState == .inferencing)
        }
    }

    @Test func bulkReadStopsBeforeCollectionReconciliationAndKeepsLocalLibrary() async throws {
        let suite = "history-update-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let lease = AccountBoundWorkLease(id: UUID(), session: AuthTransitionSession(userID: UUID(), isAnonymous: false))
        let update = AppUpdateCoordinator(defaults: defaults, buildIdentity: "1:10", allowsUpdatePrompt: true) { lease.session.userID }
        var fetchCount = 0, collectionFetchCount = 0, finishCount = 0
        let client = HistoricalSyncCloudClient(
            beginAccountWork: { lease }, finishAccountWork: { _ in finishCount += 1 },
            isAccountWorkCurrent: { _ in true },
            fetchScanPage: { _ in
                fetchCount += 1
                throw PostgrestError(code: "PT426", message: "client_update_required")
            },
            fetchScan: { _ in Data("[]".utf8) },
            fetchCollectionPage: { _ in collectionFetchCount += 1; return [] }
        )
        let repository = ScanRepository(historicalCloudClient: client)
        repository.appUpdateCoordinator = update
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        defer { manager.modelContext = originalContext }
        context.insert(ScanCollection(name: "Saved locally"))
        try context.save()
        await repository.syncHistoricalScansDown(modelContext: context)
        update.dismiss()
        await repository.syncHistoricalScansDown(modelContext: context)
        #expect(fetchCount == 1)
        #expect(collectionFetchCount == 0)
        #expect(finishCount == 2)
        #expect(try context.fetchCount(FetchDescriptor<ScanCollection>()) == 1)
        #expect(!update.showsPrompt)
        #expect(update.requiresUpdate(.history, accountID: lease.session.userID))
    }

    @Test func completedServerPauseCannotResetBudgetOrDispatchOnSameBuild() throws {
        let suite = "history-update-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = UUID()
        let update = AppUpdateCoordinator(defaults: defaults, buildIdentity: "1:10", allowsUpdatePrompt: true) { account }
        update.record(.history)
        update.dismiss()
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext, originalUpdate = manager.appUpdateCoordinator
        defer {
            OfflineJobScheduler.shared.cancelScheduledWake(using: manager)
            manager.modelContext = originalContext
            manager.appUpdateCoordinator = originalUpdate
        }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        manager.appUpdateCoordinator = update
        let id = UUID().uuidString
        let scan = OfflineQueuedScan(id: id, timestamp: Date(), scanState: .inferencing, queueAttemptCount: 3)
        let job = OfflineJobRecord(id: OfflineQueueManager.scanIngestionJobId(scanId: id), kind: .scanIngestion, subjectId: id, status: .running)
        context.insert(scan)
        context.insert(job)
        try context.save()
        #expect(manager.markQueuedScanNeedsAttention(
            scanId: id, code: "server_result_local_recovery_update_required",
            message: BackgroundInferencePolicy.clientUpdateAttentionMessage
        ))
        #expect(!manager.retryQueuedScanNow(scanId: id))
        #expect(update.showsPrompt)
        #expect(try manager.hasDurableCompletedServerResult(scanId: id))
        #expect(scan.queueAttemptCount == 3)
        #expect(scan.queueNeedsAttention)
        #expect(job.status == .needsAttention)
        #expect(scan.queueNextRetryAt == nil)
    }
}
