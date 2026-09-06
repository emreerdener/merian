import Foundation
@testable import Merian
import Testing

@Suite("Purchase Principal Secure State Store")
struct PurchasePrincipalSecureStateStoreTests {
    @Test func stableFingerprintPersistsOnceWithDeviceOnlyAccessibility() throws {
        let secureStore = PurchasePrincipalSecureStoreSpy()
        let store = PurchasePrincipalSecureStateStore(
            secureStore: secureStore
        )
        let fingerprint = String(repeating: "a", count: 64)

        try store.persistStableActivationFingerprint(fingerprint)
        try store.persistStableActivationFingerprint(fingerprint)

        #expect(try store.loadStableActivationFingerprint() == fingerprint)
        #expect(secureStore.writes.count == 1)
        #expect(
            secureStore.writes.first?.key
                == KeychainKeys.purchasePrincipalStableActivationFingerprint
        )
        #expect(
            secureStore.writes.first?.accessibility
                == .whenUnlockedThisDeviceOnly
        )
    }

    @Test func stableFingerprintUncertaintyFailsClosed() throws {
        let invalidInputStore = PurchasePrincipalSecureStoreSpy()
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalSecureStateStore(
                secureStore: invalidInputStore
            ).persistStableActivationFingerprint("not-a-fingerprint")
        }
        #expect(invalidInputStore.writes.isEmpty)

        let malformedStore = PurchasePrincipalSecureStoreSpy()
        malformedStore.values[
            KeychainKeys.purchasePrincipalStableActivationFingerprint
        ] = Data("not-a-fingerprint".utf8)
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalSecureStateStore(
                secureStore: malformedStore
            ).loadStableActivationFingerprint()
        }

        let mismatchedStore = PurchasePrincipalSecureStoreSpy()
        mismatchedStore.values[
            KeychainKeys.purchasePrincipalStableActivationFingerprint
        ] = Data(String(repeating: "a", count: 64).utf8)
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalSecureStateStore(
                secureStore: mismatchedStore
            ).persistStableActivationFingerprint(
                String(repeating: "b", count: 64)
            )
        }

        let unverifiedStore = PurchasePrincipalSecureStoreSpy()
        unverifiedStore.discardsWrites = true
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalSecureStateStore(
                secureStore: unverifiedStore
            ).persistStableActivationFingerprint(
                String(repeating: "c", count: 64)
            )
        }
    }

    @Test func bindingIntentAdvancesAndReadVerifies() throws {
        let secureStore = PurchasePrincipalSecureStoreSpy()
        let store = PurchasePrincipalSecureStateStore(
            secureStore: secureStore
        )

        #expect(
            try store.advanceBindingIntentGeneration(
                requiresExisting: false
            ) == 1
        )
        #expect(
            try store.advanceBindingIntentGeneration(
                requiresExisting: true
            ) == 2
        )
        #expect(
            secureStore.values[
                KeychainKeys.purchasePrincipalBindingIntentGeneration
            ] == Data("2".utf8)
        )
        #expect(
            secureStore.writes.allSatisfy {
                $0.accessibility == .whenUnlockedThisDeviceOnly
            }
        )
    }

    @Test func missingMalformedAndExhaustedIntentStateFailsClosed() throws {
        let missingStore = PurchasePrincipalSecureStoreSpy()
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalSecureStateStore(
                secureStore: missingStore
            ).advanceBindingIntentGeneration(requiresExisting: true)
        }

        for value in ["-1", "01", "not-a-number"] {
            let malformedStore = PurchasePrincipalSecureStoreSpy()
            malformedStore.values[
                KeychainKeys.purchasePrincipalBindingIntentGeneration
            ] = Data(value.utf8)
            #expect(throws: PurchasePrincipalResolverError.self) {
                try PurchasePrincipalSecureStateStore(
                    secureStore: malformedStore
                ).advanceBindingIntentGeneration(requiresExisting: false)
            }
        }

        let exhaustedStore = PurchasePrincipalSecureStoreSpy()
        exhaustedStore.values[
            KeychainKeys.purchasePrincipalBindingIntentGeneration
        ] = Data(
            String(PurchasePrincipalBindingIntentPolicy.maximum).utf8
        )
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalSecureStateStore(
                secureStore: exhaustedStore
            ).advanceBindingIntentGeneration(requiresExisting: false)
        }
    }
}
