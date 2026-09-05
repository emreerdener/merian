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

        var requests: [SpeciesPreferenceCloudPageRequest] = []
        var capturedUpserts: [SpeciesPreferenceCloudUpsert] = []
        var finishCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { finishedLease in
                #expect(finishedLease == lease)
                finishCount += 1
            },
            isAccountWorkCurrent: { $0 == lease },
            fetchPage: { request in
                requests.append(request)
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
        #expect(requests.first?.afterScientificName == nil)
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
            ownerUserID: userID,
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
        var cursors: [String?] = []
        var upsertCallCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { request in
                cursors.append(request.afterScientificName)
                let startIndex = request.afterScientificName.flatMap { cursor in
                    rows.firstIndex { $0.scientific_name == cursor }.map {
                        $0 + 1
                    }
                } ?? 0
                return Array(
                    rows.dropFirst(startIndex).prefix(request.pageSize)
                )
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

        #expect(cursors.count == 2)
        #expect(cursors[0] == nil)
        #expect(cursors[1] == "Quercus macrocarpa")
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
                ownerUserID: lease.session.userID,
                userDefaults: defaults
            ).lastPulledCount == 3
        )
    }

    @Test func keysetPaginationDefersRowsInsertedBeforeCursorWithoutDuplicatingPages() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lease = makeSpeciesPreferenceLease()
        var remoteRows = [
            makeSpeciesPreferenceCloudRow(
                scientificName: "Aquila alpha",
                preferredName: "Alpha",
                updatedAt: "2026-08-01T12:00:00.000Z"
            ),
            makeSpeciesPreferenceCloudRow(
                scientificName: "Aquila charlie",
                preferredName: "Charlie",
                updatedAt: "2026-08-01T12:00:00.000Z"
            )
        ]
        var cursors: [String?] = []
        var fetchCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { request in
                cursors.append(request.afterScientificName)
                fetchCount += 1
                let page = remoteRows
                    .filter { row in
                        request.afterScientificName.map {
                            row.scientific_name > $0
                        } ?? true
                    }
                    .prefix(request.pageSize)

                if fetchCount == 1 {
                    remoteRows = [
                        remoteRows[0],
                        makeSpeciesPreferenceCloudRow(
                            scientificName: "Aquila bravo",
                            preferredName: "Bravo",
                            updatedAt: "2026-08-01T12:00:00.000Z"
                        ),
                        remoteRows[1],
                        makeSpeciesPreferenceCloudRow(
                            scientificName: "Aquila delta",
                            preferredName: "Delta",
                            updatedAt: "2026-08-01T12:00:00.000Z"
                        )
                    ]
                }
                return Array(page)
            },
            upsert: { _ in }
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
        #expect(cursors == [nil, "Aquila charlie"])
        #expect(try fetchSpeciesPreference(
            for: "Aquila alpha",
            modelContext: context
        ) != nil)
        #expect(try fetchSpeciesPreference(
            for: "Aquila charlie",
            modelContext: context
        ) != nil)
        #expect(try fetchSpeciesPreference(
            for: "Aquila delta",
            modelContext: context
        ) != nil)
        #expect(try fetchSpeciesPreference(
            for: "Aquila bravo",
            modelContext: context
        ) == nil)

        cursors.removeAll()
        #expect(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        ))
        #expect(cursors == [nil, "Aquila bravo", "Aquila delta"])
        #expect(try fetchSpeciesPreference(
            for: "Aquila bravo",
            modelContext: context
        )?.preferredCommonName == "Bravo")
    }

    @Test func oneAccountsFreshMarkerDoesNotSuppressAnotherAccountsSync() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 10_000)
        let ownerA = try #require(
            UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        )
        let ownerB = try #require(
            UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        )
        SpeciesPreferredNameStore.recordSyncSuccess(
            ownerUserID: ownerA,
            at: now.addingTimeInterval(-10),
            pushedCount: 0,
            pulledCount: 0,
            userDefaults: defaults
        )
        let lease = makeSpeciesPreferenceLease(userID: ownerB)
        var fetchCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _ in
                fetchCount += 1
                return []
            },
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
        #expect(fetchCount == 1)
        #expect(
            SpeciesPreferredNameStore.syncDiagnostics(
                ownerUserID: ownerB,
                userDefaults: defaults
            ).status == .success
        )
    }

    @Test func remoteOverflowFailsBeforeUpsertOrLocalMutation() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lease = makeSpeciesPreferenceLease()
        let remoteRows = (0 ..< 4).map { index in
            makeSpeciesPreferenceCloudRow(
                scientificName: "Species \(index)",
                preferredName: "Preferred \(index)",
                updatedAt: "2026-08-01T12:00:00.000Z"
            )
        }
        var upsertCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { request in
                let rows = remoteRows.filter { row in
                    request.afterScientificName.map {
                        row.scientific_name > $0
                    } ?? true
                }
                return Array(rows.prefix(request.pageSize))
            },
            upsert: { _ in upsertCount += 1 }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client,
            maximumLocalPreferenceCount: 3,
            pageSize: 2
        )

        #expect(!(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        )))
        #expect(upsertCount == 0)
        #expect(try context.fetch(
            FetchDescriptor<UserSpeciesPreference>()
        ).isEmpty)
        #expect(
            SpeciesPreferredNameStore.syncDiagnostics(
                ownerUserID: lease.session.userID,
                userDefaults: defaults
            ).status == .failure
        )
    }

    @Test func pendingDeleteUnionOverflowFailsBeforeUpsert() async throws {
        let context = try makeSpeciesPreferenceContext()
        context.insert(UserSpeciesPreference(
            scientificName: "Species local",
            preferredCommonName: "Local"
        ))
        try context.save()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lease = makeSpeciesPreferenceLease()
        for scientificName in ["Species deleted A", "Species deleted B"] {
            SpeciesPreferredNameStore.markPendingCloudDelete(
                for: scientificName,
                ownerUserID: lease.session.userID,
                userDefaults: defaults
            )
        }
        var upsertCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _ in [] },
            upsert: { _ in upsertCount += 1 }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client,
            maximumLocalPreferenceCount: 2
        )

        #expect(!(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        )))
        #expect(upsertCount == 0)
        #expect(
            SpeciesPreferredNameStore.syncDiagnostics(
                ownerUserID: lease.session.userID,
                userDefaults: defaults
            ).status == .failure
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
        let lease = makeSpeciesPreferenceLease()
        SpeciesPreferredNameStore.recordSyncSuccess(
            ownerUserID: lease.session.userID,
            at: now.addingTimeInterval(-10),
            pushedCount: 0,
            pulledCount: 0,
            userDefaults: defaults
        )

        var beginCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: {
                beginCount += 1
                return lease
            },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _ in [] },
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

        #expect(await coordinator.sync(
            modelContext: context,
            legacyDefaults: defaults,
            force: true
        ))
        #expect(beginCount == 2)
    }

    @Test func laterFailureInvalidatesARecentSuccess() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 10_000)
        let lease = makeSpeciesPreferenceLease()
        SpeciesPreferredNameStore.recordSyncSuccess(
            ownerUserID: lease.session.userID,
            at: now.addingTimeInterval(-10),
            pushedCount: 0,
            pulledCount: 0,
            userDefaults: defaults
        )
        SpeciesPreferredNameStore.recordSyncFailure(
            "Most recent attempt failed.",
            ownerUserID: lease.session.userID,
            at: now.addingTimeInterval(-5),
            userDefaults: defaults
        )

        var fetchCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _ in
                fetchCount += 1
                return []
            },
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
        #expect(fetchCount == 1)
    }

    @Test func futureSuccessTimestampDoesNotSuppressSync() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 10_000)
        let lease = makeSpeciesPreferenceLease()
        SpeciesPreferredNameStore.recordSyncSuccess(
            ownerUserID: lease.session.userID,
            at: now.addingTimeInterval(60),
            pushedCount: 0,
            pulledCount: 0,
            userDefaults: defaults
        )

        var beginCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: {
                beginCount += 1
                return lease
            },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _ in [] },
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

    @Test func unavailableSessionDoesNotWriteUnscopedDiagnostics() async throws {
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
            fetchPage: { _ in
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

        #expect(fetchCount == 0)
        #expect(!SpeciesPreferredNameStore.hasStoredAccountData(
            userDefaults: defaults
        ))
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
            fetchPage: { _ in
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
                ownerUserID: lease.session.userID,
                userDefaults: defaults
            ).status == .failure
        )
        #expect(
            SpeciesPreferredNameStore.syncDiagnostics(
                ownerUserID: lease.session.userID,
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
                ownerUserID: lease.session.userID,
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
            ownerUserID: speciesPreferenceTestUserID,
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
            fetchPage: { _ in [] },
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
                ownerUserID: lease.session.userID,
                userDefaults: defaults
            )[scientificName] != nil
        )
        #expect(
            SpeciesPreferredNameStore.syncDiagnostics(
                ownerUserID: lease.session.userID,
                userDefaults: defaults
            ).status == .failure
        )
    }

    @Test func newerPendingDeleteCreatedDuringUpsertRemainsQueued() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scientificName = "Quercus macrocarpa"
        let lease = makeSpeciesPreferenceLease()
        let firstDeleteDate = Date(timeIntervalSince1970: 2_000)
        let newerDeleteDate = Date(timeIntervalSince1970: 3_000)
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: scientificName,
            ownerUserID: lease.session.userID,
            at: firstDeleteDate,
            userDefaults: defaults
        )
        let gate = SpeciesPreferenceCloudSyncGate()
        var capturedUpserts: [SpeciesPreferenceCloudUpsert] = []
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _ in [] },
            upsert: { upserts in
                capturedUpserts = upserts
                await gate.suspend()
            }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client
        )

        let syncTask = Task { @MainActor in
            await coordinator.sync(
                modelContext: context,
                legacyDefaults: defaults,
                force: true
            )
        }
        await gate.waitUntilEntered()
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: scientificName,
            ownerUserID: lease.session.userID,
            at: newerDeleteDate,
            userDefaults: defaults
        )
        await gate.release()

        #expect(await syncTask.value)
        #expect(capturedUpserts.count == 1)
        #expect(capturedUpserts.first?.deleted_at == SpeciesPreferredNamePolicy
            .cloudString(firstDeleteDate))
        #expect(
            SpeciesPreferredNameStore.pendingDeleteDates(
                ownerUserID: lease.session.userID,
                userDefaults: defaults
            )[scientificName] == newerDeleteDate
        )
    }

    @Test func localEditDuringUpsertIsNotOverwrittenByStaleRemoteRow() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let lease = makeSpeciesPreferenceLease()
        let editedScientificName = "Quercus macrocarpa"
        context.insert(UserSpeciesPreference(
            scientificName: "Quercus alba",
            preferredCommonName: "White Oak",
            updatedAt: Date(timeIntervalSince1970: 2_000)
        ))
        try context.save()
        let gate = SpeciesPreferenceCloudSyncGate()
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _ in
                [
                    makeSpeciesPreferenceCloudRow(
                        scientificName: editedScientificName,
                        preferredName: "Old Bur Oak",
                        updatedAt: "1970-01-01T00:50:00.000Z"
                    )
                ]
            },
            upsert: { _ in await gate.suspend() }
        )
        let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
            client: client
        )

        let syncTask = Task { @MainActor in
            await coordinator.sync(
                modelContext: context,
                legacyDefaults: defaults,
                force: true
            )
        }
        await gate.waitUntilEntered()
        context.insert(UserSpeciesPreference(
            scientificName: editedScientificName,
            preferredCommonName: "New Bur Oak",
            updatedAt: Date(timeIntervalSince1970: 4_000)
        ))
        try context.save()
        await gate.release()

        #expect(await syncTask.value)
        #expect(
            try fetchSpeciesPreference(
                for: editedScientificName,
                modelContext: context
            )?.preferredCommonName == "New Bur Oak"
        )
    }

    @Test func confirmedRemoteTombstoneClearsPendingDelete() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scientificName = "Quercus macrocarpa"
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: scientificName,
            ownerUserID: speciesPreferenceTestUserID,
            at: Date(timeIntervalSince1970: 2_000),
            userDefaults: defaults
        )
        let lease = makeSpeciesPreferenceLease()
        var upsertCallCount = 0
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _ in
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
                ownerUserID: lease.session.userID,
                userDefaults: defaults
            ).isEmpty
        )
    }

    @Test func newerActiveValueRepairsInterruptedPendingDeleteCleanup() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scientificName = "Quercus macrocarpa"
        let lease = makeSpeciesPreferenceLease()
        context.insert(UserSpeciesPreference(
            scientificName: scientificName,
            preferredCommonName: "Bur Oak",
            updatedAt: Date(timeIntervalSince1970: 3_000)
        ))
        try context.save()
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: scientificName,
            ownerUserID: lease.session.userID,
            at: Date(timeIntervalSince1970: 2_000),
            userDefaults: defaults
        )

        var capturedUpserts: [SpeciesPreferenceCloudUpsert] = []
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _ in [] },
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
        #expect(capturedUpserts.first?.deleted_at == nil)
        #expect(
            SpeciesPreferredNameStore.pendingDeleteDates(
                ownerUserID: lease.session.userID,
                userDefaults: defaults
            ).isEmpty
        )
        #expect(
            try fetchSpeciesPreference(
                for: scientificName,
                modelContext: context
            )?.preferredCommonName == "Bur Oak"
        )
    }

    @Test func newerPendingDeleteRepairsInterruptedLocalRowCleanup() async throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scientificName = "Quercus macrocarpa"
        let lease = makeSpeciesPreferenceLease()
        context.insert(UserSpeciesPreference(
            scientificName: scientificName,
            preferredCommonName: "Bur Oak",
            updatedAt: Date(timeIntervalSince1970: 2_000)
        ))
        try context.save()
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: scientificName,
            ownerUserID: lease.session.userID,
            at: Date(timeIntervalSince1970: 3_000),
            userDefaults: defaults
        )

        var capturedUpserts: [SpeciesPreferenceCloudUpsert] = []
        let client = SpeciesPreferredNameCloudClient(
            beginAccountWork: { lease },
            finishAccountWork: { _ in },
            isAccountWorkCurrent: { _ in true },
            fetchPage: { _ in [] },
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
        #expect(capturedUpserts.first?.preferred_common_name == nil)
        #expect(capturedUpserts.first?.deleted_at != nil)
        #expect(
            SpeciesPreferredNameStore.pendingDeleteDates(
                ownerUserID: lease.session.userID,
                userDefaults: defaults
            ).isEmpty
        )
        #expect(
            try fetchSpeciesPreference(
                for: scientificName,
                modelContext: context
            ) == nil
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
            fetchPage: { _ in
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

    @Test func overlappingRequestsPreserveForcedTrailingSync() async throws {
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
            fetchPage: { _ in
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

        var laterLifecycleRequestStarted = false
        let laterLifecycleTask = Task { @MainActor in
            laterLifecycleRequestStarted = true
            return await coordinator.sync(
                modelContext: secondContext,
                legacyDefaults: defaults,
                force: false
            )
        }
        while !laterLifecycleRequestStarted {
            await Task.yield()
        }
        await Task.yield()
        await gate.release()

        #expect(await firstTask.value)
        #expect(await secondTask.value)
        #expect(await laterLifecycleTask.value)
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
