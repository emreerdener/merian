import Supabase

private struct PurchasePrincipalResolvePayload: Encodable {
    let operation = "resolve"
    let installation_capability: String
    let client_protocol = PurchasePrincipalProtocol.current
    let binding_intent_generation: Int64
}

private struct PrincipalRotationPreparePayload: Encodable {
    let operation = "prepare_signout_rotation"
    let installation_capability: String
    let client_protocol = PurchasePrincipalProtocol.current
    let rotation_id: String
    let rotation_secret: String
    let expected_binding_generation: Int64
}

private struct PrincipalRotationClaimPayload: Encodable {
    let operation = "claim_signout_rotation"
    let installation_capability: String
    let client_protocol = PurchasePrincipalProtocol.current
    let rotation_id: String
    let rotation_secret: String
}

private struct PrincipalRotationCancelPayload: Encodable {
    let operation = "cancel_signout_rotation"
    let installation_capability: String
    let client_protocol = PurchasePrincipalProtocol.current
    let rotation_id: String
    let rotation_secret: String
}

extension PurchasePrincipalRemoteService {
    static func live(client: SupabaseClient) -> Self {
        Self(
            resolve: { request in
                try await client.functions.invoke(
                    "resolve-purchase-principal",
                    options: .init(
                        body: PurchasePrincipalResolvePayload(
                            installation_capability:
                                request.installationCapability,
                            binding_intent_generation:
                                request.bindingIntentGeneration
                        )
                    )
                )
            },
            prepare: { request in
                try await client.functions.invoke(
                    "resolve-purchase-principal",
                    options: .init(
                        body: PrincipalRotationPreparePayload(
                            installation_capability:
                                request.installationCapability,
                            rotation_id: request.rotationId.uuidString
                                .lowercased(),
                            rotation_secret: request.rotationSecret,
                            expected_binding_generation:
                                request.expectedBindingGeneration
                        )
                    )
                )
            },
            claim: { request in
                try await client.functions.invoke(
                    "resolve-purchase-principal",
                    options: .init(
                        body: PrincipalRotationClaimPayload(
                            installation_capability:
                                request.installationCapability,
                            rotation_id: request.rotationId.uuidString
                                .lowercased(),
                            rotation_secret: request.rotationSecret
                        )
                    )
                )
            },
            cancel: { request in
                try await client.functions.invoke(
                    "resolve-purchase-principal",
                    options: .init(
                        body: PrincipalRotationCancelPayload(
                            installation_capability:
                                request.installationCapability,
                            rotation_id: request.rotationId.uuidString
                                .lowercased(),
                            rotation_secret: request.rotationSecret
                        )
                    )
                )
            },
            isUnsupportedRoute: { error in
                guard let functionsError = error as? FunctionsError,
                      case let .httpError(status, _) = functionsError else {
                    return false
                }
                return status == 404
            }
        )
    }
}

extension PurchasePrincipalResolver {
    convenience init(
        client: SupabaseClient,
        keychain: any PurchasePrincipalSecureStore = KeychainManager.shared
    ) {
        self.init(
            remoteService: .live(client: client),
            secureStore: keychain
        )
    }
}
