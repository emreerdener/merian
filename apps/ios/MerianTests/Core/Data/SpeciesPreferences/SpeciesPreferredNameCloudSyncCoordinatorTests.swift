import Foundation
@testable import Merian
import SwiftData
import Testing

private enum SpeciesPreferenceCloudTestError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Cloud unavailable."
    }
}

private struct CloudPageRequest: Equatable {
    let userID: String
    let offset: Int
    let pageSize: Int
}

private actor SpeciesPreferenceCloudSyncGate {
    private var didEnter = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        didEnter = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        if didEnter { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
@Suite(
    "Species Preferred Name Cloud Sync Coordinator",
    .timeLimit(.minutes(1))
)
struct SpeciesNameCloudSyncTests {
    @Test func syncPushesLocalRowsThroughTheInjectedClient() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = try #require(
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        let lease = makeSpeciesPreferenceLease(userID: userID)
        let updatedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(
            UserSpeciesPreference(
                scientificName: "Quercus macrocarpa",
                preferredCommonName: "Bur Oak",
                updatedAt: updatedAt
            )
        )
        try context.save()

        var requests: [CloudPageRequest] = []
        var capturedUpserts: [SpeciesPreferenceCloudUpsert] = []
        var finishCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { finishedLease in
                #expect(finishedLease == lease)
                finishCount += 1
            },
            isAccountWorkCurrent: { $0 == lease },
            fetchPage: { requestedUserID, offset, pageSize in
                requests.append(
                    CloudPageRequest(
                        userID: requestedUserID,
                        offset: offset,
                        pageSize: pageSize
                    )
                )
                return []
            },
            upsert: { capturedUpserts = $0 }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client,
            now: { Date(timeIntervalSince1970: 3_000) },
            pageSize: 2
        )

        let didSync = await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        )

        #expect(didSync)
        #expect(requests.count == 1)
        #expect(requests.first?.userID == userID.uuidString)
        #expect(requests.first?.offset == 0)
        #expect(requests.first?.pageSize == 2)
        #expect(finishCount == 1)
        #expect(
            capturedUpserts == [
                SpeciesPreferenceCloudUpsert(
                    user_id: userID.uuidString,
                    scientific_name: "Quercus macrocarpa",
                    preferred_common_name: "Bur Oak",
                    deleted_at: nil
                )
            ]
        )
        let diagnostics = SpeciesPreferredNameStore.syncDiagnostics(
            userDefaults: defaults
        )
        #expect(diagnostics.status == .success)
        #expect(diagnostics.lastSuccessAt == Date(timeIntervalSince1970: 3_000))
        #expect(diagnostics.lastPushedCount == 1)
        #expect(diagnostics.lastPulledCount == 0)
    }

    @Test func syncPaginatesAndAppliesRemoteRows() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lease = makeSpeciesPreferenceLease()
        let rows = [
            makeSpeciesPreferenceCloudRow(
                scientificName: "Quercus alba",
                preferredName: "White Oak",
                updatedAt: "2026-08-01T12:00:00.000Z"
            ),
            makeSpeciesPreferenceCloudRow(
                scientificName: "Quercus macrocarpa",
                preferredName: "Bur Oak",
                updatedAt: "2026-08-01T12:01:00.000Z"
            ),
            makeSpeciesPreferenceCloudRow(
                scientificName: "Quercus stellata",
                preferredName: "Post Oak",
                updatedAt: "2026-08-01T12:02:00.000Z"
            )
        ]
        var offsets: [Int] = []
        var upsertCallCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _, offset, pageSize in
                offsets.append(offset)
                return Array(rows.dropFirst(offset).prefix(pageSize))
            },
            upsert: { _ in upsertCallCount += 1 }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client,
            pageSize: 2
        )

        #expect(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        ))

        #expect(offsets == [0, 2])
        #expect(upsertCallCount == 0)
        #expect(
            try fetchSpeciesPreference(
                for: "Quercus alba",
                modelContext: context
            )?.preferredCommonName == "White Oak"
        )
        #expect(
            try fetchSpeciesPreference(
                for: "Quercus stellata",
                modelContext: context
            )?.preferredCommonName == "Post Oak"
        )
        #expect(
            SpeciesPreferredNameStore.syncDiagnostics(
                userDefaults: defaults
            ).lastPulledCount == 3
        )
    }

    @Test func freshCleanSyncSkipsUnlessForced() async {
        let context: ModelContext
        do {
            context = try makeSpeciesPreferenceContext()
        } catch {
            Issue.record(error)
            return
        }
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 10_000)
        SpeciesPreferredNameStore.recordSyncSuccess(
            at: now.addingTimeInterval(-10),
            pushedCount: 0,
            pulledCount: 0,
            userDefaults: defaults
        )

        let lease = makeSpeciesPreferenceLease()
        var beginCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: {
                beginCount += 1
                return lease
            },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _, _, _ in [] },
            upsert: { _ in }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client,
            now: { now }
        )

        #expect(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults
        ))
        #expect(beginCount == 0)

        #expect(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        ))
        #expect(beginCount == 1)
    }

    @Test func futureSuccessTimestampDoesNotSuppressSync() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 10_000)
        SpeciesPreferredNameStore.recordSyncSuccess(
            at: now.addingTimeInterval(60),
            pushedCount: 0,
            pulledCount: 0,
            userDefaults: defaults
        )

        let lease = makeSpeciesPreferenceLease()
        var beginCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: {
                beginCount += 1
                return lease
            },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _, _, _ in [] },
            upsert: { _ in }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client,
            now: { now }
        )

        #expect(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults
        ))
        #expect(beginCount == 1)
    }

    @Test func unavailableSessionRecordsTheExistingSkipOutcome() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var fetchCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: {
                throw SupabaseAuthTransitionError.signOutInProgress
            },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in false },
            fetchPage: { _, _, _ in
                fetchCount += 1
                return []
            },
            upsert: { _ in }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client,
            now: { Date(timeIntervalSince1970: 4_000) }
        )

        #expect(!(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        )))

        let diagnostics = SpeciesPreferredNameStore.syncDiagnostics(
            userDefaults: defaults
        )
        #expect(fetchCount == 0)
        #expect(diagnostics.status == .skipped)
        #expect(diagnostics.message == "No stable authenticated Supabase session.")
        #expect(diagnostics.lastAttemptAt == Date(timeIntervalSince1970: 4_000))
    }

    @Test func failedFetchFinishesTheLeaseAndCanRecover() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lease = makeSpeciesPreferenceLease()
        var shouldFail = true
        var finishCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in finishCount += 1 },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _, _, _ in
                if shouldFail {
                    throw SpeciesPreferenceCloudTestError.unavailable
                }
                return []
            },
            upsert: { _ in }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client,
            now: { Date(timeIntervalSince1970: 5_000) }
        )

        #expect(!(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        )))
        #expect(finishCount == 1)
        #expect(
            SpeciesPreferredNameStore.syncDiagnostics(
                userDefaults: defaults
            ).status == .failure
        )
        #expect(
            SpeciesPreferredNameStore.syncDiagnostics(
                userDefaults: defaults
            ).message == "Cloud unavailable."
        )

        shouldFail = false
        #expect(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        ))
        #expect(finishCount == 2)
        #expect(
            SpeciesPreferredNameStore.syncDiagnostics(
                userDefaults: defaults
            ).status == .success
        )
    }

    @Test func staleLeaseAfterUpsertKeepsPendingDeleteForRetry() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scientificName = "Quercus macrocarpa"
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: scientificName,
            at: Date(timeIntervalSince1970: 2_000),
            userDefaults: defaults
        )
        let lease = makeSpeciesPreferenceLease()
        var currentCheckCount = 0
        var finishCount = 0
        var capturedUpserts: [SpeciesPreferenceCloudUpsert] = []
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in finishCount += 1 },
            isAccountWorkCurrent: { _ in
                currentCheckCount += 1
                return currentCheckCount < 3
            },
            fetchPage: { _, _, _ in [] },
            upsert: { capturedUpserts = $0 }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client,
            now: { Date(timeIntervalSince1970: 3_000) }
        )

        #expect(!(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        )))

        #expect(finishCount == 1)
        #expect(capturedUpserts.count == 1)
        #expect(capturedUpserts.first?.scientific_name == scientificName)
        #expect(
            SpeciesPreferredNameStore.pendingDeleteDates(
                userDefaults: defaults
            )[scientificName] != nil
        )
        #expect(
            SpeciesPreferredNameStore.syncDiagnostics(
                userDefaults: defaults
            ).status == .failure
        )
    }

    @Test func confirmedRemoteTombstoneClearsPendingDelete() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scientificName = "Quercus macrocarpa"
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: scientificName,
            at: Date(timeIntervalSince1970: 2_000),
            userDefaults: defaults
        )
        let lease = makeSpeciesPreferenceLease()
        var upsertCallCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _, _, _ in
                [
                    SpeciesPreferenceCloudRow(
                        scientific_name: scientificName,
                        preferred_common_name: nil,
                        updated_at: "1970-01-01T00:50:00.000Z",
                        deleted_at: "1970-01-01T00:50:00.000Z"
                    )
                ]
            },
            upsert: { _ in upsertCallCount += 1 }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client
        )

        #expect(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        ))

        #expect(upsertCallCount == 0)
        #expect(
            SpeciesPreferredNameStore.pendingDeleteDates(
                userDefaults: defaults
            ).isEmpty
        )
    }

    @Test func equalTimestampLocalValueWinsOverRemoteTombstone() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scientificName = "Quercus macrocarpa"
        let updatedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(
            UserSpeciesPreference(
                scientificName: scientificName,
                preferredCommonName: "Bur Oak",
                updatedAt: updatedAt
            )
        )
        try context.save()

        let lease = makeSpeciesPreferenceLease()
        var capturedUpserts: [SpeciesPreferenceCloudUpsert] = []
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _, _, _ in
                [
                    makeSpeciesPreferenceCloudRow(
                        scientificName: scientificName,
                        preferredName: nil,
                        updatedAt: "1970-01-01T00:33:20.000Z",
                        deletedAt: "1970-01-01T00:33:20.000Z"
                    )
                ]
            },
            upsert: { capturedUpserts = $0 }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client
        )

        #expect(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        ))

        #expect(capturedUpserts.count == 1)
        #expect(capturedUpserts.first?.preferred_common_name == "Bur Oak")
        #expect(
            try fetchSpeciesPreference(
                for: scientificName,
                modelContext: context
            )?.preferredCommonName == "Bur Oak"
        )
    }

    @Test func overlappingRequestRunsOneTrailingSyncWithLatestContext() async throws {
        let firstContext = try makeSpeciesPreferenceContext()
        let secondContext = try makeSpeciesPreferenceContext()
        secondContext.insert(
            UserSpeciesPreference(
                scientificName: "Quercus stellata",
                preferredCommonName: "Post Oak",
                updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        try secondContext.save()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lease = makeSpeciesPreferenceLease()
        let gate = SpeciesPreferenceCloudSyncGate()
        var beginCount = 0
        var finishCount = 0
        var fetchCount = 0
        var upsertBatches: [[SpeciesPreferenceCloudUpsert]] = []
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: {
                beginCount += 1
                return lease
            },
            finishAccountWork: { _ in finishCount += 1 },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _, _, _ in
                fetchCount += 1
                if fetchCount == 1 {
                    await gate.suspend()
                }
                return []
            },
            upsert: { upsertBatches.append($0) }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client
        )

        let firstTask = Task { @MainActor in
            await coordinator.sync(
                modelContext: firstContext,
                legacyDefaults: defaults,
                force: true
            )
        }
        await gate.waitUntilEntered()

        let secondTask = Task { @MainActor in
            await coordinator.sync(
                modelContext: secondContext,
                legacyDefaults: defaults,
                force: true
            )
        }
        while !coordinator.snapshot.hasPendingRequest {
            await Task.yield()
        }
        #expect(coordinator.snapshot.hasPendingRequest)
        await gate.release()

        #expect(await firstTask.value)
        #expect(await secondTask.value)
        #expect(beginCount == 2)
        #expect(finishCount == 2)
        #expect(fetchCount == 2)
        #expect(upsertBatches.count == 1)
        #expect(upsertBatches.first?.count == 1)
        #expect(
            upsertBatches.first?.first?.scientific_name
                == "Quercus stellata"
        )
        #expect(!coordinator.snapshot.isSyncing)
        #expect(!coordinator.snapshot.hasPendingRequest)
    }

}
