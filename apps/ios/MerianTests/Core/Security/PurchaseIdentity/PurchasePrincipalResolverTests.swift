import Foundation
@testable import Merian
import Testing

@Suite("Purchase Principal Models, Policies, and Stores")
struct PurchasePrincipalFoundationTests {
    @Test("Capability fingerprints are exact lowercase SHA-256 values")
    func capabilityFingerprintPolicy() {
        let capability = Data(0..<32)
        let fingerprint = PurchasePrincipalCapabilityPolicy.fingerprint(
            capability
        )

        #expect(fingerprint.utf8.count == 64)
        #expect(PurchasePrincipalCapabilityPolicy.isValidFingerprint(fingerprint))
        #expect(!PurchasePrincipalCapabilityPolicy.isValidFingerprint(
            fingerprint.uppercased()
        ))
        #expect(!PurchasePrincipalCapabilityPolicy.isValidFingerprint(
            String(repeating: "٠", count: 64)
        ))
    }

    @Test("Missing capability is created once and read-verified before use")
    func capabilityCreationIsDurable() throws {
        let secureStore = PurchasePrincipalSecureStoreSpy()
        let expected = Data(repeating: 0xA5, count: 32)
        var generationCount = 0
        let store = PurchasePrincipalCapabilityStore(
            secureStore: secureStore,
            generateCapability: {
                generationCount += 1
                return expected
            }
        )

        #expect(try store.loadOrCreate(allowsCreation: true) == expected)
        #expect(try store.loadOrCreate(allowsCreation: true) == expected)
        #expect(generationCount == 1)
        #expect(secureStore.writes.count == 1)
        #expect(
            secureStore.writes.first?.key
                == KeychainKeys.purchasePrincipalInstallationCapability
        )
        #expect(
            secureStore.writes.first?.accessibility
                == .whenUnlockedThisDeviceOnly
        )
    }

    @Test("Missing stable capability fails closed without creating a new identity")
    func missingCapabilityFailsClosedWhenCreationIsForbidden() {
        let secureStore = PurchasePrincipalSecureStoreSpy()
        var generated = false
        let store = PurchasePrincipalCapabilityStore(
            secureStore: secureStore,
            generateCapability: {
                generated = true
                return Data(repeating: 0x01, count: 32)
            }
        )

        #expect(throws: PurchasePrincipalResolverError.self) {
            try store.loadOrCreate(allowsCreation: false)
        }
        #expect(!generated)
        #expect(secureStore.writes.isEmpty)
    }

    @Test("Locked, corrupt, random-failure, and unverified Keychain states fail closed")
    func capabilityStorageFailuresFailClosed() {
        let lockedStore = PurchasePrincipalSecureStoreSpy()
        lockedStore.readError = PurchasePrincipalTestError.locked
        #expect(throws: PurchasePrincipalTestError.self) {
            try PurchasePrincipalCapabilityStore(
                secureStore: lockedStore
            ).loadOrCreate(allowsCreation: true)
        }
        #expect(lockedStore.writes.isEmpty)

        let corruptStore = PurchasePrincipalSecureStoreSpy()
        corruptStore.values[
            KeychainKeys.purchasePrincipalInstallationCapability
        ] = Data(repeating: 0x02, count: 31)
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalCapabilityStore(
                secureStore: corruptStore
            ).loadOrCreate(allowsCreation: true)
        }

        let invalidRandomStore = PurchasePrincipalSecureStoreSpy()
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalCapabilityStore(
                secureStore: invalidRandomStore,
                generateCapability: { Data(repeating: 0x03, count: 31) }
            ).loadOrCreate(allowsCreation: true)
        }
        #expect(invalidRandomStore.writes.isEmpty)

        let failedWriteStore = PurchasePrincipalSecureStoreSpy()
        failedWriteStore.acceptsWrites = false
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalCapabilityStore(
                secureStore: failedWriteStore,
                generateCapability: { Data(repeating: 0x04, count: 32) }
            ).loadOrCreate(allowsCreation: true)
        }

        let unverifiedStore = PurchasePrincipalSecureStoreSpy()
        unverifiedStore.discardsWrites = true
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalCapabilityStore(
                secureStore: unverifiedStore,
                generateCapability: { Data(repeating: 0x05, count: 32) }
            ).loadOrCreate(allowsCreation: true)
        }
    }

    @Test("Stable activation permanently disables legacy fallback")
    func stableActivationCompatibilityPolicy() {
        #expect(PurchasePrincipalCompatibilityPolicy.allowsLegacyFallback(
            hasStableActivation: false
        ))
        #expect(!PurchasePrincipalCompatibilityPolicy.allowsLegacyFallback(
            hasStableActivation: true
        ))
    }

    @Test("Server timestamps accept PostgreSQL fractions and whole seconds")
    func serverTimestampPolicy() {
        #expect(PurchasePrincipalTimestampPolicy.isValidServerTimestamp(
            "2026-09-15T00:00:00.000Z"
        ))
        #expect(PurchasePrincipalTimestampPolicy.isValidServerTimestamp(
            "2026-09-15T00:00:00Z"
        ))
        #expect(!PurchasePrincipalTimestampPolicy.isValidServerTimestamp(
            "2026-09-15"
        ))
        #expect(!PurchasePrincipalTimestampPolicy.isValidServerTimestamp(
            String(repeating: "0", count: 41)
        ))
    }

    @Test("Binding intents advance monotonically and reject exhaustion")
    func bindingIntentPolicy() throws {
        #expect(try PurchasePrincipalBindingIntentPolicy.next(after: 0) == 1)
        #expect(try PurchasePrincipalBindingIntentPolicy.next(after: 41) == 42)
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalBindingIntentPolicy.next(after: -1)
        }
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalBindingIntentPolicy.next(
                after: PurchasePrincipalBindingIntentPolicy.maximum
            )
        }
    }

    @Test("Legacy response remains an explicit compatibility mode")
    func legacyCompatibilityResponse() throws {
        let binding = try PurchasePrincipalBinding(
            response: PurchasePrincipalResolveResponse(
                success: true,
                mode: "legacy",
                purchase_principal_id: nil,
                revenuecat_app_user_id: nil,
                binding_generation: nil,
                account_grants_allowed: nil,
                minimum_client_protocol: 1
            )
        )

        #expect(binding == .legacyFallback)
    }

    @Test("Legacy response cannot bypass the minimum client protocol")
    func legacyResponseRejectsNewerProtocol() {
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalBinding(
                response: PurchasePrincipalResolveResponse(
                    success: true,
                    mode: "legacy",
                    purchase_principal_id: nil,
                    revenuecat_app_user_id: nil,
                    binding_generation: nil,
                    account_grants_allowed: nil,
                    minimum_client_protocol: 4
                )
            )
        }
    }

    @Test("Stable response binds one opaque provider identity and generation")
    func stableResponse() throws {
        let principalID = UUID()
        let binding = try PurchasePrincipalBinding(
            response: PurchasePrincipalResolveResponse(
                success: true,
                mode: "stable",
                purchase_principal_id: principalID.uuidString.lowercased(),
                revenuecat_app_user_id: "MERIAN_PP_0123456789ABCDEF",
                binding_generation: 7,
                account_grants_allowed: false,
                minimum_client_protocol: 2
            )
        )

        #expect(binding.mode == .stable)
        #expect(binding.purchasePrincipalId == principalID)
        #expect(binding.revenueCatAppUserId == "MERIAN_PP_0123456789ABCDEF")
        #expect(binding.bindingGeneration == 7)
        #expect(binding.accountGrantsAllowed == false)
    }

    @Test("Stable response rejects anonymous, control, and incomplete identities")
    func invalidStableResponses() {
        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalBinding(
                response: PurchasePrincipalResolveResponse(
                    success: true,
                    mode: "stable",
                    purchase_principal_id: UUID().uuidString,
                    revenuecat_app_user_id: "MERIAN_PP_PROTOCOL_ONE",
                    binding_generation: 1,
                    account_grants_allowed: false,
                    minimum_client_protocol: 1
                )
            )
        }

        for appUserID in ["", "$RCAnonymousID:unsafe", "unsafe\nidentity"] {
            #expect(throws: PurchasePrincipalResolverError.self) {
                try PurchasePrincipalBinding(
                    response: PurchasePrincipalResolveResponse(
                        success: true,
                        mode: "stable",
                        purchase_principal_id: UUID().uuidString,
                        revenuecat_app_user_id: appUserID,
                        binding_generation: 1,
                        account_grants_allowed: false,
                        minimum_client_protocol: 2
                    )
                )
            }
        }

        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalBinding(
                response: PurchasePrincipalResolveResponse(
                    success: true,
                    mode: "stable",
                    purchase_principal_id: UUID().uuidString,
                    revenuecat_app_user_id: "MERIAN_PP_VALID",
                    binding_generation: nil,
                    account_grants_allowed: false,
                    minimum_client_protocol: 2
                )
            )
        }

        #expect(throws: PurchasePrincipalResolverError.self) {
            try PurchasePrincipalBinding(
                response: PurchasePrincipalResolveResponse(
                    success: true,
                    mode: "stable",
                    purchase_principal_id: UUID().uuidString,
                    revenuecat_app_user_id: "MERIAN_PP_REQUIRES_NEW_CLIENT",
                    binding_generation: 1,
                    account_grants_allowed: false,
                    minimum_client_protocol: 4
                )
            )
        }
    }

    @Test("Stable sign-out claim accepts only a completed anonymous binding")
    func stableSignOutClaimResponse() throws {
        let rotationID = UUID()
        let principalID = UUID()
        let binding = try PurchasePrincipalBinding(
            signOutRotationClaim: PrincipalRotationClaimResponse(
                success: true,
                operation: "claim_signout_rotation",
                rotation_id: rotationID.uuidString.lowercased(),
                rotation_status: "completed",
                expires_at: "2026-09-15T00:00:00Z",
                purchase_principal_id: principalID.uuidString.lowercased(),
                revenuecat_app_user_id: "MERIAN_PP_ROTATED",
                binding_generation: 8,
                account_grants_allowed: false,
                already_claimed: false
            )
        )

        #expect(binding.mode == .stable)
        #expect(binding.purchasePrincipalId == principalID)
        #expect(binding.bindingGeneration == 8)
        #expect(binding.accountGrantsAllowed == false)

        for (status, accountGrantsAllowed) in [
            ("prepared", false),
            ("completed", true)
        ] {
            #expect(throws: PurchasePrincipalResolverError.self) {
                try PurchasePrincipalBinding(
                    signOutRotationClaim: PrincipalRotationClaimResponse(
                        success: true,
                        operation: "claim_signout_rotation",
                        rotation_id: rotationID.uuidString,
                        rotation_status: status,
                        expires_at: "2026-09-15T00:00:00Z",
                        purchase_principal_id: principalID.uuidString,
                        revenuecat_app_user_id: "MERIAN_PP_ROTATED",
                        binding_generation: 8,
                        account_grants_allowed: accountGrantsAllowed,
                        already_claimed: false
                    )
                )
            }
        }
    }

    @Test("Stable sign-out secrets are exact one-use base64url values")
    @MainActor
    func stableSignOutSecretGeneration() throws {
        let first = try PurchasePrincipalResolver
            .generateSignoutRotationSecret()
        let second = try PurchasePrincipalResolver
            .generateSignoutRotationSecret()

        #expect(first.utf8.count == 43)
        #expect(first != second)
        #expect(first.range(
            of: #"^[A-Za-z0-9_-]{43}$"#,
            options: .regularExpression
        ) != nil)
    }
}
