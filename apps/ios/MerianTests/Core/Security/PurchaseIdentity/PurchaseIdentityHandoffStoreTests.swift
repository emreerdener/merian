import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Purchase Identity Handoff Store")
struct PurchaseIdentityHandoffStoreTests {
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

        var dependencies: PurchaseIdentityHandoffStore.Dependencies {
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

    @Test func absentJournalsRemainAbsent() throws {
        let store = makeStore()

        #expect(try store.loadPendingSignOutPurchaseHandoff() == nil)
        #expect(try store.loadPendingPurchasePrincipalAuthRotation() == nil)
    }

    @Test func legacyTransferRoundTripsWithDeviceOnlyAccessibility() throws {
        let spy = SecureStoreSpy()
        let store = makeStore(spy)
        let pending = makeLegacyTransfer()

        try store.persistPendingSignOutPurchaseHandoff(pending)

        #expect(try store.loadPendingSignOutPurchaseHandoff() == pending)
        #expect(
            spy.persistedKeys == [KeychainKeys.pendingSignOutPurchaseHandoff]
        )
        #expect(
            spy.persistedAccessibility == [.whenUnlockedThisDeviceOnly]
        )
    }

    @Test func persistedJournalFieldNamesRemainByteCompatible() throws {
        let legacyObject = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(makeLegacyTransfer())
            ) as? [String: Any]
        )
        #expect(
            Set(legacyObject.keys) == [
                "sourceUserId",
                "handoffId",
                "handoffSecret",
                "expiresAt"
            ]
        )

        let legacyRotationObject = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(makeLegacyRotation())
            ) as? [String: Any]
        )
        #expect(
            Set(legacyRotationObject.keys) == [
                "sourceUserId",
                "purchasePrincipalId",
                "revenueCatAppUserId",
                "installationCapabilityFingerprint",
                "startedAt"
            ]
        )

        let stableObject = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(
                    makeServerRotation(
                        state: .prepared,
                        expiresAt: "2026-10-05T12:00:00Z"
                    )
                )
            ) as? [String: Any]
        )
        #expect(
            Set(stableObject.keys) == [
                "protocolVersion",
                "localState",
                "rotationId",
                "rotationSecret",
                "sourceUserId",
                "purchasePrincipalId",
                "revenueCatAppUserId",
                "bindingGeneration",
                "installationCapabilityFingerprint",
                "startedAt",
                "expiresAt"
            ]
        )
    }

    @Test func malformedLegacyTransferFailsClosed() throws {
        let spy = SecureStoreSpy()
        spy.dataByKey[KeychainKeys.pendingSignOutPurchaseHandoff] = try JSONEncoder()
            .encode(
                PendingSignOutPurchaseHandoff(
                    sourceUserId: "not-a-uuid",
                    handoffId: UUID().uuidString,
                    handoffSecret: String(repeating: "s", count: 43),
                    expiresAt: "2026-09-10T12:00:00Z"
                )
            )

        do {
            _ = try makeStore(spy).loadPendingSignOutPurchaseHandoff()
            Issue.record("Expected malformed legacy proof rejection")
        } catch PurchaseIdentityHandoffStoreError
            .signOutPurchaseHandoffPersistenceFailed {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func failedOrUnverifiedLegacyTransferWriteFailsClosed() throws {
        let pending = makeLegacyTransfer()

        let failedWrite = SecureStoreSpy()
        failedWrite.writeResult = false
        #expect(throws: PurchaseIdentityHandoffStoreError.self) {
            try makeStore(failedWrite)
                .persistPendingSignOutPurchaseHandoff(pending)
        }

        let unverifiedWrite = SecureStoreSpy()
        unverifiedWrite.storesSuccessfulWrites = false
        #expect(throws: PurchaseIdentityHandoffStoreError.self) {
            try makeStore(unverifiedWrite)
                .persistPendingSignOutPurchaseHandoff(pending)
        }
    }

    @Test func invalidJournalsAreRejectedBeforeSecureStorage() throws {
        let legacySpy = SecureStoreSpy()
        let malformedLegacy = PendingSignOutPurchaseHandoff(
            sourceUserId: "not-a-uuid",
            handoffId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            handoffSecret: String(repeating: "s", count: 43),
            expiresAt: "2026-09-10T12:00:00Z"
        )

        do {
            try makeStore(legacySpy)
                .persistPendingSignOutPurchaseHandoff(malformedLegacy)
            Issue.record("Expected invalid legacy journal rejection")
        } catch PurchaseIdentityHandoffStoreError
            .signOutPurchaseHandoffPersistenceFailed {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(legacySpy.persistedKeys.isEmpty)

        let stableSpy = SecureStoreSpy()
        let malformedStable = makeServerRotation(
            state: .prepared,
            expiresAt: nil
        )

        do {
            try makeStore(stableSpy)
                .persistPendingPurchasePrincipalAuthRotation(malformedStable)
            Issue.record("Expected invalid stable journal rejection")
        } catch PurchaseIdentityHandoffStoreError
            .purchasePrincipalRotationPersistenceFailed {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(stableSpy.persistedKeys.isEmpty)
    }

    @Test func preparingServerRotationRoundTripsWithoutManufacturedExpiry() throws {
        let spy = SecureStoreSpy()
        let store = makeStore(spy)
        let pending = makeServerRotation(state: .preparing, expiresAt: nil)

        try store.persistPendingPurchasePrincipalAuthRotation(pending)

        #expect(
            try store.loadPendingPurchasePrincipalAuthRotation()
                == .server(pending)
        )
        #expect(
            spy.persistedKeys == [
                KeychainKeys.pendingPurchasePrincipalAuthRotation
            ]
        )
        #expect(
            spy.persistedAccessibility == [.whenUnlockedThisDeviceOnly]
        )
    }

    @Test func preparedServerRotationRequiresServerExpiry() throws {
        let validSpy = SecureStoreSpy()
        let valid = makeServerRotation(
            state: .prepared,
            expiresAt: "2026-10-05T12:00:00Z"
        )
        validSpy.dataByKey[KeychainKeys.pendingPurchasePrincipalAuthRotation] =
            try JSONEncoder().encode(valid)
        #expect(
            try makeStore(validSpy)
                .loadPendingPurchasePrincipalAuthRotation() == .server(valid)
        )

        let invalidSpy = SecureStoreSpy()
        invalidSpy.dataByKey[
            KeychainKeys.pendingPurchasePrincipalAuthRotation
        ] = try JSONEncoder().encode(
            makeServerRotation(state: .prepared, expiresAt: nil)
        )
        #expect(throws: PurchaseIdentityHandoffStoreError.self) {
            try makeStore(invalidSpy)
                .loadPendingPurchasePrincipalAuthRotation()
        }
    }

    @Test func preparingServerRotationRejectsAnExpiry() throws {
        let spy = SecureStoreSpy()
        spy.dataByKey[KeychainKeys.pendingPurchasePrincipalAuthRotation] =
            try JSONEncoder().encode(
                makeServerRotation(
                    state: .preparing,
                    expiresAt: "2026-10-05T12:00:00Z"
                )
            )

        #expect(throws: PurchaseIdentityHandoffStoreError.self) {
            try makeStore(spy).loadPendingPurchasePrincipalAuthRotation()
        }
    }

    @Test func legacyClientOnlyRotationRemainsReadable() throws {
        let spy = SecureStoreSpy()
        let legacy = makeLegacyRotation()
        spy.dataByKey[KeychainKeys.pendingPurchasePrincipalAuthRotation] =
            try JSONEncoder().encode(legacy)

        #expect(
            try makeStore(spy)
                .loadPendingPurchasePrincipalAuthRotation() == .legacy(legacy)
        )
    }

    @Test func malformedStableRotationFailsClosed() throws {
        let spy = SecureStoreSpy()
        let malformed = ServerPrincipalRotation(
            protocolVersion: 2,
            localState: .preparing,
            rotationId: UUID().uuidString,
            rotationSecret: String(repeating: "s", count: 43),
            sourceUserId: UUID().uuidString,
            purchasePrincipalId: UUID().uuidString,
            revenueCatAppUserId: "MERIAN_PP_test",
            bindingGeneration: 1,
            installationCapabilityFingerprint: String(
                repeating: "a",
                count: 64
            ),
            startedAt: "2026-09-05T12:00:00Z",
            expiresAt: nil
        )
        spy.dataByKey[KeychainKeys.pendingPurchasePrincipalAuthRotation] =
            try JSONEncoder().encode(malformed)

        #expect(throws: PurchaseIdentityHandoffStoreError.self) {
            try makeStore(spy).loadPendingPurchasePrincipalAuthRotation()
        }
    }

    @Test func clearingEachJournalUsesItsExactVerifiedKey() throws {
        let spy = SecureStoreSpy()
        let store = makeStore(spy)

        try store.clearPendingSignOutPurchaseHandoff()
        try store.clearPendingPurchasePrincipalAuthRotation()

        #expect(
            spy.removedKeys == [
                KeychainKeys.pendingSignOutPurchaseHandoff,
                KeychainKeys.pendingPurchasePrincipalAuthRotation
            ]
        )
    }

    @Test func secureStoreFailuresPropagateWithoutBecomingAbsence() throws {
        let readFailure = SecureStoreSpy()
        readFailure.readError = StubError.unavailable
        #expect(throws: StubError.self) {
            try makeStore(readFailure).loadPendingSignOutPurchaseHandoff()
        }

        let removalFailure = SecureStoreSpy()
        removalFailure.removalError = StubError.unavailable
        #expect(throws: StubError.self) {
            try makeStore(removalFailure)
                .clearPendingPurchasePrincipalAuthRotation()
        }
    }

    private func makeStore(
        _ spy: SecureStoreSpy = SecureStoreSpy()
    ) -> PurchaseIdentityHandoffStore {
        PurchaseIdentityHandoffStore(dependencies: spy.dependencies)
    }

    private func makeLegacyTransfer() -> PendingSignOutPurchaseHandoff {
        PendingSignOutPurchaseHandoff(
            sourceUserId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            handoffId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            handoffSecret: String(repeating: "s", count: 43),
            expiresAt: "2026-09-10T12:00:00Z"
        )
    }

    private func makeServerRotation(
        state: PrincipalRotationLocalState,
        expiresAt: String?
    ) -> ServerPrincipalRotation {
        ServerPrincipalRotation(
            protocolVersion: 3,
            localState: state,
            rotationId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            rotationSecret: String(repeating: "r", count: 43),
            sourceUserId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            purchasePrincipalId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            revenueCatAppUserId: "MERIAN_PP_test",
            bindingGeneration: 2,
            installationCapabilityFingerprint: String(
                repeating: "a",
                count: 64
            ),
            startedAt: "2026-09-05T12:00:00Z",
            expiresAt: expiresAt
        )
    }

    private func makeLegacyRotation() -> LegacyPrincipalRotation {
        LegacyPrincipalRotation(
            sourceUserId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            purchasePrincipalId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            revenueCatAppUserId: "MERIAN_PP_legacy",
            installationCapabilityFingerprint: String(
                repeating: "a",
                count: 64
            ),
            startedAt: "2026-09-05T12:00:00Z"
        )
    }
}
