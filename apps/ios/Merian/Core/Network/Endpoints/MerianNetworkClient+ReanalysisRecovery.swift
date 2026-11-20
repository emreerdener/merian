import Foundation

extension MerianNetworkClient {
    /// Owner-only completed-result recovery. Does not require inference consent or mutate selection.
    /// Only a verified missing target returns nil; all other denials remain failures.
    func recoverObservationAnalysis(
        _ input: ObservationReanalysisRequest,
        expectedAuthUserID: UUID,
        validateAttempt: @escaping @MainActor @Sendable () throws -> Void
    ) async throws -> Data? {
        func validate() async throws {
            try Task.checkCancellation()
            guard try await authenticatedUserIDForInferenceRequest() == expectedAuthUserID else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
            try await validateAttempt()
        }
        struct Parameters: Encodable {
            let p_request: ObservationHistoryStateRequest
            let p_reader = 10
        }
        let request = ObservationHistoryStateRequest(observation_id: input.observationID.uuidString.lowercased(),
            analysis_id: input.analysisID.uuidString.lowercased())
        try await validate()
        let bytes: Data
        do {
            bytes = try await performOwnedIdentificationRead(body: JSONEncoder().encode(Parameters(p_request: request)),
                expectedAuthUserID: expectedAuthUserID, route: .analysisState)
        } catch {
            try await validate()
            if Self.isMissingObservationAnalysis(error) { return nil }
            throw error
        }
        try await validate()
        let result: ObservationHistoryPage.Result
        do {
            let state = try ObservationHistoryState.decode(bytes, request: request, ownerID: expectedAuthUserID)
            result = try ObservationReanalysisResult.decode(state.result.bytes, matching: input)
        } catch let error as ObservationHistoryError {
            throw error
        } catch {
            // Parser/decoder failures are invalid stored state, never transport uncertainty.
            throw ObservationHistoryError.invalidSnapshot
        }
        try await validate()
        return result.bytes
    }

    private static func isMissingObservationAnalysis(_ error: Error) -> Bool {
        guard let error = error as? MerianError, case let .httpError(_, message) = error,
              message.utf8.count <= 8_192,
              let row = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any],
              Set(row.keys).isSubset(of: ["code", "message", "details", "hint"]),
              row["code"] as? String == "P0002", row["message"] as? String == "analysis_history_not_found" else { return false }
        return ["details", "hint"].allSatisfy { row[$0] == nil || row[$0] is NSNull || row[$0] is String }
    }
}

/// Fixed reader-10 endpoint; does not expose arbitrary RPC or mutation access.
struct ObservationReanalysisStatusTransport {
    let baseURL: String
    let dispatcher: AuthenticatedTransportDispatcher

    func read(_ input: ObservationAnalysisExecutionLookup, ownerID: UUID,
              validateAttempt: @escaping @MainActor @Sendable () throws -> Void) async throws -> ObservationAnalysisExecutionStatus {
        try Task.checkCancellation()
        try await validateAttempt()
        guard let base = SecureTransportPolicy.httpsURL(from: baseURL) else { throw MerianError.invalidURL }
        let body = try JSONSerialization.data(withJSONObject: ["p_request": input.object(), "p_reader": 10])
        var request = AuthenticatedRequestExecutor.Request(
            url: base.appendingPathComponent("rest/v1/rpc/get_owned_observation_analysis_execution"), method: "POST", body: body,
            timeoutInterval: 5, idempotencyKey: nil, allowsTransientTransportRetry: false, allowsUnauthorizedSessionRecovery: false,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: ownerID, allowsRouteUnavailableRetry: false)
        request.validateAttempt = validateAttempt
        let (data, _) = try await AuthenticatedRequestExecutor.live(using: dispatcher).execute(request)
        try Task.checkCancellation()
        try await validateAttempt()
        return try ObservationAnalysisExecutionStatus(data: data, request: input, ownerID: ownerID)
    }
}

/// Fixed retirement mutation. Its caller must first persist the exact operation and claim.
struct ObservationAnalysisRetirementTransport {
    let baseURL: String
    let dispatcher: AuthenticatedTransportDispatcher

    func retire(_ input: ObservationAnalysisRetirementRequest, ownerID: UUID,
                validateAttempt: @escaping @MainActor @Sendable () throws -> Void,
                validateResponse: @escaping @MainActor @Sendable () throws -> Void) async throws -> ObservationAnalysisRetirementReceipt {
        try Task.checkCancellation()
        try await validateAttempt()
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "retire-observation-analysis")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "POST"; request.httpBody = input.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("3", forHTTPHeaderField: "X-Merian-Entitlement-Protocol")
        let result = try await dispatcher.performAnalysisRetirement(.init(request: request, body: input.body,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: ownerID, validateAttempt: validateAttempt))
        guard let response = result.response as? HTTPURLResponse else { throw MerianError.invalidResponse }
        guard response.statusCode == 200 else {
            throw MerianError.httpError(statusCode: response.statusCode, message: "analysis_history_unavailable")
        }
        let receipt = try ObservationAnalysisRetirementReceipt(data: result.data, request: input)
        // Dispatch cancellation must not erase a known same-claim answer.
        try await validateResponse()
        return receipt
    }
}
