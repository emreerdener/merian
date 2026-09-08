import Foundation
@testable import Merian
import SwiftData
import Testing

private actor CollectionSyncServiceRecorder {
    private(set) var pushedSnapshots: [[CollectionSyncSnapshot]] = []
    private(set) var finishCount = 0
    private var accountWorkResults: [Bool]

    init(accountWorkResults: [Bool] = [true]) {
        self.accountWorkResults = accountWorkResults
    }

    func recordPush(_ snapshots: [CollectionSyncSnapshot]) {
        pushedSnapshots.append(snapshots)
    }

    func recordFinish() {
        finishCount += 1
    }

    func nextAccountWorkResult() -> Bool {
        guard accountWorkResults.count > 1 else {
            return accountWorkResults.first ?? false
        }
        return accountWorkResults.removeFirst()
    }
}

private enum CollectionSyncTestError: Error {
    case accountUnavailable
    case remoteFailure
}

@Suite("Collection Sync", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct CollectionSyncTests {
    @Test func testCollectionSyncPayloadsReadDirectRelationshipsAndExcludeUnrelatedScans() async throws {
        let container = try makeIsolatedContainer()
        let context = ModelContext(container)
        let firstMember = LocalScanRecord(
            id: "collection_member_b",
            speciesId: "species_b",
            scientificName: "Quercus alba",
            commonName: "White Oak"
        )
        let secondMember = LocalScanRecord(
            id: "collection_member_a",
            speciesId: "species_a",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        let unrelated = LocalScanRecord(
            id: "collection_unrelated",
            speciesId: "species_unrelated",
            scientificName: "Turdus migratorius",
            commonName: "American Robin"
        )
        let collection = ScanCollection(
            id: "collection_direct_members",
            name: "Field Notes",
            createdAt: Date(timeIntervalSince1970: 100),
            scans: [firstMember, secondMember]
        )
        let favorites = ScanCollection(
            id: "collection_favorites",
            name: "Favorites",
            createdAt: Date(timeIntervalSince1970: 50),
            scans: [unrelated]
        )

        for model in [firstMember, secondMember, unrelated] {
            context.insert(model)
        }
        context.insert(collection)
        context.insert(favorites)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let snapshots = try await actor.collectionSyncSnapshots()

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.id == collection.id)
        #expect(snapshots.first?.scanIDs == [secondMember.id, firstMember.id])
        #expect(snapshots.first?.scanIDs.contains(unrelated.id) == false)
    }

    @Test func collectionSyncDoesNotInvokeDuringAuthTransition() async throws {
        let container = try makeIsolatedContainer()
        try insertCollection(
            id: "collection_auth_transition_preflight",
            isPendingDeletion: true,
            into: container
        )
        let recorder = CollectionSyncServiceRecorder()
        let service = CollectionSyncService(
            dependencies: .init(
                beginAccountWork: {
                    throw CollectionSyncTestError.accountUnavailable
                },
                isAccountWorkCurrent: { _ in true },
                finishAccountWork: { _ in await recorder.recordFinish() },
                pushSnapshots: { snapshots in
                    await recorder.recordPush(snapshots)
                }
            )
        )

        let result = await service.sync(modelContainer: container)

        #expect(!result)
        #expect(await recorder.pushedSnapshots.isEmpty)
        #expect(await recorder.finishCount == 0)
        #expect(try await collection(id: "collection_auth_transition_preflight", in: container) != nil)
    }

    @Test func collectionSyncRetainsTombstoneWhenTransitionStartsInFlight() async throws {
        let container = try makeIsolatedContainer()
        let collectionID = "collection_auth_transition_in_flight"
        try insertCollection(
            id: collectionID,
            isPendingDeletion: true,
            into: container
        )
        let recorder = CollectionSyncServiceRecorder(
            accountWorkResults: [true, false]
        )
        let service = CollectionSyncService(
            dependencies: dependencies(recorder: recorder)
        )

        let result = await service.sync(modelContainer: container)

        #expect(!result)
        #expect(await recorder.pushedSnapshots.count == 1)
        #expect(await recorder.finishCount == 1)
        #expect(try await collection(id: collectionID, in: container) != nil)
    }

    @Test func collectionSyncDoesNotDispatchAfterSnapshotWhenLeaseIsStale() async throws {
        let container = try makeIsolatedContainer()
        let collectionID = "collection_stale_before_dispatch"
        try insertCollection(
            id: collectionID,
            isPendingDeletion: true,
            into: container
        )
        let recorder = CollectionSyncServiceRecorder(
            accountWorkResults: [false]
        )
        let service = CollectionSyncService(
            dependencies: dependencies(recorder: recorder)
        )

        let result = await service.sync(modelContainer: container)

        #expect(!result)
        #expect(await recorder.pushedSnapshots.isEmpty)
        #expect(await recorder.finishCount == 1)
        #expect(try await collection(id: collectionID, in: container) != nil)
    }

    @Test func collectionSyncPurgesConfirmedTombstoneAndFinishesLease() async throws {
        let container = try makeIsolatedContainer()
        let collectionID = "collection_confirmed_tombstone"
        try insertCollection(
            id: collectionID,
            isPendingDeletion: true,
            into: container
        )
        let recorder = CollectionSyncServiceRecorder()
        let service = CollectionSyncService(
            dependencies: dependencies(recorder: recorder)
        )

        let result = await service.sync(modelContainer: container)

        #expect(result)
        #expect(await recorder.pushedSnapshots.first?.map(\.id) == [collectionID])
        #expect(await recorder.finishCount == 1)
        #expect(try await collection(id: collectionID, in: container) == nil)
    }

    @Test func collectionSyncRemoteFailureRetainsTombstoneAndFinishesLease() async throws {
        let container = try makeIsolatedContainer()
        let collectionID = "collection_remote_failure"
        try insertCollection(
            id: collectionID,
            isPendingDeletion: true,
            into: container
        )
        let recorder = CollectionSyncServiceRecorder()
        let service = CollectionSyncService(
            dependencies: dependencies(
                recorder: recorder,
                pushSnapshots: { snapshots in
                    await recorder.recordPush(snapshots)
                    throw CollectionSyncTestError.remoteFailure
                }
            )
        )

        let result = await service.sync(modelContainer: container)

        #expect(!result)
        #expect(await recorder.pushedSnapshots.count == 1)
        #expect(await recorder.finishCount == 1)
        #expect(try await collection(id: collectionID, in: container) != nil)
    }

    @Test func collectionSyncDoesNotPurgeCollectionReactivatedDuringRequest() async throws {
        let container = try makeIsolatedContainer()
        let collectionID = "collection_reactivated_in_flight"
        try insertCollection(
            id: collectionID,
            isPendingDeletion: true,
            into: container
        )
        let recorder = CollectionSyncServiceRecorder()
        let service = CollectionSyncService(
            dependencies: dependencies(
                recorder: recorder,
                pushSnapshots: { snapshots in
                    await recorder.recordPush(snapshots)
                    try await MainActor.run {
                        let context = ModelContext(container)
                        let descriptor = FetchDescriptor<ScanCollection>(
                            predicate: #Predicate { $0.id == collectionID }
                        )
                        let collection = try #require(
                            context.fetch(descriptor).first
                        )
                        collection.isPendingDeletion = false
                        try context.save()
                    }
                }
            )
        )

        let result = await service.sync(modelContainer: container)
        let reactivated = try await collection(id: collectionID, in: container)

        #expect(result)
        #expect(await recorder.pushedSnapshots.first?.first?.isPendingDeletion == true)
        #expect(await recorder.finishCount == 1)
        #expect(reactivated?.isPendingDeletion == false)
    }

    @Test func testFinishCollectionSyncAttemptLeavesPendingFlagForNewerCollectionMutation() async {
        let manager = OfflineQueueManager.shared
        let originalRevision = manager.collectionSyncRevision
        let originalSyncing = manager.isCollectionSyncing
        let originalTask = manager.collectionSyncTask
        let originalModelContext = manager.modelContext
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        defer {
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
            manager.modelContext = originalModelContext
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        manager.modelContext = nil
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
        manager.collectionSyncRevision = 8
        manager.isCollectionSyncing = true

        // Simulate a fresh local edit landing while revision 7 was in flight.
        manager.finishCollectionSyncAttempt(success: true, capturedRevision: 7)

        #expect(manager.isCollectionSyncing == false, "Completion must always release the collection sync latch")
        #expect(manager.collectionSyncTask == nil, "Completion must clear the in-flight collection sync task handle")
        #expect(
            UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync),
            "An older successful collection sync must not clear a newer pending local mutation"
        )
    }

    @Test func testFinishCollectionSyncAttemptClearsPendingFlagWhenNoNewerMutationExists() async {
        let manager = OfflineQueueManager.shared
        let originalRevision = manager.collectionSyncRevision
        let originalSyncing = manager.isCollectionSyncing
        let originalTask = manager.collectionSyncTask
        let originalModelContext = manager.modelContext
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        defer {
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
            manager.modelContext = originalModelContext
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        manager.modelContext = nil
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
        manager.collectionSyncRevision = 12
        manager.isCollectionSyncing = true

        manager.finishCollectionSyncAttempt(success: true, capturedRevision: 12)

        #expect(
            !UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync),
            "A successful collection sync may clear the pending bit only when no newer local collection change exists"
        )
    }

    @Test func testFinishCollectionSyncAttemptLeavesPendingFlagWhenSyncFails() async {
        let manager = OfflineQueueManager.shared
        let originalRevision = manager.collectionSyncRevision
        let originalSyncing = manager.isCollectionSyncing
        let originalTask = manager.collectionSyncTask
        let originalModelContext = manager.modelContext
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        defer {
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
            manager.modelContext = originalModelContext
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        manager.modelContext = nil
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
        manager.collectionSyncRevision = 21
        manager.isCollectionSyncing = true

        manager.finishCollectionSyncAttempt(success: false, capturedRevision: 21)

        #expect(manager.isCollectionSyncing == false, "A failed collection sync must still release the latch")
        #expect(manager.collectionSyncTask == nil, "A failed collection sync must clear the in-flight task handle")
        #expect(
            UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync),
            "A failed collection sync must keep the pending bit set so a later retry can pick it up"
        )
    }

    @Test func testFinishCollectionSyncAttemptPausesAfterRetryBudget() async throws {
        let manager = OfflineQueueManager.shared
        let originalModelContext = manager.modelContext
        let originalRevision = manager.collectionSyncRevision
        let originalSyncing = manager.isCollectionSyncing
        let originalTask = manager.collectionSyncTask
        let ctx = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = ctx
        defer {
            manager.modelContext = originalModelContext
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
        }

        let job = OfflineJobRecord(
            id: OfflineQueueManager.collectionSyncJobId,
            kind: .collectionSync,
            status: .running,
            attemptCount: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        )
        ctx.insert(job)
        try ctx.save()

        manager.isCollectionSyncing = true
        manager.finishCollectionSyncAttempt(success: false, capturedRevision: 1)

        let jobId = OfflineQueueManager.collectionSyncJobId
        let descriptor = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.id == jobId })
        let fetched = try #require(ctx.fetch(descriptor).first)
        #expect(fetched.status == .needsAttention)
        #expect(fetched.nextRunAt == nil)
        #expect(fetched.attemptCount == OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts)
        #expect(fetched.lastErrorCode == "collection_sync_retry_limit_reached")
        #expect(!manager.hasPendingCollectionSyncJob)
    }

    @Test func testMarkCollectionSyncPendingResetsRetryBudgetForNewMutation() async throws {
        let manager = OfflineQueueManager.shared
        let originalModelContext = manager.modelContext
        let originalRevision = manager.collectionSyncRevision
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        let ctx = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = ctx
        defer {
            manager.modelContext = originalModelContext
            manager.collectionSyncRevision = originalRevision
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        let job = OfflineJobRecord(
            id: OfflineQueueManager.collectionSyncJobId,
            kind: .collectionSync,
            status: .needsAttention,
            nextRunAt: Date().addingTimeInterval(600),
            attemptCount: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts,
            lastErrorCode: "collection_sync_retry_limit_reached",
            lastErrorMessage: "Paused."
        )
        ctx.insert(job)
        try ctx.save()

        manager.markCollectionSyncPending()

        let jobId = OfflineQueueManager.collectionSyncJobId
        let descriptor = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.id == jobId })
        let fetched = try #require(ctx.fetch(descriptor).first)
        #expect(fetched.status == .pending)
        #expect(fetched.attemptCount == 0)
        #expect(fetched.nextRunAt == nil)
        #expect(fetched.lastErrorCode == nil)
        #expect(fetched.lastErrorMessage == nil)
    }

    private func makeIsolatedContainer() throws -> ModelContainer {
        let schema = Schema(CurrentSchema.models)
        let storeURL = URL.cachesDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private func insertCollection(
        id: String,
        isPendingDeletion: Bool,
        into container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        context.insert(ScanCollection(
            id: id,
            name: "Field Notes",
            isPendingDeletion: isPendingDeletion
        ))
        try context.save()
    }

    private func collection(
        id: String,
        in container: ModelContainer
    ) async throws -> CollectionSyncSnapshot? {
        let actor = BackgroundDatabaseActor(modelContainer: container)
        return try await actor.collectionSyncSnapshots().first {
            $0.id == id
        }
    }

    private func dependencies(
        recorder: CollectionSyncServiceRecorder,
        pushSnapshots: (@Sendable ([CollectionSyncSnapshot]) async throws -> Void)? = nil
    ) -> CollectionSyncService.Dependencies {
        let lease = AccountBoundWorkLease(
            id: UUID(),
            session: AuthTransitionSession(
                userID: UUID(),
                isAnonymous: false
            )
        )
        return .init(
            beginAccountWork: { lease },
            isAccountWorkCurrent: { _ in
                await recorder.nextAccountWorkResult()
            },
            finishAccountWork: { _ in await recorder.recordFinish() },
            pushSnapshots: pushSnapshots ?? { snapshots in
                await recorder.recordPush(snapshots)
            }
        )
    }
}
