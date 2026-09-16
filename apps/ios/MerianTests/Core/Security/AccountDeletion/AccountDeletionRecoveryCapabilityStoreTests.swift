import Foundation
@testable import Merian
import Testing

@Suite("Account Deletion Recovery Capability Tests")
struct AccountDeletionCapabilityStoreTests {
    private final class SecureStoreStub:
        AccountDeletionRecoverySecureStore {
        var values: [String: Data] = [:]
        var readError: Error?
        var removalError: Error?
        var acceptsWrites = true
        var discardsWrites = false
        private(set) var writes: [
            (key: String, accessibility: KeychainManager.Accessibility)
        ] = []
        private(set) var removals: [String] = []

        func dataOrThrow(forKey key: String) throws -> Data? {
            if let readError { throw readError }
            return values[key]
        }

        func set(
            _ data: Data,
            forKey key: String,
            accessibility: KeychainManager.Accessibility
        ) -> Bool {
            writes.append((key, accessibility))
            guard acceptsWrites else { return false }
            if !discardsWrites {
                values[key] = data
            }
            return true
        }

        func removeObjectVerified(forKey key: String) throws {
            removals.append(key)
            if let removalError { throw removalError }
            values.removeValue(forKey: key)
        }
    }

    private struct SecureStoreFailure: Error {}

    @Test("Capability is device-only, read-verified, and reused")
    func capabilityIsDurableAndStable() throws {
        let secureStore = SecureStoreStub()
        let expected = Data(0..<32)
        let acknowledgement = Data((32..<64).map(UInt8.init))
        var generationCount = 0
        let store = AccountDeletionRecoveryCapabilityStore(
            secureStore: secureStore,
            generateCapability: {
                generationCount += 1
                return generationCount == 1 ? expected : acknowledgement
            }
        )

        let created = try store.prepare()
        let reused = try store.prepare()

        #expect(created.wasCreated)
        #expect(!reused.wasCreated)
        #expect(created.value == reused.value)
        #expect(created.protocolVersion == 2)
        #expect(created.acknowledgementValue != nil)
        #expect(created.acknowledgementValue != created.recoveryValue)
        #expect(created.value.utf8.count == 43)
        #expect(created.value.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil)
        #expect(generationCount == 2)
        #expect(secureStore.writes.count == 1)
        #expect(
            secureStore.writes.first?.key
                == KeychainKeys.accountDeletionRecoveryCapability
        )
        #expect(
            secureStore.writes.first?.accessibility
                == .whenUnlockedThisDeviceOnly
        )
        #expect(try store.loadExistingValue() == created.value)
        #expect(try store.loadExisting() == reused)
    }

    @Test("Locked, corrupt, short, failed, and unverified storage fails closed")
    func storageFailuresFailClosed() {
        let locked = SecureStoreStub()
        locked.readError = SecureStoreFailure()
        #expect(throws: SecureStoreFailure.self) {
            try AccountDeletionRecoveryCapabilityStore(
                secureStore: locked
            ).prepare()
        }
        #expect(locked.writes.isEmpty)

        let corrupt = SecureStoreStub()
        corrupt.values[KeychainKeys.accountDeletionRecoveryCapability] =
            Data(repeating: 0x01, count: 31)
        #expect(throws: AccountDeletionRecoveryCapabilityError.self) {
            try AccountDeletionRecoveryCapabilityStore(
                secureStore: corrupt
            ).prepare()
        }

        let short = SecureStoreStub()
        #expect(throws: AccountDeletionRecoveryCapabilityError.self) {
            try AccountDeletionRecoveryCapabilityStore(
                secureStore: short,
                generateCapability: { Data(repeating: 0x02, count: 31) }
            ).prepare()
        }
        #expect(short.writes.isEmpty)

        let failedWrite = SecureStoreStub()
        failedWrite.acceptsWrites = false
        var failedWriteGeneration = 0
        #expect(throws: AccountDeletionRecoveryCapabilityError.self) {
            try AccountDeletionRecoveryCapabilityStore(
                secureStore: failedWrite,
                generateCapability: {
                    failedWriteGeneration += 1
                    return Data(
                        repeating: failedWriteGeneration == 1 ? 0x03 : 0x13,
                        count: 32
                    )
                }
            ).prepare()
        }

        let unverified = SecureStoreStub()
        unverified.discardsWrites = true
        var unverifiedGeneration = 0
        #expect(throws: AccountDeletionRecoveryCapabilityError.self) {
            try AccountDeletionRecoveryCapabilityStore(
                secureStore: unverified,
                generateCapability: {
                    unverifiedGeneration += 1
                    return Data(
                        repeating: unverifiedGeneration == 1 ? 0x04 : 0x14,
                        count: 32
                    )
                }
            ).prepare()
        }
    }

    @Test("Existing capability is required for recovery")
    func recoveryDoesNotCreateMissingProof() {
        let secureStore = SecureStoreStub()
        var generated = false
        let store = AccountDeletionRecoveryCapabilityStore(
            secureStore: secureStore,
            generateCapability: {
                generated = true
                return Data(repeating: 0x05, count: 32)
            }
        )

        #expect(throws: AccountDeletionRecoveryCapabilityError.self) {
            try store.loadExistingValue()
        }
        #expect(!generated)
        #expect(secureStore.writes.isEmpty)
    }

    @Test("Legacy raw recovery proofs remain protocol-one compatible")
    func legacyRawProofRemainsReadable() throws {
        let secureStore = SecureStoreStub()
        secureStore.values[KeychainKeys.accountDeletionRecoveryCapability] =
            Data(repeating: 0x21, count: 32)
        let capability = try AccountDeletionRecoveryCapabilityStore(
            secureStore: secureStore
        ).prepare()

        #expect(capability.protocolVersion == 1)
        #expect(capability.acknowledgementValue == nil)
        #expect(!capability.wasCreated)
    }

    @Test("Pre-capability intake creates and reuses a verified v1 proof")
    func preCapabilityIntakeCreatesLegacyProof() throws {
        let secureStore = SecureStoreStub()
        let expected = Data(repeating: 0x22, count: 32)
        var generationCount = 0
        let store = AccountDeletionRecoveryCapabilityStore(
            secureStore: secureStore,
            generateCapability: {
                generationCount += 1
                return expected
            }
        )

        let created = try store.prepareLegacyIntake()
        let reused = try store.prepareLegacyIntake()

        #expect(created.protocolVersion == 1)
        #expect(created.acknowledgementValue == nil)
        #expect(created.wasCreated)
        #expect(reused == PreparedDeletionRecoveryCapability(
            protocolVersion: 1,
            recoveryValue: created.recoveryValue,
            acknowledgementValue: nil,
            wasCreated: false
        ))
        #expect(generationCount == 1)
        #expect(
            secureStore.values[
                KeychainKeys.accountDeletionRecoveryCapability
            ] == expected
        )
        #expect(secureStore.writes.count == 1)
        #expect(
            secureStore.writes.first?.accessibility
                == .whenUnlockedThisDeviceOnly
        )
    }

    @Test("Legacy intake refuses an existing v2 envelope")
    func legacyIntakeDoesNotReinterpretV2Proof() throws {
        let secureStore = SecureStoreStub()
        var generationCount = 0
        let store = AccountDeletionRecoveryCapabilityStore(
            secureStore: secureStore,
            generateCapability: {
                generationCount += 1
                return Data(repeating: UInt8(generationCount), count: 32)
            }
        )
        _ = try store.prepare()

        #expect(throws: AccountDeletionRecoveryCapabilityError.self) {
            try store.prepareLegacyIntake()
        }
        #expect(generationCount == 2)
        #expect(secureStore.writes.count == 1)
    }

    @MainActor
    @Test("A markerless or unreadable Keychain proof restores a pre-Auth barrier")
    func orphanedProofRestoresBarrierBeforeAuth() throws {
        let suiteName =
            "AccountDeletionCapabilityStoreTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secureStore = SecureStoreStub()
        secureStore.values[KeychainKeys.accountDeletionRecoveryCapability] =
            Data(repeating: 0x07, count: 32)

        #expect(
            AccountDeletionRecoveryCapabilityStore
                .restoreBarrierBeforeAuthBootstrap(
                    secureStore: secureStore,
                    userDefaults: defaults
                )
        )
        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .capabilityLookupPending
        )

        let uncertainSuiteName =
            "AccountDeletionCapabilityStoreTests.\(UUID())"
        let uncertainDefaults = try #require(
            UserDefaults(suiteName: uncertainSuiteName)
        )
        defer {
            uncertainDefaults.removePersistentDomain(
                forName: uncertainSuiteName
            )
        }
        let unreadable = SecureStoreStub()
        unreadable.readError = SecureStoreFailure()
        #expect(
            AccountDeletionRecoveryCapabilityStore
                .restoreBarrierBeforeAuthBootstrap(
                    secureStore: unreadable,
                    userDefaults: uncertainDefaults
                )
        )
        #expect(
            AccountDeletionLocalCleanupStore.state(
                userDefaults: uncertainDefaults
            ) == .capabilityLookupPending
        )
    }

    @MainActor
    @Test("Verified proof absence does not create a recovery barrier")
    func absentProofKeepsBootstrapOpen() throws {
        let suiteName =
            "AccountDeletionCapabilityStoreTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secureStore = SecureStoreStub()

        #expect(
            AccountDeletionRecoveryCapabilityStore
                .restoreBarrierBeforeAuthBootstrap(
                    secureStore: secureStore,
                    userDefaults: defaults
                )
        )
        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == nil
        )
    }

    @Test("Capability retirement is verified by secure storage")
    func retirementUsesVerifiedRemoval() throws {
        let secureStore = SecureStoreStub()
        secureStore.values[KeychainKeys.accountDeletionRecoveryCapability] =
            Data(repeating: 0x06, count: 32)
        let store = AccountDeletionRecoveryCapabilityStore(
            secureStore: secureStore
        )

        try store.clearVerified()
        #expect(
            secureStore.removals
                == [KeychainKeys.accountDeletionRecoveryCapability]
        )
        #expect(
            secureStore.values[KeychainKeys.accountDeletionRecoveryCapability]
                == nil
        )

        secureStore.removalError = SecureStoreFailure()
        #expect(throws: SecureStoreFailure.self) {
            try store.clearVerified()
        }
    }
}
