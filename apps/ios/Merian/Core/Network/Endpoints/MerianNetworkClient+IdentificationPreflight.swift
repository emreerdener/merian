import Foundation

extension MerianNetworkClient {
    /// Runs only after required consent synchronization and binds the advisory
    /// result and subsequent local checks to the same serialized request owner.
    func prepareIdentificationAuthorization(
        input: IdentificationPreflightInput,
        expectedAuthUserID: UUID,
        validateAttempt: (@MainActor @Sendable () throws -> Void)? = nil
    ) async throws -> IdentificationDispatchAuthorization {
        try Task.checkCancellation()
        let response: Data
        do {
            response = try await performIdentificationRecipientPreflight(
                body: JSONEncoder().encode(input), expectedAuthUserID: expectedAuthUserID
            )
        } catch let error as MerianError {
            // PostgREST uses its own error envelope. Project only the reviewed
            // entitlement denial; never expose raw SQL diagnostics as UI copy.
            if case let .httpError(_, message) = error,
               let data = message.data(using: .utf8), data.count <= 8_192,
               let errorObject = try? JSONDecoder().decode(IdentificationPreflightDatabaseError.self, from: data),
               errorObject.code == "P0001", errorObject.message == "ai_entitlement_required" {
                throw MerianError.httpError(statusCode: 402, message: #"{"code":"pro_required"}"#)
            }
            throw MerianError.edgeFunctionUnavailable
        }
        try Task.checkCancellation()
        guard try await authenticatedUserIDForInferenceRequest() == expectedAuthUserID else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        let recipient: IdentificationRecipientExpectation
        do {
            recipient = try IdentificationPreflightResponse.recipient(from: response, for: input)
        } catch MerianError.aiConsentRequired {
            await MainActor.run {
                let consent = ConsentManager.shared
                if consent.currentSessionUserId == expectedAuthUserID {
                    _ = try? consent.requireCurrentConsentReapprovalAfterServerRejection()
                }
            }
            throw MerianError.aiConsentRequired
        }
        #if DEBUG
        let usesTestConsent = overridingInferenceConsentCheck != nil
            && overridingSession != nil && TestExecutionCoordinator.isRunningTests
        #else
        let usesTestConsent = false
        #endif
        let authorization = IdentificationDispatchAuthorization(recipient: recipient) {
            try Task.checkCancellation()
            try validateAttempt?()
            if usesTestConsent { return }
            let consent = ConsentManager.shared
            guard consent.currentSessionUserId == expectedAuthUserID else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
            // Stored-result recovery never authorizes a fresh provider call.
            if recipient == .recoveryOnly { return }
            guard consent.hasCurrentRequiredConsent else { throw MerianError.aiConsentRequired }
            if recipient == .openAI {
                let permission = consent.aiProcessingPermissions
                guard permission.ownerUserId == expectedAuthUserID, permission.hasCurrentAccount else {
                    throw SupabaseAuthTransitionError.signOutSessionChanged
                }
                if !permission.canProcessOpenAI { throw MerianError.openAIConsentRequired }
            }
        }
        try await authorization.validate()
        return authorization
    }
}

private struct IdentificationPreflightDatabaseError: Decodable {
    let code: String
    let message: String
}
