import Foundation
import Supabase

private struct GhostProfileMergePreparePayload: Encodable {
    let operation = "prepare"
    let provider: String
    let provider_subject: String
}

private struct GhostProfileMergePrepareResponse: Decodable {
    let handoff_id: String
    let handoff_secret: String
    let expires_at: String
}

private struct GhostProfileMergeCompletePayload: Encodable {
    let operation = "complete"
    let handoff_id: String
    let handoff_secret: String
}

private struct GhostProfileIdentityRefreshPayload: Encodable {
    let operation = "refresh_identity"
}

private struct GhostProfileMergeErrorPayload: Decodable {
    let code: String?
}

extension GhostProfileMergeRemoteService {
    static func live(client: SupabaseClient) -> Self {
        Self(
            prepare: { provider, providerSubject in
                let response: GhostProfileMergePrepareResponse =
                    try await client.functions.invoke(
                        "merge-ghost-profile",
                        options: .init(
                            body: GhostProfileMergePreparePayload(
                                provider: provider,
                                provider_subject: providerSubject
                            )
                        )
                    )
                return GhostProfileMergePreparation(
                    handoffID: response.handoff_id,
                    handoffSecret: response.handoff_secret,
                    expiresAt: response.expires_at
                )
            },
            complete: { handoff in
                try await client.functions.invoke(
                    "merge-ghost-profile",
                    options: .init(
                        body: GhostProfileMergeCompletePayload(
                            handoff_id: handoff.handoffId,
                            handoff_secret: handoff.handoffSecret
                        )
                    )
                )
            },
            refreshIdentity: {
                try await client.functions.invoke(
                    "merge-ghost-profile",
                    options: .init(
                        body: GhostProfileIdentityRefreshPayload()
                    )
                )
            },
            requiresProviderBoundMerge: Self.requiresProviderBoundMerge,
            isTerminalHandoffError: Self.isTerminalHandoffError
        )
    }

    nonisolated static func requiresProviderBoundMerge(
        after error: Error
    ) -> Bool {
        guard let authError = error as? AuthError else { return false }
        return authError.errorCode == .identityAlreadyExists
    }

    nonisolated static func isTerminalHandoffError(
        _ error: Error
    ) -> Bool {
        guard case let FunctionsError.httpError(_, data) = error,
              let payload = try? JSONDecoder().decode(
                  GhostProfileMergeErrorPayload.self,
                  from: data
              ) else {
            return false
        }
        return GhostProfileMergePolicy.shouldDiscardPendingHandoff(
            serverCode: payload.code
        )
    }
}
