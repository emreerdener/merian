import Foundation

@MainActor
final class PurchasePrincipalResolver {
    private let remoteService: PurchasePrincipalRemoteService
    private let capabilityStore: PurchasePrincipalCapabilityStore
    private let secureStateStore: PurchasePrincipalSecureStateStore

    init(
        remoteService: PurchasePrincipalRemoteService,
        secureStore: any PurchasePrincipalSecureStore,
        capabilityStore: PurchasePrincipalCapabilityStore? = nil
    ) {
        self.remoteService = remoteService
        self.capabilityStore = capabilityStore ?? PurchasePrincipalCapabilityStore(
            secureStore: secureStore
        )
        secureStateStore = PurchasePrincipalSecureStateStore(
            secureStore: secureStore
        )
    }

    func resolve(
        expectedCapabilityFingerprint: String? = nil,
        allowsCapabilityCreation: Bool = true
    ) async throws -> PurchasePrincipalBinding {
        let stableActivationFingerprint = try secureStateStore
            .loadStableActivationFingerprint()
        let capabilityData = try capabilityStore.loadOrCreate(
            allowsCreation:
                allowsCapabilityCreation && stableActivationFingerprint == nil
        )
        let fingerprint = PurchasePrincipalCapabilityPolicy.fingerprint(
            capabilityData
        )
        guard expectedCapabilityFingerprint.map({ $0 == fingerprint }) ?? true else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        guard stableActivationFingerprint.map({ $0 == fingerprint }) ?? true else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        let capability = PurchasePrincipalSecretPolicy.base64URL(capabilityData)
        let bindingIntentGeneration = try secureStateStore
            .advanceBindingIntentGeneration(
                requiresExisting: stableActivationFingerprint != nil
            )
        let response: PurchasePrincipalResolveResponse
        do {
            response = try await remoteService.resolve(
                .init(
                    installationCapability: capability,
                    bindingIntentGeneration: bindingIntentGeneration
                )
            )
        } catch {
            guard remoteService.isUnsupportedRoute(error),
                  PurchasePrincipalCompatibilityPolicy
                    .allowsLegacyFallback(
                        hasStableActivation:
                            stableActivationFingerprint != nil
                    ) else {
                throw error
            }
            // New clients can roll out before the additive backend route. Only
            // a definite missing route falls back; every transient/auth/service
            // failure remains fail-closed.
            return .legacyFallback
        }
        let binding = try PurchasePrincipalBinding(response: response)
        switch binding.mode {
        case .legacy:
            guard PurchasePrincipalCompatibilityPolicy
                .allowsLegacyFallback(
                    hasStableActivation:
                        stableActivationFingerprint != nil
                ) else {
                throw PurchasePrincipalResolverError.invalidResponse
            }
        case .stable:
            try secureStateStore.persistStableActivationFingerprint(
                fingerprint
            )
        }
        return binding
    }

    static func generateSignoutRotationSecret() throws -> String {
        try PurchasePrincipalSecureRandom.generateRotationSecret()
    }

    func prepareSignoutRotation(
        rotationId: UUID,
        rotationSecret: String,
        expectedBinding: PurchasePrincipalBinding,
        expectedCapabilityFingerprint: String
    ) async throws -> PrincipalRotationPreparation {
        guard expectedBinding.mode == .stable,
              let expectedPrincipalId = expectedBinding.purchasePrincipalId,
              let expectedAppUserId = expectedBinding.revenueCatAppUserId,
              let expectedGeneration = expectedBinding.bindingGeneration,
              expectedGeneration > 0,
              PurchasePrincipalSecretPolicy.isValidRotationSecret(
                  rotationSecret
              ) else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        let capability = try activatedInstallationCapability(
            expectedFingerprint: expectedCapabilityFingerprint
        )
        let response = try await remoteService.prepare(
            .init(
                installationCapability: capability,
                rotationId: rotationId,
                rotationSecret: rotationSecret,
                expectedBindingGeneration: expectedGeneration
            )
        )
        guard response.success,
              response.operation == "prepare_signout_rotation",
              response.rotation_status == "prepared",
              let responseRotationId = UUID(uuidString: response.rotation_id),
              responseRotationId == rotationId,
              let responsePrincipalId = UUID(
                uuidString: response.purchase_principal_id
              ),
              responsePrincipalId == expectedPrincipalId,
              response.revenuecat_app_user_id == expectedAppUserId,
              response.binding_generation == expectedGeneration,
              PurchasePrincipalBinding.isValidRevenueCatAppUserId(
                  response.revenuecat_app_user_id
              ),
              PurchasePrincipalTimestampPolicy.isValidServerTimestamp(
                  response.expires_at
              ) else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        return PrincipalRotationPreparation(
            rotationId: responseRotationId,
            purchasePrincipalId: responsePrincipalId,
            revenueCatAppUserId: response.revenuecat_app_user_id,
            bindingGeneration: response.binding_generation,
            expiresAt: response.expires_at
        )
    }

    func claimSignoutRotation(
        rotationId: UUID,
        rotationSecret: String,
        expectedCapabilityFingerprint: String
    ) async throws -> PurchasePrincipalBinding {
        guard PurchasePrincipalSecretPolicy.isValidRotationSecret(
            rotationSecret
        ) else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        let capability = try activatedInstallationCapability(
            expectedFingerprint: expectedCapabilityFingerprint
        )
        let response = try await remoteService.claim(
            .init(
                installationCapability: capability,
                rotationId: rotationId,
                rotationSecret: rotationSecret
            )
        )
        guard UUID(uuidString: response.rotation_id) == rotationId else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        return try PurchasePrincipalBinding(signOutRotationClaim: response)
    }

    func cancelSignoutRotation(
        rotationId: UUID,
        rotationSecret: String,
        expectedCapabilityFingerprint: String
    ) async throws -> PrincipalRotationCancellation {
        guard PurchasePrincipalSecretPolicy.isValidRotationSecret(
            rotationSecret
        ) else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        let capability = try activatedInstallationCapability(
            expectedFingerprint: expectedCapabilityFingerprint
        )
        let response = try await remoteService.cancel(
            .init(
                installationCapability: capability,
                rotationId: rotationId,
                rotationSecret: rotationSecret
            )
        )
        guard response.success,
              response.operation == "cancel_signout_rotation",
              let responseRotationId = UUID(uuidString: response.rotation_id),
              responseRotationId == rotationId,
              ["cancelled", "expired"].contains(response.rotation_status),
              PurchasePrincipalTimestampPolicy.isValidServerTimestamp(
                  response.expires_at
              ) else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        return PrincipalRotationCancellation(
            rotationId: responseRotationId,
            status: response.rotation_status,
            expiresAt: response.expires_at
        )
    }

    func currentInstallationCapabilityFingerprint() throws -> String {
        let capability = try capabilityStore.loadExisting()
        let fingerprint = PurchasePrincipalCapabilityPolicy.fingerprint(
            capability
        )
        guard try secureStateStore.loadStableActivationFingerprint().map({
            $0 == fingerprint
        }) ?? true else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return fingerprint
    }

    private func activatedInstallationCapability(
        expectedFingerprint: String
    ) throws -> String {
        guard PurchasePrincipalCapabilityPolicy.isValidFingerprint(
            expectedFingerprint
        ) else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        let capability = try capabilityStore.loadExisting()
        let fingerprint = PurchasePrincipalCapabilityPolicy.fingerprint(
            capability
        )
        guard fingerprint == expectedFingerprint,
              try secureStateStore.loadStableActivationFingerprint()
                == fingerprint else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return PurchasePrincipalSecretPolicy.base64URL(capability)
    }
}
