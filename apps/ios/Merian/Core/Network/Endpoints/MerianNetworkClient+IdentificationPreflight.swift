import Foundation

extension MerianNetworkClient {
    /// Runs only after required consent synchronization and binds the advisory
    /// result and subsequent local checks to the same serialized request owner.
    func prepareIdentificationAuthorization(
        input: IdentificationPreflightInput,
        expectedAuthUserID: UUID,
        validateAttempt: (@MainActor @Sendable () throws -> Void)? = nil
    ) async throws -> IdentificationDispatchAuthorization {
        try await prepareIdentificationAuthorization(expectedAuthUserID: expectedAuthUserID,
            validateAttempt: validateAttempt, preflight: {
                try await performOwnedIdentificationRead(
                    body: JSONEncoder().encode(input), expectedAuthUserID: expectedAuthUserID)
            }, decode: { try IdentificationPreflightResponse.recipient(from: $0, for: input) })
    }

    /// The child already has a durable identity. This read neither starts work nor selects a result.
    func prepareIdentificationAuthorization(
        input: ObservationReanalysisPreflightRequest,
        expectedAuthUserID: UUID,
        validateAttempt: (@MainActor @Sendable () throws -> Void)? = nil
    ) async throws -> IdentificationDispatchAuthorization {
        struct Parameters: Encodable { let p_request: ObservationReanalysisPreflightRequest }
        return try await prepareIdentificationAuthorization(expectedAuthUserID: expectedAuthUserID,
            validateAttempt: validateAttempt, preflight: {
                try await performOwnedIdentificationRead(
                    body: JSONEncoder().encode(Parameters(p_request: input)),
                    expectedAuthUserID: expectedAuthUserID, route: .reanalysisRecipient)
            }, decode: { try ObservationReanalysisPreflightRequest.recipient(from: $0, for: input) })
    }

    /// Bound retries retain the saved processor. Recovery-only preflight never authorizes dispatch.
    /// Synchronize current required consent without recipient discovery or response-driven Auth recovery.
    func prepareBoundObservationReanalysisAuthorization(
        processor: IdentificationRecipientExpectation,
        expectedAuthUserID: UUID,
        validateAttempt: @escaping @MainActor @Sendable () throws -> Void
    ) async throws -> IdentificationDispatchAuthorization {
        guard processor != .recoveryOnly else { throw MerianError.invalidResponse }
        try await synchronizeReanalysisConsent(expectedAuthUserID: expectedAuthUserID, validateAttempt: validateAttempt)
        return try await identificationDispatchAuthorization(recipient: processor,
            expectedAuthUserID: expectedAuthUserID, validateAttempt: validateAttempt)
    }

    /// Explicit durable submission synchronizes current consent before advisory recipient discovery.
    func prepareObservationReanalysisAdmissionAuthorization(
        input: ObservationReanalysisPreflightRequest, expectedAuthUserID: UUID,
        validateAttempt: @escaping @MainActor @Sendable () throws -> Void
    ) async throws -> IdentificationDispatchAuthorization {
        try await synchronizeReanalysisConsent(expectedAuthUserID: expectedAuthUserID, validateAttempt: validateAttempt)
        return try await prepareIdentificationAuthorization(input: input, expectedAuthUserID: expectedAuthUserID, validateAttempt: validateAttempt)
    }

    private func synchronizeReanalysisConsent(expectedAuthUserID: UUID,
                                              validateAttempt: @escaping @MainActor @Sendable () throws -> Void) async throws {
        try Task.checkCancellation()
        guard try await authenticatedUserIDForInferenceRequest() == expectedAuthUserID else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        try await validateAttempt()
        #if DEBUG
        if let overridingInferenceConsentCheck {
            try await overridingInferenceConsentCheck()
        } else {
            try await ConsentManager.shared.ensureCloudConsentForInference()
        }
        #else
        try await ConsentManager.shared.ensureCloudConsentForInference()
        #endif
        try Task.checkCancellation()
        guard try await authenticatedUserIDForInferenceRequest() == expectedAuthUserID else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        try await validateAttempt()
    }

    private func prepareIdentificationAuthorization(
        expectedAuthUserID: UUID,
        validateAttempt: (@MainActor @Sendable () throws -> Void)?,
        preflight: () async throws -> Data,
        decode: (Data) throws -> IdentificationRecipientExpectation
    ) async throws -> IdentificationDispatchAuthorization {
        try Task.checkCancellation()
        guard try await authenticatedUserIDForInferenceRequest() == expectedAuthUserID else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        try Task.checkCancellation()
        try await validateAttempt?()
        let response: Data
        do {
            response = try await preflight()
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
            recipient = try decode(response)
        } catch MerianError.aiConsentRequired {
            await MainActor.run {
                let consent = ConsentManager.shared
                if consent.currentSessionUserId == expectedAuthUserID {
                    _ = try? consent.requireCurrentConsentReapprovalAfterServerRejection()
                }
            }
            throw MerianError.aiConsentRequired
        }
        return try await identificationDispatchAuthorization(recipient: recipient,
            expectedAuthUserID: expectedAuthUserID, validateAttempt: validateAttempt)
    }

    private func identificationDispatchAuthorization(
        recipient: IdentificationRecipientExpectation,
        expectedAuthUserID: UUID,
        validateAttempt: (@MainActor @Sendable () throws -> Void)?
    ) async throws -> IdentificationDispatchAuthorization {
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
