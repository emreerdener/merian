import Foundation
import Supabase

private struct LegacyPurchaseHandoffPreparePayload: Encodable {
    let operation = "prepare"
}

private struct LegacyPurchaseHandoffPrepareResponse: Decodable {
    let success: Bool
    let handoff_id: String
    let handoff_secret: String
    let expires_at: String
}

private struct LegacyPurchaseHandoffContinuePayload: Encodable {
    let operation: String
    let handoff_id: String
    let handoff_secret: String
}

private struct LegacyPurchaseHandoffOperationResponse: Decodable {
    let success: Bool
    let handoff_id: String
}

private struct LegacyPurchaseHandoffBindResponse: Decodable {
    let success: Bool
    let handoff_id: String
    let destination_user_id: String
}

private struct LegacyPurchaseHandoffErrorPayload: Decodable {
    let code: String?
}

extension LegacyPurchaseHandoffRemoteService {
    static func live(client: SupabaseClient) -> Self {
        Self(
            prepare: {
                let response: LegacyPurchaseHandoffPrepareResponse =
                    try await client.functions.invoke(
                        "transfer-signout-purchases",
                        options: .init(
                            body: LegacyPurchaseHandoffPreparePayload()
                        )
                    )
                guard response.success,
                      UUID(uuidString: response.handoff_id) != nil,
                      response.handoff_secret.range(
                          of: #"^[A-Za-z0-9_-]{43}$"#,
                          options: .regularExpression
                      ) != nil,
                      PurchasePrincipalTimestampPolicy
                          .isValidServerTimestamp(response.expires_at) else {
                    throw LegacyPurchaseHandoffRemoteError
                        .invalidResponse
                }
                return LegacyPurchaseIdentityHandoffPreparation(
                    handoffID: response.handoff_id.lowercased(),
                    handoffSecret: response.handoff_secret,
                    expiresAt: response.expires_at
                )
            },
            bind: { handoff, destinationUserID in
                let response: LegacyPurchaseHandoffBindResponse =
                    try await client.functions.invoke(
                        "transfer-signout-purchases",
                        options: .init(
                            body: LegacyPurchaseHandoffContinuePayload(
                                operation: "bind",
                                handoff_id: handoff.handoffId,
                                handoff_secret: handoff.handoffSecret
                            )
                        )
                    )
                guard response.success,
                      response.handoff_id.caseInsensitiveCompare(
                          handoff.handoffId
                      ) == .orderedSame,
                      response.destination_user_id.lowercased()
                        == destinationUserID.lowercased() else {
                    throw LegacyPurchaseHandoffRemoteError
                        .invalidResponse
                }
            },
            complete: { handoff in
                try await Self.performOperation(
                    "complete",
                    handoff: handoff,
                    client: client
                )
            },
            cancel: { handoff in
                try await Self.performOperation(
                    "cancel",
                    handoff: handoff,
                    client: client
                )
            },
            isTerminalProofError: Self.isTerminalProofError
        )
    }

    nonisolated static func isTerminalProofError(_ error: Error) -> Bool {
        guard case let FunctionsError.httpError(_, data) = error,
              let payload = try? JSONDecoder().decode(
                  LegacyPurchaseHandoffErrorPayload.self,
                  from: data
              ) else {
            return false
        }
        return payload.code == "handoff_expired"
            || payload.code == "handoff_invalid"
    }

    private static func performOperation(
        _ operation: String,
        handoff: PendingSignOutPurchaseHandoff,
        client: SupabaseClient
    ) async throws {
        let response: LegacyPurchaseHandoffOperationResponse =
            try await client.functions.invoke(
                "transfer-signout-purchases",
                options: .init(
                    body: LegacyPurchaseHandoffContinuePayload(
                        operation: operation,
                        handoff_id: handoff.handoffId,
                        handoff_secret: handoff.handoffSecret
                    )
                )
            )
        guard response.success,
              response.handoff_id.caseInsensitiveCompare(
                  handoff.handoffId
              ) == .orderedSame else {
            throw LegacyPurchaseHandoffRemoteError
                .invalidResponse
        }
    }
}
