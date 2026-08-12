import Foundation
@testable import Merian
import Testing

@Suite("Purchase Principal Resolver Tests")
struct PurchasePrincipalResolverTests {
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

    @Test("Stable activation permanently disables legacy fallback")
    func stableActivationCompatibilityPolicy() {
        #expect(PurchasePrincipalCompatibilityPolicy.allowsLegacyFallback(
            hasStableActivation: false
        ))
        #expect(!PurchasePrincipalCompatibilityPolicy.allowsLegacyFallback(
            hasStableActivation: true
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
                minimum_client_protocol: 1
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
                        minimum_client_protocol: 1
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
                    minimum_client_protocol: 1
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
                    minimum_client_protocol: 2
                )
            )
        }
    }
}
