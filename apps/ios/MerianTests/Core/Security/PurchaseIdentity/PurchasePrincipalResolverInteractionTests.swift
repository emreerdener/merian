import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Purchase Principal Resolver Interactions")
struct PurchasePrincipalResolverInteractionTests {
    @Test func legacyResolutionForwardsCapabilityAndPersistsIntent() async throws {
        let secureStore = PurchasePrincipalSecureStoreSpy()
        let capability = Data(0..<32)
        secureStore.values[
            KeychainKeys.purchasePrincipalInstallationCapability
        ] = capability
        var request: PurchasePrincipalRemoteService.ResolveRequest?
        let resolver = makeResolver(
            secureStore: secureStore,
            remoteService: remoteService(resolve: {
                request = $0
                return Self.legacyResponse
            })
        )

        let binding = try await resolver.resolve()

        #expect(binding == .legacyFallback)
        #expect(
            request == .init(
                installationCapability:
                    PurchasePrincipalSecretPolicy.base64URL(capability),
                bindingIntentGeneration: 1
            )
        )
        #expect(
            secureStore.values[
                KeychainKeys.purchasePrincipalBindingIntentGeneration
            ] == Data("1".utf8)
        )
    }

    @Test func stableResolutionPersistsActivationAndRejectsLegacyRegression() async throws {
        let secureStore = PurchasePrincipalSecureStoreSpy()
        let capability = Data(repeating: 0xA5, count: 32)
        secureStore.values[
            KeychainKeys.purchasePrincipalInstallationCapability
        ] = capability
        var returnsStable = true
        let resolver = makeResolver(
            secureStore: secureStore,
            remoteService: remoteService(resolve: { _ in
                if returnsStable {
                    return Self.stableResponse()
                }
                return Self.legacyResponse
            })
        )

        let binding = try await resolver.resolve()
        let fingerprint = PurchasePrincipalCapabilityPolicy.fingerprint(
            capability
        )

        #expect(binding.isStable)
        #expect(
            secureStore.values[
                KeychainKeys.purchasePrincipalStableActivationFingerprint
            ] == Data(fingerprint.utf8)
        )

        returnsStable = false
        await #expect(throws: PurchasePrincipalResolverError.self) {
            try await resolver.resolve()
        }
    }

    @Test func onlyDefiniteMissingRouteMayUseLegacyFallback() async throws {
        let missingRouteStore = makeSecureStore()
        let missingRouteResolver = makeResolver(
            secureStore: missingRouteStore,
            remoteService: remoteService(
                resolve: { _ in throw PurchasePrincipalTestError.notFound },
                isUnsupportedRoute: {
                    ($0 as? PurchasePrincipalTestError) == .notFound
                }
            )
        )

        #expect(try await missingRouteResolver.resolve() == .legacyFallback)

        let transportStore = makeSecureStore()
        let transportResolver = makeResolver(
            secureStore: transportStore,
            remoteService: remoteService(
                resolve: { _ in throw PurchasePrincipalTestError.transport },
                isUnsupportedRoute: { _ in false }
            )
        )
        await #expect(throws: PurchasePrincipalTestError.self) {
            try await transportResolver.resolve()
        }

        let activatedStore = makeSecureStore(stable: true)
        let activatedResolver = makeResolver(
            secureStore: activatedStore,
            remoteService: remoteService(
                resolve: { _ in throw PurchasePrincipalTestError.notFound },
                isUnsupportedRoute: { _ in true }
            )
        )
        await #expect(throws: PurchasePrincipalTestError.self) {
            try await activatedResolver.resolve()
        }
    }

    @Test func responseValidationErrorsNeverEnterRouteFallback() async throws {
        let secureStore = makeSecureStore()
        var didClassifyError = false
        let resolver = makeResolver(
            secureStore: secureStore,
            remoteService: remoteService(
                resolve: { _ in
                    PurchasePrincipalResolveResponse(
                        success: false,
                        mode: "legacy",
                        purchase_principal_id: nil,
                        revenuecat_app_user_id: nil,
                        binding_generation: nil,
                        account_grants_allowed: nil,
                        minimum_client_protocol: 1
                    )
                },
                isUnsupportedRoute: { _ in
                    didClassifyError = true
                    return true
                }
            )
        )

        await #expect(throws: PurchasePrincipalResolverError.self) {
            try await resolver.resolve()
        }
        #expect(!didClassifyError)
    }

    @Test func stableRotationOperationsForwardTypedRequests() async throws {
        let secureStore = makeSecureStore(stable: true)
        let capability = try #require(
            secureStore.values[
                KeychainKeys.purchasePrincipalInstallationCapability
            ]
        )
        let fingerprint = PurchasePrincipalCapabilityPolicy.fingerprint(
            capability
        )
        let rotationId = UUID()
        let principalId = UUID()
        let appUserId = "MERIAN_PP_ROTATION_TEST"
        let secret = String(repeating: "s", count: 43)
        let expectedBinding = try PurchasePrincipalBinding(
            response: Self.stableResponse(
                principalId: principalId,
                appUserId: appUserId,
                generation: 7
            )
        )
        var prepareRequest: PurchasePrincipalRemoteService.PrepareRequest?
        var claimRequest: PurchasePrincipalRemoteService.ClaimRequest?
        var cancelRequest: PurchasePrincipalRemoteService.CancelRequest?
        let service = PurchasePrincipalRemoteService(
            resolve: { _ in Self.legacyResponse },
            prepare: {
                prepareRequest = $0
                return PrincipalRotationPrepareResponse(
                    success: true,
                    operation: "prepare_signout_rotation",
                    rotation_id: rotationId.uuidString.lowercased(),
                    rotation_status: "prepared",
                    expires_at: "2026-10-05T12:00:00.000Z",
                    purchase_principal_id: principalId.uuidString.lowercased(),
                    revenuecat_app_user_id: appUserId,
                    binding_generation: 7,
                    already_prepared: false
                )
            },
            claim: {
                claimRequest = $0
                return PrincipalRotationClaimResponse(
                    success: true,
                    operation: "claim_signout_rotation",
                    rotation_id: rotationId.uuidString.lowercased(),
                    rotation_status: "completed",
                    expires_at: "2026-10-05T12:00:00.000Z",
                    purchase_principal_id: principalId.uuidString.lowercased(),
                    revenuecat_app_user_id: appUserId,
                    binding_generation: 8,
                    account_grants_allowed: false,
                    already_claimed: false
                )
            },
            cancel: {
                cancelRequest = $0
                return PrincipalRotationCancelResponse(
                    success: true,
                    operation: "cancel_signout_rotation",
                    rotation_id: rotationId.uuidString.lowercased(),
                    rotation_status: "cancelled",
                    expires_at: "2026-10-05T12:00:00.000Z",
                    already_cancelled: false
                )
            },
            isUnsupportedRoute: { _ in false }
        )
        let resolver = makeResolver(
            secureStore: secureStore,
            remoteService: service
        )

        let preparation = try await resolver.prepareSignoutRotation(
            rotationId: rotationId,
            rotationSecret: secret,
            expectedBinding: expectedBinding,
            expectedCapabilityFingerprint: fingerprint
        )
        let claimed = try await resolver.claimSignoutRotation(
            rotationId: rotationId,
            rotationSecret: secret,
            expectedCapabilityFingerprint: fingerprint
        )
        let cancellation = try await resolver.cancelSignoutRotation(
            rotationId: rotationId,
            rotationSecret: secret,
            expectedCapabilityFingerprint: fingerprint
        )

        let encodedCapability = PurchasePrincipalSecretPolicy.base64URL(
            capability
        )
        #expect(
            prepareRequest == .init(
                installationCapability: encodedCapability,
                rotationId: rotationId,
                rotationSecret: secret,
                expectedBindingGeneration: 7
            )
        )
        #expect(
            claimRequest == .init(
                installationCapability: encodedCapability,
                rotationId: rotationId,
                rotationSecret: secret
            )
        )
        #expect(
            cancelRequest == .init(
                installationCapability: encodedCapability,
                rotationId: rotationId,
                rotationSecret: secret
            )
        )
        #expect(preparation.bindingGeneration == 7)
        #expect(claimed.bindingGeneration == 8)
        #expect(cancellation.status == "cancelled")
    }

    private func makeResolver(
        secureStore: PurchasePrincipalSecureStoreSpy,
        remoteService: PurchasePrincipalRemoteService
    ) -> PurchasePrincipalResolver {
        PurchasePrincipalResolver(
            remoteService: remoteService,
            secureStore: secureStore
        )
    }

    private func makeSecureStore(
        stable: Bool = false
    ) -> PurchasePrincipalSecureStoreSpy {
        let secureStore = PurchasePrincipalSecureStoreSpy()
        let capability = Data(repeating: 0x5A, count: 32)
        secureStore.values[
            KeychainKeys.purchasePrincipalInstallationCapability
        ] = capability
        if stable {
            let fingerprint = PurchasePrincipalCapabilityPolicy.fingerprint(
                capability
            )
            secureStore.values[
                KeychainKeys.purchasePrincipalStableActivationFingerprint
            ] = Data(fingerprint.utf8)
            secureStore.values[
                KeychainKeys.purchasePrincipalBindingIntentGeneration
            ] = Data("1".utf8)
        }
        return secureStore
    }

    private func remoteService(
        resolve: @escaping PurchasePrincipalRemoteService.ResolveOperation,
        isUnsupportedRoute: @escaping PurchasePrincipalRemoteService
            .UnsupportedRouteClassifier = { _ in false }
    ) -> PurchasePrincipalRemoteService {
        PurchasePrincipalRemoteService(
            resolve: resolve,
            prepare: { _ in throw PurchasePrincipalTestError.transport },
            claim: { _ in throw PurchasePrincipalTestError.transport },
            cancel: { _ in throw PurchasePrincipalTestError.transport },
            isUnsupportedRoute: isUnsupportedRoute
        )
    }

    private static let legacyResponse = PurchasePrincipalResolveResponse(
        success: true,
        mode: "legacy",
        purchase_principal_id: nil,
        revenuecat_app_user_id: nil,
        binding_generation: nil,
        account_grants_allowed: nil,
        minimum_client_protocol: 1
    )

    private static func stableResponse(
        principalId: UUID = UUID(),
        appUserId: String = "MERIAN_PP_STABLE_TEST",
        generation: Int64 = 7
    ) -> PurchasePrincipalResolveResponse {
        PurchasePrincipalResolveResponse(
            success: true,
            mode: "stable",
            purchase_principal_id: principalId.uuidString.lowercased(),
            revenuecat_app_user_id: appUserId,
            binding_generation: generation,
            account_grants_allowed: false,
            minimum_client_protocol: 3
        )
    }
}
