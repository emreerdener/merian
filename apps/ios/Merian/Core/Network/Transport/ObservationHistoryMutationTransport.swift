import Foundation

/// Closed history mutations share authentication, never an arbitrary URL or payload capability.
struct ObservationHistoryMutationTransport {
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
            body = try JSONSerialization.data(withJSONObject: ["p_request": payload, "p_reader": 10])
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

    func confirmationUndo(_ lookup: ObservationConfirmationUndoLookup, ownerID: UUID,
                          validateAttempt: @escaping @MainActor @Sendable () throws -> Void) async throws -> ObservationConfirmationUndoReply {
        guard let base = SecureTransportPolicy.httpsURL(from: baseURL) else { throw MerianError.invalidURL }
        let body = try JSONSerialization.data(withJSONObject: ["p_request": lookup.object(), "p_reader": 10])
        var request = AuthenticatedRequestExecutor.Request(
            url: base.appendingPathComponent("rest/v1/rpc/get_owned_observation_confirmation_undo"), method: "POST", body: body,
            timeoutInterval: 5, idempotencyKey: nil, allowsTransientTransportRetry: false, allowsUnauthorizedSessionRecovery: false,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: ownerID, allowsRouteUnavailableRetry: false)
        request.validateAttempt = validateAttempt
        let (data, _) = try await AuthenticatedRequestExecutor.live(using: dispatcher).execute(request)
        return try ObservationConfirmationUndoReply(data: data, request: lookup)
    }

    func rejectionUndo(_ lookup: ObservationRejectionUndoLookup, ownerID: UUID,
                       validateAttempt: @escaping @MainActor @Sendable () throws -> Void) async throws -> ObservationRejectionUndoReply {
        guard let base = SecureTransportPolicy.httpsURL(from: baseURL) else { throw MerianError.invalidURL }
        let body = try JSONSerialization.data(withJSONObject: ["p_request": lookup.object(), "p_reader": 10])
        var request = AuthenticatedRequestExecutor.Request(
            url: base.appendingPathComponent("rest/v1/rpc/get_owned_observation_rejection_undo"), method: "POST", body: body,
            timeoutInterval: 5, idempotencyKey: nil, allowsTransientTransportRetry: false, allowsUnauthorizedSessionRecovery: false,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: ownerID, allowsRouteUnavailableRetry: false)
        request.validateAttempt = validateAttempt
        let (data, _) = try await AuthenticatedRequestExecutor.live(using: dispatcher).execute(request)
        return try ObservationRejectionUndoReply(data: data, request: lookup)
    }

    /// Every call may dispatch; the durable caller must already own the exact request claim.
    func submit(_ request: ProtectedInsightChatRequest, expectedAuthUserID: UUID,
                claimExpiresAt: Date,
                validateAttempt: @escaping @MainActor @Sendable () throws -> Void,
                validateResponse: @escaping @MainActor @Sendable () throws -> Void) async throws -> ProtectedInsightChatReply {
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "insight-chat")
        var wire = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                              timeoutInterval: ProtectedInsightChatBudget.requestSeconds)
        wire.httpMethod = "POST"
        wire.setValue("application/json", forHTTPHeaderField: "Content-Type")
        wire.setValue("application/json", forHTTPHeaderField: "Accept")
        wire.setValue("3", forHTTPHeaderField: "X-Merian-Entitlement-Protocol")
        wire.httpBody = try request.encoded()
        let result = try await dispatcher.performProtectedInsightChat(
            .init(request: wire, body: wire.httpBody, onRequestBodySent: nil,
                  authTransitionOwner: nil, expectedAuthUserID: expectedAuthUserID, validateAttempt: validateAttempt),
            claimExpiresAt: claimExpiresAt)
        try await validateResponse()
        guard let response = result.response as? HTTPURLResponse else { throw MerianError.invalidResponse }
        guard response.statusCode == 200 else {
            throw MerianError.httpError(statusCode: response.statusCode, message: "Protected chat did not complete.")
        }
        guard response.mimeType?.lowercased() == "application/json" else { throw MerianError.invalidResponse }
        return try ProtectedInsightChatReply(data: result.data, request: request)
    }
}

/// Admission is checked after Auth, preserving persistence time within the original claim.
enum ProtectedInsightChatBudget {
    static let requestSeconds: TimeInterval = 145
    static let receiptReserve: TimeInterval = 15
    static let dispatchMargin: TimeInterval = 2
    static func requireDispatch(claimExpiresAt: Date, now: Date = Date()) throws {
        let remaining = claimExpiresAt.timeIntervalSince(now)
        guard remaining.isFinite, remaining >= requestSeconds + receiptReserve + dispatchMargin else {
            throw URLError(.timedOut)
        }
    }
}
