import Foundation

/// One pinned, account-bound attempt. The durable media owner supplies bytes,
/// dispatch/settlement fences and any preceding receipt. No automatic retry.
struct CaptureStageTransport {
    static let requestSeconds: TimeInterval = 130
    private let baseURL: String
    private let dispatcher: AuthenticatedTransportDispatcher

    init(baseURL: String, dispatcher: AuthenticatedTransportDispatcher) {
        self.baseURL = baseURL; self.dispatcher = dispatcher
    }

    func upload(_ wire: CaptureStageWireRequest, previous: CaptureStageReceipt? = nil,
                validateAttempt: @escaping @MainActor @Sendable () throws -> Void,
                validateResponse: @escaping @MainActor @Sendable () throws -> Void) async throws -> CaptureStageReceipt {
        try Task.checkCancellation()
        try previous?.requirePlan(wire.plan)
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "upload-capture-stage")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.requestSeconds)
        request.httpMethod = "POST"; request.httpBody = wire.body
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result = try await dispatcher.performCaptureStageUpload(.init(request: request, body: wire.body,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: wire.plan.ownerID, validateAttempt: validateAttempt))
        guard let response = result.response as? HTTPURLResponse else { throw MerianError.invalidResponse }
        guard response.statusCode == 200 else {
            throw MerianError.httpError(statusCode: response.statusCode, message: "analysis_history_unavailable")
        }
        guard response.mimeType?.lowercased() == "application/json" else { throw MerianError.invalidResponse }
        let receipt = try CaptureStageReceipt(data: result.data, wire: wire, previous: previous)
        try await validateResponse()
        return receipt
    }
}
