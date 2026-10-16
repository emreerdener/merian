import Foundation

/// One fixed potentially-dispatching endpoint. Recovery claims cannot enter this boundary.
struct ObservationVideoAnalysisTransport {
    static let requestSeconds: TimeInterval = 130
    private let baseURL: String
    private let dispatcher: AuthenticatedTransportDispatcher
    init(baseURL: String, dispatcher: AuthenticatedTransportDispatcher) {
        self.baseURL = baseURL; self.dispatcher = dispatcher
    }

    func submit(_ permit: ObservationVideoExecutionStore.DispatchPermit, authorization: IdentificationDispatchAuthorization,
                validateAttempt: @escaping @MainActor @Sendable () throws -> Void,
                validateResponse: @escaping @MainActor @Sendable () throws -> Void) async throws -> ObservationAnalysisReceipt {
        try Task.checkCancellation()
        guard authorization.recipient == .gemini else { throw MerianError.aiConsentRequired }
        let work = permit.snapshot.work
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "analyze-observation-video")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.requestSeconds)
        request.httpMethod = "POST"; request.httpBody = work.request.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("3", forHTTPHeaderField: "X-Merian-Entitlement-Protocol")
        request.setValue(String(authorization.identificationProtocol), forHTTPHeaderField: IdentificationDispatchAuthorization.protocolHeader)
        request.setValue(authorization.recipient.rawValue, forHTTPHeaderField: IdentificationRecipientExpectation.header)
        // Bypass the logical retry executor entirely; dispatcher retains its Auth lease through I/O.
        let result = try await dispatcher.performVideoAnalysis(.init(request: request, body: work.request.body,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: work.preparation.identity.ownerID,
            identificationAuthorization: authorization, validateAttempt: validateAttempt))
        guard let response = result.response as? HTTPURLResponse else { throw MerianError.invalidResponse }
        guard response.statusCode == 200 || response.statusCode == 202 else {
            throw MerianError.httpError(statusCode: response.statusCode, message: "analysis_history_unavailable")
        }
        guard response.mimeType?.lowercased() == "application/json" else { throw MerianError.invalidResponse }
        let receipt = try ObservationAnalysisReceipt.decode(result.data, videoRequest: work.request)
        let terminal = receipt.state == .complete || receipt.state == .failedTerminal
        guard response.statusCode == (terminal ? 200 : 202) else { throw MerianError.invalidResponse }
        // A validated answer survives dispatch cancellation; settlement still checks the original scope.
        try await validateResponse()
        return receipt
    }
}
