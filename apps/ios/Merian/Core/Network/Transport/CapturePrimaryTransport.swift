import Foundation

/// Exactly one private whole-observation request. This transport never enters
/// the logical retry executor, refreshes credentials after failure or changes routes.
struct CapturePrimaryTransport {
    static let requestSeconds: TimeInterval = 130
    private let baseURL: String
    private let dispatcher: AuthenticatedTransportDispatcher

    init(baseURL: String, dispatcher: AuthenticatedTransportDispatcher) {
        self.baseURL = baseURL; self.dispatcher = dispatcher
    }

    func submit(_ built: AuthenticatedInferenceRequest, plan: CaptureInitialEvidencePlan,
                validate: @escaping @MainActor @Sendable () throws -> Void,
                reserveDispatch: @escaping @MainActor @Sendable () async throws -> Void) async throws -> Data {
        try Task.checkCancellation(); try await validate()
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "identify-multimodal")
        guard built.expectedAuthUserID == plan.ownerID, built.request.url == url,
              built.request.httpMethod == "POST", let body = built.request.httpBody,
              built.request.value(forHTTPHeaderField: "Idempotency-Key") == plan.scanID.uuidString.lowercased(),
              built.identificationAuthorization?.recipient == .gemini else { throw MerianError.invalidResponse }
        var request = built.request
        request.timeoutInterval = Self.requestSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result = try await dispatcher.performCapturePrimary(.init(request: request, body: body,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: plan.ownerID,
            identificationAuthorization: built.identificationAuthorization, validateAttempt: validate),
            reserveDispatch: reserveDispatch)
        // Settlement checks intentionally do not reuse Task cancellation as a
        // dispatch decision. The retained owner still checks the exact claim.
        guard let response = result.response as? HTTPURLResponse else { throw MerianError.invalidResponse }
        guard response.statusCode == 200 else {
            throw MerianError.httpError(statusCode: response.statusCode, message: "capture_completion_unavailable")
        }
        guard response.mimeType?.lowercased() == "application/json",
              result.data.count <= OrdinaryInferenceCompletion.maximumBytes else { throw MerianError.invalidResponse }
        return result.data
    }
}
