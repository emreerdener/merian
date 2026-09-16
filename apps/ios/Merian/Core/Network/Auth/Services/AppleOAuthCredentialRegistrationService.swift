import Foundation

struct AppleOAuthCredentialRegistrationReceipt: Equatable, Sendable {
    let success: Bool
    let status: String
}

/// Typed boundary for the authenticated Apple revocation-credential
/// registration route. Auth-transition and exact-session admission remain with
/// the OAuth coordination layer.
@MainActor
struct AppleOAuthCredentialRegistrationService {
    typealias RegistrationOperation = @MainActor (
        UUID,
        String,
        String
    ) async throws -> AppleOAuthCredentialRegistrationReceipt

    private let registrationOperation: RegistrationOperation

    init(register: @escaping RegistrationOperation) {
        registrationOperation = register
    }

    func register(
        registrationID: UUID,
        authorizationCode: String,
        identityToken: String
    ) async throws {
        let receipt = try await registrationOperation(
            registrationID,
            authorizationCode,
            identityToken
        )
        guard receipt.success,
              receipt.status == "registered" else {
            throw OAuthSignInWorkflowError
                .invalidAppleCredentialRegistrationReceipt
        }
    }
}
