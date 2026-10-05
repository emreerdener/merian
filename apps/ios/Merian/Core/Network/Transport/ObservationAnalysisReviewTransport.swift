import Foundation

/// Closed mutation transport; never extends the read-only admission RPC capability.
struct ObservationAnalysisReviewTransport {
    private let baseURL: String
    private let dispatcher: AuthenticatedTransportDispatcher
    init(baseURL: String, dispatcher: AuthenticatedTransportDispatcher) {
        self.baseURL = baseURL; self.dispatcher = dispatcher
    }
    func submit(_ request: ObservationAnalysisReviewRequest, expectedAuthUserID: UUID,
                validateAttempt: @escaping @MainActor @Sendable () throws -> Void) async throws -> Data {
        guard let base = SecureTransportPolicy.httpsURL(from: baseURL) else {
            throw MerianError.invalidURL
        }
        let payload = try ObservationAnalysisReviewWire.object(request.encoded(), limit: 2048)
        let body: Data
        let url: URL
        if request.decision.isConfirmation {
            body = try request.encoded()
            url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "confirm-observation-analysis")
        } else {
            body = try JSONSerialization.data(withJSONObject: ["p_request": payload, "p_reader": 9])
            url = base.appendingPathComponent("rest/v1/rpc/review_owned_observation_analysis")
        }
        var transportRequest = AuthenticatedRequestExecutor.Request(
            url: url, method: "POST", body: body, timeoutInterval: 30, idempotencyKey: nil,
            allowsTransientTransportRetry: false, allowsUnauthorizedSessionRecovery: false,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: expectedAuthUserID,
            allowsRouteUnavailableRetry: false)
        transportRequest.validateAttempt = validateAttempt
        let (data, _) = try await AuthenticatedRequestExecutor.live(using: dispatcher).execute(transportRequest)
        return data
    }
}
