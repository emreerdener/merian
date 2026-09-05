import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Ghost Profile Merge Store")
struct GhostProfileMergeStoreTests {
    private enum StubError: Error {
        case unavailable
    }

    private final class SecureStoreSpy {
        var dataByKey: [String: Data] = [:]
        var persistedKeys: [String] = []
        var removedKeys: [String] = []
        var persistedAccessibility: [KeychainManager.Accessibility] = []
        var writeResult = true
        var storesSuccessfulWrites = true
        var readError: Error?
        var removalError: Error?

        var dependencies: GhostProfileMergeStore.Dependencies {
            .init(
                loadData: { [self] key in
                    if let readError {
                        throw readError
                    }
                    return dataByKey[key]
                },
                persistData: { [self] data, key, accessibility in
                    persistedKeys.append(key)
                    persistedAccessibility.append(accessibility)
                    if writeResult && storesSuccessfulWrites {
                        dataByKey[key] = data
                    }
                    return writeResult
                },
                removeDataVerified: { [self] key in
                    if let removalError {
                        throw removalError
                    }
                    dataByKey.removeValue(forKey: key)
                    removedKeys.append(key)
                }
            )
        }
    }

    @Test func absentQueueRemainsAbsent() throws {
        let result = try makeStore().loadPendingHandoffs()

        #expect(result.handoffs.isEmpty)
        #expect(!result.legacyMigrationWasDeferred)
    }

    @Test func queueRoundTripsWithDeviceOnlyAccessibility() throws {
        let spy = SecureStoreSpy()
        let store = makeStore(spy)
        let handoffs = [
            makeHandoff(),
            makeHandoff(index: 2, provider: "google")
        ]

        try store.persistPendingHandoffs(handoffs)

        #expect(try store.loadPendingHandoffs().handoffs == handoffs)
        #expect(
            spy.persistedKeys == [KeychainKeys.pendingGhostProfileMerge]
        )
        #expect(
            spy.persistedAccessibility == [.whenUnlockedThisDeviceOnly]
        )
    }

    @Test func persistedFieldNamesRemainByteCompatible() throws {
        let spy = SecureStoreSpy()
        try makeStore(spy).persistPendingHandoffs([makeHandoff()])
        let data = try #require(
            spy.dataByKey[KeychainKeys.pendingGhostProfileMerge]
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(object.keys) == ["version", "handoffs"])
        #expect(object["version"] as? Int == 1)
        let handoffs = try #require(object["handoffs"] as? [[String: Any]])
        let handoff = try #require(handoffs.first)
        #expect(
            Set(handoff.keys) == [
                "ghostUserId",
                "provider",
                "providerSubject",
                "handoffId",
                "handoffSecret",
                "expiresAt"
            ]
        )
    }

    @Test func legacyRecordMigratesToVersionedQueue() throws {
        let spy = SecureStoreSpy()
        let legacy = makeHandoff()
        spy.dataByKey[KeychainKeys.pendingGhostProfileMerge] =
            try JSONEncoder().encode(legacy)

        let result = try makeStore(spy).loadPendingHandoffs()

        #expect(result.handoffs == [legacy])
        #expect(!result.legacyMigrationWasDeferred)
        let migrated = try JSONDecoder().decode(
            PendingGhostProfileMergeQueue.self,
            from: #require(
                spy.dataByKey[KeychainKeys.pendingGhostProfileMerge]
            )
        )
        #expect(migrated == PendingGhostProfileMergeQueue(handoffs: [legacy]))
    }

    @Test func failedLegacyMigrationPreservesReadableProof() throws {
        let spy = SecureStoreSpy()
        let legacy = makeHandoff()
        spy.dataByKey[KeychainKeys.pendingGhostProfileMerge] =
            try JSONEncoder().encode(legacy)
        spy.writeResult = false

        let result = try makeStore(spy).loadPendingHandoffs()

        #expect(result.handoffs == [legacy])
        #expect(result.legacyMigrationWasDeferred)
        #expect(
            try JSONDecoder().decode(
                PendingGhostProfileMerge.self,
                from: #require(
                    spy.dataByKey[KeychainKeys.pendingGhostProfileMerge]
                )
            ) == legacy
        )
    }

    @Test func malformedOrUnsupportedQueueFailsClosed() throws {
        let malformed = SecureStoreSpy()
        malformed.dataByKey[KeychainKeys.pendingGhostProfileMerge] = Data(
            "not-json".utf8
        )
        #expect(throws: GhostProfileMergeStoreError.self) {
            try makeStore(malformed).loadPendingHandoffs()
        }

        let unsupported = SecureStoreSpy()
        let data = try JSONEncoder().encode(
            PendingGhostProfileMergeQueue(handoffs: [makeHandoff()])
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["version"] = 2
        unsupported.dataByKey[KeychainKeys.pendingGhostProfileMerge] =
            try JSONSerialization.data(withJSONObject: object)
        #expect(throws: GhostProfileMergeStoreError.self) {
            try makeStore(unsupported).loadPendingHandoffs()
        }

        let invalidProof = SecureStoreSpy()
        invalidProof.dataByKey[KeychainKeys.pendingGhostProfileMerge] =
            try JSONEncoder().encode(
                PendingGhostProfileMergeQueue(
                    handoffs: [makeHandoff(handoffSecret: "too-short")]
                )
            )
        #expect(throws: GhostProfileMergeStoreError.self) {
            try makeStore(invalidProof).loadPendingHandoffs()
        }
    }

    @Test func invalidProofsAreRejectedBeforeSecureStorage() throws {
        let invalidProofs = [
            makeHandoff(ghostUserId: "not-a-uuid"),
            makeHandoff(provider: "github"),
            makeHandoff(providerSubject: ""),
            makeHandoff(providerSubject: "subject\u{0085}"),
            makeHandoff(providerSubject: String(repeating: "😀", count: 128)),
            makeHandoff(handoffId: "not-a-uuid"),
            makeHandoff(handoffSecret: "too-short"),
            makeHandoff(handoffSecret: String(repeating: "!", count: 43)),
            makeHandoff(expiresAt: "not-a-timestamp")
        ]

        for proof in invalidProofs {
            let spy = SecureStoreSpy()
            #expect(throws: GhostProfileMergeStoreError.self) {
                try makeStore(spy).persistPendingHandoffs([proof])
            }
            #expect(spy.persistedKeys.isEmpty)
        }
    }

    @Test func serverOwnsExpiryClassification() throws {
        let spy = SecureStoreSpy()
        let expiredByWallClock = makeHandoff(
            expiresAt: "2020-01-01T00:00:00.123456+00:00"
        )

        try makeStore(spy).persistPendingHandoffs([expiredByWallClock])

        #expect(
            try makeStore(spy).loadPendingHandoffs().handoffs
                == [expiredByWallClock]
        )
    }

    @Test func failedOrUnverifiedWriteFailsClosed() throws {
        let failedWrite = SecureStoreSpy()
        failedWrite.writeResult = false
        #expect(throws: GhostProfileMergeStoreError.self) {
            try makeStore(failedWrite).persistPendingHandoffs([makeHandoff()])
        }

        let unverifiedWrite = SecureStoreSpy()
        unverifiedWrite.storesSuccessfulWrites = false
        #expect(throws: GhostProfileMergeStoreError.self) {
            try makeStore(unverifiedWrite)
                .persistPendingHandoffs([makeHandoff()])
        }
    }

    @Test func clearingUsesExactCaseInsensitiveIdentifiers() throws {
        let spy = SecureStoreSpy()
        let store = makeStore(spy)
        let first = makeHandoff()
        let second = makeHandoff(index: 2)
        try store.persistPendingHandoffs([first, second])

        try store.clearPendingHandoff(
            handoffId: first.handoffId.uppercased()
        )
        #expect(try store.loadPendingHandoffs().handoffs == [second])

        let remaining = try store.clearPendingHandoffs(
            ghostUserId: second.ghostUserId.uppercased()
        )
        #expect(remaining.isEmpty)
        #expect(
            spy.removedKeys == [KeychainKeys.pendingGhostProfileMerge]
        )
    }

    @Test func secureStoreFailuresPropagateWithoutBecomingAbsence() throws {
        let readFailure = SecureStoreSpy()
        readFailure.readError = StubError.unavailable
        #expect(throws: StubError.self) {
            try makeStore(readFailure).loadPendingHandoffs()
        }

        let removalFailure = SecureStoreSpy()
        removalFailure.removalError = StubError.unavailable
        #expect(throws: StubError.self) {
            try makeStore(removalFailure).persistPendingHandoffs([])
        }
    }

    private func makeStore(
        _ spy: SecureStoreSpy = SecureStoreSpy()
    ) -> GhostProfileMergeStore {
        GhostProfileMergeStore(dependencies: spy.dependencies)
    }

    private func makeHandoff(
        index: Int = 1,
        ghostUserId: String? = nil,
        provider: String = "apple",
        providerSubject: String = "provider-subject",
        handoffId: String? = nil,
        handoffSecret: String = String(repeating: "s", count: 43),
        expiresAt: String = "2026-10-05T12:00:00Z"
    ) -> PendingGhostProfileMerge {
        let ghostIds = [
            "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        ]
        let handoffIds = [
            "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
        ]
        return PendingGhostProfileMerge(
            ghostUserId: ghostUserId ?? ghostIds[index - 1],
            provider: provider,
            providerSubject: providerSubject,
            handoffId: handoffId ?? handoffIds[index - 1],
            handoffSecret: handoffSecret,
            expiresAt: expiresAt
        )
    }
}
