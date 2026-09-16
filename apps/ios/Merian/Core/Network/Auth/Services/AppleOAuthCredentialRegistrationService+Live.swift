import Foundation
import Supabase

private struct AppleOAuthCredentialRegistrationPayload: Encodable {
    let registration_id: String
    let authorization_code: String
    let identity_token: String
}

private struct AppleOAuthCredentialRegistrationResponse: Decodable {
    let success: Bool
    let status: String
}

extension AppleOAuthCredentialRegistrationService {
    static func live(client: SupabaseClient) -> Self {
        Self { registrationID, authorizationCode, identityToken in
            let response: AppleOAuthCredentialRegistrationResponse =
                try await client.functions.invoke(
                    "register-apple-revocation-token",
                    options: .init(
                        body: AppleOAuthCredentialRegistrationPayload(
                            registration_id: registrationID
                                .uuidString.lowercased(),
                            authorization_code: authorizationCode,
                            identity_token: identityToken
                        )
                    )
                )
            return AppleOAuthCredentialRegistrationReceipt(
                success: response.success,
                status: response.status
            )
        }
    }
}
